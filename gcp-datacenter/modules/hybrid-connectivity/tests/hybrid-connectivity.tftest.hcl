mock_provider "google" {}

variables {
  project_id      = "example-net-hub"
  prefix          = "bnt"
  connection_name = "onprem"
  region          = "us-central1"
  network         = "projects/example-net-hub/global/networks/bnt-common-net-hub"
  router          = "bnt-common-net-hub-router-usc1"
  shared_secret   = "example-only-not-a-real-secret-0000000000"
  labels = {
    env         = "common"
    app         = "network"
    owner       = "example-team"
    cost_center = "example-cc"
    managed_by  = "terraform"
  }
  peer = {
    type                 = "external"
    asn                  = 65001
    external_gateway_ips = ["203.0.113.10", "203.0.113.11"]
  }
  bgp_sessions = {
    if0 = { vpn_gateway_interface = 0, ip_range = "169.254.0.0/30" }
    if1 = { vpn_gateway_interface = 1, ip_range = "169.254.0.4/30" }
  }
  advertised_ranges = ["10.0.0.0/16", "10.10.0.0/16", "35.199.192.0/19"]
}

run "vpn_a_gateway_externo" {
  command = plan

  assert {
    condition     = google_compute_ha_vpn_gateway.this.name == "bnt-common-net-vpn-onprem-usc1" && google_compute_ha_vpn_gateway.this.labels["managed_by"] == "terraform"
    error_message = "El gateway HA VPN no sigue la convención o no lleva etiquetas."
  }

  assert {
    condition     = google_compute_external_vpn_gateway.this[0].redundancy_type == "TWO_IPS_REDUNDANCY" && length(google_compute_external_vpn_gateway.this[0].interface) == 2
    error_message = "Con dos IP el gateway externo debe ser TWO_IPS_REDUNDANCY."
  }

  assert {
    condition     = length(google_compute_vpn_tunnel.this) == 2 && google_compute_vpn_tunnel.this["if0"].vpn_gateway_interface == 0 && google_compute_vpn_tunnel.this["if1"].vpn_gateway_interface == 1
    error_message = "Debe haber dos túneles, uno por interfaz."
  }

  assert {
    condition     = google_compute_vpn_tunnel.this["if1"].peer_external_gateway_interface == 1 && google_compute_vpn_tunnel.this["if0"].ike_version == 2
    error_message = "Cada túnel debe ir a la interfaz externa correspondiente con IKEv2."
  }

  assert {
    condition     = google_compute_vpn_tunnel.this["if0"].name == "bnt-common-net-vpn-onprem-usc1-if0"
    error_message = "El nombre del túnel no sigue la convención."
  }

  assert {
    condition     = google_compute_router_interface.vpn["if0"].ip_range == "169.254.0.1/30" && google_compute_router_peer.vpn["if0"].peer_ip_address == "169.254.0.2"
    error_message = "Por defecto el Cloud Router usa la primera IP del /30 y el par la segunda."
  }

  assert {
    condition     = alltrue([for p in google_compute_router_peer.vpn : p.peer_asn == 65001 && p.advertise_mode == "CUSTOM" && length(p.advertised_ip_ranges) == 3])
    error_message = "Las sesiones BGP deben usar anuncios personalizados con los rangos indicados."
  }

  assert {
    condition     = length(google_compute_interconnect_attachment.this) == 0
    error_message = "Interconnect debe estar apagado por defecto."
  }

  assert {
    condition = (
      output.bgp_peers["if0"].advertised_ip_ranges == sort(["10.0.0.0/16", "10.10.0.0/16", "35.199.192.0/19"]) &&
      output.bgp_peers["if1"].ip_address == "169.254.0.5" &&
      output.bgp_peers["if1"].peer_ip_address == "169.254.0.6" &&
      output.bgp_peers["if0"].advertised_route_priority == 100 &&
      output.bgp_peers["if0"].router == "bnt-common-net-hub-router-usc1"
    )
    error_message = "La salida bgp_peers debe reflejar las sesiones creadas (rangos anunciados, IP y prioridad)."
  }
}

run "par_con_asn_publico_de_4_bytes" {
  command = plan

  variables {
    peer = {
      type                 = "external"
      asn                  = 4200000000 - 1
      external_gateway_ips = ["203.0.113.10"]
    }
  }

  assert {
    condition     = alltrue([for p in google_compute_router_peer.vpn : p.peer_asn == 4199999999])
    error_message = "Un ASN público de 4 bytes debe aceptarse para on-premises."
  }

  assert {
    condition     = google_compute_external_vpn_gateway.this[0].redundancy_type == "SINGLE_IP_INTERNALLY_REDUNDANT" && google_compute_vpn_tunnel.this["if1"].peer_external_gateway_interface == 0
    error_message = "Con una IP el gateway externo tiene redundancia interna y los dos túneles van a la interfaz 0."
  }
}

