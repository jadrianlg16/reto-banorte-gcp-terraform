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
  description = "Parte <recurso> del nombre (§4.2). El nombre final es <prefix>-<environment>-data-<name>-<código de región> y no pasa de 40 caracteres."
  type        = string
  default     = "redis"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,12}[a-z0-9]$", var.name))
    error_message = "name debe tener de 2 a 14 caracteres: minúsculas, dígitos y guiones; empieza con letra y no termina en guion."
  }
}

variable "region" {
  description = "Región de la instancia."
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

variable "tier" {
  description = "STANDARD_HA (réplica en otra zona con conmutación automática) o BASIC. Nulo: STANDARD_HA en prod y BASIC en dev y qa. En prod solo se acepta STANDARD_HA."
  type        = string
  default     = null

  validation {
    condition     = var.tier == null ? true : contains(["BASIC", "STANDARD_HA"], var.tier)
    error_message = "tier debe ser BASIC o STANDARD_HA."
  }
  validation {
    condition     = var.environment != "prod" || var.tier == null || var.tier == "STANDARD_HA"
    error_message = "En prod la instancia debe ser STANDARD_HA (alta disponibilidad)."
  }
}

variable "memory_gb" {
  description = "Memoria de la instancia en GB."
  type        = number
  default     = 5

  validation {
    condition     = var.memory_gb >= 1 && var.memory_gb <= 300 && floor(var.memory_gb) == var.memory_gb
    error_message = "memory_gb debe ser un entero entre 1 y 300."
  }
}

variable "redis_version" {
  description = "Versión de Redis, por ejemplo REDIS_7_2."
  type        = string
  default     = "REDIS_7_2"

  validation {
    condition     = can(regex("^REDIS_[0-9]+(_[0-9]+)?$", var.redis_version))
    error_message = "redis_version debe tener la forma REDIS_<mayor>[_<menor>], por ejemplo REDIS_7_2."
  }
}

variable "network" {
  description = "VPC de la Shared VPC autorizada, como ID o self link (projects/<host>/global/networks/<red>). La conexión es por Private Service Access."
  type        = string

  validation {
    condition     = can(regex("projects/[a-z][a-z0-9-]{4,28}[a-z0-9]/global/networks/[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.network))
    error_message = "network debe ser el ID o self link de una VPC: projects/<proyecto>/global/networks/<red>."
  }
}

variable "reserved_ip_range" {
  description = "Nombre del rango de Private Service Access de donde se toma la IP (psa_range_name de la etapa 3). Nulo: cualquier rango de la conexión."
  type        = string
  default     = null

  validation {
    condition     = var.reserved_ip_range == null ? true : can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.reserved_ip_range))
    error_message = "reserved_ip_range debe ser el nombre de un rango de direcciones globales."
  }
}

variable "kms_key" {
  description = "ID de la llave KMS (CMEK) de la instancia; debe estar en la misma región que region."
  type        = string

  validation {
    condition     = try(regex("^projects/[^/]+/locations/([^/]+)/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key)[0], "") == var.region
    error_message = "kms_key debe ser projects/<p>/locations/<region>/keyRings/<k>/cryptoKeys/<llave> con la misma ubicación que region."
  }
}

variable "location_id" {
  description = "Zona principal (por ejemplo us-central1-a). Nulo: la elige GCP."
  type        = string
  default     = null

  validation {
    condition     = var.location_id == null ? true : startswith(var.location_id, "${var.region}-")
    error_message = "location_id debe ser una zona de region."
  }
}

variable "alternative_location_id" {
  description = "Zona de la réplica en STANDARD_HA; debe ser distinta de location_id. Nulo: la elige GCP."
  type        = string
  default     = null

  validation {
    condition     = var.alternative_location_id == null ? true : startswith(var.alternative_location_id, "${var.region}-") && var.alternative_location_id != var.location_id
    error_message = "alternative_location_id debe ser otra zona de region."
  }
}

variable "redis_configs" {
  description = "Parámetros de Redis (por ejemplo maxmemory-policy). Ver la lista admitida por Memorystore."
  type        = map(string)
  default     = {}
}

variable "rdb_snapshot_period" {
  description = "Periodo de las instantáneas RDB de persistencia: ONE_HOUR, SIX_HOURS, TWELVE_HOURS o TWENTY_FOUR_HOURS. Nulo: sin persistencia."
  type        = string
  default     = "TWELVE_HOURS"

  validation {
    condition     = var.rdb_snapshot_period == null ? true : contains(["ONE_HOUR", "SIX_HOURS", "TWELVE_HOURS", "TWENTY_FOUR_HOURS"], var.rdb_snapshot_period)
    error_message = "rdb_snapshot_period debe ser ONE_HOUR, SIX_HOURS, TWELVE_HOURS, TWENTY_FOUR_HOURS o null."
  }
}

variable "maintenance_window" {
  description = "Ventana de mantenimiento semanal: día (MONDAY … SUNDAY) y hora de inicio UTC (0-23)."
  type = object({
    day  = string
    hour = number
  })
  default = {
    day  = "SUNDAY"
    hour = 7
  }

  validation {
    condition     = contains(["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"], var.maintenance_window.day)
    error_message = "maintenance_window.day debe ser un día en inglés y mayúsculas (MONDAY … SUNDAY)."
  }
  validation {
    condition     = var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23
    error_message = "maintenance_window.hour va de 0 a 23."
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
