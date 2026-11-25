variable "project_id" {
  description = "ID del proyecto donde se crea la VPC (proyecto net-hub)."
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
  description = "Entorno que se usa en los nombres. El hub vive en common."
  type        = string
  default     = "common"

  validation {
    condition     = contains(["common", "dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser common, dev, qa o prod."
  }
}

variable "network_suffix" {
  description = "Recurso que cierra el nombre de la VPC: <prefix>-<environment>-net-<network_suffix>. Por defecto hub; la VPC simulada de on-premises (ADR 0006) usa onprem-sim."
  type        = string
  default     = "hub"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}[a-z0-9]$", var.network_suffix))
    error_message = "network_suffix debe tener de 2 a 32 caracteres: minúsculas, dígitos y guiones."
  }
}

variable "subnets" {
  description = "Subredes de la VPC. Llave = nombre lógico (por ejemplo hub, hub_dr); valor = región y CIDR primario. Todas son privadas, con Private Google Access y flow logs."
  type = map(object({
    region      = string
    cidr        = string
    description = optional(string, "")
  }))

  validation {
    condition     = length(var.subnets) > 0
    error_message = "subnets debe tener al menos una subred."
  }
  validation {
    condition     = alltrue([for k in keys(var.subnets) : can(regex("^[a-z][a-z0-9_]{0,20}$", k))])
    error_message = "Las llaves de subnets deben ser minúsculas, dígitos o guion bajo (hasta 21 caracteres)."
  }
  validation {
    condition     = alltrue([for s in values(var.subnets) : can(cidrhost(s.cidr, 0)) && can(regex("^[0-9.]+/[0-9]+$", s.cidr))])
    error_message = "Cada subnets[*].cidr debe ser un CIDR IPv4 válido."
  }
  validation {
    condition     = alltrue([for s in values(var.subnets) : contains(keys(var.region_short_names), s.region)])
    error_message = "Cada subnets[*].region debe existir en region_short_names."
  }
  validation {
    condition = alltrue(flatten([
      for a, sa in var.subnets : [
        # Dos bloques CIDR se traslapan si coinciden al truncarlos al prefijo más corto.
        # try(): un CIDR inválido lo reporta la validación anterior, no esta.
        for b, sb in var.subnets : a == b || try(
          cidrhost("${cidrhost(sa.cidr, 0)}/${min(tonumber(split("/", sa.cidr)[1]), tonumber(split("/", sb.cidr)[1]))}", 0) !=
          cidrhost("${cidrhost(sb.cidr, 0)}/${min(tonumber(split("/", sa.cidr)[1]), tonumber(split("/", sb.cidr)[1]))}", 0),
          true
        )
      ]
    ]))
    error_message = "Los CIDR de subnets no deben traslaparse entre sí."
  }
}

variable "extra_router_regions" {
  description = "Regiones donde se crea un Cloud Router aunque la VPC no tenga subred allí (por ejemplo, la región de DR de la VPC simulada de on-premises, que solo necesita el router para su HA VPN). Por defecto ninguna: un router por región con subred."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for r in var.extra_router_regions : contains(keys(var.region_short_names), r)])
    error_message = "Cada región de extra_router_regions debe existir en region_short_names."
  }
}

variable "router_asn" {
  description = "ASN privado de los Cloud Router del hub (hub_asn del plan de direccionamiento, por ejemplo 64514)."
  type        = number

  validation {
    condition     = (var.router_asn >= 64512 && var.router_asn <= 65534) || (var.router_asn >= 4200000000 && var.router_asn <= 4294967294)
    error_message = "router_asn debe ser un ASN privado (64512-65534 o 4200000000-4294967294)."
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
