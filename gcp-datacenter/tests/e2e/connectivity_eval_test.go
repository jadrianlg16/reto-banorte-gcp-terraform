package e2e

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// TestEvaluateConnectivity prueba sin GCP la evaluación de resultados de Connectivity Tests
// con respuestas de `gcloud network-management connectivity-tests describe --format=json`
// escritas a mano en testdata/connectivity (forma de la API v1: reachabilityDetails.result,
// traces[].steps[] con drop.cause o abort.cause). No tiene compuerta: corre en
// `go test -run TestEvaluateConnectivity ./e2e/`.
func TestEvaluateConnectivity(t *testing.T) {
	cases := []struct {
		fixture string
		expect  string
		ok      bool
	}{
		{"reachable", expectReachable, true},
		{"reachable", expectNotReachable, false},
		{"reachable", expectRouted, true},
		{"unreachable_no_route", expectNotReachable, true},
		{"unreachable_no_route", expectReachable, false},
		{"unreachable_no_route", expectRouted, false}, // descarte por ruta
		{"unreachable_firewall", expectRouted, true},  // la ruta existe; el firewall descarta
		{"unreachable_firewall", expectNotReachable, true},
		// Resultados no definidos: nunca pasan, se espere lo que se espere.
		{"undetermined_abort", expectNotReachable, false},
		{"undetermined_abort", expectRouted, false},
		{"undetermined_abort", expectReachable, false},
		{"ambiguous", expectNotReachable, false},
		{"ambiguous", expectRouted, false},
		{"ambiguous", expectReachable, false},
		// Un paso abort invalida el análisis aunque el resultado diga UNREACHABLE.
		{"unreachable_with_abort", expectNotReachable, false},
		{"unreachable_with_abort", expectRouted, false},
		// ROUTED necesita trazas para comprobar la ruta.
		{"unreachable_no_traces", expectRouted, false},
		{"unreachable_no_traces", expectNotReachable, true},
	}
	for _, c := range cases {
		t.Run(c.fixture+"/"+c.expect, func(t *testing.T) {
			raw, err := os.ReadFile(filepath.Join("testdata", "connectivity", c.fixture+".json"))
			if err != nil {
				t.Fatal(err)
			}
			var result map[string]any
			if err := json.Unmarshal(raw, &result); err != nil {
				t.Fatal(err)
			}
			err = evaluateConnectivity(c.expect, result)
			if c.ok && err != nil {
				t.Errorf("debía pasar y falló: %v", err)
			}
			if !c.ok && err == nil {
				t.Errorf("debía fallar y pasó")
			}
		})
	}

	if err := evaluateConnectivity(expectReachable, map[string]any{}); err == nil {
		t.Error("un resultado vacío debía fallar")
	}
	if err := evaluateConnectivity("OTRO", map[string]any{"reachabilityDetails": map[string]any{"result": "REACHABLE"}}); err == nil {
		t.Error("una expectativa desconocida debía fallar")
	}
}
