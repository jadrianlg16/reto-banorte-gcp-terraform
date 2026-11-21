# Pruebas de la raíz del hub sin GCP: proveedores simulados y estado remoto de 1-org con la
# forma exacta de su tabla de salidas (contrato §7.1).

mock_provider "google" {
  mock_data "google_secret_manager_secret_version" {
    defaults = {
      secret_data = "example-shared-secret-000000000000000000000000000"
    }
  }
}

mock_provider "google-beta" {}

mock_provider "random" {
  mock_resource "random_password" {
    defaults = {
      result = "example-shared-secret-000000000000000000000000000"
    }
  }
}

override_data {
  target = data.terraform_remote_state.org
  values = {
    outputs = {
      folder_ids = {
        common = "folders/000000000001"
        dev    = "folders/000000000002"
        qa     = "folders/000000000003"
        prod   = "folders/000000000004"
      }
      common_project_ids = {
        net_hub  = "bnt-common-net-hub"
        logging  = "bnt-common-logging"
        security = "bnt-common-security"
        backup   = "bnt-common-backup"
      }
      common_project_numbers = {
        net_hub  = "000000000011"
        logging  = "000000000012"
        security = "000000000013"
        backup   = "000000000014"
      }
      log_bucket = "bnt-common-logging-audit"
    }
  }
}

# Los mismos valores que terraform.tfvars.example.
variables {
  org_id       = "000000000000"
  prefix       = "bnt"
  state_bucket = "bnt-bootstrap-tfstate-example"

  primary_region = "us-central1"
  dr_region      = "us-east4"

  hub_supernet = "10.0.0.0/16"
  hub_cidrs = {
    hub    = "10.0.0.0/24"
    hub_dr = "10.0.1.0/24"
  }
  spoke_supernets = {
    dev  = "10.10.0.0/16"
    qa   = "10.20.0.0/16"
    prod = "10.30.0.0/16"
  }
  onprem_cidrs   = ["192.168.0.0/16"]
  vpn_bgp_ranges = ["169.254.0.0/30", "169.254.0.4/30"]
  hub_asn        = 64514
  onprem_asn     = 65001

  simulate_onprem = true
  onprem_sim_cidr = "192.168.0.0/24"

  onprem_dns_domain  = "corp.example.com."
  onprem_dns_servers = ["192.168.0.10"]

  enable_interconnect = false

  labels = {
    app         = "network"
    owner       = "example-team"
    cost_center = "example-cc"
  }
}

