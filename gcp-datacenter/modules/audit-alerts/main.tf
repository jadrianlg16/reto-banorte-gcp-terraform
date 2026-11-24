# Métricas de log y alertas de auditoría de un proyecto (CIS GCP Foundation v5.0 2.5 a 2.12;
# 2.4 a 2.11 en v3.0). Ver docs/cumplimiento-cis.md y el README del módulo.
#
# Los filtros de las ocho métricas CIS son, palabra por palabra, los que la página de hallazgos
# de Security Health Analytics dice que busca cada detector ("Checks whether the filter property
# of the project's LogsMetric resource is set to ..."):
# https://docs.cloud.google.com/security-command-center/docs/concepts-vulnerabilities-findings
# Por eso no se les agrega nada: los cambios de políticas de firewall (las de red que usa este
# repositorio en lugar de reglas de VPC, y las jerárquicas) van en una novena métrica aparte
# (firewall_policy), para no arriesgar que el detector de 2.8 deje de reconocer su filtro.
# VERIFICAR-EN-APPLY: que SHA reconozca los filtros escritos en una sola línea (la documentación
# los muestra en varias) y que dé por buenas las alertas (pendiente 58).

locals {
  # §4.2: <empresa>-<entorno>-ops-<recurso>.
  name = "${var.prefix}-${var.environment}-ops-audit"

  # resource_type: tipo de recurso monitoreado de la serie de tiempo de cada métrica. Las
  # entradas de auditoría de proyecto, rol, firewall, ruta y red no son tipos de Cloud
  # Monitoring y la métrica queda en "global"; gcs_bucket y cloudsql_database sí lo son
  # (https://docs.cloud.google.com/logging/docs/api/v2/resource-list#resource-mappings).
  # VERIFICAR-EN-APPLY: el tipo con que llegan las series (sobre todo firewall_policy, cuyo tipo
  # de recurso de log no está documentado); con otro tipo la alerta no se dispara nunca.
  metrics = {
    owner = {
      cis           = "2.5"
      title         = "Cambios de propietario del proyecto"
      category      = "OWNER_NOT_MONITORED"
      severity      = "CRITICAL"
      resource_type = "global"
      filter = join(" ", [
        "(protoPayload.serviceName=\"cloudresourcemanager.googleapis.com\")",
        "AND ( (ProjectOwnership OR projectOwnerInvitee) OR",
        "(protoPayload.serviceData.policyDelta.bindingDeltas.action=\"REMOVE\"",
        "AND protoPayload.serviceData.policyDelta.bindingDeltas.role=\"roles/owner\")",
        "OR (protoPayload.serviceData.policyDelta.bindingDeltas.action=\"ADD\"",
        "AND protoPayload.serviceData.policyDelta.bindingDeltas.role=\"roles/owner\") )",
      ])
    }
    audit_config = {
      cis           = "2.6"
      title         = "Cambios de la configuración de auditoría"
      category      = "AUDIT_CONFIG_NOT_MONITORED"
      severity      = "CRITICAL"
      resource_type = "global"
      filter = join(" ", [
        "protoPayload.methodName=\"SetIamPolicy\"",
        "AND protoPayload.serviceData.policyDelta.auditConfigDeltas:*",
      ])
    }
    custom_role = {
      cis           = "2.7"
      title         = "Cambios de roles personalizados"
      category      = "CUSTOM_ROLE_NOT_MONITORED"
      severity      = "WARNING"
      resource_type = "global"
      filter = join(" ", [
        "resource.type=\"iam_role\"",
        "AND (protoPayload.methodName=\"google.iam.admin.v1.CreateRole\"",
        "OR protoPayload.methodName=\"google.iam.admin.v1.DeleteRole\"",
        "OR protoPayload.methodName=\"google.iam.admin.v1.UpdateRole\")",
      ])
    }
    firewall = {
      cis           = "2.8"
      title         = "Cambios de reglas de firewall de VPC"
      category      = "FIREWALL_NOT_MONITORED"
      severity      = "WARNING"
      resource_type = "global"
      filter = join(" ", [
        "resource.type=\"gce_firewall_rule\"",
        "AND (protoPayload.methodName:\"compute.firewalls.insert\"",
        "OR protoPayload.methodName:\"compute.firewalls.patch\"",
        "OR protoPayload.methodName:\"compute.firewalls.delete\")",
      ])
    }
    route = {
      cis           = "2.9"
      title         = "Cambios de rutas de VPC"
      category      = "ROUTE_NOT_MONITORED"
      severity      = "WARNING"
      resource_type = "global"
      filter = join(" ", [
        "resource.type=\"gce_route\"",
        "AND (protoPayload.methodName:\"compute.routes.delete\"",
        "OR protoPayload.methodName:\"compute.routes.insert\")",
      ])
    }
    network = {
      cis           = "2.10"
      title         = "Cambios de redes de VPC"
      category      = "NETWORK_NOT_MONITORED"
      severity      = "WARNING"
      resource_type = "global"
      filter = join(" ", [
        "resource.type=\"gce_network\"",
        "AND (protoPayload.methodName:\"compute.networks.insert\"",
        "OR protoPayload.methodName:\"compute.networks.patch\"",
        "OR protoPayload.methodName:\"compute.networks.delete\"",
        "OR protoPayload.methodName:\"compute.networks.removePeering\"",
        "OR protoPayload.methodName:\"compute.networks.addPeering\")",
      ])
    }
    bucket_iam = {
      cis           = "2.11"
      title         = "Cambios de IAM de buckets de Cloud Storage"
      category      = "BUCKET_IAM_NOT_MONITORED"
      severity      = "WARNING"
      resource_type = "gcs_bucket"
      filter = join(" ", [
        "resource.type=gcs_bucket",
        "AND protoPayload.methodName=\"storage.setIamPermissions\"",
      ])
    }
    sql_instance = {
      cis           = "2.12"
      title         = "Cambios de configuración de Cloud SQL"
      category      = "SQL_INSTANCE_NOT_MONITORED"
      severity      = "WARNING"
      resource_type = "cloudsql_database"
      filter = join(" ", [
        "protoPayload.methodName=\"cloudsql.instances.update\"",
        "OR protoPayload.methodName=\"cloudsql.instances.create\"",
        "OR protoPayload.methodName=\"cloudsql.instances.delete\"",
      ])
    }
    # Extensión de 2.8 (no es un filtro de CIS): el repositorio no crea reglas de VPC sino
    # políticas de firewall de red (spokes y onprem-sim); el filtro también cubre las jerárquicas,
    # que ya no crea (ADR 0029 §6). Solo el registro de actividad: con Data Access de Compute las
    # lecturas también llegarían como auditoría. Los cambios de una política jerárquica se
    # registran en la organización (HYPOTHESIS, pendiente 58): esta métrica de proyecto no los
    # ve. Las políticas de red las vigila además el drift diario de 2-networks.
    firewall_policy = {
      cis           = "2.8"
      title         = "Cambios de políticas de firewall jerárquicas y de red"
      category      = ""
      severity      = "WARNING"
      resource_type = "global"
      filter = join(" ", [
        "logName:\"cloudaudit.googleapis.com%2Factivity\"",
        "AND (protoPayload.methodName:\"compute.firewallPolicies.\"",
        "OR protoPayload.methodName:\"compute.networkFirewallPolicies.\"",
        "OR protoPayload.methodName:\"compute.regionNetworkFirewallPolicies.\")",
      ])
    }
  }
}

