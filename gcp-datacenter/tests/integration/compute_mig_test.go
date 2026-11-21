package integration

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gcp-datacenter/tests/helpers"
)

// TestComputeMIG comprueba el módulo compute-mig (§8): plantilla con Shielded VM (arranque
// seguro, vTPM e integridad), sin IP pública, disco con CMEK y cuenta de servicio propia; MIG
// regional con autocuración por verificación de salud y autoescalador con los límites pedidos.
// No lleva compuerta: una o dos e2-small durante unos minutos.
func TestComputeMIG(t *testing.T) {
	run, project := moduleTest(t, "compute-mig", "compute.googleapis.com")
	ctx := t.Context()
	region := helpers.Region()

	opts := helpers.FixtureOptions(t, "compute-mig", fixtureVars(run, project, varsPNPRL, map[string]any{
		"image": helpers.Getenv(helpers.EnvMIGImage, helpers.DefaultMIGImage),
	}))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	template := helpers.LastSegment(terraform.OutputContext(t, ctx, opts, "instance_template_self_link"))
	mig := terraform.OutputContext(t, ctx, opts, "instance_group_manager_name")
	keyID := terraform.OutputContext(t, ctx, opts, "kms_key_id")
	sa := terraform.OutputContext(t, ctx, opts, "service_account")

	tpl := helpers.GcloudJSON(t, ctx, "compute", "instance-templates", "describe", template,
		"--region="+region, "--project="+project.ID)
	props, _ := helpers.Path(tpl, "properties")
	for _, f := range []string{"enableSecureBoot", "enableVtpm", "enableIntegrityMonitoring"} {
		assert.True(t, helpers.PathBool(props, "shieldedInstanceConfig."+f), "Shielded VM: %s", f)
	}
	nics := helpers.PathList(props, "networkInterfaces")
	require.NotEmpty(t, nics)
	for _, nic := range nics {
		assert.Empty(t, helpers.PathList(nic, "accessConfigs"), "sin IP pública (política 4 de §9.1)")
	}
	for _, d := range helpers.PathList(props, "disks") {
		assert.Equal(t, keyID, helpers.PathString(d, "diskEncryptionKey.kmsKeyName"), "disco con CMEK")
	}
	assert.Equal(t, sa, helpers.PathString(props, "serviceAccounts.0.email"), "cuenta de servicio propia")

	m := helpers.GcloudJSON(t, ctx, "compute", "instance-groups", "managed", "describe", mig,
		"--region="+region, "--project="+project.ID)
	assert.NotEmpty(t, helpers.PathList(m, "autoHealingPolicies"), "autocuración")
	assert.Equal(t, terraform.OutputContext(t, ctx, opts, "health_check_id"),
		trimComputePrefix(helpers.PathString(m, "autoHealingPolicies.0.healthCheck")), "autocuración con la verificación del módulo")

	// VERIFICAR-EN-APPLY: que el JSON de "managed list" traiga el autoscalador asociado (gcloud
	// lo agrega a cada MIG); si no, leerlo de la API regionAutoscalers.
	autoscalers := helpers.GcloudJSONList(t, ctx, "compute", "instance-groups", "managed", "list",
		"--project="+project.ID, "--filter=name="+mig)
	require.Len(t, autoscalers, 1)
	as, _ := helpers.Path(autoscalers[0], "autoscaler")
	assert.Equal(t, "1", helpers.PathString(as, "autoscalingPolicy.minNumReplicas"), "min_replicas")
	assert.Equal(t, "2", helpers.PathString(as, "autoscalingPolicy.maxNumReplicas"), "max_replicas")
}

// trimComputePrefix quita "https://www.googleapis.com/compute/v1/" de un self_link para
// compararlo con un ID de Terraform (projects/…).
func trimComputePrefix(s string) string {
	const p = "https://www.googleapis.com/compute/v1/"
	if len(s) > len(p) && s[:len(p)] == p {
		return s[len(p):]
	}
	return s
}
