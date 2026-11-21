output "members" {
  description = "Lista ordenada y sin repetir de los miembros que recibieron algún rol."
  value       = sort(distinct([for b in var.bindings : b.member]))
}

output "bindings" {
  description = "Mapa llave del for_each → { scope, resource, role, member } de cada asignación creada."
  value = {
    for k, b in local.bindings : k => {
      scope    = b.scope
      resource = b.resource
      role     = b.role
      member   = b.member
    }
  }
}

output "conditions" {
  description = "Mapa llave del for_each → condición de IAM ({ title, expression, description }) de cada asignación creada, o null si no tiene."
  value       = { for k, b in local.bindings : k => b.condition }
}
