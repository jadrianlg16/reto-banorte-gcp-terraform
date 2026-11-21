package integration

import (
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gcp-datacenter/tests/helpers"
)

// TestFirewallNetwork comprueba el módulo firewall como política de red (§7.4 y §8): una
// llave de etiqueta segura por etiqueta, con propósito GCE_FIREWALL; reglas que apuntan a los
// valores de etiqueta; denegación por defecto; y la política asociada a la VPC.
func TestFirewallNetwork(t *testing.T) {
	run, project := moduleTest(t, "firewall", "compute.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "firewall", fixtureVars(run, project,
		[]string{"project_id", "prefix", "region"}, nil))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	policyName := terraform.OutputContext(t, ctx, opts, "policy_name")
	network := terraform.OutputContext(t, ctx, opts, "network_name")
	tagValues := terraform.OutputMapContext(t, ctx, opts, "secure_tag_ids")
	tagKeys := terraform.OutputMapContext(t, ctx, opts, "secure_tag_key_ids")
	require.Len(t, tagKeys, 2, "una llave por etiqueta (lb_backend, iap_ssh)")
	require.Len(t, tagValues, 2)

	for k, keyID := range tagKeys {
		key := helpers.GcloudJSON(t, ctx, "resource-manager", "tags", "keys", "describe", keyID)
		assert.Equal(t, "GCE_FIREWALL", helpers.PathString(key, "purpose"), "propósito de la llave %s", k)
		assert.Regexp(t, `^tagValues/[0-9]+$`, tagValues[k])
	}

	policy := helpers.GcloudJSON(t, ctx, "compute", "network-firewall-policies", "describe", policyName,
		"--global", "--project="+project.ID)

	associated := false
	for _, a := range helpers.PathList(policy, "associations") {
		if strings.HasSuffix(helpers.PathString(a, "attachmentTarget"), "/networks/"+network) {
			associated = true
		}
	}
	assert.True(t, associated, "política asociada a la VPC")

	targets := map[string]bool{}
	denyIngress := false
	for _, r := range helpers.PathList(policy, "rules") {
		for _, tag := range helpers.PathList(r, "targetSecureTags") {
			targets[helpers.PathString(tag, "name")] = true
		}
		if helpers.PathString(r, "action") == "deny" && helpers.PathString(r, "direction") == "INGRESS" &&
			strings.Contains(helpers.PathString(r, "match.srcIpRanges"), "0.0.0.0/0") {
			denyIngress = true
		}
	}
	for k, v := range tagValues {
		assert.True(t, targets[v], "alguna regla apunta a la etiqueta %s", k)
	}
	assert.True(t, denyIngress, "regla de denegación por defecto de entrada")
}

// TestFirewallHierarchical comprueba el módulo firewall como política jerárquica (§7.3):
// asociada al padre (una carpeta contenedora de la prueba), sin reglas allow, con las
// verificaciones de salud, el IAP y el tráfico interno delegados con goto_next y la
// denegación por defecto.
// Compuerta: TEST_ALLOW_ORG=true.
func TestFirewallHierarchical(t *testing.T) {
	t.Parallel()
	helpers.RequireOrgScope(t, "TestFirewallHierarchical")
	parent := parentResource(t)
	run := helpers.NewRun("firewall-hier")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "firewall-hierarchical", map[string]any{
		"parent": parent,
		"prefix": run.Prefix,
	})
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	policyID := terraform.OutputContext(t, ctx, opts, "policy_id")
	container := terraform.OutputContext(t, ctx, opts, "container_id")

	policy := helpers.GcloudJSON(t, ctx, "compute", "firewall-policies", "describe", helpers.LastSegment(policyID))
	associated := false
	for _, a := range helpers.PathList(policy, "associations") {
		if helpers.PathString(a, "attachmentTarget") == container {
			associated = true
		}
	}
	assert.True(t, associated, "política asociada a %s", container)

	actions := map[string]int{}
	for _, r := range helpers.PathList(policy, "rules") {
		actions[helpers.PathString(r, "action")]++
	}
	assert.Zero(t, actions["allow"], "ninguna regla allow en la política jerárquica (§7.3)")
	assert.GreaterOrEqual(t, actions["goto_next"], 3, "verificaciones de salud, IAP y tráfico interno delegados a la política de red")
	assert.GreaterOrEqual(t, actions["deny"], 1, "denegación por defecto")
}
