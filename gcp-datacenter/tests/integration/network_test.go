package integration

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gcp-datacenter/tests/helpers"
)

// assertPrivateSubnet comprueba en la API lo que §8 exige a toda subred de los módulos de red:
// Private Google Access y flow logs con el muestreo por defecto de los módulos (1.0: CIS 3.8,
// ADR 0027; los fixtures no lo cambian).
func assertPrivateSubnet(t *testing.T, project, region, name string) map[string]any {
	t.Helper()
	s := helpers.GcloudJSON(t, t.Context(), "compute", "networks", "subnets", "describe", name,
		"--project="+project, "--region="+region)
	assert.True(t, helpers.PathBool(s, "privateIpGoogleAccess"), "%s: Private Google Access", name)
	assert.True(t, helpers.PathBool(s, "logConfig.enable"), "%s: flow logs", name)
	assert.Equal(t, "1", helpers.PathString(s, "logConfig.flowSampling"), "%s: muestreo de flow logs", name)
	return s
}

// TestNetworkHub comprueba el módulo network-hub (§8): VPC personalizada, subredes privadas
// con PGA y flow logs al 100 %, y un Cloud Router por región con el ASN del hub.
func TestNetworkHub(t *testing.T) {
	run, project := moduleTest(t, "network-hub", "compute.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "network-hub", fixtureVars(run, project,
		[]string{"project_id", "prefix", "region", "dr_region"}, nil))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	network := terraform.OutputContext(t, ctx, opts, "network_name")
	n := helpers.GcloudJSON(t, ctx, "compute", "networks", "describe", network, "--project="+project.ID)
	assert.False(t, helpers.PathBool(n, "autoCreateSubnetworks"), "VPC en modo personalizado")

	subnets := terraform.OutputMapOfObjectsContext(t, ctx, opts, "subnets")
	require.Len(t, subnets, 2)
	for key, raw := range subnets {
		s, _ := raw.(map[string]any)
		assertPrivateSubnet(t, project.ID, helpers.LastSegment(helpers.PathString(s, "region")), helpers.PathString(s, "name"))
		t.Logf("subred %s verificada", key)
	}

	routers := terraform.OutputMapContext(t, ctx, opts, "routers")
	require.Len(t, routers, 2, "un Cloud Router por región")
	for region, name := range routers {
		r := helpers.GcloudJSON(t, ctx, "compute", "routers", "describe", name, "--project="+project.ID, "--region="+region)
		assert.Equal(t, "64514", helpers.PathString(r, "bgp.asn"), "ASN del router de %s", region)
	}
}

// TestNetworkSpoke comprueba el módulo network-spoke (§7.4 y §8): subredes de §5 con PGA y
// flow logs al 100 %, rangos secundarios pods/services, subred proxy-only, rango y conexión de PSA,
// peering en ambos sentidos (el hub exporta rutas, el spoke las importa) y Cloud NAT por
// región sin IP públicas en las VM.
func TestNetworkSpoke(t *testing.T) {
	run, project := moduleTest(t, "network-spoke", "compute.googleapis.com", "servicenetworking.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "network-spoke", fixtureVars(run, project,
		[]string{"project_id", "prefix", "region", "dr_region", "labels"}, nil))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	region := helpers.Region()
	network := terraform.OutputContext(t, ctx, opts, "network_name")
	hub := terraform.OutputContext(t, ctx, opts, "hub_network_name")
	subnets := terraform.OutputMapOfObjectsContext(t, ctx, opts, "subnets")

	for _, key := range []string{"app", "run"} {
		s, ok := subnets[key].(map[string]any)
		require.True(t, ok, "falta la subred %s", key)
		api := assertPrivateSubnet(t, project.ID, region, helpers.PathString(s, "name"))
		if key == "app" {
			names := map[string]bool{}
			for _, r := range helpers.PathList(api, "secondaryIpRanges") {
				names[helpers.PathString(r, "rangeName")] = true
			}
			assert.Len(t, names, 2, "app lleva dos rangos secundarios (pods y services)")
		}
	}

	proxy, ok := subnets["proxy"].(map[string]any)
	require.True(t, ok, "falta la subred proxy")
	p := helpers.GcloudJSON(t, ctx, "compute", "networks", "subnets", "describe", helpers.PathString(proxy, "name"),
		"--project="+project.ID, "--region="+region)
	assert.Equal(t, "REGIONAL_MANAGED_PROXY", helpers.PathString(p, "purpose"), "subred proxy-only")

	// PSA: rango reservado y conexión con servicenetworking.
	psa := terraform.OutputContext(t, ctx, opts, "psa_range_name")
	addr := helpers.GcloudJSON(t, ctx, "compute", "addresses", "describe", psa, "--global", "--project="+project.ID)
	assert.Equal(t, "VPC_PEERING", helpers.PathString(addr, "purpose"))
	conns := helpers.GcloudJSONList(t, ctx, "services", "vpc-peerings", "list", "--network="+network, "--project="+project.ID)
	assert.NotEmpty(t, conns, "conexión de Private Service Access")

	// Peering en ambos sentidos.
	spoke := helpers.GcloudJSON(t, ctx, "compute", "networks", "describe", network, "--project="+project.ID)
	assertPeering(t, spoke, hub, true, false)
	hubNet := helpers.GcloudJSON(t, ctx, "compute", "networks", "describe", hub, "--project="+project.ID)
	assertPeering(t, hubNet, network, false, true)

	// Cloud NAT por región activa.
	routers := terraform.OutputMapContext(t, ctx, opts, "routers")
	nats := terraform.OutputMapContext(t, ctx, opts, "nat_names")
	require.Contains(t, nats, region, "NAT en la región primaria")
	nat := helpers.GcloudJSON(t, ctx, "compute", "routers", "nats", "describe", nats[region],
		"--router="+routers[region], "--region="+region, "--project="+project.ID)
	assert.NotEmpty(t, helpers.PathString(nat, "name"))
}

// assertPeering busca en una red (JSON de networks describe) el peering hacia peer y comprueba
// que esté activo y con la importación/exportación de rutas personalizadas pedida.
func assertPeering(t *testing.T, network map[string]any, peer string, importCustom, exportCustom bool) {
	t.Helper()
	for _, p := range helpers.PathList(network, "peerings") {
		if helpers.LastSegment(helpers.PathString(p, "network")) != peer {
			continue
		}
		assert.Equal(t, "ACTIVE", helpers.PathString(p, "state"), "peering hacia %s", peer)
		assert.Equal(t, importCustom, helpers.PathBool(p, "importCustomRoutes"), "importCustomRoutes hacia %s", peer)
		assert.Equal(t, exportCustom, helpers.PathBool(p, "exportCustomRoutes"), "exportCustomRoutes hacia %s", peer)
		return
	}
	t.Errorf("no hay peering hacia %s", peer)
}