run "secreto_por_tunel_y_prioridad" {
  command = plan

  variables {
    shared_secret_overrides = {
      if1 = "example-only-rotated-secret-111111111111"
    }
    bgp_sessions = {
      if0 = { vpn_gateway_interface = 0, ip_range = "169.254.0.8/30", advertised_route_priority = 200 }
      if1 = { vpn_gateway_interface = 1, ip_range = "169.254.0.12/30", advertised_route_priority = 200 }
    }
  }

  assert {
    condition = (
      nonsensitive(google_compute_vpn_tunnel.this["if0"].shared_secret) == "example-only-not-a-real-secret-0000000000" &&
      nonsensitive(google_compute_vpn_tunnel.this["if1"].shared_secret) == "example-only-rotated-secret-111111111111"
    )
    error_message = "shared_secret_overrides cambia solo el secreto de su túnel."
  }

  assert {
    condition     = alltrue([for p in google_compute_router_peer.vpn : p.advertised_route_priority == 200])
    error_message = "advertised_route_priority debe llegar a las sesiones BGP."
  }
}

run "rechaza_secreto_de_tunel_desconocido" {
  command = plan

  variables {
    shared_secret_overrides = {
      if9 = "example-only-rotated-secret-111111111111"
    }
  }

  expect_failures = [var.shared_secret_overrides]
}

run "rechaza_asn_reservado" {
  command = plan

  variables {
    peer = {
      type                 = "external"
      asn                  = 23456
      external_gateway_ips = ["203.0.113.10"]
    }
  }

  expect_failures = [var.peer]
}

run "rechaza_asn_publico_en_par_gcp" {
  command = plan

  variables {
    peer = {
      type                  = "gcp"
      asn                   = 131072
      gcp_gateway_self_link = "projects/example-net-hub/regions/us-central1/vpnGateways/bnt-common-net-vpn-onprem-usc1"
    }
  }

  expect_failures = [var.peer]
}

run "vpn_entre_vpc_simulada" {
  command = plan

  variables {
    connection_name = "onprem-sim"
    peer = {
      type                  = "gcp"
      asn                   = 64514
      gcp_gateway_self_link = "projects/example-net-hub/regions/us-central1/vpnGateways/bnt-common-net-vpn-onprem-usc1"
    }
    bgp_sessions = {
      if0 = { vpn_gateway_interface = 0, ip_range = "169.254.0.0/30", router_ip = "169.254.0.2", peer_ip = "169.254.0.1" }
      if1 = { vpn_gateway_interface = 1, ip_range = "169.254.0.4/30", router_ip = "169.254.0.6", peer_ip = "169.254.0.5" }
    }
    advertised_ranges = ["192.168.0.0/24"]
  }

  assert {
    condition     = length(google_compute_external_vpn_gateway.this) == 0 && google_compute_vpn_tunnel.this["if0"].peer_gcp_gateway == "projects/example-net-hub/regions/us-central1/vpnGateways/bnt-common-net-vpn-onprem-usc1"
    error_message = "Con peer.type = gcp el túnel apunta al gateway de la otra VPC, sin gateway externo."
  }

  assert {
    condition     = google_compute_router_interface.vpn["if0"].ip_range == "169.254.0.2/30" && google_compute_router_peer.vpn["if0"].peer_ip_address == "169.254.0.1"
    error_message = "La punta simulada debe poder invertir las IP del /30."
  }
}

run "interconnect_activado" {
  command = plan

  variables {
    enable_interconnect = true
    interconnect_attachments = {
      a1 = {
        interconnect = "https://www.googleapis.com/compute/v1/projects/example-net-hub/global/interconnects/example-ic"
        vlan_tag     = 100
      }
    }
  }

  assert {
    condition     = length(google_compute_interconnect_attachment.this) == 1 && google_compute_interconnect_attachment.this["a1"].type == "DEDICATED" && length(google_compute_router_peer.interconnect) == 1
    error_message = "Con enable_interconnect se crea el attachment y su sesión BGP."
  }
}

run "rechaza_un_solo_tunel" {
  command = plan

  variables {
    bgp_sessions = {
      if0 = { vpn_gateway_interface = 0, ip_range = "169.254.0.0/30" }
    }
  }

  expect_failures = [var.bgp_sessions]
}

run "rechaza_rango_bgp_fuera_de_link_local" {
  command = plan

  variables {
    bgp_sessions = {
      if0 = { vpn_gateway_interface = 0, ip_range = "10.0.0.0/30" }
      if1 = { vpn_gateway_interface = 1, ip_range = "169.254.0.4/30" }
    }
  }

  expect_failures = [var.bgp_sessions]
}

run "rechaza_secreto_corto" {
  command = plan

  variables {
    shared_secret = "corto"
  }

  expect_failures = [var.shared_secret]
}

run "rechaza_externo_sin_ip" {
  command = plan

  variables {
    peer = { type = "external", asn = 65001 }
  }

  expect_failures = [var.peer]
}
