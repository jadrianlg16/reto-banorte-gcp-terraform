package integration

import (
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gcp-datacenter/tests/helpers"
)

// TestCloudArmor comprueba el módulo cloud-armor (§8): reglas OWASP preconfiguradas de SQLi y
// XSS como mínimo y una regla de límite de tasa.
func TestCloudArmor(t *testing.T) {
	run, project := moduleTest(t, "cloud-armor", "compute.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "cloud-armor", fixtureVars(run, project, []string{"project_id", "prefix"}, nil))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	name := terraform.OutputContext(t, ctx, opts, "policy_name")
	p := helpers.GcloudJSON(t, ctx, "compute", "security-policies", "describe", name, "--project="+project.ID)

	var exprs []string
	rateLimit := false
	for _, r := range helpers.PathList(p, "rules") {
		exprs = append(exprs, helpers.PathString(r, "match.expr.expression"))
		if a := helpers.PathString(r, "action"); a == "rate_based_ban" || a == "throttle" {
			rateLimit = true
		}
	}
	all := strings.Join(exprs, "\n")
	assert.Contains(t, all, "sqli", "regla OWASP de SQLi")
	assert.Contains(t, all, "xss", "regla OWASP de XSS")
	assert.True(t, rateLimit, "regla de límite de tasa")
}

// TestLoadBalancerExternal comprueba el módulo load-balancer externo (§8): HTTPS en 443 con
// certificado administrado, redirección de HTTP (80) a HTTPS y política de Cloud Armor en el
// servicio de backend.
func TestLoadBalancerExternal(t *testing.T) {
	run, project := moduleTest(t, "load-balancer", "compute.googleapis.com", "run.googleapis.com", "certificatemanager.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "load-balancer", fixtureVars(run, project, varsPPRL, map[string]any{
		"domain": helpers.Getenv(helpers.EnvLBDomain, run.Prefix+".terratest.example.com"),
		"image":  helpers.Getenv(helpers.EnvCloudRunImage, helpers.DefaultCloudRunImage),
	}))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	assert.NotEmpty(t, terraform.OutputContext(t, ctx, opts, "ip_address"), "IP pública")
	rules := terraform.OutputMapContext(t, ctx, opts, "forwarding_rule_names")
	require.Contains(t, rules, "https")
	require.Contains(t, rules, "http")

	https := helpers.GcloudJSON(t, ctx, "compute", "forwarding-rules", "describe", rules["https"], "--global", "--project="+project.ID)
	assert.Equal(t, "443-443", helpers.PathString(https, "portRange"), "HTTPS en 443")
	proxy := helpers.GcloudJSON(t, ctx, "compute", "target-https-proxies", "describe",
		helpers.LastSegment(helpers.PathString(https, "target")), "--global", "--project="+project.ID)
	assert.NotEmpty(t, helpers.PathList(proxy, "sslCertificates"), "certificado administrado")

	http := helpers.GcloudJSON(t, ctx, "compute", "forwarding-rules", "describe", rules["http"], "--global", "--project="+project.ID)
	assert.Equal(t, "80-80", helpers.PathString(http, "portRange"))
	httpProxy := helpers.GcloudJSON(t, ctx, "compute", "target-http-proxies", "describe",
		helpers.LastSegment(helpers.PathString(http, "target")), "--global", "--project="+project.ID)
	redirect := helpers.GcloudJSON(t, ctx, "compute", "url-maps", "describe",
		helpers.LastSegment(helpers.PathString(httpProxy, "urlMap")), "--global", "--project="+project.ID)
	assert.True(t, helpers.PathBool(redirect, "defaultUrlRedirect.httpsRedirect"), "HTTP redirige a HTTPS")

	armor := terraform.OutputContext(t, ctx, opts, "security_policy")
	for key, id := range terraform.OutputMapContext(t, ctx, opts, "backend_service_ids") {
		b := helpers.GcloudJSON(t, ctx, "compute", "backend-services", "describe", helpers.LastSegment(id), "--global", "--project="+project.ID)
		assert.Equal(t, helpers.LastSegment(armor), helpers.LastSegment(helpers.PathString(b, "securityPolicy")), "Cloud Armor en %s", key)
		assert.True(t, helpers.PathBool(b, "logConfig.enable"), "registro de solicitudes en %s", key)
	}
}

