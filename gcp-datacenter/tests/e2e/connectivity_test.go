package e2e

import (
	"context"
	"fmt"
	"net/netip"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/terraform"

	"gcp-datacenter/tests/helpers"
)

// connectivityCheck es una prueba de Network Intelligence Center (Connectivity Tests). Es un
// análisis de la configuración (rutas, firewall, peering, VPN): no envía tráfico ni necesita VM.
type connectivityCheck struct {
	name      string
	project   string   // proyecto donde se crea la prueba
	args      []string // origen y destino para gcloud network-management connectivity-tests create
	expect    string   // expectReachable, expectNotReachable o expectRouted
	rationale string
}

// Resultados esperados de una prueba de conectividad.
const (
	expectReachable    = "REACHABLE"     // result REACHABLE
	expectNotReachable = "NOT_REACHABLE" // result UNREACHABLE
	expectRouted       = "ROUTED"        // result definido y ningún descarte por ruta
)

// hostInCIDR devuelve la n-ésima dirección de un rango (n = 10 queda dentro de cualquier /28).
func hostInCIDR(cidr string, n int) (string, error) {
	p, err := netip.ParsePrefix(cidr)
	if err != nil {
		return "", err
	}
	a := p.Masked().Addr()
	for i := 0; i < n; i++ {
		a = a.Next()
	}
	if !p.Contains(a) {
		return "", fmt.Errorf("%s no tiene %d direcciones", cidr, n)
	}
	return a.String(), nil
}

// appSourceIP devuelve una IP de la subred app de un spoke (salida subnets de 3-networks/envs).
func appSourceIP(t *testing.T, ctx context.Context, spoke *stageRun) (string, error) {
	subnets := terraform.OutputMapOfObjectsContext(t, ctx, spoke.opts, "subnets")
	app, ok := subnets["app"].(map[string]any)
	if !ok {
		return "", fmt.Errorf("%s: sin subred app", spoke.Key)
	}
	return hostInCIDR(helpers.PathString(app, "cidr"), 10)
}

// optionalOutput lee una salida de texto que puede ser null a propósito (recurso
// deshabilitado). Devuelve ("", false, nil) con null y un error si la salida no existe o no se
// pudo leer: un error nunca debe confundirse con "deshabilitado".
func optionalOutput(t *testing.T, ctx context.Context, opts *terraform.Options, key string) (string, bool, error) {
	var v any
	if err := terraform.OutputStructContextE(t, ctx, opts, key, &v); err != nil {
		return "", false, fmt.Errorf("salida %s: %w", key, err)
	}
	if v == nil {
		return "", false, nil
	}
	s, ok := v.(string)
	if !ok || s == "" {
		return "", false, fmt.Errorf("salida %s: se esperaba texto y llegó %v", key, v)
	}
	return s, true, nil
}

// sqlPrivateIP devuelve la IP privada (PSA) de la instancia de un nombre de conexión
// <proyecto>:<región>:<instancia>.
func sqlPrivateIP(t *testing.T, ctx context.Context, conn string) (string, error) {
	parts := strings.Split(conn, ":")
	if len(parts) != 3 {
		return "", fmt.Errorf("nombre de conexión de Cloud SQL inesperado: %q", conn)
	}
	inst, err := helpers.GcloudObjectE(t, ctx, "sql", "instances", "describe", parts[2], "--project="+parts[0])
	if err != nil {
		return "", fmt.Errorf("gcloud sql instances describe %s: %w", parts[2], err)
	}
	for _, a := range helpers.PathList(inst, "ipAddresses") {
		if helpers.PathString(a, "type") == "PRIVATE" {
			if ip := helpers.PathString(a, "ipAddress"); ip != "" {
				return ip, nil
			}
		}
	}
	return "", fmt.Errorf("la instancia %s no tiene IP privada", parts[2])
}

