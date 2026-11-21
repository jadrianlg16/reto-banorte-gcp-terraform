output "project_id" {
  description = "ID del proyecto. Se publica después de habilitar las APIs y Shared VPC, para que quien lo use no llegue antes."
  value       = google_project.this.project_id

  depends_on = [
    google_project_service.this,
    google_compute_shared_vpc_host_project.this,
    google_compute_shared_vpc_service_project.this,
  ]
}

output "project_number" {
  description = "Número del proyecto (para identificar agentes de servicio)."
  value       = google_project.this.number

  depends_on = [google_project_service.this]
}

output "enabled_apis" {
  description = "APIs habilitadas por el módulo, incluida compute.googleapis.com si se agregó por Shared VPC."
  value       = sort(tolist(local.apis))
}

output "shared_vpc_host_project" {
  description = "Proyecto host al que se unió este proyecto como servicio, o null."
  value       = var.shared_vpc_host_project
}
