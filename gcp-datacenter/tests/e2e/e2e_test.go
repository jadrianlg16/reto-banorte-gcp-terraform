// Package e2e contiene la prueba de extremo a extremo (contrato §9.2): aplica las etapas
// 0 → 5 contra una organización real, mide el tiempo contra el objetivo de 90 minutos, exige un
// segundo plan sin cambios en cada raíz, corre las pruebas de conectividad que la
// configuración permite expresar, destruye dev en orden inverso y busca huérfanos con Cloud
// Asset. El simulacro de DR no se automatiza: es el runbook docs/runbooks/04-conmutacion-a-dr.md.
//
// Estado al 21 nov 2026: escrita y compilada, nunca ejecutada (no hay acceso a GCP).
package e2e

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"

	"gcp-datacenter/tests/helpers"
)

// deployTarget es el objetivo de tiempo del despliegue 0 → 5 (§12, pendiente 10).
const deployTarget = 90 * time.Minute

// TestEndToEnd aplica la landing zone completa. Compuerta: TEST_E2E=true, más TEST_E2E_CONFIG
// y TERRATEST_ORG_ID. Cuesta dinero real y tarda más de una hora: ver tests/README.md.
func TestEndToEnd(t *testing.T) {
	helpers.RequireGate(t, envE2E, "la prueba de extremo a extremo aplica 0 → 5 en una organización real")
	env := helpers.RequireEnv(t, envConfig, helpers.EnvOrgID)
	ctx := t.Context()

	r := &e2eRun{
		t:      t,
		root:   helpers.RepoRoot(t),
		cfg:    loadConfig(t, env[envConfig]),
		runID:  strings.ToLower(helpers.Getenv(envRunID, random.UniqueID())),
		varDir: t.TempDir(),
	}
	envs := environments(t)
	orgID := helpers.OrgNumber(env[helpers.EnvOrgID])
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
		destroyDev(t, applied)
		checkNoOrphans(t, orgID, r.runID)
	}()

	// --- 1. Aplicar 0 → 5 y medir el tiempo ----------------------------------------------
	start := time.Now()
	boot := r.bootstrap(ctx)
	runs[boot.Key] = boot
	applied = append(applied, boot)
	r.accounts = terraform.OutputMapContext(t, ctx, boot.opts, "stage_service_accounts")

	for _, s := range stagesInOrder(envs) {
		sr := r.apply(ctx, s)
		runs[s.Key] = sr
		applied = append(applied, sr)
	}
	total := time.Since(start)
	t.Logf("TIEMPO 0 → 5: %s (objetivo %s; entornos %v)", total.Round(time.Second), deployTarget, envs)
	if total > deployTarget {
		msg := fmt.Sprintf("el despliegue 0 → 5 tardó %s, más que el objetivo de %s", total.Round(time.Second), deployTarget)
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

// destroyDev destruye las raíces de dev en orden inverso al de aplicación (5 → 4 → 3). Las
// compartidas (0, 1, 2 y el hub) y los demás entornos no se destruyen: guardan el estado, las
// llaves con prevent_destroy y el bloqueo de logs; su desmontaje es manual.
func destroyDev(t *testing.T, applied []*stageRun) {
	t.Helper()
	ctx := context.Background()
	for i := len(applied) - 1; i >= 0; i-- {
		sr := applied[i]
		if sr.Env != "dev" {
			continue
		}
		t.Logf("== destroy %s", sr.Key)
		if _, err := terraform.DestroyContextE(t, ctx, sr.opts); err != nil {
			t.Errorf("destroy de %s falló: %v", sr.Key, err)
		}
	}
}

// checkNoOrphans busca con Cloud Asset recursos de la organización con las etiquetas de la
// corrida y env=dev. El índice de Cloud Asset tarda en reflejar los borrados: se reintenta
// hasta 30 minutos. Los proyectos borrados quedan 30 días en DELETE_REQUESTED y no cuentan.
// VERIFICAR-EN-APPLY: que la cuenta que corre la prueba tenga cloudasset.assets.searchAllResources
// en la organización y la API cloudasset.googleapis.com en su proyecto de cuota.
func checkNoOrphans(t *testing.T, orgID, runID string) {
	t.Helper()
	ctx := context.Background()
	query := fmt.Sprintf("labels.%s=%s AND labels.env=dev", runLabelKey, runID)
	var last []string
	err := retryUntil(ctx, 30*time.Minute, time.Minute, func() error {
		res, err := helpers.GcloudListE(t, ctx, "asset", "search-all-resources",
			"--scope=organizations/"+orgID, "--query="+query)
		if err != nil {
			return err
		}
		last = last[:0]
		for _, a := range res {
			state := helpers.PathString(a, "state")
			if state == "DELETE_REQUESTED" || state == "DELETED" || state == "DELETE_IN_PROGRESS" {
				continue
			}
			last = append(last, helpers.PathString(a, "assetType")+" "+helpers.PathString(a, "name"))
		}
		if len(last) > 0 {
			return fmt.Errorf("%d recursos de dev siguen vivos", len(last))
		}
		return nil
	})
	if err != nil {
		t.Errorf("huérfanos tras el destroy de dev (consulta %q): %v\n%s", query, err, strings.Join(last, "\n"))
		return
	}
	t.Logf("sin huérfanos de dev con %s", query)
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
