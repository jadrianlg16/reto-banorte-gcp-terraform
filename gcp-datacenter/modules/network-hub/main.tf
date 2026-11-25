locals {
  # <empresa>-<entorno>-<dominio> (convención de nombres del contrato).
  name_base    = "${var.prefix}-${var.environment}-net"
  network_name = "${local.name_base}-${var.network_suffix}"

  # Regiones distintas que usan las subredes, más las de extra_router_regions: un Cloud
  # Router por cada una.
  regions = toset(concat([for s in values(var.subnets) : s.region], var.extra_router_regions))

  # VIP de restricted.googleapis.com (Private Google Access con VPC Service Controls).
  restricted_vip = "199.36.153.4/30"
}

# VPC en modo personalizado con enrutamiento global: las rutas aprendidas por BGP en una
# región quedan disponibles en todas.
resource "google_compute_network" "this" {
  # checkov:skip=CKV2_GCP_18: las reglas de firewall viven en políticas de firewall de red del módulo firewall (stages/2-networks/firewall.tf para el hub y onprem-sim, envs/<env>/firewall.tf para los spokes), no en este módulo
  project                         = var.project_id
  name                            = local.network_name
  description                     = "VPC ${var.network_suffix} administrada por Terraform."
  auto_create_subnetworks         = false
  routing_mode                    = "GLOBAL"
  delete_default_routes_on_create = true
}

# Subredes privadas: sin IP externas (eso lo impone la política de organización), con
# Private Google Access y flow logs con muestreo de al menos 0.5 (1 por defecto, ADR 0027).
resource "google_compute_subnetwork" "this" {
  for_each = var.subnets

  project                  = var.project_id
  network                  = google_compute_network.this.id
  name                     = "${local.name_base}-${replace(each.key, "_", "-")}-${var.region_short_names[each.value.region]}"
  description              = each.value.description
  region                   = each.value.region
  ip_cidr_range            = each.value.cidr
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = var.flow_log_sampling
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Un Cloud Router por región. Anuncia por defecto sus subredes; los anuncios
# personalizados hacia on-premises se fijan en cada sesión BGP (módulo hybrid-connectivity).
resource "google_compute_router" "this" {
  for_each = local.regions

  project = var.project_id
  network = google_compute_network.this.id
  name    = "${local.name_base}-${var.network_suffix}-router-${var.region_short_names[each.value]}"
  region  = each.value

  bgp {
    asn = var.router_asn
  }
}

# La VPC se crea sin la ruta por defecto a internet: el hub no tiene salida a internet.
# Solo se agrega la ruta al VIP restringido para que Private Google Access funcione.
resource "google_compute_route" "restricted_vip" {
  project          = var.project_id
  network          = google_compute_network.this.id
  name             = "${local.network_name}-restricted-vip"
  description      = "Private Google Access por restricted.googleapis.com."
  dest_range       = local.restricted_vip
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000
}
