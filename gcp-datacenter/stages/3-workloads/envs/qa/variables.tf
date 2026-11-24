# Entradas de la etapa 3-workloads (ADR 0029 §2: lo que eran las etapas 4 y 5 de un entorno).
# Los nombres comunes son los de §4.4; el resto son los que piden los módulos que compone la
# etapa. Las diferencias entre entornos llegan solo por variables.

# ---------------------------------------------------------------------------------------------
# Identidad del entorno y estado
# ---------------------------------------------------------------------------------------------

variable "project_id" {
  description = "ID del proyecto único de GCP (ADR 0029 §1). Lo crea una persona; ninguna raíz lo crea ni lo borra. Todo lo de esta raíz vive en él."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id debe ser un ID de proyecto válido (6 a 30 caracteres: minúsculas, dígitos y guiones, empezando con letra)."
  }
}

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
  description = "Aplicación cuyas cargas crea esta raíz (por defecto app): llave de artifact_registry_repositories[environment] de 1-base y parte de los nombres de las cuentas de ejecución (<prefix>-<environment>-<application>-<uso>), del clúster de GKE, del balanceador, de la política de Cloud Armor y del bucket."
  type        = string
  default     = "app"

  validation {
    # 8 caracteres como máximo: con el prefijo más largo (6) y prod,
    # <prefix>-prod-<app>-gke-nodes llega a 30 (límite del ID de cuenta de servicio, ADR 0017).
    condition     = can(regex("^[a-z][a-z0-9]{1,7}$", var.application))
    error_message = "application debe tener de 2 a 8 caracteres: minúsculas y dígitos, empezando con letra."
  }
  validation {
    # El uso más largo es gke-nodes (9 caracteres): <prefix>-<environment>-<app>-gke-nodes.
    condition     = length("${var.prefix}-${var.environment}-${var.application}-gke-nodes") <= 30
    error_message = "application demasiado larga: <prefix>-<environment>-<application>-gke-nodes no puede pasar de 30 caracteres (límite del ID de cuenta de servicio, ADR 0017)."
  }
}

variable "state_bucket" {
  description = "Bucket de estado de 0-bootstrap; de él se leen los prefijos 1-base y 2-networks/<environment> (ADR 0029 §2)."
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
  description = "DR de datos (prod): réplica de Cloud SQL en dr_region, bucket de doble región con turbo replication y plan de Backup for GKE. Exige que el spoke de 2-networks tenga enable_dr = true."
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
    la región primaria siguen protegidos. Primer apply: dr_active = true y dr_teardown = true
    (cambio en el lugar). Segundo apply: dr_active = false y dr_teardown = false juntos; el
    proveedor lee la protección del estado al borrar, así que destruye el cómputo de DR. Solo se
    admite con dr_active = true: no puede quedar encendido y desproteger el cómputo de DR de la
    siguiente conmutación.
  EOT
  type        = bool
  default     = false
  nullable    = false

  validation {
    # dr_active ya exige enable_dr, así que esta validación también cubre ese caso.
    condition     = !var.dr_teardown || var.dr_active
    error_message = "dr_teardown = true exige dr_active = true: se usa solo en el primer apply de la vuelta; el segundo pasa dr_active = false y dr_teardown = false juntos."
  }
}

