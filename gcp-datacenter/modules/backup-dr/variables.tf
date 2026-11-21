variable "project_id" {
  description = "ID del proyecto donde se crean la bóveda y los planes (los planes de Backup and DR deben estar en el mismo proyecto que su bóveda)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id debe ser un ID de proyecto válido de GCP (6 a 30 caracteres, minúsculas, dígitos y guiones)."
  }
}

variable "prefix" {
  description = "Prefijo de la empresa para los nombres (§4.2), por ejemplo \"bnt\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.prefix))
    error_message = "prefix debe tener de 2 a 6 caracteres: minúsculas y dígitos, empezando con letra."
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

variable "region" {
  description = "Región de las cargas protegidas (primaria). Los planes de Backup and DR se crean aquí: deben estar en la región del recurso que respaldan."
  type        = string

  validation {
    condition     = contains(keys(var.region_short_codes), var.region)
    error_message = "region debe ser una llave de region_short_codes."
  }
}

variable "dr_region" {
  description = "Región secundaria (DR) donde vive la bóveda de respaldos y el plan de Backup for GKE. Debe ser distinta de region."
  type        = string

  validation {
    condition     = contains(keys(var.region_short_codes), var.dr_region)
    error_message = "dr_region debe ser una llave de region_short_codes."
  }
  validation {
    condition     = var.dr_region != var.region
    error_message = "dr_region debe ser distinta de region: los respaldos van a la región secundaria."
  }
}

variable "region_short_codes" {
  description = "Código corto de cada región para los nombres (§4.2)."
  type        = map(string)
  default = {
    "us-central1"         = "usc1"
    "us-east4"            = "use4"
    "northamerica-south1" = "nas1"
  }

  validation {
    condition     = alltrue([for v in values(var.region_short_codes) : can(regex("^[a-z0-9]{2,6}$", v))])
    error_message = "Los códigos cortos de región van en minúsculas y dígitos (2 a 6 caracteres)."
  }
}

variable "retention_days" {
  description = "Días que se conserva cada respaldo diario. También es la retención mínima forzada de la bóveda (los respaldos no se pueden borrar antes). La especificación pide 30 días como mínimo."
  type        = number
  default     = 30

  validation {
    condition     = var.retention_days >= 30 && var.retention_days <= 365 && floor(var.retention_days) == var.retention_days
    error_message = "retention_days debe ser un entero entre 30 (mínimo de la especificación) y 365 (máximo de Backup for GKE)."
  }
  validation {
    condition     = !contains(values(var.backup_plans), "sqladmin.googleapis.com/Instance") || var.retention_days <= 186
    error_message = "Con un plan de Cloud SQL, retention_days no puede pasar de 186 (límite de Backup and DR para Cloud SQL)."
  }
}

variable "backup_plans" {
  description = "Planes de Backup and DR a crear. Llave: nombre corto del plan. Valor: tipo de recurso que respalda (compute.googleapis.com/Instance, compute.googleapis.com/Disk o sqladmin.googleapis.com/Instance)."
  type        = map(string)
  default = {
    vm  = "compute.googleapis.com/Instance"
    sql = "sqladmin.googleapis.com/Instance"
  }

  validation {
    condition     = length(var.backup_plans) > 0
    error_message = "backup_plans debe tener al menos un plan."
  }
  validation {
    condition     = alltrue([for k in keys(var.backup_plans) : can(regex("^[a-z][a-z0-9-]{0,14}$", k)) && k != "gke"])
    error_message = "Las llaves de backup_plans tienen de 1 a 15 caracteres (minúsculas, dígitos, guion) y no pueden ser \"gke\" (reservada)."
  }
  validation {
    condition = alltrue([
      for t in values(var.backup_plans) : contains(["compute.googleapis.com/Instance", "compute.googleapis.com/Disk", "sqladmin.googleapis.com/Instance"], t)
    ])
    error_message = "Tipos admitidos: compute.googleapis.com/Instance, compute.googleapis.com/Disk, sqladmin.googleapis.com/Instance."
  }
}

variable "protected_resources" {
  description = "Recursos que se asocian a un plan. Llave: nombre corto. resource: ID completo del recurso (por ejemplo projects/p/zones/z/instances/vm o projects/p/instances/sql); plan: llave de backup_plans. El recurso debe estar en region."
  type = map(object({
    resource = string
    plan     = string
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.protected_resources) : can(regex("^[a-z][a-z0-9-]{0,19}$", k))])
    error_message = "Las llaves de protected_resources tienen de 1 a 20 caracteres: minúsculas, dígitos o guion."
  }
  validation {
    condition     = alltrue([for r in values(var.protected_resources) : contains(keys(var.backup_plans), r.plan)])
    error_message = "plan debe ser una llave de backup_plans."
  }
}

