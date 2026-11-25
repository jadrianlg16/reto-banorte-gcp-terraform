variable "project_id" {
  description = "ID del proyecto (único, ADR 0029) donde viven los trabajos de Cloud Scheduler, la instancia de Cloud SQL y el clúster de GKE."
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
  description = "Entorno: dev o qa. prod no se admite: el apagado fuera de horario es solo para entornos que no son de producción (ADR 0028)."
  type        = string

  validation {
    condition     = contains(["dev", "qa"], var.environment)
    error_message = "environment debe ser dev o qa: el apagado fuera de horario no se admite en prod (ADR 0028)."
  }
}

variable "region" {
  description = "Región de los trabajos de Cloud Scheduler (la región primaria del entorno)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region debe ser una región de GCP, por ejemplo us-central1."
  }
  validation {
    condition     = contains(keys(var.region_codes), var.region)
    error_message = "region no tiene código corto en region_codes."
  }
}

variable "region_codes" {
  description = "Mapa región → código corto que se agrega a los nombres (§4.2)."
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

variable "time_zone" {
  description = "Zona horaria (nombre IANA, por ejemplo America/Monterrey) en la que se leen start_schedule y stop_schedule."
  type        = string
  default     = "America/Mexico_City"
  nullable    = false

  validation {
    condition     = can(regex("^(UTC|[A-Za-z_]+(/[A-Za-z0-9_+-]+)+)$", var.time_zone))
    error_message = "time_zone debe ser UTC o un nombre IANA como America/Monterrey."
  }
}

variable "start_schedule" {
  description = "Cron de encendido en time_zone, con la forma \"M H * * D\" (minuto, hora y días de la semana 0-6; día del mes y mes siempre *). Por ejemplo \"0 7 * * 1-5\": 07:00 de lunes a viernes."
  type        = string
  default     = "0 7 * * 1-5"
  nullable    = false

  validation {
    condition     = can(regex("^([0-9]|[1-5][0-9]) ([0-9]|1[0-9]|2[0-3]) \\* \\* (\\*|[0-6](-[0-6])?(,[0-6](-[0-6])?)*)$", var.start_schedule))
    error_message = "start_schedule debe tener la forma \"M H * * D\": minuto 0-59, hora 0-23, día del mes y mes en *, y días de la semana * o una lista de 0-6 con rangos (por ejemplo 1-5)."
  }
}

variable "stop_schedule" {
  description = "Cron de apagado en time_zone, con la misma forma y los mismos días que start_schedule. Debe caer al menos 60 minutos después del encendido del mismo día y antes de las 23:59 menos gke_step_minutes."
  type        = string
  default     = "0 20 * * 1-5"
  nullable    = false

  validation {
    condition     = can(regex("^([0-9]|[1-5][0-9]) ([0-9]|1[0-9]|2[0-3]) \\* \\* (\\*|[0-6](-[0-6])?(,[0-6](-[0-6])?)*)$", var.stop_schedule))
    error_message = "stop_schedule debe tener la forma \"M H * * D\": minuto 0-59, hora 0-23, día del mes y mes en *, y días de la semana * o una lista de 0-6 con rangos (por ejemplo 1-5)."
  }
  validation {
    condition     = try(split(" ", var.stop_schedule)[4] == split(" ", var.start_schedule)[4], false)
    error_message = "stop_schedule y start_schedule deben tener los mismos días de la semana (el horario encendido empieza y termina el mismo día)."
  }
  validation {
    condition = try(
      (tonumber(split(" ", var.stop_schedule)[1]) * 60 + tonumber(split(" ", var.stop_schedule)[0])) -
      (tonumber(split(" ", var.start_schedule)[1]) * 60 + tonumber(split(" ", var.start_schedule)[0])) >= 60,
      false
    )
    error_message = "stop_schedule debe caer al menos 60 minutos después de start_schedule, el mismo día."
  }
  validation {
    condition     = try(tonumber(split(" ", var.stop_schedule)[1]) * 60 + tonumber(split(" ", var.stop_schedule)[0]) + var.gke_step_minutes <= 1439, false)
    error_message = "stop_schedule más gke_step_minutes debe caer el mismo día (antes de las 23:59): el segundo paso del apagado de GKE usa los mismos días."
  }
}

variable "gke_step_minutes" {
  description = "Minutos entre los dos pasos del apagado y del encendido de cada pool de GKE (apagar el autoescalado y luego llevar el pool a 0; al encender, el tamaño mínimo y luego el autoescalado)."
  type        = number
  default     = 10
  nullable    = false

  validation {
    condition     = var.gke_step_minutes >= 5 && var.gke_step_minutes <= 30 && floor(var.gke_step_minutes) == var.gke_step_minutes
    error_message = "gke_step_minutes debe ser un entero de 5 a 30."
  }
}

variable "service_account_email" {
  description = "Correo de la cuenta de servicio dedicada cuyo token OAuth usan los trabajos (la crea 1-base con el rol personalizado de permisos mínimos de 0-bootstrap). No se admite la cuenta de Compute por defecto."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]@[a-z][a-z0-9-]{4,28}[a-z0-9]\\.iam\\.gserviceaccount\\.com$", var.service_account_email))
    error_message = "service_account_email debe ser el correo de una cuenta de servicio administrada por el usuario (<id>@<proyecto>.iam.gserviceaccount.com)."
  }
}

