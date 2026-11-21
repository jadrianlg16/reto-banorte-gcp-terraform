# Este módulo no tiene, a propósito, ninguna variable por la que pueda entrar el valor de un
# secreto (ADR 0015): solo crea contenedores y permisos. Las versiones se cargan fuera de
# Terraform (consola, gcloud o el sistema que genere la credencial).

variable "project_id" {
  description = "ID del proyecto donde se crean los contenedores de secretos."
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
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.prefix))
    error_message = "prefix debe tener de 2 a 10 caracteres: minúsculas y dígitos, empezando con letra."
  }
}

variable "environment" {
  description = "Entorno dueño de los secretos: common, dev, qa o prod."
  type        = string

  validation {
    condition     = contains(["common", "dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser common, dev, qa o prod."
  }
}

variable "names" {
  description = "Nombres cortos de los secretos; el ID final es <prefix>-<environment>-sec-<nombre>."
  type        = set(string)

  validation {
    condition     = alltrue([for n in var.names : can(regex("^[a-z][a-z0-9-]{0,62}$", n))])
    error_message = "Cada nombre debe tener de 1 a 63 caracteres: minúsculas, dígitos o guion, empezando con letra."
  }
}

variable "kms_keys" {
  description = <<-EOT
    Mapa región → ID de la llave KMS (projects/<p>/locations/<región>/keyRings/<k>/cryptoKeys/<n>)
    con la que se cifra la réplica de esa región. Cada región del mapa es una réplica
    (replicación administrada por el usuario); la llave debe estar en la misma región.
  EOT
  type        = map(string)

  validation {
    condition     = length(var.kms_keys) > 0
    error_message = "kms_keys debe tener al menos una región: los secretos siempre van con CMEK."
  }
  validation {
    condition     = alltrue([for r in keys(var.kms_keys) : can(regex("^[a-z]+-[a-z]+[0-9]+$", r))])
    error_message = "Las llaves de kms_keys deben ser regiones (por ejemplo us-central1); Secret Manager no admite multirregiones en réplicas administradas."
  }
  validation {
    condition = alltrue([
      for r, k in var.kms_keys : can(regex("^projects/[^/]+/locations/${r}/keyRings/[^/]+/cryptoKeys/[^/]+$", k))
    ])
    error_message = "Cada llave debe tener el formato projects/<p>/locations/<región>/keyRings/<k>/cryptoKeys/<n> y estar en la misma región que su réplica."
  }
}

variable "accessors" {
  description = "Miembros que reciben roles/secretmanager.secretAccessor sobre todos los secretos del módulo. Sin user:."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for m in var.accessors : can(regex("^(serviceAccount:|group:|principal://|principalSet://)", m))])
    error_message = "accessors solo admite serviceAccount:, group:, principal:// o principalSet://; nunca user:, allUsers ni allAuthenticatedUsers."
  }
}

variable "deletion_protection" {
  description = "Impide que Terraform borre los contenedores (y con ellos todas sus versiones)."
  type        = bool
  default     = true
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
