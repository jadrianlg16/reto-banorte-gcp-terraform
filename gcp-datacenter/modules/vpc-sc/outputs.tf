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
  description = "Reglas de entrada forzadas (status) que administra este módulo (recursos ..._ingress_policy): lista de { title, ingress_from, ingress_to }; vacía en dry-run. No incluye las que agrega la etapa 4. Para revisión y pruebas."
  value = [for p in values(google_access_context_manager_service_perimeter_ingress_policy.pipeline) : {
    title        = p.title
    ingress_from = p.ingress_from
    ingress_to   = p.ingress_to
  }]
}

output "spec_ingress_policies" {
  description = "Reglas de entrada dry-run (spec) que administra este módulo (recursos ..._dry_run_ingress_policy): lista de { title, ingress_from, ingress_to }; vacía si está forzado. No incluye las que agrega la etapa 4. Para revisión y pruebas."
  value = [for p in values(google_access_context_manager_service_perimeter_dry_run_ingress_policy.pipeline) : {
    title        = p.title
    ingress_from = p.ingress_from
    ingress_to   = p.ingress_to
  }]
}

output "enforced" {
  description = "true si el perímetro está forzado; false si está en dry-run. La etapa 4 lo usa para elegir el recurso de alta."
  value       = var.enforced
}
