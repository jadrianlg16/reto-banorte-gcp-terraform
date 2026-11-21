# Entradas de la etapa 5 (§7.6). Los nombres comunes son los de §4.4; el resto son los que piden
# los módulos que compone la etapa. Las diferencias entre entornos llegan solo por variables.

# ---------------------------------------------------------------------------------------------
# Identidad del entorno y estado
# ---------------------------------------------------------------------------------------------

variable "prefix" {
  description = "Prefijo de la empresa para los nombres (§4.2), por ejemplo bnt."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.prefix))
    error_message = "prefix debe tener de 2 a 6 caracteres: minúsculas y dígitos, empezando con letra."
  }
}

variable "environment" {
  description = "Entorno de esta raíz: dev, qa o prod. Debe coincidir con el prefijo de backend.tf."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser dev, qa o prod."
  }
}

variable "application" {
  description = "Aplicación cuyas cargas crea esta raíz: llave de service_project_ids y service_accounts de la etapa 4 (por defecto app). Forma parte de los nombres del balanceador, la política de Cloud Armor y el bucket."
  type        = string
  default     = "app"

  validation {
    # Mismo conjunto que las llaves de applications de 4-projects (límites de 30 caracteres de
    # los ID de cuenta de servicio y de proyecto con el prefijo más largo y prod).
    condition     = can(regex("^[a-z][a-z0-9]{1,7}$", var.application))
    error_message = "application debe tener de 2 a 8 caracteres: minúsculas y dígitos, empezando con letra."
  }
}

variable "state_bucket" {
  description = "Bucket de estado de la etapa 0; de él se leen los prefijos 2-security, 3-networks/<env> y 4-projects/<env> (§6.1)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", var.state_bucket))
    error_message = "state_bucket debe ser un nombre de bucket de Cloud Storage válido."
  }
}

variable "labels" {
  description = "Etiquetas comunes (§4.3). Obligatorias aquí: app (igual a application), owner y cost_center; env y managed_by las fija la raíz."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["app", "owner", "cost_center"] : contains(keys(var.labels), k)])
    error_message = "labels debe incluir app, owner y cost_center."
  }
  validation {
    condition     = lookup(var.labels, "app", "") == var.application
    error_message = "labels.app debe ser igual a application."
  }
  validation {
    condition     = alltrue([for v in values(var.labels) : can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "Los valores de etiquetas van en minúsculas, dígitos, guion o guion bajo (ADR 0016)."
  }
  validation {
    condition     = alltrue([for k in keys(var.labels) : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))])
    error_message = "Las llaves de etiquetas empiezan con minúscula y llevan minúsculas, dígitos, guion o guion bajo."
  }
}

# ---------------------------------------------------------------------------------------------
# Regiones y DR
# ---------------------------------------------------------------------------------------------

variable "primary_region" {
  description = "Región primaria (ADR 0002)."
  type        = string
  default     = "us-central1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.primary_region))
    error_message = "primary_region debe ser una región de GCP (por ejemplo, us-central1)."
  }
  validation {
    condition     = contains(keys(var.region_codes), var.primary_region)
    error_message = "primary_region debe ser una llave de region_codes."
  }
}

variable "dr_region" {
  description = "Región de DR (ADR 0002). Siempre se declara: la bóveda de respaldos vive ahí aunque enable_dr = false."
  type        = string
  default     = "us-east4"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.dr_region))
    error_message = "dr_region debe ser una región de GCP (por ejemplo, us-east4)."
  }
  validation {
    condition     = contains(keys(var.region_codes), var.dr_region) && var.dr_region != var.primary_region
    error_message = "dr_region debe ser una llave de region_codes distinta de primary_region."
  }
}

