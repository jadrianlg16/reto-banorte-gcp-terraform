package integration

import (
	"encoding/base64"
	"encoding/json"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gcp-datacenter/tests/helpers"
)

// TestOffHoursShutdown comprueba el módulo off-hours-shutdown (ADR 0028) en la API de Cloud
// Scheduler: los seis trabajos de una instancia de Cloud SQL y un pool de GKE, habilitados, con
// el horario y la zona horaria pedidos, el método, la URI y el cuerpo de cada llamada y el token
// OAuth de la cuenta del fixture. No comprueba el efecto de los trabajos (la instancia y el
// pool del fixture no existen): eso queda en los pendientes del primer apply de dev.
// VERIFICAR-EN-APPLY: que Cloud Scheduler no pida una app de App Engine en el proyecto
// efímero y que gcloud devuelva httpTarget.body en base64 (campo bytes de la API).
func TestOffHoursShutdown(t *testing.T) {
	run, project := moduleTest(t, "off-hours-shutdown", "cloudscheduler.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "off-hours-shutdown", fixtureVars(run, project, []string{"project_id", "prefix", "region"}, nil))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	jobIDs := terraform.OutputMapContext(t, ctx, opts, "job_ids")
	email := terraform.OutputContext(t, ctx, opts, "scheduler_email")
	instance := terraform.OutputContext(t, ctx, opts, "sql_instance")
	pool := terraform.OutputContext(t, ctx, opts, "node_pool_path")

	sqlURI := "https://sqladmin.googleapis.com/v1/projects/" + project.ID + "/instances/" + instance
	gkeURI := "https://container.googleapis.com/v1/projects/" + project.ID + "/" + pool
	want := map[string]struct {
		schedule, method, uri, body string
	}{
		"sql-primary-stop":              {"0 20 * * 1-5", "PATCH", sqlURI, `{"settings":{"activationPolicy":"NEVER"}}`},
		"sql-primary-start":             {"0 7 * * 1-5", "PATCH", sqlURI, `{"settings":{"activationPolicy":"ALWAYS"}}`},
		"gke-general-stop-autoscaling":  {"0 20 * * 1-5", "POST", gkeURI + ":setAutoscaling", `{"autoscaling":{"enabled":false}}`},
		"gke-general-stop-resize":       {"10 20 * * 1-5", "POST", gkeURI + ":setSize", `{"nodeCount":0}`},
		"gke-general-start-resize":      {"0 7 * * 1-5", "POST", gkeURI + ":setSize", `{"nodeCount":1}`},
		"gke-general-start-autoscaling": {"10 7 * * 1-5", "POST", gkeURI + ":setAutoscaling", `{"autoscaling":{"enabled":true,"minNodeCount":0,"maxNodeCount":3}}`},
	}
	require.Len(t, jobIDs, len(want), "un trabajo por llave esperada")

	for key, w := range want {
		id, ok := jobIDs[key]
		if !assert.True(t, ok, "falta el trabajo %s", key) {
			continue
		}
		job := helpers.GcloudJSON(t, ctx, "scheduler", "jobs", "describe", helpers.LastSegment(id),
			"--location="+helpers.Region(), "--project="+project.ID)

		assert.Equal(t, "ENABLED", helpers.PathString(job, "state"), "%s: habilitado", key)
		assert.Equal(t, w.schedule, helpers.PathString(job, "schedule"), "%s: horario", key)
		assert.Equal(t, "America/Monterrey", helpers.PathString(job, "timeZone"), "%s: zona horaria", key)
		assert.Equal(t, w.method, helpers.PathString(job, "httpTarget.httpMethod"), "%s: método", key)
		assert.Equal(t, w.uri, helpers.PathString(job, "httpTarget.uri"), "%s: URI", key)
		assert.Equal(t, email, helpers.PathString(job, "httpTarget.oauthToken.serviceAccountEmail"), "%s: cuenta del token", key)
		assert.Equal(t, "https://www.googleapis.com/auth/cloud-platform", helpers.PathString(job, "httpTarget.oauthToken.scope"), "%s: alcance del token", key)

		raw, err := base64.StdEncoding.DecodeString(helpers.PathString(job, "httpTarget.body"))
		if !assert.NoError(t, err, "%s: cuerpo en base64", key) {
			continue
		}
		var got, exp any
		require.NoError(t, json.Unmarshal([]byte(w.body), &exp))
		if assert.NoError(t, json.Unmarshal(raw, &got), "%s: cuerpo JSON", key) {
			assert.Equal(t, exp, got, "%s: cuerpo", key)
		}
	}
}
