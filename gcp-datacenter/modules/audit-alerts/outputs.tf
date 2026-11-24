output "metric_names" {
  description = "Mapa control (owner, audit_config, custom_role, firewall, route, network, bucket_iam, sql_instance, firewall_policy) → nombre de la métrica de log."
  value       = { for k, m in google_logging_metric.this : k => m.name }
}

output "metric_filters" {
  description = "Mapa control → filtro de la métrica de log, para revisar contra los detectores de Security Command Center."
  value       = { for k, m in google_logging_metric.this : k => m.filter }
}

output "alert_policy_ids" {
  description = "Mapa control → ID de la política de alerta."
  value       = { for k, p in google_monitoring_alert_policy.this : k => p.id }
}

output "notification_email" {
  description = "Correo del canal de notificación (en minúsculas)."
  value       = google_monitoring_notification_channel.email.labels["email_address"]
}

output "notification_channel_id" {
  description = "ID del canal de correo hacia el grupo security_admins."
  value       = google_monitoring_notification_channel.email.id
}