# Canal hacia el grupo security_admins.
# VERIFICAR-EN-APPLY: que el grupo acepte correo de remitentes externos (Cloud Monitoring); los
# canales de correo no piden verificación (pendiente 58).
resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "${local.name}-security-admins"
  description  = "Grupo security_admins: alertas de auditoría CIS 2.5 a 2.12."
  type         = "email"
  labels = {
    email_address = lower(var.notification_email)
  }
  user_labels = var.labels
}

# Contador de entradas de log (la página de remediación de SHA pide un contador con unidad 1).
resource "google_logging_metric" "this" {
  for_each = local.metrics

  project     = var.project_id
  name        = "${local.name}-${replace(each.key, "_", "-")}"
  description = "CIS ${each.value.cis}: ${each.value.title}."
  filter      = each.value.filter

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "CIS ${each.value.cis}: ${each.value.title}"
  }
}

# Una alerta por métrica: cualquier evento en la ventana (suma > 0) avisa al canal. CIS no fija
# el umbral; la página de remediación deja los valores de "Create alert from metric".
# VERIFICAR-EN-APPLY: que la API acepte la alerta justo después de crear la métrica (si
# responde que no encuentra el tipo de métrica, repetir el apply; pendiente 58).
resource "google_monitoring_alert_policy" "this" {
  for_each = local.metrics

  project               = var.project_id
  display_name          = "${local.name}-${replace(each.key, "_", "-")}"
  combiner              = "OR"
  severity              = each.value.severity
  notification_channels = [google_monitoring_notification_channel.email.id]
  user_labels           = var.labels

  conditions {
    display_name = "CIS ${each.value.cis}: ${each.value.title}"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.this[each.key].name}\" AND resource.type=\"${each.value.resource_type}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period     = var.alignment_period
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }

      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    mime_type = "text/markdown"
    content   = "CIS GCP Foundation v5.0 ${each.value.cis}${each.value.category == "" ? " (extensión: el repositorio usa políticas de firewall, no reglas de VPC)" : " (detector de SCC ${each.value.category})"}: ${each.value.title} en el proyecto ${var.project_id}. Revisar en Cloud Logging la entrada que la disparó (filtro de la métrica ${google_logging_metric.this[each.key].name}) y confirmar que el cambio vino del pipeline."
  }
}
