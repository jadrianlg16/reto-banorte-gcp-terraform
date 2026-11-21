output "access_policy_id" {
  description = "ID numérico de la política de Access Context Manager (creada o recibida)."
  value       = local.access_policy_id
}

output "perimeter_name" {
  description = "Nombre completo del perímetro (accessPolicies/<política>/servicePerimeters/<nombre>), el que piden los recursos de alta de proyectos."
  value       = google_access_context_manager_service_perimeter.this.name
}

output "perimeter_short_name" {
  description = "Nombre corto del perímetro."
  value       = local.short_name
}

output "status_ingress_policies" {
  description = "Reglas de entrada de la configuración forzada (status) del perímetro, tal como las lleva el recurso; lista vacía en dry-run. Para revisión y pruebas."
  value       = flatten([for s in google_access_context_manager_service_perimeter.this.status : s.ingress_policies])
}

output "spec_ingress_policies" {
  description = "Reglas de entrada de la configuración dry-run (spec) del perímetro, tal como las lleva el recurso; lista vacía si está forzado. Para revisión y pruebas."
  value       = flatten([for s in google_access_context_manager_service_perimeter.this.spec : s.ingress_policies])
}

output "enforced" {
  description = "true si el perímetro está forzado; false si está en dry-run. La etapa 4 lo usa para elegir el recurso de alta."
  value       = var.enforced
}
