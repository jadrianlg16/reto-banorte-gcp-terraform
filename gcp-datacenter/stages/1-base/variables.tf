variable "project_id" {
  description = "ID del proyecto único (ADR 0029 §1). Llega por tfvars como en las demás raíces; una precondición exige que sea el mismo que publica 0-bootstrap."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id debe ser un ID de proyecto válido (6 a 30 caracteres: minúsculas, dígitos y guiones)."
  }
}

variable "state_bucket" {
  description = "Bucket de estado (salida state_bucket de 0-bootstrap); se usa para leer el estado de 0-bootstrap."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", var.state_bucket))
    error_message = "state_bucket debe ser un nombre de bucket válido."
  }
}

variable "prefix" {
  description = "Prefijo de la empresa en todos los nombres (§4.2), por ejemplo bnt. El mismo que en 0-bootstrap."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.prefix))
    error_message = "prefix debe tener de 2 a 6 caracteres: minúsculas y dígitos, empezando con letra."
  }
}

variable "name_suffix" {
  description = "Sufijo opcional del nombre del bucket de logs para que sea único a nivel mundial. Vacío: sin sufijo."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]{0,8}$", var.name_suffix))
    error_message = "name_suffix: hasta 8 caracteres en minúsculas o dígitos, sin guiones."
  }
}

variable "primary_region" {
  description = "Región primaria (ADR 0002): llaveros de entorno, llavero común, bucket de logs y tema de SCC."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.primary_region))
    error_message = "primary_region debe ser una región, por ejemplo us-central1."
  }
}

variable "dr_region" {
  description = "Región de DR (ADR 0002): segundo llavero de cada entorno y segunda réplica de los secretos."
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
  description = "Mapa ubicación → código corto de los nombres de llaveros (§4.2). Debe incluir primary_region, dr_region y us."
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

variable "environments" {
  description = "Entornos con llaveros, llaves, contenedores de secretos y repositorios de imágenes."
  type        = list(string)
  default     = ["dev", "qa", "prod"]
  nullable    = false

  validation {
    condition     = length(var.environments) > 0 && alltrue([for e in var.environments : contains(["dev", "qa", "prod"], e)])
    error_message = "environments debe tener al menos un entorno y solo dev, qa o prod."
  }
  validation {
    condition     = length(distinct(var.environments)) == length(var.environments)
    error_message = "environments no puede repetir entornos."
  }
}

variable "applications" {
  description = "Aplicaciones de cada entorno: repositorio de imágenes (<prefix>-<env>-<app>), cuentas de ejecución (<prefix>-<env>-<app>-<uso>) y regla de Binary Authorization en sus clústeres de prod (<prefix>-prod-<app>-gke[-dr]). Misma validación que application de 3-workloads: de 2 a 8 caracteres."
  type        = set(string)
  default     = ["app"]
  nullable    = false

  # Con 8 caracteres como máximo, la cuenta más larga (<prefix de 6>-prod-<app de 8>-gke-nodes)
  # tiene 30, el límite del ID de cuenta de servicio (ADR 0017).
  validation {
    condition     = length(var.applications) > 0 && alltrue([for a in var.applications : can(regex("^[a-z][a-z0-9]{1,7}$", a))])
    error_message = "Cada aplicación debe tener de 2 a 8 caracteres: minúsculas y dígitos, empezando con letra."
  }
}

variable "off_hours_environments" {
  description = "Entornos con cuenta de los trabajos del apagado fuera de horario (<prefix>-<env>-<app>-sched, ADR 0028) y su rol. 3-workloads la usa con off_hours_shutdown.enabled. Nunca prod."
  type        = list(string)
  default     = ["dev", "qa"]
  nullable    = false

  validation {
    condition     = alltrue([for e in var.off_hours_environments : contains(["dev", "qa"], e)])
    error_message = "off_hours_environments solo admite dev y qa: el apagado fuera de horario nunca es de prod (ADR 0028)."
  }
}

variable "gke_workload_ksa_name" {
  description = "Nombre de la cuenta de servicio de Kubernetes que actúa como la cuenta workload de cada aplicación (Workload Identity), en el namespace <app>-<env>."
  type        = string
  default     = "app"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.gke_workload_ksa_name)) && var.gke_workload_ksa_name != "default"
    error_message = "gke_workload_ksa_name debe ser un nombre DNS-1123 de hasta 63 caracteres y no la cuenta default del namespace."
  }
}

