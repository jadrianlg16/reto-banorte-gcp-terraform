package e2e

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"gcp-datacenter/tests/helpers"
)

// Variables de entorno propias de la prueba de extremo a extremo.
const (
	envE2E              = "TEST_E2E"                  // "true" habilita la prueba
	envConfig           = "TEST_E2E_CONFIG"           // ruta al JSON de variables (ver config.example.json)
	envEnvs             = "TEST_E2E_ENVS"             // entornos a aplicar, separados por coma (por defecto "dev")
	envEnforceDuration  = "TEST_E2E_ENFORCE_DURATION" // "true": falla si 0 → 3 tarda más de 90 min
	envStateBucket      = "TEST_E2E_STATE_BUCKET"     // etapa 0 ya arrancada: se salta el estado local
	envImpersonate      = "TEST_E2E_IMPERSONATE"      // "true": etapas 1 a 3 con la cuenta de su raíz
	envSkipDestroy      = "TEST_E2E_SKIP_DESTROY"     // "true": no destruye dev al final
	envDestroyNetwork   = "TEST_E2E_DESTROY_NETWORK"  // "true": destruye también el spoke de dev (incluir_red)
	envRunID            = "TEST_E2E_RUN_ID"           // ID de la corrida (etiqueta e2e_run); por defecto aleatorio
	envConnectivityTest = "TEST_E2E_CONNECTIVITY"     // "false" omite las pruebas de conectividad
)

// runLabelKey es la etiqueta que la prueba agrega a todas las raíces, para reconocer en el
// proyecto lo que creó cada corrida.
const runLabelKey = "e2e_run"

// e2eConfig es el JSON de TEST_E2E_CONFIG. common se mezcla en el archivo de variables de cada
// raíz (las variables que una raíz no declara solo producen una advertencia de Terraform);
// stages tiene, por raíz (ruta bajo stages/, con barras: "2-networks/envs/dev"), sus variables
// propias, que pisan a common. Lo que la prueba conoce por las salidas de otras etapas
// (state_bucket) y los ajustes de destroy de dev los agrega ella.
type e2eConfig struct {
	Common map[string]any            `json:"common"`
	Stages map[string]map[string]any `json:"stages"`
}

func loadConfig(t *testing.T, path string) e2eConfig {
	t.Helper()
	b, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		t.Fatalf("no se pudo leer %s=%s: %v", envConfig, path, err)
	}
	var cfg e2eConfig
	if err := json.Unmarshal(b, &cfg); err != nil {
		t.Fatalf("%s no es JSON válido: %v", path, err)
	}
	if cfg.Common == nil {
		cfg.Common = map[string]any{}
	}
	if cfg.Stages == nil {
		cfg.Stages = map[string]map[string]any{}
	}
	return cfg
}

// environments devuelve los entornos pedidos; dev siempre va (es el que se destruye y revisa).
func environments(t *testing.T) []string {
	t.Helper()
	raw := helpers.Getenv(envEnvs, "dev")
	seen := map[string]bool{}
	var out []string
	for _, e := range strings.Split(raw, ",") {
		e = strings.TrimSpace(strings.ToLower(e))
		if e == "" || seen[e] {
			continue
		}
		if e != "dev" && e != "qa" && e != "prod" {
			t.Fatalf("%s: entorno %q no válido (dev, qa, prod)", envEnvs, e)
		}
		seen[e] = true
		out = append(out, e)
	}
	if !seen["dev"] {
		out = append([]string{"dev"}, out...)
	}
	return out
}

// varsFor arma las variables de una raíz: common, luego las de la raíz, luego lo inyectado.
// Las etiquetas se mezclan en vez de reemplazarse, y siempre llevan e2e_run.
func (c e2eConfig) varsFor(key, runID string, injected map[string]any) map[string]any {
	vars := map[string]any{}
	for k, v := range c.Common {
		vars[k] = v
	}
	for k, v := range c.Stages[key] {
		vars[k] = v
	}
	for k, v := range injected {
		vars[k] = v
	}
	labels := map[string]any{}
	for _, src := range []map[string]any{c.Common, c.Stages[key]} {
		if l, ok := src["labels"].(map[string]any); ok {
			for k, v := range l {
				labels[k] = v
			}
		}
	}
	labels[runLabelKey] = runID
	vars["labels"] = labels
	return vars
}

// writeVarFile escribe las variables de una raíz como <dir>/<raíz>.tfvars.json y devuelve la
// ruta absoluta. Se pasan con -var-file (no con -var) para que una variable común que la raíz
// no declara sea advertencia y no error.
func writeVarFile(t *testing.T, dir, key string, vars map[string]any) string {
	t.Helper()
	name := strings.ReplaceAll(key, "/", "_") + ".tfvars.json"
	path := filepath.Join(dir, name)
	b, err := json.MarshalIndent(vars, "", "  ")
	if err != nil {
		t.Fatalf("no se pudieron serializar las variables de %s: %v", key, err)
	}
	if err := os.WriteFile(path, b, 0o600); err != nil {
		t.Fatalf("no se pudo escribir %s: %v", path, err)
	}
	return path
}
