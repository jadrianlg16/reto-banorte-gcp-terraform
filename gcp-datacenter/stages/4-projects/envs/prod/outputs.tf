# Salidas de §7.5 (interfaz con la etapa 5) y una adicional.

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

output "service_agents" {
  description = "[aplicación][agente] → miembro de IAM (serviceAccount:<correo>) de los agentes de servicio que recibieron permisos: apis, compute, filestore, gke, gkebackup, redis, run, sql y storage."
  value       = local.service_agents
}
