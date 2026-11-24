package e2e

import (
	"encoding/json"
	"strings"
	"testing"
)

// TestSQLStoppedError prueba sin GCP la detección de una instancia de Cloud SQL detenida por el
// apagado fuera de horario (ADR 0028) con respuestas de `gcloud sql instances describe
// --format=json` escritas a mano, solo con campos de la referencia v1 de DatabaseInstance
// (name, state, settings.activationPolicy, ipAddresses[].type/ipAddress). No tiene compuerta:
// corre en `go test -run TestSQLStoppedError ./e2e/`.
func TestSQLStoppedError(t *testing.T) {
	cases := []struct {
		name    string
		json    string
		stopped bool
	}{
		{
			name: "encendida",
			json: `{"name":"bnt-dev-app-pg-mx","state":"RUNNABLE",
				"settings":{"activationPolicy":"ALWAYS"},
				"ipAddresses":[{"type":"PRIVATE","ipAddress":"10.20.0.3"}]}`,
		},
		{
			// Detenida: state sigue en RUNNABLE y conserva la IP privada.
			name: "detenida",
			json: `{"name":"bnt-dev-app-pg-mx","state":"RUNNABLE",
				"settings":{"activationPolicy":"NEVER"},
				"ipAddresses":[{"type":"PRIVATE","ipAddress":"10.20.0.3"}]}`,
			stopped: true,
		},
		{
			// Sin settings (respuesta incompleta): no se inventa una detención; la falta de IP
			// la reporta sqlPrivateIP.
			name: "sin_settings",
			json: `{"name":"bnt-dev-app-pg-mx","state":"RUNNABLE"}`,
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			var inst map[string]any
			if err := json.Unmarshal([]byte(c.json), &inst); err != nil {
				t.Fatal(err)
			}
			err := sqlStoppedError(inst)
			if c.stopped != (err != nil) {
				t.Fatalf("detenida = %v, error = %v", c.stopped, err)
			}
			if err == nil {
				return
			}
			// El mensaje nombra la instancia, la causa y las salidas que tiene quien lo lee.
			for _, want := range []string{"bnt-dev-app-pg-mx", "ADR 0028", "sql-primary-start", "Re-run failed jobs", "docs/pipeline.md"} {
				if !strings.Contains(err.Error(), want) {
					t.Errorf("el mensaje no menciona %q: %v", want, err)
				}
			}
		})
	}
}
