# Pruebas del spoke sin GCP: proveedores simulados y estado remoto de 1-org y del hub con la
# forma exacta de sus tablas de salidas (contrato §7.1 y §7.3; spoke_supernets es una salida
# adicional del hub). Este archivo es idéntico en envs/dev, envs/qa y envs/prod, como el
# código: las variables comunes son las de dev y los runs spoke_qa y spoke_prod planean con
# los valores de terraform.tfvars.example de esos entornos.

mock_provider "google" {}

mock_provider "google-beta" {}

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

override_data {
  target = data.terraform_remote_state.hub
  values = {
    outputs = {
      hub_project_id        = "bnt-common-net-hub"
      hub_network_name      = "bnt-common-net-hub"
      hub_network_self_link = "https://www.googleapis.com/compute/v1/projects/bnt-common-net-hub/global/networks/bnt-common-net-hub"
      firewall_policy_id    = "locations/global/firewallPolicies/000000000000"
      spoke_supernets = {
        dev  = "10.10.0.0/16"
        qa   = "10.20.0.0/16"
        prod = "10.30.0.0/16"
      }
    }
  }
}

# Valores de terraform.tfvars.example de dev (X = 10).
variables {
  billing_account = "000000-000000-000000"
  prefix          = "bnt"
  project_suffix  = ""
  environment     = "dev"
  state_bucket    = "bnt-bootstrap-tfstate-example"

  primary_region = "us-central1"
  dr_region      = "us-east4"
  enable_dr      = false

  spoke_supernet = "10.10.0.0/16"
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
  onprem_cidrs = ["192.168.0.0/16"]

  onprem_dns_domain = "corp.example.com."
  dns_domain_base   = "empresa.internal."
  flow_log_sampling = 0.5

  labels = {
    app         = "network"
    owner       = "example-team"
    cost_center = "example-cc"
  }
}

run "spoke_dev_sin_dr" {
  command = plan

  assert {
    condition     = output.host_project_id == "bnt-dev-net-spoke" && output.network_name == "bnt-dev-net-spoke"
    error_message = "El proyecto y la VPC deben llamarse <prefix>-<env>-net-spoke."
  }

  assert {
    condition     = toset(keys(output.subnets)) == toset(["app", "run", "proxy"])
    error_message = "Sin enable_dr solo se crean las subredes de la región primaria."
  }

  assert {
    condition = (
      output.subnets["app"].name == "bnt-dev-net-app-usc1" &&
      output.subnets["app"].cidr == "10.10.0.0/20" &&
      output.subnets["app"].region == "us-central1" &&
      output.subnets["app"].secondary_ranges["pods"] == "10.10.64.0/18" &&
      output.subnets["app"].secondary_ranges["services"] == "10.10.128.0/20" &&
      output.subnets["proxy"].name == "bnt-dev-net-proxy-usc1"
    )
    error_message = "Las subredes no siguen el plan de direccionamiento o la convención de nombres."
  }

  assert {
    condition     = output.psa_range_name == "bnt-dev-net-psa" && output.reserved_cidrs["gke_master"] == "10.10.38.0/28" && length(output.reserved_cidrs) == 1
    error_message = "Falta el rango de Private Service Access o la reserva del plano de control de GKE."
  }

  assert {
    condition     = length(output.nat_names) == 1 && output.nat_names["us-central1"] == "bnt-dev-net-nat-usc1" && output.routers["us-central1"] == "bnt-dev-net-spoke-router-usc1"
    error_message = "Debe haber un Cloud Router y un Cloud NAT en la región primaria."
  }

  assert {
    condition     = toset(keys(output.secure_tags)) == toset(["lb_backend", "iap_ssh"]) && toset(keys(output.secure_tag_keys)) == toset(["lb_backend", "iap_ssh"])
    error_message = "secure_tags y secure_tag_keys deben tener las llaves lb_backend e iap_ssh."
  }

  assert {
    condition = (
      toset(output.firewall_policy_rules["allow-lb-health-checks"].src_ip_ranges) == toset(["35.191.0.0/16", "130.211.0.0/22"]) &&
      toset(output.firewall_policy_rules["allow-lb-health-checks"].target_secure_tags) == toset(["lb_backend"]) &&
      toset(output.firewall_policy_rules["allow-iap-ssh"].src_ip_ranges) == toset(["35.235.240.0/20"]) &&
      toset(output.firewall_policy_rules["allow-iap-ssh"].target_secure_tags) == toset(["iap_ssh"])
    )
    error_message = "Los rangos del balanceador e IAP solo deben llegar a sus etiquetas seguras."
  }

  assert {
    condition = (
      toset(output.firewall_policy_rules["allow-proxy-to-backends"].src_ip_ranges) == toset(["10.10.32.0/23"]) &&
      toset(output.firewall_policy_rules["allow-gke-control-plane"].src_ip_ranges) == toset(["10.10.38.0/28"]) &&
      toset(output.firewall_policy_rules["allow-workload-internal"].src_ip_ranges) == toset(["10.10.0.0/20", "10.10.64.0/18", "10.10.36.0/24"])
    )
    error_message = "Sin enable_dr las reglas internas solo usan los rangos de la región primaria."
  }

  assert {
    condition     = output.private_dns_domain == "dev.empresa.internal."
    error_message = "La zona privada del entorno debe ser dev.empresa.internal."
  }

  assert {
    condition = (
      output.dns_zone_names["env"] == "bnt-dev-net-dns-env" &&
      output.dns_zone_names["onprem"] == "bnt-dev-net-dns-onprem" &&
      output.dns_zone_names["googleapis"] == "bnt-dev-net-dns-googleapis" &&
      module.dns.zone_domains["googleapis"] == "googleapis.com." &&
      module.dns.zone_domains["onprem"] == "corp.example.com."
    )
    error_message = "Faltan la zona privada, la de peering hacia el hub o la de googleapis.com."
  }

  assert {
    condition     = module.project.shared_vpc_host_project == null && contains(module.project.enabled_apis, "servicenetworking.googleapis.com")
    error_message = "El proyecto debe ser host (no servicio) de Shared VPC y tener Service Networking."
  }
}

