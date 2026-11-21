variable "project_id" {
  description = "ID del proyecto de la VPC local (net-hub, o el de la VPC simulada de on-premises)."
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
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.prefix))
    error_message = "prefix debe tener de 2 a 10 caracteres: minúsculas y dígitos, empezando con letra."
  }
}

variable "environment" {
  description = "Entorno que se usa en los nombres. La conectividad híbrida vive en common (hub)."
  type        = string
  default     = "common"

  validation {
    condition     = contains(["common", "dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser common, dev, qa o prod."
  }
}

variable "connection_name" {
  description = "Nombre corto de la conexión, parte de los nombres de gateway, túneles y sesiones. Distingue las dos puntas cuando el hub y la VPC simulada de on-premises (ADR 0006) viven en el mismo proyecto (por ejemplo onprem y onprem-sim)."
  type        = string
  default     = "onprem"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,10}[a-z0-9]$", var.connection_name))
    error_message = "connection_name debe tener de 2 a 12 caracteres: minúsculas, dígitos y guiones."
  }
}

variable "region" {
  description = "Región del gateway HA VPN, de los túneles y del Cloud Router."
  type        = string

  validation {
    condition     = contains(keys(var.region_short_names), var.region)
    error_message = "region debe existir en region_short_names."
  }
}

variable "network" {
  description = "self_link o ID de la VPC local donde se crea el gateway HA VPN."
  type        = string

  validation {
    condition     = can(regex("projects/[^/]+/global/networks/[^/]+$", var.network))
    error_message = "network debe terminar en projects/<proyecto>/global/networks/<nombre>."
  }
}

variable "router" {
  description = "Nombre del Cloud Router existente en la región (salida routers del módulo network-hub). Su ASN es el ASN local de las sesiones."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.router))
    error_message = "router debe ser el nombre de un Cloud Router."
  }
}

variable "peer" {
  description = <<-EOT
    Punta remota. type = external: gateway on-premises con external_gateway_ips (1 IP,
    redundancia interna, o 2 IP, una por interfaz). type = gcp: gateway HA VPN de otra VPC
    (on-premises simulado, ADR 0006) en gcp_gateway_self_link. asn: ASN del router remoto.
  EOT
  type = object({
    type                  = string
    asn                   = number
    external_gateway_ips  = optional(list(string), [])
    gcp_gateway_self_link = optional(string)
  })

  validation {
    condition     = contains(["external", "gcp"], var.peer.type)
    error_message = "peer.type debe ser external o gcp."
  }
  validation {
    condition     = (var.peer.asn >= 64512 && var.peer.asn <= 65534) || (var.peer.asn >= 4200000000 && var.peer.asn <= 4294967294) || (var.peer.asn >= 1 && var.peer.asn <= 64495)
    error_message = "peer.asn debe ser un ASN válido (público 1-64495 o privado 64512-65534 / 4200000000-4294967294)."
  }
  validation {
    condition     = var.peer.type != "external" || (contains([1, 2], length(var.peer.external_gateway_ips)) && alltrue([for ip in var.peer.external_gateway_ips : can(cidrhost("${ip}/32", 0))]))
    error_message = "Con peer.type = external, external_gateway_ips debe tener 1 o 2 IPv4 válidas."
  }
  validation {
    condition     = var.peer.type != "gcp" || (var.peer.gcp_gateway_self_link != null && length(var.peer.external_gateway_ips) == 0)
    error_message = "Con peer.type = gcp, gcp_gateway_self_link es obligatorio y external_gateway_ips debe ir vacío."
  }
}

variable "shared_secret" {
  description = "Secreto compartido IKE de los túneles. No tiene valor por defecto ni sale en ninguna salida: la raíz lo lee de Secret Manager (on-premises real) o lo genera con random_password (on-premises simulado). Queda en el estado de Terraform, que está cifrado con CMEK."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.shared_secret) >= 32
    error_message = "shared_secret debe tener al menos 32 caracteres."
  }
}