variable "gke_workload_identity_bindings" {
  description = "true: crea el enlace de Workload Identity (roles/iam.workloadIdentityUser) de <app>-<env>/<gke_workload_ksa_name> en la cuenta workload de cada entorno y aplicación. Exige que ya exista el pool <proyecto>.svc.id.goog, que GKE crea con el primer clúster con Workload Identity del proyecto: false (por defecto) hasta el primer apply de 3-workloads con enable_gke, y después true."
  type        = bool
  default     = false
  nullable    = false
}

variable "artifact_registry_location" {
  description = "Ubicación de los repositorios de Artifact Registry: la multirregión us (por defecto; sobrevive a la pérdida de una región) o primary_region o dr_region. Se cifran con la llave artifacts de esa ubicación."
  type        = string
  default     = "us"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+(-[a-z]+[0-9]+)?$", var.artifact_registry_location))
    error_message = "artifact_registry_location debe ser us o una región."
  }
}

variable "artifact_registry_publishers" {
  description = "Mapa entorno → aplicación → miembros que publican imágenes (roles/artifactregistry.writer solo sobre ese repositorio), por ejemplo la cuenta del CI de la aplicación. Sin user:."
  type        = map(map(list(string)))
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue(flatten([for e, apps in var.artifact_registry_publishers : [for a, members in apps : [for m in members : can(regex("^(serviceAccount:|group:|principal://|principalSet://)", m))]]]))
    error_message = "Los publicadores solo admiten serviceAccount:, group:, principal:// o principalSet://; nunca user:."
  }
}

variable "binary_authorization_allowlist_patterns" {
  description = "Patrones de imágenes que Binary Authorization admite además de los repositorios del proyecto (por ejemplo, imágenes base de un registro aprobado), con la forma <registro>/<ruta>[/*|/**|*]: comodines solo al final, * al final del nombre o después de una /, ** solo después de una /. Globales: valen para todos los clústeres y Cloud Run."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    # Registro con al menos un segmento de ruta antes de cualquier comodín: nada de "*" solo ni
    # de un registro entero (gcr.io/*), y ** solo después de / para no cubrir otros proyectos.
    condition = alltrue([
      for p in var.binary_authorization_allowlist_patterns :
      can(regex("^[a-z0-9.-]+\\.[a-z]{2,}(:[0-9]+)?/[a-z0-9][a-z0-9._-]*(/[a-z0-9][a-z0-9._-]*)*(/\\*\\*|/\\*|\\*)?$", p))
    ])
    error_message = "Cada patrón debe ser <registro>/<ruta>[/*|/**|*]: con al menos un segmento de ruta, sin comodines en medio, * al final del nombre o después de / y ** solo después de /."
  }
}

variable "binary_authorization_attestors" {
  description = "Atestadores (projects/<p>/attestors/<a>) que exigen la regla por defecto y las reglas de los clústeres de prod. Vacío (por defecto): sin atestaciones, se niega todo lo que no esté en la lista de permitidos."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.binary_authorization_attestors : can(regex("^projects/[^/]+/attestors/[^/]+$", a))])
    error_message = "Cada atestador debe tener la forma projects/<proyecto>/attestors/<nombre>."
  }
}

