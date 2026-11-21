# Comprobación de traslape usada en varias validaciones: dos bloques CIDR se traslapan si
# coinciden al truncarlos al prefijo más corto. try(..., true): un CIDR inválido lo reporta
# la validación de formato de su propia variable, no la de traslape.

variable "billing_account" {
  description = "Cuenta de facturación del proyecto net-spoke (formato XXXXXX-XXXXXX-XXXXXX)."
  type        = string

  validation {
    condition     = can(regex("^[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$", var.billing_account))
    error_message = "billing_account debe tener la forma XXXXXX-XXXXXX-XXXXXX (hexadecimal en mayúsculas)."
  }
}

variable "prefix" {
  description = "Prefijo de la empresa en los nombres (por ejemplo, bnt)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.prefix))
    error_message = "prefix: de 2 a 6 caracteres, minúsculas y dígitos, empieza con letra."
  }
}

variable "project_suffix" {
  description = "Sufijo opcional para que el ID del proyecto net-spoke sea único a nivel mundial. Vacío: sin sufijo."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9]{0,8}$", var.project_suffix))
    error_message = "project_suffix: hasta 8 caracteres en minúsculas o dígitos, sin guiones."
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

variable "primary_region" {
  description = "Región primaria del spoke (subredes app, proxy y run, router y NAT)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.primary_region)) && contains(keys(var.region_short_names), var.primary_region)
    error_message = "primary_region debe ser una región de GCP (por ejemplo us-central1) presente en region_short_names."
  }
}

variable "dr_region" {
  description = "Región de DR del spoke (subredes *_dr, router y NAT; solo con enable_dr = true)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.dr_region)) && contains(keys(var.region_short_names), var.dr_region)
    error_message = "dr_region debe ser una región de GCP (por ejemplo us-east4) presente en region_short_names."
  }
  validation {
    condition     = var.dr_region != var.primary_region
    error_message = "dr_region debe ser distinta de primary_region."
  }
}

variable "region_short_names" {
  description = "Mapa región → código corto que se agrega a los nombres de recursos regionales (contrato §4.2)."
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

variable "enable_dr" {
  description = "Crea las subredes, el router y el NAT de la región de DR. En dev y qa las llaves *_dr se reservan pero no se crean (false)."
  type        = bool
  default     = false
}

variable "spoke_supernet" {
  description = "/16 del spoke (plan: 10.X.0.0/16 con X = 10 dev, 20 qa, 30 prod). Todos los rangos de subnet_cidrs deben caber aquí y debe coincidir con spoke_supernets[environment] del hub, que es lo que se anuncia a on-premises."
  type        = string

  validation {
    condition     = can(cidrhost(var.spoke_supernet, 0)) && try(tonumber(split("/", var.spoke_supernet)[1]) == 16, false)
    error_message = "spoke_supernet debe ser un CIDR /16."
  }
  validation {
    condition = alltrue([
      for o in var.onprem_cidrs : try(
        cidrhost("${cidrhost(var.spoke_supernet, 0)}/${min(16, tonumber(split("/", o)[1]))}", 0) !=
        cidrhost("${cidrhost(o, 0)}/${min(16, tonumber(split("/", o)[1]))}", 0),
        true
      )
    ])
    error_message = "spoke_supernet no debe traslaparse con onprem_cidrs."
  }
  validation {
    condition     = local.hub_spoke_supernet == null || local.hub_spoke_supernet == var.spoke_supernet
    error_message = "spoke_supernet debe coincidir con spoke_supernets[environment] del hub (el rango que el hub anuncia a on-premises)."
  }
}

variable "subnet_cidrs" {
  description = "Rangos del plan de direccionamiento (contrato §5). Llaves: app, proxy, run, gke_master, pods, services, psa y sus *_dr (app_dr, proxy_dr, run_dr, gke_master_dr, pods_dr, services_dr), obligatorias solo con enable_dr = true."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["app", "proxy", "run", "gke_master", "pods", "services", "psa"] : contains(keys(var.subnet_cidrs), k)])
    error_message = "subnet_cidrs debe tener las llaves app, proxy, run, gke_master, pods, services y psa."
  }
  validation {
    condition     = !var.enable_dr || alltrue([for k in ["app_dr", "proxy_dr", "run_dr", "gke_master_dr", "pods_dr", "services_dr"] : contains(keys(var.subnet_cidrs), k)])
    error_message = "Con enable_dr = true, subnet_cidrs debe tener app_dr, proxy_dr, run_dr, gke_master_dr, pods_dr y services_dr."
  }
  validation {
    condition     = alltrue([for c in values(var.subnet_cidrs) : can(cidrhost(c, 0)) && can(regex("^[0-9.]+/[0-9]+$", c))])
    error_message = "Cada valor de subnet_cidrs debe ser un CIDR IPv4 válido."
  }
  validation {
    condition = alltrue([
      for c in values(var.subnet_cidrs) : try(
        tonumber(split("/", c)[1]) >= 16 &&
        cidrhost("${cidrhost(c, 0)}/16", 0) == cidrhost(var.spoke_supernet, 0),
        true
      )
    ])
    error_message = "Cada rango de subnet_cidrs debe caber en spoke_supernet (el /16 del entorno)."
  }
  validation {
    condition = alltrue(flatten([
      for c in values(var.subnet_cidrs) : [
        for o in var.onprem_cidrs : try(
          cidrhost("${cidrhost(c, 0)}/${min(tonumber(split("/", c)[1]), tonumber(split("/", o)[1]))}", 0) !=
          cidrhost("${cidrhost(o, 0)}/${min(tonumber(split("/", c)[1]), tonumber(split("/", o)[1]))}", 0),
          true
        )
      ]
    ]))
    error_message = "Ningún rango de subnet_cidrs debe traslaparse con onprem_cidrs."
  }
}

