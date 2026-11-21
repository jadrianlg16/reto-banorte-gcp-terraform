package integration

import (
	"testing"

	"cloud.google.com/go/storage"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gcp-datacenter/tests/helpers"
)

// TestStorage comprueba las exigencias del módulo storage (§8): CMEK, versionado, reglas de
// ciclo de vida, acceso uniforme, sin acceso público y etiquetas obligatorias.
func TestStorage(t *testing.T) {
	run, project := moduleTest(t, "storage", "storage.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "storage", fixtureVars(run, project, varsPPRL, nil))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	bucket := terraform.OutputContext(t, ctx, opts, "bucket_name")
	keyID := terraform.OutputContext(t, ctx, opts, "kms_key_id")
	assert.Regexp(t, "^"+run.Prefix+"-dev-data-", bucket, "nombre según §4.2")

	client, err := storage.NewClient(ctx)
	require.NoError(t, err)
	defer client.Close()

	attrs, err := client.Bucket(bucket).Attrs(ctx)
	require.NoError(t, err)

	require.NotNil(t, attrs.Encryption, "el bucket debe tener CMEK")
	assert.Equal(t, keyID, attrs.Encryption.DefaultKMSKeyName, "llave por defecto del bucket")
	assert.True(t, attrs.VersioningEnabled, "versionado")
	assert.True(t, attrs.UniformBucketLevelAccess.Enabled, "acceso uniforme")
	assert.Equal(t, storage.PublicAccessPreventionEnforced, attrs.PublicAccessPrevention, "sin acceso público")
	assert.NotEmpty(t, attrs.Lifecycle.Rules, "reglas de ciclo de vida")
	for _, k := range helpers.RequiredLabelKeys {
		assert.Contains(t, attrs.Labels, k, "etiqueta obligatoria")
	}

	// Ningún miembro público en el IAM del bucket (política 1 de §9.1).
	policy, err := client.Bucket(bucket).IAM().Policy(ctx)
	require.NoError(t, err)
	for _, role := range policy.Roles() {
		for _, m := range policy.Members(role) {
			assert.NotContains(t, []string{"allUsers", "allAuthenticatedUsers"}, m, "miembro público en %s", role)
		}
	}
}
