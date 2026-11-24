variable "project_id" {
  description = "ID del proyecto de servicio donde se crean la plantilla, el MIG y el autoescalador."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id debe ser un ID de proyecto válido (6 a 30 caracteres, minúsculas, dígitos y guiones)."
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
  description = "Entorno: dev, qa o prod."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser dev, qa o prod."
  }
}

variable "name" {
  description = "Identificador corto de la carga dentro de los nombres (<prefix>-<environment>-app-<name>-<región>)."
  type        = string
  default     = "mig"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,10}[a-z0-9]$", var.name))
    error_message = "name debe tener de 2 a 12 caracteres: minúsculas, dígitos y guiones, empezando con letra."
  }
}

variable "region" {
  description = "Región del MIG regional (primaria, o la de DR durante una conmutación)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region debe ser una región de GCP (por ejemplo, us-central1)."
  }
}

variable "region_codes" {
  description = "Mapa región → código corto que se agrega a los nombres (§4.2 del contrato)."
  type        = map(string)
  default = {
    "us-central1"         = "usc1"
    "us-east4"            = "use4"
    "northamerica-south1" = "nas1"
  }

  validation {
    condition     = alltrue([for v in values(var.region_codes) : can(regex("^[a-z0-9]{2,6}$", v))])
    error_message = "Cada código corto de región debe tener de 2 a 6 minúsculas o dígitos."
  }
}

variable "subnet" {
  description = "Self link (o ruta projects/<host>/regions/<región>/subnetworks/<subred>) de la subred compartida del proyecto host."
  type        = string

  validation {
    condition     = can(regex("(^|/)projects/[^/]+/regions/[^/]+/subnetworks/[^/]+$", var.subnet))
    error_message = "subnet debe ser un self link o una ruta projects/<proyecto>/regions/<región>/subnetworks/<subred>."
  }
}

variable "image" {
  description = "Imagen endurecida del disco de arranque: projects/<p>/global/images/<imagen> o projects/<p>/global/images/family/<familia>. Sin valor por defecto: la elige quien llama. En prod no se admiten las imágenes públicas sin endurecer de Google."
  type        = string

  validation {
    condition     = can(regex("(^|/)projects/[a-z][a-z0-9-]+/global/images/(family/)?[a-z][a-z0-9-]*$", var.image))
    error_message = "image debe tener la forma projects/<p>/global/images/<imagen> o projects/<p>/global/images/family/<familia>."
  }
  validation {
    condition = var.environment != "prod" || !contains([
      "centos-cloud", "cos-cloud", "debian-cloud", "fedora-coreos-cloud", "opensuse-cloud",
      "rhel-cloud", "rhel-sap-cloud", "rocky-linux-cloud", "suse-cloud", "suse-sap-cloud",
      "ubuntu-os-cloud", "ubuntu-os-pro-cloud", "windows-cloud", "windows-sql-cloud",
    ], try(regex("projects/([^/]+)/global/images/", var.image)[0], ""))
    error_message = "En prod la imagen debe ser endurecida (proyecto de imágenes propio o CIS), no una imagen pública base de Google."
  }
}

variable "machine_type" {
  description = "Tipo de máquina de las instancias (por ejemplo, e2-standard-2)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+-[a-z0-9-]+$", var.machine_type))
    error_message = "machine_type debe ser un tipo de máquina de Compute Engine (por ejemplo, e2-standard-2)."
  }
}

variable "min_replicas" {
  description = "Mínimo de instancias del autoescalador. En prod, al menos 2. Con business_hours es el número de VM durante el horario encendido (fuera de él, 0)."
  type        = number

  validation {
    condition     = var.min_replicas >= 1 && floor(var.min_replicas) == var.min_replicas
    error_message = "min_replicas debe ser un entero mayor o igual a 1."
  }
  validation {
    condition     = var.environment != "prod" || var.min_replicas >= 2
    error_message = "En prod min_replicas debe ser al menos 2."
  }
}

variable "max_replicas" {
  description = "Máximo de instancias del autoescalador; no puede ser menor que min_replicas."
  type        = number

  validation {
    condition     = floor(var.max_replicas) == var.max_replicas && var.max_replicas >= var.min_replicas
    error_message = "max_replicas debe ser un entero mayor o igual a min_replicas."
  }
}

variable "cpu_target" {
  description = "Uso de CPU objetivo del autoescalador (entre 0.1 y 0.9)."
  type        = number
  default     = 0.6

  validation {
    condition     = var.cpu_target >= 0.1 && var.cpu_target <= 0.9
    error_message = "cpu_target debe estar entre 0.1 y 0.9."
  }
}

variable "business_hours" {
  description = "Apagado fuera de horario (solo dev y qa, ADR 0028): programa de escalado del autoescalador con el cron de encendido (schedule), su duración en segundos (duration_sec) y su zona horaria IANA (time_zone). Durante el programa el MIG tiene min_replicas VM; fuera de él, 0. En este modo no hay señal de CPU: un autoescalador por CPU no puede bajar a 0. null: autoescalado por CPU sin horario."
  type = object({
    schedule     = string
    duration_sec = number
    time_zone    = string
  })
  default = null

  validation {
    condition     = var.environment != "prod" || var.business_hours == null
    error_message = "business_hours no se admite en prod: el apagado fuera de horario es solo para dev y qa (ADR 0028)."
  }
  validation {
    condition     = var.business_hours == null || try(length(split(" ", var.business_hours.schedule)) == 5, false)
    error_message = "business_hours.schedule debe ser un cron de cinco campos (minuto hora día-del-mes mes día-de-la-semana)."
  }
  validation {
    condition     = var.business_hours == null || try(var.business_hours.duration_sec >= 300 && floor(var.business_hours.duration_sec) == var.business_hours.duration_sec, false)
    error_message = "business_hours.duration_sec debe ser un entero de al menos 300 (la duración mínima de un programa de escalado)."
  }
  validation {
    condition     = var.business_hours == null || try(can(regex("^(UTC|[A-Za-z_]+(/[A-Za-z0-9_+-]+)+)$", var.business_hours.time_zone)), false)
    error_message = "business_hours.time_zone debe ser UTC o un nombre IANA como America/Monterrey."
  }
}

