variable "project_id" {
  description = "ID del proyecto de servicio donde se crea la instancia."
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

variable "name" {
  description = "Parte <recurso> del nombre (§4.2). El nombre final es <prefix>-<environment>-data-<name>-<código de región>."
  type        = string
  default     = "sql"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,29}[a-z0-9]$", var.name))
    error_message = "name debe tener de 2 a 31 caracteres: minúsculas, dígitos y guiones; empieza con letra y no termina en guion."
  }
}

variable "region" {
  description = "Región primaria de la instancia."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region debe ser una región de GCP, por ejemplo us-central1."
  }
  validation {
    condition     = contains(keys(var.region_short_codes), var.region)
    error_message = "region no tiene código corto en region_short_codes."
  }
}

variable "dr_region" {
  description = "Región de DR para la réplica de lectura. Obligatoria con enable_dr = true."
  type        = string
  default     = null

  validation {
    condition     = var.dr_region == null ? true : can(regex("^[a-z]+-[a-z]+[0-9]+$", var.dr_region))
    error_message = "dr_region debe ser una región de GCP, por ejemplo us-east4."
  }
  validation {
    condition     = !var.enable_dr || (var.dr_region == null ? false : contains(keys(var.region_short_codes), var.dr_region) && var.dr_region != var.region)
    error_message = "Con enable_dr = true, dr_region es obligatoria, distinta de region y con código corto en region_short_codes."
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

variable "enable_dr" {
  description = "Crea una réplica de lectura entre regiones en dr_region, cifrada con dr_kms_key."
  type        = bool
  default     = false
}

variable "allow_scheduled_stop" {
  description = "Permite que la primaria esté detenida (activation_policy NEVER) por el apagado fuera de horario de dev y qa (módulo off-hours-shutdown, ADR 0028). Con false, un plan con la instancia detenida falla. Se rechaza en prod y con enable_dr (una réplica de lectura no se puede detener)."
  type        = bool
  default     = false
  nullable    = false

  validation {
    condition     = var.environment != "prod" || !var.allow_scheduled_stop
    error_message = "allow_scheduled_stop no se admite en prod: el apagado fuera de horario es solo para dev y qa (ADR 0028)."
  }
  validation {
    condition     = !var.allow_scheduled_stop || !var.enable_dr
    error_message = "allow_scheduled_stop no se admite con enable_dr: la réplica de lectura no se puede detener y seguiría cobrando (ADR 0028)."
  }
}

variable "sql_tier" {
  description = "Tipo de máquina de Cloud SQL (por ejemplo db-custom-2-7680). Debe ser compatible con edition."
  type        = string
  default     = "db-custom-2-7680"

  validation {
    condition     = can(regex("^db-[a-z0-9-]+$", var.sql_tier))
    error_message = "sql_tier debe ser un tipo de máquina de Cloud SQL (empieza con db-)."
  }
  validation {
    condition     = startswith(var.sql_tier, "db-perf-optimized-") == (var.edition == "ENTERPRISE_PLUS")
    error_message = "ENTERPRISE_PLUS usa tipos db-perf-optimized-*; ENTERPRISE usa los demás (db-custom-*, db-g1-small...)."
  }
}

variable "edition" {
  description = "Edición de Cloud SQL: ENTERPRISE (tipos db-custom-*) o ENTERPRISE_PLUS (tipos db-perf-optimized-*)."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition debe ser ENTERPRISE o ENTERPRISE_PLUS."
  }
}

variable "database_version" {
  description = "Versión de PostgreSQL (por ejemplo POSTGRES_16). El módulo solo admite PostgreSQL: sus banderas de auditoría son de PostgreSQL."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version debe ser POSTGRES_<versión mayor>, por ejemplo POSTGRES_16."
  }
}

variable "availability_type" {
  description = "REGIONAL (alta disponibilidad) o ZONAL. Nulo: REGIONAL en prod y ZONAL en dev y qa. En prod solo se acepta REGIONAL."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null ? true : contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type debe ser REGIONAL o ZONAL."
  }
  validation {
    condition     = var.environment != "prod" || var.availability_type == null || var.availability_type == "REGIONAL"
    error_message = "En prod la instancia debe ser REGIONAL (alta disponibilidad)."
  }
}

