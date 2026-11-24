output "job_names" {
  description = "Mapa llave del trabajo (sql-<llave>-stop|start, gke-<llave>-stop-autoscaling|stop-resize|start-resize|start-autoscaling) → nombre del trabajo de Cloud Scheduler."
  value       = { for k, j in google_cloud_scheduler_job.this : k => j.name }
}

output "job_ids" {
  description = "Mapa llave del trabajo → ID (projects/<p>/locations/<región>/jobs/<nombre>), para lanzarlo a mano con gcloud scheduler jobs run."
  value       = { for k, j in google_cloud_scheduler_job.this : k => j.id }
}

output "window" {
  description = "Horario encendido calculado de los crons: zona horaria, crons, días, minutos del día de encendido y apagado y duración en segundos. La etapa 5 lo usa para el programa de escalado del MIG (business_hours) y para la ventana de Backup and DR."
  value = {
    time_zone      = var.time_zone
    start_schedule = var.start_schedule
    stop_schedule  = var.stop_schedule
    days           = local.days
    start_minute   = local.start_minute
    stop_minute    = local.stop_minute
    duration_sec   = (local.stop_minute - local.start_minute) * 60
  }
}
