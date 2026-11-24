# Salidas de §7.5 (interfaz con la etapa 5) y adicionales.

output "service_project_ids" {
  description = "Aplicación → ID del proyecto de servicio."
  value       = { for app, p in module.project : app => p.project_id }
}

output "service_project_numbers" {
  description = "Aplicación → número del proyecto de servicio."
  value       = { for app, p in module.project : app => tostring(p.project_number) }
}

output "service_accounts" {
  description = "[aplicación][uso] → correo de la cuenta de servicio de ejecución; usos gke_nodes, workload, mig y run."
  value = {
    for app in keys(var.applications) : app => {
      for use in keys(local.runtime_roles) : use => google_service_account.runtime["${app}/${use}"].email
    }
  }
}

output "artifact_registry_repositories" {
  description = "Aplicación → URL del repositorio Docker (<ubicación>-docker.pkg.dev/<proyecto>/<repositorio>); es la única fuente de imágenes que admite Binary Authorization además de binary_authorization_allowlist_patterns."
  value       = { for app, r in google_artifact_registry_repository.this : app => "${r.location}-docker.pkg.dev/${r.project}/${r.repository_id}" }
}

output "scheduler_service_accounts" {
  description = "Aplicación → correo de la cuenta de los trabajos del apagado fuera de horario (ADR 0028). Vacío sin enable_off_hours_shutdown (siempre en prod)."
  value       = { for app, sa in google_service_account.scheduler : app => sa.email }
}

output "service_agents" {
  description = "[aplicación][agente] → miembro de IAM (serviceAccount:<correo>) de los agentes de servicio que recibieron permisos: apis, artifactregistry, compute, filestore, gke, gkebackup, redis, run, sql y storage."
  value       = local.service_agents
}
