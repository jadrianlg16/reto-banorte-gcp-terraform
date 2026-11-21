package integration

import (
	"testing"
	"time"

	"cloud.google.com/go/storage"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gcp-datacenter/tests/helpers"
)

// TestLogExport comprueba las exigencias del módulo log-export (§8): bucket con CMEK,
// retención configurada (sin bloquear: un bloqueo es irreversible), sin acceso público y un
// sink hacia él cuya identidad puede escribir en el bucket.
func TestLogExport(t *testing.T) {
	run, project := moduleTest(t, "log-export", "storage.googleapis.com", "logging.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "log-export", fixtureVars(run, project, varsPPRL, nil))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	bucket := terraform.OutputContext(t, ctx, opts, "bucket_name")
	keyID := terraform.OutputContext(t, ctx, opts, "kms_key_id")
	sink := terraform.OutputContext(t, ctx, opts, "sink_name")
	writer := terraform.OutputContext(t, ctx, opts, "writer_identity")
	destination := terraform.OutputContext(t, ctx, opts, "destination")

	client, err := storage.NewClient(ctx)
	require.NoError(t, err)
	defer client.Close()

	attrs, err := client.Bucket(bucket).Attrs(ctx)
	require.NoError(t, err)
	require.NotNil(t, attrs.Encryption, "CMEK")
	assert.Equal(t, keyID, attrs.Encryption.DefaultKMSKeyName)
	require.NotNil(t, attrs.RetentionPolicy, "política de retención")
	assert.Equal(t, 30*24*time.Hour, attrs.RetentionPolicy.RetentionPeriod, "retention_days = 30")
	assert.False(t, attrs.RetentionPolicy.IsLocked, "la prueba nunca bloquea la retención")
	assert.Equal(t, storage.PublicAccessPreventionEnforced, attrs.PublicAccessPrevention)
	assert.True(t, attrs.UniformBucketLevelAccess.Enabled)

	// Sink de proyecto hacia el bucket.
	s := helpers.GcloudJSON(t, ctx, "logging", "sinks", "describe", sink, "--project="+project.ID)
	assert.Equal(t, destination, helpers.PathString(s, "destination"))
	assert.Equal(t, "storage.googleapis.com/"+bucket, destination)

	// La identidad del sink puede crear objetos en el bucket.
	policy, err := client.Bucket(bucket).IAM().Policy(ctx)
	require.NoError(t, err)
	assert.Contains(t, policy.Members("roles/storage.objectCreator"), writer, "writer_identity con objectCreator")
}
