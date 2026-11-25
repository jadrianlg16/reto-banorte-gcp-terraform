package integration

import (
	"sort"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gcp-datacenter/tests/helpers"
)

// Las siete políticas que el módulo org aplica siempre al proyecto (ADR 0029 §1). Con
// directory_customer_id se suma iam.allowedPolicyMemberDomains.
var orgConstraints = []string{
	"compute.requireShieldedVm",
	"compute.vmExternalIpAccess",
	"gcp.resourceLocations",
	"iam.disableServiceAccountKeyCreation",
	"sql.restrictPublicIp",
	"storage.publicAccessPrevention",
	"storage.uniformBucketLevelAccess",
}

// domainConstraint es la política que solo existe con TEST_DIRECTORY_CUSTOMER_ID.
const domainConstraint = "iam.allowedPolicyMemberDomains"

// TestOrg comprueba el módulo org (§8, ADR 0029 §1): las políticas de organización aplicadas
// al proyecto de la prueba (padre projects/<id>) con su valor.
// Compuerta: TEST_ALLOW_ORG=true y TERRATEST_ORG_ID. Las políticas solo tienen sentido con el
// proyecto dentro de una organización (sin ella, 0-bootstrap no llama al módulo; que la API las
// rechace sin organización es HYPOTHESIS), y la cuenta de la prueba necesita
// roles/orgpolicy.policyAdmin, que solo se da en la organización. TEST_DIRECTORY_CUSTOMER_ID es
// opcional: con él también se prueba iam.allowedPolicyMemberDomains.
// No corre en paralelo: las políticas valen para todo el proyecto mientras dura la prueba
// (ubicaciones, IP externas, VM blindadas) y en el proyecto único afectarían a las demás.
func TestOrg(t *testing.T) {
	helpers.RequireOrganization(t, "TestOrg")
	helpers.RequireOrgScope(t, "TestOrg")
	helpers.RequireEnv(t, helpers.EnvOrgID)
	run, project := serialModuleTest(t, "org", "orgpolicy.googleapis.com")
	ctx := t.Context()

	extra := map[string]any{}
	want := append([]string{}, orgConstraints...)
	customer := helpers.Getenv(helpers.EnvDirectoryCust, "")
	if customer != "" {
		extra["directory_customer_id"] = customer
		want = append(want, domainConstraint)
	}
	sort.Strings(want)

	opts := helpers.FixtureOptions(t, "org", fixtureVars(run, project,
		[]string{"project_id", "region", "dr_region"}, extra))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	names := terraform.OutputMapContext(t, ctx, opts, "policy_names")
	var got []string
	for k := range names {
		got = append(got, k)
	}
	sort.Strings(got)
	require.Equal(t, want, got, "las siete políticas de la línea base (ocho con cliente de directorio)")
	assert.Equal(t, "projects/"+project.ID, terraform.OutputContext(t, ctx, opts, "policy_parent"))

	describe := func(c string) map[string]any {
		return helpers.GcloudJSON(t, ctx, "org-policies", "describe", c, "--project="+project.ID)
	}
	for _, c := range []string{
		"iam.disableServiceAccountKeyCreation", "compute.requireShieldedVm", "storage.publicAccessPrevention",
		"storage.uniformBucketLevelAccess", "sql.restrictPublicIp",
	} {
		assert.True(t, helpers.PathBool(describe(c), "spec.rules.0.enforce"), "%s debe estar forzada", c)
	}
	assert.True(t, helpers.PathBool(describe("compute.vmExternalIpAccess"), "spec.rules.0.denyAll"), "sin IP externas")
	locs := helpers.PathList(describe("gcp.resourceLocations"), "spec.rules.0.values.allowedValues")
	assert.Contains(t, locs, any("in:"+helpers.Region()+"-locations"))
	assert.Contains(t, locs, any("in:"+helpers.DRRegion()+"-locations"))
	if customer != "" {
		domains := helpers.PathList(describe(domainConstraint), "spec.rules.0.values.allowedValues")
		assert.Contains(t, domains, any(customer), "solo el cliente de directorio")
	}
}
