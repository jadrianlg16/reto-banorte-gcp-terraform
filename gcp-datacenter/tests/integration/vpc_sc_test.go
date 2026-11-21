package integration

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"

	"gcp-datacenter/tests/helpers"
)

// TestVPCSC comprueba el módulo vpc-sc (§8, ADR 0009): perímetro en dry-run con el proyecto
// de la prueba dentro, servicios restringidos (storage siempre) y regla de entrada para la
// identidad del pipeline.
// Compuerta: TEST_ALLOW_ORG=true y TEST_ACCESS_POLICY_ID (política de acceso existente).
func TestVPCSC(t *testing.T) {
	helpers.RequireOrgScope(t, "TestVPCSC")
	env := helpers.RequireEnv(t, helpers.EnvOrgID, helpers.EnvAccessPolicyID)
	run, project := moduleTest(t, "vpc-sc", "accesscontextmanager.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "vpc-sc", fixtureVars(run, project,
		[]string{"project_id", "project_number", "prefix"},
		map[string]any{
			"org_id":           helpers.OrgNumber(env[helpers.EnvOrgID]),
			"access_policy_id": env[helpers.EnvAccessPolicyID],
		}))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	assert.Equal(t, "false", terraform.OutputContext(t, ctx, opts, "enforced"), "arranca en dry-run")
	perimeter := terraform.OutputContext(t, ctx, opts, "perimeter_name")
	identity := terraform.OutputContext(t, ctx, opts, "ingress_identity")

	p := helpers.GcloudJSON(t, ctx, "access-context-manager", "perimeters", "describe", perimeter,
		"--policy="+env[helpers.EnvAccessPolicyID])
	assert.True(t, helpers.PathBool(p, "useExplicitDryRunSpec"), "dry-run explícito")
	assert.Contains(t, helpers.PathList(p, "spec.resources"), any("projects/"+project.Number), "proyecto dentro del perímetro (dry-run)")
	assert.Contains(t, helpers.PathList(p, "spec.restrictedServices"), any("storage.googleapis.com"))

	found := false
	for _, rule := range helpers.PathList(p, "spec.ingressPolicies") {
		for _, id := range helpers.PathList(rule, "ingressFrom.identities") {
			if id == any(identity) {
				found = true
			}
		}
	}
	assert.True(t, found, "regla de entrada para la identidad del pipeline")
}
