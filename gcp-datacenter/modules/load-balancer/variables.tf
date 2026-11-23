variable "project_id" {
  description = "ID del proyecto de servicio donde vive el balanceador (ADR 0005)."
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

variable "name" {
  description = "Nombre corto del balanceador (por ejemplo, la aplicación); forma parte del nombre de cada recurso."
  type        = string
  default     = "web"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,14}$", var.name))
    error_message = "name debe tener de 1 a 15 caracteres: minúsculas, dígitos o guion, empezando con letra."
  }
}

variable "type" {
  description = "\"external\": balanceador de aplicaciones externo global (EXTERNAL_MANAGED). \"internal\": balanceador de aplicaciones interno regional (INTERNAL_MANAGED) en la Shared VPC."
  type        = string

  validation {
    condition     = contains(["external", "internal"], var.type)
    error_message = "type debe ser \"external\" o \"internal\"."
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

variable "backends" {
  description = <<-EOT
    Servicios de backend. Llave: nombre corto del servicio. Cada uno lleva:
    - groups: grupos de backend activos en operación normal (grupo de instancias de compute-mig,
      NEG serverless de cloud-run o NEG de GKE), con su modo de balanceo opcional.
    - dr_groups: grupos equivalentes en la región de DR; se usan cuando dr_active = true.
    - serverless: true para NEG serverless (sin verificación de salud, port_name ni timeout).
    - health_check_id: verificación de salud existente (global para "external", regional para
      "internal"), o health_check para que el módulo la cree. Una de las dos si no es serverless.
    - paths: rutas que el mapa de URL envía a este servicio (por ejemplo ["/api/*"]).
    - log_sample_rate: fracción de solicitudes registradas (mayor que 0; el registro no se apaga).
  EOT
  type = map(object({
    description = optional(string)
    protocol    = optional(string, "HTTP")
    port_name   = optional(string, "http")
    timeout_sec = optional(number, 30)
    serverless  = optional(bool, false)
    groups = list(object({
      group                 = string
      balancing_mode        = optional(string)
      capacity_scaler       = optional(number, 1)
      max_utilization       = optional(number)
      max_rate_per_instance = optional(number)
      max_rate_per_endpoint = optional(number)
    }))
    dr_groups = optional(list(object({
      group                 = string
      balancing_mode        = optional(string)
      capacity_scaler       = optional(number, 1)
      max_utilization       = optional(number)
      max_rate_per_instance = optional(number)
      max_rate_per_endpoint = optional(number)
    })), [])
    health_check_id = optional(string)
    health_check = optional(object({
      protocol            = optional(string, "HTTP")
      port                = optional(number)
      request_path        = optional(string, "/healthz")
      check_interval_sec  = optional(number, 10)
      timeout_sec         = optional(number, 5)
      healthy_threshold   = optional(number, 2)
      unhealthy_threshold = optional(number, 3)
    }))
    paths                           = optional(list(string), [])
    log_sample_rate                 = optional(number, 1)
    connection_draining_timeout_sec = optional(number, 300)
  }))

  validation {
    condition     = length(var.backends) > 0
    error_message = "backends debe tener al menos un servicio."
  }
  validation {
    condition     = alltrue([for k in keys(var.backends) : can(regex("^[a-z][a-z0-9-]{0,19}$", k))])
    error_message = "Las llaves de backends deben tener de 1 a 20 caracteres: minúsculas, dígitos o guion, empezando con letra."
  }
  validation {
    condition     = alltrue([for b in values(var.backends) : contains(["HTTP", "HTTPS", "HTTP2"], b.protocol)])
    error_message = "protocol debe ser HTTP, HTTPS o HTTP2."
  }
  validation {
    condition     = alltrue([for b in values(var.backends) : length(b.groups) > 0])
    error_message = "Cada servicio de backend necesita al menos un grupo en groups."
  }
  validation {
    condition = alltrue([
      for b in values(var.backends) :
      b.serverless ? (b.health_check_id == null && b.health_check == null) : ((b.health_check_id == null) != (b.health_check == null))
    ])
    error_message = "Un backend serverless no lleva verificación de salud; cualquier otro lleva exactamente una: health_check_id o health_check."
  }
  validation {
    condition = alltrue(flatten([
      for b in values(var.backends) : [
        for g in concat(b.groups, b.dr_groups) : contains(["UTILIZATION", "RATE", "CONNECTION"], g.balancing_mode == null ? "UTILIZATION" : g.balancing_mode)
      ]
    ]))
    error_message = "balancing_mode debe ser UTILIZATION, RATE o CONNECTION."
  }
  validation {
    condition = alltrue(flatten([
      for b in values(var.backends) : [for g in concat(b.groups, b.dr_groups) : g.capacity_scaler >= 0 && g.capacity_scaler <= 1]
    ]))
    error_message = "capacity_scaler debe estar entre 0 y 1."
  }
  validation {
    condition     = alltrue([for b in values(var.backends) : b.log_sample_rate > 0 && b.log_sample_rate <= 1])
    error_message = "log_sample_rate debe ser mayor que 0 y menor o igual a 1: el registro del balanceador no se apaga."
  }
  validation {
    condition = alltrue([
      for b in values(var.backends) : b.health_check == null || contains(["HTTP", "HTTPS", "HTTP2"], try(b.health_check.protocol, "HTTP"))
    ])
    error_message = "health_check.protocol debe ser HTTP, HTTPS o HTTP2."
  }
  validation {
    condition     = alltrue(flatten([for b in values(var.backends) : [for p in b.paths : startswith(p, "/")]]))
    error_message = "Cada ruta de paths debe empezar con \"/\"."
  }
}

variable "default_backend" {
  description = "Llave de backends que atiende las solicitudes que no coinciden con ninguna ruta de paths."
  type        = string

  validation {
    condition     = contains(keys(var.backends), var.default_backend)
    error_message = "default_backend debe ser una llave de backends."
  }
}

variable "dr_active" {
  description = "Conmutación a DR: true hace que cada servicio de backend use dr_groups en lugar de groups (§7.6)."
  type        = bool
  default     = false

  validation {
    condition     = !var.dr_active || alltrue([for b in values(var.backends) : length(b.dr_groups) > 0])
    error_message = "Con dr_active = true, cada servicio de backend necesita dr_groups."
  }
}

variable "domain_names" {
  description = "Dominios del certificado administrado por Google. Obligatorio en \"external\"; en \"internal\" se usa si no se pasan certificate_manager_certificates."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for d in var.domain_names : can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", d))])
    error_message = "Cada dominio debe ser un nombre DNS válido en minúsculas, sin comodines ni punto final."
  }
  validation {
    condition     = var.type != "external" || (length(var.domain_names) > 0 && length(var.domain_names) <= 100)
    error_message = "El balanceador externo necesita de 1 a 100 dominios para el certificado administrado."
  }
  validation {
    condition     = var.type != "internal" || length(var.domain_names) > 0 || length(var.certificate_manager_certificates) > 0
    error_message = "El balanceador interno necesita domain_names o certificate_manager_certificates."
  }
}

variable "security_policy" {
  description = "self_link de la política de Cloud Armor (salida policy_self_link del módulo cloud-armor). Obligatoria en \"external\"; no aplica en \"internal\"."
  type        = string
  default     = null

  validation {
    condition     = var.type != "external" || (var.security_policy != null && var.security_policy != "")
    error_message = "El balanceador externo exige una política de Cloud Armor en security_policy."
  }
  validation {
    condition     = var.type != "internal" || var.security_policy == null
    error_message = "security_policy no aplica al balanceador interno; déjala en null."
  }
}

variable "ssl_policy_profile" {
  description = "Perfil de la política SSL (siempre con TLS 1.2 como mínimo): MODERN o RESTRICTED."
  type        = string
  default     = "MODERN"

  validation {
    condition     = contains(["MODERN", "RESTRICTED"], var.ssl_policy_profile)
    error_message = "ssl_policy_profile debe ser MODERN o RESTRICTED."
  }
}

variable "region" {
  description = "Región del balanceador interno (uno por región: sus backends deben estar en esa región). No aplica en \"external\"."
  type        = string
  default     = null

  validation {
    condition     = var.type != "internal" || var.region != null
    error_message = "El balanceador interno necesita region."
  }
  validation {
    condition     = var.region == null || contains(keys(var.region_short_codes), coalesce(var.region, "-"))
    error_message = "region debe ser una llave de region_short_codes."
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

variable "network" {
  description = "self_link de la VPC de la Shared VPC (salida network_self_link de la etapa 3). Obligatoria en \"internal\"."
  type        = string
  default     = null

  validation {
    condition     = var.type != "internal" || var.network != null
    error_message = "El balanceador interno necesita network."
  }
}

variable "subnet" {
  description = "self_link de la subred de la Shared VPC donde se reserva la IP interna (subred app de la región activa). Obligatoria en \"internal\". La subred proxy-only de esa región debe existir antes."
  type        = string
  default     = null

  validation {
    condition     = var.type != "internal" || var.subnet != null
    error_message = "El balanceador interno necesita subnet."
  }
}

variable "internal_ip_address" {
  description = "IP interna fija opcional para el balanceador interno, dentro de subnet. null: la asigna GCP."
  type        = string
  default     = null

  validation {
    condition     = var.internal_ip_address == null || can(cidrhost("${coalesce(var.internal_ip_address, "0.0.0.0")}/32", 0))
    error_message = "internal_ip_address debe ser una dirección IPv4."
  }
}

variable "certificate_manager_certificates" {
  description = "Solo \"internal\": IDs de certificados de Certificate Manager regionales ya existentes (por ejemplo, emitidos por una CA privada para dominios internos). Vacío: el módulo crea un certificado administrado por Google con autorización DNS para domain_names."
  type        = list(string)
  default     = []

  validation {
    condition     = var.type == "internal" || length(var.certificate_manager_certificates) == 0
    error_message = "certificate_manager_certificates solo aplica al balanceador interno."
  }
}
