// Package integration contiene las pruebas de integración de los módulos (contrato §9.2):
// cada prueba crea lo que necesita en un proyecto efímero, aplica un fixture de
// tests/fixtures/<módulo>/ que llama al módulo con entradas de forma real, comprueba las
// exigencias del módulo (§8) en las salidas y en la API de GCP, y destruye todo al final.
//
// Estado al 21 nov 2026: escritas y compiladas, nunca ejecutadas (no hay acceso a GCP).
package integration

import (
	"testing"

	"gcp-datacenter/tests/helpers"
)

// APIs que casi todos los fixtures necesitan.
var baseAPIs = []string{
	"cloudresourcemanager.googleapis.com",
	"serviceusage.googleapis.com",
	"iam.googleapis.com",
	"cloudkms.googleapis.com",
}

// moduleTest prepara una prueba de módulo: la marca como paralela, la omite si no hay con qué
// obtener un proyecto, crea los identificadores de la ejecución y el proyecto con las APIs
// dadas (más baseAPIs). El proyecto se destruye con t.Cleanup al final de la prueba.
func moduleTest(t *testing.T, module string, apis ...string) (helpers.Run, helpers.TestProject) {
	t.Helper()
	t.Parallel()
	helpers.RequireProjectEnv(t)
	run := helpers.NewRun(module)
	project := helpers.NewTestProject(t, run, append(append([]string{}, baseAPIs...), apis...))
	t.Logf("ejecución %s: prefijo %s, proyecto %s (efímero: %v)", run.ID, run.Prefix, project.ID, project.Ephemeral)
	return run, project
}

// fixtureVars arma las variables de un fixture. Terratest las pasa con -var y Terraform
// rechaza una variable no declarada, así que cada prueba nombra solo las que su fixture
// declara: project_id, project_number, prefix, region, dr_region y labels salen de aquí; las
// demás se agregan en extra.
func fixtureVars(run helpers.Run, project helpers.TestProject, names []string, extra map[string]any) map[string]any {
	all := map[string]any{
		"project_id":     project.ID,
		"project_number": project.Number,
		"prefix":         run.Prefix,
		"region":         helpers.Region(),
		"dr_region":      helpers.DRRegion(),
		"labels":         helpers.RequiredLabels("dev", run),
	}
	vars := make(map[string]any, len(names)+len(extra))
	for _, n := range names {
		vars[n] = all[n]
	}
	for k, v := range extra {
		vars[k] = v
	}
	return vars
}

// Conjuntos de variables más comunes.
var (
	varsPPRL  = []string{"project_id", "prefix", "region", "labels"}
	varsPNPRL = []string{"project_id", "project_number", "prefix", "region", "labels"}
)
