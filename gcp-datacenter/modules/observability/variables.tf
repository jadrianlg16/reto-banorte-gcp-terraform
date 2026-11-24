variable "project_id" {
  description = "ID del proyecto donde se crean canales, verificaciones, alertas, tablero y SLO (el proyecto único, ADR 0029)."
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

variable "notification_emails" {
  description = "Correos (de preferencia listas de grupo) que reciben las alertas. Sin valor por defecto: llegan desde tfvars de la etapa."
  type        = list(string)

  validation {
    condition     = length(var.notification_emails) > 0
    error_message = "notification_emails debe tener al menos un correo: una alerta sin destinatario no sirve."
  }
  validation {
    condition     = alltrue([for e in var.notification_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[a-z]{2,}$", lower(e)))])
    error_message = "Cada elemento de notification_emails debe ser un correo válido."
  }
  validation {
    condition     = length(distinct([for e in var.notification_emails : lower(e)])) == length(var.notification_emails)
    error_message = "notification_emails no debe repetir correos."
  }
}

variable "extra_notification_channel_ids" {
  description = "Canales de notificación que ya existen (projects/<proyecto>/notificationChannels/<id>) y que reciben también todas las alertas del módulo, además de los de notification_emails. En el proyecto único, los de 1-base (salida notification_channel_ids). Vacío por defecto."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.extra_notification_channel_ids : can(regex("^projects/[^/]+/notificationChannels/[^/]+$", c))])
    error_message = "Cada canal debe tener la forma projects/<proyecto>/notificationChannels/<id>."
  }
  validation {
    condition     = length(distinct(var.extra_notification_channel_ids)) == length(var.extra_notification_channel_ids)
    error_message = "extra_notification_channel_ids no debe repetir canales."
  }
}

variable "uptime_checks" {
  description = <<-EOT
    Verificaciones de disponibilidad HTTP(S). Llave: nombre corto. host: dominio público a revisar
    (por ejemplo, uno de domain_names del balanceador). Cada verificación genera además una alerta
    que avisa cuando falla desde más de una región.
  EOT
  type = map(object({
    host             = string
    path             = optional(string, "/")
    port             = optional(number, 443)
    use_ssl          = optional(bool, true)
    validate_ssl     = optional(bool, true)
    period           = optional(string, "60s")
    timeout          = optional(string, "10s")
    selected_regions = optional(list(string), [])
    content_match    = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.uptime_checks) : can(regex("^[a-z][a-z0-9-]{0,19}$", k))])
    error_message = "Las llaves de uptime_checks deben tener de 1 a 20 caracteres: minúsculas, dígitos o guion."
  }
  validation {
    condition     = alltrue([for c in values(var.uptime_checks) : can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", c.host))])
    error_message = "host debe ser un nombre DNS válido en minúsculas, sin esquema ni ruta."
  }
  validation {
    condition     = alltrue([for c in values(var.uptime_checks) : contains(["60s", "300s", "600s", "900s"], c.period)])
    error_message = "period debe ser 60s, 300s, 600s o 900s."
  }
  validation {
    condition     = alltrue([for c in values(var.uptime_checks) : can(regex("^([1-9]|[1-5][0-9]|60)s$", c.timeout))])
    error_message = "timeout debe estar entre 1s y 60s."
  }
  validation {
    condition     = alltrue([for c in values(var.uptime_checks) : startswith(c.path, "/")])
    error_message = "path debe empezar con \"/\"."
  }
  validation {
    condition = alltrue(flatten([
      for c in values(var.uptime_checks) : [for r in c.selected_regions : contains(["USA", "USA_OREGON", "USA_IOWA", "USA_VIRGINIA", "EUROPE", "SOUTH_AMERICA", "ASIA_PACIFIC"], r)]
    ]))
    error_message = "selected_regions acepta USA, USA_OREGON, USA_IOWA, USA_VIRGINIA, EUROPE, SOUTH_AMERICA o ASIA_PACIFIC."
  }
  validation {
    condition     = alltrue([for c in values(var.uptime_checks) : length(c.selected_regions) == 0 || length(c.selected_regions) >= 3])
    error_message = "selected_regions vacío (todas) o con al menos 3 regiones: Cloud Monitoring lo exige."
  }
}

variable "slo_target" {
  description = "Objetivo del SLO de disponibilidad por solicitudes del balanceador (la especificación pide 99.9 %)."
  type        = number
  default     = 0.999

  validation {
    condition     = var.slo_target >= 0.999 && var.slo_target < 1
    error_message = "slo_target debe estar entre 0.999 (99.9 %, mínimo de la especificación) y menos de 1."
  }
}

variable "slo_rolling_period_days" {
  description = "Ventana móvil del SLO, en días."
  type        = number
  default     = 28

  validation {
    condition     = var.slo_rolling_period_days >= 1 && var.slo_rolling_period_days <= 30 && floor(var.slo_rolling_period_days) == var.slo_rolling_period_days
    error_message = "slo_rolling_period_days debe ser un entero de 1 a 30."
  }
}

variable "lb_url_map_name" {
  description = "Nombre del mapa de URL del balanceador externo (salida url_map_name de load-balancer) para filtrar el SLO, la alerta de 5xx y el tablero. null: todos los balanceadores del entorno (mapas de URL que empiezan con <prefix>-<environment>-)."
  type        = string
  default     = null

  validation {
    condition     = var.lb_url_map_name == null || can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", coalesce(var.lb_url_map_name, "x")))
    error_message = "lb_url_map_name debe ser un nombre de recurso de Compute válido."
  }
}

variable "lb_5xx_ratio_threshold" {
  description = "Fracción de respuestas 5xx del balanceador sobre el total que dispara la alerta."
  type        = number
  default     = 0.05

  validation {
    condition     = var.lb_5xx_ratio_threshold > 0 && var.lb_5xx_ratio_threshold < 1
    error_message = "lb_5xx_ratio_threshold debe estar entre 0 y 1 (sin incluirlos)."
  }
}

variable "cpu_utilization_threshold" {
  description = "Uso de CPU (0 a 1) sostenido 5 minutos que dispara la alerta de saturación (VM y nodos de GKE)."
  type        = number
  default     = 0.85

  validation {
    condition     = var.cpu_utilization_threshold > 0 && var.cpu_utilization_threshold < 1
    error_message = "cpu_utilization_threshold debe estar entre 0 y 1 (sin incluirlos)."
  }
}

variable "memory_utilization_threshold" {
  description = "Uso de memoria (0 a 1) sostenido 5 minutos que dispara la alerta de saturación (VM con Ops Agent y nodos de GKE)."
  type        = number
  default     = 0.9

  validation {
    condition     = var.memory_utilization_threshold > 0 && var.memory_utilization_threshold < 1
    error_message = "memory_utilization_threshold debe estar entre 0 y 1 (sin incluirlos)."
  }
}

variable "sql_replica_lag_threshold_seconds" {
  description = "Retraso de la réplica de Cloud SQL (segundos) que dispara la alerta. Debe quedar por debajo del RPO de 15 minutos (900 s) para avisar antes de incumplirlo."
  type        = number
  default     = 300

  validation {
    condition     = var.sql_replica_lag_threshold_seconds > 0 && var.sql_replica_lag_threshold_seconds < 900
    error_message = "sql_replica_lag_threshold_seconds debe ser mayor que 0 y menor que 900 (RPO de 15 minutos)."
  }
}
