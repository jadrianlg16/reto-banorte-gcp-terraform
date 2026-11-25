variable "project_id" {
  description = "ID del proyecto donde se crea la VPC spoke y sus recursos (con el ADR 0029, el proyecto único de la landing zone, el mismo del hub)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id debe ser un ID de proyecto válido de GCP (6 a 30 caracteres, minúsculas, dígitos y guiones)."
  }
}

variable "prefix" {
  description = "Prefijo de la empresa para los nombres (por ejemplo, bnt)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.prefix))
    error_message = "prefix debe tener de 2 a 6 caracteres: minúsculas y dígitos, empezando con letra."
  }
}

variable "environment" {
  description = "Entorno del spoke: dev, qa o prod."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser dev, qa o prod."
  }
}

variable "regions" {
  description = "Regiones del spoke: primary (primaria) y dr (recuperación). La de DR solo se usa con enable_dr = true."
  type = object({
    primary = string
    dr      = string
  })

  validation {
    condition     = contains(keys(var.region_short_names), var.regions.primary) && contains(keys(var.region_short_names), var.regions.dr)
    error_message = "regions.primary y regions.dr deben existir en region_short_names."
  }
  validation {
    condition     = var.regions.primary != var.regions.dr
    error_message = "regions.primary y regions.dr deben ser distintas."
  }
}

variable "enable_dr" {
  description = "Crea las subredes, el router y el NAT de la región de DR (llaves *_dr de subnet_cidrs). En dev y qa las llaves *_dr se reservan pero no se crean."
  type        = bool
  default     = false
}

variable "subnet_cidrs" {
  description = "Rangos del plan de direccionamiento. Llaves: app, proxy, run, gke_master, pods, services, psa (siempre) y app_dr, proxy_dr, run_dr, gke_master_dr, pods_dr, services_dr (obligatorias con enable_dr = true). gke_master y gke_master_dr son solo reservas: no crean subred."
  type        = map(string)

  validation {
    condition = alltrue([for k in keys(var.subnet_cidrs) : contains([
      "app", "app_dr", "proxy", "proxy_dr", "run", "run_dr", "gke_master", "gke_master_dr",
      "pods", "services", "pods_dr", "services_dr", "psa",
    ], k)])
    error_message = "subnet_cidrs solo admite las llaves del plan de direccionamiento: app, app_dr, proxy, proxy_dr, run, run_dr, gke_master, gke_master_dr, pods, services, pods_dr, services_dr, psa."
  }
  validation {
    condition     = alltrue([for k in ["app", "proxy", "run", "gke_master", "pods", "services", "psa"] : contains(keys(var.subnet_cidrs), k)])
    error_message = "subnet_cidrs debe tener las llaves app, proxy, run, gke_master, pods, services y psa."
  }
  validation {
    condition     = !var.enable_dr || alltrue([for k in ["app_dr", "proxy_dr", "run_dr", "gke_master_dr", "pods_dr", "services_dr"] : contains(keys(var.subnet_cidrs), k)])
    error_message = "Con enable_dr = true, subnet_cidrs debe tener app_dr, proxy_dr, run_dr, gke_master_dr, pods_dr y services_dr."
  }
  validation {
    condition     = alltrue([for v in values(var.subnet_cidrs) : can(cidrhost(v, 0)) && can(regex("^[0-9.]+/[0-9]+$", v))])
    error_message = "Cada valor de subnet_cidrs debe ser un CIDR IPv4 válido."
  }
  validation {
    condition     = !contains(keys(var.subnet_cidrs), "gke_master") || try(tonumber(split("/", var.subnet_cidrs["gke_master"])[1]) == 28, false)
    error_message = "gke_master debe ser un /28 (plano de control de GKE)."
  }
  validation {
    condition     = !contains(keys(var.subnet_cidrs), "gke_master_dr") || try(tonumber(split("/", var.subnet_cidrs["gke_master_dr"])[1]) == 28, false)
    error_message = "gke_master_dr debe ser un /28 (plano de control de GKE)."
  }
  validation {
    condition     = !contains(keys(var.subnet_cidrs), "psa") || try(tonumber(split("/", var.subnet_cidrs["psa"])[1]) <= 24, false)
    error_message = "psa debe ser un rango de /24 o mayor (Private Service Access)."
  }
  validation {
    condition = alltrue(flatten([
      for a, ca in var.subnet_cidrs : [
        # Dos bloques CIDR se traslapan si coinciden al truncarlos al prefijo más corto.
        # try(): un CIDR inválido lo reporta la validación anterior, no esta.
        for b, cb in var.subnet_cidrs : a == b || try(
          cidrhost("${cidrhost(ca, 0)}/${min(tonumber(split("/", ca)[1]), tonumber(split("/", cb)[1]))}", 0) !=
          cidrhost("${cidrhost(cb, 0)}/${min(tonumber(split("/", ca)[1]), tonumber(split("/", cb)[1]))}", 0),
          true
        )
      ]
    ]))
    error_message = "Los rangos de subnet_cidrs no deben traslaparse entre sí."
  }
}

variable "hub_network_self_link" {
  description = "self_link (o ID projects/<proyecto>/global/networks/<nombre>) de la VPC hub. Se usa para el peering en ambos sentidos: el lado del hub se crea sobre esa red, en su proyecto."
  type        = string

  validation {
    condition     = can(regex("projects/[a-z][a-z0-9-]{4,28}[a-z0-9]/global/networks/[a-z]([-a-z0-9]*[a-z0-9])?$", var.hub_network_self_link))
    error_message = "hub_network_self_link debe terminar en projects/<proyecto>/global/networks/<nombre>."
  }
}

# VERIFICAR-EN-APPLY: que VPC_FLOW_LOGS_SETTINGS_NOT_RECOMMENDED no marque las subredes con 1.0 y
# el volumen de flow logs contra estimacion-de-costos.md (pendiente 62).
variable "flow_log_sampling" {
  description = "Fracción de muestreo de los flow logs. La especificación pide 0.5 como mínimo; solo se permite subirla. Por defecto 1 (100 %, lo que pide el detector de CIS 3.10; ADR 0027)."
  type        = number
  default     = 1

  validation {
    condition     = var.flow_log_sampling >= 0.5 && var.flow_log_sampling <= 1
    error_message = "flow_log_sampling debe estar entre 0.5 y 1."
  }
}

variable "region_short_names" {
  description = "Mapa región → código corto que se agrega a los nombres de recursos regionales."
  type        = map(string)
  default = {
    "us-central1"         = "usc1"
    "us-east4"            = "use4"
    "northamerica-south1" = "nas1"
  }

  validation {
    condition     = alltrue([for v in values(var.region_short_names) : can(regex("^[a-z0-9]{2,6}$", v))])
    error_message = "Los códigos cortos de región deben tener de 2 a 6 minúsculas o dígitos."
  }
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