variable "region_codes" {
  description = "Mapa región → código corto para los nombres (§4.2)."
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

variable "enable_dr" {
  description = "DR de datos (prod): réplica de Cloud SQL en dr_region, bucket de doble región con turbo replication y plan de Backup for GKE. Exige que el spoke de la etapa 3 tenga enable_dr = true."
  type        = bool
  default     = false
  nullable    = false
}

variable "dr_active" {
  description = "Conmutación a DR: crea el cómputo (GKE, MIG, Cloud Run) también en dr_region y apunta los backends de los balanceadores a esa región. Exige enable_dr. La promoción de la réplica de Cloud SQL es un paso del runbook, no de Terraform."
  type        = bool
  default     = false
  nullable    = false

  validation {
    condition     = !var.dr_active || var.enable_dr
    error_message = "dr_active = true exige enable_dr = true (la región de DR debe tener subredes, llaves y réplica)."
  }
}

variable "dr_teardown" {
  description = <<-EOT
    Vuelta a la región primaria (runbook 04): quita la protección contra borrado solo del clúster
    de GKE y del servicio de Cloud Run de la región de DR (llave "dr"), también en prod; los de
    la región primaria siguen protegidos. Se aplica primero con dr_active = true (cambio en el
    lugar) y después dr_active = false destruye el cómputo de DR. Sin este paso el proveedor se
    niega a destruirlos. Volver a false al terminar.
  EOT
  type        = bool
  default     = false
  nullable    = false

  validation {
    condition     = !var.dr_teardown || var.enable_dr
    error_message = "dr_teardown = true exige enable_dr = true (solo hay cómputo de DR con enable_dr)."
  }
}

variable "multi_region" {
  description = "Multirregión del bucket de doble región con enable_dr (anillo de llaves de la etapa 2 de esa ubicación). Debe contener primary_region y dr_region."
  type        = string
  default     = "us"

  validation {
    condition     = contains(["us", "eu", "asia"], var.multi_region)
    error_message = "multi_region debe ser us, eu o asia (en minúsculas)."
  }
}

variable "deletion_protection" {
  description = "Protección contra borrado de Cloud SQL, Filestore, GKE y Cloud Run fuera de prod. En prod debe ser true (los módulos además la fijan)."
  type        = bool
  default     = true
  nullable    = false

  validation {
    condition     = var.environment != "prod" || var.deletion_protection
    error_message = "En prod deletion_protection debe ser true."
  }
}

# ---------------------------------------------------------------------------------------------
# Interruptores por carga
# ---------------------------------------------------------------------------------------------

variable "enable_gke" {
  description = "Crea el clúster de GKE (ADR 0012) en la región primaria (y en la de DR con dr_active)."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_mig" {
  description = "Crea el MIG regional de VM (ADR 0012) en la región primaria (y en la de DR con dr_active)."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_cloud_run" {
  description = "Crea el servicio de Cloud Run (ADR 0012) en la región primaria (y en la de DR con dr_active)."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_filestore" {
  description = "Crea la instancia de Filestore en la región primaria."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_memorystore" {
  description = "Crea la instancia de Memorystore para Redis en la región primaria."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_internal_lb" {
  description = "Crea el balanceador de aplicaciones interno regional (subred proxy-only del spoke) delante del MIG y de Cloud Run para clientes internos y on-premises."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_backup" {
  description = "Crea la bóveda de Backup and DR en dr_region y los planes diarios (retención de 30 días)."
  type        = bool
  default     = true
  nullable    = false
}

# ---------------------------------------------------------------------------------------------
# GKE
# ---------------------------------------------------------------------------------------------

variable "gke_node_pools" {
  description = "Pools de nodos de GKE (llave → configuración); mismo formato que el módulo gke. min_node_count y max_node_count son por zona. Obligatorio con enable_gke."
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
  default  = {}
  nullable = false

  validation {
    condition     = !var.enable_gke || length(var.gke_node_pools) > 0
    error_message = "enable_gke = true exige al menos un pool en gke_node_pools."
  }
}

variable "gke_workload_namespace" {
  description = "Namespace de Kubernetes de la cuenta de servicio de Kubernetes que actúa como la cuenta workload de la aplicación (Workload Identity)."
  type        = string
  default     = "app"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.gke_workload_namespace)) && !contains(["default", "kube-system", "kube-public", "kube-node-lease"], var.gke_workload_namespace)
    error_message = "gke_workload_namespace debe ser un nombre DNS-1123 de hasta 63 caracteres y no un namespace del sistema ni default."
  }
}

variable "gke_workload_ksa_name" {
  description = "Nombre de la cuenta de servicio de Kubernetes (en gke_workload_namespace) que actúa como la cuenta workload de la aplicación (Workload Identity)."
  type        = string
  default     = "app"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.gke_workload_ksa_name)) && var.gke_workload_ksa_name != "default"
    error_message = "gke_workload_ksa_name debe ser un nombre DNS-1123 de hasta 63 caracteres y no la cuenta default del namespace."
  }
}

variable "gke_authenticator_security_group" {
  description = "Grupo raíz de Google Groups for RBAC del clúster (gke-security-groups@<dominio>). Obligatorio con enable_gke."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_gke || var.gke_authenticator_security_group != null
    error_message = "enable_gke = true exige gke_authenticator_security_group."
  }
  validation {
    condition     = var.gke_authenticator_security_group == null || can(regex("^gke-security-groups@[a-z0-9.-]+\\.[a-z]{2,}$", coalesce(var.gke_authenticator_security_group, "x")))
    error_message = "gke_authenticator_security_group debe ser gke-security-groups@<dominio>."
  }
}