variable "network" {
  description = "VPC de la Shared VPC donde vive la IP privada, como ID o self link (projects/<host>/global/networks/<red>)."
  type        = string

  validation {
    condition     = can(regex("projects/[a-z][a-z0-9-]{4,28}[a-z0-9]/global/networks/[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.network))
    error_message = "network debe ser el ID o self link de una VPC: projects/<proyecto>/global/networks/<red>."
  }
}

variable "allocated_ip_range" {
  description = "Nombre del rango de Private Service Access de donde se toma la IP (psa_range_name de la etapa 3). Nulo: cualquier rango de la conexión."
  type        = string
  default     = null

  validation {
    condition     = var.allocated_ip_range == null ? true : can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.allocated_ip_range))
    error_message = "allocated_ip_range debe ser el nombre de un rango de direcciones globales."
  }
}

variable "kms_key" {
  description = "ID de la llave KMS (CMEK) de la instancia primaria; debe estar en la misma región que region."
  type        = string

  validation {
    condition     = try(regex("^projects/[^/]+/locations/([^/]+)/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key)[0], "") == var.region
    error_message = "kms_key debe ser projects/<p>/locations/<region>/keyRings/<k>/cryptoKeys/<llave> con la misma ubicación que region."
  }
}

variable "dr_kms_key" {
  description = "ID de la llave KMS de la réplica en DR; obligatoria con enable_dr = true y en la misma ubicación que dr_region."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_dr || try(regex("^projects/[^/]+/locations/([^/]+)/keyRings/[^/]+/cryptoKeys/[^/]+$", var.dr_kms_key)[0], "") == var.dr_region
    error_message = "Con enable_dr = true, dr_kms_key es obligatoria y su ubicación debe ser dr_region."
  }
}

variable "ssl_mode" {
  description = "Modo de SSL de las conexiones. TRUSTED_CLIENT_CERTIFICATE_REQUIRED funciona con los conectores de Cloud SQL y la autenticación IAM; ENCRYPTED_ONLY exige TLS sin certificado de cliente."
  type        = string
  default     = "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"

  validation {
    condition     = contains(["TRUSTED_CLIENT_CERTIFICATE_REQUIRED", "ENCRYPTED_ONLY"], var.ssl_mode)
    error_message = "ssl_mode debe ser TRUSTED_CLIENT_CERTIFICATE_REQUIRED o ENCRYPTED_ONLY (nunca sin cifrado)."
  }
}

variable "iam_users" {
  description = "Usuarios de base de datos con autenticación IAM. type: CLOUD_IAM_USER, CLOUD_IAM_SERVICE_ACCOUNT o CLOUD_IAM_GROUP. Sin contraseñas (ADR 0015)."
  type = list(object({
    email = string
    type  = string
  }))
  default = []

  validation {
    condition = alltrue([
      for u in var.iam_users : contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT", "CLOUD_IAM_GROUP"], u.type)
    ])
    error_message = "type debe ser CLOUD_IAM_USER, CLOUD_IAM_SERVICE_ACCOUNT o CLOUD_IAM_GROUP."
  }
  validation {
    condition     = alltrue([for u in var.iam_users : can(regex("^[^@\\s]+@[^@\\s]+\\.[a-z]{2,}$", u.email))])
    error_message = "Cada email debe ser una dirección de correo."
  }
  validation {
    condition = alltrue([
      for u in var.iam_users : u.type != "CLOUD_IAM_SERVICE_ACCOUNT" || endswith(u.email, ".gserviceaccount.com")
    ])
    error_message = "Un usuario CLOUD_IAM_SERVICE_ACCOUNT debe ser el correo de una cuenta de servicio (*.gserviceaccount.com)."
  }
  validation {
    condition     = length(distinct([for u in var.iam_users : lower(u.email)])) == length(var.iam_users)
    error_message = "iam_users no debe repetir correos."
  }
}

variable "grant_iam_login_roles" {
  description = "Otorga roles/cloudsql.client y roles/cloudsql.instanceUser (condicionados a esta instancia) a los usuarios IAM de tipo cuenta de servicio y grupo. Los CLOUD_IAM_USER nunca reciben roles directos: los obtienen por su grupo (§7.1)."
  type        = bool
  default     = true
}

variable "databases" {
  description = "Bases de datos que se crean en la instancia."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for d in var.databases : can(regex("^[a-z][a-z0-9_]{0,62}$", d))])
    error_message = "Cada base debe tener de 1 a 63 caracteres: minúsculas, dígitos y guion bajo, empezando por letra."
  }
  validation {
    condition     = length(distinct(var.databases)) == length(var.databases)
    error_message = "databases no debe repetir nombres."
  }
}

