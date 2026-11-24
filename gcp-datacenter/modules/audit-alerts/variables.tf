variable "project_id" {
  description = "ID del proyecto donde se crean las métricas de log, las alertas y el canal. Los detectores de Security Command Center revisan cada proyecto por separado: hace falta una instancia por proyecto."
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
  description = "Entorno del proyecto según la convención de nombres: bootstrap, common, dev, qa o prod."
  type        = string

  validation {
    condition     = contains(["bootstrap", "common", "dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser bootstrap, common, dev, qa o prod."
  }
}

variable "notification_email" {
  description = "Correo del grupo security_admins (groups.security_admins de la etapa 1) que recibe las alertas. Sin valor por defecto: llega de la etapa."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", var.notification_email))
    error_message = "notification_email debe ser un correo válido (el del grupo security_admins)."
  }
}

variable "alignment_period" {
  description = "Ventana en la que se suman los eventos de cada métrica antes de compararlos con el umbral 0 (de 60s a 3600s). Por defecto 10 minutos: la documentación de Cloud Logging recomienda una ventana que cubra el retraso de ingesta de las métricas de log (hasta 10 minutos)."
  type        = string
  default     = "600s"

  validation {
    condition     = can(regex("^[0-9]{1,4}s$", var.alignment_period)) ? tonumber(trimsuffix(var.alignment_period, "s")) >= 60 && tonumber(trimsuffix(var.alignment_period, "s")) <= 3600 : false
    error_message = "alignment_period debe ser un número de segundos con sufijo s, entre 60s y 3600s (por ejemplo 600s)."
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
