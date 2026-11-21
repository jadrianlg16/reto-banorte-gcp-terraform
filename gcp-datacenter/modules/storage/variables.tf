variable "project_id" {
  description = "ID del proyecto donde se crea el bucket."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id debe ser un ID de proyecto válido (6 a 30 caracteres, minúsculas, dígitos y guiones)."
  }
}

variable "prefix" {
  description = "Prefijo de la empresa para los nombres (§4.2), por ejemplo bnt."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.prefix))
    error_message = "prefix debe tener de 2 a 10 caracteres: minúsculas y dígitos, empezando por letra."
  }
}

variable "environment" {
  description = "Entorno: dev, qa o prod."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser dev, qa o prod."
  }
}

variable "name" {
  description = "Parte <recurso> del nombre (§4.2). El nombre final es <prefix>-<environment>-data-<name>-<código de ubicación><name_suffix>."
  type        = string
  default     = "bucket"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name))
    error_message = "name debe tener de 2 a 24 caracteres: minúsculas, dígitos y guiones; empieza con letra y no termina en guion."
  }
}

variable "name_suffix" {
  description = "Sufijo que se agrega al final del nombre para hacerlo único a nivel mundial (como project_suffix). Vacío por defecto."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^(-?[a-z0-9]{1,10})?$", var.name_suffix))
    error_message = "name_suffix admite hasta 10 minúsculas o dígitos, opcionalmente precedidos de un guion."
  }
}

variable "location" {
  description = "Ubicación del bucket: una región (us-central1) o, con dual_region, la multirregión que contiene ambas regiones (us)."
  type        = string

  validation {
    condition     = contains(keys(var.region_short_codes), lower(var.location)) || contains(["us", "eu", "asia"], lower(var.location))
    error_message = "location debe ser una región con código corto en region_short_codes o una multirregión (us, eu, asia)."
  }
  validation {
    condition     = var.dual_region == null || contains(["us", "eu", "asia"], lower(var.location))
    error_message = "Con dual_region, location debe ser la multirregión que contiene ambas regiones (us, eu o asia)."
  }
}

variable "region_short_codes" {
  description = "Mapa región → código corto que se agrega a los nombres (§4.2)."
  type        = map(string)
  default = {
    "us-central1"         = "usc1"
    "us-east4"            = "use4"
    "northamerica-south1" = "nas1"
  }

  validation {
    condition     = alltrue([for v in values(var.region_short_codes) : can(regex("^[a-z0-9]{2,6}$", v))])
    error_message = "Los códigos cortos van en minúsculas y dígitos, de 2 a 6 caracteres."
  }
}

variable "dual_region" {
  description = "Doble región configurable: dos regiones dentro de location y turbo replication (RPO de 15 min, ASYNC_TURBO) por defecto. Nulo: bucket de una sola ubicación."
  type = object({
    regions           = list(string)
    turbo_replication = optional(bool, true)
  })
  default = null

  validation {
    condition = var.dual_region == null ? true : (
      length(var.dual_region.regions) == 2 &&
      length(distinct([for r in var.dual_region.regions : lower(r)])) == 2 &&
      alltrue([for r in var.dual_region.regions : contains(keys(var.region_short_codes), lower(r))])
    )
    error_message = "dual_region.regions debe tener dos regiones distintas con código corto en region_short_codes."
  }
}