variable "disk_size_gb" {
  description = "Tamaño inicial del disco en GB; crece solo (disk_autoresize)."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 65536
    error_message = "disk_size_gb debe estar entre 10 y 65536."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Límite del crecimiento automático del disco en GB; 0 es sin límite."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit_gb >= 0
    error_message = "disk_autoresize_limit_gb no puede ser negativo."
  }
}

variable "backup_start_time" {
  description = "Hora de inicio del respaldo diario, HH:MM en UTC."
  type        = string
  default     = "06:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time debe tener formato HH:MM (UTC)."
  }
}

variable "backup_location" {
  description = "Ubicación de los respaldos (región o multirregión). Nulo: la multirregión más cercana a la instancia."
  type        = string
  default     = null

  validation {
    condition     = var.backup_location == null ? true : can(regex("^[a-z]+(-[a-z]+[0-9]+)?$", var.backup_location))
    error_message = "backup_location debe ser una región (us-east4) o una multirregión (us)."
  }
}

variable "retained_backups" {
  description = "Número de respaldos diarios que se conservan."
  type        = number
  default     = 30

  validation {
    condition     = var.retained_backups >= 7 && var.retained_backups <= 365
    error_message = "retained_backups debe estar entre 7 y 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Días de registros de transacciones para la recuperación a un punto en el tiempo (hasta 7 en ENTERPRISE, hasta 35 en ENTERPRISE_PLUS)."
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= (var.edition == "ENTERPRISE_PLUS" ? 35 : 7)
    error_message = "transaction_log_retention_days debe estar entre 1 y 7 (ENTERPRISE) o entre 1 y 35 (ENTERPRISE_PLUS)."
  }
}

variable "backup_plan_managed" {
  description = "true cuando un plan de Backup and DR (módulo backup-dr) protege la instancia (respaldos mejorados): el plan define horario, retención y días de registros, y el módulo deja de declarar backup_start_time, retained_backups y transaction_log_retention_days (fijar log_retention_days del plan con el mismo valor). Respaldos y PITR quedan encendidos."
  type        = bool
  default     = false
  nullable    = false
}

variable "maintenance_window" {
  description = "Ventana de mantenimiento: día (1 = lunes … 7 = domingo), hora UTC (0-23) y canal (stable o canary)."
  type = object({
    day          = number
    hour         = number
    update_track = optional(string, "stable")
  })
  default = {
    day  = 7
    hour = 7
  }

  validation {
    condition     = var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 && var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23
    error_message = "maintenance_window.day va de 1 a 7 y maintenance_window.hour de 0 a 23."
  }
  validation {
    condition     = contains(["stable", "canary", "week5"], var.maintenance_window.update_track)
    error_message = "maintenance_window.update_track debe ser stable, canary o week5."
  }
}

variable "pgaudit_log" {
  description = "Clases de sentencias que registra pgAudit (bandera pgaudit.log), separadas por coma. La extensión se activa con CREATE EXTENSION pgaudit en cada base."
  type        = string
  default     = "ddl,role,write"

  validation {
    condition = alltrue([
      for c in split(",", var.pgaudit_log) :
      contains(["read", "write", "function", "role", "ddl", "misc", "misc_set", "all"], trimspace(c))
    ])
    error_message = "pgaudit_log admite read, write, function, role, ddl, misc, misc_set o all, separadas por coma (none no está permitido)."
  }
}

variable "additional_database_flags" {
  description = "Banderas de PostgreSQL adicionales. No pueden reemplazar las banderas obligatorias de autenticación IAM y auditoría que fija el módulo."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Protección contra borrado (en Terraform y en la API). En prod siempre debe ser true."
  type        = bool
  default     = true

  validation {
    condition     = var.environment != "prod" || var.deletion_protection
    error_message = "En prod deletion_protection debe ser true."
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