variable "bgp_sessions" {
  description = <<-EOT
    Exactamente dos sesiones, una por interfaz del gateway HA VPN (0 y 1), para el SLA de
    99.99 %. Llave = nombre corto del túnel. ip_range: /30 en 169.254.0.0/16. Por defecto el
    Cloud Router usa la primera IP del /30 y el par la segunda; la punta simulada las invierte
    con router_ip y peer_ip. peer_external_interface: interfaz del gateway externo (por
    defecto la misma que vpn_gateway_interface con 2 IP, o 0 con 1 IP).
  EOT
  type = map(object({
    vpn_gateway_interface     = number
    ip_range                  = string
    router_ip                 = optional(string)
    peer_ip                   = optional(string)
    peer_external_interface   = optional(number)
    advertised_route_priority = optional(number, 100)
  }))

  validation {
    condition     = length(var.bgp_sessions) == 2 && toset([for s in values(var.bgp_sessions) : s.vpn_gateway_interface]) == toset([0, 1])
    error_message = "bgp_sessions debe tener exactamente dos sesiones, una en la interfaz 0 y otra en la 1."
  }
  validation {
    condition     = alltrue([for k in keys(var.bgp_sessions) : can(regex("^[a-z][a-z0-9-]{0,8}[a-z0-9]$", k))])
    error_message = "Las llaves de bgp_sessions deben tener de 2 a 10 caracteres: minúsculas, dígitos y guiones."
  }
  validation {
    condition = alltrue([
      for s in values(var.bgp_sessions) : can(cidrhost(s.ip_range, 0)) && try(tonumber(split("/", s.ip_range)[1]) == 30, false) && try(cidrhost("${cidrhost(s.ip_range, 0)}/16", 0) == "169.254.0.0", false)
    ])
    error_message = "bgp_sessions[*].ip_range debe ser un /30 dentro de 169.254.0.0/16."
  }
  validation {
    condition     = length(distinct([for s in values(var.bgp_sessions) : s.ip_range])) == length(var.bgp_sessions)
    error_message = "Cada sesión BGP necesita su propio /30."
  }
  validation {
    condition = alltrue([
      for s in values(var.bgp_sessions) : alltrue([
        for ip in compact([s.router_ip, s.peer_ip]) : try(contains([cidrhost(s.ip_range, 1), cidrhost(s.ip_range, 2)], ip), false)
      ]) && (s.router_ip == null || s.peer_ip == null || s.router_ip != s.peer_ip)
    ])
    error_message = "router_ip y peer_ip deben ser la primera y la segunda IP del /30, distintas entre sí."
  }
  validation {
    condition     = alltrue([for s in values(var.bgp_sessions) : s.advertised_route_priority >= 0 && s.advertised_route_priority <= 65535])
    error_message = "advertised_route_priority debe estar entre 0 y 65535."
  }
}

variable "advertised_ranges" {
  description = "Rangos que el Cloud Router anuncia al par en estas sesiones (modo CUSTOM). En el hub: el /16 del hub, los /16 de los spokes y 35.199.192.0/19 (reenvío de Cloud DNS)."
  type        = list(string)

  validation {
    condition     = length(var.advertised_ranges) > 0 && alltrue([for r in var.advertised_ranges : can(cidrhost(r, 0))])
    error_message = "advertised_ranges debe tener al menos un CIDR válido."
  }
}

variable "enable_interconnect" {
  description = "Crea los VLAN attachments de Cloud Interconnect de interconnect_attachments. Apagado por defecto."
  type        = bool
  default     = false
}

variable "interconnect_attachments" {
  description = "VLAN attachments (solo con enable_interconnect = true). type DEDICATED: interconnect (URL), y opcionales bandwidth, vlan_tag y candidate_subnets (/29 en 169.254.0.0/16); el módulo crea la interfaz y la sesión BGP. type PARTNER: edge_availability_domain; la sesión la configura el proveedor."
  type = map(object({
    type                     = optional(string, "DEDICATED")
    interconnect             = optional(string)
    edge_availability_domain = optional(string)
    bandwidth                = optional(string)
    vlan_tag                 = optional(number)
    candidate_subnets        = optional(list(string), [])
    mtu                      = optional(number, 1440)
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.interconnect_attachments) : can(regex("^[a-z][a-z0-9-]{0,8}[a-z0-9]$", k))])
    error_message = "Las llaves de interconnect_attachments deben tener de 2 a 10 caracteres: minúsculas, dígitos y guiones."
  }
  validation {
    condition     = alltrue([for a in values(var.interconnect_attachments) : contains(["DEDICATED", "PARTNER"], a.type)])
    error_message = "interconnect_attachments[*].type debe ser DEDICATED o PARTNER."
  }
  validation {
    condition     = alltrue([for a in values(var.interconnect_attachments) : a.type != "DEDICATED" || a.interconnect != null])
    error_message = "Un attachment DEDICATED necesita interconnect."
  }
  validation {
    condition     = alltrue([for a in values(var.interconnect_attachments) : a.type != "PARTNER" || contains(["AVAILABILITY_DOMAIN_1", "AVAILABILITY_DOMAIN_2", "AVAILABILITY_DOMAIN_ANY"], coalesce(a.edge_availability_domain, "-"))])
    error_message = "Un attachment PARTNER necesita edge_availability_domain (AVAILABILITY_DOMAIN_1, _2 o _ANY)."
  }
  validation {
    condition     = alltrue([for a in values(var.interconnect_attachments) : contains([1440, 1460, 1500, 8896], a.mtu)])
    error_message = "mtu debe ser 1440, 1460, 1500 u 8896."
  }
  validation {
    condition     = alltrue(flatten([for a in values(var.interconnect_attachments) : [for c in a.candidate_subnets : can(cidrhost(c, 0)) && try(tonumber(split("/", c)[1]) == 29, false)]]))
    error_message = "candidate_subnets debe tener CIDR /29."
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
