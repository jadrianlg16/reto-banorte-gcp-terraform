mock_provider "google" {}

variables {
  project_id          = "example-prod-app"
  prefix              = "bnt"
  environment         = "prod"
  notification_emails = ["alertas@example.com", "Guardia@Example.com"]
  lb_url_map_name     = "bnt-prod-app-web-xlb-um"
  uptime_checks = {
    web = { host = "app.example.com", path = "/healthz" }
  }
  labels = {
    env         = "prod"
    app         = "web"
    owner       = "plataforma"
    cost_center = "cc-0000"
    managed_by  = "terraform"
  }
}

run "base_cumple_lo_exigido" {
  command = plan

  assert {
    condition     = length(google_monitoring_notification_channel.email) == 2 && google_monitoring_notification_channel.email["guardia@example.com"].labels["email_address"] == "guardia@example.com"
    error_message = "Debe haber un canal de correo por destinatario."
  }

  assert {
    condition     = google_monitoring_uptime_check_config.this["web"].display_name == "bnt-prod-ops-uptime-web"
    error_message = "El nombre de la verificación no sigue §4.2."
  }

  assert {
    condition     = google_monitoring_uptime_check_config.this["web"].http_check[0].use_ssl && google_monitoring_uptime_check_config.this["web"].http_check[0].validate_ssl
    error_message = "La verificación debe usar HTTPS y validar el certificado por defecto."
  }

  assert {
    condition     = length(google_monitoring_alert_policy.uptime) == 1
    error_message = "Cada verificación necesita su alerta."
  }

  assert {
    condition     = google_monitoring_alert_policy.lb_5xx_ratio.conditions[0].condition_threshold[0].threshold_value == 0.05 && strcontains(google_monitoring_alert_policy.lb_5xx_ratio.conditions[0].condition_threshold[0].filter, "response_code_class=500")
    error_message = "Falta la alerta de proporción de 5xx."
  }

  assert {
    condition     = strcontains(google_monitoring_alert_policy.lb_5xx_ratio.conditions[0].condition_threshold[0].denominator_filter, "url_map_name=\"bnt-prod-app-web-xlb-um\"")
    error_message = "La alerta de 5xx debe filtrar por el mapa de URL indicado."
  }

  assert {
    condition     = length(google_monitoring_alert_policy.saturation.conditions) == 4
    error_message = "La alerta de saturación debe cubrir CPU y memoria de VM y de GKE."
  }

  assert {
    condition     = google_monitoring_alert_policy.sql_replica_lag.conditions[0].condition_threshold[0].threshold_value < 900
    error_message = "La alerta de retraso de réplica debe saltar antes del RPO de 15 minutos."
  }

  assert {
    condition     = google_monitoring_slo.availability.goal == 0.999 && google_monitoring_slo.availability.rolling_period_days == 28
    error_message = "El SLO debe ser 99.9 % en 28 días por defecto."
  }

  assert {
    condition     = google_monitoring_slo.availability.slo_id == "bnt-prod-ops-lb-availability" && google_monitoring_custom_service.this.service_id == "bnt-prod-ops-lb"
    error_message = "Los nombres del servicio y del SLO no siguen §4.2."
  }

  assert {
    condition     = length(google_monitoring_alert_policy.slo_burn_rate.conditions) == 2
    error_message = "Falta la alerta de consumo del presupuesto de errores (rápida y lenta)."
  }

  assert {
    condition     = jsondecode(google_monitoring_dashboard.baseline.dashboard_json).displayName == "bnt-prod-ops-dashboard-baseline" && length(jsondecode(google_monitoring_dashboard.baseline.dashboard_json).mosaicLayout.tiles) == 6
    error_message = "Falta el tablero base."
  }

  assert {
    condition     = google_monitoring_alert_policy.lb_5xx_ratio.user_labels["managed_by"] == "terraform"
    error_message = "Las alertas deben llevar etiquetas."
  }
}