variable "sql_log_retention_days" {
  description = "Solo planes de Cloud SQL (sqladmin.googleapis.com/Instance): días de registros de transacciones que guarda el plan, es decir, la ventana de recuperación a un punto en el tiempo con respaldos mejorados. Igual que transaction_log_retention_days del módulo cloud-sql (7 por defecto, máximo de ENTERPRISE)."
  type        = number
  default     = 7
  nullable    = false

  validation {
    condition     = var.sql_log_retention_days >= 1 && var.sql_log_retention_days <= 35 && floor(var.sql_log_retention_days) == var.sql_log_retention_days
    error_message = "sql_log_retention_days debe ser un entero de 1 a 35."
  }
}

variable "backup_time_zone" {
  description = "Zona horaria (IANA) para interpretar la ventana diaria de respaldo."
  type        = string
  default     = "America/Mexico_City"

  validation {
    condition     = can(regex("^(UTC|[A-Za-z_]+(/[A-Za-z0-9_+-]+)+)$", var.backup_time_zone))
    error_message = "backup_time_zone debe ser UTC o un nombre IANA como America/Mexico_City."
  }
}

variable "backup_window_start_hour" {
  description = "Hora (0 a 17) en que abre la ventana diaria de respaldo; la ventana dura 6 horas."
  type        = number
  default     = 1

  validation {
    condition     = var.backup_window_start_hour >= 0 && var.backup_window_start_hour <= 17 && floor(var.backup_window_start_hour) == var.backup_window_start_hour
    error_message = "backup_window_start_hour debe ser un entero de 0 a 17."
  }
}

variable "enable_gke_backup" {
  description = "Crea el plan de Backup for GKE para gke_cluster_id. Es un interruptor aparte porque el ID del clúster puede no conocerse en el plan."
  type        = bool
  default     = false
}

variable "gke_cluster_id" {
  description = "ID completo del clúster de GKE a respaldar (projects/<p>/locations/<l>/clusters/<n>, salida cluster_id del módulo gke). Obligatorio con enable_gke_backup."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_gke_backup || var.gke_cluster_id != null
    error_message = "enable_gke_backup = true exige gke_cluster_id."
  }
  validation {
    condition     = var.gke_cluster_id == null || can(regex("^projects/[^/]+/locations/[^/]+/clusters/[^/]+$", coalesce(var.gke_cluster_id, "x")))
    error_message = "gke_cluster_id debe tener la forma projects/<p>/locations/<l>/clusters/<n>."
  }
}

variable "gke_backup_kms_key" {
  description = "Llave KMS (uso backup, en dr_region) con la que Backup for GKE cifra los respaldos. Obligatoria con enable_gke_backup."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_gke_backup || var.gke_backup_kms_key != null
    error_message = "enable_gke_backup = true exige gke_backup_kms_key (CMEK)."
  }
  validation {
    condition     = var.gke_backup_kms_key == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", coalesce(var.gke_backup_kms_key, "x")))
    error_message = "gke_backup_kms_key debe tener la forma projects/<p>/locations/<l>/keyRings/<k>/cryptoKeys/<c>."
  }
}

variable "gke_backup_cron" {
  description = "Programación cron (UTC) del respaldo diario de GKE."
  type        = string
  default     = "0 7 * * *"

  validation {
    condition     = can(regex("^[0-9]{1,2} [0-9]{1,2} \\* \\* \\*$", var.gke_backup_cron))
    error_message = "gke_backup_cron debe ser diario: \"<minuto> <hora> * * *\"."
  }
}

variable "gke_backup_delete_lock_days" {
  description = "Días en que un respaldo de GKE no se puede borrar (protección contra borrado accidental o malicioso). No puede pasar de retention_days."
  type        = number
  default     = 7

  validation {
    condition     = var.gke_backup_delete_lock_days >= 0 && var.gke_backup_delete_lock_days <= 90 && var.gke_backup_delete_lock_days <= var.retention_days
    error_message = "gke_backup_delete_lock_days debe estar entre 0 y 90 y no superar retention_days."
  }
}