run "spoke_con_dr" {
  command = plan

  variables {
    enable_dr = true
  }

  assert {
    condition     = toset(keys(output.subnets)) == toset(["app", "run", "proxy", "app_dr", "run_dr", "proxy_dr"])
    error_message = "Con enable_dr se crean también las subredes de DR."
  }

  assert {
    condition     = output.subnets["app_dr"].name == "bnt-dev-net-app-use4" && output.subnets["app_dr"].secondary_ranges["pods"] == "10.10.192.0/18"
    error_message = "La subred app_dr debe estar en DR con sus rangos secundarios."
  }

  assert {
    condition     = length(output.nat_names) == 2 && output.nat_names["us-east4"] == "bnt-dev-net-nat-use4"
    error_message = "Con enable_dr debe haber NAT en las dos regiones."
  }

  assert {
    condition = (
      toset(output.firewall_policy_rules["allow-proxy-to-backends"].src_ip_ranges) == toset(["10.10.32.0/23", "10.10.34.0/23"]) &&
      toset(output.firewall_policy_rules["allow-gke-control-plane"].src_ip_ranges) == toset(["10.10.38.0/28", "10.10.38.16/28"])
    )
    error_message = "Con enable_dr las reglas internas incluyen los rangos de DR."
  }
}

run "spoke_qa" {
  command = plan

  variables {
    environment    = "qa"
    enable_dr      = false
    spoke_supernet = "10.20.0.0/16"
    subnet_cidrs = {
      app           = "10.20.0.0/20"
      app_dr        = "10.20.16.0/20"
      proxy         = "10.20.32.0/23"
      proxy_dr      = "10.20.34.0/23"
      run           = "10.20.36.0/24"
      run_dr        = "10.20.37.0/24"
      gke_master    = "10.20.38.0/28"
      gke_master_dr = "10.20.38.16/28"
      pods          = "10.20.64.0/18"
      services      = "10.20.128.0/20"
      services_dr   = "10.20.160.0/20"
      psa           = "10.20.176.0/20"
      pods_dr       = "10.20.192.0/18"
    }
  }

  assert {
    condition     = output.host_project_id == "bnt-qa-net-spoke" && output.private_dns_domain == "qa.empresa.internal." && length(output.nat_names) == 1
    error_message = "qa debe crear bnt-qa-net-spoke, la zona qa.empresa.internal. y NAT solo en la región primaria."
  }
}

run "spoke_prod" {
  command = plan

  variables {
    environment    = "prod"
    enable_dr      = true
    spoke_supernet = "10.30.0.0/16"
    subnet_cidrs = {
      app           = "10.30.0.0/20"
      app_dr        = "10.30.16.0/20"
      proxy         = "10.30.32.0/23"
      proxy_dr      = "10.30.34.0/23"
      run           = "10.30.36.0/24"
      run_dr        = "10.30.37.0/24"
      gke_master    = "10.30.38.0/28"
      gke_master_dr = "10.30.38.16/28"
      pods          = "10.30.64.0/18"
      services      = "10.30.128.0/20"
      services_dr   = "10.30.160.0/20"
      psa           = "10.30.176.0/20"
      pods_dr       = "10.30.192.0/18"
    }
  }

  assert {
    condition     = output.host_project_id == "bnt-prod-net-spoke" && output.private_dns_domain == "prod.empresa.internal." && length(output.subnets) == 6 && length(output.nat_names) == 2
    error_message = "prod debe crear bnt-prod-net-spoke, la zona prod.empresa.internal. y las subredes y NAT de las dos regiones."
  }
}

run "rechaza_subred_fuera_del_slash16" {
  command = plan

  variables {
    subnet_cidrs = {
      app        = "10.10.0.0/20"
      proxy      = "10.10.32.0/23"
      run        = "10.11.36.0/24"
      gke_master = "10.10.38.0/28"
      pods       = "10.10.64.0/18"
      services   = "10.10.128.0/20"
      psa        = "10.10.176.0/20"
    }
  }

  expect_failures = [var.subnet_cidrs]
}

run "rechaza_traslape_con_onprem" {
  command = plan

  variables {
    onprem_cidrs = ["192.168.0.0/16", "10.10.36.0/22"]
  }

  # La validación de subnet_cidrs depende de spoke_supernet: al fallar esta, Terraform no
  # llega a evaluar aquella (un rango dentro del /16 no puede traslaparse sin que el /16 lo haga).
  expect_failures = [var.spoke_supernet]
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

run "rechaza_supernet_distinto_del_hub" {
  command = plan

  # Rangos coherentes con 10.20.0.0/16, pero el hub anuncia 10.10.0.0/16 para dev.
  variables {
    spoke_supernet = "10.20.0.0/16"
    subnet_cidrs = {
      app        = "10.20.0.0/20"
      proxy      = "10.20.32.0/23"
      run        = "10.20.36.0/24"
      gke_master = "10.20.38.0/28"
      pods       = "10.20.64.0/18"
      services   = "10.20.128.0/20"
      psa        = "10.20.176.0/20"
    }
  }

  expect_failures = [var.spoke_supernet]
}