variable "kms_key" {
  description = "ID de la llave KMS (CMEK) del bucket. Su ubicación debe coincidir con location (para doble región, la multirregión, por ejemplo us)."
  type        = string

  validation {
    condition     = try(regex("^projects/[^/]+/locations/([^/]+)/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key)[0], "") == lower(var.location)
    error_message = "kms_key debe ser projects/<p>/locations/<ubicación>/keyRings/<k>/cryptoKeys/<llave> con la misma ubicación que location."
  }
}

variable "storage_class" {
  description = "Clase de almacenamiento por defecto."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "storage_class debe ser STANDARD, NEARLINE, COLDLINE o ARCHIVE."
  }
}

variable "lifecycle_rules" {
  description = "Reglas de ciclo de vida (al menos una). Por defecto: borrar versiones no actuales a los 30 días y abortar cargas multiparte incompletas a los 7 días."
  type = list(object({
    action = object({
      type          = string
      storage_class = optional(string)
    })
    condition = object({
      age                        = optional(number)
      created_before             = optional(string)
      with_state                 = optional(string)
      matches_storage_class      = optional(list(string))
      matches_prefix             = optional(list(string))
      matches_suffix             = optional(list(string))
      num_newer_versions         = optional(number)
      days_since_noncurrent_time = optional(number)
      noncurrent_time_before     = optional(string)
      days_since_custom_time     = optional(number)
    })
  }))
  default = [
    {
      action    = { type = "Delete" }
      condition = { days_since_noncurrent_time = 30, with_state = "ARCHIVED" }
    },
    {
      action    = { type = "AbortIncompleteMultipartUpload" }
      condition = { age = 7 }
    },
  ]

  validation {
    condition     = length(var.lifecycle_rules) >= 1
    error_message = "Se exige al menos una regla de ciclo de vida."
  }
  validation {
    condition = alltrue([
      for r in var.lifecycle_rules : contains(["Delete", "SetStorageClass", "AbortIncompleteMultipartUpload"], r.action.type)
    ])
    error_message = "action.type debe ser Delete, SetStorageClass o AbortIncompleteMultipartUpload."
  }
  validation {
    condition = alltrue([
      for r in var.lifecycle_rules : r.action.type != "SetStorageClass" || r.action.storage_class != null
    ])
    error_message = "Una regla SetStorageClass necesita action.storage_class."
  }
  validation {
    condition = alltrue([
      for r in var.lifecycle_rules : r.condition.with_state == null ? true : contains(["LIVE", "ARCHIVED", "ANY"], r.condition.with_state)
    ])
    error_message = "condition.with_state debe ser LIVE, ARCHIVED o ANY."
  }
}

variable "retention_policy" {
  description = "Política de retención opcional: retention_period en segundos e is_locked. Bloquearla es irreversible."
  type = object({
    retention_period = number
    is_locked        = optional(bool, false)
  })
  default = null

  validation {
    condition     = var.retention_policy == null ? true : var.retention_policy.retention_period >= 1 && var.retention_policy.retention_period <= 3155760000
    error_message = "retention_policy.retention_period va de 1 a 3 155 760 000 segundos (100 años)."
  }
}

variable "soft_delete_retention_seconds" {
  description = "Retención de objetos borrados (borrado suave) en segundos: 0 la apaga; si no, entre 7 y 90 días."
  type        = number
  default     = 604800

  validation {
    condition     = var.soft_delete_retention_seconds == 0 || (var.soft_delete_retention_seconds >= 604800 && var.soft_delete_retention_seconds <= 7776000)
    error_message = "soft_delete_retention_seconds debe ser 0 o estar entre 604800 (7 días) y 7776000 (90 días)."
  }
}

variable "force_destroy" {
  description = "Permite borrar el bucket con objetos dentro. false por defecto; en prod siempre false."
  type        = bool
  default     = false

  validation {
    condition     = var.environment != "prod" || !var.force_destroy
    error_message = "En prod force_destroy debe ser false."
  }
}

variable "labels" {
  description = "Etiquetas comunes. Obligatorias: env, app, owner, cost_center, managed_by."
  type        = map(string)

  validation {
    condition = alltrue([
      for k in ["env", "app", "owner", "cost_center", "managed_by"] : contains(keys(var.labels), k)
    ])
    error_message = "Faltan etiquetas obligatorias: env, app, owner, cost_center, managed_by."
  }
  validation {
    condition     = lookup(var.labels, "managed_by", "") == "terraform"
    error_message = "managed_by debe ser \"terraform\"."
  }
  validation {
    condition     = alltrue([for v in values(var.labels) : can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "Los valores de etiquetas van en minúsculas, dígitos, guion o guion bajo."
  }
}