# Proyecto único (ADR 0029): cada filtro se limita al entorno para que las alertas de dev no
# vean los recursos de prod del mismo proyecto.
run "filtros_limitados_al_entorno" {
  command = plan

  variables {
    environment     = "dev"
    lb_url_map_name = null
    labels = {
      env         = "dev"
      app         = "web"
      owner       = "plataforma"
      cost_center = "cc-0000"
      managed_by  = "terraform"
    }
  }

  assert {
    condition = (
      strcontains(google_monitoring_alert_policy.lb_5xx_ratio.conditions[0].condition_threshold[0].filter, "resource.label.url_map_name=starts_with(\"bnt-dev-\")") &&
      strcontains(google_monitoring_alert_policy.lb_5xx_ratio.conditions[0].condition_threshold[0].denominator_filter, "resource.label.url_map_name=starts_with(\"bnt-dev-\")") &&
      strcontains(google_monitoring_slo.availability.request_based_sli[0].good_total_ratio[0].total_service_filter, "starts_with(\"bnt-dev-\")")
    )
    error_message = "Sin lb_url_map_name, la alerta de 5xx y el SLO deben limitarse a los mapas de URL <prefix>-<env>-."
  }
  assert {
    condition = (
      alltrue([for c in google_monitoring_alert_policy.saturation.conditions : strcontains(c.condition_threshold[0].filter, "metadata.user_labels.env=\"dev\"") if strcontains(c.condition_threshold[0].filter, "gce_instance")]) &&
      alltrue([for c in google_monitoring_alert_policy.saturation.conditions : strcontains(c.condition_threshold[0].filter, "resource.label.cluster_name=starts_with(\"bnt-dev-\")") if strcontains(c.condition_threshold[0].filter, "k8s_node")])
    )
    error_message = "La saturación debe limitarse a las VM con env = dev y a los clústeres bnt-dev-."
  }
  assert {
    condition     = strcontains(google_monitoring_alert_policy.sql_replica_lag.conditions[0].condition_threshold[0].filter, "resource.label.database_id=starts_with(\"example-prod-app:bnt-dev-\")")
    error_message = "El retraso de réplica debe limitarse a las instancias <proyecto>:<prefix>-<env>-."
  }
  assert {
    condition     = strcontains(jsondecode(google_monitoring_dashboard.baseline.dashboard_json).mosaicLayout.tiles[5].widget.xyChart.dataSets[0].timeSeriesQuery.timeSeriesFilter.filter, "resource.label.host=one_of(\"app.example.com\")")
    error_message = "El mosaico de disponibilidad debe mostrar solo los dominios de este entorno."
  }
}

run "canales_existentes_en_todas_las_alertas" {
  command = plan

  variables {
    extra_notification_channel_ids = ["projects/example-prod-app/notificationChannels/123"]
  }

  # Los ID de los canales de correo se conocen solo al crearlos: se fijan para el plan.
  override_resource {
    target          = google_monitoring_notification_channel.email
    override_during = plan
    values          = { id = "projects/example-prod-app/notificationChannels/correo" }
  }

  assert {
    condition = alltrue([
      for p in [google_monitoring_alert_policy.lb_5xx_ratio, google_monitoring_alert_policy.saturation, google_monitoring_alert_policy.sql_replica_lag, google_monitoring_alert_policy.slo_burn_rate, google_monitoring_alert_policy.uptime["web"]] :
      contains(p.notification_channels, "projects/example-prod-app/notificationChannels/123") && length(p.notification_channels) == 3
    ])
    error_message = "Cada alerta debe avisar a los dos canales de correo y al canal existente."
  }
  assert {
    condition     = length(google_monitoring_notification_channel.email) == 2
    error_message = "Los canales existentes no crean canales nuevos."
  }
}

run "sin_verificaciones_no_hay_mosaico_de_disponibilidad" {
  command = plan

  variables {
    uptime_checks = {}
  }

  assert {
    condition     = length(jsondecode(google_monitoring_dashboard.baseline.dashboard_json).mosaicLayout.tiles) == 5 && length(google_monitoring_alert_policy.uptime) == 0
    error_message = "Sin verificaciones, el tablero no debe mostrar las de otros entornos."
  }
}

run "rechaza_canal_existente_mal_formado" {
  command = plan

  variables {
    extra_notification_channel_ids = ["123"]
  }

  expect_failures = [var.extra_notification_channel_ids]
}

run "rechaza_sin_correos" {
  command = plan

  variables {
    notification_emails = []
  }

  expect_failures = [var.notification_emails]
}

run "rechaza_correo_invalido" {
  command = plan

  variables {
    notification_emails = ["no-es-correo"]
  }

  expect_failures = [var.notification_emails]
}

run "rechaza_slo_menor_a_99_9" {
  command = plan

  variables {
    slo_target = 0.99
  }

  expect_failures = [var.slo_target]
}

run "rechaza_slo_de_100" {
  command = plan

  variables {
    slo_target = 1
  }

  expect_failures = [var.slo_target]
}

run "rechaza_umbral_de_replica_sobre_rpo" {
  command = plan

  variables {
    sql_replica_lag_threshold_seconds = 900
  }

  expect_failures = [var.sql_replica_lag_threshold_seconds]
}

run "rechaza_etiquetas_incompletas" {
  command = plan

  variables {
    labels = { env = "prod", managed_by = "terraform" }
  }

  expect_failures = [var.labels]
}
