package integration

import (
	"sort"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gcp-datacenter/tests/helpers"
)

// Las nueve políticas de organización de §7.1.
var orgConstraints = []string{
	"compute.requireShieldedVm",
	"compute.skipDefaultNetworkCreation",
	"compute.vmExternalIpAccess",
	"gcp.resourceLocations",
	"iam.allowedPolicyMemberDomains",
	"iam.disableServiceAccountKeyCreation",
	"sql.restrictPublicIp",
	"storage.publicAccessPrevention",
	"storage.uniformBucketLevelAccess",
}

// TestOrg comprueba el módulo org (§8): las nueve políticas aplicadas con su valor (en una
// carpeta contenedora de la prueba, no en la organización) y el sink agregado con hijos
// incluidos y permiso de escritura en el destino.
// Compuerta: TEST_ALLOW_ORG=true (el sink es de organización).
func TestOrg(t *testing.T) {
	helpers.RequireOrgScope(t, "TestOrg")
	env := helpers.RequireEnv(t, helpers.EnvOrgID, helpers.EnvDirectoryCust)
	run, project := moduleTest(t, "org", "storage.googleapis.com", "orgpolicy.googleapis.com", "logging.googleapis.com")
	ctx := t.Context()
	orgID := helpers.OrgNumber(env[helpers.EnvOrgID])

	opts := helpers.FixtureOptions(t, "org", fixtureVars(run, project,
		[]string{"project_id", "prefix", "region", "dr_region", "labels"},
		map[string]any{
			"org_id":                orgID,
			"parent":                parentResource(t),
			"directory_customer_id": env[helpers.EnvDirectoryCust],
		}))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	names := terraform.OutputMapContext(t, ctx, opts, "policy_names")
	var got []string
	for k := range names {
		got = append(got, k)
	}
	sort.Strings(got)
	require.Equal(t, orgConstraints, got, "exactamente las nueve políticas de §7.1")

	parent := terraform.OutputContext(t, ctx, opts, "policy_parent")
	folder := helpers.FolderNumber(parent)

	describe := func(c string) map[string]any {
		return helpers.GcloudJSON(t, ctx, "org-policies", "describe", c, "--folder="+folder)
	}
	for _, c := range []string{
		"iam.disableServiceAccountKeyCreation", "compute.requireShieldedVm", "storage.publicAccessPrevention",
		"storage.uniformBucketLevelAccess", "compute.skipDefaultNetworkCreation", "sql.restrictPublicIp",
	} {
		assert.True(t, helpers.PathBool(describe(c), "spec.rules.0.enforce"), "%s debe estar forzada", c)
	}
	assert.True(t, helpers.PathBool(describe("compute.vmExternalIpAccess"), "spec.rules.0.denyAll"), "sin IP externas")
	domains := helpers.PathList(describe("iam.allowedPolicyMemberDomains"), "spec.rules.0.values.allowedValues")
	assert.Contains(t, domains, any(env[helpers.EnvDirectoryCust]), "solo el cliente de directorio")
	locs := helpers.PathList(describe("gcp.resourceLocations"), "spec.rules.0.values.allowedValues")
	assert.Contains(t, locs, any("in:"+helpers.Region()+"-locations"))

	sinkName := terraform.OutputContext(t, ctx, opts, "sink_name")
	sink := helpers.GcloudJSON(t, ctx, "logging", "sinks", "describe", sinkName, "--organization="+orgID)
	assert.True(t, helpers.PathBool(sink, "includeChildren"), "sink agregado")
	assert.Equal(t, "storage.googleapis.com/"+terraform.OutputContext(t, ctx, opts, "sink_bucket"), helpers.PathString(sink, "destination"))
	assert.NotEmpty(t, terraform.OutputContext(t, ctx, opts, "sink_writer_identity"))
}
