variable "bindings" {
  description = <<-EOT
    Asignaciones aditivas de un rol a un miembro sobre un recurso. Campos:
    - scope: organization, project, service_account, storage_bucket, kms_key_ring,
      kms_crypto_key, secret o subnetwork.
    - resource: identificador del recurso según scope (ver README).
    - role: rol predefinido (roles/...) o personalizado (organizations/N/roles/... o projects/P/roles/...).
    - member: group:, serviceAccount:, principal:// o principalSet://. Nunca user:.
    - key (opcional): llave estable del for_each. Obligatoria cuando resource, role o member no
      se conocen en el plan (por ejemplo, el correo de una cuenta de servicio creada en el mismo
      plan); si es null se usa "scope|resource|role|member".
    - condition (opcional): condición de IAM { title, expression, description }.
  EOT
  type = list(object({
    scope    = string
    resource = string
    role     = string
    member   = string
    key      = optional(string)
    condition = optional(object({
      title       = string
      expression  = string
      description = optional(string)
    }))
  }))
  default  = []
  nullable = false

  validation {
    condition = alltrue([for b in var.bindings : contains([
      "organization", "project", "service_account", "storage_bucket", "kms_key_ring",
      "kms_crypto_key", "secret", "subnetwork",
    ], b.scope)])
    error_message = "scope debe ser organization, project, service_account, storage_bucket, kms_key_ring, kms_crypto_key, secret o subnetwork."
  }
  validation {
    condition     = alltrue([for b in var.bindings : !startswith(lower(b.member), "user:")])
    error_message = "No se asignan roles a miembros user:; usa un grupo (group:) o una cuenta de servicio."
  }
  validation {
    condition = alltrue([for b in var.bindings : can(regex(
      "^(group:[^@\\s]+@[^@\\s]+|serviceAccount:[^@\\s]+@[^@\\s]+|principal://\\S+|principalSet://\\S+)$", b.member
    ))])
    error_message = "member debe ser group:<correo>, serviceAccount:<correo>, principal://... o principalSet://... (sin user:, domain:, allUsers ni allAuthenticatedUsers)."
  }
  validation {
    condition = alltrue([for b in var.bindings : can(regex(
      "^(roles/[A-Za-z0-9_.]+|organizations/[0-9]+/roles/[A-Za-z0-9_.]+|projects/[a-z][a-z0-9-]{4,28}[a-z0-9]/roles/[A-Za-z0-9_.]+)$", b.role
    ))])
    error_message = "role debe ser roles/<nombre> o un rol personalizado organizations/<n>/roles/<nombre> o projects/<id>/roles/<nombre>."
  }
  validation {
    condition     = alltrue([for b in var.bindings : !contains(["roles/owner", "roles/editor"], b.role)])
    error_message = "Los roles básicos roles/owner y roles/editor no se asignan (mínimo privilegio)."
  }
  validation {
    condition = alltrue([for b in var.bindings : can(regex(lookup({
      organization    = "^(organizations/)?[0-9]+$"
      project         = "^[a-z][a-z0-9-]{4,28}[a-z0-9]$"
      service_account = "^projects/[^/]+/serviceAccounts/[^/@]+@[^/]+$"
      storage_bucket  = "^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$"
      kms_key_ring    = "^projects/[^/]+/locations/[^/]+/keyRings/[^/]+$"
      kms_crypto_key  = "^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$"
      secret          = "^projects/[^/]+/secrets/[^/]+$"
      subnetwork      = "^projects/[^/]+/regions/[^/]+/subnetworks/[^/]+$"
    }, b.scope, "^$"), b.resource))])
    error_message = "resource no tiene el formato de su scope (ver README: organizations/<n>, ID de proyecto, projects/<p>/serviceAccounts/<correo>, nombre de bucket, ID completo de llavero, llave, secreto o subred)."
  }
  validation {
    condition     = alltrue([for b in var.bindings : b.key == null || can(regex("^\\S+$", b.key))])
    error_message = "key no puede estar vacía ni tener espacios."
  }
  validation {
    condition = length(var.bindings) == length(distinct([
      for b in var.bindings : b.key != null ? b.key : join("|", [b.scope, b.resource, b.role, b.member])
    ]))
    error_message = "Hay asignaciones repetidas (misma key, o mismo scope, resource, role y member)."
  }
}
