package integration

import (
	"fmt"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gcp-datacenter/tests/helpers"
)

// TestHybridConnectivity comprueba el módulo hybrid-connectivity (§7.3 y §8): HA VPN con dos
// interfaces y dos túneles (topología del SLA de 99.99 %), túneles ESTABLISHED, sesiones BGP
// arriba y anuncio personalizado de los rangos pedidos.
// Compuerta: TEST_ALLOW_EXPENSIVE=true (dos gateways HA VPN y cuatro túneles cobran por hora).
func TestHybridConnectivity(t *testing.T) {
	helpers.RequireExpensive(t, "TestHybridConnectivity")
	run, project := moduleTest(t, "hybrid", "compute.googleapis.com")
	ctx := t.Context()
	region := helpers.Region()

	opts := helpers.FixtureOptions(t, "hybrid-connectivity", fixtureVars(run, project, varsPPRL, nil))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	ips := terraform.OutputListContext(t, ctx, opts, "hub_gateway_ip_addresses")
	assert.Len(t, ips, 2, "gateway HA VPN con dos interfaces")
	tunnels := terraform.OutputMapContext(t, ctx, opts, "hub_tunnel_names")
	require.Len(t, tunnels, 2, "dos túneles")

	for _, name := range tunnels {
		helpers.WaitFor(t, ctx, "túnel "+name+" ESTABLISHED", 10*time.Minute, 30*time.Second, func() error {
			tun, err := helpers.GcloudObjectE(t, ctx, "compute", "vpn-tunnels", "describe", name, "--region="+region, "--project="+project.ID)
			if err != nil {
				return err
			}
			if s := helpers.PathString(tun, "status"); s != "ESTABLISHED" {
				return fmt.Errorf("túnel %s en %s", name, s)
			}
			return nil
		})
	}

	router := terraform.OutputContext(t, ctx, opts, "hub_router")
	helpers.WaitFor(t, ctx, "sesiones BGP arriba", 10*time.Minute, 30*time.Second, func() error {
		st, err := helpers.GcloudObjectE(t, ctx, "compute", "routers", "get-status", router, "--region="+region, "--project="+project.ID)
		if err != nil {
			return err
		}
		peers := helpers.PathList(st, "result.bgpPeerStatus")
		if len(peers) < 2 {
			return fmt.Errorf("%d sesiones BGP", len(peers))
		}
		for _, p := range peers {
			if helpers.PathString(p, "status") != "UP" {
				return fmt.Errorf("sesión %s en %s", helpers.PathString(p, "name"), helpers.PathString(p, "status"))
			}
		}
		return nil
	})

	r := helpers.GcloudJSON(t, ctx, "compute", "routers", "describe", router, "--region="+region, "--project="+project.ID)
	for _, p := range helpers.PathList(r, "bgpPeers") {
		assert.Equal(t, "CUSTOM", helpers.PathString(p, "advertiseMode"), "anuncio personalizado en %s", helpers.PathString(p, "name"))
		var ranges []string
		for _, a := range helpers.PathList(p, "advertisedIpRanges") {
			ranges = append(ranges, helpers.PathString(a, "range"))
		}
		assert.Contains(t, ranges, "35.199.192.0/19", "rango de reenvío de Cloud DNS anunciado")
	}
}
