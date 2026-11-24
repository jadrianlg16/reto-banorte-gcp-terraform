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
  description = "Cuenta de facturación de los proyectos de common y del presupuesto (formato XXXXXX-XXXXXX-XXXXXX)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$", var.billing_account))
    error_message = "billing_account debe tener la forma XXXXXX-XXXXXX-XXXXXX (hexadecimal en mayúsculas)."
  }
}

variable "prefix" {
  description = "Prefijo de la empresa en todos los nombres (§4.2), por ejemplo bnt. El mismo que en la etapa 0."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.prefix))
    error_message = "prefix debe tener de 2 a 6 caracteres: minúsculas y dígitos, empezando con letra."
  }
}

variable "project_suffix" {
  description = "Sufijo opcional de los IDs de proyecto y del bucket de logs, para que sean únicos a nivel mundial. Vacío: sin sufijo."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]{0,8}$", var.project_suffix))
    error_message = "project_suffix: hasta 8 caracteres en minúsculas o dígitos, sin guiones."
  }
}

variable "primary_region" {
  description = "Región primaria (ADR 0002). Aquí viven el bucket de logs, su llave y el tema de hallazgos de SCC."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.primary_region))
    error_message = "primary_region debe ser una región, por ejemplo us-central1."
  }
}

variable "dr_region" {
  description = "Región de DR (ADR 0002). Junto con la primaria forma la lista de regiones permitidas por gcp.resourceLocations."
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

variable "additional_allowed_locations" {
  description = "Ubicaciones extra permitidas por gcp.resourceLocations, además de las dos regiones. Por defecto us: la multirregión de los llaveros de la etapa 2 y de los buckets de doble región."
  type        = list(string)
  default     = ["us"]
  nullable    = false

  validation {
    condition     = alltrue([for l in var.additional_allowed_locations : can(regex("^(in:[a-z0-9-]+-locations|[a-z][a-z0-9-]*)$", l))])
    error_message = "Cada valor debe ser una ubicación (us) o un grupo in:<grupo>-locations."
  }
}

variable "location_short_codes" {
  description = "Mapa ubicación → código corto que se agrega a los nombres de recursos con región (§4.2). Debe incluir primary_region."
  type        = map(string)
  default = {
    "us-central1"         = "usc1"
    "us-east4"            = "use4"
    "northamerica-south1" = "nas1"
    "us"                  = "us"
  }
  nullable = false

  validation {
    condition     = alltrue([for v in values(var.location_short_codes) : can(regex("^[a-z0-9]{2,6}$", v))])
    error_message = "Cada código corto debe tener de 2 a 6 minúsculas o dígitos."
  }
}

variable "directory_customer_id" {
  description = "ID de cliente de Cloud Identity / Google Workspace (Cxxxxxxxx): único dominio admitido en las políticas de IAM (iam.allowedPolicyMemberDomains)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^C[0-9a-zA-Z]{6,}$", var.directory_customer_id))
    error_message = "directory_customer_id debe tener la forma C seguida del identificador (por ejemplo, C0abc1234)."
  }
}

