package integration

import (
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gcp-datacenter/tests/helpers"
)

// TestDNS comprueba el módulo dns (§8): zonas privadas visibles solo desde la VPC, zona de
// googleapis.com hacia el VIP restringido, reenvío condicional a on-premises por ruta privada
// y política de servidor con reenvío entrante (con sus IP en la subred).
func TestDNS(t *testing.T) {
	run, project := moduleTest(t, "dns", "compute.googleapis.com", "dns.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "dns", fixtureVars(run, project, varsPPRL, nil))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	zones := terraform.OutputMapContext(t, ctx, opts, "zone_names")
	network := terraform.OutputContext(t, ctx, opts, "network_id")
	require.Len(t, zones, 3)

	for key, name := range zones {
		z := helpers.GcloudJSON(t, ctx, "dns", "managed-zones", "describe", name, "--project="+project.ID)
		assert.Equal(t, "private", helpers.PathString(z, "visibility"), "zona %s privada", key)
		nets := helpers.PathList(z, "privateVisibilityConfig.networks")
		require.Len(t, nets, 1, "zona %s visible desde una sola VPC", key)
		assert.True(t, strings.HasSuffix(helpers.PathString(nets[0], "networkUrl"), network), "zona %s en la VPC de la prueba", key)
		if key == "onprem" {
			targets := helpers.PathList(z, "forwardingConfig.targetNameServers")
			require.Len(t, targets, 1)
			assert.Equal(t, "192.168.0.10", helpers.PathString(targets[0], "ipv4Address"))
			assert.Equal(t, "private", helpers.PathString(targets[0], "forwardingPath"), "reenvío por ruta privada")
		}
	}

	records := helpers.GcloudJSONList(t, ctx, "dns", "record-sets", "list", "--zone="+zones["googleapis"], "--project="+project.ID)
	vip := false
	for _, r := range records {
		if helpers.PathString(r, "name") == "restricted.googleapis.com." && helpers.PathString(r, "type") == "A" {
			vip = strings.Contains(helpers.PathString(r, "rrdatas"), "199.36.153.4")
		}
	}
	assert.True(t, vip, "restricted.googleapis.com apunta al VIP restringido 199.36.153.4/30")

	policyName := terraform.OutputContext(t, ctx, opts, "policy_name")
	policy := helpers.GcloudJSON(t, ctx, "dns", "policies", "describe", policyName, "--project="+project.ID)
	assert.True(t, helpers.PathBool(policy, "enableInboundForwarding"), "reenvío entrante")

	// Las IP de reenvío entrante aparecen como direcciones DNS_RESOLVER de la subred; pueden
	// tardar en existir después del apply.
	helpers.WaitFor(t, ctx, "IP de reenvío entrante", 5*time.Minute, 30*time.Second, func() error {
		addrs, err := helpers.GcloudListE(t, ctx, "compute", "addresses", "list", "--project="+project.ID, "--filter=purpose=DNS_RESOLVER")
		if err != nil {
			return err
		}
		if len(addrs) == 0 {
			return errNotYet("sin direcciones DNS_RESOLVER")
		}
		return nil
	})
	t.Logf("inbound_forwarder_ips (salida del módulo): %v", terraform.OutputListContext(t, ctx, opts, "inbound_forwarder_ips"))
}

// errNotYet es el error de una condición que todavía no se cumple (para helpers.WaitFor).
type errNotYet string

func (e errNotYet) Error() string { return string(e) }
