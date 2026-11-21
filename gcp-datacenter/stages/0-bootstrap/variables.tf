variable "org_id" {
  description = "ID numérico de la organización de GCP (sin el prefijo organizations/)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{6,20}$", var.org_id))
    error_message = "org_id debe ser el número de la organización, sin organizations/."
  }
}

variable "billing_account" {
  description = "Cuenta de facturación del proyecto semilla y de los proyectos que crean las etapas (formato XXXXXX-XXXXXX-XXXXXX)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$", var.billing_account))
    error_message = "billing_account debe tener la forma XXXXXX-XXXXXX-XXXXXX (hexadecimal en mayúsculas)."
  }
}

variable "prefix" {
  description = "Prefijo de la empresa en todos los nombres (§4.2), por ejemplo bnt."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.prefix))
    error_message = "prefix: de 2 a 6 caracteres, minúsculas y dígitos, empieza con letra."
  }
}

variable "project_suffix" {
  description = "Sufijo opcional que se agrega al ID del proyecto semilla y al nombre del bucket de estado para que sean únicos a nivel mundial. Vacío: sin sufijo."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]{0,8}$", var.project_suffix))
    error_message = "project_suffix: hasta 8 caracteres en minúsculas o dígitos, sin guiones."
  }
}

variable "primary_region" {
  description = "Región primaria (ADR 0002). Aquí viven el llavero de KMS y el bucket de estado."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.primary_region))
    error_message = "primary_region debe ser una región, por ejemplo us-central1."
  }
}

variable "location_short_codes" {
  description = "Mapa ubicación → código corto que se agrega a los nombres de recursos con región (§4.2). Debe incluir primary_region."
  type        = map(string)
  default = {
    "us-central1"         = "usc1"
    "us-east4"            = "use4"
    "northamerica-south1" = "nas1"
    "us"                  = "us"
  }
  nullable = false

  validation {
    condition     = alltrue([for v in values(var.location_short_codes) : can(regex("^[a-z0-9]{2,6}$", v))])
    error_message = "Cada código corto debe tener de 2 a 6 minúsculas o dígitos."
  }
}

variable "github_repository" {
  description = "Repositorio de GitHub (<dueño>/<repositorio>) único autorizado a usar las cuentas de servicio de las etapas por Workload Identity Federation (§6.3)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}$", var.github_repository))
    error_message = "github_repository debe tener la forma <dueño>/<repositorio>, por ejemplo mi-org/mi-repo."
  }
}

variable "state_versions_to_keep" {
  description = "Versiones no actuales de cada archivo de estado que se conservan en el bucket; las más viejas se borran. Permiten recuperar un estado dañado."
  type        = number
  default     = 20
  nullable    = false

  validation {
    condition     = var.state_versions_to_keep >= 5 && floor(var.state_versions_to_keep) == var.state_versions_to_keep
    error_message = "state_versions_to_keep debe ser un entero mayor o igual a 5."
  }
}

variable "labels" {
  description = "Etiquetas comunes (§4.3). Deben traer app, owner y cost_center; la raíz agrega env = bootstrap y managed_by = terraform."
  type        = map(string)
  nullable    = false

  validation {
    condition     = alltrue([for k in ["app", "owner", "cost_center"] : contains(keys(var.labels), k)])
    error_message = "labels debe incluir app, owner y cost_center."
  }
  validation {
    condition     = alltrue([for v in values(var.labels) : can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "Los valores de etiquetas van en minúsculas, dígitos, guion o guion bajo (ADR 0016)."
  }
}
