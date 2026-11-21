variable "project_id" {
  description = "ID del proyecto de servicio donde se crea el clúster."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id debe ser un ID de proyecto válido (6 a 30 caracteres, minúsculas, dígitos y guiones)."
  }
}

variable "prefix" {
  description = "Prefijo de la empresa para los nombres (por ejemplo, bnt)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.prefix))
    error_message = "prefix debe empezar con letra y tener de 2 a 10 minúsculas o dígitos."
  }
}

variable "environment" {
  description = "Entorno: dev, qa o prod."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser dev, qa o prod."
  }
}

variable "name" {
  description = "Identificador corto de la carga dentro del nombre del clúster (<prefix>-<environment>-app-<name>-<región>)."
  type        = string
  default     = "gke"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,10}[a-z0-9]$", var.name))
    error_message = "name debe tener de 2 a 12 caracteres: minúsculas, dígitos y guiones, empezando con letra."
  }
}

variable "location" {
  description = "Ubicación del clúster: una región (clúster regional) o una zona (clúster zonal, solo fuera de prod)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+(-[a-z])?$", var.location))
    error_message = "location debe ser una región (us-central1) o una zona (us-central1-a)."
  }
  validation {
    condition     = var.environment != "prod" || can(regex("^[a-z]+-[a-z]+[0-9]+$", var.location))
    error_message = "En prod el clúster debe ser regional: location tiene que ser una región, no una zona."
  }
}

variable "region_codes" {
  description = "Mapa región → código corto que se agrega a los nombres (§4.2 del contrato)."
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

variable "network" {
  description = "Self link (o ruta projects/<host>/global/networks/<red>) de la VPC compartida del proyecto host."
  type        = string

  validation {
    condition     = can(regex("(^|/)projects/[^/]+/global/networks/[^/]+$", var.network))
    error_message = "network debe ser un self link o una ruta projects/<proyecto>/global/networks/<red>."
  }
}

variable "subnet" {
  description = "Self link (o ruta projects/<host>/regions/<región>/subnetworks/<subred>) de la subred compartida donde viven los nodos."
  type        = string

  validation {
    condition     = can(regex("(^|/)projects/[^/]+/regions/[^/]+/subnetworks/[^/]+$", var.subnet))
    error_message = "subnet debe ser un self link o una ruta projects/<proyecto>/regions/<región>/subnetworks/<subred>."
  }
}

variable "pods_range" {
  description = "Nombre del rango secundario de la subred para los pods (VPC nativa)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.pods_range))
    error_message = "pods_range debe ser un nombre de rango secundario válido."
  }
}

variable "services_range" {
  description = "Nombre del rango secundario de la subred para los servicios (VPC nativa)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.services_range))
    error_message = "services_range debe ser un nombre de rango secundario válido."
  }
}

variable "master_cidr" {
  description = "Rango /28 privado del plano de control (llave gke_master de §5)."
  type        = string

  validation {
    condition     = can(cidrhost(var.master_cidr, 0)) && endswith(var.master_cidr, "/28")
    error_message = "master_cidr debe ser un CIDR /28 válido."
  }
}

variable "enable_private_endpoint" {
  description = "Si es true, el plano de control solo tiene IP privada (sin endpoint público). Si es false (solo dev y qa), el endpoint público queda limitado a master_authorized_networks, que no puede estar vacío."
  type        = bool
  default     = true
  nullable    = false

  validation {
    condition     = var.environment != "prod" || var.enable_private_endpoint
    error_message = "En prod el plano de control debe tener solo endpoint privado (enable_private_endpoint = true)."
  }
}

variable "master_authorized_networks" {
  description = "Rangos autorizados para llegar al plano de control (por ejemplo, la subred de administración o el rango on-premises)."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for n in var.master_authorized_networks : can(cidrhost(n.cidr_block, 0))])
    error_message = "Cada cidr_block de master_authorized_networks debe ser un CIDR válido."
  }
  validation {
    condition     = alltrue([for n in var.master_authorized_networks : !endswith(n.cidr_block, "/0")])
    error_message = "master_authorized_networks no admite rangos /0 (abierto a todo Internet)."
  }
  validation {
    condition     = var.enable_private_endpoint || length(var.master_authorized_networks) > 0
    error_message = "Con endpoint público (enable_private_endpoint = false) hay que declarar al menos un rango en master_authorized_networks."
  }
}

variable "release_channel" {
  description = "Canal de versiones de GKE: RAPID, REGULAR o STABLE. En prod no se admite RAPID."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel debe ser RAPID, REGULAR o STABLE."
  }
  validation {
    condition     = var.environment != "prod" || var.release_channel != "RAPID"
    error_message = "En prod release_channel debe ser REGULAR o STABLE."
  }
}

