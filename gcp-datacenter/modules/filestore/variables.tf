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
  default     = "nfs"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,29}[a-z0-9]$", var.name))
    error_message = "name debe tener de 2 a 31 caracteres: minúsculas, dígitos y guiones; empieza con letra y no termina en guion."
  }
}

variable "tier" {
  description = "Nivel de servicio con soporte de CMEK: ZONAL, REGIONAL o ENTERPRISE (los niveles BASIC_HDD y BASIC_SSD no admiten CMEK)."
  type        = string
  default     = "ZONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL", "ENTERPRISE"], var.tier)
    error_message = "tier debe ser ZONAL, REGIONAL o ENTERPRISE: los niveles básicos no admiten CMEK."
  }
}

variable "location" {
  description = "Zona (us-central1-a) para ZONAL; región (us-central1) para REGIONAL y ENTERPRISE."
  type        = string

  validation {
    condition = (
      var.tier == "ZONAL"
      ? can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.location))
      : can(regex("^[a-z]+-[a-z]+[0-9]+$", var.location))
    )
    error_message = "location debe ser una zona con tier ZONAL, o una región con REGIONAL y ENTERPRISE."
  }
  validation {
    condition     = contains(keys(var.region_short_codes), var.tier == "ZONAL" ? replace(var.location, "/-[a-z]$/", "") : var.location)
    error_message = "La región de location no tiene código corto en region_short_codes."
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

variable "capacity_gb" {
  description = "Capacidad del recurso compartido en GiB. ZONAL: 1024-9984 en pasos de 256 o 10240-102400 en pasos de 2560. REGIONAL: 100-10239 en pasos de 1 o 10240-102400 en pasos de 2560. ENTERPRISE: 1024-10240 en pasos de 256."
  type        = number
  default     = 1024

  validation {
    condition = floor(var.capacity_gb) == var.capacity_gb && (
      var.tier == "ZONAL" ? (
        (var.capacity_gb >= 1024 && var.capacity_gb <= 9984 && var.capacity_gb % 256 == 0) ||
        (var.capacity_gb >= 10240 && var.capacity_gb <= 102400 && (var.capacity_gb - 10240) % 2560 == 0)
      ) :
      var.tier == "REGIONAL" ? (
        (var.capacity_gb >= 100 && var.capacity_gb <= 10239) ||
        (var.capacity_gb >= 10240 && var.capacity_gb <= 102400 && (var.capacity_gb - 10240) % 2560 == 0)
      ) :
      (var.capacity_gb >= 1024 && var.capacity_gb <= 10240 && var.capacity_gb % 256 == 0)
    )
    error_message = "capacity_gb no es válida para el tier: ZONAL 1024-9984 (pasos de 256) o 10240-102400 (pasos de 2560); REGIONAL 100-10239 o 10240-102400 (pasos de 2560); ENTERPRISE 1024-10240 (pasos de 256)."
  }
}

variable "share_name" {
  description = "Nombre del recurso compartido NFS (letras, dígitos y guion bajo, hasta 16 caracteres)."
  type        = string
  default     = "data"

  validation {
    condition     = can(regex("^[a-zA-Z][_a-zA-Z0-9]{0,15}$", var.share_name))
    error_message = "share_name debe empezar con letra y tener hasta 16 letras, dígitos o guiones bajos."
  }
}

variable "network" {
  description = "VPC de la Shared VPC (host), como ID o self link: projects/<host>/global/networks/<red>. La conexión es por Private Service Access."
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
  description = "ID de la llave KMS (CMEK) de la instancia; debe estar en la región de location."
  type        = string

  validation {
    condition = try(regex("^projects/[^/]+/locations/([^/]+)/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key)[0], "") == (
      var.tier == "ZONAL" ? replace(var.location, "/-[a-z]$/", "") : var.location
    )
    error_message = "kms_key debe ser projects/<p>/locations/<región>/keyRings/<k>/cryptoKeys/<llave> en la misma región que la instancia."
  }
}

variable "nfs_export_options" {
  description = "Reglas de exportación NFS (hasta 10): rangos de IP de clientes, acceso y squash. Lista vacía: todos los clientes de la VPC con lectura y escritura (valor de GCP)."
  type = list(object({
    ip_ranges   = list(string)
    access_mode = optional(string, "READ_WRITE")
    squash_mode = optional(string, "ROOT_SQUASH")
    anon_uid    = optional(number)
    anon_gid    = optional(number)
  }))
  default = []

  validation {
    condition     = length(var.nfs_export_options) <= 10
    error_message = "Filestore admite hasta 10 reglas de exportación."
  }
  validation {
    condition = alltrue([
      for o in var.nfs_export_options :
      contains(["READ_ONLY", "READ_WRITE"], o.access_mode) && contains(["NO_ROOT_SQUASH", "ROOT_SQUASH"], o.squash_mode)
    ])
    error_message = "access_mode debe ser READ_ONLY o READ_WRITE y squash_mode NO_ROOT_SQUASH o ROOT_SQUASH."
  }
  validation {
    condition = alltrue(flatten([
      for o in var.nfs_export_options : [for r in o.ip_ranges : can(cidrhost(r, 0)) || can(regex("^[0-9.]+$", r))]
    ]))
    error_message = "Cada ip_ranges debe ser una IP o un CIDR."
  }
}

variable "deletion_protection" {
  description = "Protección contra borrado de la instancia. En prod siempre debe ser true."
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
