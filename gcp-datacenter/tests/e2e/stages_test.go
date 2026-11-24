package e2e

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"

	"gcp-datacenter/tests/helpers"
)

// stage es una raíz de stages/ tal como la recorre la prueba.
type stage struct {
	Key     string // ruta bajo stages/ con barras, p. ej. "3-workloads/envs/dev"
	Account string // llave de stage_service_accounts ("" para 0-bootstrap)
	Env     string // dev, qa o prod; "" para las raíces compartidas
}

// Raíces del ADR 0029 §2 (rutas bajo stages/).
const (
	keyBootstrap = "0-bootstrap"
	keyBase      = "1-base"
	keyHub       = "2-networks"
)

// spokeKey y workloadsKey dan la raíz del spoke y la de las cargas de un entorno.
func spokeKey(env string) string     { return "2-networks/envs/" + env }
func workloadsKey(env string) string { return "3-workloads/envs/" + env }

// stagesInOrder devuelve las raíces 1 → 3 en el orden de apply.yml (ADR 0029 §2): 1-base, el
// hub y, por cada entorno en el orden pedido, su spoke y sus cargas. La cuenta de cada raíz es
// la llave de stage_service_accounts de 0-bootstrap (1-base, 2-networks, 2-networks/<env>,
// 3-workloads/<env>).
func stagesInOrder(envs []string) []stage {
	out := []stage{
		{Key: keyBase, Account: "1-base"},
		{Key: keyHub, Account: "2-networks"},
	}
	for _, e := range envs {
		out = append(out,
			stage{Key: spokeKey(e), Account: "2-networks/" + e, Env: e},
			stage{Key: workloadsKey(e), Account: "3-workloads/" + e, Env: e},
		)
	}
	return out
}

// stageRun guarda las opciones de Terraform de una raíz ya inicializada.
type stageRun struct {
	stage
	opts *terraform.Options
}

// e2eRun reúne el estado de la corrida.
type e2eRun struct {
	t             *testing.T
	root          string // gcp-datacenter/
	cfg           e2eConfig
	runID         string
	varDir        string
	bucket        string
	accounts      map[string]string
	projectID     string // salida project_id de 0-bootstrap: el proyecto único
	projectNumber string // salida project_number de 0-bootstrap
}

func (r *e2eRun) dir(key string) string {
	return filepath.Join(r.root, "stages", filepath.FromSlash(key))
}

// injected devuelve lo que la prueba agrega a las variables de una raíz: el bucket de estado
// y, solo en las cargas de dev, deletion_protection = false para poder destruirlas (en qa y
// prod se deja el valor por defecto, que lo impide). Ninguna raíz crea ni borra proyectos
// (ADR 0029 §1): ya no hay deletion_policy de proyectos.
func (r *e2eRun) injected(s stage) map[string]any {
	in := map[string]any{"state_bucket": r.bucket}
	if s.Env == "dev" && s.Key == workloadsKey("dev") {
		in["deletion_protection"] = false
	}
	return in
}

// options arma las opciones de una raíz usada en su lugar (sin copiarla): backend gcs con
// -backend-config bucket=… y -reconfigure (la carpeta puede tener un .terraform de
// scripts/check.sh hecho con -backend=false), variables por -var-file y, si se pide,
// suplantación de la cuenta de servicio de la etapa (VERIFICAR-EN-APPLY: que el operador
// tenga roles/iam.serviceAccountTokenCreator sobre ellas; la etapa 0 no lo da).
func (r *e2eRun) options(s stage, vars map[string]any) *terraform.Options {
	opts := helpers.BaseOptions(r.t, r.dir(s.Key), nil)
	opts.VarFiles = []string{writeVarFile(r.t, r.varDir, s.Key, vars)}
	opts.BackendConfig = map[string]any{"bucket": r.bucket}
	opts.Reconfigure = true
	opts.EnvVars = map[string]string{}
	if s.Account != "" && helpers.IsTrue(envImpersonate) {
		sa := r.accounts[s.Account]
		opts.EnvVars["GOOGLE_IMPERSONATE_SERVICE_ACCOUNT"] = sa
		opts.EnvVars["GOOGLE_BACKEND_IMPERSONATE_SERVICE_ACCOUNT"] = sa
	}
	return opts
}

// apply inicializa y aplica una raíz.
func (r *e2eRun) apply(ctx context.Context, s stage) *stageRun {
	r.t.Helper()
	opts := r.options(s, r.cfg.varsFor(s.Key, r.runID, r.injected(s)))
	r.t.Logf("== apply %s", s.Key)
	terraform.InitAndApplyContext(r.t, ctx, opts)
	return &stageRun{stage: s, opts: opts}
}

