variable "org_id" {
  description = "ID numérico de la organización."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+$", var.org_id))
    error_message = "org_id debe ser el número de la organización, sin el prefijo organizations/."
  }
}

variable "prefix" {
  description = "Prefijo de la empresa en los nombres (por ejemplo, bnt)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.prefix))
    error_message = "prefix: de 2 a 6 caracteres, minúsculas y dígitos, empieza con letra."
  }
}

variable "policy_parent" {
  description = "Dónde se aplican las nueve políticas: \"organizations/<n>\" o \"folders/<n>\". null (por defecto): la organización de org_id. Las excepciones para un proyecto o carpeta concretos se declaran en la etapa con su propio google_org_policy_policy."
  type        = string
  default     = null

  validation {
    condition     = var.policy_parent == null || can(regex("^(organizations|folders)/[0-9]+$", var.policy_parent))
    error_message = "policy_parent debe ser organizations/<n>, folders/<n> o null."
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
  description = "ID de cliente de Cloud Identity / Google Workspace (Cxxxxxxxx) cuyo dominio es el único admitido en las políticas de IAM (iam.allowedPolicyMemberDomains)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^C[0-9a-zA-Z]{6,}$", var.directory_customer_id))
    error_message = "directory_customer_id debe tener la forma C seguida del identificador (por ejemplo, C0abc1234)."
  }
}

variable "log_sink_destination" {
  description = "Destino del sink agregado de la organización, por ejemplo storage.googleapis.com/<bucket> (salida destination del módulo log-export)."
  type        = string
  nullable    = false

  validation {
    condition = can(regex(
      "^(storage\\.googleapis\\.com/[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]|logging\\.googleapis\\.com/projects/[^/]+/locations/[^/]+/buckets/[^/]+|bigquery\\.googleapis\\.com/projects/[^/]+/datasets/[^/]+|pubsub\\.googleapis\\.com/projects/[^/]+/topics/[^/]+)$",
      var.log_sink_destination
    ))
    error_message = "log_sink_destination debe ser un destino de Logging: storage.googleapis.com/<bucket>, logging.googleapis.com/..., bigquery.googleapis.com/... o pubsub.googleapis.com/...."
  }
}

variable "log_sink_filter" {
  description = "Filtro del sink agregado. Por defecto, todos los registros de auditoría de la organización."
  type        = string
  default     = "logName:\"cloudaudit.googleapis.com\""
  nullable    = false
}

variable "grant_sink_writer" {
  description = "Si es true y el destino es un bucket de Cloud Storage, el módulo da roles/storage.objectCreator sobre ese bucket a la identidad del sink. Para otros destinos el permiso lo asigna la etapa."
  type        = bool
  default     = true
  nullable    = false
}
