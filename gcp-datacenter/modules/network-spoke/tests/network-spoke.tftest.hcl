mock_provider "google" {}

variables {
  project_id  = "example-dev-net-spoke"
  prefix      = "bnt"
  environment = "dev"
  regions = {
    primary = "us-central1"
    dr      = "us-east4"
  }
  hub_network_self_link = "https://www.googleapis.com/compute/v1/projects/example-net-hub/global/networks/bnt-common-net-hub"
  subnet_cidrs = {
    app           = "10.10.0.0/20"
    app_dr        = "10.10.16.0/20"
    proxy         = "10.10.32.0/23"
    proxy_dr      = "10.10.34.0/23"
    run           = "10.10.36.0/24"
    run_dr        = "10.10.37.0/24"
    gke_master    = "10.10.38.0/28"
    gke_master_dr = "10.10.38.16/28"
    pods          = "10.10.64.0/18"
    services      = "10.10.128.0/20"
    services_dr   = "10.10.160.0/20"
    psa           = "10.10.176.0/20"
    pods_dr       = "10.10.192.0/18"
  }
  labels = {
    env         = "dev"
    app         = "network"
    owner       = "example-team"
    cost_center = "example-cc"
    managed_by  = "terraform"
  }
}

run "spoke_sin_dr" {
  command = plan

  assert {
    condition     = google_compute_network.this.name == "bnt-dev-net-spoke" && google_compute_network.this.routing_mode == "GLOBAL" && google_compute_network.this.auto_create_subnetworks == false
    error_message = "La VPC debe llamarse bnt-dev-net-spoke, en modo personalizado y con enrutamiento global."
  }

  assert {
    condition     = toset(keys(google_compute_subnetwork.this)) == toset(["app", "run"]) && toset(keys(google_compute_subnetwork.proxy)) == toset(["proxy"])
    error_message = "Sin enable_dr solo se crean las subredes de la región primaria."
  }

  assert {
    condition     = google_compute_subnetwork.this["app"].name == "bnt-dev-net-app-usc1" && google_compute_subnetwork.proxy["proxy"].name == "bnt-dev-net-proxy-usc1"
    error_message = "Los nombres de subred no siguen la convención."
  }

  assert {
    condition     = alltrue([for s in google_compute_subnetwork.this : s.private_ip_google_access == true && s.log_config[0].flow_sampling == 1 && s.log_config[0].aggregation_interval == "INTERVAL_5_SEC" && s.log_config[0].metadata == "INCLUDE_ALL_METADATA"])
    error_message = "Toda subred normal debe tener Private Google Access y, por defecto, flow logs al 100 %, cada 5 s y con todos los metadatos (CIS 3.10, ADR 0027)."
  }

  assert {
    condition     = google_compute_subnetwork.proxy["proxy"].purpose == "REGIONAL_MANAGED_PROXY" && google_compute_subnetwork.proxy["proxy"].role == "ACTIVE"
    error_message = "La subred proxy debe ser proxy-only regional y activa."
  }

  assert {
    condition = (
      length(google_compute_subnetwork.this["app"].secondary_ip_range) == 2 &&
      google_compute_subnetwork.this["app"].secondary_ip_range[0].range_name == "pods" &&
      google_compute_subnetwork.this["app"].secondary_ip_range[0].ip_cidr_range == "10.10.64.0/18" &&
      google_compute_subnetwork.this["app"].secondary_ip_range[1].range_name == "services"
    )
    error_message = "La subred app debe tener los rangos secundarios pods y services."
  }

  assert {
    condition     = output.subnets["app"].secondary_ranges == tomap({ pods = "10.10.64.0/18", services = "10.10.128.0/20" }) && output.subnets["app"].cidr == "10.10.0.0/20" && output.subnets["app"].region == "us-central1"
    error_message = "La salida subnets no tiene la forma del contrato."
  }

  assert {
    condition     = output.reserved_cidrs == { gke_master = "10.10.38.0/28" }
    error_message = "Sin enable_dr solo se reserva gke_master."
  }

  assert {
    condition     = google_compute_global_address.psa.purpose == "VPC_PEERING" && google_compute_global_address.psa.address == "10.10.176.0" && google_compute_global_address.psa.prefix_length == 20 && google_compute_global_address.psa.name == "bnt-dev-net-psa"
    error_message = "El rango de PSA no coincide con subnet_cidrs.psa."
  }

  assert {
    condition     = google_service_networking_connection.psa.service == "servicenetworking.googleapis.com"
    error_message = "Falta la conexión de Private Service Access."
  }

  assert {
    condition     = google_compute_network_peering.spoke_to_hub.import_custom_routes == true && google_compute_network_peering.spoke_to_hub.peer_network == var.hub_network_self_link
    error_message = "El spoke debe importar las rutas personalizadas del hub."
  }

  assert {
    condition     = google_compute_network_peering.hub_to_spoke.export_custom_routes == true && google_compute_network_peering.hub_to_spoke.network == "projects/example-net-hub/global/networks/bnt-common-net-hub"
    error_message = "El hub debe exportar sus rutas personalizadas hacia el spoke."
  }

  assert {
    condition     = google_compute_network_peering.spoke_to_hub.export_custom_routes == false && google_compute_network_peering.hub_to_spoke.import_custom_routes == false
    error_message = "El spoke no exporta rutas personalizadas (su 0.0.0.0/0 queda local) y el hub no importa las del spoke."
  }

  assert {
    condition = (
      output.peerings["spoke_to_hub"].import_custom_routes == true && output.peerings["spoke_to_hub"].export_custom_routes == false &&
      output.peerings["hub_to_spoke"].export_custom_routes == true && output.peerings["hub_to_spoke"].import_custom_routes == false &&
      output.peerings["hub_to_spoke"].network == "projects/example-net-hub/global/networks/bnt-common-net-hub"
    )
    error_message = "La salida peerings debe reflejar los recursos de peering."
  }

  assert {
    condition     = toset(keys(google_compute_router_nat.this)) == toset(["primary"]) && google_compute_router_nat.this["primary"].name == "bnt-dev-net-nat-usc1"
    error_message = "Debe haber un Cloud NAT en la región primaria."
  }

  assert {
    condition     = google_compute_router_nat.this["primary"].nat_ip_allocate_option == "AUTO_ONLY" && google_compute_router_nat.this["primary"].log_config[0].enable == true
    error_message = "El NAT debe usar IP automáticas y registrar errores."
  }

  assert {
    condition     = local.nat_subnet_keys["primary"] == tolist(["app", "run"]) && google_compute_router_nat.this["primary"].source_subnetwork_ip_ranges_to_nat == "LIST_OF_SUBNETWORKS"
    error_message = "El NAT debe cubrir app y run, sin la subred proxy-only."
  }

  assert {
    condition     = google_compute_route.restricted_vip.dest_range == "199.36.153.4/30" && google_compute_route.internet_egress.dest_range == "0.0.0.0/0" && google_compute_network.this.delete_default_routes_on_create == true
    error_message = "Las rutas de salida deben ser explícitas: VIP restringido e internet por NAT."
  }

  assert {
    condition     = google_compute_global_address.psa.labels["managed_by"] == "terraform"
    error_message = "El rango de PSA debe llevar las etiquetas."
  }
}

