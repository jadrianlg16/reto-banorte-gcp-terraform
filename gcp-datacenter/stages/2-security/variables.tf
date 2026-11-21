variable "org_id" {
  description = "ID numérico de la organización de GCP (sin el prefijo organizations/); padre de la política de acceso si la etapa la crea."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{6,20}$", var.org_id))
    error_message = "org_id debe ser el número de la organización, sin organizations/."
  }
}

variable "prefix" {
  description = "Prefijo de la empresa en todos los nombres (§4.2), por ejemplo bnt. El mismo que en las etapas 0 y 1."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.prefix))
    error_message = "prefix: de 2 a 6 caracteres, minúsculas y dígitos, empieza con letra."
  }
}

variable "primary_region" {
  description = "Región primaria (ADR 0002): un llavero por entorno y réplica primaria de los secretos."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.primary_region))
    error_message = "primary_region debe ser una región, por ejemplo us-central1."
  }
}

variable "dr_region" {
  description = "Región de DR (ADR 0002): un llavero por entorno y segunda réplica de los secretos."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.dr_region))
    error_message = "dr_region debe ser una región, por ejemplo us-east4."
  }
  validation {
    condition     = var.dr_region != var.primary_region
    error_message = "dr_region debe ser distinta de primary_region."
  }
}

variable "location_short_codes" {
  description = "Mapa ubicación → código corto de los nombres de llaveros (§4.2). Debe incluir primary_region, dr_region y us."
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

variable "environments" {
  description = "Entornos para los que se crean llaveros, llaves y contenedores de secretos."
  type        = list(string)
  default     = ["dev", "qa", "prod"]
  nullable    = false

  validation {
    condition     = length(var.environments) > 0 && alltrue([for e in var.environments : contains(["dev", "qa", "prod"], e)])
    error_message = "environments debe tener al menos un entorno y solo dev, qa o prod."
  }
  validation {
    condition     = length(distinct(var.environments)) == length(var.environments)
    error_message = "environments no puede repetir entornos."
  }
}

variable "secret_names" {
  description = "Mapa entorno → nombres cortos de los contenedores de secretos (sin valores, ADR 0015). El ID queda <prefix>-<entorno>-sec-<nombre>. Un entorno sin entrada no tiene secretos."
  type        = map(list(string))
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for e in keys(var.secret_names) : contains(var.environments, e)])
    error_message = "Cada llave de secret_names debe ser un entorno de environments."
  }
  validation {
    condition     = alltrue(flatten([for names in values(var.secret_names) : [for n in names : can(regex("^[a-z][a-z0-9-]{0,62}$", n))]]))
    error_message = "Cada nombre de secreto: de 1 a 63 caracteres en minúsculas, dígitos o guion, empezando con letra."
  }
}

variable "key_rotation_period" {
  description = "Periodo de rotación de todas las llaves, en segundos con sufijo s. Por defecto 7776000s (90 días); máximo 90 días."
  type        = string
  default     = "7776000s"
  nullable    = false

  validation {
    condition = can(regex("^[0-9]+s$", var.key_rotation_period)) && try(
      tonumber(trimsuffix(var.key_rotation_period, "s")) >= 86400 && tonumber(trimsuffix(var.key_rotation_period, "s")) <= 7776000,
      false
    )
    error_message = "key_rotation_period debe estar entre 86400s (1 día) y 7776000s (90 días)."
  }
}

variable "access_policy_id" {
  description = "ID numérico de la política de Access Context Manager si la organización ya tiene una (solo puede haber una). null: la etapa la crea."
  type        = string
  default     = null

  validation {
    condition     = var.access_policy_id == null || can(regex("^[0-9]+$", var.access_policy_id))
    error_message = "access_policy_id debe ser el número de la política (sin accessPolicies/) o null."
  }
}

variable "vpc_sc_enforced" {
  description = "true: perímetro de prod forzado. false (por defecto): modo dry-run, solo registra violaciones (ADR 0009)."
  type        = bool
  default     = false
  nullable    = false
}

variable "vpc_sc_restricted_services" {
  description = <<-EOT
    Servicios restringidos por el perímetro de prod; debe incluir storage.googleapis.com.
    Por defecto NO incluye cloudkms.googleapis.com ni secretmanager.googleapis.com (ADR 0019):
    el proyecto security está dentro del perímetro de prod y también guarda las llaves y
    secretos de dev y qa; restringir esas APIs bloquearía a dev y qa (fuera del perímetro) al
    forzarlo. Se agregan cuando dev y qa tengan su propio proyecto de llaves.
  EOT
  type        = list(string)
  default = [
    "artifactregistry.googleapis.com",
    "backupdr.googleapis.com",
    "bigquery.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "file.googleapis.com",
    "gkebackup.googleapis.com",
    "pubsub.googleapis.com",
    "redis.googleapis.com",
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
  ]
  nullable = false

  validation {
    condition     = alltrue([for s in var.vpc_sc_restricted_services : can(regex("^[a-z0-9.-]+\\.googleapis\\.com$", s))])
    error_message = "Cada servicio debe tener la forma <servicio>.googleapis.com."
  }
  validation {
    condition     = contains(var.vpc_sc_restricted_services, "storage.googleapis.com")
    error_message = "vpc_sc_restricted_services debe incluir storage.googleapis.com."
  }
}

variable "labels" {
  description = "Etiquetas comunes (§4.3). Deben traer app, owner y cost_center; la raíz agrega env (el entorno de cada llave o secreto) y managed_by = terraform."
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

variable "state_bucket" {
  description = "Bucket de estado (salida state_bucket de la etapa 0); se usa para leer los estados de 0-bootstrap y 1-org."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", var.state_bucket))
    error_message = "state_bucket debe ser un nombre de bucket válido."
  }
}
