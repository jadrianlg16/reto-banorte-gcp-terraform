package integration

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"

	"gcp-datacenter/tests/helpers"
)

// TestCloudRun comprueba el módulo cloud-run (§8, ADR 0020): entrada solo interna y del
// balanceador, cuenta de servicio propia, CMEK, salida directa a la VPC, ningún miembro
// público en el IAM y un NEG sin servidor para el balanceador.
func TestCloudRun(t *testing.T) {
	run, project := moduleTest(t, "cloud-run", "compute.googleapis.com", "run.googleapis.com",
		"binaryauthorization.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "cloud-run", fixtureVars(run, project, varsPNPRL, map[string]any{
		"image": helpers.Getenv(helpers.EnvCloudRunImage, helpers.DefaultCloudRunImage),
	}))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	name := terraform.OutputContext(t, ctx, opts, "service_name")
	region := terraform.OutputContext(t, ctx, opts, "location")
	assert.NotEmpty(t, terraform.OutputContext(t, ctx, opts, "neg_id"), "NEG sin servidor")

	// gcloud run services describe devuelve el formato de Knative (API v1).
	svc := helpers.GcloudJSON(t, ctx, "run", "services", "describe", name, "--region="+region, "--project="+project.ID)
	// Las llaves de anotación llevan puntos: se leen del mapa, no con helpers.Path.
	metaRaw, _ := helpers.Path(svc, "metadata.annotations")
	meta, _ := metaRaw.(map[string]any)
	assert.Equal(t, "internal-and-cloud-load-balancing", meta["run.googleapis.com/ingress"], "entrada interna y del balanceador")
	assert.Equal(t, terraform.OutputContext(t, ctx, opts, "service_account"),
		helpers.PathString(svc, "spec.template.spec.serviceAccountName"), "cuenta de servicio propia")

	annotations, _ := helpers.Path(svc, "spec.template.metadata.annotations")
	ann, _ := annotations.(map[string]any)
	assert.Equal(t, terraform.OutputContext(t, ctx, opts, "kms_key_id"), ann["run.googleapis.com/encryption-key"], "CMEK")
	assert.NotEmpty(t, ann["run.googleapis.com/network-interfaces"], "salida directa a la VPC")

	policy := helpers.GcloudJSON(t, ctx, "run", "services", "get-iam-policy", name, "--region="+region, "--project="+project.ID)
	for _, b := range helpers.PathList(policy, "bindings") {
		for _, m := range helpers.PathList(b, "members") {
			assert.NotContains(t, []any{"allUsers", "allAuthenticatedUsers"}, m, "miembro público en %s", helpers.PathString(b, "role"))
		}
	}
}