// TestObservability comprueba el módulo observability (§8): canal de correo, las cuatro
// alertas base, SLO de disponibilidad y tablero base.
// Necesita TEST_NOTIFICATION_EMAIL (buzón real que recibe las alertas de la prueba).
func TestObservability(t *testing.T) {
	env := helpers.RequireEnv(t, helpers.EnvNotificationMail)
	run, project := moduleTest(t, "observability", "monitoring.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "observability", fixtureVars(run, project,
		[]string{"project_id", "prefix", "labels"},
		map[string]any{"notification_email": env[helpers.EnvNotificationMail]}))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	assert.Len(t, terraform.OutputMapContext(t, ctx, opts, "notification_channel_ids"), 1, "un canal por correo")
	alerts := terraform.OutputMapContext(t, ctx, opts, "alert_policy_ids")
	for _, k := range []string{"lb_5xx_ratio", "saturation", "sql_replica_lag", "slo_burn_rate"} {
		assert.Contains(t, alerts, k, "alerta base %s", k)
	}
	assert.NotEmpty(t, terraform.OutputContext(t, ctx, opts, "slo_id"), "SLO")

	dashboards := terraform.OutputMapContext(t, ctx, opts, "dashboard_ids")
	require.Contains(t, dashboards, "baseline")
	d := helpers.GcloudJSON(t, ctx, "monitoring", "dashboards", "describe", dashboards["baseline"], "--project="+project.ID)
	assert.NotEmpty(t, helpers.PathString(d, "displayName"), "tablero base")
}

// TestBackupDR comprueba el módulo backup-dr (§8): bóveda en la región secundaria con
// retención mínima forzada de 30 días y planes con respaldo diario y retención de 30 días.
// Compuerta: TEST_ALLOW_EXPENSIVE=true (Backup and DR cobra por bóveda; la bóveda no se puede
// borrar si llegó a guardar respaldos).
func TestBackupDR(t *testing.T) {
	helpers.RequireExpensive(t, "TestBackupDR")
	run, project := moduleTest(t, "backup-dr", "backupdr.googleapis.com")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "backup-dr", fixtureVars(run, project,
		[]string{"project_id", "prefix", "region", "dr_region", "labels"}, nil))
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	vaultID := terraform.OutputContext(t, ctx, opts, "vault_id")
	assert.Contains(t, vaultID, "/locations/"+helpers.DRRegion()+"/", "bóveda en la región de DR")
	v := helpers.GcloudJSON(t, ctx, "backup-dr", "backup-vaults", "describe", helpers.LastSegment(vaultID),
		"--location="+helpers.DRRegion(), "--project="+project.ID)
	secs, err := helpers.ParseSeconds(helpers.PathString(v, "backupMinimumEnforcedRetentionDuration"))
	require.NoError(t, err)
	assert.Equal(t, int64(30*24*3600), secs, "retención mínima forzada de 30 días")

	plans := terraform.OutputMapContext(t, ctx, opts, "plan_ids")
	require.NotEmpty(t, plans)
	for key, id := range plans {
		p := helpers.GcloudJSON(t, ctx, "backup-dr", "backup-plans", "describe", helpers.LastSegment(id),
			"--location="+helpers.Region(), "--project="+project.ID)
		assert.Equal(t, "DAILY", helpers.PathString(p, "backupRules.0.standardSchedule.recurrenceType"), "plan %s diario", key)
		assert.Equal(t, "30", helpers.PathString(p, "backupRules.0.backupRetentionDays"), "plan %s con 30 días", key)
	}
}
