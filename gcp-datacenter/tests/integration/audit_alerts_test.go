package integration

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gcp-datacenter/tests/helpers"
)

// TestAuditAlerts comprueba el módulo audit-alerts (CIS 2.5 a 2.12): nueve métricas de log con
// el filtro que publica el módulo, una política de alerta por métrica y el canal de correo.
// Que los detectores de Security Health Analytics reconozcan las métricas no se puede ver aquí
// (necesita SCC Premium en la organización): pendiente 58.
// Necesita TEST_NOTIFICATION_EMAIL (buzón real que recibe las alertas de la prueba).
func TestAuditAlerts(t *testing.T) {
	env := helpers.RequireEnv(t, helpers.EnvNotificationMail)
	run, project := moduleTest(t, "audit-alerts", "logging.googleapis.com", "monitoring.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "audit-alerts", fixtureVars(run, project,
		[]string{"project_id", "prefix", "labels"},
		map[string]any{"notification_email": env[helpers.EnvNotificationMail]}))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	controls := []string{
		"owner", "audit_config", "custom_role", "firewall", "route", "network",
		"bucket_iam", "sql_instance", "firewall_policy",
	}
	names := terraform.OutputMapContext(t, ctx, opts, "metric_names")
	filters := terraform.OutputMapContext(t, ctx, opts, "metric_filters")
	alerts := terraform.OutputMapContext(t, ctx, opts, "alert_policy_ids")
	require.Len(t, names, len(controls), "una métrica por control")
	require.Len(t, alerts, len(controls), "una alerta por métrica")

	for _, k := range controls {
		require.Contains(t, names, k, "métrica %s", k)
		m := helpers.GcloudJSON(t, ctx, "logging", "metrics", "describe", names[k], "--project="+project.ID)
		assert.Equal(t, filters[k], helpers.PathString(m, "filter"), "filtro de la métrica %s tal como se publicó", k)
		assert.Contains(t, alerts[k], "/alertPolicies/", "alerta de %s", k)
	}

	assert.Contains(t, terraform.OutputContext(t, ctx, opts, "notification_channel_id"), "/notificationChannels/", "canal de correo")
}
