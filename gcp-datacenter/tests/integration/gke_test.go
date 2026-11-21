package integration

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"

	"gcp-datacenter/tests/helpers"
)

// TestGKE comprueba el módulo gke (§8): nodos privados, endpoint privado, Workload Identity con
// el pool del proyecto, Binary Authorization forzada, etcd cifrado con CMEK y nodos con la
// cuenta de servicio pedida y Shielded.
// Compuerta: TEST_ALLOW_EXPENSIVE=true (clúster regional, ~15 min de creación) y
// TEST_GKE_SECURITY_GROUP (gke-security-groups@<dominio>, exigido por el módulo).
func TestGKE(t *testing.T) {
	helpers.RequireExpensive(t, "TestGKE")
	env := helpers.RequireEnv(t, helpers.EnvGKESecurityGroup)
	run, project := moduleTest(t, "gke", "compute.googleapis.com", "container.googleapis.com",
		"binaryauthorization.googleapis.com", "gkebackup.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "gke", fixtureVars(run, project, varsPNPRL, map[string]any{
		"authenticator_security_group": env[helpers.EnvGKESecurityGroup],
	}))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	name := terraform.OutputContext(t, ctx, opts, "cluster_name")
	location := terraform.OutputContext(t, ctx, opts, "location")
	keyID := terraform.OutputContext(t, ctx, opts, "kms_key_id")
	assert.Equal(t, project.ID+".svc.id.goog", terraform.OutputContext(t, ctx, opts, "workload_pool"))

	c := helpers.GcloudJSON(t, ctx, "container", "clusters", "describe", name, "--location="+location, "--project="+project.ID)
	assert.True(t, helpers.PathBool(c, "privateClusterConfig.enablePrivateNodes"), "nodos privados")
	assert.True(t, helpers.PathBool(c, "privateClusterConfig.enablePrivateEndpoint"), "endpoint privado")
	assert.Equal(t, project.ID+".svc.id.goog", helpers.PathString(c, "workloadIdentityConfig.workloadPool"), "Workload Identity")
	assert.Equal(t, "PROJECT_SINGLETON_POLICY_ENFORCE", helpers.PathString(c, "binaryAuthorization.evaluationMode"), "Binary Authorization")
	assert.Equal(t, "ENCRYPTED", helpers.PathString(c, "databaseEncryption.state"), "etcd cifrado")
	assert.Equal(t, keyID, helpers.PathString(c, "databaseEncryption.keyName"), "llave de etcd")
	assert.Equal(t, env[helpers.EnvGKESecurityGroup], helpers.PathString(c, "authenticatorGroupsConfig.securityGroup"))

	for _, np := range helpers.PathList(c, "nodePools") {
		npName := helpers.PathString(np, "name")
		assert.Regexp(t, `^[a-z0-9-]+@`+project.ID+`\.iam\.gserviceaccount\.com$`, helpers.PathString(np, "config.serviceAccount"), "%s: cuenta de nodos propia", npName)
		assert.True(t, helpers.PathBool(np, "config.shieldedInstanceConfig.enableSecureBoot"), "%s: arranque seguro", npName)
		assert.Equal(t, "GKE_METADATA", helpers.PathString(np, "config.workloadMetadataConfig.mode"), "%s: metadatos de Workload Identity", npName)
	}
}
