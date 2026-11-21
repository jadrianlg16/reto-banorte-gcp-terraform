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
	expect    string   // "REACHABLE", "NOT_REACHABLE" o "ROUTED" (sin descarte por ruta)
	rationale string
}

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

// buildConnectivityChecks arma las pruebas que la configuración desplegada permite expresar.
// Lo que exige una VM, DNS público o tráfico real queda como paso manual (tests/README.md).
func buildConnectivityChecks(t *testing.T, ctx context.Context, runs map[string]*stageRun, runID string) []connectivityCheck {
	t.Helper()
	var checks []connectivityCheck

	hub := runs["3-networks"]
	devNet := runs["3-networks/envs/dev"]
	devWork := runs["5-workloads/envs/dev"]
	if hub == nil || devNet == nil {
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

	// 1) dev → Cloud SQL por IP privada (PSA).
	if devWork != nil {
		if conn, _ := terraform.OutputContextE(t, ctx, devWork.opts, "sql_instance_connection_name"); conn != "" {
			parts := strings.Split(conn, ":")
			if len(parts) == 3 {
				inst, err := helpers.GcloudObjectE(t, ctx, "sql", "instances", "describe", parts[2], "--project="+parts[0])
				ip := ""
				if err == nil {
					for _, a := range helpers.PathList(inst, "ipAddresses") {
						if helpers.PathString(a, "type") == "PRIVATE" {
							ip = helpers.PathString(a, "ipAddress")
						}
					}
				}
				if ip != "" {
					checks = append(checks, connectivityCheck{
						name:    "e2e-" + runID + "-dev-sql",
						project: devHost,
						args: append(append([]string{}, srcArgs...),
							"--destination-ip-address="+ip, "--destination-port=5432", "--protocol=TCP"),
						expect:    "REACHABLE",
						rationale: "las cargas de dev alcanzan Cloud SQL por su IP privada (PSA)",
					})
				}
			}
		}
	}

	// 2) Internet → balanceador externo de dev en 443.
	if devWork != nil {
		if ip, _ := terraform.OutputContextE(t, ctx, devWork.opts, "lb_ip_address"); ip != "" {
			checks = append(checks, connectivityCheck{
				name:    "e2e-" + runID + "-internet-lb",
				project: devHost,
				// Origen público de documentación (RFC 5737): el análisis no envía tráfico.
				args:      []string{"--source-ip-address=203.0.113.10", "--destination-ip-address=" + ip, "--destination-port=443", "--protocol=TCP"},
				expect:    "REACHABLE",
				rationale: "el balanceador HTTPS global de dev es alcanzable desde Internet en 443",
			})
		}
	}

	// 3) dev → on-premises (VPC onprem-sim por la HA VPN del hub). El firewall de onprem-sim
	// puede descartar el paquete; lo que se exige es que la ruta exista (pendiente 6 de §12).
	if sim, _ := terraform.OutputContextE(t, ctx, hub.opts, "onprem_sim_network_name"); sim != "" {
		hubProject := terraform.OutputContext(t, ctx, hub.opts, "hub_project_id")
		onpremIP := helpers.Getenv("TEST_E2E_ONPREM_IP", "192.168.0.10")
		checks = append(checks, connectivityCheck{
			name:    "e2e-" + runID + "-dev-onprem",
			project: devHost,
			args: append(append([]string{}, srcArgs...),
				"--destination-ip-address="+onpremIP, "--destination-port=22", "--protocol=TCP",
				"--destination-network=projects/"+hubProject+"/global/networks/"+sim,
				"--destination-project="+hubProject),
			expect:    "ROUTED",
			rationale: "las rutas BGP del hub llegan al spoke por el peering (sin descarte por ruta)",
		})
	}

	// 4) dev → prod: sin peering entre spokes (ADR 0003), no debe ser alcanzable.
	if prodNet := runs["3-networks/envs/prod"]; prodNet != nil {
		dst, err := appSourceIP(t, ctx, prodNet)
		if err == nil {
			prodHost := terraform.OutputContext(t, ctx, prodNet.opts, "host_project_id")
			checks = append(checks, connectivityCheck{
				name:    "e2e-" + runID + "-dev-prod",
				project: devHost,
				args: append(append([]string{}, srcArgs...),
					"--destination-ip-address="+dst, "--destination-port=22", "--protocol=TCP",
					"--destination-network="+terraform.OutputContext(t, ctx, prodNet.opts, "network_self_link"),
					"--destination-project="+prodHost),
				expect:    "NOT_REACHABLE",
				rationale: "los entornos están aislados por la red: no hay peering entre spokes (ADR 0003)",
			})
		}
	}
	return checks
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

	got := helpers.PathString(result, "reachabilityDetails.result")
	var drops []string
	for _, trace := range helpers.PathList(result, "reachabilityDetails.traces") {
		for _, step := range helpers.PathList(trace, "steps") {
			if cause := helpers.PathString(step, "drop.cause"); cause != "" {
				drops = append(drops, cause)
			}
		}
	}
	t.Logf("%s: %s (descartes: %v) — %s", c.name, got, drops, c.rationale)

	switch c.expect {
	case "REACHABLE":
		if got != "REACHABLE" {
			t.Errorf("%s: se esperaba REACHABLE y dio %s (%v): %s", c.name, got, drops, c.rationale)
		}
	case "NOT_REACHABLE":
		if got == "REACHABLE" {
			t.Errorf("%s: no debía ser alcanzable: %s", c.name, c.rationale)
		}
	case "ROUTED":
		for _, d := range drops {
			if strings.Contains(d, "ROUTE") {
				t.Errorf("%s: descarte por ruta (%s): %s", c.name, d, c.rationale)
			}
		}
	}
}
