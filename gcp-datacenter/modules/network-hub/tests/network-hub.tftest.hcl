mock_provider "google" {}

variables {
  project_id = "example-net-hub"
  prefix     = "bnt"
  router_asn = 64514
  subnets = {
    hub    = { region = "us-central1", cidr = "10.0.0.0/24" }
    hub_dr = { region = "us-east4", cidr = "10.0.1.0/24" }
  }
}

run "hub_por_defecto" {
  command = plan

  assert {
    condition     = google_compute_network.this.name == "bnt-common-net-hub"
    error_message = "El nombre de la VPC no sigue <prefix>-<entorno>-net-<recurso>."
  }

  assert {
    condition     = google_compute_network.this.auto_create_subnetworks == false && google_compute_network.this.routing_mode == "GLOBAL"
    error_message = "La VPC debe ser de modo personalizado con enrutamiento global."
  }

  assert {
    condition     = google_compute_network.this.delete_default_routes_on_create == true
    error_message = "El hub no debe tener ruta por defecto a internet."
  }

  assert {
    condition     = google_compute_subnetwork.this["hub"].name == "bnt-common-net-hub-usc1" && google_compute_subnetwork.this["hub_dr"].name == "bnt-common-net-hub-dr-use4"
    error_message = "Los nombres de subred no siguen la convención con código corto de región."
  }

  assert {
    condition     = alltrue([for s in google_compute_subnetwork.this : s.private_ip_google_access == true])
    error_message = "Todas las subredes deben tener Private Google Access."
  }

  assert {
    condition     = alltrue([for s in google_compute_subnetwork.this : s.log_config[0].flow_sampling == 0.5])
    error_message = "Todas las subredes deben tener flow logs con muestreo 0.5."
  }

  assert {
    condition     = length(google_compute_router.this) == 2 && alltrue([for r in google_compute_router.this : r.bgp[0].asn == 64514])
    error_message = "Debe haber un Cloud Router por región con el ASN del hub."
  }

  assert {
    condition     = google_compute_router.this["us-central1"].name == "bnt-common-net-hub-router-usc1"
    error_message = "El nombre del Cloud Router no sigue la convención."
  }

  assert {
    condition     = output.routers == { "us-central1" = "bnt-common-net-hub-router-usc1", "us-east4" = "bnt-common-net-hub-router-use4" }
    error_message = "La salida routers debe ser el mapa región → nombre."
  }

  assert {
    condition     = google_compute_route.restricted_vip.dest_range == "199.36.153.4/30" && google_compute_route.restricted_vip.next_hop_gateway == "default-internet-gateway"
    error_message = "Falta la ruta al VIP restringido."
  }
}

run "vpc_onprem_simulada" {
  command = plan

  variables {
    network_suffix = "onprem-sim"
    router_asn     = 65001
    subnets = {
      onprem = { region = "us-central1", cidr = "192.168.0.0/24" }
    }
  }

  assert {
    condition     = google_compute_network.this.name == "bnt-common-net-onprem-sim" && google_compute_router.this["us-central1"].name == "bnt-common-net-onprem-sim-router-usc1"
    error_message = "network_suffix debe cambiar el nombre de la VPC y de los routers."
  }

  assert {
    condition     = length(google_compute_router.this) == 1
    error_message = "Sin extra_router_regions solo hay router en las regiones con subred."
  }
}

run "router_extra_sin_subred" {
  command = plan

  variables {
    network_suffix       = "onprem-sim"
    router_asn           = 65001
    extra_router_regions = ["us-east4"]
    subnets = {
      onprem = { region = "us-central1", cidr = "192.168.0.0/24" }
    }
  }

  assert {
    condition     = length(google_compute_router.this) == 2 && google_compute_router.this["us-east4"].name == "bnt-common-net-onprem-sim-router-use4" && google_compute_router.this["us-east4"].bgp[0].asn == 65001
    error_message = "extra_router_regions debe crear un router en la región aunque no tenga subred."
  }

  assert {
    condition     = length(google_compute_subnetwork.this) == 1
    error_message = "extra_router_regions no crea subredes."
  }
}

run "rechaza_region_extra_desconocida" {
  command = plan

  variables {
    extra_router_regions = ["europe-west1"]
  }

  expect_failures = [var.extra_router_regions]
}

run "rechaza_muestreo_bajo" {
  command = plan

  variables {
    flow_log_sampling = 0.1
  }

  expect_failures = [var.flow_log_sampling]
}

run "rechaza_cidr_invalido" {
  command = plan

  variables {
    subnets = {
      hub = { region = "us-central1", cidr = "10.0.0.0/33" }
    }
  }

  expect_failures = [var.subnets]
}

run "rechaza_traslape" {
  command = plan

  variables {
    subnets = {
      hub    = { region = "us-central1", cidr = "10.0.0.0/23" }
      hub_dr = { region = "us-east4", cidr = "10.0.1.0/24" }
    }
  }

  expect_failures = [var.subnets]
}

run "rechaza_region_desconocida" {
  command = plan

  variables {
    subnets = {
      hub = { region = "europe-west1", cidr = "10.0.0.0/24" }
    }
  }

  expect_failures = [var.subnets]
}

run "rechaza_asn_publico" {
  command = plan

  variables {
    router_asn = 15169
  }

  expect_failures = [var.router_asn]
}
