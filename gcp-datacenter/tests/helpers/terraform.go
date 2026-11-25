package helpers

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

// GCPRetryableErrors son errores transitorios conocidos de la API de GCP: propagación de APIs
// recién habilitadas, de IAM y de agentes de servicio, y operaciones concurrentes sobre la
// misma red. Se suman a terraform.DefaultRetryableTerraformErrors.
var GCPRetryableErrors = map[string]string{
	`(?s)Error 403: .*has not been used in project .* before or it is disabled`: "API recién habilitada; se reintenta",
	`(?s)SERVICE_DISABLED`:                                                                   "API recién habilitada; se reintenta",
	`(?s)Error 400: .*Service account .* does not exist`:                                     "cuenta de servicio recién creada; propagación de IAM",
	`(?s)Error 400: .*Invalid service account`:                                               "cuenta de servicio recién creada; propagación de IAM",
	`(?s)Permission .*cloudkms.cryptoKeyVersions.useToEncrypt.* denied`:                      "permiso de KMS del agente de servicio todavía sin propagar",
	`(?s)(CMEK|KMS).*(permission|PERMISSION_DENIED)`:                                         "permiso de KMS del agente de servicio todavía sin propagar",
	`(?s)Error 409: .*operation .* in progress`:                                              "otra operación sobre el mismo recurso sigue en curso",
	`(?s)Error 400: .*The resource .* is not ready`:                                          "recurso todavía no listo",
	`(?s)Cannot modify allocated ranges in CreateConnection`:                                 "conexión de Private Service Access en curso",
	`(?s)Error waiting for .*: timeout while waiting for state`:                              "espera de operación de GCP agotada",
	`(?s)googleapi: Error 503`:                                                               "API de GCP no disponible momentáneamente",
	`(?s)googleapi: Error 429`:                                                               "cuota de solicitudes; se reintenta",
	`(?s)Error 412: .*Precondition`:                                                          "condición previa (etag) cambió; se reintenta",
	`(?s)Error 400: .*Peering operation in progress`:                                         "operación de peering en curso",
	`(?s)Error 400: .*There is a peering operation in progress on the local or peer network`: "operación de peering en curso",
}

// RepoRoot devuelve la carpeta gcp-datacenter/. Las pruebas corren con el directorio de su
// paquete como directorio actual (tests/integration o tests/e2e); se sube hasta encontrar la
// carpeta que contiene modules/, stages/ y tests/.
func RepoRoot(t testing.TB) string {
	t.Helper()
	dir, err := os.Getwd()
	if err != nil {
		t.Fatalf("no se pudo leer el directorio actual: %v", err)
	}
	for {
		if isDir(filepath.Join(dir, "modules")) && isDir(filepath.Join(dir, "stages")) && isDir(filepath.Join(dir, "tests")) {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			t.Fatalf("no se encontró la raíz gcp-datacenter/ subiendo desde el directorio actual")
		}
		dir = parent
	}
}

func isDir(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.IsDir()
}

// BaseOptions arma opciones de Terraform para dir con los errores reintentables de GCP, sin
// color y con las variables dadas.
func BaseOptions(t testing.TB, dir string, vars map[string]any) *terraform.Options {
	t.Helper()
	opts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: dir,
		Vars:         vars,
		NoColor:      true,
	})
	for k, v := range GCPRetryableErrors {
		opts.RetryableTerraformErrors[k] = v
	}
	opts.MaxRetries = 5
	opts.TimeBetweenRetries = 30 * time.Second
	return opts
}

// FixtureOptions copia gcp-datacenter/ a una carpeta temporal (para que las pruebas en
// paralelo no compartan .terraform ni estado) y devuelve opciones apuntando a
// tests/fixtures/<fixture> dentro de la copia. Los fixtures llaman a los módulos con rutas
// relativas (../../../modules/<m>), que siguen valiendo en la copia.
func FixtureOptions(t testing.TB, fixture string, vars map[string]any) *terraform.Options {
	t.Helper()
	root := RepoRoot(t)
	dir := test_structure.CopyTerraformFolderToTemp(t, root, filepath.Join("tests", "fixtures", filepath.FromSlash(fixture)))
	return BaseOptions(t, dir, vars)
}

// DestroyOnCleanup registra un destroy de opts con t.Cleanup. Se usa para lo que debe
// sobrevivir a los defer de la prueba (el proyecto efímero se destruye al final). El contexto
// de t ya está cancelado cuando corren las funciones de Cleanup, así que se usa uno nuevo.
func DestroyOnCleanup(t testing.TB, opts *terraform.Options) {
	t.Helper()
	t.Cleanup(func() {
		if _, err := terraform.DestroyContextE(t, context.Background(), opts); err != nil {
			t.Errorf("destroy de %s falló; revisar huérfanos a mano: %v", opts.TerraformDir, err)
		}
	})
}

// StateRemove saca direcciones del estado (terraform state rm). Se usa antes del destroy para
// los recursos con prevent_destroy (llaves de KMS del módulo kms), que GCP no permite borrar.
func StateRemove(t testing.TB, ctx context.Context, opts *terraform.Options, addresses ...string) {
	t.Helper()
	args := append([]string{"state", "rm"}, addresses...)
	out, err := terraform.RunTerraformCommandContextE(t, ctx, opts, args...)
	if err == nil {
		return
	}
	// Si el apply falló antes de crear el recurso, no hay nada que sacar.
	if strings.Contains(out, "No matching objects found") || strings.Contains(err.Error(), "No matching objects found") {
		t.Logf("terraform state rm %v: no estaban en el estado", addresses)
		return
	}
	t.Errorf("terraform state rm %v falló: %v", addresses, err)
}