run "spoke_con_dr" {
  command = plan

  variables {
    environment = "prod"
    enable_dr   = true
    labels = {
      env         = "prod"
      app         = "network"
      owner       = "example-team"
      cost_center = "example-cc"
      managed_by  = "terraform"
    }
  }

  assert {
    condition     = toset(keys(google_compute_subnetwork.this)) == toset(["app", "run", "app_dr", "run_dr"]) && toset(keys(google_compute_subnetwork.proxy)) == toset(["proxy", "proxy_dr"])
    error_message = "Con enable_dr se crean las subredes de las dos regiones."
  }

  assert {
    condition     = google_compute_subnetwork.this["app_dr"].name == "bnt-prod-net-app-use4" && google_compute_subnetwork.this["app_dr"].region == "us-east4"
    error_message = "La subred app_dr debe vivir en la región de DR con código use4."
  }

  assert {
    condition     = output.subnets["app_dr"].secondary_ranges == tomap({ pods = "10.10.192.0/18", services = "10.10.160.0/20" })
    error_message = "app_dr debe exponer sus rangos con las llaves pods y services."
  }

  assert {
    condition     = length(google_compute_router_nat.this) == 2 && google_compute_router_nat.this["dr"].name == "bnt-prod-net-nat-use4"
    error_message = "Debe haber un Cloud NAT por región."
  }

  assert {
    condition     = output.reserved_cidrs == { gke_master = "10.10.38.0/28", gke_master_dr = "10.10.38.16/28" }
    error_message = "Con enable_dr se reservan los dos rangos de plano de control."
  }
}

run "rechaza_dr_sin_llaves" {
  command = plan

  variables {
    enable_dr = true
    subnet_cidrs = {
      app        = "10.10.0.0/20"
      proxy      = "10.10.32.0/23"
      run        = "10.10.36.0/24"
      gke_master = "10.10.38.0/28"
      pods       = "10.10.64.0/18"
      services   = "10.10.128.0/20"
      psa        = "10.10.176.0/20"
    }
  }

  expect_failures = [var.subnet_cidrs]
}

run "rechaza_llave_desconocida" {
  command = plan

  variables {
    subnet_cidrs = {
      app        = "10.10.0.0/20"
      proxy      = "10.10.32.0/23"
      run        = "10.10.36.0/24"
      gke_master = "10.10.38.0/28"
      pods       = "10.10.64.0/18"
      services   = "10.10.128.0/20"
      psa        = "10.10.176.0/20"
      extra      = "10.10.40.0/24"
    }
  }

  expect_failures = [var.subnet_cidrs]
}

run "rechaza_traslape" {
  command = plan

  variables {
    subnet_cidrs = {
      app        = "10.10.0.0/20"
      proxy      = "10.10.32.0/23"
      run        = "10.10.4.0/24"
      gke_master = "10.10.38.0/28"
      pods       = "10.10.64.0/18"
      services   = "10.10.128.0/20"
      psa        = "10.10.176.0/20"
    }
  }

  expect_failures = [var.subnet_cidrs]
}

run "rechaza_cidr_invalido" {
  command = plan

  variables {
    subnet_cidrs = {
      app        = "10.10.0.300/20"
      proxy      = "10.10.32.0/23"
      run        = "10.10.36.0/24"
      gke_master = "10.10.38.0/28"
      pods       = "10.10.64.0/18"
      services   = "10.10.128.0/20"
      psa        = "10.10.176.0/20"
    }
  }

  expect_failures = [var.subnet_cidrs]
}

run "rechaza_muestreo_bajo" {
  command = plan

  variables {
    flow_log_sampling = 0.2
  }

  expect_failures = [var.flow_log_sampling]
}

run "rechaza_etiquetas_incompletas" {
  command = plan

  variables {
    labels = { env = "dev", managed_by = "terraform" }
  }

  expect_failures = [var.labels]
}

run "rechaza_hub_mal_formado" {
  command = plan

  variables {
    hub_network_self_link = "bnt-common-net-hub"
  }

  expect_failures = [var.hub_network_self_link]
}