run "hub_con_onprem_simulado" {
  command = plan

  assert {
    condition     = output.hub_project_id == "bnt-common-net-hub" && output.hub_network_name == "bnt-common-net-hub"
    error_message = "La VPC hub debe llamarse bnt-common-net-hub y vivir en el proyecto net-hub de 1-org."
  }

  assert {
    condition     = length(output.hub_routers) == 2 && output.hub_routers["us-central1"] == "bnt-common-net-hub-router-usc1" && output.hub_routers["us-east4"] == "bnt-common-net-hub-router-use4"
    error_message = "Debe haber un Cloud Router por región con el código corto en el nombre."
  }

  assert {
    condition     = module.hub.subnets["hub"].name == "bnt-common-net-hub-usc1" && module.hub.subnets["hub_dr"].name == "bnt-common-net-hub-dr-use4" && module.hub.subnets["hub"].cidr == "10.0.0.0/24"
    error_message = "Las subredes del hub no siguen el plan o la convención de nombres."
  }

  assert {
    condition     = toset(output.bgp_advertised_ranges) == toset(["10.0.0.0/16", "10.10.0.0/16", "10.20.0.0/16", "10.30.0.0/16", "35.199.192.0/19"]) && length(output.bgp_advertised_ranges) == 5
    error_message = "El hub debe anunciar su /16, el /16 de cada spoke y 35.199.192.0/19."
  }

  assert {
    condition     = length(output.vpn_tunnel_names) == 2 && output.vpn_tunnel_names["if0"] == "bnt-common-net-vpn-onprem-usc1-if0" && output.vpn_tunnel_names["if1"] == "bnt-common-net-vpn-onprem-usc1-if1"
    error_message = "La HA VPN debe tener dos túneles, uno por interfaz."
  }

  assert {
    condition     = output.onprem_sim_network_name == "bnt-common-net-onprem-sim" && module.onprem_sim[0].subnets["onprem_sim"].cidr == "192.168.0.0/24"
    error_message = "Con simulate_onprem = true debe existir la VPC onprem-sim con 192.168.0.0/24."
  }

  assert {
    condition     = module.onprem_sim[0].routers["us-central1"] == "bnt-common-net-onprem-sim-router-usc1" && length(module.vpn_onprem_sim) == 1
    error_message = "La VPC onprem-sim necesita su Cloud Router y su punta de HA VPN."
  }

  assert {
    condition     = length(random_password.vpn_shared_secret) == 1 && length(data.google_secret_manager_secret_version.vpn_shared_secret) == 0
    error_message = "En modo simulado el secreto se genera y no se lee de Secret Manager."
  }

  assert {
    condition     = module.vpn_hub.external_gateway_self_link == null && length(module.vpn_hub.interconnect_attachment_names) == 0
    error_message = "En modo simulado no hay gateway externo, y sin enable_interconnect no hay attachments."
  }

  assert {
    condition     = module.dns.zone_names["onprem"] == "bnt-common-net-dns-onprem" && module.dns.zone_domains["onprem"] == "corp.example.com." && module.dns.policy_name == "bnt-common-net-dns-policy"
    error_message = "Falta la zona de reenvío on-premises o la política de servidor DNS."
  }

  assert {
    condition = (
      output.firewall_policy_rules["delegate-health-checks"].action == "goto_next" &&
      toset(output.firewall_policy_rules["delegate-health-checks"].src_ip_ranges) == toset(["35.191.0.0/16", "130.211.0.0/22"]) &&
      output.firewall_policy_rules["delegate-iap"].action == "goto_next" &&
      toset(output.firewall_policy_rules["delegate-iap"].src_ip_ranges) == toset(["35.235.240.0/20"])
    )
    error_message = "La política jerárquica debe delegar (goto_next) las verificaciones de salud y el IAP a la política del spoke."
  }

  assert {
    condition     = length([for r in values(output.firewall_policy_rules) : r if r.action == "allow"]) == 0
    error_message = "La política jerárquica no debe tener reglas allow: serían finales y anularían las etiquetas seguras del spoke (contrato §7.3)."
  }

  assert {
    condition = (
      output.firewall_policy_rules["delegate-internal"].action == "goto_next" &&
      toset(output.firewall_policy_rules["delegate-internal"].src_ip_ranges) == toset(["10.0.0.0/16", "10.10.0.0/16", "10.20.0.0/16", "10.30.0.0/16"]) &&
      output.firewall_policy_rules["delegate-onprem"].action == "goto_next" &&
      toset(output.firewall_policy_rules["delegate-onprem"].src_ip_ranges) == toset(["192.168.0.0/16"])
    )
    error_message = "El tráfico interno y de on-premises debe delegarse (goto_next) a la política de red del spoke."
  }

  assert {
    condition     = toset(keys(google_project_service.hub)) == toset(["compute.googleapis.com", "dns.googleapis.com"])
    error_message = "La raíz debe habilitar Compute y DNS en net-hub."
  }

  # Sesiones BGP leídas de los recursos google_compute_router_peer (salida bgp_peers).
  assert {
    condition = alltrue([
      for k in ["if0", "if1"] :
      toset(module.vpn_hub.bgp_peers[k].advertised_ip_ranges) == toset(["10.0.0.0/16", "10.10.0.0/16", "10.20.0.0/16", "10.30.0.0/16", "35.199.192.0/19"]) &&
      module.vpn_hub.bgp_peers[k].advertise_mode == "CUSTOM" &&
      module.vpn_hub.bgp_peers[k].peer_asn == 65001 &&
      module.vpn_hub.bgp_peers[k].advertised_route_priority == 100 &&
      module.vpn_hub.bgp_peers[k].router == "bnt-common-net-hub-router-usc1"
    ])
    error_message = "Las sesiones BGP primarias deben anunciar hub, spokes y 35.199.192.0/19 con prioridad 100 desde el router primario."
  }

  # Segunda HA VPN en la región de DR (decisión 9).
  assert {
    condition = (
      jsonencode(output.vpn_dr_tunnel_names) == jsonencode({ if0 = "bnt-common-net-vpn-onprem-dr-use4-if0", if1 = "bnt-common-net-vpn-onprem-dr-use4-if1" }) &&
      alltrue([
        for k in ["if0", "if1"] :
        module.vpn_hub_dr[0].bgp_peers[k].router == "bnt-common-net-hub-router-use4" &&
        module.vpn_hub_dr[0].bgp_peers[k].advertised_route_priority == 200 &&
        module.vpn_hub_dr[0].bgp_peers[k].peer_asn == 65001 &&
        toset(module.vpn_hub_dr[0].bgp_peers[k].advertised_ip_ranges) == toset(module.vpn_hub.bgp_peers[k].advertised_ip_ranges)
      ])
    )
    error_message = "La VPN de DR debe usar el router del hub en us-east4, anunciar lo mismo que la primaria y con prioridad 200 (menos preferida)."
  }

  assert {
    condition = (
      module.vpn_hub_dr[0].bgp_peers["if0"].ip_address == "169.254.0.9" && module.vpn_hub_dr[0].bgp_peers["if0"].peer_ip_address == "169.254.0.10" &&
      module.vpn_hub_dr[0].bgp_peers["if1"].ip_address == "169.254.0.13" && module.vpn_hub_dr[0].bgp_peers["if1"].peer_ip_address == "169.254.0.14"
    )
    error_message = "La VPN de DR debe usar los /30 169.254.0.8/30 y 169.254.0.12/30."
  }

  assert {
    condition = (
      module.onprem_sim[0].routers["us-east4"] == "bnt-common-net-onprem-sim-router-use4" &&
      length(module.onprem_sim[0].subnets) == 1 &&
      module.vpn_onprem_sim_dr[0].bgp_peers["if0"].router == "bnt-common-net-onprem-sim-router-use4" &&
      module.vpn_onprem_sim_dr[0].bgp_peers["if0"].ip_address == "169.254.0.10" &&
      module.vpn_onprem_sim_dr[0].bgp_peers["if0"].peer_ip_address == "169.254.0.9" &&
      module.vpn_onprem_sim_dr[0].bgp_peers["if1"].advertised_route_priority == 200 &&
      module.vpn_onprem_sim_dr[0].bgp_peers["if1"].peer_asn == 64514 &&
      jsonencode(module.vpn_onprem_sim_dr[0].bgp_peers["if1"].advertised_ip_ranges) == jsonencode(["192.168.0.0/24"])
    )
    error_message = "La punta simulada de DR necesita su router en us-east4 (sin subred), las IP invertidas y la prioridad de DR."
  }

  # Reenvío DNS en modo simulado: delegación solo hacia onprem-sim y política de red propia.
  assert {
    condition = (
      output.firewall_policy_rules["delegate-dns-onprem-sim"].action == "goto_next" &&
      jsonencode(output.firewall_policy_rules["delegate-dns-onprem-sim"].src_ip_ranges) == jsonencode(["35.199.192.0/19"]) &&
      jsonencode(output.firewall_policy_rules["delegate-dns-onprem-sim"].target_resources) == jsonencode(["https://www.googleapis.com/compute/v1/projects/bnt-common-net-hub/global/networks/bnt-common-net-onprem-sim"]) &&
      jsonencode(output.firewall_policy_rules["delegate-dns-onprem-sim"].layer4_configs) == jsonencode([{ ip_protocol = "tcp", ports = ["53"] }, { ip_protocol = "udp", ports = ["53"] }])
    )
    error_message = "Con simulate_onprem = true, la organización debe delegar 35.199.192.0/19 (TCP/UDP 53) solo hacia la VPC onprem-sim."
  }

  assert {
    condition = alltrue([
      for k, r in output.firewall_policy_rules : length(r.target_resources) == 0 if k != "delegate-dns-onprem-sim"
    ])
    error_message = "Las demás delegaciones aplican a todas las VPC (sin target_resources)."
  }

  assert {
    condition = (
      length(module.firewall_onprem_sim) == 1 &&
      toset(keys(module.firewall_onprem_sim[0].rules)) == toset(["allow-dns-forwarding", "allow-iap-ssh"]) &&
      module.firewall_onprem_sim[0].rules["allow-dns-forwarding"].action == "allow" &&
      jsonencode(module.firewall_onprem_sim[0].rules["allow-dns-forwarding"].src_ip_ranges) == jsonencode(["35.199.192.0/19"]) &&
      jsonencode(module.firewall_onprem_sim[0].rules["allow-dns-forwarding"].layer4_configs) == jsonencode([{ ip_protocol = "tcp", ports = ["53"] }, { ip_protocol = "udp", ports = ["53"] }]) &&
      jsonencode(module.firewall_onprem_sim[0].rules["allow-iap-ssh"].src_ip_ranges) == jsonencode(["35.235.240.0/20"]) &&
      jsonencode(module.firewall_onprem_sim[0].rules["allow-iap-ssh"].layer4_configs) == jsonencode([{ ip_protocol = "tcp", ports = ["22"] }])
    )
    error_message = "onprem-sim debe tener una política de red que permita solo DNS desde 35.199.192.0/19 e SSH por IAP."
  }

  # Zona de reenvío leída del recurso: servidores on-premises y visible desde la VPC hub.
  assert {
    condition = (
      jsonencode(module.dns.zones["onprem"].forwarding_targets) == jsonencode(["192.168.0.10"]) &&
      length(module.dns.zones["onprem"].networks) == 1 &&
      module.dns.zones["onprem"].peer_network == null
    )
    error_message = "La zona de reenvío debe apuntar a onprem_dns_servers y estar adjunta a la VPC hub."
  }
}