variable "gke_release_channel" {
  description = "Canal de versiones de GKE: RAPID, REGULAR o STABLE (sin RAPID en prod, lo valida el módulo)."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.gke_release_channel)
    error_message = "gke_release_channel debe ser RAPID, REGULAR o STABLE."
  }
}

variable "gke_master_authorized_networks" {
  description = "Rangos autorizados para llegar al plano de control privado de GKE (por ejemplo, el rango on-premises o una subred de administración)."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for n in var.gke_master_authorized_networks : can(cidrhost(n.cidr_block, 0)) && !endswith(n.cidr_block, "/0")])
    error_message = "Cada cidr_block debe ser un CIDR válido y distinto de /0."
  }
}

variable "gke_lb_negs" {
  description = <<-EOT
    Backends de GKE para el balanceador externo. GKE crea los NEG zonales al desplegar un Service
    con la anotación cloud.google.com/neg (fuera de Terraform), así que sus self links se llenan
    después del primer despliegue de la carga y se aplica de nuevo. Vacío por defecto: sin backend
    de GKE en el balanceador.
    - primary: self links de los NEG zonales del clúster de la región primaria.
    - dr: los del clúster de DR. Se llenan después de conmutar (el clúster de DR nace con
      dr_active): mientras estén vacíos, con dr_active el backend de GKE queda fuera del
      balanceador (si es el único backend, sigue con los NEG primarios para no destruir el
      balanceador).
    - max_rate_per_endpoint: solicitudes por segundo por endpoint (modo RATE).
    - health_check_path: ruta de la verificación de salud que crea el balanceador.
  EOT
  type = object({
    primary               = optional(list(string), [])
    dr                    = optional(list(string), [])
    max_rate_per_endpoint = optional(number, 100)
    health_check_path     = optional(string, "/healthz")
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for n in concat(var.gke_lb_negs.primary, var.gke_lb_negs.dr) :
      can(regex("(^|/)projects/[^/]+/zones/[^/]+/networkEndpointGroups/[^/]+$", n))
    ])
    error_message = "Cada NEG debe ser un self link projects/<p>/zones/<zona>/networkEndpointGroups/<nombre>."
  }
  validation {
    condition     = var.gke_lb_negs.max_rate_per_endpoint > 0
    error_message = "max_rate_per_endpoint debe ser mayor que 0."
  }
  validation {
    condition     = startswith(var.gke_lb_negs.health_check_path, "/")
    error_message = "health_check_path debe empezar con /."
  }
}

# ---------------------------------------------------------------------------------------------
# MIG
# ---------------------------------------------------------------------------------------------

variable "mig_image" {
  description = "Imagen endurecida de las VM del MIG (projects/<p>/global/images/<imagen> o .../images/family/<familia>). Sin valor por defecto público: obligatoria con enable_mig."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_mig || var.mig_image != null
    error_message = "enable_mig = true exige mig_image (imagen endurecida)."
  }
  validation {
    condition     = var.mig_image == null || can(regex("(^|/)projects/[a-z][a-z0-9-]+/global/images/(family/)?[a-z][a-z0-9-]*$", coalesce(var.mig_image, "x")))
    error_message = "mig_image debe tener la forma projects/<p>/global/images/<imagen> o projects/<p>/global/images/family/<familia>."
  }
}

variable "mig_machine_type" {
  description = "Tipo de máquina de las VM del MIG."
  type        = string
  default     = "e2-standard-2"

  validation {
    condition     = can(regex("^[a-z0-9]+-[a-z0-9-]+$", var.mig_machine_type))
    error_message = "mig_machine_type debe ser un tipo de máquina de Compute Engine (por ejemplo, e2-standard-2)."
  }
}

variable "mig_min_replicas" {
  description = "Mínimo de VM del autoescalador (al menos 2 en prod, lo valida el módulo)."
  type        = number
  default     = 2

  validation {
    condition     = var.mig_min_replicas >= 1 && floor(var.mig_min_replicas) == var.mig_min_replicas
    error_message = "mig_min_replicas debe ser un entero mayor o igual a 1."
  }
}

variable "mig_max_replicas" {
  description = "Máximo de VM del autoescalador."
  type        = number
  default     = 4

  validation {
    condition     = floor(var.mig_max_replicas) == var.mig_max_replicas && var.mig_max_replicas >= var.mig_min_replicas
    error_message = "mig_max_replicas debe ser un entero mayor o igual a mig_min_replicas."
  }
}

