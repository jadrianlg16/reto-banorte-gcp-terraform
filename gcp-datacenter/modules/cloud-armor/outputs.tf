output "policy_self_link" {
  description = "self_link de la política de seguridad, para el argumento security_policy del módulo load-balancer."
  value       = google_compute_security_policy.this.self_link
}

output "policy_id" {
  description = "ID de la política de seguridad."
  value       = google_compute_security_policy.this.id
}

output "policy_name" {
  description = "Nombre de la política de seguridad."
  value       = google_compute_security_policy.this.name
}