variable "groups" {
  description = "Mapa rol → correo del grupo de Cloud Identity. Llaves exactas: org_admins, billing_admins, security_admins, network_admins, platform_devops, developers, auditors. Las personas solo reciben roles de lectura (§7.1)."
  type        = map(string)
  nullable    = false

  validation {
    condition = toset(keys(var.groups)) == toset([
      "org_admins", "billing_admins", "security_admins", "network_admins", "platform_devops", "developers", "auditors",
    ])
    error_message = "groups debe tener exactamente las llaves org_admins, billing_admins, security_admins, network_admins, platform_devops, developers y auditors."
  }
  validation {
    condition     = alltrue([for v in values(var.groups) : can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", v))])
    error_message = "Cada valor de groups debe ser el correo de un grupo (sin el prefijo group:)."
  }
}

variable "log_retention_days" {
  description = "Días de retención de cada objeto del bucket de logs de auditoría."
  type        = number
  default     = 365
  nullable    = false

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 36500 && floor(var.log_retention_days) == var.log_retention_days
    error_message = "log_retention_days debe ser un entero entre 30 y 36500."
  }
}

variable "log_retention_locked" {
  description = "Si es true, bloquea la retención del bucket de logs. IRREVERSIBLE una vez aplicado: la retención ya no se puede acortar ni quitar y el bucket no se puede borrar hasta que venza el último objeto."
  type        = bool
  default     = false
  nullable    = false
}

variable "budget_amount" {
  description = "Monto mensual del presupuesto de la organización, en la moneda de la cuenta de facturación (unidades enteras)."
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

variable "scc_notification_filter" {
  description = "Filtro de los hallazgos de Security Command Center que se publican en el tema de Pub/Sub. Por defecto, los activos y sin silenciar de severidad alta o crítica."
  type        = string
  default     = "state = \"ACTIVE\" AND mute != \"MUTED\" AND (severity = \"HIGH\" OR severity = \"CRITICAL\")"
  nullable    = false

  validation {
    condition     = length(trimspace(var.scc_notification_filter)) > 0
    error_message = "scc_notification_filter no puede estar vacío."
  }
}

variable "essential_contacts" {
  description = "Contactos esenciales de la organización (CIS 1.17): llave de groups → categorías de notificación que recibe ese grupo. Entre todos deben cubrir LEGAL, SECURITY, SUSPENSION y TECHNICAL, las que revisa el detector ESSENTIAL_CONTACTS_NOT_CONFIGURED. Categorías admitidas por la API: ALL, BILLING, LEGAL, PRODUCT_UPDATES, SECURITY, SUSPENSION, TECHNICAL y TECHNICAL_INCIDENTS."
  type        = map(list(string))
  default = {
    org_admins      = ["LEGAL", "SUSPENSION", "TECHNICAL"]
    security_admins = ["SECURITY", "TECHNICAL"]
    billing_admins  = ["BILLING"]
  }
  nullable = false

  validation {
    condition = alltrue([
      for k in keys(var.essential_contacts) :
      contains(["org_admins", "billing_admins", "security_admins", "network_admins", "platform_devops", "developers", "auditors"], k)
    ])
    error_message = "Cada llave de essential_contacts debe ser una llave de groups (org_admins, billing_admins, security_admins, network_admins, platform_devops, developers, auditors)."
  }
  validation {
    condition = alltrue([
      for c in flatten(values(var.essential_contacts)) :
      contains(["ALL", "BILLING", "LEGAL", "PRODUCT_UPDATES", "SECURITY", "SUSPENSION", "TECHNICAL", "TECHNICAL_INCIDENTS"], c)
    ])
    error_message = "Categoría desconocida en essential_contacts: solo ALL, BILLING, LEGAL, PRODUCT_UPDATES, SECURITY, SUSPENSION, TECHNICAL o TECHNICAL_INCIDENTS."
  }
  validation {
    condition     = alltrue([for l in values(var.essential_contacts) : length(l) > 0])
    error_message = "Cada grupo de essential_contacts necesita al menos una categoría."
  }
  validation {
    condition = alltrue([
      for c in ["LEGAL", "SECURITY", "SUSPENSION", "TECHNICAL"] : contains(flatten(values(var.essential_contacts)), c)
    ])
    error_message = "essential_contacts debe cubrir LEGAL, SECURITY, SUSPENSION y TECHNICAL (CIS 1.17)."
  }
}

variable "essential_contacts_language" {
  description = "Idioma de las notificaciones de Essential Contacts (etiqueta BCP-47, por ejemplo es o en)."
  type        = string
  default     = "es"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$", var.essential_contacts_language))
    error_message = "essential_contacts_language debe ser una etiqueta de idioma BCP-47 (por ejemplo es, en o es-419)."
  }
}

variable "labels" {
  description = "Etiquetas comunes (§4.3). Deben traer app, owner y cost_center; la raíz agrega env = common y managed_by = terraform."
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

variable "state_bucket" {
  description = "Bucket de estado (salida state_bucket de la etapa 0); se usa para leer el estado de 0-bootstrap."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", var.state_bucket))
    error_message = "state_bucket debe ser un nombre de bucket válido."
  }
}
