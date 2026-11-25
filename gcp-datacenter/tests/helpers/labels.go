package helpers

// RequiredLabelKeys son las cinco etiquetas obligatorias del contrato (§4.3).
var RequiredLabelKeys = []string{"env", "app", "owner", "cost_center", "managed_by"}

// RunLabelKey marca cada recurso con el ID de la ejecución; la limpieza y la búsqueda de
// huérfanos (Cloud Asset) filtran por esta etiqueta.
const RunLabelKey = "terratest_run"

// TestEnvLabel es el valor de la etiqueta env de lo que crean las pruebas de integración: no es
// dev, qa ni prod, así que scripts/destroy-orphans.py y una búsqueda por env=dev no confunden
// un resto de prueba con un recurso de un entorno real. policies/required_labels.rego solo exige
// que la llave exista, y los módulos solo validan las llaves y managed_by (la variable
// environment de cada fixture sigue en dev, que es lo que validan los módulos).
const TestEnvLabel = "test"

// RequiredLabels devuelve el mapa de etiquetas que pasan las pruebas a los módulos: las cinco
// obligatorias con valores válidos (minúsculas, ADR 0016) y la del ID de la ejecución.
func RequiredLabels(env string, run Run) map[string]string {
	return map[string]string{
		"env":         env,
		"app":         "terratest",
		"owner":       "plataforma",
		"cost_center": "terratest",
		"managed_by":  "terraform",
		RunLabelKey:   run.ID,
	}
}
