# Interfaz con las raíces siguientes (ADR 0029, "Interfaces entre etapas"): nombres y tipos
# fijos.

output "kms_key_ids" {
  description = "Mapa entorno → llave → ID de la llave KMS. Llave: <uso> en primary_region, <uso>_dr en dr_region y <uso>_us en la multirregión us (formato de la etapa 2 anterior; el uso es la primera palabra y la ubicación sale del ID). Usos: gke, compute, sql, storage, filestore, redis, secrets, backup, run y artifacts (en us solo storage, backup y artifacts)."
  value = {
    for e in var.environments : e => merge([
      for l in local.kms_locations : {
        for use, id in module.kms["${e}/${l}"].key_ids : "${use}${local.location_suffix[l]}" => id
      }
    ]...)
  }
}

output "secret_ids" {
  description = "Mapa entorno → nombre corto → ID del secreto (projects/<proyecto>/secrets/<id>). Un entorno sin secretos tiene un mapa vacío."
  value = {
    for e in var.environments : e => try(module.secrets[e].secret_ids, {})
  }
}

output "artifact_registry_repositories" {
  description = "Mapa entorno → aplicación → URL del repositorio Docker (<ubicación>-docker.pkg.dev/<proyecto>/<repositorio>), como la salida de la etapa 4 anterior. Binary Authorization admite estos repositorios y binary_authorization_allowlist_patterns."
  value = {
    for e in var.environments : e => {
      for k, r in google_artifact_registry_repository.this : local.repositories[k].app => "${r.location}-docker.pkg.dev/${r.project}/${r.repository_id}" if local.repositories[k].environment == e
    }
  }
}

output "off_hours_role_id" {
  description = "ID completo (projects/<id>/roles/<prefix>OffHoursScheduler) del rol personalizado del apagado fuera de horario (ADR 0028). Lo crea 0-bootstrap; 1-base lo publica."
  value       = local.custom_role_ids["off_hours_scheduler"]
}

output "security_alert_email" {
  description = "Correo que recibe las alertas de auditoría del proyecto (CIS 2.5 a 2.12)."
  value       = var.security_alert_email
}

output "notification_channel_ids" {
  description = "Mapa uso → ID del canal de notificación de Monitoring. security: canal de correo de security_alert_email (alertas de auditoría)."
  value = {
    security = module.audit_alerts.notification_channel_id
  }
}

output "log_bucket" {
  description = "Nombre del bucket de logs de auditoría (destino del sink de proyecto)."
  value       = module.audit_logs.bucket_name
}

output "vpc_sc_perimeter_name" {
  description = "Nombre completo del perímetro de VPC-SC (accessPolicies/<política>/servicePerimeters/<nombre>), o null sin access_policy_id."
  value       = try(module.vpc_sc[0].perimeter_name, null)
}

output "org_policies_enabled" {
  description = "true si el proyecto está en una organización (org_id) y se aplicaron las políticas de organización."
  value       = var.org_id != null
}