// buildConnectivityChecks arma las pruebas que la configuración desplegada permite expresar.
// Lo que exige una VM, DNS público o tráfico real queda como paso manual (tests/README.md).
// Una salida en null por un recurso deshabilitado omite su prueba (queda en el registro); un
// error al leer una salida o al describir un recurso habilitado falla la prueba.
func buildConnectivityChecks(t *testing.T, ctx context.Context, runs map[string]*stageRun, runID string) []connectivityCheck {
	t.Helper()
	var checks []connectivityCheck

	hub := runs["3-networks"]
	devNet := runs["3-networks/envs/dev"]
	devWork := runs["5-workloads/envs/dev"]
	if hub == nil || devNet == nil {
		t.Errorf("faltan las raíces 3-networks o 3-networks/envs/dev: no hay pruebas de conectividad")
		return nil
	}
	devHost := terraform.OutputContext(t, ctx, devNet.opts, "host_project_id")
	devNetwork := terraform.OutputContext(t, ctx, devNet.opts, "network_self_link")
	src, err := appSourceIP(t, ctx, devNet)
	if err != nil {
		t.Errorf("no se pudo elegir IP de origen en dev: %v", err)
		return nil
	}
	srcArgs := []string{"--source-ip-address=" + src, "--source-network=" + devNetwork, "--source-project=" + devHost}

	if devWork != nil {
		// 1) dev → Cloud SQL por IP privada (PSA). 5-workloads siempre crea la instancia.
		conn, ok, err := optionalOutput(t, ctx, devWork.opts, "sql_instance_connection_name")
		switch {
		case err != nil:
			t.Errorf("dev → Cloud SQL: %v", err)
		case !ok:
			t.Errorf("dev → Cloud SQL: sql_instance_connection_name es null y 5-workloads siempre crea la instancia")
		default:
			if ip, err := sqlPrivateIP(t, ctx, conn); err != nil {
				t.Errorf("dev → Cloud SQL: %v", err)
			} else {
				checks = append(checks, connectivityCheck{
					name:    "e2e-" + runID + "-dev-sql",
					project: devHost,
					args: append(append([]string{}, srcArgs...),
						"--destination-ip-address="+ip, "--destination-port=5432", "--protocol=TCP"),
					expect:    expectReachable,
					rationale: "las cargas de dev alcanzan Cloud SQL por su IP privada (PSA)",
				})
			}
		}

		// 2) Internet → balanceador externo de dev en 443 (null si no hay backend habilitado).
		ip, ok, err := optionalOutput(t, ctx, devWork.opts, "lb_ip_address")
		switch {
		case err != nil:
			t.Errorf("Internet → balanceador: %v", err)
		case !ok:
			t.Logf("Internet → balanceador: omitida, lb_ip_address es null (ningún backend habilitado)")
		default:
			checks = append(checks, connectivityCheck{
				name:    "e2e-" + runID + "-internet-lb",
				project: devHost,
				// Origen público de documentación (RFC 5737): el análisis no envía tráfico.
				args:      []string{"--source-ip-address=203.0.113.10", "--destination-ip-address=" + ip, "--destination-port=443", "--protocol=TCP"},
				expect:    expectReachable,
				rationale: "el balanceador HTTPS global de dev es alcanzable desde Internet en 443",
			})
		}
	}

	// 3) dev → on-premises (VPC onprem-sim por la HA VPN del hub). El firewall de onprem-sim
	// puede descartar el paquete; lo que se exige es que la ruta exista (pendiente 6 de §12).
	sim, ok, err := optionalOutput(t, ctx, hub.opts, "onprem_sim_network_name")
	switch {
	case err != nil:
		t.Errorf("dev → on-premises: %v", err)
	case !ok:
		t.Logf("dev → on-premises: omitida, onprem_sim_network_name es null (simulate_onprem = false)")
	default:
		hubProject := terraform.OutputContext(t, ctx, hub.opts, "hub_project_id")
		onpremIP := helpers.Getenv("TEST_E2E_ONPREM_IP", "192.168.0.10")
		checks = append(checks, connectivityCheck{
			name:    "e2e-" + runID + "-dev-onprem",
			project: devHost,
			args: append(append([]string{}, srcArgs...),
				"--destination-ip-address="+onpremIP, "--destination-port=22", "--protocol=TCP",
				"--destination-network=projects/"+hubProject+"/global/networks/"+sim,
				"--destination-project="+hubProject),
			expect:    expectRouted,
			rationale: "las rutas BGP del hub llegan al spoke por el peering (sin descarte por ruta)",
		})
	}

	// 4) dev → prod: sin peering entre spokes (ADR 0003), no debe ser alcanzable.
	if prodNet := runs["3-networks/envs/prod"]; prodNet != nil {
		if dst, err := appSourceIP(t, ctx, prodNet); err != nil {
			t.Errorf("dev → prod: no se pudo elegir IP de destino en prod: %v", err)
		} else {
			prodHost := terraform.OutputContext(t, ctx, prodNet.opts, "host_project_id")
			checks = append(checks, connectivityCheck{
				name:    "e2e-" + runID + "-dev-prod",
				project: devHost,
				args: append(append([]string{}, srcArgs...),
					"--destination-ip-address="+dst, "--destination-port=22", "--protocol=TCP",
					"--destination-network="+terraform.OutputContext(t, ctx, prodNet.opts, "network_self_link"),
					"--destination-project="+prodHost),
				expect:    expectNotReachable,
				rationale: "los entornos están aislados por la red: no hay peering entre spokes (ADR 0003)",
			})
		}
	}
	return checks
}