variable "onprem_cidrs" {
  description = "Rangos de on-premises, real o simulado (plan: 192.168.0.0/16). Ningún rango del spoke puede traslaparse con ellos."
  type        = list(string)

  validation {
    condition     = length(var.onprem_cidrs) > 0 && alltrue([for c in var.onprem_cidrs : can(cidrhost(c, 0)) && can(regex("^[0-9.]+/[0-9]+$", c))])
    error_message = "onprem_cidrs debe tener al menos un CIDR IPv4 válido."
  }
}

variable "onprem_dns_domain" {
  description = "Dominio DNS de on-premises (el mismo que en el hub). El spoke lo resuelve con una zona de peering hacia la VPC hub. Termina en punto."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([-a-z0-9]*[a-z0-9])?\\.)+$", var.onprem_dns_domain))
    error_message = "onprem_dns_domain debe ser un nombre DNS en minúsculas que termine en punto."
  }
}

variable "dns_domain_base" {
  description = "Dominio base de las zonas privadas por entorno: la zona del spoke es <environment>.<dns_domain_base>. Termina en punto."
  type        = string
  default     = "empresa.internal."

  validation {
    condition     = can(regex("^([a-z0-9]([-a-z0-9]*[a-z0-9])?\\.)+$", var.dns_domain_base))
    error_message = "dns_domain_base debe ser un nombre DNS en minúsculas que termine en punto."
  }
}

variable "flow_log_sampling" {
  description = "Fracción de muestreo de los flow logs de las subredes. La especificación pide 0.5; solo se permite subirla."
  type        = number
  default     = 0.5

  validation {
    condition     = var.flow_log_sampling >= 0.5 && var.flow_log_sampling <= 1
    error_message = "flow_log_sampling debe estar entre 0.5 y 1."
  }
}

variable "lb_backend_ports" {
  description = "Puertos TCP en los que los backends con la etiqueta lb_backend reciben tráfico y verificaciones de salud de los balanceadores."
  type        = list(string)
  default     = ["80", "443", "8080"]

  validation {
    condition     = length(var.lb_backend_ports) > 0 && alltrue([for p in var.lb_backend_ports : can(regex("^[0-9]{1,5}(-[0-9]{1,5})?$", p))])
    error_message = "lb_backend_ports debe tener puertos o rangos de puertos (por ejemplo 443 u 8000-8100)."
  }
}

variable "project_deletion_policy" {
  description = "deletion_policy del proyecto net-spoke: PREVENT (por defecto), ABANDON o DELETE. El módulo project-factory solo admite PREVENT en prod; DELETE sirve para desmontar dev en la prueba de extremo a extremo."
  type        = string
  default     = "PREVENT"

  validation {
    condition     = contains(["PREVENT", "ABANDON", "DELETE"], var.project_deletion_policy)
    error_message = "project_deletion_policy debe ser PREVENT, ABANDON o DELETE."
  }
}

variable "labels" {
  description = "Etiquetas comunes de la raíz (app, owner, cost_center y las que se agreguen). env y managed_by las fija la raíz."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["app", "owner", "cost_center"] : contains(keys(var.labels), k)])
    error_message = "labels debe tener app, owner y cost_center (env y managed_by los agrega la raíz)."
  }
  validation {
    condition     = alltrue([for v in values(var.labels) : can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "Los valores de etiquetas van en minúsculas, dígitos, guion o guion bajo."
  }
}

variable "state_bucket" {
  description = "Bucket de estado de Terraform (salida state_bucket de 0-bootstrap) del que se leen las etapas anteriores."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", var.state_bucket))
    error_message = "state_bucket debe ser un nombre de bucket válido."
  }
}
