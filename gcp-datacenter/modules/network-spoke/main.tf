locals {
  # <empresa>-<entorno>-<dominio> (convención de nombres del contrato).
  name_base = "${var.prefix}-${var.environment}-net"

  # Regiones activas: la primaria siempre, la de DR solo con enable_dr.
  active_regions = var.enable_dr ? {
    primary = var.regions.primary
    dr      = var.regions.dr
  } : { primary = var.regions.primary }

  # Subredes normales (VM, nodos de GKE, salida de Cloud Run). Los rangos secundarios se
  # llaman pods y services en las dos regiones, para que quien los consume use las mismas
  # llaves en subnets[*].secondary_ranges.
  regular_subnets_primary = {
    app = {
      region    = var.regions.primary
      cidr      = var.subnet_cidrs["app"]
      secondary = { pods = var.subnet_cidrs["pods"], services = var.subnet_cidrs["services"] }
    }
    run = {
      region    = var.regions.primary
      cidr      = var.subnet_cidrs["run"]
      secondary = {}
    }
  }
  regular_subnets_dr = var.enable_dr ? {
    app_dr = {
      region    = var.regions.dr
      cidr      = var.subnet_cidrs["app_dr"]
      secondary = { pods = var.subnet_cidrs["pods_dr"], services = var.subnet_cidrs["services_dr"] }
    }
    run_dr = {
      region    = var.regions.dr
      cidr      = var.subnet_cidrs["run_dr"]
      secondary = {}
    }
  } : {}
  regular_subnets = merge(local.regular_subnets_primary, local.regular_subnets_dr)

  # Subredes proxy-only para el balanceador interno regional.
  proxy_subnets = merge(
    { proxy = { region = var.regions.primary, cidr = var.subnet_cidrs["proxy"] } },
    var.enable_dr ? { proxy_dr = { region = var.regions.dr, cidr = var.subnet_cidrs["proxy_dr"] } } : {},
  )

  # Reservas sin subred (plano de control de GKE).
  reserved_cidrs = { for k in ["gke_master", "gke_master_dr"] : k => var.subnet_cidrs[k] if contains(keys(var.subnet_cidrs), k) && (k == "gke_master" || var.enable_dr) }

  # Nombre de subred: la llave sin _dr; la región la distingue el código corto.
  subnet_names = {
    for k, s in merge(local.regular_subnets, local.proxy_subnets) :
    k => "${local.name_base}-${replace(trimsuffix(k, "_dr"), "_", "-")}-${var.region_short_names[s.region]}"
  }

  # Subredes que pasan por el NAT de cada región activa (las proxy-only no).
  nat_subnet_keys = {
    for rk, region in local.active_regions : rk => sort([for k, s in local.regular_subnets : k if s.region == region])
  }

  psa_cidr = var.subnet_cidrs["psa"]

  hub_network    = regex("projects/([^/]+)/global/networks/([^/]+)$", var.hub_network_self_link)
  hub_network_id = "projects/${local.hub_network[0]}/global/networks/${local.hub_network[1]}"

  # VIP de restricted.googleapis.com (Private Google Access con VPC Service Controls).
  restricted_vip = "199.36.153.4/30"
}

# VPC spoke en modo personalizado con enrutamiento global.
resource "google_compute_network" "this" {
  # checkov:skip=CKV2_GCP_18: las reglas de firewall viven en el módulo firewall (política de red con etiquetas seguras), no en este módulo
  project                         = var.project_id
  name                            = "${local.name_base}-spoke"
  description                     = "VPC spoke del entorno ${var.environment}."
  auto_create_subnetworks         = false
  routing_mode                    = "GLOBAL"
  delete_default_routes_on_create = true
}