run "hub_sin_vpn_dr" {
  command = plan

  variables {
    enable_vpn_dr = false
  }

  assert {
    condition     = length(module.vpn_hub_dr) == 0 && length(module.vpn_onprem_sim_dr) == 0 && length(output.vpn_dr_tunnel_names) == 0 && length(module.onprem_sim[0].routers) == 1
    error_message = "Con enable_vpn_dr = false no se crea la VPN de DR ni el router de DR de onprem-sim."
  }
}

run "hub_real_rotacion_por_tunel" {
  command = plan

  variables {
    simulate_onprem           = false
    onprem_asn                = 4199999999
    onprem_vpn_gateway_ips    = ["203.0.113.10", "203.0.113.11"]
    onprem_vpn_secret_id      = "projects/bnt-common-security/secrets/bnt-common-vpn-psk"
    onprem_vpn_secret_version = "3"
    onprem_vpn_secret_version_overrides = {
      primary-if1 = "4"
    }
    onprem_dns_servers = ["192.168.10.10"]
  }

  override_data {
    target = data.google_secret_manager_secret_version.vpn_shared_secret["4"]
    values = {
      secret_data = "example-rotated-secret-44444444444444444444444"
    }
  }

  assert {
    condition     = toset(keys(data.google_secret_manager_secret_version.vpn_shared_secret)) == toset(["3", "4"])
    error_message = "Se lee una vez cada versión en uso (la común y la del túnel que rota)."
  }

  assert {
    condition = (
      jsonencode(keys(local.vpn_secret_overrides["primary"])) == jsonencode(["if1"]) &&
      nonsensitive(local.vpn_secret_overrides["primary"]["if1"]) == "example-rotated-secret-44444444444444444444444" &&
      length(local.vpn_secret_overrides["dr"]) == 0
    )
    error_message = "Solo el túnel primary-if1 debe recibir el secreto de la versión 4."
  }

  assert {
    condition     = module.vpn_hub.bgp_peers["if0"].peer_asn == 4199999999 && module.vpn_hub_dr[0].bgp_peers["if0"].peer_asn == 4199999999
    error_message = "Con on-premises real se admite un ASN público de 4 bytes."
  }

  assert {
    condition     = length(module.vpn_hub_dr[0].tunnel_names) == 2 && length(module.onprem_sim) == 0 && length(module.vpn_onprem_sim_dr) == 0
    error_message = "Con on-premises real la VPN de DR tiene dos túneles hacia el gateway externo y no hay punta simulada."
  }
}