variable "gke_node_pools" {
  description = "Pools de nodos (llave → configuración). min_node_count y max_node_count son por zona. La llave forma parte del nombre del pool."
  type = map(object({
    machine_type    = string
    min_node_count  = number
    max_node_count  = number
    disk_size_gb    = optional(number, 100)
    disk_type       = optional(string, "pd-balanced")
    spot            = optional(bool, false)
    node_locations  = optional(list(string))
    max_surge       = optional(number, 1)
    max_unavailable = optional(number, 0)
    k8s_labels      = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))

  validation {
    condition     = length(var.gke_node_pools) > 0
    error_message = "gke_node_pools debe declarar al menos un pool."
  }
  validation {
    condition     = alltrue([for k in keys(var.gke_node_pools) : can(regex("^[a-z][a-z0-9-]{0,13}[a-z0-9]$", k))])
    error_message = "Las llaves de gke_node_pools deben tener de 2 a 15 caracteres: minúsculas, dígitos y guiones."
  }
  validation {
    condition = alltrue([
      for p in values(var.gke_node_pools) : p.min_node_count >= 0 && p.min_node_count <= p.max_node_count && p.max_node_count >= 1
    ])
    error_message = "En cada pool: 0 <= min_node_count <= max_node_count y max_node_count >= 1."
  }
  validation {
    condition     = alltrue([for p in values(var.gke_node_pools) : p.disk_size_gb >= 20])
    error_message = "disk_size_gb debe ser al menos 20 GB."
  }
  validation {
    condition     = alltrue([for p in values(var.gke_node_pools) : contains(["pd-standard", "pd-balanced", "pd-ssd", "hyperdisk-balanced"], p.disk_type)])
    error_message = "disk_type debe ser pd-standard, pd-balanced, pd-ssd o hyperdisk-balanced."
  }
  validation {
    condition = alltrue(flatten([
      for p in values(var.gke_node_pools) : [for t in p.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)]
    ]))
    error_message = "El effect de cada taint debe ser NO_SCHEDULE, PREFER_NO_SCHEDULE o NO_EXECUTE."
  }
  validation {
    condition     = alltrue([for p in values(var.gke_node_pools) : p.max_surge >= 0 && p.max_unavailable >= 0 && p.max_surge + p.max_unavailable > 0])
    error_message = "max_surge y max_unavailable no pueden ser negativos y al menos uno debe ser mayor que cero."
  }
}

variable "node_service_account" {
  description = "Correo de la cuenta de servicio dedicada de los nodos (uso gke_nodes de la etapa 4). No se admite la cuenta de Compute por defecto."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]@[a-z][a-z0-9-]{4,28}[a-z0-9]\\.iam\\.gserviceaccount\\.com$", var.node_service_account))
    error_message = "node_service_account debe ser el correo de una cuenta de servicio administrada por el usuario (<id>@<proyecto>.iam.gserviceaccount.com)."
  }
}

variable "kms_key" {
  description = "ID de la llave KMS (uso gke) para cifrar los secretos de Kubernetes en la capa de aplicación y los discos de arranque de los nodos. Debe estar en la misma región que el clúster."
  type        = string

  validation {
    condition     = can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key))
    error_message = "kms_key debe tener la forma projects/<p>/locations/<l>/keyRings/<k>/cryptoKeys/<c>."
  }
}

variable "authenticator_security_group" {
  description = "Grupo raíz de Google Groups for RBAC (debe llamarse gke-security-groups@<dominio>)."
  type        = string

  validation {
    condition     = can(regex("^gke-security-groups@[a-z0-9.-]+\\.[a-z]{2,}$", var.authenticator_security_group))
    error_message = "authenticator_security_group debe ser gke-security-groups@<dominio>."
  }
}

variable "node_resource_manager_tags" {
  description = "Etiquetas seguras de los nodos de todos los pools (tagKeys/<id> → tagValues/<id>), por ejemplo la de lb_backend de la etapa 3. Vacío: sin etiquetas seguras."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for k, v in var.node_resource_manager_tags : can(regex("^tagKeys/[0-9]+$", k)) && can(regex("^tagValues/[0-9]+$", v))
    ])
    error_message = "node_resource_manager_tags debe mapear tagKeys/<id> → tagValues/<id>."
  }
}

variable "enable_backup_agent" {
  description = "Habilita el complemento de Backup for GKE (lo necesita el plan de respaldo del módulo backup-dr)."
  type        = bool
  default     = true
  nullable    = false
}

variable "maintenance_start_time" {
  description = "Hora de inicio (UTC, HH:MM) de la ventana diaria de mantenimiento."
  type        = string
  default     = "08:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_start_time))
    error_message = "maintenance_start_time debe tener formato HH:MM (UTC)."
  }
}

variable "deletion_protection" {
  description = "Protección contra borrado fuera de prod. En prod siempre es true, sin importar este valor."
  type        = bool
  default     = false
  nullable    = false
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
