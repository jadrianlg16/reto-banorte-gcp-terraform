variable "project_id" {
  description = "ID del proyecto único (ADR 0029 §1). Lo crea una persona con la consola o gcloud y lo liga a una cuenta de facturación de pago; ninguna raíz lo crea ni lo borra."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id debe ser un ID de proyecto válido (6 a 30 caracteres: minúsculas, dígitos y guiones)."
  }
}

variable "billing_account" {
  description = "Cuenta de facturación ligada al proyecto (formato XXXXXX-XXXXXX-XXXXXX). Solo se usa para el presupuesto del proyecto; la persona que aplica necesita roles/billing.costsManager en ella."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$", var.billing_account))
    error_message = "billing_account debe tener la forma XXXXXX-XXXXXX-XXXXXX (hexadecimal en mayúsculas)."
  }
}

variable "org_id" {
  description = "ID numérico de la organización, si el proyecto está dentro de una (ADR 0029 §1). Con él, esta etapa aplica las políticas de organización al proyecto (org.tf); quien la aplica necesita roles/orgpolicy.policyAdmin en la organización. null (por defecto): proyecto sin organización ni políticas de organización. Ninguna cuenta del pipeline recibe roles de organización."
  type        = string
  default     = null

  validation {
    condition     = var.org_id == null || can(regex("^[0-9]{6,20}$", var.org_id))
    error_message = "org_id debe ser el número de la organización, sin organizations/, o null."
  }
}

variable "additional_allowed_locations" {
  description = "Solo con org_id: ubicaciones extra permitidas por gcp.resourceLocations además de primary_region y dr_region. Por defecto us: la multirregión del estado, de los llaveros y de los repositorios."
  type        = list(string)
  default     = ["us"]
  nullable    = false

  validation {
    condition     = alltrue([for l in var.additional_allowed_locations : can(regex("^(in:[a-z0-9-]+-locations|[a-z][a-z0-9-]*)$", l))])
    error_message = "Cada valor debe ser una ubicación (us) o un grupo in:<grupo>-locations."
  }
}

variable "directory_customer_id" {
  description = "Solo con org_id: ID de cliente de Cloud Identity (Cxxxxxxxx), único dominio admitido en las políticas de IAM (iam.allowedPolicyMemberDomains). null: esa política no se crea."
  type        = string
  default     = null

  validation {
    condition     = var.directory_customer_id == null || can(regex("^C[0-9a-zA-Z]{6,}$", var.directory_customer_id))
    error_message = "directory_customer_id debe tener la forma C seguida del identificador (por ejemplo, C0abc1234), o ser null."
  }
  validation {
    condition     = var.directory_customer_id == null || var.org_id != null
    error_message = "directory_customer_id solo tiene sentido con org_id: sin organización no hay políticas de organización."
  }
}

variable "access_policy_id" {
  description = "ID numérico de la política de Access Context Manager de la organización, si existe. Con él, esta etapa crea el perímetro de VPC-SC en dry-run alrededor de todo el proyecto (org.tf); quien la aplica necesita roles/accesscontextmanager.policyAdmin en la organización (o policyEditor sobre la política). null (por defecto): sin perímetro. Exige org_id."
  type        = string
  default     = null

  validation {
    condition     = var.access_policy_id == null || can(regex("^[0-9]+$", var.access_policy_id))
    error_message = "access_policy_id debe ser el número de la política (sin accessPolicies/) o null."
  }
  validation {
    condition     = var.access_policy_id == null || var.org_id != null
    error_message = "access_policy_id solo tiene sentido con org_id: la política de acceso es de una organización."
  }
}

variable "vpc_sc_restricted_services" {
  description = "Servicios restringidos por el perímetro opcional; debe incluir storage.googleapis.com. Con un solo proyecto, el perímetro ya incluye llaves y secretos: KMS y Secret Manager se restringen también."
  type        = list(string)
  default = [
    "artifactregistry.googleapis.com",
    "backupdr.googleapis.com",
    "bigquery.googleapis.com",
    "cloudkms.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "file.googleapis.com",
    "gkebackup.googleapis.com",
    "pubsub.googleapis.com",
    "redis.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
  ]
  nullable = false

  validation {
    condition     = alltrue([for s in var.vpc_sc_restricted_services : can(regex("^[a-z0-9.-]+\\.googleapis\\.com$", s))])
    error_message = "Cada servicio debe tener la forma <servicio>.googleapis.com."
  }
  validation {
    condition     = contains(var.vpc_sc_restricted_services, "storage.googleapis.com")
    error_message = "vpc_sc_restricted_services debe incluir storage.googleapis.com."
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
  validation {
    condition     = var.prefix != "gcp"
    error_message = "Los IDs de pools de WIF no pueden empezar con gcp-: elige otro prefix."
  }
}

variable "name_suffix" {
  description = "Sufijo opcional del nombre del bucket de estado para que sea único a nivel mundial (los nombres de bucket son globales). Vacío: sin sufijo."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]{0,8}$", var.name_suffix))
    error_message = "name_suffix: hasta 8 caracteres en minúsculas o dígitos, sin guiones."
  }
}

