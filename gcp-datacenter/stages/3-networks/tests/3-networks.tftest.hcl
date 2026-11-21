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
}

run "hub_con_onprem_real" {
  command = plan

  variables {
    simulate_onprem        = false
    onprem_vpn_gateway_ips = ["203.0.113.10", "203.0.113.11"]
    onprem_vpn_secret_id   = "projects/bnt-common-security/secrets/bnt-common-vpn-psk"
    onprem_dns_servers     = ["192.168.10.10", "192.168.10.11"]
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
      data.google_secret_manager_secret_version.vpn_shared_secret[0].project == "bnt-common-security" &&
      data.google_secret_manager_secret_version.vpn_shared_secret[0].secret == "bnt-common-vpn-psk" &&
      data.google_secret_manager_secret_version.vpn_shared_secret[0].version == "latest"
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
    simulate_onprem        = false
    onprem_vpn_gateway_ips = ["203.0.113.10"]
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