run "rechaza_version_latest" {
  command = plan

  variables {
    simulate_onprem           = false
    onprem_vpn_gateway_ips    = ["203.0.113.10"]
    onprem_vpn_secret_id      = "projects/bnt-common-security/secrets/bnt-common-vpn-psk"
    onprem_vpn_secret_version = "latest"
  }

  expect_failures = [var.onprem_vpn_secret_version]
}

run "rechaza_onprem_real_sin_version" {
  command = plan

  variables {
    simulate_onprem        = false
    onprem_vpn_gateway_ips = ["203.0.113.10"]
    onprem_vpn_secret_id   = "projects/bnt-common-security/secrets/bnt-common-vpn-psk"
  }

  expect_failures = [var.onprem_vpn_secret_version]
}

run "rechaza_rangos_bgp_dr_repetidos" {
  command = plan

  variables {
    vpn_dr_bgp_ranges = ["169.254.0.4/30", "169.254.0.12/30"]
  }

  expect_failures = [var.vpn_dr_bgp_ranges]
}

run "rechaza_prioridad_dr_no_mayor" {
  command = plan

  variables {
    vpn_dr_route_priority = 100
  }

  expect_failures = [var.vpn_dr_route_priority]
}

run "rechaza_asn_publico_en_modo_simulado" {
  command = plan

  variables {
    onprem_asn = 131072
  }

  expect_failures = [var.onprem_asn]
}