variable "multi_region" {
  description = "Multirregión del bucket de doble región con enable_dr (llave storage de 1-base en esa ubicación). Debe contener primary_region y dr_region."
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
  description = "Puerto HTTP en el que sirven las VM (puerto con nombre http del grupo y de las verificaciones de salud). Debe estar en lb_backend_ports del spoke de 2-networks (lo comprueba el plan si el spoke publica esa salida)."
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
  description = "Imagen del contenedor de Cloud Run (registro/ruta:etiqueta o @sha256:digest; en prod sin latest), del repositorio del entorno (artifact_registry_repositories de 1-base). Obligatoria con enable_cloud_run."
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

variable "sql_instance_name" {
  description = "Parte <recurso> del nombre de la instancia de Cloud SQL: <prefix>-<environment>-data-<sql_instance_name>-<región>. Por defecto sql. En el proyecto único el destroy de un entorno ya no borra el proyecto, y el nombre de una instancia borrada no se puede reutilizar de inmediato (HYPOTHESIS: hasta una semana, según la documentación de Cloud SQL): para volver a crear el entorno antes, se cambia (por ejemplo sql2)."
  type        = string
  default     = "sql"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,14}[a-z0-9]$", var.sql_instance_name))
    error_message = "sql_instance_name debe tener de 2 a 16 caracteres: minúsculas, dígitos y guiones, empezando con letra y sin terminar en guion."
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

# ---------------------------------------------------------------------------------------------
# Apagado fuera de horario (solo dev y qa, ADR 0028)
# ---------------------------------------------------------------------------------------------

variable "off_hours_shutdown" {
  description = <<-EOT
    Apagado fuera de horario de dev y qa (ADR 0028). Con enabled = true:
    - Cloud SQL se detiene a la hora de stop_schedule y se enciende a la de start_schedule
      (trabajos de Cloud Scheduler, módulo off-hours-shutdown);
    - el MIG (enable_mig) baja a 0 VM fuera del horario con un programa de escalado nativo y
      tiene mig_min_replicas VM durante el horario, sin autoescalado por CPU;
    - los pools de GKE (enable_gke) se llevan a 0 nodos y vuelven a su mínimo con el
      autoescalado reactivado;
    - la ventana de Backup and DR pasa al horario encendido.
    Cloud Run ya escala a 0 (min_instances = 0); Memorystore y Filestore no se pueden detener.
    Los crons van en time_zone con la forma "M H * * D" (minuto, hora, días de la semana 0-6) y
    los mismos días en los dos. La cuenta de los trabajos (<prefix>-<environment>-<app>-sched) la
    crea 1-base con el rol del apagado si off_hours_environments de 1-base incluye el entorno.
    Se rechaza en prod y con enable_dr.
  EOT
  type = object({
    enabled        = bool
    time_zone      = optional(string, "America/Mexico_City")
    start_schedule = optional(string, "0 7 * * 1-5")
    stop_schedule  = optional(string, "0 20 * * 1-5")
  })
  default  = { enabled = false }
  nullable = false

  validation {
    condition     = var.environment != "prod" || !var.off_hours_shutdown.enabled
    error_message = "off_hours_shutdown no se admite en prod: el apagado fuera de horario es solo para dev y qa (ADR 0028)."
  }
  validation {
    condition     = !var.off_hours_shutdown.enabled || !var.enable_dr
    error_message = "off_hours_shutdown no se admite con enable_dr: la réplica de Cloud SQL no se puede detener (ADR 0028)."
  }
  validation {
    condition = alltrue([
      for c in [var.off_hours_shutdown.start_schedule, var.off_hours_shutdown.stop_schedule] :
      can(regex("^([0-9]|[1-5][0-9]) ([0-9]|1[0-9]|2[0-3]) \\* \\* (\\*|[0-6](-[0-6])?(,[0-6](-[0-6])?)*)$", c))
    ])
    error_message = "start_schedule y stop_schedule deben tener la forma \"M H * * D\": minuto 0-59, hora 0-23, día del mes y mes en *, y días de la semana * o una lista de 0-6 con rangos (por ejemplo 1-5)."
  }
  validation {
    condition     = try(split(" ", var.off_hours_shutdown.start_schedule)[4] == split(" ", var.off_hours_shutdown.stop_schedule)[4], false)
    error_message = "start_schedule y stop_schedule deben tener los mismos días de la semana (el horario encendido empieza y termina el mismo día)."
  }
  validation {
    condition = try(
      (tonumber(split(" ", var.off_hours_shutdown.stop_schedule)[1]) * 60 + tonumber(split(" ", var.off_hours_shutdown.stop_schedule)[0])) -
      (tonumber(split(" ", var.off_hours_shutdown.start_schedule)[1]) * 60 + tonumber(split(" ", var.off_hours_shutdown.start_schedule)[0])) >= 60,
      false
    )
    error_message = "stop_schedule debe caer al menos 60 minutos después de start_schedule, el mismo día."
  }
  validation {
    # El segundo paso del apagado de GKE corre 10 minutos después (gke_step_minutes del módulo).
    condition     = try(tonumber(split(" ", var.off_hours_shutdown.stop_schedule)[1]) * 60 + tonumber(split(" ", var.off_hours_shutdown.stop_schedule)[0]) + 10 <= 1439, false)
    error_message = "stop_schedule debe ser a más tardar a las 23:29: el segundo paso del apagado de GKE corre 10 minutos después, el mismo día."
  }
  validation {
    condition     = can(regex("^(UTC|[A-Za-z_]+(/[A-Za-z0-9_+-]+)+)$", var.off_hours_shutdown.time_zone))
    error_message = "off_hours_shutdown.time_zone debe ser UTC o un nombre IANA como America/Monterrey."
  }
  validation {
    # La ventana diaria de Backup and DR (6 horas, empieza en hora cerrada) debe caber en el
    # horario encendido: con Cloud SQL detenida, el respaldo de ese día no se toma.
    condition = !var.off_hours_shutdown.enabled || !var.enable_backup || try(
      ceil((tonumber(split(" ", var.off_hours_shutdown.start_schedule)[1]) * 60 + tonumber(split(" ", var.off_hours_shutdown.start_schedule)[0])) / 60) * 60 + 360 <=
      tonumber(split(" ", var.off_hours_shutdown.stop_schedule)[1]) * 60 + tonumber(split(" ", var.off_hours_shutdown.stop_schedule)[0]),
      false
    )
    error_message = "Con enable_backup, el horario encendido debe contener la ventana de respaldo de 6 horas que empieza en la primera hora cerrada desde start_schedule (por ejemplo, 07:00 a 13:00 con encendido a las 07:00)."
  }
}