// bootstrap aplica la etapa 0 y devuelve sus opciones con el backend ya en el bucket.
//
// Con TEST_E2E_STATE_BUCKET la etapa 0 ya está arrancada: se inicializa contra ese bucket y se
// aplica (idempotente). Sin él, sigue el procedimiento de stages/0-bootstrap/README.md:
//  1. copiar backend_override.tf.example a backend_override.tf (backend local temporal);
//  2. init y apply con estado local;
//  3. borrar backend_override.tf y migrar con init -migrate-state -backend-config=bucket=…;
//  4. comprobar que el estado remoto tiene recursos y, en vez de borrar terraform.tfstate*,
//     moverlos a la carpeta temporal de la prueba (copia de respaldo fuera del repositorio).
func (r *e2eRun) bootstrap(ctx context.Context) *stageRun {
	t := r.t
	t.Helper()
	s := stage{Key: keyBootstrap}
	dir := r.dir(s.Key)
	vars := r.cfg.varsFor(s.Key, r.runID, nil)

	if b := helpers.Getenv(envStateBucket, ""); b != "" {
		r.bucket = b
		opts := r.options(s, vars)
		t.Logf("== apply 0-bootstrap (ya arrancada, bucket %s)", b)
		terraform.InitAndApplyContext(t, ctx, opts)
		return &stageRun{stage: s, opts: opts}
	}

	override := filepath.Join(dir, "backend_override.tf")
	localState := filepath.Join(dir, "terraform.tfstate")
	for _, p := range []string{override, localState} {
		if _, err := os.Stat(p); err == nil {
			t.Fatalf("%s ya existe: puede ser un arranque real en curso; la prueba no lo pisa. "+
				"Si la etapa 0 ya está arrancada, exporta %s", p, envStateBucket)
		}
	}
	copyFile(t, filepath.Join(dir, "backend_override.tf.example"), override)
	defer func() {
		if err := os.Remove(override); err != nil && !errors.Is(err, os.ErrNotExist) {
			t.Errorf("no se pudo borrar %s: %v", override, err)
		}
	}()

	local := helpers.BaseOptions(t, dir, nil)
	local.VarFiles = []string{writeVarFile(t, r.varDir, s.Key, vars)}
	local.Reconfigure = true
	t.Log("== apply 0-bootstrap con estado local (backend_override.tf)")
	terraform.InitAndApplyContext(t, ctx, local)
	r.bucket = terraform.OutputContext(t, ctx, local, "state_bucket")

	if err := os.Remove(override); err != nil {
		t.Fatalf("no se pudo borrar %s antes de migrar: %v", override, err)
	}
	remote := r.options(s, vars)
	remote.Reconfigure = false
	remote.MigrateState = true
	t.Logf("== migración del estado de 0-bootstrap al bucket %s", r.bucket)
	terraform.InitContext(t, ctx, remote)
	remote.MigrateState = false

	list, err := terraform.RunTerraformCommandContextE(t, ctx, remote, "state", "list")
	if err != nil || strings.TrimSpace(list) == "" {
		t.Fatalf("el estado remoto de 0-bootstrap está vacío tras migrar (se conserva %s): %v", localState, err)
	}
	for _, p := range []string{localState, localState + ".backup"} {
		if _, err := os.Stat(p); err == nil {
			dst := filepath.Join(r.varDir, filepath.Base(p))
			copyFile(t, p, dst)
			if err := os.Remove(p); err != nil {
				t.Errorf("no se pudo borrar %s: %v", p, err)
			}
			t.Logf("estado local de 0-bootstrap movido a %s", dst)
		}
	}
	return &stageRun{stage: s, opts: remote}
}

// planIsClean corre plan -detailed-exitcode y devuelve un error si hay cambios (2) o falla (1).
func planIsClean(t *testing.T, ctx context.Context, sr *stageRun) error {
	t.Helper()
	code, err := terraform.PlanExitCodeContextE(t, ctx, sr.opts)
	switch {
	case code == terraform.DefaultSuccessExitCode:
		return nil
	case code == terraform.TerraformPlanChangesPresentExitCode:
		return fmt.Errorf("%s: el segundo plan tiene cambios (exit 2)", sr.Key)
	default:
		return fmt.Errorf("%s: plan falló (exit %d): %v", sr.Key, code, err)
	}
}

func copyFile(t *testing.T, src, dst string) {
	t.Helper()
	in, err := os.Open(src)
	if err != nil {
		t.Fatalf("no se pudo abrir %s: %v", src, err)
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		t.Fatalf("no se pudo crear %s: %v", dst, err)
	}
	defer out.Close()
	if _, err := io.Copy(out, in); err != nil {
		t.Fatalf("no se pudo copiar %s a %s: %v", src, dst, err)
	}
}