variable "mig_http_port" {
  description = "Puerto HTTP en el que sirven las VM (puerto con nombre http del grupo y de las verificaciones de salud). Debe estar en lb_backend_ports de la etapa 3 (lo comprueba el plan si la etapa 3 publica esa salida)."
  type        = number
  default     = 80

  validation {
    condition     = var.mig_http_port >= 1 && var.mig_http_port <= 65535
    error_message = "mig_http_port debe estar entre 1 y 65535."
  }
}

variable "mig_health_check_path" {
  description = "Ruta HTTP de la verificación de salud del MIG (autocuración y balanceadores)."
  type        = string
  default     = "/healthz"

  validation {
    condition     = startswith(var.mig_health_check_path, "/")
    error_message = "mig_health_check_path debe empezar con /."
  }
}

# ---------------------------------------------------------------------------------------------
# Cloud Run
# ---------------------------------------------------------------------------------------------

variable "cloud_run_image" {
  description = "Imagen del contenedor de Cloud Run (registro/ruta:etiqueta o @sha256:digest; en prod sin latest). Obligatoria con enable_cloud_run."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_cloud_run || var.cloud_run_image != null
    error_message = "enable_cloud_run = true exige cloud_run_image."
  }
  validation {
    condition     = var.cloud_run_image == null || can(regex("^[a-z0-9.-]+(:[0-9]+)?/[a-z0-9._/-]+(:[A-Za-z0-9._-]+|@sha256:[a-f0-9]{64})?$", coalesce(var.cloud_run_image, "x")))
    error_message = "cloud_run_image debe ser una referencia de imagen con registro (registro/ruta[:etiqueta|@sha256:digest])."
  }
}

variable "cloud_run_container_port" {
  description = "Puerto en el que escucha el contenedor de Cloud Run."
  type        = number
  default     = 8080

  validation {
    condition     = var.cloud_run_container_port >= 1 && var.cloud_run_container_port <= 65535
    error_message = "cloud_run_container_port debe estar entre 1 y 65535."
  }
}

variable "cloud_run_max_instances" {
  description = "Máximo de instancias del servicio de Cloud Run."
  type        = number
  default     = 10

  validation {
    condition     = var.cloud_run_max_instances >= 1 && floor(var.cloud_run_max_instances) == var.cloud_run_max_instances
    error_message = "cloud_run_max_instances debe ser un entero mayor o igual a 1."
  }
}

# ---------------------------------------------------------------------------------------------
# Datos
# ---------------------------------------------------------------------------------------------

variable "sql_tier" {
  description = "Tipo de máquina de Cloud SQL (db-custom-* en edición ENTERPRISE)."
  type        = string
  default     = "db-custom-2-7680"

  validation {
    condition     = can(regex("^db-custom-[0-9]+-[0-9]+$", var.sql_tier))
    error_message = "sql_tier debe ser un tipo db-custom-<vCPU>-<MB> (edición ENTERPRISE)."
  }
}

variable "sql_database_version" {
  description = "Versión de PostgreSQL de Cloud SQL (POSTGRES_<n>)."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.sql_database_version))
    error_message = "sql_database_version debe ser POSTGRES_<versión> (el módulo cloud-sql solo admite PostgreSQL)."
  }
}

variable "sql_databases" {
  description = "Bases de datos que se crean en la instancia de Cloud SQL."
  type        = list(string)
  default     = ["app"]
  nullable    = false

  validation {
    condition     = alltrue([for d in var.sql_databases : can(regex("^[a-z][a-z0-9_]{0,62}$", d))])
    error_message = "Cada base de datos debe empezar con minúscula y llevar minúsculas, dígitos o guion bajo."
  }
}

variable "memorystore_memory_gb" {
  description = "Memoria de la instancia de Redis en GB (el tier lo decide el módulo: STANDARD_HA en prod, BASIC fuera)."
  type        = number
  default     = 5

  validation {
    condition     = var.memorystore_memory_gb >= 1 && var.memorystore_memory_gb <= 300 && floor(var.memorystore_memory_gb) == var.memorystore_memory_gb
    error_message = "memorystore_memory_gb debe ser un entero de 1 a 300."
  }
}

variable "filestore_tier" {
  description = "Nivel de Filestore con CMEK: ZONAL (en la zona primary_region-<filestore_zone_suffix>), REGIONAL o ENTERPRISE."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL", "ENTERPRISE"], var.filestore_tier)
    error_message = "filestore_tier debe ser ZONAL, REGIONAL o ENTERPRISE."
  }
}

