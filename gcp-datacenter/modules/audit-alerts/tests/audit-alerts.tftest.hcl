# Pruebas sin GCP: proveedor simulado y command = plan. Comprueban que los filtros de las ocho
# métricas CIS son exactamente los que buscan los detectores de Security Health Analytics, la
# métrica adicional de políticas de firewall, las alertas, el canal y las validaciones.

mock_provider "google" {}

override_resource {
  target          = google_monitoring_notification_channel.email
  override_during = plan
  values = {
    id = "projects/bnt-common-logging/notificationChannels/1234567890"
  }
}

variables {
  project_id         = "bnt-common-logging"
  prefix             = "bnt"
  environment        = "common"
  notification_email = "GCP-Security-Admins@Example.com"
  labels = {
    env         = "common"
    app         = "logging"
    owner       = "seguridad"
    cost_center = "cc-0000"
    managed_by  = "terraform"
  }
}

run "metricas_y_alertas_cis" {
  command = plan

  assert {
    condition = toset(keys(google_logging_metric.this)) == toset([
      "owner", "audit_config", "custom_role", "firewall", "route", "network", "bucket_iam", "sql_instance", "firewall_policy",
    ])
    error_message = "Deben existir las ocho métricas CIS (2.5 a 2.12) y la de políticas de firewall."
  }

  assert {
    condition     = toset(keys(google_monitoring_alert_policy.this)) == toset(keys(google_logging_metric.this))
    error_message = "Cada métrica necesita su política de alerta."
  }

  # Filtros exactos de la página de hallazgos de SHA (concepts-vulnerabilities-findings).
  assert {
    condition     = google_logging_metric.this["owner"].filter == "(protoPayload.serviceName=\"cloudresourcemanager.googleapis.com\") AND ( (ProjectOwnership OR projectOwnerInvitee) OR (protoPayload.serviceData.policyDelta.bindingDeltas.action=\"REMOVE\" AND protoPayload.serviceData.policyDelta.bindingDeltas.role=\"roles/owner\") OR (protoPayload.serviceData.policyDelta.bindingDeltas.action=\"ADD\" AND protoPayload.serviceData.policyDelta.bindingDeltas.role=\"roles/owner\") )"
    error_message = "El filtro de 2.5 (OWNER_NOT_MONITORED) cambió."
  }
  assert {
    condition     = google_logging_metric.this["audit_config"].filter == "protoPayload.methodName=\"SetIamPolicy\" AND protoPayload.serviceData.policyDelta.auditConfigDeltas:*"
    error_message = "El filtro de 2.6 (AUDIT_CONFIG_NOT_MONITORED) cambió."
  }
  assert {
    condition     = google_logging_metric.this["custom_role"].filter == "resource.type=\"iam_role\" AND (protoPayload.methodName=\"google.iam.admin.v1.CreateRole\" OR protoPayload.methodName=\"google.iam.admin.v1.DeleteRole\" OR protoPayload.methodName=\"google.iam.admin.v1.UpdateRole\")"
    error_message = "El filtro de 2.7 (CUSTOM_ROLE_NOT_MONITORED) cambió."
  }
  assert {
    condition     = google_logging_metric.this["firewall"].filter == "resource.type=\"gce_firewall_rule\" AND (protoPayload.methodName:\"compute.firewalls.insert\" OR protoPayload.methodName:\"compute.firewalls.patch\" OR protoPayload.methodName:\"compute.firewalls.delete\")"
    error_message = "El filtro de 2.8 (FIREWALL_NOT_MONITORED) cambió."
  }
  assert {
    condition     = google_logging_metric.this["route"].filter == "resource.type=\"gce_route\" AND (protoPayload.methodName:\"compute.routes.delete\" OR protoPayload.methodName:\"compute.routes.insert\")"
    error_message = "El filtro de 2.9 (ROUTE_NOT_MONITORED) cambió."
  }
  assert {
    condition     = google_logging_metric.this["network"].filter == "resource.type=\"gce_network\" AND (protoPayload.methodName:\"compute.networks.insert\" OR protoPayload.methodName:\"compute.networks.patch\" OR protoPayload.methodName:\"compute.networks.delete\" OR protoPayload.methodName:\"compute.networks.removePeering\" OR protoPayload.methodName:\"compute.networks.addPeering\")"
    error_message = "El filtro de 2.10 (NETWORK_NOT_MONITORED) cambió."
  }
  assert {
    condition     = google_logging_metric.this["bucket_iam"].filter == "resource.type=gcs_bucket AND protoPayload.methodName=\"storage.setIamPermissions\""
    error_message = "El filtro de 2.11 (BUCKET_IAM_NOT_MONITORED) cambió."
  }
  assert {
    condition     = google_logging_metric.this["sql_instance"].filter == "protoPayload.methodName=\"cloudsql.instances.update\" OR protoPayload.methodName=\"cloudsql.instances.create\" OR protoPayload.methodName=\"cloudsql.instances.delete\""
    error_message = "El filtro de 2.12 (SQL_INSTANCE_NOT_MONITORED) cambió."
  }

  # Extensión de 2.8: políticas de firewall jerárquicas y de red, solo registro de actividad.
  assert {
    condition = alltrue([
      for s in ["cloudaudit.googleapis.com%2Factivity", "compute.firewallPolicies.", "compute.networkFirewallPolicies.", "compute.regionNetworkFirewallPolicies."] :
      strcontains(google_logging_metric.this["firewall_policy"].filter, s)
    ])
    error_message = "La métrica firewall_policy debe cubrir las políticas jerárquicas y de red, solo con el registro de actividad."
  }

  assert {
    condition = alltrue([
      for m in values(google_logging_metric.this) :
      m.metric_descriptor[0].metric_kind == "DELTA" && m.metric_descriptor[0].value_type == "INT64" && m.metric_descriptor[0].unit == "1"
    ])
    error_message = "Las métricas deben ser contadores (DELTA, INT64, unidad 1)."
  }

  # Nombres (§4.2).
  assert {
    condition     = google_logging_metric.this["audit_config"].name == "bnt-common-ops-audit-audit-config" && google_monitoring_alert_policy.this["sql_instance"].display_name == "bnt-common-ops-audit-sql-instance"
    error_message = "Los nombres no siguen <prefix>-<environment>-ops-audit-<control>."
  }

  # Canal de correo hacia security_admins y alertas que lo usan.
  assert {
    condition     = google_monitoring_notification_channel.email.type == "email" && google_monitoring_notification_channel.email.labels["email_address"] == "gcp-security-admins@example.com"
    error_message = "El canal debe ser de correo hacia el grupo, en minúsculas."
  }
  assert {
    condition = alltrue([
      for p in values(google_monitoring_alert_policy.this) :
      p.notification_channels == tolist(["projects/bnt-common-logging/notificationChannels/1234567890"])
    ])
    error_message = "Todas las alertas deben notificar al canal de security_admins."
  }

  # Condición: suma de eventos > 0 en la ventana, sobre la métrica de usuario y su tipo de recurso.
  assert {
    condition = alltrue([
      for k, p in google_monitoring_alert_policy.this :
      strcontains(p.conditions[0].condition_threshold[0].filter, "metric.type=\"logging.googleapis.com/user/bnt-common-ops-audit-${replace(k, "_", "-")}\"") &&
      p.conditions[0].condition_threshold[0].comparison == "COMPARISON_GT" &&
      p.conditions[0].condition_threshold[0].threshold_value == 0 &&
      p.conditions[0].condition_threshold[0].aggregations[0].alignment_period == "600s" &&
      p.conditions[0].condition_threshold[0].aggregations[0].per_series_aligner == "ALIGN_SUM"
    ])
    error_message = "Cada alerta debe disparar con más de 0 eventos de su métrica en 10 minutos."
  }
  assert {
    condition = (
      strcontains(google_monitoring_alert_policy.this["owner"].conditions[0].condition_threshold[0].filter, "resource.type=\"global\"") &&
      strcontains(google_monitoring_alert_policy.this["bucket_iam"].conditions[0].condition_threshold[0].filter, "resource.type=\"gcs_bucket\"") &&
      strcontains(google_monitoring_alert_policy.this["sql_instance"].conditions[0].condition_threshold[0].filter, "resource.type=\"cloudsql_database\"")
    )
    error_message = "El tipo de recurso de la condición no corresponde al de la serie de la métrica."
  }

  assert {
    condition     = google_monitoring_alert_policy.this["owner"].user_labels["managed_by"] == "terraform" && google_monitoring_notification_channel.email.user_labels["app"] == "logging"
    error_message = "Alertas y canal llevan las etiquetas comunes (§4.3)."
  }
}

run "rechaza_correo_invalido" {
  command = plan

  variables {
    notification_email = "security-admins"
  }

  expect_failures = [var.notification_email]
}

run "rechaza_entorno_desconocido" {
  command = plan

  variables {
    environment = "staging"
  }

  expect_failures = [var.environment]
}

run "rechaza_ventana_fuera_de_rango" {
  command = plan

  variables {
    alignment_period = "30s"
  }

  expect_failures = [var.alignment_period]
}

run "rechaza_ventana_sin_unidad" {
  command = plan

  variables {
    alignment_period = "10m"
  }

  expect_failures = [var.alignment_period]
}

run "rechaza_etiquetas_incompletas" {
  command = plan

  variables {
    labels = {
      env        = "common"
      managed_by = "terraform"
    }
  }

  expect_failures = [var.labels]
}
