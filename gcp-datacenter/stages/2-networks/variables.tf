# Comprobación de traslape usada en varias validaciones: dos bloques CIDR se traslapan si
# coinciden al truncarlos al prefijo más corto. try(..., true): un CIDR inválido lo reporta
# la validación de formato de su propia variable, no la de traslape.

variable "project_id" {
  description = "ID del proyecto único de la landing zone (ADR 0029 §1; salida project_id de 0-bootstrap). Aquí viven el hub, onprem-sim y los spokes. Lo crea una persona: esta raíz no lo crea ni lo borra."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id debe ser un ID de proyecto válido de GCP (6 a 30 caracteres, minúsculas, dígitos y guiones)."
  }
}

variable "prefix" {
  description = "Prefijo de la empresa en los nombres (por ejemplo, bnt)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.prefix))
    error_message = "prefix debe tener de 2 a 6 caracteres: minúsculas y dígitos, empezando con letra."
  }
}

variable "primary_region" {
  description = "Región primaria (subred hub, HA VPN y su Cloud Router)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.primary_region)) && contains(keys(var.region_short_names), var.primary_region)
    error_message = "primary_region debe ser una región de GCP (por ejemplo us-central1) presente en region_short_names."
  }
}

variable "dr_region" {
  description = "Región de recuperación (subred hub_dr y su Cloud Router)."
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

variable "hub_supernet" {
  description = "Bloque /16 del hub (plan de direccionamiento: 10.0.0.0/16). Se anuncia a on-premises por BGP y debe contener hub_cidrs."
  type        = string

  validation {
    condition     = can(cidrhost(var.hub_supernet, 0)) && try(tonumber(split("/", var.hub_supernet)[1]) == 16, false)
    error_message = "hub_supernet debe ser un CIDR /16."
  }
  validation {
    condition = alltrue([
      for o in var.onprem_cidrs : try(
        cidrhost("${cidrhost(var.hub_supernet, 0)}/${min(16, tonumber(split("/", o)[1]))}", 0) !=
        cidrhost("${cidrhost(o, 0)}/${min(16, tonumber(split("/", o)[1]))}", 0),
        true
      )
    ])
    error_message = "hub_supernet no debe traslaparse con onprem_cidrs."
  }
}

variable "hub_cidrs" {
  description = "Subredes del hub: llave hub (región primaria) y hub_dr (región de DR) → CIDR (plan: 10.0.0.0/24 y 10.0.1.0/24)."
  type        = map(string)

  validation {
    condition     = toset(keys(var.hub_cidrs)) == toset(["hub", "hub_dr"])
    error_message = "hub_cidrs debe tener exactamente las llaves hub y hub_dr."
  }
  validation {
    condition     = alltrue([for c in values(var.hub_cidrs) : can(cidrhost(c, 0)) && can(regex("^[0-9.]+/[0-9]+$", c))])
    error_message = "Cada valor de hub_cidrs debe ser un CIDR IPv4 válido."
  }
  validation {
    condition = alltrue([
      for c in values(var.hub_cidrs) : try(
        tonumber(split("/", c)[1]) >= 16 &&
        cidrhost("${cidrhost(c, 0)}/16", 0) == cidrhost(var.hub_supernet, 0),
        true
      )
    ])
    error_message = "Cada rango de hub_cidrs debe caber en hub_supernet."
  }
  validation {
    condition = alltrue(flatten([
      for c in values(var.hub_cidrs) : [
        for o in var.onprem_cidrs : try(
          cidrhost("${cidrhost(c, 0)}/${min(tonumber(split("/", c)[1]), tonumber(split("/", o)[1]))}", 0) !=
          cidrhost("${cidrhost(o, 0)}/${min(tonumber(split("/", c)[1]), tonumber(split("/", o)[1]))}", 0),
          true
        )
      ]
    ]))
    error_message = "Ningún rango de hub_cidrs debe traslaparse con onprem_cidrs."
  }
}

variable "spoke_supernets" {
  description = "Mapa entorno (dev, qa, prod) → /16 de su spoke (plan: 10.10.0.0/16, 10.20.0.0/16, 10.30.0.0/16). El hub los anuncia a on-premises por BGP."
  type        = map(string)

  validation {
    condition     = length(var.spoke_supernets) > 0 && alltrue([for k in keys(var.spoke_supernets) : contains(["dev", "qa", "prod"], k)])
    error_message = "spoke_supernets debe tener al menos una llave y solo dev, qa o prod."
  }
  validation {
    condition     = alltrue([for c in values(var.spoke_supernets) : can(cidrhost(c, 0)) && try(tonumber(split("/", c)[1]) == 16, false)])
    error_message = "Cada valor de spoke_supernets debe ser un CIDR /16."
  }
  validation {
    condition = alltrue(flatten([
      for c in values(var.spoke_supernets) : [
        for o in concat(var.onprem_cidrs, [var.hub_supernet]) : try(
          cidrhost("${cidrhost(c, 0)}/${min(16, tonumber(split("/", o)[1]))}", 0) !=
          cidrhost("${cidrhost(o, 0)}/${min(16, tonumber(split("/", o)[1]))}", 0),
          true
        )
      ]
    ]))
    error_message = "Ningún spoke_supernet debe traslaparse con onprem_cidrs ni con hub_supernet."
  }
  validation {
    condition     = length(distinct(values(var.spoke_supernets))) == length(var.spoke_supernets)
    error_message = "Cada entorno necesita su propio /16 en spoke_supernets."
  }
}

variable "onprem_cidrs" {
  description = "Rangos de on-premises, real o simulado (plan: 192.168.0.0/16). Ningún rango de GCP puede traslaparse con ellos."
  type        = list(string)

  validation {
    condition     = length(var.onprem_cidrs) > 0 && alltrue([for c in var.onprem_cidrs : can(cidrhost(c, 0)) && can(regex("^[0-9.]+/[0-9]+$", c))])
    error_message = "onprem_cidrs debe tener al menos un CIDR IPv4 válido."
  }
}

variable "hub_asn" {
  description = "ASN privado de los Cloud Router del hub (plan: 64514)."
  type        = number

  validation {
    condition     = (var.hub_asn >= 64512 && var.hub_asn <= 65534) || (var.hub_asn >= 4200000000 && var.hub_asn <= 4294967294)
    error_message = "hub_asn debe ser un ASN privado (64512-65534 o 4200000000-4294967294)."
  }
}

variable "onprem_asn" {
  description = "ASN del router on-premises (plan: 65001). Con on-premises real puede ser público (de 2 o 4 bytes) o privado. En modo simulado es el ASN del Cloud Router de la VPC onprem-sim y debe ser privado."
  type        = number

  # Públicos de 2 bytes (1-64495 sin 23456, AS_TRANS), privados de 2 bytes (64512-65534),
  # públicos de 4 bytes (131072-4199999999) y privados de 4 bytes (4200000000-4294967294).
  validation {
    condition = (
      (var.onprem_asn >= 1 && var.onprem_asn <= 64495 && var.onprem_asn != 23456) ||
      (var.onprem_asn >= 64512 && var.onprem_asn <= 65534) ||
      (var.onprem_asn >= 131072 && var.onprem_asn <= 4294967294)
    ) && floor(var.onprem_asn) == var.onprem_asn
    error_message = "onprem_asn debe ser un ASN válido: público 1-64495 (sin 23456) o 131072-4199999999, o privado 64512-65534 o 4200000000-4294967294."
  }
  validation {
    condition     = !var.simulate_onprem || (var.onprem_asn >= 64512 && var.onprem_asn <= 65534) || (var.onprem_asn >= 4200000000 && var.onprem_asn <= 4294967294)
    error_message = "Con simulate_onprem = true, onprem_asn es el ASN del Cloud Router de onprem-sim y debe ser privado (64512-65534 o 4200000000-4294967294)."
  }
  validation {
    condition     = var.onprem_asn != var.hub_asn
    error_message = "onprem_asn debe ser distinto de hub_asn (sesión eBGP)."
  }
}

variable "vpn_bgp_ranges" {
  description = "Dos /30 de 169.254.0.0/16 para las sesiones BGP de los túneles de la interfaz 0 y 1 (plan: 169.254.0.0/30 y 169.254.0.4/30). El Cloud Router del hub toma la primera IP de cada /30."
  type        = list(string)

  validation {
    condition = length(var.vpn_bgp_ranges) == 2 && length(distinct(var.vpn_bgp_ranges)) == 2 && alltrue([
      for r in var.vpn_bgp_ranges : can(cidrhost(r, 0)) && try(tonumber(split("/", r)[1]) == 30, false) && try(cidrhost("${cidrhost(r, 0)}/16", 0) == "169.254.0.0", false)
    ])
    error_message = "vpn_bgp_ranges debe tener dos /30 distintos dentro de 169.254.0.0/16."
  }
}

variable "enable_vpn_dr" {
  description = "Crea la segunda HA VPN (dos túneles y BGP) en el Cloud Router del hub en dr_region, y con simulate_onprem = true su punta en onprem-sim. Sin ella, perder la región primaria deja a la región de DR sin camino a on-premises."
  type        = bool
  default     = true
}

variable "vpn_dr_bgp_ranges" {
  description = "Dos /30 de 169.254.0.0/16 para las sesiones BGP de la VPN de DR, interfaz 0 y 1 (plan: 169.254.0.8/30 y 169.254.0.12/30). Distintos entre sí y de vpn_bgp_ranges."
  type        = list(string)
  default     = ["169.254.0.8/30", "169.254.0.12/30"]

  validation {
    condition = length(var.vpn_dr_bgp_ranges) == 2 && alltrue([
      for r in var.vpn_dr_bgp_ranges : can(cidrhost(r, 0)) && try(tonumber(split("/", r)[1]) == 30, false) && try(cidrhost("${cidrhost(r, 0)}/16", 0) == "169.254.0.0", false)
    ])
    error_message = "vpn_dr_bgp_ranges debe tener dos /30 dentro de 169.254.0.0/16."
  }
  validation {
    condition = try(
      length(distinct([for r in concat(var.vpn_bgp_ranges, var.vpn_dr_bgp_ranges) : cidrhost(r, 0)])) == length(var.vpn_bgp_ranges) + length(var.vpn_dr_bgp_ranges),
      true
    )
    error_message = "Los /30 de vpn_dr_bgp_ranges deben ser distintos entre sí y de los de vpn_bgp_ranges."
  }
}

variable "vpn_dr_route_priority" {
  description = "advertised_route_priority (MED) de las sesiones BGP de la VPN de DR. Mayor que el de la primaria (100) para que on-premises prefiera la primaria mientras exista."
  type        = number
  default     = 200

  validation {
    condition     = var.vpn_dr_route_priority > 100 && var.vpn_dr_route_priority <= 65535 && floor(var.vpn_dr_route_priority) == var.vpn_dr_route_priority
    error_message = "vpn_dr_route_priority debe ser un entero mayor que 100 (la prioridad de la VPN primaria) y como máximo 65535."
  }
}

variable "simulate_onprem" {
  description = "true: crea la VPC onprem-sim y una HA VPN entre VPC como punta on-premises (ADR 0006), con secreto generado. false: VPN hacia el gateway real de onprem_vpn_gateway_ips con el secreto de onprem_vpn_secret_id."
  type        = bool
  default     = true
}

variable "onprem_sim_cidr" {
  description = "Subred de la VPC simulada onprem-sim (plan: 192.168.0.0/24). Solo se usa con simulate_onprem = true y debe caber en onprem_cidrs."
  type        = string
  default     = "192.168.0.0/24"

  validation {
    condition     = can(cidrhost(var.onprem_sim_cidr, 0)) && can(regex("^[0-9.]+/[0-9]+$", var.onprem_sim_cidr))
    error_message = "onprem_sim_cidr debe ser un CIDR IPv4 válido."
  }
  validation {
    condition = !var.simulate_onprem || anytrue([
      for o in var.onprem_cidrs : try(
        tonumber(split("/", var.onprem_sim_cidr)[1]) >= tonumber(split("/", o)[1]) &&
        cidrhost("${cidrhost(var.onprem_sim_cidr, 0)}/${split("/", o)[1]}", 0) == cidrhost(o, 0),
        false
      )
    ])
    error_message = "Con simulate_onprem = true, onprem_sim_cidr debe caber en uno de los rangos de onprem_cidrs."
  }
}

variable "onprem_vpn_gateway_ips" {
  description = "IP públicas del gateway VPN on-premises (1 o 2). Obligatorias con simulate_onprem = false; deben ir vacías con simulate_onprem = true."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for ip in var.onprem_vpn_gateway_ips : can(cidrhost("${ip}/32", 0)) && can(regex("^[0-9.]+$", ip))])
    error_message = "onprem_vpn_gateway_ips debe contener direcciones IPv4."
  }
  validation {
    condition     = var.simulate_onprem ? length(var.onprem_vpn_gateway_ips) == 0 : contains([1, 2], length(var.onprem_vpn_gateway_ips))
    error_message = "Con simulate_onprem = false se necesitan 1 o 2 IP en onprem_vpn_gateway_ips; con simulate_onprem = true debe ir vacía."
  }
}

