output "notification_channel_ids" {
  description = "Mapa correo → ID del canal de notificación."
  value       = { for k, c in google_monitoring_notification_channel.email : k => c.id }
}

output "dashboard_ids" {
  description = "Mapa nombre → ID del tablero (llave baseline)."
  value       = { baseline = google_monitoring_dashboard.baseline.id }
}

output "uptime_check_ids" {
  description = "Mapa llave de uptime_checks → ID de la verificación (uptime_check_id)."
  value       = { for k, u in google_monitoring_uptime_check_config.this : k => u.uptime_check_id }
}

output "alert_policy_ids" {
  description = "Mapa nombre → ID de cada política de alerta (lb_5xx_ratio, saturation, sql_replica_lag, slo_burn_rate y uptime-<llave>)."
  value = merge(
    {
      lb_5xx_ratio    = google_monitoring_alert_policy.lb_5xx_ratio.id
      saturation      = google_monitoring_alert_policy.saturation.id
      sql_replica_lag = google_monitoring_alert_policy.sql_replica_lag.id
      slo_burn_rate   = google_monitoring_alert_policy.slo_burn_rate.id
    },
    { for k, p in google_monitoring_alert_policy.uptime : "uptime-${k}" => p.id },
  )
}

output "slo_id" {
  description = "Nombre completo del SLO de disponibilidad."
  value       = google_monitoring_slo.availability.name
}
