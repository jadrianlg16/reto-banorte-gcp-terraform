package integration

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"

	"gcp-datacenter/tests/helpers"
)

// TestVPCSC comprueba el módulo vpc-sc (§8, ADR 0009 y ADR 0029 §1): perímetro common en
// dry-run alrededor del proyecto de la prueba, sobre una política de acceso que ya existe,
// servicios restringidos (storage siempre) y regla de entrada para la identidad del pipeline.
// Compuerta: TEST_ALLOW_ORG=true, TERRATEST_ORG_ID y TEST_ACCESS_POLICY_ID: VPC-SC solo existe
// con organización (la política de acceso es de la organización).
func TestVPCSC(t *testing.T) {
	helpers.RequireOrganization(t, "TestVPCSC")
	helpers.RequireOrgScope(t, "TestVPCSC")
	env := helpers.RequireEnv(t, helpers.EnvOrgID, helpers.EnvAccessPolicyID)
	run, project := moduleTest(t, "vpc-sc", "accesscontextmanager.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "vpc-sc", fixtureVars(run, project,
		[]string{"project_id", "project_number", "prefix"},
		map[string]any{"access_policy_id": env[helpers.EnvAccessPolicyID]}))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	assert.Equal(t, "false", terraform.OutputContext(t, ctx, opts, "enforced"), "arranca en dry-run")
	assert.Equal(t, run.Prefix+"_common_sec_perimeter", terraform.OutputContext(t, ctx, opts, "perimeter_short_name"))
	perimeter := terraform.OutputContext(t, ctx, opts, "perimeter_name")
	identity := terraform.OutputContext(t, ctx, opts, "ingress_identity")

	p := helpers.GcloudJSON(t, ctx, "access-context-manager", "perimeters", "describe", perimeter,
		"--policy="+env[helpers.EnvAccessPolicyID])
	assert.True(t, helpers.PathBool(p, "useExplicitDryRunSpec"), "dry-run explícito")
	assert.Contains(t, helpers.PathList(p, "spec.resources"), any("projects/"+project.Number), "proyecto dentro del perímetro (dry-run)")
	assert.Contains(t, helpers.PathList(p, "spec.restrictedServices"), any("storage.googleapis.com"))
	assert.Empty(t, helpers.PathList(p, "status.resources"), "en dry-run la configuración forzada queda vacía")

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
