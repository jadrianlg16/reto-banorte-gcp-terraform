# Raíz del hub (contrato §7.3, ADR 0014): VPC hub en el proyecto net-hub, conectividad
# híbrida, política de firewall jerárquica de la organización y DNS. Los spokes viven en
# envs/<env> y se unen al hub por peering (ADR 0003).
#
# Archivos: main.tf (red), vpn.tf (HA VPN, on-premises simulado e Interconnect),
# firewall.tf (política jerárquica) y dns.tf (reenvío, política de servidor y registro DNS de
# onprem-sim).

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

# APIs del proyecto net-hub que usa esta raíz. El proyecto lo crea 1-org; habilitarlas aquí
# hace que la raíz no dependa de cómo las dejó esa etapa. disable_on_destroy = false: quitar
# esta raíz no apaga APIs que otra etapa pueda usar.
resource "google_project_service" "hub" {
  for_each = toset(["compute.googleapis.com", "dns.googleapis.com"])

  project                    = local.hub_project_id
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = false
}

# VPC hub: sin ruta por defecto a internet (solo la del VIP restringido), subred primaria y
# de DR, y un Cloud Router por región con el ASN del hub.
module "hub" {
  source = "../../modules/network-hub"

  project_id         = local.hub_project_id
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

  depends_on = [google_project_service.hub]
}