variable "sql_instances" {
  description = "Instancias de Cloud SQL que se detienen y encienden (llave corta → nombre de la instancia en project_id). Solo primarias: una réplica de lectura no se puede detener."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k in keys(var.sql_instances) : can(regex("^[a-z][a-z0-9-]{0,14}[a-z0-9]$", k))])
    error_message = "Las llaves de sql_instances tienen de 2 a 16 caracteres: minúsculas, dígitos y guiones, empezando con letra."
  }
  validation {
    condition     = alltrue([for n in values(var.sql_instances) : can(regex("^[a-z][a-z0-9-]{0,96}[a-z0-9]$", n))])
    error_message = "Cada valor de sql_instances debe ser el nombre de una instancia de Cloud SQL (minúsculas, dígitos y guiones)."
  }
}

variable "gke_node_pools" {
  description = "Pools de nodos de GKE que se apagan y encienden (llave corta → ubicación y nombre del clúster, nombre del pool y su autoescalado por zona). Los pools deben ignorar autoscaling en Terraform (scheduled_scaling del módulo gke)."
  type = map(object({
    location       = string
    cluster        = string
    node_pool      = string
    min_node_count = number
    max_node_count = number
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.gke_node_pools) : can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", k))])
    error_message = "Las llaves de gke_node_pools tienen de 2 a 24 caracteres: minúsculas, dígitos y guiones, empezando con letra."
  }
  validation {
    condition = alltrue([
      for p in values(var.gke_node_pools) :
      can(regex("^[a-z]+-[a-z]+[0-9]+(-[a-z])?$", p.location)) && can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", p.cluster)) && can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", p.node_pool))
    ])
    error_message = "Cada pool necesita location (región o zona), cluster y node_pool con nombres válidos de GKE."
  }
  validation {
    condition = alltrue([
      for p in values(var.gke_node_pools) :
      p.min_node_count >= 0 && p.max_node_count >= 1 && p.min_node_count <= p.max_node_count &&
      floor(p.min_node_count) == p.min_node_count && floor(p.max_node_count) == p.max_node_count
    ])
    error_message = "En cada pool, min_node_count y max_node_count son enteros con 0 <= min <= max y max >= 1."
  }
  validation {
    condition     = length(var.sql_instances) + length(var.gke_node_pools) > 0
    error_message = "Sin instancias de Cloud SQL ni pools de GKE no hay nada que apagar: pasa al menos uno."
  }
}
