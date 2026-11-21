# Entradas de §7.5 (nombres exactos de §4.4) y variables internas de la raíz.

variable "org_id" {
  description = "ID numérico de la organización. Se comprueba que la carpeta del entorno (estado de 1-org) pertenezca a ella."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{6,20}$", var.org_id))
    error_message = "org_id debe ser el ID numérico de la organización."
  }
}

variable "billing_account" {
  description = "Cuenta de facturación de los proyectos de servicio (formato XXXXXX-XXXXXX-XXXXXX)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$", var.billing_account))
    error_message = "billing_account debe tener la forma XXXXXX-XXXXXX-XXXXXX (hexadecimal en mayúsculas)."
  }
}

variable "prefix" {
  description = "Prefijo de la empresa en los nombres (por ejemplo, bnt)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.prefix))
    error_message = "prefix debe tener de 2 a 6 caracteres: minúsculas y dígitos, empezando con letra."
  }
}

variable "project_suffix" {
  description = "Sufijo opcional para que los IDs de proyecto sean únicos a nivel mundial; se agrega al final con un guion. Vacío: sin sufijo."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]{0,8}$", var.project_suffix))
    error_message = "project_suffix: hasta 8 caracteres en minúsculas o dígitos, sin guiones."
  }
}

variable "environment" {
  description = "Entorno de esta raíz: dev, qa o prod. Debe coincidir con el prefijo del backend."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser dev, qa o prod."
  }
}

variable "primary_region" {
  description = "Región primaria (ADR 0002). Debe ser una ubicación de kms_key_ids en el estado de 2-security."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.primary_region))
    error_message = "primary_region debe ser una región de GCP, por ejemplo us-central1."
  }
}

variable "dr_region" {
  description = "Región de DR (ADR 0002), distinta de la primaria."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.dr_region))
    error_message = "dr_region debe ser una región de GCP, por ejemplo us-east4."
  }
  validation {
    condition     = var.dr_region != var.primary_region
    error_message = "dr_region debe ser distinta de primary_region."
  }
}

variable "applications" {
  description = <<-EOT
    Aplicaciones del entorno: un proyecto de servicio por llave (<prefix>-<environment>-<llave>).
    - apis: APIs adicionales a las base que la raíz siempre habilita (ver README).
    - secrets: nombres cortos de secretos de 2-security (secret_ids[environment]) que leen las
      cuentas workload y run de la aplicación.
    La llave forma también las cuentas de servicio <prefix>-<environment>-<llave>-<uso>, que no
    pueden pasar de 30 caracteres (ADR 0017).
  EOT
  type = map(object({
    apis    = optional(set(string), [])
    secrets = optional(set(string), [])
  }))
  default  = { app = {} }
  nullable = false

  validation {
    condition     = length(var.applications) > 0
    error_message = "applications debe tener al menos una aplicación."
  }
  validation {
    # Mismo conjunto que application de 5-workloads. 8 caracteres como máximo: con el prefijo
    # más largo (6) y prod, <prefix>-prod-<app>-gke-nodes llega a 30 (límite del ID de cuenta
    # de servicio) y <prefix>-prod-<app>-<project_suffix de 8> a 30 (ID de proyecto).
    condition     = alltrue([for k in keys(var.applications) : can(regex("^[a-z][a-z0-9]{1,7}$", k))])
    error_message = "Cada llave de applications debe tener de 2 a 8 caracteres: minúsculas y dígitos, empezando con letra."
  }
  validation {
    # El uso más largo es gke-nodes (9 caracteres): <prefix>-<environment>-<app>-gke-nodes.
    condition     = alltrue([for k in keys(var.applications) : length("${var.prefix}-${var.environment}-${k}-gke-nodes") <= 30])
    error_message = "Llave de applications demasiado larga: <prefix>-<environment>-<app>-gke-nodes no puede pasar de 30 caracteres (límite del ID de cuenta de servicio, ADR 0017)."
  }
  validation {
    condition = alltrue(flatten([
      for a in values(var.applications) : [for api in a.apis : can(regex("^[a-z0-9][a-z0-9.-]*\\.googleapis\\.com$", api))]
    ]))
    error_message = "Cada API debe ser un nombre de servicio como pubsub.googleapis.com."
  }
  validation {
    condition = alltrue(flatten([
      for a in values(var.applications) : [for s in a.secrets : can(regex("^[a-z][a-z0-9-]*$", s))]
    ]))
    error_message = "Cada secreto es el nombre corto de secret_names de 2-security (minúsculas, dígitos y guiones)."
  }
}

variable "workloads_service_account" {
  description = "Correo de la cuenta de servicio del pipeline de la etapa 5 (<prefix>-tf-5-workloads). Debe ser igual a stage_service_accounts[\"5-workloads\"] de las salidas de 0-bootstrap. Recibe el uso de subredes, el uso de etiquetas seguras y actAs sobre las cuentas de ejecución para crear las cargas. Llega por variable porque esta etapa no lee el estado de 0-bootstrap (§6.1)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]@[a-z][a-z0-9-]{4,28}[a-z0-9]\\.iam\\.gserviceaccount\\.com$", var.workloads_service_account))
    error_message = "workloads_service_account debe ser el correo de una cuenta de servicio (<id>@<proyecto>.iam.gserviceaccount.com)."
  }
  validation {
    condition     = startswith(var.workloads_service_account, "${var.prefix}-tf-5-workloads@")
    error_message = "workloads_service_account debe ser stage_service_accounts[\"5-workloads\"] de 0-bootstrap (<prefix>-tf-5-workloads@<proyecto semilla>.iam.gserviceaccount.com)."
  }
}

variable "deletion_policy" {
  description = "deletion_policy de los proyectos de servicio: PREVENT (falla al destruir), ABANDON o DELETE. En prod solo PREVENT (lo exige project-factory); en dev se puede usar DELETE para el destroy de prueba."
  type        = string
  default     = "PREVENT"
  nullable    = false

  validation {
    condition     = contains(["PREVENT", "ABANDON", "DELETE"], var.deletion_policy)
    error_message = "deletion_policy debe ser PREVENT, ABANDON o DELETE."
  }
}

variable "labels" {
  description = "Etiquetas comunes de §4.3. Deben traer owner y cost_center; env y managed_by los pone la raíz y app es la llave de cada aplicación."
  type        = map(string)
  nullable    = false

  validation {
    condition     = alltrue([for k in ["owner", "cost_center"] : contains(keys(var.labels), k)])
    error_message = "labels debe traer owner y cost_center."
  }
  validation {
    condition     = alltrue([for v in values(var.labels) : can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "Los valores de etiquetas van en minúsculas, dígitos, guion o guion bajo (ADR 0016)."
  }
}

variable "state_bucket" {
  description = "Bucket del estado remoto (salida state_bucket de 0-bootstrap). Se usa para leer 1-org, 2-security y 3-networks/<environment>."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", var.state_bucket))
    error_message = "state_bucket debe ser un nombre de bucket válido."
  }
}
