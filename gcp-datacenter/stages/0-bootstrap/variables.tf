variable "org_id" {
  description = "ID numérico de la organización de GCP (sin el prefijo organizations/)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{6,20}$", var.org_id))
    error_message = "org_id debe ser el número de la organización, sin organizations/."
  }
}

variable "billing_account" {
  description = "Cuenta de facturación del proyecto semilla y de los proyectos que crean las etapas (formato XXXXXX-XXXXXX-XXXXXX)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$", var.billing_account))
    error_message = "billing_account debe tener la forma XXXXXX-XXXXXX-XXXXXX (hexadecimal en mayúsculas)."
  }
}

variable "prefix" {
  description = "Prefijo de la empresa en todos los nombres (§4.2), por ejemplo bnt."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.prefix))
    error_message = "prefix debe tener de 2 a 6 caracteres: minúsculas y dígitos, empezando con letra."
  }
}

variable "project_suffix" {
  description = "Sufijo opcional que se agrega al ID del proyecto semilla y al nombre del bucket de estado para que sean únicos a nivel mundial. Vacío: sin sufijo."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]{0,8}$", var.project_suffix))
    error_message = "project_suffix: hasta 8 caracteres en minúsculas o dígitos, sin guiones."
  }
}

variable "primary_region" {
  description = "Región primaria (ADR 0002). La etapa 0 no crea recursos regionales: el bucket de estado y su llave van en state_bucket_location para sobrevivir a la caída de esta región."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.primary_region))
    error_message = "primary_region debe ser una región, por ejemplo us-central1."
  }
}

variable "location_short_codes" {
  description = "Mapa ubicación → código corto que se agrega a los nombres de recursos con ubicación (§4.2). Debe incluir la ubicación de KMS del estado (lower(state_bucket_location): us, eu o asia)."
  type        = map(string)
  default = {
    "us-central1"         = "usc1"
    "us-east4"            = "use4"
    "northamerica-south1" = "nas1"
    "us"                  = "us"
    "eu"                  = "eu"
    "asia"                = "asia"
  }
  nullable = false

  validation {
    condition     = alltrue([for v in values(var.location_short_codes) : can(regex("^[a-z0-9]{2,6}$", v))])
    error_message = "Cada código corto debe tener de 2 a 6 minúsculas o dígitos."
  }
}

variable "state_bucket_location" {
  description = "Multirregión del bucket de estado y de su llave KMS: US, EU o ASIA. Con state_bucket_dual_regions vacío el bucket es multirregional; si no, es de doble región configurable dentro de esta multirregión. La llave va en la ubicación de KMS homónima (us, eu, asia), como exige la CMEK de Cloud Storage. Así el estado y la llave sobreviven a la caída de primary_region (runbook de conmutación a DR). La ubicación de un bucket no se cambia después de crearlo."
  type        = string
  default     = "US"
  nullable    = false

  validation {
    condition     = contains(["US", "EU", "ASIA"], var.state_bucket_location)
    error_message = "state_bucket_location debe ser US, EU o ASIA (multirregión, en mayúsculas)."
  }
}

variable "state_bucket_dual_regions" {
  description = "Opcional: las dos regiones de un bucket de estado de doble región configurable (por ejemplo [\"us-central1\", \"us-east4\"], primaria y DR del ADR 0002), dentro de state_bucket_location; lleva replicación turbo (RPO de 15 minutos). Vacío (por defecto): bucket multirregional."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.state_bucket_dual_regions) == 0 || (length(var.state_bucket_dual_regions) == 2 && length(distinct(var.state_bucket_dual_regions)) == 2)
    error_message = "state_bucket_dual_regions debe estar vacío o tener exactamente dos regiones distintas."
  }
  validation {
    condition     = alltrue([for r in var.state_bucket_dual_regions : can(regex("^[a-z]+-[a-z]+[0-9]+$", r))])
    error_message = "Cada elemento de state_bucket_dual_regions debe ser una región, por ejemplo us-central1."
  }
}

variable "github_repository" {
  description = "Repositorio de GitHub (<dueño>/<repositorio>) autorizado por Workload Identity Federation (§6.3). Solo es informativo (descripción del proveedor, atributo attribute.repository): la confianza se basa en github_repository_id y github_repository_owner_id, que no se reutilizan si el nombre cambia de dueño."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}$", var.github_repository))
    error_message = "github_repository debe tener la forma <dueño>/<repositorio>, por ejemplo mi-org/mi-repo."
  }
}

variable "github_repository_id" {
  description = "ID numérico del repositorio autorizado (afirmación repository_id del token OIDC de GitHub; se obtiene con gh api repos/<dueño>/<repositorio> --jq .id). Es la base de la confianza de WIF: a diferencia del nombre, no se reutiliza si el repositorio se borra o se renombra."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{1,20}$", var.github_repository_id))
    error_message = "github_repository_id debe ser el ID numérico del repositorio (solo dígitos)."
  }
}

variable "github_repository_owner_id" {
  description = "ID numérico del dueño (organización o usuario) del repositorio autorizado (afirmación repository_owner_id; gh api repos/<dueño>/<repositorio> --jq .owner.id)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{1,20}$", var.github_repository_owner_id))
    error_message = "github_repository_owner_id debe ser el ID numérico del dueño del repositorio (solo dígitos)."
  }
}

variable "state_versions_to_keep" {
  description = "Versiones no actuales de cada archivo de estado que se conservan en el bucket; las más viejas se borran. Permiten recuperar un estado dañado."
  type        = number
  default     = 20
  nullable    = false

  validation {
    condition     = var.state_versions_to_keep >= 5 && floor(var.state_versions_to_keep) == var.state_versions_to_keep
    error_message = "state_versions_to_keep debe ser un entero mayor o igual a 5."
  }
}

variable "labels" {
  description = "Etiquetas comunes (§4.3). Deben traer app, owner y cost_center; la raíz agrega env = bootstrap y managed_by = terraform."
  type        = map(string)
  nullable    = false

  validation {
    condition     = alltrue([for k in ["app", "owner", "cost_center"] : contains(keys(var.labels), k)])
    error_message = "labels debe incluir app, owner y cost_center."
  }
  validation {
    condition     = alltrue([for v in values(var.labels) : can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "Los valores de etiquetas van en minúsculas, dígitos, guion o guion bajo (ADR 0016)."
  }
}
