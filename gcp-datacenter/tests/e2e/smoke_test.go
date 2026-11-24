package e2e

import (
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"

	"gcp-datacenter/tests/helpers"
)

// envSmoke habilita la prueba de humo de dev.
const envSmoke = "TEST_SMOKE"

// smokeRoots son las raíces ya aplicadas cuyas salidas usa la prueba de humo de dev.
var smokeRoots = []stage{
	{Key: "3-networks"},
	{Key: "3-networks/envs/dev", Env: "dev"},
	{Key: "5-workloads/envs/dev", Env: "dev"},
}

// TestDevSmoke es la prueba de humo de dev que corre apply.yml después de aplicar dev y antes
// de qa (trabajo "dev / prueba de humo"). No aplica ni destruye nada: inicializa las raíces de
// smokeRoots contra el bucket de estado, lee sus salidas y corre las Connectivity Tests que
// la configuración de dev permite expresar (las mismas de TestEndToEnd, sin la de prod):
// dev → Cloud SQL por IP privada, Internet → balanceador de dev en 443 y dev → on-premises
// simulado. Exige al menos una. Si la instancia de Cloud SQL está detenida por el apagado fuera
// de horario (ADR 0028), la prueba dev → Cloud SQL falla con un mensaje que lo dice y explica
// cómo seguir (sqlStoppedError); no la enciende.
//
// Compuerta: TEST_SMOKE=true y TEST_E2E_STATE_BUCKET. La identidad (en CI, la cuenta
// GCP_AUDIT_SERVICE_ACCOUNT) necesita leer los prefijos de estado 3-networks/ y 5-workloads/,
// crear Connectivity Tests en el proyecto host de dev y describir la instancia de Cloud SQL.
// VERIFICAR-EN-APPLY: esos permisos (ver docs/pipeline.md §2) y que cada prueba dé lo esperado.
func TestDevSmoke(t *testing.T) {
	helpers.RequireGate(t, envSmoke, "la prueba de humo lee el estado y crea Connectivity Tests en dev")
	env := helpers.RequireEnv(t, envStateBucket)
	ctx := t.Context()
	root := helpers.RepoRoot(t)
	r := &e2eRun{t: t, root: root}
	runID := strings.ToLower(helpers.Getenv(envRunID, "smoke-"+random.UniqueID()))

	runs := map[string]*stageRun{}
	for _, s := range smokeRoots {
		opts := helpers.BaseOptions(t, r.dir(s.Key), nil)
		opts.BackendConfig = map[string]any{"bucket": env[envStateBucket]}
		opts.Reconfigure = true
		t.Logf("== init %s (solo lectura de salidas)", s.Key)
		terraform.InitContext(t, ctx, opts)
		runs[s.Key] = &stageRun{stage: s, opts: opts}
	}

	checks := buildConnectivityChecks(t, ctx, runs, runID)
	if len(checks) == 0 {
		t.Fatal("no hay pruebas de conectividad expresables con lo desplegado en dev: la prueba de humo no puede pasar vacía")
	}
	for _, c := range checks {
		runConnectivityCheck(t, ctx, c)
	}
}