variable "secret_names" {
  description = "Mapa entorno → nombres cortos de los contenedores de secretos (sin valores, ADR 0015). El ID queda <prefix>-<entorno>-sec-<nombre>. Un entorno sin entrada no tiene secretos."
  type        = map(list(string))
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for e in keys(var.secret_names) : contains(["dev", "qa", "prod"], e)])
    error_message = "Cada llave de secret_names debe ser dev, qa o prod."
  }
  validation {
    condition     = alltrue(flatten([for names in values(var.secret_names) : [for n in names : can(regex("^[a-z][a-z0-9-]{0,62}$", n))]]))
    error_message = "Cada nombre de secreto: de 1 a 63 caracteres en minúsculas, dígitos o guion, empezando con letra."
  }
}

variable "key_rotation_period" {
  description = "Periodo de rotación de todas las llaves, en segundos con sufijo s. Por defecto 7776000s (90 días); máximo 90 días."
  type        = string
  default     = "7776000s"
  nullable    = false

  validation {
    condition = can(regex("^[0-9]+s$", var.key_rotation_period)) && try(
      tonumber(trimsuffix(var.key_rotation_period, "s")) >= 86400 && tonumber(trimsuffix(var.key_rotation_period, "s")) <= 7776000,
      false
    )
    error_message = "key_rotation_period debe estar entre 86400s (1 día) y 7776000s (90 días)."
  }
}

variable "security_alert_email" {
  description = "Correo que recibe las alertas de auditoría (CIS 2.5 a 2.12, módulo audit-alerts). Puede ser un grupo o una persona: es un canal de notificación, no un permiso de IAM."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", var.security_alert_email))
    error_message = "security_alert_email debe ser un correo válido."
  }
}

variable "groups" {
  description = "Grupos de personas con roles de solo lectura en el proyecto (ADR 0029 §4). Llaves opcionales: readers (viewer, logging.viewer, monitoring.viewer), security_admins (viewer, iam.securityReviewer, logging.viewer, cloudkms.viewer) y auditors (viewer, iam.securityReviewer, logging.privateLogViewer y lectura del bucket de logs). Valor: correo del grupo, sin group:. Solo grupos: las políticas de Conftest rechazan user:."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k in keys(var.groups) : contains(["readers", "security_admins", "auditors"], k)])
    error_message = "Las llaves de groups solo pueden ser readers, security_admins y auditors."
  }
  validation {
    condition     = alltrue([for v in values(var.groups) : can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", v))])
    error_message = "Cada valor de groups debe ser el correo de un grupo (sin el prefijo group:)."
  }
}

variable "essential_contacts" {
  description = "Contactos esenciales del proyecto (CIS 1.17): correo → categorías de notificación. Entre todos deben cubrir LEGAL, SECURITY, SUSPENSION y TECHNICAL (detector ESSENTIAL_CONTACTS_NOT_CONFIGURED). Categorías admitidas: ALL, BILLING, LEGAL, PRODUCT_UPDATES, SECURITY, SUSPENSION, TECHNICAL y TECHNICAL_INCIDENTS."
  type        = map(list(string))
  nullable    = false

  validation {
    condition     = alltrue([for e in keys(var.essential_contacts) : can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", e))])
    error_message = "Cada llave de essential_contacts debe ser un correo."
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
    error_message = "Cada contacto de essential_contacts necesita al menos una categoría."
  }
  validation {
    condition = alltrue([
      for c in ["LEGAL", "SECURITY", "SUSPENSION", "TECHNICAL"] : contains(flatten(values(var.essential_contacts)), c) || contains(flatten(values(var.essential_contacts)), "ALL")
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

variable "enable_scc_notification" {
  description = "Si es true, crea el tema de Pub/Sub con CMEK y la notificación de hallazgos de Security Command Center del proyecto. SCC se activa a mano en el proyecto antes (ADR 0029 §7); por eso es false por defecto."
  type        = bool
  default     = false
  nullable    = false
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

variable "labels" {
  description = "Etiquetas comunes (§4.3). Deben traer app, owner y cost_center; la raíz agrega env (common o el entorno de cada recurso) y managed_by = terraform."
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
