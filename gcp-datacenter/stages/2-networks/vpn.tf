# Conectividad híbrida: dos HA VPN, cada una con dos túneles y BGP (SLA 99.99 %):
# - primaria, en el Cloud Router del hub en primary_region (y los attachments de Interconnect
#   si enable_interconnect = true);
# - de DR, en el Cloud Router del hub en dr_region (enable_vpn_dr, encendida por defecto), con
#   un valor de advertised_route_priority mayor (menos preferida): on-premises entra por la
#   primaria mientras exista y por la de DR si se pierde la región primaria.
# La punta remota depende de simulate_onprem (ADR 0006):
# - true: VPC onprem-sim en el mismo proyecto, con su propio Cloud Router y gateway HA VPN en
#   cada región; cada instancia del módulo hybrid-connectivity apunta al gateway de la otra.
# - false: gateway externo con las IP de onprem_vpn_gateway_ips (las mismas para las dos VPN).

locals {
  onprem_secret = var.onprem_vpn_secret_id == null ? null : regex("^projects/([^/]+)/secrets/([^/]+)$", var.onprem_vpn_secret_id)

  # Prioridad de las rutas que anuncian las sesiones de la VPN primaria (la del módulo por
  # defecto). La de DR (vpn_dr_route_priority) debe ser mayor.
  vpn_primary_route_priority = 100

  # Túneles de la VPN real y versión del secreto que usa cada uno. Cambiar el secreto
  # reemplaza el túnel (shared_secret fuerza el reemplazo en el proveedor): con una versión
  # por túnel (onprem_vpn_secret_version_overrides) se rota de uno en uno.
  vpn_tunnel_keys = concat(["primary-if0", "primary-if1"], var.enable_vpn_dr ? ["dr-if0", "dr-if1"] : [])
  vpn_secret_versions = var.simulate_onprem ? {} : {
    for t in local.vpn_tunnel_keys : t => lookup(var.onprem_vpn_secret_version_overrides, t, var.onprem_vpn_secret_version)
  }

  # El secreto compartido nunca entra por variables (contrato §7.3). Con on-premises real se
  # lee de Secret Manager; en modo simulado lo genera random_password. En los dos casos el
  # valor queda en el estado de Terraform, que vive en el bucket con CMEK (ADR 0006 y 0008).
  vpn_secret_by_version = { for v, d in data.google_secret_manager_secret_version.vpn_shared_secret : v => d.secret_data }
  vpn_shared_secret     = var.simulate_onprem ? random_password.vpn_shared_secret[0].result : local.vpn_secret_by_version[var.onprem_vpn_secret_version]

  # Secreto propio de cada túnel cuya versión difiere de onprem_vpn_secret_version.
  vpn_secret_overrides = {
    for site in ["primary", "dr"] : site => {
      for t in ["if0", "if1"] : t => local.vpn_secret_by_version[local.vpn_secret_versions["${site}-${t}"]]
      if contains(keys(local.vpn_secret_versions), "${site}-${t}") && try(local.vpn_secret_versions["${site}-${t}"] != var.onprem_vpn_secret_version, false)
    }
  }

  # Sesiones BGP: el Cloud Router del hub toma la primera IP de cada /30 y el par la segunda.
  hub_bgp_sessions = {
    if0 = { vpn_gateway_interface = 0, ip_range = var.vpn_bgp_ranges[0], advertised_route_priority = local.vpn_primary_route_priority }
    if1 = { vpn_gateway_interface = 1, ip_range = var.vpn_bgp_ranges[1], advertised_route_priority = local.vpn_primary_route_priority }
  }
  hub_dr_bgp_sessions = {
    if0 = { vpn_gateway_interface = 0, ip_range = var.vpn_dr_bgp_ranges[0], advertised_route_priority = var.vpn_dr_route_priority }
    if1 = { vpn_gateway_interface = 1, ip_range = var.vpn_dr_bgp_ranges[1], advertised_route_priority = var.vpn_dr_route_priority }
  }

  # Punta simulada: invierte las IP de cada /30 y conserva la prioridad de su sitio.
  sim_bgp_sessions = {
    for k, s in local.hub_bgp_sessions : k => merge(s, {
      router_ip = cidrhost(s.ip_range, 2)
      peer_ip   = cidrhost(s.ip_range, 1)
    })
  }
  sim_dr_bgp_sessions = {
    for k, s in local.hub_dr_bgp_sessions : k => merge(s, {
      router_ip = cidrhost(s.ip_range, 2)
      peer_ip   = cidrhost(s.ip_range, 1)
    })
  }

  hub_peer = {
    type                  = "external"
    asn                   = var.onprem_asn
    external_gateway_ips  = var.onprem_vpn_gateway_ips
    gcp_gateway_self_link = null
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

# Secreto del modo real: lo carga el equipo de red en Secret Manager fuera de Terraform. Se
# lee una vez por versión distinta en uso (versiones numéricas fijas: una rotación entra con
# un PR que cambia la versión, nunca sola). La cuenta de servicio del hub (<prefix>-tf-net)
# necesita roles/secretmanager.secretAccessor sobre el secreto.
data "google_secret_manager_secret_version" "vpn_shared_secret" {
  for_each = var.simulate_onprem ? toset([]) : toset(concat([var.onprem_vpn_secret_version], values(local.vpn_secret_versions)))

  project = local.onprem_secret[0]
  secret  = local.onprem_secret[1]
  version = each.value
}

# Punta del hub en la región primaria. advertised_ranges: hub, spokes y 35.199.192.0/19.
module "vpn_hub" {
  source = "../../modules/hybrid-connectivity"

  project_id              = var.project_id
  prefix                  = var.prefix
  environment             = local.environment
  connection_name         = "onprem"
  region                  = var.primary_region
  network                 = module.hub.network_self_link
  router                  = module.hub.routers[var.primary_region]
  shared_secret           = local.vpn_shared_secret
  shared_secret_overrides = local.vpn_secret_overrides["primary"]
  bgp_sessions            = local.hub_bgp_sessions
  advertised_ranges       = local.advertised_ranges
  region_short_names      = var.region_short_names
  labels                  = local.labels

  peer = var.simulate_onprem ? {
    type                  = "gcp"
    asn                   = var.onprem_asn
    external_gateway_ips  = []
    gcp_gateway_self_link = module.vpn_onprem_sim[0].gateway_self_link
  } : local.hub_peer

  enable_interconnect      = var.enable_interconnect
  interconnect_attachments = var.interconnect_attachments
}

# Punta del hub en la región de DR (decisión de conmutación por error): mismo par, mismos
# anuncios, sus propios /30 y una prioridad mayor. Con on-premises real crea su propio gateway
# externo (<prefix>-common-net-vpn-onprem-dr-peer) con las mismas IP.
# VERIFICAR-EN-APPLY: que on-premises reciba los anuncios de las dos VPN y prefiera la
# primaria (MED menor), y que al caer la primaria el tráfico pase a la de DR.
module "vpn_hub_dr" {
  source = "../../modules/hybrid-connectivity"
  count  = var.enable_vpn_dr ? 1 : 0

  project_id              = var.project_id
  prefix                  = var.prefix
  environment             = local.environment
  connection_name         = "onprem-dr"
  region                  = var.dr_region
  network                 = module.hub.network_self_link
  router                  = module.hub.routers[var.dr_region]
  shared_secret           = local.vpn_shared_secret
  shared_secret_overrides = local.vpn_secret_overrides["dr"]
  bgp_sessions            = local.hub_dr_bgp_sessions
  advertised_ranges       = local.advertised_ranges
  region_short_names      = var.region_short_names
  labels                  = local.labels

  peer = var.simulate_onprem ? {
    type                  = "gcp"
    asn                   = var.onprem_asn
    external_gateway_ips  = []
    gcp_gateway_self_link = module.vpn_onprem_sim_dr[0].gateway_self_link
  } : local.hub_peer
}

# ---------------------------------------------------------------------------------------
# On-premises simulado (ADR 0006)

# VPC onprem-sim en el proyecto único con una subred (192.168.0.0/24) y un Cloud Router
# con el ASN de on-premises en la región primaria y, con enable_vpn_dr, otro en la de DR
# (sin subred: solo termina la VPN de DR). Reutiliza network-hub con otro sufijo de nombre.
module "onprem_sim" {
  source = "../../modules/network-hub"
  count  = var.simulate_onprem ? 1 : 0

  project_id           = var.project_id
  prefix               = var.prefix
  environment          = local.environment
  network_suffix       = "onprem-sim"
  router_asn           = var.onprem_asn
  region_short_names   = var.region_short_names
  extra_router_regions = var.enable_vpn_dr ? [var.dr_region] : []

  subnets = {
    onprem_sim = {
      region      = var.primary_region
      cidr        = var.onprem_sim_cidr
      description = "Subred de la VPC que simula on-premises (ADR 0006)."
    }
  }
}

# Punta simulada de la VPN primaria: invierte las IP de cada /30 y anuncia solo su subred.
module "vpn_onprem_sim" {
  source = "../../modules/hybrid-connectivity"
  count  = var.simulate_onprem ? 1 : 0

  project_id         = var.project_id
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
  bgp_sessions       = local.sim_bgp_sessions

  peer = {
    type                  = "gcp"
    asn                   = var.hub_asn
    gcp_gateway_self_link = module.vpn_hub.gateway_self_link
  }
}

# Punta simulada de la VPN de DR, en el router de DR de onprem-sim. Los nombres regionales
# llevan el código de la región (…-vpn-onprem-sim-use4), así que no chocan con la primaria.
module "vpn_onprem_sim_dr" {
  source = "../../modules/hybrid-connectivity"
  count  = var.simulate_onprem && var.enable_vpn_dr ? 1 : 0

  project_id         = var.project_id
  prefix             = var.prefix
  environment        = local.environment
  connection_name    = "onprem-sim"
  region             = var.dr_region
  network            = module.onprem_sim[0].network_self_link
  router             = module.onprem_sim[0].routers[var.dr_region]
  shared_secret      = local.vpn_shared_secret
  advertised_ranges  = [var.onprem_sim_cidr]
  region_short_names = var.region_short_names
  labels             = local.labels
  bgp_sessions       = local.sim_dr_bgp_sessions

  peer = {
    type                  = "gcp"
    asn                   = var.hub_asn
    gcp_gateway_self_link = module.vpn_hub_dr[0].gateway_self_link
  }
}