variable "onprem_vpn_secret_id" {
  description = "Secreto de Secret Manager con la llave compartida IKE de la VPN real, como projects/<proyecto>/secrets/<nombre>. Obligatorio con simulate_onprem = false y null con simulate_onprem = true. El valor nunca pasa por variables."
  type        = string
  default     = null

  validation {
    condition     = var.onprem_vpn_secret_id == null || can(regex("^projects/[a-z][a-z0-9-]{4,28}[a-z0-9]/secrets/[A-Za-z0-9_-]{1,255}$", var.onprem_vpn_secret_id))
    error_message = "onprem_vpn_secret_id debe tener la forma projects/<proyecto>/secrets/<nombre>."
  }
  validation {
    condition     = var.simulate_onprem ? var.onprem_vpn_secret_id == null : var.onprem_vpn_secret_id != null
    error_message = "onprem_vpn_secret_id es obligatorio con simulate_onprem = false y debe ser null con simulate_onprem = true."
  }
}

variable "onprem_vpn_secret_version" {
  description = "Versión numérica del secreto onprem_vpn_secret_id que usan los túneles (obligatoria con simulate_onprem = false). No se admite latest: cambiar el secreto reemplaza los túneles, y una versión nueva en Secret Manager no debe cambiar la VPN sin un PR. Para rotar un túnel a la vez, ver onprem_vpn_secret_version_overrides."
  type        = string
  default     = null

  validation {
    condition     = var.onprem_vpn_secret_version == null || can(regex("^[1-9][0-9]*$", var.onprem_vpn_secret_version))
    error_message = "onprem_vpn_secret_version debe ser un número de versión (1, 2, …); latest no se admite."
  }
  validation {
    condition     = var.simulate_onprem || var.onprem_vpn_secret_version != null
    error_message = "Con simulate_onprem = false, onprem_vpn_secret_version es obligatoria."
  }
}

