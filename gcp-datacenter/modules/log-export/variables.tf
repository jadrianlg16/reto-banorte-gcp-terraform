variable "project_id" {
  description = "Proyecto donde se crea el bucket de logs (el proyecto único, ADR 0029)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id debe ser un ID de proyecto válido (6 a 30 caracteres)."
  }
}

variable "project_number" {
  description = "Número de project_id (opcional). Pasarlo cuando el proyecto se crea en el mismo plan: el agente de Cloud Storage se consulta con el número, que no se conoce hasta el apply, y así la consulta no corre en el plan contra un proyecto que todavía no existe. null: se consulta con project_id (proyecto que ya existe)."
  type        = string
  default     = null

  validation {
    condition     = var.project_number == null || can(regex("^[0-9]+$", var.project_number))
    error_message = "project_number debe ser el número del proyecto (solo dígitos)."
  }
}

variable "prefix" {
  description = "Prefijo de la empresa en los nombres (por ejemplo, bnt)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.prefix))
    error_message = "prefix debe tener de 2 a 6 caracteres: minúsculas y dígitos, empezando con letra."
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
  description = "Proyecto cuyos logs se exportan: \"projects/<id>\" (sink de proyecto, ADR 0029 §7). null: solo se crea el bucket (el sink lo crea otra raíz con la salida destination)."
  type        = string
  default     = null

  validation {
    condition     = var.parent == null || can(regex("^projects/[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.parent))
    error_message = "parent debe ser projects/<id> o null (ya no hay sinks de organización ni de carpeta)."
  }
}

variable "filter" {
  description = "Filtro de Logging del sink. Por defecto, los registros de auditoría (actividad de administración, acceso a datos, eventos del sistema y política denegada). \"\" exporta todo."
  type        = string
  default     = "logName:\"cloudaudit.googleapis.com\""
  nullable    = false
}

variable "exclusions" {
  description = "Exclusiones del sink: entradas que cumplen filter no se exportan aunque cumplan el filtro del sink. Campos: name (único, letras, dígitos, guion o guion bajo), filter, description (opcional) y disabled (opcional, false). Sin efecto si parent es null."
  type = list(object({
    name        = string
    filter      = string
    description = optional(string)
    disabled    = optional(bool, false)
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for e in var.exclusions : can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$", e.name)) && trimspace(e.filter) != ""])
    error_message = "Cada exclusión necesita name (hasta 100 caracteres: letras, dígitos, guion o guion bajo) y un filter no vacío."
  }
  validation {
    condition     = length(var.exclusions) == length(distinct([for e in var.exclusions : e.name]))
    error_message = "Los nombres de las exclusiones no se pueden repetir."
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
