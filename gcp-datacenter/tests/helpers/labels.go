package helpers

// RequiredLabelKeys son las cinco etiquetas obligatorias del contrato (§4.3).
var RequiredLabelKeys = []string{"env", "app", "owner", "cost_center", "managed_by"}

// RunLabelKey marca cada recurso con el ID de la ejecución; la limpieza y la búsqueda de
// huérfanos (Cloud Asset) filtran por esta etiqueta.
const RunLabelKey = "terratest_run"

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