variable "onprem_vpn_secret_version_overrides" {
  description = "Versión del secreto propia de algunos túneles de la VPN real, para rotarlos de uno en uno: llave primary-if0, primary-if1, dr-if0 o dr-if1 → versión numérica. Los túneles sin entrada usan onprem_vpn_secret_version. Solo con simulate_onprem = false."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.onprem_vpn_secret_version_overrides : contains(["primary-if0", "primary-if1", "dr-if0", "dr-if1"], k) && can(regex("^[1-9][0-9]*$", v))])
    error_message = "Las llaves de onprem_vpn_secret_version_overrides son primary-if0, primary-if1, dr-if0 o dr-if1, y cada valor es un número de versión."
  }
  validation {
    condition     = !var.simulate_onprem || length(var.onprem_vpn_secret_version_overrides) == 0
    error_message = "onprem_vpn_secret_version_overrides solo aplica con simulate_onprem = false."
  }
}

variable "onprem_dns_domain" {
  description = "Dominio DNS de on-premises que el hub reenvía a onprem_dns_servers (por ejemplo corp.example.com.). Termina en punto."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([-a-z0-9]*[a-z0-9])?\\.)+$", var.onprem_dns_domain))
    error_message = "onprem_dns_domain debe ser un nombre DNS en minúsculas que termine en punto."
  }
}

