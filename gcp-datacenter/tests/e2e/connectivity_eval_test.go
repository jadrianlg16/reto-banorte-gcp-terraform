package e2e

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"gcp-datacenter/tests/helpers"
)

// Valores de la referencia v1 de la API de Network Management (projects.locations.global.
// connectivityTests, consultada el 23 nov 2026): Step.State, campos de Step y
// RouteInfo.NextHopType. Los fixtures solo pueden usar estos.
var (
	apiStepStates = strings.Fields(`STATE_UNSPECIFIED START_FROM_INSTANCE START_FROM_INTERNET
		START_FROM_GOOGLE_SERVICE START_FROM_PRIVATE_NETWORK START_FROM_GKE_MASTER
		START_FROM_CLOUD_SQL_INSTANCE START_FROM_GKE_POD START_FROM_REDIS_INSTANCE
		START_FROM_REDIS_CLUSTER START_FROM_CLOUD_FUNCTION START_FROM_APP_ENGINE_VERSION
		START_FROM_CLOUD_RUN_REVISION START_FROM_CLOUD_RUN_JOB START_FROM_STORAGE_BUCKET
		START_FROM_PSC_PUBLISHED_SERVICE START_FROM_SERVERLESS_NEG START_FROM_DMS_PRIVATE_CONNECTION
		START_FROM_DATASTREAM_PRIVATE_CONNECTION APPLY_INGRESS_FIREWALL_RULE APPLY_EGRESS_FIREWALL_RULE
		APPLY_ROUTE APPLY_FORWARDING_RULE ANALYZE_LOAD_BALANCER_BACKEND SPOOFING_APPROVED
		ARRIVE_AT_INSTANCE ARRIVE_AT_INTERNAL_LOAD_BALANCER ARRIVE_AT_EXTERNAL_LOAD_BALANCER
		ARRIVE_AT_HYBRID_SUBNET ARRIVE_AT_VPN_GATEWAY ARRIVE_AT_VPN_TUNNEL
		ARRIVE_AT_INTERCONNECT_ATTACHMENT ARRIVE_AT_VPC_CONNECTOR ARRIVE_AT_GKE_POD
		DIRECT_VPC_EGRESS_CONNECTION SERVERLESS_EXTERNAL_CONNECTION NGFW_PACKET_INSPECTION NAT
		SKIP_GKE_POD_IP_MASQUERADING SKIP_GKE_INGRESS_NETWORK_POLICY SKIP_GKE_EGRESS_NETWORK_POLICY
		APPLY_INGRESS_GKE_NETWORK_POLICY APPLY_EGRESS_GKE_NETWORK_POLICY PROXY_CONNECTION DELIVER DROP
		FORWARD ABORT VIEWER_PERMISSION_MISSING`)
	apiStepFields = strings.Fields(`description state causesDrop projectId instance firewall route
		endpoint googleService forwardingRule hybridSubnet vpnGateway vpnTunnel interconnectAttachment
		vpcConnector directVpcEgressConnection serverlessExternalConnection deliver forward abort drop
		loadBalancer network gkeMaster gkePod ipMasqueradingSkipped gkeNetworkPolicy
		gkeNetworkPolicySkipped cloudSqlInstance redisInstance redisCluster cloudFunction
		appEngineVersion cloudRunRevision cloudRunJob nat proxyConnection loadBalancerBackendInfo
		storageBucket serverlessNeg ngfwPacketInspection dmsPrivateConnection datastreamPrivateConnection`)
	apiNextHopTypes = strings.Fields(`NEXT_HOP_TYPE_UNSPECIFIED NEXT_HOP_IP NEXT_HOP_INSTANCE
		NEXT_HOP_NETWORK NEXT_HOP_PEERING NEXT_HOP_INTERCONNECT NEXT_HOP_VPN_TUNNEL NEXT_HOP_VPN_GATEWAY
		NEXT_HOP_INTERNET_GATEWAY NEXT_HOP_BLACKHOLE NEXT_HOP_ILB NEXT_HOP_ROUTER_APPLIANCE
		NEXT_HOP_NCC_HUB SECURE_WEB_PROXY_GATEWAY`)
)

func contains(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

// checkFixtureShapes falla si un fixture usa un estado, un campo de Step o un tipo de siguiente
// salto que no existen en la API (revisión h7: ARRIVE_AT_CLOUD_SQL_INSTANCE no existe).
func checkFixtureShapes(t *testing.T) {
	t.Helper()
	files, err := filepath.Glob(filepath.Join("testdata", "connectivity", "*.json"))
	if err != nil || len(files) == 0 {
		t.Fatalf("sin fixtures de conectividad: %v", err)
	}
	for _, f := range files {
		raw, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		var result map[string]any
		if err := json.Unmarshal(raw, &result); err != nil {
			t.Fatalf("%s: %v", f, err)
		}
		for _, trace := range helpers.PathList(result, "reachabilityDetails.traces") {
			for _, step := range helpers.PathList(trace, "steps") {
				m, _ := step.(map[string]any)
				for k := range m {
					if !contains(apiStepFields, k) {
						t.Errorf("%s: campo de Step que no existe en la API: %s", f, k)
					}
				}
				if s := helpers.PathString(step, "state"); !contains(apiStepStates, s) {
					t.Errorf("%s: Step.State que no existe en la API: %q", f, s)
				}
				if n := helpers.PathString(step, "route.nextHopType"); n != "" && !contains(apiNextHopTypes, n) {
					t.Errorf("%s: RouteInfo.NextHopType que no existe en la API: %q", f, n)
				}
			}
		}
	}
}

// TestEvaluateConnectivity prueba sin GCP la evaluación de resultados de Connectivity Tests
// con respuestas de `gcloud network-management connectivity-tests describe --format=json`
// escritas a mano en testdata/connectivity, solo con campos y valores de la referencia v1 de
// la API de Network Management (ConnectivityTest.reachabilityDetails, Trace.steps, Step.state,
// causesDrop, route/vpnTunnel/firewall/deliver/drop/abort). No tiene compuerta: corre en
// `go test -run TestEvaluateConnectivity ./e2e/`.
func TestEvaluateConnectivity(t *testing.T) {
	cases := []struct {
		fixture string
		expect  string
		ok      bool
	}{
		{"reachable", expectReachable, true},
		{"reachable", expectNotReachable, false},
		{"reachable", expectRouted, false}, // entrega por peering, sin túnel VPN
		{"unreachable_no_route", expectNotReachable, true},
		{"unreachable_no_route", expectReachable, false},
		{"unreachable_no_route", expectRouted, false},
		{"unreachable_firewall", expectRouted, true}, // túnel VPN y después descarte del firewall
		{"unreachable_firewall", expectNotReachable, true},
		{"reachable_via_vpn", expectRouted, true},
		{"reachable_via_vpn", expectReachable, true},
		// Sin ruta a on-premises aunque ninguna causa diga "ROUTE" (revisión h1).
		{"unreachable_internet_gateway", expectRouted, false},
		{"unreachable_internet_gateway", expectNotReachable, true},
		{"unreachable_vpn_routing_loop", expectRouted, false}, // después del túnel solo FIREWALL_RULE
		{"unreachable_firewall_before_vpn", expectRouted, false},
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

	checkFixtureShapes(t)

	if err := evaluateConnectivity(expectReachable, map[string]any{}); err == nil {
		t.Error("un resultado vacío debía fallar")
	}
	if err := evaluateConnectivity("OTRO", map[string]any{"reachabilityDetails": map[string]any{"result": "REACHABLE"}}); err == nil {
		t.Error("una expectativa desconocida debía fallar")
	}
}