variable "filestore_zone_suffix" {
  description = "Letra de la zona de primary_region para Filestore ZONAL (por ejemplo, a)."
  type        = string
  default     = "a"

  validation {
    condition     = can(regex("^[a-z]$", var.filestore_zone_suffix))
    error_message = "filestore_zone_suffix debe ser una letra minúscula."
  }
}

variable "filestore_capacity_gb" {
  description = "Capacidad del recurso compartido de Filestore en GiB (rangos por tier: los valida el módulo)."
  type        = number
  default     = 1024

  validation {
    condition     = var.filestore_capacity_gb >= 100 && floor(var.filestore_capacity_gb) == var.filestore_capacity_gb
    error_message = "filestore_capacity_gb debe ser un entero de al menos 100."
  }
}

variable "bucket_name_suffix" {
  description = "Sufijo del nombre del bucket para hacerlo único a nivel mundial (como project_suffix). Vacío por defecto."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = can(regex("^(-?[a-z0-9]{1,10})?$", var.bucket_name_suffix))
    error_message = "bucket_name_suffix debe estar vacío o tener hasta 10 minúsculas o dígitos (con guion inicial opcional)."
  }
}

# ---------------------------------------------------------------------------------------------
# Balanceadores
# ---------------------------------------------------------------------------------------------

variable "domain_names" {
  description = "Dominios públicos del certificado administrado del balanceador externo; el primero recibe la verificación de disponibilidad."
  type        = list(string)

  validation {
    condition     = length(var.domain_names) > 0 && length(var.domain_names) <= 100
    error_message = "domain_names debe tener de 1 a 100 dominios."
  }
  validation {
    condition     = alltrue([for d in var.domain_names : can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", d))])
    error_message = "Cada dominio debe ser un nombre DNS válido en minúsculas, sin comodines ni punto final."
  }
}

variable "lb_default_backend" {
  description = "Backend por defecto del mapa de URL externo: gke, mig o run. null: el primero habilitado en el orden run, mig, gke."
  type        = string
  default     = null

  validation {
    condition     = var.lb_default_backend == null || contains(["gke", "mig", "run"], coalesce(var.lb_default_backend, "x"))
    error_message = "lb_default_backend debe ser gke, mig, run o null."
  }
}

variable "lb_backend_paths" {
  description = "Rutas del mapa de URL por backend (llaves gke, mig o run → lista de rutas, por ejemplo { run = [\"/api/*\"] }). Las solicitudes sin ruta van a lb_default_backend."
  type        = map(list(string))
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k in keys(var.lb_backend_paths) : contains(["gke", "mig", "run"], k)])
    error_message = "Las llaves de lb_backend_paths deben ser gke, mig o run."
  }
  validation {
    condition     = alltrue(flatten([for p in values(var.lb_backend_paths) : [for r in p : startswith(r, "/")]]))
    error_message = "Cada ruta de lb_backend_paths debe empezar con /."
  }
}

variable "internal_domain_names" {
  description = "Dominios del certificado del balanceador interno (Certificate Manager con autorización DNS). Obligatorio con enable_internal_lb."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = !var.enable_internal_lb || length(var.internal_domain_names) > 0
    error_message = "enable_internal_lb = true exige al menos un dominio en internal_domain_names."
  }
  validation {
    condition     = alltrue([for d in var.internal_domain_names : can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", d))])
    error_message = "Cada dominio interno debe ser un nombre DNS válido en minúsculas, sin comodines ni punto final."
  }
}

# ---------------------------------------------------------------------------------------------
# Observabilidad
# ---------------------------------------------------------------------------------------------

variable "notification_emails" {
  description = "Correos (de preferencia listas de grupo) que reciben las alertas del entorno."
  type        = list(string)

  validation {
    condition     = length(var.notification_emails) > 0
    error_message = "notification_emails debe tener al menos un correo."
  }
  validation {
    condition     = alltrue([for e in var.notification_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[a-z]{2,}$", lower(e)))])
    error_message = "Cada elemento de notification_emails debe ser un correo válido."
  }
}

variable "uptime_check_path" {
  description = "Ruta HTTPS que revisa la verificación de disponibilidad sobre el primer dominio de domain_names."
  type        = string
  default     = "/"

  validation {
    condition     = startswith(var.uptime_check_path, "/")
    error_message = "uptime_check_path debe empezar con /."
  }
}
