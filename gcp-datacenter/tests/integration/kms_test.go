package integration

import (
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gcp-datacenter/tests/helpers"
)

// TestKMS comprueba las exigencias del módulo kms (§8): rotación de 90 días o menos en cada
// llave, nombres de §4.2 y permiso encrypter_decrypter para el miembro pedido.
//
// Las llaves llevan prevent_destroy (no se pueden borrar en GCP): antes del destroy la prueba
// las saca del estado y programa la destrucción de sus versiones.
func TestKMS(t *testing.T) {
	run, project := moduleTest(t, "kms")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "kms", fixtureVars(run, project, varsPPRL, nil))

	var keyIDs map[string]string
	defer func() {
		helpers.StateRemove(t, ctx, opts, "module.kms.google_kms_crypto_key.this")
		for _, id := range keyIDs {
			helpers.DestroyKeyVersions(t, ctx, id)
		}
		helpers.DestroyContextBackground(t, opts)
	}()
	terraform.InitAndApplyContext(t, ctx, opts)

	keyIDs = terraform.OutputMapContext(t, ctx, opts, "key_ids")
	require.Len(t, keyIDs, 2)
	keyring := terraform.OutputContext(t, ctx, opts, "keyring_id")
	assert.Contains(t, keyring, "/keyRings/"+run.Prefix+"-dev-sec-keyring-", "nombre del llavero según §4.2")

	for use, id := range keyIDs {
		assert.True(t, strings.HasSuffix(id, "/cryptoKeys/"+run.Prefix+"-dev-sec-"+use), "nombre de la llave %s", use)
		helpers.AssertKeyRotation(t, ctx, id)
	}

	// encrypter_decrypters de la llave storage.
	member := terraform.OutputContext(t, ctx, opts, "user_member")
	policy := helpers.GcloudJSON(t, ctx, "kms", "keys", "get-iam-policy", keyIDs["storage"])
	assert.True(t, hasBinding(policy, "roles/cloudkms.cryptoKeyEncrypterDecrypter", member),
		"%s debe tener cryptoKeyEncrypterDecrypter sobre la llave storage", member)
}

// hasBinding indica si una política de IAM (JSON de gcloud get-iam-policy) da role a member.
func hasBinding(policy map[string]any, role, member string) bool {
	for _, b := range helpers.PathList(policy, "bindings") {
		if helpers.PathString(b, "role") != role {
			continue
		}
		for _, m := range helpers.PathList(b, "members") {
			if s, _ := m.(string); s == member {
				return true
			}
		}
	}
	return false
}
