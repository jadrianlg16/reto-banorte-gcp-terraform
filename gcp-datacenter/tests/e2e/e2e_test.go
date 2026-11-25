// Package e2e contiene la prueba de extremo a extremo (contrato §9.2, ADR 0029): aplica las
// etapas 0 → 3 en el proyecto único de la landing zone, mide el tiempo contra el objetivo de 90
// minutos, exige un segundo plan sin cambios en cada raíz, corre las pruebas de conectividad que
// la configuración permite expresar, destruye las cargas de dev (y su spoke, si se pide) y busca
// huérfanos de dev con Cloud Asset y scripts/destroy-orphans.py, como destroy.yml. El simulacro
// de DR no se automatiza: es el runbook docs/runbooks/04-conmutacion-a-dr.md.
//
// Estado al 24 nov 2026: escrita y compilada, nunca ejecutada (no hay acceso a GCP).
package e2e

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"

	"gcp-datacenter/tests/helpers"
)

// deployTarget es el objetivo de tiempo del despliegue 0 → 3 (§12, pendiente 10).
const deployTarget = 90 * time.Minute

// TestEndToEnd aplica la landing zone completa. Compuerta: TEST_E2E=true, más TEST_E2E_CONFIG.
// Cuesta dinero real y tarda más de una hora: ver tests/README.md.
func TestEndToEnd(t *testing.T) {
	helpers.RequireGate(t, envE2E, "la prueba de extremo a extremo aplica 0 → 3 en el proyecto de la landing zone")
	env := helpers.RequireEnv(t, envConfig)
	ctx := t.Context()

	r := &e2eRun{
		t:      t,
		root:   helpers.RepoRoot(t),
		cfg:    loadConfig(t, env[envConfig]),
		runID:  strings.ToLower(helpers.Getenv(envRunID, random.UniqueID())),
		varDir: t.TempDir(),
	}
	envs := environments(t)
	t.Logf("corrida %s; entornos %v; archivos de variables y estado local de respaldo en %s", r.runID, envs, r.varDir)

	// Las raíces aplicadas, por llave, en orden de aplicación.
	runs := map[string]*stageRun{}
	var applied []*stageRun

	// Destroy de dev en orden inverso y búsqueda de huérfanos: corre aunque algo falle antes.
	defer func() {
		if helpers.IsTrue(envSkipDestroy) {
			t.Logf("%s=true: dev queda desplegado", envSkipDestroy)
			return
		}
		destroyDev(t, applied, helpers.IsTrue(envDestroyNetwork))
		checkNoOrphans(t, r, applied)
	}()

	// --- 1. Aplicar 0 → 3 y medir el tiempo ----------------------------------------------
	start := time.Now()
	boot := r.bootstrap(ctx)
	runs[boot.Key] = boot
	applied = append(applied, boot)
	r.accounts = terraform.OutputMapContext(t, ctx, boot.opts, "stage_service_accounts")
	r.projectID = terraform.OutputContext(t, ctx, boot.opts, "project_id")
	r.projectNumber = terraform.OutputContext(t, ctx, boot.opts, "project_number")

	for _, s := range stagesInOrder(envs) {
		sr := r.apply(ctx, s)
		runs[s.Key] = sr
		applied = append(applied, sr)
	}
	total := time.Since(start)
	t.Logf("TIEMPO 0 → 3: %s (objetivo %s; entornos %v)", total.Round(time.Second), deployTarget, envs)
	if total > deployTarget {
		msg := fmt.Sprintf("el despliegue 0 → 3 tardó %s, más que el objetivo de %s", total.Round(time.Second), deployTarget)
		if helpers.IsTrue(envEnforceDuration) {
			t.Error(msg)
		} else {
			t.Logf("AVISO: %s (%s no es true: no falla)", msg, envEnforceDuration)
		}
	}

	// --- 2. Segundo plan sin cambios en todas las raíces (§12, pendiente 11) ---------------
	for _, sr := range applied {
		if err := planIsClean(t, ctx, sr); err != nil {
			t.Error(err)
		} else {
			t.Logf("segundo plan de %s: sin cambios", sr.Key)
		}
	}

	// --- 3. Conectividad -----------------------------------------------------------------
	if strings.EqualFold(helpers.Getenv(envConnectivityTest, "true"), "false") {
		t.Logf("%s=false: se omiten las pruebas de conectividad", envConnectivityTest)
	} else {
		checks := buildConnectivityChecks(t, ctx, runs, r.runID)
		if len(checks) == 0 {
			t.Log("no hay pruebas de conectividad expresables con lo desplegado")
		}
		for _, c := range checks {
			runConnectivityCheck(t, ctx, c)
		}
	}
	t.Log("pasos manuales (ver tests/README.md): SSH por IAP a una VM, HTTPS por el dominio con " +
		"certificado ACTIVE, resolución DNS desde on-premises y simulacro de DR " +
		"(docs/runbooks/04-conmutacion-a-dr.md)")
}