run "hub_con_onprem_real" {
  command = plan

  variables {
    simulate_onprem           = false
    onprem_vpn_gateway_ips    = ["203.0.113.10", "203.0.113.11"]
    onprem_vpn_secret_id      = "projects/bnt-common-security/secrets/bnt-common-vpn-psk"
    onprem_vpn_secret_version = "3"
    onprem_dns_servers        = ["192.168.10.10", "192.168.10.11"]
  }

  assert {
    condition     = length(module.onprem_sim) == 0 && length(module.vpn_onprem_sim) == 0 && output.onprem_sim_network_name == null
    error_message = "Con simulate_onprem = false no se crea la VPC onprem-sim."
  }

  assert {
    condition     = length(random_password.vpn_shared_secret) == 0 && length(data.google_secret_manager_secret_version.vpn_shared_secret) == 1
    error_message = "Con on-premises real el secreto se lee de Secret Manager."
  }

  assert {
    condition = (
      data.google_secret_manager_secret_version.vpn_shared_secret["3"].project == "bnt-common-security" &&
      data.google_secret_manager_secret_version.vpn_shared_secret["3"].secret == "bnt-common-vpn-psk" &&
      data.google_secret_manager_secret_version.vpn_shared_secret["3"].version == "3"
    )
    error_message = "El secreto debe leerse del proyecto y nombre de onprem_vpn_secret_id."
  }

  assert {
    condition     = length(output.vpn_tunnel_names) == 2
    error_message = "La HA VPN hacia on-premises real debe tener dos túneles."
  }
}

run "hub_con_interconnect" {
  command = plan

  variables {
    enable_interconnect = true
    interconnect_attachments = {
      dc1-a = {
        type                     = "PARTNER"
        edge_availability_domain = "AVAILABILITY_DOMAIN_1"
      }
    }
  }

  assert {
    condition     = length(module.vpn_hub.interconnect_attachment_names) == 1 && module.vpn_hub.interconnect_attachment_names["dc1-a"] == "bnt-common-net-ic-onprem-usc1-dc1-a"
    error_message = "Con enable_interconnect = true se crean los VLAN attachments."
  }
}

run "rechaza_spoke_traslapado_con_onprem" {
  command = plan

  variables {
    spoke_supernets = {
      dev  = "10.10.0.0/16"
      qa   = "192.168.0.0/16"
      prod = "10.30.0.0/16"
    }
  }

  expect_failures = [var.spoke_supernets]
}

run "rechaza_spokes_repetidos" {
  command = plan

  variables {
    spoke_supernets = {
      dev  = "10.10.0.0/16"
      qa   = "10.10.0.0/16"
      prod = "10.30.0.0/16"
    }
  }

  expect_failures = [var.spoke_supernets]
}

run "rechaza_spoke_traslapado_con_hub" {
  command = plan

  variables {
    spoke_supernets = {
      dev  = "10.0.0.0/16"
      qa   = "10.20.0.0/16"
      prod = "10.30.0.0/16"
    }
  }

  expect_failures = [var.spoke_supernets]
}

run "rechaza_hub_traslapado_con_onprem" {
  command = plan

  variables {
    onprem_cidrs       = ["10.0.0.0/8"]
    onprem_sim_cidr    = "10.0.200.0/24"
    onprem_dns_servers = ["10.0.200.10"]
    spoke_supernets    = { dev = "172.16.0.0/16" }
  }

  expect_failures = [var.hub_supernet]
}

run "rechaza_subred_fuera_del_hub" {
  command = plan

  variables {
    hub_cidrs = {
      hub    = "10.0.0.0/24"
      hub_dr = "10.1.0.0/24"
    }
  }

  expect_failures = [var.hub_cidrs]
}

run "rechaza_onprem_real_sin_secreto" {
  command = plan

  variables {
    simulate_onprem           = false
    onprem_vpn_gateway_ips    = ["203.0.113.10"]
    onprem_vpn_secret_version = "1"
  }

  expect_failures = [var.onprem_vpn_secret_id]
}

run "rechaza_simulado_con_gateway_externo" {
  command = plan

  variables {
    onprem_vpn_gateway_ips = ["203.0.113.10"]
  }

  expect_failures = [var.onprem_vpn_gateway_ips]
}

run "rechaza_dns_onprem_fuera_de_onprem" {
  command = plan

  variables {
    onprem_dns_servers = ["10.10.0.53"]
  }

  expect_failures = [var.onprem_dns_servers]
}