variable "cooldown_period" {
  description = "Segundos que el autoescalador espera tras iniciar una instancia antes de leer sus métricas."
  type        = number
  default     = 120

  validation {
    condition     = var.cooldown_period >= 15
    error_message = "cooldown_period debe ser al menos 15 segundos."
  }
}

variable "service_account" {
  description = "Correo de la cuenta de servicio dedicada de las instancias (uso mig de la etapa 4). No se admite la cuenta de Compute por defecto."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]@[a-z][a-z0-9-]{4,28}[a-z0-9]\\.iam\\.gserviceaccount\\.com$", var.service_account))
    error_message = "service_account debe ser el correo de una cuenta de servicio administrada por el usuario (<id>@<proyecto>.iam.gserviceaccount.com)."
  }
}

variable "kms_key" {
  description = "ID de la llave KMS (uso compute) que cifra los discos de arranque. Debe estar en la misma región que el MIG."
  type        = string

  validation {
    condition     = can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key))
    error_message = "kms_key debe tener la forma projects/<p>/locations/<l>/keyRings/<k>/cryptoKeys/<c>."
  }
}

variable "disk_size_gb" {
  description = "Tamaño del disco de arranque en GB."
  type        = number
  default     = 50

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb debe ser al menos 10 GB."
  }
}

variable "disk_type" {
  description = "Tipo del disco de arranque."
  type        = string
  default     = "pd-balanced"

  validation {
    condition     = contains(["pd-standard", "pd-balanced", "pd-ssd"], var.disk_type)
    error_message = "disk_type debe ser pd-standard, pd-balanced o pd-ssd."
  }
}

variable "named_ports" {
  description = "Puertos con nombre del grupo (nombre → puerto) que usa el servicio de backend del balanceador."
  type        = map(number)
  default     = { http = 80 }
  nullable    = false

  validation {
    condition     = length(var.named_ports) > 0
    error_message = "named_ports debe tener al menos un puerto."
  }
  validation {
    condition     = alltrue([for n, p in var.named_ports : can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", n)) && p >= 1 && p <= 65535])
    error_message = "Cada puerto con nombre necesita un nombre válido (minúsculas) y un puerto entre 1 y 65535."
  }
}

variable "health_check" {
  description = "Verificación de salud para la autocuración: protocolo (HTTP, HTTPS o TCP), puerto, ruta (HTTP/HTTPS), umbrales y retraso inicial."
  type = object({
    protocol            = optional(string, "HTTP")
    port                = optional(number, 80)
    request_path        = optional(string, "/healthz")
    check_interval_sec  = optional(number, 10)
    timeout_sec         = optional(number, 5)
    healthy_threshold   = optional(number, 2)
    unhealthy_threshold = optional(number, 3)
    initial_delay_sec   = optional(number, 300)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["HTTP", "HTTPS", "TCP"], var.health_check.protocol)
    error_message = "health_check.protocol debe ser HTTP, HTTPS o TCP."
  }
  validation {
    condition     = var.health_check.port >= 1 && var.health_check.port <= 65535
    error_message = "health_check.port debe estar entre 1 y 65535."
  }
  validation {
    condition     = startswith(var.health_check.request_path, "/")
    error_message = "health_check.request_path debe empezar con /."
  }
  validation {
    condition     = var.health_check.timeout_sec <= var.health_check.check_interval_sec
    error_message = "health_check.timeout_sec no puede ser mayor que check_interval_sec."
  }
  validation {
    condition     = var.health_check.initial_delay_sec >= 0 && var.health_check.initial_delay_sec <= 3600
    error_message = "health_check.initial_delay_sec debe estar entre 0 y 3600."
  }
}

variable "distribution_zones" {
  description = "Zonas de la región donde se reparten las instancias. Vacío: GCP elige tres zonas."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for z in var.distribution_zones : startswith(z, "${var.region}-")])
    error_message = "Todas las zonas de distribution_zones deben pertenecer a region."
  }
}

variable "network_tags" {
  description = "Etiquetas de red de las instancias (las reglas de firewall del spoke usan etiquetas seguras; ver resource_manager_tags)."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "resource_manager_tags" {
  description = "Etiquetas seguras de las instancias (tagKeys/<id> → tagValues/<id>), por ejemplo la de lb_backend de la etapa 3."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for k, v in var.resource_manager_tags : can(regex("^tagKeys/[0-9]+$", k)) && can(regex("^tagValues/[0-9]+$", v))
    ])
    error_message = "resource_manager_tags debe mapear tagKeys/<id> → tagValues/<id>."
  }
}

variable "metadata" {
  description = "Metadatos adicionales de las instancias (por ejemplo, startup-script). No pueden cambiar enable-oslogin, block-project-ssh-keys ni serial-port-enable."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = length(setintersection(keys(var.metadata), ["enable-oslogin", "block-project-ssh-keys", "serial-port-enable", "ssh-keys"])) == 0
    error_message = "metadata no puede definir enable-oslogin, block-project-ssh-keys, serial-port-enable ni ssh-keys: son fijos en el módulo."
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