// connectivitySummary es lo que evaluateConnectivity extrae del resultado de la API.
type connectivitySummary struct {
	result string
	traces int
	drops  []string // causas de los pasos drop
	aborts []string // causas de los pasos abort (análisis incompleto)
}

func summarizeConnectivity(result map[string]any) connectivitySummary {
	s := connectivitySummary{result: helpers.PathString(result, "reachabilityDetails.result")}
	for _, trace := range helpers.PathList(result, "reachabilityDetails.traces") {
		s.traces++
		for _, step := range helpers.PathList(trace, "steps") {
			if cause := helpers.PathString(step, "drop.cause"); cause != "" {
				s.drops = append(s.drops, cause)
			}
			if _, isAbort := helpers.Path(step, "abort"); isAbort || helpers.PathString(step, "state") == "ABORT" {
				cause := helpers.PathString(step, "abort.cause")
				if cause == "" {
					cause = "ABORT"
				}
				s.aborts = append(s.aborts, cause)
			}
		}
	}
	return s
}

// evaluateConnectivity compara el resultado de `connectivity-tests describe` con lo esperado.
// Exige un resultado definido: UNDETERMINED, AMBIGUOUS o vacío fallan siempre, igual que
// cualquier paso abort en una traza (el análisis no terminó y no prueba nada).
func evaluateConnectivity(expect string, result map[string]any) error {
	s := summarizeConnectivity(result)
	if len(s.aborts) > 0 {
		return fmt.Errorf("análisis abortado (%s): el resultado %q no prueba nada", strings.Join(s.aborts, ", "), s.result)
	}
	if s.result != "REACHABLE" && s.result != "UNREACHABLE" {
		return fmt.Errorf("resultado no definido %q: se exige REACHABLE o UNREACHABLE", s.result)
	}
	switch expect {
	case expectReachable:
		if s.result != "REACHABLE" {
			return fmt.Errorf("se esperaba REACHABLE y dio %s (descartes: %v)", s.result, s.drops)
		}
	case expectNotReachable:
		if s.result != "UNREACHABLE" {
			return fmt.Errorf("se esperaba UNREACHABLE y dio %s", s.result)
		}
	case expectRouted:
		if s.traces == 0 {
			return fmt.Errorf("resultado %s sin trazas: no se puede comprobar la ruta", s.result)
		}
		if s.result == "UNREACHABLE" && len(s.drops) == 0 {
			return fmt.Errorf("UNREACHABLE sin paso drop: no se sabe si el descarte es por ruta")
		}
		for _, d := range s.drops {
			if strings.Contains(d, "ROUTE") {
				return fmt.Errorf("descarte por ruta (%s)", d)
			}
		}
	default:
		return fmt.Errorf("expectativa desconocida %q", expect)
	}
	return nil
}

// runConnectivityCheck crea la prueba, espera el resultado, lo compara con lo esperado y la
// borra.
func runConnectivityCheck(t *testing.T, ctx context.Context, c connectivityCheck) {
	t.Helper()
	project := "--project=" + c.project
	create := append([]string{"network-management", "connectivity-tests", "create", c.name, project, "--async"}, c.args...)
	if _, err := helpers.GcloudE(t, ctx, create...); err != nil {
		t.Errorf("%s: no se pudo crear la prueba de conectividad: %v", c.name, err)
		return
	}
	defer func() {
		if _, err := helpers.GcloudE(t, context.Background(), "network-management", "connectivity-tests", "delete", c.name, project); err != nil {
			t.Logf("%s: no se pudo borrar la prueba de conectividad: %v", c.name, err)
		}
	}()

	var result map[string]any
	helpers.WaitFor(t, ctx, "resultado de "+c.name, 5*time.Minute, 15*time.Second, func() error {
		r, err := helpers.GcloudObjectE(t, ctx, "network-management", "connectivity-tests", "describe", c.name, project)
		if err != nil {
			return err
		}
		if helpers.PathString(r, "reachabilityDetails.result") == "" {
			return fmt.Errorf("%s todavía sin resultado", c.name)
		}
		result = r
		return nil
	})

	s := summarizeConnectivity(result)
	t.Logf("%s: %s (trazas: %d, descartes: %v, abortos: %v) — %s", c.name, s.result, s.traces, s.drops, s.aborts, c.rationale)
	if err := evaluateConnectivity(c.expect, result); err != nil {
		t.Errorf("%s: %v: %s", c.name, err, c.rationale)
	}
}
