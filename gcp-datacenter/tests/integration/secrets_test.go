package integration

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gcp-datacenter/tests/helpers"
)

// TestSecrets comprueba las exigencias del módulo secrets (§8, ADR 0015): contenedores sin
// ninguna versión (nunca recibe valores), réplica con CMEK en la región pedida, etiquetas y
// permiso de lectura para los accessors.
func TestSecrets(t *testing.T) {
	run, project := moduleTest(t, "secrets", "secretmanager.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "secrets", fixtureVars(run, project, varsPNPRL, nil))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	secretIDs := terraform.OutputMapContext(t, ctx, opts, "secret_ids")
	keyID := terraform.OutputContext(t, ctx, opts, "kms_key_id")
	reader := terraform.OutputContext(t, ctx, opts, "reader_member")
	require.Len(t, secretIDs, 2)

	for name, id := range secretIDs {
		secret := helpers.GcloudJSON(t, ctx, "secrets", "describe", id)

		replicas := helpers.PathList(secret, "replication.userManaged.replicas")
		require.Len(t, replicas, 1, "%s: una réplica por región de kms_keys", name)
		assert.Equal(t, helpers.Region(), helpers.PathString(replicas[0], "location"), "%s: región de la réplica", name)
		assert.Equal(t, keyID, helpers.PathString(replicas[0], "customerManagedEncryption.kmsKeyName"), "%s: CMEK de la réplica", name)

		for _, k := range helpers.RequiredLabelKeys {
			assert.NotEmpty(t, helpers.PathString(secret, "labels."+k), "%s: etiqueta %s", name, k)
		}

		versions := helpers.GcloudJSONList(t, ctx, "secrets", "versions", "list", id)
		assert.Empty(t, versions, "%s: el módulo nunca crea versiones (valores)", name)

		policy := helpers.GcloudJSON(t, ctx, "secrets", "get-iam-policy", id)
		assert.True(t, hasBinding(policy, "roles/secretmanager.secretAccessor", reader), "%s: accessor", name)
	}
}
