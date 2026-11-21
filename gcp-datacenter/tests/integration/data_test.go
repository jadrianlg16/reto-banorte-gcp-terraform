package integration

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gcp-datacenter/tests/helpers"
)

// TestCloudSQL comprueba el módulo cloud-sql (§8, ADR 0015): sin IP pública (solo privada por
// PSA), SSL obligatorio, respaldos con PITR, CMEK, autenticación IAM activa y un usuario IAM;
// en dev, zonal (en prod la validación exige REGIONAL, cubierta por la prueba unitaria).
// Compuerta: TEST_ALLOW_EXPENSIVE=true (instancia de ~10 min y cobro por hora).
func TestCloudSQL(t *testing.T) {
	helpers.RequireExpensive(t, "TestCloudSQL")
	run, project := moduleTest(t, "cloud-sql", "compute.googleapis.com", "servicenetworking.googleapis.com", "sqladmin.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "cloud-sql", fixtureVars(run, project, varsPNPRL, nil))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	name := terraform.OutputContext(t, ctx, opts, "instance_name")
	keyID := terraform.OutputContext(t, ctx, opts, "kms_key_id")
	assert.NotEmpty(t, terraform.OutputContext(t, ctx, opts, "private_ip"), "IP privada")
	assert.Equal(t, []string{"app"}, terraform.OutputListContext(t, ctx, opts, "database_names"))
	assert.Len(t, terraform.OutputMapContext(t, ctx, opts, "iam_user_names"), 1, "usuario IAM")

	i := helpers.GcloudJSON(t, ctx, "sql", "instances", "describe", name, "--project="+project.ID)
	assert.False(t, helpers.PathBool(i, "settings.ipConfiguration.ipv4Enabled"), "sin IP pública (política 5 de §9.1)")
	for _, a := range helpers.PathList(i, "ipAddresses") {
		assert.Equal(t, "PRIVATE", helpers.PathString(a, "type"), "solo direcciones privadas")
	}
	assert.Equal(t, "TRUSTED_CLIENT_CERTIFICATE_REQUIRED", helpers.PathString(i, "settings.ipConfiguration.sslMode"), "SSL obligatorio")
	assert.True(t, helpers.PathBool(i, "settings.backupConfiguration.enabled"), "respaldos")
	assert.True(t, helpers.PathBool(i, "settings.backupConfiguration.pointInTimeRecoveryEnabled"), "PITR")
	assert.Equal(t, keyID, helpers.PathString(i, "diskEncryptionConfiguration.kmsKeyName"), "CMEK")
	assert.Equal(t, "ZONAL", helpers.PathString(i, "settings.availabilityType"), "dev es zonal")

	iamAuth := false
	for _, f := range helpers.PathList(i, "settings.databaseFlags") {
		if helpers.PathString(f, "name") == "cloudsql.iam_authentication" && helpers.PathString(f, "value") == "on" {
			iamAuth = true
		}
	}
	assert.True(t, iamAuth, "autenticación IAM")
	for _, k := range helpers.RequiredLabelKeys {
		assert.NotEmpty(t, helpers.PathString(i, "settings.userLabels."+k), "etiqueta %s", k)
	}
}

// TestMemorystore comprueba el módulo memorystore (§8): conexión por Private Service Access
// (IP privada) a la VPC pedida, CMEK y, en dev, tier BASIC.
// Compuerta: TEST_ALLOW_EXPENSIVE=true (instancia de ~10 min).
func TestMemorystore(t *testing.T) {
	helpers.RequireExpensive(t, "TestMemorystore")
	run, project := moduleTest(t, "memorystore", "compute.googleapis.com", "servicenetworking.googleapis.com", "redis.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "memorystore", fixtureVars(run, project, varsPNPRL, nil))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	name := terraform.OutputContext(t, ctx, opts, "instance_name")
	network := terraform.OutputContext(t, ctx, opts, "network_id")
	assert.NotEmpty(t, terraform.OutputContext(t, ctx, opts, "host"))

	r := helpers.GcloudJSON(t, ctx, "redis", "instances", "describe", name, "--region="+helpers.Region(), "--project="+project.ID)
	assert.Equal(t, "PRIVATE_SERVICE_ACCESS", helpers.PathString(r, "connectMode"), "IP privada por PSA")
	assert.Contains(t, helpers.PathString(r, "authorizedNetwork"), network, "VPC autorizada")
	assert.Equal(t, terraform.OutputContext(t, ctx, opts, "kms_key_id"), helpers.PathString(r, "customerManagedKey"), "CMEK")
	assert.Equal(t, "BASIC", helpers.PathString(r, "tier"), "dev sin HA")
}

// TestFilestore comprueba el módulo filestore (§8): CMEK y red por Private Service Access.
// Compuerta: TEST_ALLOW_EXPENSIVE=true (1 TiB ZONAL es el mínimo del tier).
func TestFilestore(t *testing.T) {
	helpers.RequireExpensive(t, "TestFilestore")
	run, project := moduleTest(t, "filestore", "compute.googleapis.com", "servicenetworking.googleapis.com", "file.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "filestore", fixtureVars(run, project, varsPNPRL, nil))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	name := terraform.OutputContext(t, ctx, opts, "instance_name")
	location := terraform.OutputContext(t, ctx, opts, "location")
	assert.NotEmpty(t, terraform.OutputContext(t, ctx, opts, "ip_address"))

	f := helpers.GcloudJSON(t, ctx, "filestore", "instances", "describe", name, "--location="+location, "--project="+project.ID)
	assert.Equal(t, terraform.OutputContext(t, ctx, opts, "kms_key_id"), helpers.PathString(f, "kmsKeyName"), "CMEK")
	nets := helpers.PathList(f, "networks")
	require.Len(t, nets, 1)
	assert.Equal(t, "PRIVATE_SERVICE_ACCESS", helpers.PathString(nets[0], "connectMode"), "red por PSA")
}
