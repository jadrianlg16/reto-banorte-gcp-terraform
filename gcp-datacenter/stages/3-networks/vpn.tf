# Conectividad híbrida: HA VPN con dos túneles y BGP (SLA 99.99 %) desde el router primario
# del hub. La punta remota depende de simulate_onprem (ADR 0006):
# - true: VPC onprem-sim en el mismo proyecto, con su propio Cloud Router y gateway HA VPN;
#   cada instancia del módulo hybrid-connectivity apunta al gateway de la otra.
# - false: gateway externo con las IP de onprem_vpn_gateway_ips.

locals {
  onprem_secret = var.onprem_vpn_secret_id == null ? null : regex("^projects/([^/]+)/secrets/([^/]+)$", var.onprem_vpn_secret_id)

  # El secreto compartido nunca entra por variables (contrato §7.3). Con on-premises real se
  # lee de Secret Manager; en modo simulado lo genera random_password. En los dos casos el
  # valor queda en el estado de Terraform, que vive en el bucket con CMEK (ADR 0006 y 0008).
  vpn_shared_secret = var.simulate_onprem ? random_password.vpn_shared_secret[0].result : data.google_secret_manager_secret_version.vpn_shared_secret[0].secret_data

  # Sesiones BGP: el Cloud Router del hub toma la primera IP de cada /30 y el par la segunda.
  hub_bgp_sessions = {
    if0 = { vpn_gateway_interface = 0, ip_range = var.vpn_bgp_ranges[0] }
    if1 = { vpn_gateway_interface = 1, ip_range = var.vpn_bgp_ranges[1] }
  }
}

# Secreto del modo simulado. Solo existe en el estado cifrado: no sale en ninguna salida ni
# se guarda en otro lado. Sin caracteres especiales para evitar problemas de escape en IKE;
# 48 caracteres alfanuméricos dan unos 285 bits de entropía.
resource "random_password" "vpn_shared_secret" {
  count = var.simulate_onprem ? 1 : 0

  length  = 48
  special = false
}

# Secreto del modo real: lo carga el equipo de red en Secret Manager fuera de Terraform. La
# cuenta de servicio de la etapa necesita roles/secretmanager.secretAccessor sobre él.
data "google_secret_manager_secret_version" "vpn_shared_secret" {
  count = var.simulate_onprem ? 0 : 1

  project = local.onprem_secret[0]
  secret  = local.onprem_secret[1]
  version = var.onprem_vpn_secret_version
}

# Punta del hub. advertised_ranges: hub, spokes y 35.199.192.0/19.
module "vpn_hub" {
  source = "../../modules/hybrid-connectivity"

  project_id         = local.hub_project_id
  prefix             = var.prefix
  environment        = local.environment
  connection_name    = "onprem"
  region             = var.primary_region
  network            = module.hub.network_self_link
  router             = module.hub.routers[var.primary_region]
  shared_secret      = local.vpn_shared_secret
  bgp_sessions       = local.hub_bgp_sessions
  advertised_ranges  = local.advertised_ranges
  region_short_names = var.region_short_names
  labels             = local.labels

  peer = var.simulate_onprem ? {
    type                  = "gcp"
    asn                   = var.onprem_asn
    external_gateway_ips  = []
    gcp_gateway_self_link = module.vpn_onprem_sim[0].gateway_self_link
    } : {
    type                  = "external"
    asn                   = var.onprem_asn
    external_gateway_ips  = var.onprem_vpn_gateway_ips
    gcp_gateway_self_link = null
  }

  enable_interconnect      = var.enable_interconnect
  interconnect_attachments = var.interconnect_attachments
}

# ---------------------------------------------------------------------------------------
# On-premises simulado (ADR 0006)

# VPC onprem-sim en el proyecto net-hub con una subred (192.168.0.0/24) y un Cloud Router
# con el ASN de on-premises. Reutiliza network-hub con otro sufijo de nombre.
module "onprem_sim" {
  source = "../../modules/network-hub"
  count  = var.simulate_onprem ? 1 : 0

  project_id         = local.hub_project_id
  prefix             = var.prefix
  environment        = local.environment
  network_suffix     = "onprem-sim"
  router_asn         = var.onprem_asn
  region_short_names = var.region_short_names

  subnets = {
    onprem_sim = {
      region      = var.primary_region
      cidr        = var.onprem_sim_cidr
      description = "Subred de la VPC que simula on-premises (ADR 0006)."
    }
  }

  depends_on = [google_project_service.hub]
}

# Punta simulada: invierte las IP de cada /30 y anuncia solo su subred.
module "vpn_onprem_sim" {
  source = "../../modules/hybrid-connectivity"
  count  = var.simulate_onprem ? 1 : 0

  project_id         = local.hub_project_id
  prefix             = var.prefix
  environment        = local.environment
  connection_name    = "onprem-sim"
  region             = var.primary_region
  network            = module.onprem_sim[0].network_self_link
  router             = module.onprem_sim[0].routers[var.primary_region]
  shared_secret      = local.vpn_shared_secret
  advertised_ranges  = [var.onprem_sim_cidr]
  region_short_names = var.region_short_names
  labels             = local.labels

  peer = {
    type                  = "gcp"
    asn                   = var.hub_asn
    gcp_gateway_self_link = module.vpn_hub.gateway_self_link
  }

  bgp_sessions = {
    for k, s in local.hub_bgp_sessions : k => merge(s, {
      router_ip = cidrhost(s.ip_range, 2)
      peer_ip   = cidrhost(s.ip_range, 1)
    })
  }
}
