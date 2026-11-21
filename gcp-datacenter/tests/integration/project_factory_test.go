package integration

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gcp-datacenter/tests/helpers"
)

// TestProjectFactory comprueba las exigencias del módulo project-factory (§8): proyecto sin
// red default, con facturación, APIs pedidas, etiquetas obligatorias y alta como host o
// servicio de Shared VPC. El módulo crea sus propios proyectos: no usa el proyecto efímero.
// Necesita TERRATEST_FOLDER_ID (el módulo solo admite una carpeta como padre).
func TestProjectFactory(t *testing.T) {
	t.Parallel()
	env := helpers.RequireEnv(t, helpers.EnvFolderID, helpers.EnvBillingAccount)
	run := helpers.NewRun("project-factory")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "project-factory", map[string]any{
		"prefix":          run.Prefix,
		"folder_id":       helpers.FolderResource(env[helpers.EnvFolderID]),
		"billing_account": env[helpers.EnvBillingAccount],
		"labels":          helpers.RequiredLabels("dev", run),
	})
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	host := terraform.OutputContext(t, ctx, opts, "host_project_id")
	service := terraform.OutputContext(t, ctx, opts, "service_project_id")
	assert.Regexp(t, "^"+run.Prefix+"-dev-net-spoke", host, "nombre según §4.2")
	assert.Regexp(t, "^"+run.Prefix+"-dev-app", service, "nombre según §4.2")
	assert.Equal(t, host, terraform.OutputContext(t, ctx, opts, "service_shared_vpc_host_project"))
	assert.Contains(t, terraform.OutputListContext(t, ctx, opts, "service_enabled_apis"), "run.googleapis.com")

	for _, p := range []string{host, service} {
		proj := helpers.GcloudJSON(t, ctx, "projects", "describe", p)
		assert.Equal(t, helpers.FolderNumber(env[helpers.EnvFolderID]), helpers.PathString(proj, "parent.id"), "%s: carpeta", p)
		for _, k := range helpers.RequiredLabelKeys {
			assert.NotEmpty(t, helpers.PathString(proj, "labels."+k), "%s: etiqueta %s", p, k)
		}

		billing := helpers.GcloudJSON(t, ctx, "billing", "projects", "describe", p)
		assert.True(t, helpers.PathBool(billing, "billingEnabled"), "%s: facturación", p)

		networks := helpers.GcloudJSONList(t, ctx, "compute", "networks", "list", "--project="+p)
		for _, n := range networks {
			assert.NotEqual(t, "default", helpers.PathString(n, "name"), "%s: no debe existir la red default", p)
		}
	}

	hostInfo := helpers.GcloudJSON(t, ctx, "compute", "project-info", "describe", "--project="+host)
	assert.Equal(t, "HOST", helpers.PathString(hostInfo, "xpnProjectStatus"), "host de Shared VPC")

	associated := helpers.GcloudJSONList(t, ctx, "compute", "shared-vpc", "associated-projects", "list", host)
	var ids []string
	for _, a := range associated {
		ids = append(ids, helpers.PathString(a, "id"))
	}
	require.Contains(t, ids, service, "proyecto de servicio unido al host")
}
