variable "project_id" {
  description = "Proyecto donde se crea el bucket de logs (por ejemplo, el proyecto logging de common)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id debe ser un ID de proyecto válido (6 a 30 caracteres)."
  }
}

variable "prefix" {
  description = "Prefijo de la empresa en los nombres (por ejemplo, bnt)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.prefix))
    error_message = "prefix: de 2 a 6 caracteres, minúsculas y dígitos, empieza con letra."
  }
}

variable "environment" {
  description = "Entorno según la convención de nombres: bootstrap, common, dev, qa o prod."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["bootstrap", "common", "dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser bootstrap, common, dev, qa o prod."
  }
}

variable "name" {
  description = "Parte de recurso del nombre. Bucket: <prefix>-<environment>-ops-<name>[-<name_suffix>]; sink: <prefix>-<environment>-ops-<name>-sink."
  type        = string
  default     = "audit-logs"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}[a-z0-9]$", var.name))
    error_message = "name: de 2 a 32 caracteres en minúsculas, dígitos y guiones; empieza con letra."
  }
}

variable "name_suffix" {
  description = "Sufijo opcional para que el nombre del bucket sea único a nivel mundial (normalmente el project_suffix de la raíz). Vacío: sin sufijo."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]{0,8}$", var.name_suffix))
    error_message = "name_suffix: hasta 8 caracteres en minúsculas o dígitos."
  }
}

variable "location" {
  description = "Ubicación del bucket: una región (us-central1), una doble región o una multirregión (US). Debe estar permitida por gcp.resourceLocations."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]*[A-Za-z0-9]$", var.location))
    error_message = "location debe ser una ubicación de Cloud Storage, por ejemplo us-central1 o US."
  }
}

variable "storage_class" {
  description = "Clase de almacenamiento por defecto del bucket."
  type        = string
  default     = "STANDARD"
  nullable    = false

  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "storage_class debe ser STANDARD, NEARLINE, COLDLINE o ARCHIVE."
  }
}

variable "kms_key" {
  description = "ID completo de la llave KMS (CMEK) que cifra el bucket: projects/<p>/locations/<l>/keyRings/<r>/cryptoKeys/<k>. Obligatoria; debe estar en la misma ubicación que el bucket."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key))
    error_message = "kms_key debe ser el ID completo de una llave KMS."
  }
}

variable "grant_kms_to_storage_agent" {
  description = "Si es true, el módulo da roles/cloudkms.cryptoKeyEncrypterDecrypter sobre kms_key al agente de servicio de Cloud Storage del proyecto. false si ese permiso lo asigna otra etapa."
  type        = bool
  default     = true
  nullable    = false
}

variable "retention_days" {
  description = "Días que cada objeto queda protegido contra borrado y reemplazo (política de retención del bucket)."
  type        = number
  nullable    = false

  validation {
    condition     = var.retention_days >= 30 && var.retention_days <= 36500 && floor(var.retention_days) == var.retention_days
    error_message = "retention_days debe ser un entero entre 30 y 36500."
  }
}

variable "retention_locked" {
  description = "Si es true, bloquea la política de retención. IRREVERSIBLE: una vez aplicado, la retención no se puede acortar ni quitar, y el bucket no se puede borrar hasta que venza el último objeto."
  type        = bool
  default     = false
  nullable    = false
}

variable "access_logs_bucket" {
  description = "Bucket que recibe los registros de acceso de este bucket. null: sin registros de acceso (los registros de auditoría de Cloud Storage siguen activos)."
  type        = string
  default     = null
}

variable "parent" {
  description = "Recurso cuyos logs se exportan: \"organizations/<n>\", \"folders/<n>\" o \"projects/<id>\". null: solo se crea el bucket (otro módulo, por ejemplo org, crea el sink)."
  type        = string
  default     = null

  validation {
    condition     = var.parent == null || can(regex("^(organizations/[0-9]+|folders/[0-9]+|projects/[a-z][a-z0-9-]{4,28}[a-z0-9])$", var.parent))
    error_message = "parent debe ser organizations/<n>, folders/<n>, projects/<id> o null."
  }
}

variable "filter" {
  description = "Filtro de Logging del sink. Por defecto, los registros de auditoría (actividad de administración, acceso a datos, eventos del sistema y política denegada). \"\" exporta todo."
  type        = string
  default     = "logName:\"cloudaudit.googleapis.com\""
  nullable    = false
}

variable "include_children" {
  description = "Solo para parent de organización o carpeta: si es true, el sink es agregado e incluye los logs de todas las carpetas y proyectos hijos."
  type        = bool
  default     = true
  nullable    = false
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