variable "primary_region" {
  description = "Región primaria (ADR 0002). Con dr_region, las dos regiones de un bucket de estado de doble región (state_bucket_dual_regions)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.primary_region))
    error_message = "primary_region debe ser una región, por ejemplo us-central1."
  }
}

variable "dr_region" {
  description = "Región de DR (ADR 0002). Ver primary_region."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.dr_region))
    error_message = "dr_region debe ser una región, por ejemplo us-east4."
  }
  validation {
    condition     = var.dr_region != var.primary_region
    error_message = "dr_region debe ser distinta de primary_region."
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
  description = "Multirregión del bucket de estado y de su llave KMS: US, EU o ASIA. Con state_bucket_dual_regions vacío el bucket es multirregional; si no, es de doble región configurable dentro de esta multirregión. La llave va en la ubicación de KMS homónima (us, eu, asia), como exige la CMEK de Cloud Storage. Así el estado y la llave sobreviven a la caída de primary_region. La ubicación de un bucket no se cambia después de crearlo."
  type        = string
  default     = "US"
  nullable    = false

  validation {
    condition     = contains(["US", "EU", "ASIA"], var.state_bucket_location)
    error_message = "state_bucket_location debe ser US, EU o ASIA (multirregión, en mayúsculas)."
  }
}

variable "state_bucket_dual_regions" {
  description = "Opcional: las dos regiones de un bucket de estado de doble región configurable (por ejemplo [\"us-central1\", \"us-east4\"]), dentro de state_bucket_location; lleva replicación turbo. Vacío (por defecto): bucket multirregional."
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

variable "github_repository" {
  description = "Repositorio de GitHub (<dueño>/<repositorio>) autorizado por Workload Identity Federation, escrito exactamente como la afirmación repository del token (mismas mayúsculas y minúsculas). Qué repositorio entra lo deciden github_repository_id y github_repository_owner_id; este nombre decide qué flujos reutilizables pueden tomar una cuenta que escribe (job_workflow_ref tiene que empezar con <dueño>/<repositorio>/.github/workflows/). Si el repositorio se renombra, las cuentas que escriben dejan de aceptar tokens hasta volver a aplicar 0-bootstrap con el nombre nuevo."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}$", var.github_repository))
    error_message = "github_repository debe tener la forma <dueño>/<repositorio>, por ejemplo mi-org/mi-repo."
  }
}

variable "github_repository_id" {
  description = "ID numérico del repositorio autorizado (afirmación repository_id del token OIDC de GitHub; gh api repos/<dueño>/<repositorio> --jq .id). Es la base de la confianza de WIF: no se reutiliza si el repositorio se borra o se renombra."
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

variable "additional_apis" {
  description = "APIs extra que se habilitan en el proyecto además de las fijas (por ejemplo bigquery.googleapis.com). Se habilitan una sola vez y no se apagan al destruir."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.additional_apis : can(regex("^[a-z0-9.-]+\\.googleapis\\.com$", a))])
    error_message = "Cada API debe tener la forma <servicio>.googleapis.com."
  }
}

variable "budget_amount" {
  description = "Monto mensual del presupuesto del proyecto, en la moneda de la cuenta de facturación (unidades enteras)."
  type        = number
  nullable    = false

  validation {
    condition     = var.budget_amount > 0 && floor(var.budget_amount) == var.budget_amount
    error_message = "budget_amount debe ser un entero mayor que cero."
  }
}

variable "budget_alert_thresholds" {
  description = "Umbrales de alerta del presupuesto sobre el gasto real, como fracción del monto (0.5 = 50 %). Además se alerta al 100 % del gasto pronosticado."
  type        = list(number)
  default     = [0.5, 0.75, 0.9, 1.0]
  nullable    = false

  validation {
    condition     = length(var.budget_alert_thresholds) > 0 && alltrue([for t in var.budget_alert_thresholds : t > 0 && t <= 2])
    error_message = "Cada umbral debe estar entre 0 (exclusivo) y 2."
  }
}

variable "enable_protection_tags" {
  description = "Si es true (por defecto), crea la etiqueta <prefix>-proteccion = etapa-0 y la liga al bucket y al llavero del estado y a las nueve cuentas del pipeline (ADR 0029 §5). false solo si un apply demuestra que las etiquetas no funcionan en el proyecto; la protección queda entonces en los roles condicionados."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_deny_policy" {
  description = "Si es true (por defecto), crea la política de denegación del proyecto contra las nueve cuentas del pipeline (ADR 0029 §5). Sin etiquetas solo lleva la regla sin condición (WIF, roles personalizados, llaves de cuentas y borrar el proyecto). Quien aplica necesita roles/iam.denyAdmin."
  type        = bool
  default     = true
  nullable    = false
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
