package integration

import (
	"testing"

	"cloud.google.com/go/storage"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gcp-datacenter/tests/helpers"
)

// TestIAM comprueba el módulo iam (§8): asignaciones aditivas (no reemplazan la política) en
// un proyecto y, con condición, en un bucket. El rechazo de miembros user: es una validación
// de variables y lo cubre la prueba unitaria (modules/iam/tests).
func TestIAM(t *testing.T) {
	run, project := moduleTest(t, "iam", "storage.googleapis.com", "logging.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "iam", fixtureVars(run, project, varsPPRL, nil))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	member := terraform.OutputContext(t, ctx, opts, "member")
	bucket := terraform.OutputContext(t, ctx, opts, "bucket_name")
	assert.Equal(t, []string{member}, terraform.OutputListContext(t, ctx, opts, "members"))

	// Proyecto: el rol aparece y la política conserva los demás miembros (aditiva).
	policy := helpers.GcloudJSON(t, ctx, "projects", "get-iam-policy", project.ID)
	assert.True(t, hasBinding(policy, "roles/logging.viewer", member), "rol de proyecto")
	assert.Greater(t, len(helpers.PathList(policy, "bindings")), 1, "la asignación aditiva no reemplaza la política")

	// Bucket: rol con condición (política v3).
	client, err := storage.NewClient(ctx)
	require.NoError(t, err)
	defer client.Close()
	p3, err := client.Bucket(bucket).IAM().V3().Policy(ctx)
	require.NoError(t, err)
	found := false
	for _, b := range p3.Bindings {
		if b.Role != "roles/storage.objectViewer" || b.Condition == nil {
			continue
		}
		for _, m := range b.Members {
			if m == member {
				found = true
				assert.Equal(t, "solo-prefijo-datos", b.Condition.Title)
			}
		}
	}
	assert.True(t, found, "rol condicionado sobre el bucket")
}