// destroyDev destruye las raíces de dev en orden inverso al de aplicación: siempre
// 3-workloads/envs/dev y el spoke 2-networks/envs/dev solo con withNetwork (como la entrada
// incluir_red de destroy.yml: la conexión de PSA puede tardar días en poder borrarse después
// de borrar Cloud SQL, ADR 0029 §8). Las compartidas (0, 1-base y el hub) y los demás entornos no
// se destruyen: guardan el estado, las llaves con prevent_destroy y el bloqueo de logs; su
// desmontaje es manual.
func destroyDev(t *testing.T, applied []*stageRun, withNetwork bool) {
	t.Helper()
	ctx := context.Background()
	for i := len(applied) - 1; i >= 0; i-- {
		sr := applied[i]
		if sr.Env != "dev" {
			continue
		}
		if sr.Key == spokeKey("dev") && !withNetwork {
			t.Logf("== %s se conserva (%s no es true)", sr.Key, envDestroyNetwork)
			continue
		}
		t.Logf("== destroy %s", sr.Key)
		if _, err := terraform.DestroyContextE(t, ctx, sr.opts); err != nil {
			t.Errorf("destroy de %s falló: %v", sr.Key, err)
		}
	}
}

// checkNoOrphans busca huérfanos de dev en el proyecto como destroy.yml: lista el proyecto con
// Cloud Asset y corre scripts/destroy-orphans.py con los estados de todas las raíces aplicadas
// (lo que todavía administra un estado, como el spoke conservado o 1-base, no es huérfano). El
// índice de Cloud Asset tarda en reflejar los borrados: se reintenta hasta 30 minutos.
// Necesita python3 (o la ruta de PYTHON).
// VERIFICAR-EN-APPLY: que la cuenta que corre la prueba tenga cloudasset.assets.searchAllResources
// en el proyecto.
func checkNoOrphans(t *testing.T, r *e2eRun, applied []*stageRun) {
	t.Helper()
	ctx := context.Background()
	if r.projectID == "" || r.projectNumber == "" {
		t.Errorf("no se buscan huérfanos: no se leyeron project_id y project_number de 0-bootstrap")
		return
	}
	prefix, _ := r.cfg.varsFor(workloadsKey("dev"), r.runID, nil)["prefix"].(string)
	if prefix == "" {
		t.Errorf("no se buscan huérfanos: config sin prefix para %s", workloadsKey("dev"))
		return
	}
	dir := filepath.Join(r.varDir, "orphans")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Errorf("no se pudo crear %s: %v", dir, err)
		return
	}
	assets := filepath.Join(dir, "assets.json")
	args := []string{filepath.Join(r.root, "scripts", "destroy-orphans.py"), "--env", "dev", "--prefix", prefix,
		"--project", r.projectID, "--project-number", r.projectNumber, "--assets", assets}
	for _, sr := range applied {
		state, err := terraform.RunTerraformCommandAndGetStdoutContextE(t, ctx, sr.opts, "state", "pull")
		if err != nil {
			t.Errorf("no se pudo leer el estado de %s: %v", sr.Key, err)
			return
		}
		path := filepath.Join(dir, strings.ReplaceAll(sr.Key, "/", "_")+".tfstate")
		if err := os.WriteFile(path, []byte(state), 0o600); err != nil {
			t.Errorf("no se pudo escribir %s: %v", path, err)
			return
		}
		args = append(args, "--state", path)
	}

	var last string
	err := retryUntil(ctx, 30*time.Minute, time.Minute, func() error {
		out, err := helpers.GcloudE(t, ctx, "asset", "search-all-resources", "--scope=projects/"+r.projectID, "--format=json")
		if err != nil {
			return err
		}
		if err := os.WriteFile(assets, []byte(out), 0o600); err != nil {
			return err
		}
		last, err = shell.RunCommandContextAndGetStdOutE(t, ctx, &shell.Command{
			Command: helpers.Getenv("PYTHON", "python3"),
			Args:    args,
			Logger:  logger.Discard,
		})
		return err
	})
	if err != nil {
		t.Errorf("huérfanos de dev en %s tras el destroy: %v\n%s", r.projectID, err, last)
		return
	}
	t.Logf("sin huérfanos de dev en %s:\n%s", r.projectID, last)
}

// retryUntil reintenta f cada interval hasta que devuelva nil o pase timeout.
func retryUntil(ctx context.Context, timeout, interval time.Duration, f func() error) error {
	deadline := time.Now().Add(timeout)
	for {
		err := f()
		if err == nil || time.Now().After(deadline) {
			return err
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(interval):
		}
	}
}