variable "onprem_dns_servers" {
  description = "IP de los servidores DNS de on-premises (destino del reenvío por la VPN). Deben estar dentro de onprem_cidrs."
  type        = list(string)

  validation {
    condition     = length(var.onprem_dns_servers) > 0 && alltrue([for ip in var.onprem_dns_servers : can(cidrhost("${ip}/32", 0)) && can(regex("^[0-9.]+$", ip))])
    error_message = "onprem_dns_servers debe tener al menos una dirección IPv4."
  }
  validation {
    condition = alltrue([
      for ip in var.onprem_dns_servers : anytrue([
        for o in var.onprem_cidrs : try(cidrhost("${ip}/${split("/", o)[1]}", 0) == cidrhost(o, 0), false)
      ])
    ])
    error_message = "Cada servidor de onprem_dns_servers debe estar dentro de onprem_cidrs (el reenvío privado va por la VPN)."
  }
}

variable "onprem_dns_vm" {
  description = "Crea en onprem-sim la VM DNS de prueba (onprem_dns.tf): e2-micro sin IP pública, Shielded VM y OS Login, en la primera IP de onprem_dns_servers, que responde con autoridad dns.<onprem_dns_domain>. Solo con simulate_onprem = true. Antes deben estar aplicados 0-bootstrap con onprem_dns_vm = true (rol de instancias del hub) y 1-base (cuenta <prefix>-common-net-dns)."
  type        = bool
  default     = false
  nullable    = false

  validation {
    condition     = !var.onprem_dns_vm || var.simulate_onprem
    error_message = "onprem_dns_vm = true necesita simulate_onprem = true: con on-premises real, el DNS lo pone el equipo de red."
  }
  validation {
    condition = !var.onprem_dns_vm || try(
      cidrhost("${var.onprem_dns_servers[0]}/${split("/", var.onprem_sim_cidr)[1]}", 0) == cidrhost(var.onprem_sim_cidr, 0) &&
      !contains([for i in [0, 1, -2, -1] : cidrhost(var.onprem_sim_cidr, i)], var.onprem_dns_servers[0]),
      false
    )
    error_message = "Con onprem_dns_vm = true, la primera IP de onprem_dns_servers debe estar en onprem_sim_cidr y no ser una de las cuatro reservadas de la subred (red, puerta de enlace, penúltima y difusión)."
  }
}

variable "onprem_dns_vm_zone" {
  description = "Zona de la VM DNS de onprem-sim. null (por defecto): <primary_region>-b. Debe ser una zona de primary_region, donde está la subred de onprem-sim."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^${var.primary_region}-[a-z]$", coalesce(var.onprem_dns_vm_zone, "${var.primary_region}-b")))
    error_message = "onprem_dns_vm_zone debe ser una zona de primary_region (por ejemplo us-central1-b)."
  }
}

variable "enable_interconnect" {
  description = "Crea los VLAN attachments de Cloud Interconnect de interconnect_attachments en el router primario del hub. Apagado por defecto."
  type        = bool
  default     = false
}

variable "interconnect_attachments" {
  description = "VLAN attachments de Cloud Interconnect (solo con enable_interconnect = true). Mismo formato que la variable del módulo hybrid-connectivity: type DEDICATED (interconnect, bandwidth, vlan_tag, candidate_subnets) o PARTNER (edge_availability_domain)."
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
    condition     = !var.enable_interconnect || length(var.interconnect_attachments) > 0
    error_message = "Con enable_interconnect = true, interconnect_attachments debe tener al menos un attachment."
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
