variable "org_id" {
  description = "ID numérico de la organización; se usa como padre de la política de acceso si el módulo la crea."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{6,20}$", var.org_id))
    error_message = "org_id debe ser el ID numérico de la organización."
  }
}

variable "prefix" {
  description = "Prefijo de la empresa para los nombres (por ejemplo, bnt)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.prefix))
    error_message = "prefix debe tener de 2 a 6 caracteres: minúsculas y dígitos, empezando con letra."
  }
}

variable "environment" {
  description = "Entorno que protege el perímetro (la arquitectura solo crea el de prod)."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser dev, qa o prod."
  }
}

variable "access_policy_id" {
  description = "ID numérico de una política de Access Context Manager que ya exista. Si es null, el módulo crea la política de la organización (solo puede haber una)."
  type        = string
  default     = null

  validation {
    condition     = var.access_policy_id == null || can(regex("^[0-9]+$", var.access_policy_id))
    error_message = "access_policy_id debe ser el número de la política (sin accessPolicies/) o null."
  }
}

variable "access_policy_title" {
  description = "Título de la política de acceso cuando el módulo la crea. Si es null: <prefix>-org-access-policy."
  type        = string
  default     = null
}

variable "perimeter_name" {
  description = "Nombre corto del perímetro (solo letras, dígitos y guion bajo). Si es null: <prefix>_<environment>_sec_perimeter."
  type        = string
  default     = null

  validation {
    condition     = var.perimeter_name == null || can(regex("^[A-Za-z][A-Za-z0-9_]{0,49}$", var.perimeter_name))
    error_message = "perimeter_name debe empezar con letra y tener hasta 50 letras, dígitos o guiones bajos."
  }
}

variable "resources" {
  description = "Proyectos que este módulo mete al perímetro, como projects/<número>. Otras etapas agregan más con sus propios recursos (ver README)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for r in var.resources : can(regex("^projects/[0-9]+$", r))])
    error_message = "Cada recurso debe ser projects/<número de proyecto> (no el ID)."
  }
}

variable "restricted_services" {
  description = "Servicios restringidos por el perímetro (por ejemplo storage.googleapis.com). Debe incluir storage.googleapis.com."
  type        = list(string)

  validation {
    condition     = alltrue([for s in var.restricted_services : can(regex("^[a-z0-9.-]+\\.googleapis\\.com$", s))])
    error_message = "Cada servicio debe tener la forma <servicio>.googleapis.com."
  }
  validation {
    condition     = contains(var.restricted_services, "storage.googleapis.com")
    error_message = "restricted_services debe incluir al menos storage.googleapis.com: el perímetro existe para los datos de prod."
  }
}

variable "ingress_identities" {
  description = "Cuentas de servicio del pipeline (serviceAccount:...) que pueden entrar al perímetro desde cualquier origen, a todos sus servicios y proyectos."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for m in var.ingress_identities : can(regex("^(serviceAccount:|principal://|principalSet://)", m))])
    error_message = "ingress_identities solo admite serviceAccount:, principal:// o principalSet://; nunca user: ni group:."
  }
}

variable "egress_policies" {
  description = <<-EOT
    Reglas de salida opcionales. Cada una: identities (miembros serviceAccount:/group:/
    principal...; vacío con identity_type), identity_type (ANY_IDENTITY, ANY_USER_ACCOUNT,
    ANY_SERVICE_ACCOUNT o null), resources (projects/<número> o "*"), external_resources y
    operations (mapa servicio → lista de métodos; lista vacía = todos los métodos).
  EOT
  type = list(object({
    identities         = optional(list(string), [])
    identity_type      = optional(string)
    resources          = optional(list(string), [])
    external_resources = optional(list(string), [])
    operations         = map(list(string))
  }))
  default = []

  validation {
    condition = alltrue([
      for p in var.egress_policies : p.identity_type == null || contains(["ANY_IDENTITY", "ANY_USER_ACCOUNT", "ANY_SERVICE_ACCOUNT"], p.identity_type)
    ])
    error_message = "identity_type debe ser ANY_IDENTITY, ANY_USER_ACCOUNT, ANY_SERVICE_ACCOUNT o null."
  }
  validation {
    condition     = alltrue([for p in var.egress_policies : (length(p.identities) > 0) != (p.identity_type != null)])
    error_message = "Cada regla de salida lleva identities o identity_type, no ambos ni ninguno."
  }
  validation {
    condition = alltrue(flatten([
      for p in var.egress_policies : [for m in p.identities : can(regex("^(serviceAccount:|group:|principal://|principalSet://)", m))]
    ]))
    error_message = "identities de las reglas de salida no admite user:."
  }
  validation {
    condition = alltrue(flatten([
      for p in var.egress_policies : [for r in p.resources : r == "*" || can(regex("^projects/[0-9]+$", r))]
    ]))
    error_message = "resources de las reglas de salida debe ser projects/<número> o \"*\"."
  }
  validation {
    condition     = alltrue([for p in var.egress_policies : length(p.operations) > 0 && (length(p.resources) > 0 || length(p.external_resources) > 0)])
    error_message = "Cada regla de salida necesita al menos una operación y un destino (resources o external_resources)."
  }
}

variable "enforced" {
  description = "true: configuración forzada (status). false: modo dry-run (spec con use_explicit_dry_run_spec), que solo registra violaciones. Por defecto dry-run (ADR 0009)."
  type        = bool
  default     = false
}