# Subredes privadas con Private Google Access y flow logs (muestreo de al menos 0.5; 1 por
# defecto, ADR 0027).
resource "google_compute_subnetwork" "this" {
  for_each = local.regular_subnets

  project                  = var.project_id
  network                  = google_compute_network.this.id
  name                     = local.subnet_names[each.key]
  region                   = each.value.region
  ip_cidr_range            = each.value.cidr
  private_ip_google_access = true

  dynamic "secondary_ip_range" {
    for_each = each.value.secondary
    content {
      range_name    = secondary_ip_range.key
      ip_cidr_range = secondary_ip_range.value
    }
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = var.flow_log_sampling
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Subredes proxy-only (REGIONAL_MANAGED_PROXY). GCP no admite Private Google Access ni flow
# logs en este tipo de subred: solo alojan los proxies administrados del balanceador.
resource "google_compute_subnetwork" "proxy" {
  # checkov:skip=CKV_GCP_26: GCP no admite flow logs en subredes proxy-only (REGIONAL_MANAGED_PROXY)
  # checkov:skip=CKV_GCP_74: GCP no admite Private Google Access en subredes proxy-only (REGIONAL_MANAGED_PROXY)
  for_each = local.proxy_subnets

  project       = var.project_id
  network       = google_compute_network.this.id
  name          = local.subnet_names[each.key]
  region        = each.value.region
  ip_cidr_range = each.value.cidr
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

# Rutas explícitas. La VPC se crea sin la ruta por defecto para que las dos salidas queden
# a la vista: el VIP restringido (Private Google Access) y la salida a internet, que solo
# usa Cloud NAT porque ninguna VM tiene IP pública (regla de Conftest en cada PR y, si hay
# organización, la política de organización; ADR 0029 §1).
resource "google_compute_route" "restricted_vip" {
  project          = var.project_id
  network          = google_compute_network.this.id
  name             = "${local.name_base}-spoke-restricted-vip"
  description      = "Private Google Access por restricted.googleapis.com."
  dest_range       = local.restricted_vip
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000
}

resource "google_compute_route" "internet_egress" {
  project          = var.project_id
  network          = google_compute_network.this.id
  name             = "${local.name_base}-spoke-egress-nat"
  description      = "Salida a internet solo por Cloud NAT (sin IP públicas en las VM)."
  dest_range       = "0.0.0.0/0"
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000
}

# Private Service Access: rango reservado y conexión con servicenetworking.
resource "google_compute_global_address" "psa" {
  project       = var.project_id
  name          = "${local.name_base}-psa"
  description   = "Rango de Private Service Access (Cloud SQL, Memorystore, Filestore)."
  network       = google_compute_network.this.id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = cidrhost(local.psa_cidr, 0)
  prefix_length = tonumber(split("/", local.psa_cidr)[1])
  labels        = var.labels
}

# VERIFICAR-EN-APPLY: que cada VPC spoke del mismo proyecto tenga su propia conexión de
# servicenetworking con su rango (ADR 0029 §6; la guía de PSA no lo dice para varias VPC de un
# proyecto), y que el destroy de la conexión funcione después de borrar las instancias de
# 3-workloads (servicenetworking puede tardar en liberar el peering).
resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.this.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]
}

# Peering spoke → hub: el spoke importa las rutas personalizadas del hub (las aprendidas
# por BGP desde on-premises). depends_on: GCP no admite dos operaciones de peering a la vez
# sobre la misma red.
resource "google_compute_network_peering" "spoke_to_hub" {
  name                 = "${local.name_base}-peer-spoke-to-hub"
  network              = google_compute_network.this.self_link
  peer_network         = var.hub_network_self_link
  import_custom_routes = true
  export_custom_routes = false

  depends_on = [google_service_networking_connection.psa]
}

# Peering hub → spoke, creado sobre la red del hub por quien aplica el spoke (con el ADR 0029
# las dos VPC suelen estar en el mismo proyecto; el módulo también admite un hub en otro
# proyecto). El hub exporta sus rutas personalizadas.
# VERIFICAR-EN-APPLY: que dos spokes no creen su peering sobre el hub al mismo tiempo (el
# pipeline aplica los entornos en serie) y que las rutas BGP lleguen al spoke.
resource "google_compute_network_peering" "hub_to_spoke" {
  name                 = "${local.name_base}-peer-hub-to-spoke"
  network              = local.hub_network_id
  peer_network         = google_compute_network.this.self_link
  export_custom_routes = true
  import_custom_routes = false

  depends_on = [google_compute_network_peering.spoke_to_hub]
}

# Cloud Router y Cloud NAT por región activa (ADR 0004: el NAT no da salida a redes unidas
# por peering, por eso vive en cada spoke).
resource "google_compute_router" "this" {
  for_each = local.active_regions

  project = var.project_id
  network = google_compute_network.this.id
  name    = "${local.name_base}-spoke-router-${var.region_short_names[each.value]}"
  region  = each.value
}

resource "google_compute_router_nat" "this" {
  for_each = local.active_regions

  project                             = var.project_id
  name                                = "${local.name_base}-nat-${var.region_short_names[each.value]}"
  router                              = google_compute_router.this[each.key].name
  region                              = each.value
  nat_ip_allocate_option              = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat  = "LIST_OF_SUBNETWORKS"
  enable_dynamic_port_allocation      = true
  enable_endpoint_independent_mapping = false

  # Solo las subredes normales de la región; las proxy-only no pasan por NAT.
  dynamic "subnetwork" {
    for_each = toset(local.nat_subnet_keys[each.key])
    content {
      name                    = google_compute_subnetwork.this[subnetwork.value].self_link
      source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    }
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
