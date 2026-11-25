locals {
  # <empresa>-<entorno>-net-vpn-<conexión>-<región> (convención de nombres del contrato).
  short     = var.region_short_names[var.region]
  name_base = "${var.prefix}-${var.environment}-net"
  vpn_name  = "${local.name_base}-vpn-${var.connection_name}-${local.short}"

  router_id = "projects/${var.project_id}/regions/${var.region}/routers/${var.router}"

  is_external       = var.peer.type == "external"
  external_ip_count = length(var.peer.external_gateway_ips)

  # Direcciones BGP de cada sesión: por defecto el Cloud Router toma la primera IP del /30
  # y el par la segunda; la punta simulada las invierte.
  sessions = {
    for k, s in var.bgp_sessions : k => {
      vpn_gateway_interface     = s.vpn_gateway_interface
      router_ip                 = coalesce(s.router_ip, cidrhost(s.ip_range, 1))
      peer_ip                   = coalesce(s.peer_ip, cidrhost(s.ip_range, 2))
      prefix_length             = split("/", s.ip_range)[1]
      advertised_route_priority = s.advertised_route_priority
      peer_external_interface = (
        s.peer_external_interface != null ? s.peer_external_interface :
        local.external_ip_count == 2 ? s.vpn_gateway_interface : 0
      )
    }
  }

  attachments           = var.enable_interconnect ? var.interconnect_attachments : {}
  dedicated_attachments = { for k, a in local.attachments : k => a if a.type == "DEDICATED" }
}

# Gateway HA VPN: dos interfaces con IP externas propias de Google (no son direcciones de
# la VPC ni de las VM).
resource "google_compute_ha_vpn_gateway" "this" {
  project    = var.project_id
  region     = var.region
  name       = local.vpn_name
  network    = var.network
  stack_type = "IPV4_ONLY"
  labels     = var.labels
}

# Gateway externo: representa el equipo on-premises (solo con peer.type = external).
resource "google_compute_external_vpn_gateway" "this" {
  count = local.is_external ? 1 : 0

  project         = var.project_id
  name            = "${local.name_base}-vpn-${var.connection_name}-peer"
  description     = "Gateway VPN on-premises."
  redundancy_type = local.external_ip_count == 2 ? "TWO_IPS_REDUNDANCY" : "SINGLE_IP_INTERNALLY_REDUNDANT"
  labels          = var.labels

  dynamic "interface" {
    for_each = { for i, ip in var.peer.external_gateway_ips : tostring(i) => ip }
    content {
      id         = tonumber(interface.key)
      ip_address = interface.value
    }
  }
}

# Un túnel por interfaz del gateway (SLA 99.99 %), IKEv2.
resource "google_compute_vpn_tunnel" "this" {
  for_each = local.sessions

  project               = var.project_id
  region                = var.region
  name                  = "${local.vpn_name}-${each.key}"
  vpn_gateway           = google_compute_ha_vpn_gateway.this.id
  vpn_gateway_interface = each.value.vpn_gateway_interface
  ike_version           = 2
  # shared_secret fuerza el reemplazo del túnel: un secreto por túnel permite rotarlos de uno
  # en uno (shared_secret_overrides) sin tirar las dos sesiones a la vez.
  shared_secret = lookup(var.shared_secret_overrides, each.key, var.shared_secret)
  router        = local.router_id
  labels        = var.labels

  peer_external_gateway           = local.is_external ? google_compute_external_vpn_gateway.this[0].id : null
  peer_external_gateway_interface = local.is_external ? each.value.peer_external_interface : null
  peer_gcp_gateway                = local.is_external ? null : var.peer.gcp_gateway_self_link
}

resource "google_compute_router_interface" "vpn" {
  for_each = local.sessions

  project    = var.project_id
  region     = var.region
  router     = var.router
  name       = "${local.vpn_name}-${each.key}-if"
  ip_range   = "${each.value.router_ip}/${each.value.prefix_length}"
  vpn_tunnel = google_compute_vpn_tunnel.this[each.key].name
}

# Sesiones BGP con anuncios personalizados: solo se anuncian los rangos de
# advertised_ranges (por ejemplo, el hub, los spokes y el rango de reenvío de Cloud DNS).
resource "google_compute_router_peer" "vpn" {
  for_each = local.sessions

  project                   = var.project_id
  region                    = var.region
  router                    = var.router
  name                      = "${local.vpn_name}-${each.key}-bgp"
  interface                 = google_compute_router_interface.vpn[each.key].name
  ip_address                = each.value.router_ip
  peer_ip_address           = each.value.peer_ip
  peer_asn                  = var.peer.asn
  advertised_route_priority = each.value.advertised_route_priority
  advertise_mode            = "CUSTOM"
  advertised_groups         = []

  dynamic "advertised_ip_ranges" {
    for_each = toset(var.advertised_ranges)
    content {
      range = advertised_ip_ranges.value
    }
  }
}

# ---------------------------------------------------------------------------------------
# Cloud Interconnect (opcional, enable_interconnect = false por defecto)

resource "google_compute_interconnect_attachment" "this" {
  for_each = local.attachments

  project                  = var.project_id
  region                   = var.region
  name                     = "${local.name_base}-ic-${var.connection_name}-${local.short}-${each.key}"
  router                   = local.router_id
  type                     = each.value.type
  interconnect             = each.value.type == "DEDICATED" ? each.value.interconnect : null
  edge_availability_domain = each.value.type == "PARTNER" ? each.value.edge_availability_domain : null
  bandwidth                = each.value.type == "DEDICATED" ? each.value.bandwidth : null
  vlan_tag8021q            = each.value.type == "DEDICATED" ? each.value.vlan_tag : null
  candidate_subnets        = each.value.type == "DEDICATED" && length(each.value.candidate_subnets) > 0 ? each.value.candidate_subnets : null
  mtu                      = tostring(each.value.mtu)
  admin_enabled            = true
  labels                   = var.labels
}

# En DEDICATED, Google asigna las IP BGP del attachment (cloud_router_ip_address y
# customer_router_ip_address) y aquí se crea la interfaz y la sesión. En PARTNER la sesión
# la configura el proveedor.
# VERIFICAR-EN-APPLY: interfaces y sesiones BGP de los attachments (DEDICATED y PARTNER).
resource "google_compute_router_interface" "interconnect" {
  for_each = local.dedicated_attachments

  project                 = var.project_id
  region                  = var.region
  router                  = var.router
  name                    = "${google_compute_interconnect_attachment.this[each.key].name}-if"
  ip_range                = google_compute_interconnect_attachment.this[each.key].cloud_router_ip_address
  interconnect_attachment = google_compute_interconnect_attachment.this[each.key].self_link
}

resource "google_compute_router_peer" "interconnect" {
  for_each = local.dedicated_attachments

  project           = var.project_id
  region            = var.region
  router            = var.router
  name              = "${google_compute_interconnect_attachment.this[each.key].name}-bgp"
  interface         = google_compute_router_interface.interconnect[each.key].name
  peer_ip_address   = split("/", google_compute_interconnect_attachment.this[each.key].customer_router_ip_address)[0]
  peer_asn          = var.peer.asn
  advertise_mode    = "CUSTOM"
  advertised_groups = []

  dynamic "advertised_ip_ranges" {
    for_each = toset(var.advertised_ranges)
    content {
      range = advertised_ip_ranges.value
    }
  }
}
