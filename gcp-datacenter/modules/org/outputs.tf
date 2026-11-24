output "policy_names" {
  description = "Mapa restricción → nombre completo de la política (projects/<id>/policies/<restricción>): siete políticas, u ocho con directory_customer_id."
  value       = { for k, p in google_org_policy_policy.this : k => p.name }
}

output "policy_parent" {
  description = "Recurso donde se aplicaron las políticas (projects/<id>)."
  value       = local.policy_parent
}
