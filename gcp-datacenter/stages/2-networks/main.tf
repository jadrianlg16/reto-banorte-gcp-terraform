# Raíz del hub (ADR 0029 §2 y §6, ADR 0014): VPC hub, conectividad híbrida, políticas de
# firewall de red de las VPC comunes (hub y onprem-sim) y DNS, todo en el proyecto único de la
# landing zone (project_id). Los spokes viven en envs/<env> y se unen al hub por peering
# (ADR 0003).
#
# Archivos: main.tf (red), vpn.tf (HA VPN, on-premises simulado e Interconnect),
# firewall.tf (políticas de red del hub y de onprem-sim) y dns.tf (reenvío, política de
# servidor y registro DNS de onprem-sim).
#
# Las APIs del proyecto (compute, dns y, con on-premises real, secretmanager) las habilita
# 0-bootstrap una sola vez (ADR 0029 §2); esta raíz no declara ninguna.

locals {
  # El hub vive en el entorno common (contrato §4.2).
  environment = "common"

  labels = merge(var.labels, {
    env        = local.environment
    managed_by = "terraform"
  })

  # Rango de origen del reenvío de Cloud DNS hacia on-premises: se anuncia por BGP para que
  # las respuestas vuelvan por la VPN.
  cloud_dns_forwarding_range = "35.199.192.0/19"

  # Anuncios BGP personalizados hacia on-premises: el /16 del hub, el /16 de cada spoke y el
  # rango de reenvío de Cloud DNS.
  advertised_ranges = distinct(concat(
    [var.hub_supernet],
    [for env in sort(keys(var.spoke_supernets)) : var.spoke_supernets[env]],
    [local.cloud_dns_forwarding_range],
  ))
}

# VPC hub: sin ruta por defecto a internet (solo la del VIP restringido), subred primaria y
# de DR, y un Cloud Router por región con el ASN del hub.
module "hub" {
  source = "../../modules/network-hub"

  project_id         = var.project_id
  prefix             = var.prefix
  environment        = local.environment
  network_suffix     = "hub"
  router_asn         = var.hub_asn
  region_short_names = var.region_short_names

  subnets = {
    hub = {
      region      = var.primary_region
      cidr        = var.hub_cidrs["hub"]
      description = "Subred del hub en la región primaria."
    }
    hub_dr = {
      region      = var.dr_region
      cidr        = var.hub_cidrs["hub_dr"]
      description = "Subred del hub en la región de DR."
    }
  }
}
