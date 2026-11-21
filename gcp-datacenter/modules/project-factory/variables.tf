variable "prefix" {
  description = "Prefijo de la empresa en los nombres (por ejemplo, bnt)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.prefix))
    error_message = "prefix: de 2 a 6 caracteres, minúsculas y dígitos, empieza con letra."
  }
}

variable "environment" {
  description = "Entorno del proyecto según la convención de nombres: bootstrap, common, dev, qa o prod."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["bootstrap", "common", "dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser bootstrap, common, dev, qa o prod."
  }
}

variable "name" {
  description = "Parte del dominio y recurso del ID del proyecto (por ejemplo, net-hub, logging, seed, net-spoke, app). El ID queda <prefix>-<environment>-<name>[-<project_suffix>]."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name))
    error_message = "name: minúsculas, dígitos y guiones; empieza con letra y no termina en guion."
  }
}

variable "project_suffix" {
  description = "Sufijo opcional para que el ID sea único a nivel mundial; se agrega al final con un guion. Vacío: sin sufijo."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]{0,8}$", var.project_suffix))
    error_message = "project_suffix: hasta 8 caracteres en minúsculas o dígitos, sin guiones."
  }
}

variable "display_name" {
  description = "Nombre visible del proyecto. Si es null se usa el ID del proyecto."
  type        = string
  default     = null

  validation {
    condition     = var.display_name == null || can(regex("^[A-Za-z0-9 '\"!-]{4,30}$", var.display_name))
    error_message = "display_name: de 4 a 30 caracteres (letras, dígitos, espacio, guion, comillas o !)."
  }
}

variable "folder_id" {
  description = "Carpeta donde se crea el proyecto: \"folders/<número>\" o solo el número."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^(folders/)?[0-9]+$", var.folder_id))
    error_message = "folder_id debe ser \"folders/<número>\" o el número de la carpeta."
  }
}

variable "billing_account" {
  description = "Cuenta de facturación que se asocia al proyecto (formato XXXXXX-XXXXXX-XXXXXX)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$", var.billing_account))
    error_message = "billing_account debe tener la forma XXXXXX-XXXXXX-XXXXXX (hexadecimal en mayúsculas)."
  }
}

variable "apis" {
  description = "APIs que se habilitan en el proyecto (por ejemplo, container.googleapis.com). compute.googleapis.com se agrega sola si el proyecto participa en Shared VPC."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.apis : can(regex("^[a-z0-9][a-z0-9.-]*\\.googleapis\\.com$", a))])
    error_message = "Cada API debe ser un nombre de servicio como container.googleapis.com."
  }
}

variable "disable_services_on_destroy" {
  description = "Si es true, al quitar una API de la lista se deshabilita en el proyecto. Por defecto false: deshabilitar una API puede romper recursos que no administra este módulo."
  type        = bool
  default     = false
  nullable    = false
}

variable "shared_vpc_host" {
  description = "Si es true, el proyecto se habilita como host de Shared VPC."
  type        = bool
  default     = false
  nullable    = false
}

variable "shared_vpc_host_project" {
  description = "ID del proyecto host de Shared VPC al que se une este proyecto como servicio. null: no se une. Excluyente con shared_vpc_host."
  type        = string
  default     = null

  validation {
    condition     = var.shared_vpc_host_project == null || can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.shared_vpc_host_project))
    error_message = "shared_vpc_host_project debe ser un ID de proyecto válido (6 a 30 caracteres)."
  }
}

variable "deletion_policy" {
  description = "Qué hace Terraform al destruir el proyecto: PREVENT (falla), ABANDON (lo deja en GCP) o DELETE (lo borra). En bootstrap, common y prod solo se admite PREVENT."
  type        = string
  default     = "PREVENT"
  nullable    = false

  validation {
    condition     = contains(["PREVENT", "ABANDON", "DELETE"], var.deletion_policy)
    error_message = "deletion_policy debe ser PREVENT, ABANDON o DELETE."
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
