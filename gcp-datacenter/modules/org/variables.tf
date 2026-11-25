variable "project_id" {
  description = "ID del proyecto único donde se aplican las políticas (padre projects/<id>, ADR 0029 §1)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id debe ser un ID de proyecto válido (6 a 30 caracteres: minúsculas, dígitos y guiones)."
  }
}

variable "allowed_regions" {
  description = "Regiones permitidas por gcp.resourceLocations (por ejemplo, [\"us-central1\", \"us-east4\"]). Cada una se traduce al grupo de valores in:<región>-locations, que incluye sus zonas."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.allowed_regions) > 0
    error_message = "allowed_regions debe tener al menos una región."
  }
  validation {
    condition     = alltrue([for r in var.allowed_regions : can(regex("^[a-z]+-[a-z]+[0-9]+$", r))])
    error_message = "Cada región debe tener la forma de us-central1."
  }
}

variable "additional_allowed_locations" {
  description = "Valores extra para gcp.resourceLocations, tal cual: ubicaciones (por ejemplo, us para la multirregión de KMS o buckets) o grupos in:<grupo>-locations. Por defecto, ninguno."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for l in var.additional_allowed_locations : can(regex("^(in:[a-z0-9-]+-locations|[a-z][a-z0-9-]*)$", l))])
    error_message = "Cada valor debe ser una ubicación (us, us-central1) o un grupo in:<grupo>-locations."
  }
}

variable "directory_customer_id" {
  description = "ID de cliente de Cloud Identity / Google Workspace (Cxxxxxxxx) cuyo dominio es el único admitido en las políticas de IAM (iam.allowedPolicyMemberDomains). null (por defecto): esa política no se crea."
  type        = string
  default     = null

  validation {
    condition     = var.directory_customer_id == null || can(regex("^C[0-9a-zA-Z]{6,}$", var.directory_customer_id))
    error_message = "directory_customer_id debe tener la forma C seguida del identificador (por ejemplo, C0abc1234), o ser null."
  }
}
