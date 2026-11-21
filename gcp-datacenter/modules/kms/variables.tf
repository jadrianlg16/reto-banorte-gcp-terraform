variable "project_id" {
  description = "ID del proyecto donde se crean el llavero y las llaves."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id debe ser un ID de proyecto válido: 6 a 30 caracteres, minúsculas, dígitos y guiones."
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
  description = "Entorno que usa las llaves: bootstrap (llave del estado), common, dev, qa o prod."
  type        = string

  validation {
    condition     = contains(["bootstrap", "common", "dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser bootstrap, common, dev, qa o prod."
  }
}

variable "location" {
  description = "Ubicación del llavero: una región (us-central1, us-east4) o la multirregión us."
  type        = string

  validation {
    condition     = contains(keys(var.location_short_codes), var.location)
    error_message = "location no tiene código corto en location_short_codes; agrégalo ahí."
  }
}

variable "location_short_codes" {
  description = "Mapa ubicación → código corto que se agrega al nombre del llavero."
  type        = map(string)
  default = {
    "us-central1"         = "usc1"
    "us-east4"            = "use4"
    "northamerica-south1" = "nas1"
    "us"                  = "us"
  }

  validation {
    condition     = alltrue([for v in values(var.location_short_codes) : can(regex("^[a-z0-9]{2,6}$", v))])
    error_message = "Cada código corto debe tener de 2 a 6 minúsculas o dígitos."
  }
}

variable "keys" {
  description = <<-EOT
    Llaves a crear, por uso (gke, compute, sql, storage, filestore, redis, secrets, backup,
    state...). Todas son simétricas (ENCRYPT_DECRYPT) y rotan con var.rotation_period.
    Opciones: protection_level (SOFTWARE o HSM), destroy_scheduled_duration y
    encrypter_decrypters (miembros que reciben roles/cloudkms.cryptoKeyEncrypterDecrypter
    sobre la llave; sin user:).
  EOT
  type = map(object({
    protection_level           = optional(string, "SOFTWARE")
    destroy_scheduled_duration = optional(string, "2592000s")
    encrypter_decrypters       = optional(list(string), [])
  }))

  validation {
    condition     = length(var.keys) > 0
    error_message = "keys debe tener al menos una llave."
  }
  validation {
    condition     = alltrue([for k in keys(var.keys) : can(regex("^[a-z][a-z0-9-]{0,19}$", k))])
    error_message = "Cada uso (llave del mapa) debe tener de 1 a 20 caracteres: minúsculas, dígitos o guion."
  }
  validation {
    condition     = alltrue([for k in values(var.keys) : contains(["SOFTWARE", "HSM"], k.protection_level)])
    error_message = "protection_level debe ser SOFTWARE o HSM."
  }
  validation {
    condition = alltrue([
      for k in values(var.keys) : can(regex("^[0-9]+s$", k.destroy_scheduled_duration)) &&
      try(tonumber(trimsuffix(k.destroy_scheduled_duration, "s")) >= 86400 && tonumber(trimsuffix(k.destroy_scheduled_duration, "s")) <= 10368000, false)
    ])
    error_message = "destroy_scheduled_duration debe estar entre 86400s (1 día) y 10368000s (120 días)."
  }
  validation {
    condition = alltrue(flatten([
      for k in values(var.keys) : [
        for m in k.encrypter_decrypters : can(regex("^(serviceAccount:|group:|principal://|principalSet://)", m))
      ]
    ]))
    error_message = "encrypter_decrypters solo admite serviceAccount:, group:, principal:// o principalSet://; nunca user:, allUsers ni allAuthenticatedUsers."
  }
}

variable "rotation_period" {
  description = "Periodo de rotación por defecto de las llaves, en segundos con sufijo s. Máximo 90 días."
  type        = string
  default     = "7776000s"

  validation {
    condition = can(regex("^[0-9]+s$", var.rotation_period)) && try(
      tonumber(trimsuffix(var.rotation_period, "s")) >= 86400 && tonumber(trimsuffix(var.rotation_period, "s")) <= 7776000,
      false
    )
    error_message = "rotation_period debe estar entre 86400s (1 día) y 7776000s (90 días)."
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
