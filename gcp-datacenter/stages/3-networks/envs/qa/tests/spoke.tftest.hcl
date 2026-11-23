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

# Valores que el proveedor simulado no conoce en el plan y que las aserciones necesitan: los
# ID de los valores de etiqueta (para comprobar a qué etiqueta apunta cada regla) y el ID de la
# VPC spoke (para comprobar a qué VPC se adjuntan las zonas DNS).
override_resource {
  target          = module.firewall.google_tags_tag_value.this["lb_backend"]
  override_during = plan
  values          = { id = "tagValues/1000000000001" }
}

override_resource {
  target          = module.firewall.google_tags_tag_value.this["iap_ssh"]
  override_during = plan
  values          = { id = "tagValues/1000000000002" }
}

override_resource {
  target          = module.spoke.google_compute_network.this
  override_during = plan
  values = {
    id        = "projects/bnt-env-net-spoke/global/networks/bnt-env-net-spoke"
    self_link = "https://www.googleapis.com/compute/v1/projects/bnt-env-net-spoke/global/networks/bnt-env-net-spoke"
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

  # Las Connectivity Tests de la prueba de humo de dev se crean en el proyecto host.
  assert {
    condition     = contains(module.project.enabled_apis, "networkmanagement.googleapis.com")
    error_message = "El proyecto host debe tener la API de Network Management (Connectivity Tests de la prueba de humo)."
  }

  # Reglas leídas de los recursos de la política de red (salida rules del módulo firewall).
  assert {
    condition = (
      jsonencode(output.firewall_policy_rules["allow-lb-health-checks"].layer4_configs) == jsonencode([{ ip_protocol = "tcp", ports = ["80", "443", "8080"] }]) &&
      jsonencode(output.firewall_policy_rules["allow-proxy-to-backends"].target_secure_tags) == jsonencode(["lb_backend"]) &&
      jsonencode(output.firewall_policy_rules["allow-iap-ssh"].layer4_configs) == jsonencode([{ ip_protocol = "tcp", ports = ["22"] }]) &&
      length(output.firewall_policy_rules["allow-workload-internal"].target_secure_tags) == 0 &&
      alltrue([for r in values(output.firewall_policy_rules) : r.action == "allow"])
    )
    error_message = "Las reglas creadas deben abrir solo lb_backend_ports hacia lb_backend y el 22 hacia iap_ssh."
  }

  # Filestore (rango psa) hacia los clientes NFS: portmapper, statd y nlockmgr.
  assert {
    condition = (
      toset(output.firewall_policy_rules["allow-filestore-nfs-callbacks"].src_ip_ranges) == toset(["10.10.176.0/20"]) &&
      jsonencode(output.firewall_policy_rules["allow-filestore-nfs-callbacks"].layer4_configs) == jsonencode([{ ip_protocol = "tcp", ports = ["111", "2046", "4045"] }, { ip_protocol = "udp", ports = ["4045"] }]) &&
      length(output.firewall_policy_rules["allow-filestore-nfs-callbacks"].target_secure_tags) == 0 &&
      output.firewall_policy_rules["allow-filestore-nfs-callbacks"].priority == 1050
    )
    error_message = "Debe existir la regla de llamadas de Filestore desde psa a los clientes NFS (TCP 111, 2046 y 4045; UDP 4045)."
  }

  assert {
    condition     = jsonencode(output.lb_backend_ports) == jsonencode(["80", "443", "8080"])
    error_message = "La salida lb_backend_ports debe publicar los puertos abiertos hacia lb_backend."
  }

  # Zonas leídas de los recursos de Cloud DNS.
  assert {
    condition = (
      toset(module.dns.zones["env"].networks) == toset(["projects/bnt-env-net-spoke/global/networks/bnt-env-net-spoke", "https://www.googleapis.com/compute/v1/projects/bnt-common-net-hub/global/networks/bnt-common-net-hub"]) &&
      module.dns.zones["onprem"].peer_network == "https://www.googleapis.com/compute/v1/projects/bnt-common-net-hub/global/networks/bnt-common-net-hub" &&
      jsonencode(module.dns.zones["onprem"].networks) == jsonencode(["projects/bnt-env-net-spoke/global/networks/bnt-env-net-spoke"]) &&
      module.dns.zones["googleapis"].peer_network == null
    )
    error_message = "La zona del entorno debe estar adjunta al spoke y al hub, y la de on-premises debe hacer peering con la VPC hub."
  }

  assert {
    condition = (
      module.dns.records["googleapis/vip"].name == "restricted.googleapis.com." &&
      jsonencode(module.dns.records["googleapis/vip"].rrdatas) == jsonencode(["199.36.153.4", "199.36.153.5", "199.36.153.6", "199.36.153.7"]) &&
      jsonencode(module.dns.records["googleapis/wildcard"].rrdatas) == jsonencode(["restricted.googleapis.com."])
    )
    error_message = "googleapis.com. debe resolver al VIP restringido por defecto."
  }

  assert {
    condition = alltrue([
      for k, d in { gcr = "gcr.io.", pkg = "pkg.dev.", run = "run.app." } :
      module.dns.zones[k].dns_name == d &&
      module.dns.records["${k}/apex"].name == d && module.dns.records["${k}/apex"].type == "A" &&
      jsonencode(module.dns.records["${k}/apex"].rrdatas) == jsonencode(["199.36.153.4", "199.36.153.5", "199.36.153.6", "199.36.153.7"]) &&
      module.dns.records["${k}/wildcard"].name == "*.${d}" && module.dns.records["${k}/wildcard"].type == "CNAME" &&
      jsonencode(module.dns.records["${k}/wildcard"].rrdatas) == jsonencode([d])
    ])
    error_message = "gcr.io., pkg.dev. y run.app. deben resolver al VIP (A en el ápice y comodín CNAME al dominio)."
  }

  # Peering leído de los recursos: el spoke importa y no exporta; el hub exporta y no importa.
  assert {
    condition = (
      module.spoke.peerings["spoke_to_hub"].import_custom_routes == true &&
      module.spoke.peerings["spoke_to_hub"].export_custom_routes == false &&
      module.spoke.peerings["hub_to_spoke"].export_custom_routes == true &&
      module.spoke.peerings["hub_to_spoke"].import_custom_routes == false &&
      module.spoke.peerings["hub_to_spoke"].network == "projects/bnt-common-net-hub/global/networks/bnt-common-net-hub"
    )
    error_message = "El peering debe importar en el spoke y exportar en el hub, nunca al revés."
  }
}

run "spoke_sin_filestore_y_vip_privado" {
  command = plan

  variables {
    enable_filestore_nfs_lock_callbacks = false
    google_apis_vip                     = "private"
  }

  assert {
    condition     = !contains(keys(output.firewall_policy_rules), "allow-filestore-nfs-callbacks")
    error_message = "Con enable_filestore_nfs_lock_callbacks = false no se crea la regla de Filestore."
  }

  assert {
    condition = (
      module.dns.records["googleapis/vip"].name == "private.googleapis.com." &&
      jsonencode(module.dns.records["googleapis/wildcard"].rrdatas) == jsonencode(["private.googleapis.com."]) &&
      jsonencode(module.dns.records["pkg/apex"].rrdatas) == jsonencode(["199.36.153.8", "199.36.153.9", "199.36.153.10", "199.36.153.11"])
    )
    error_message = "Con google_apis_vip = private las zonas deben resolver a private.googleapis.com (199.36.153.8/30)."
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

run "rechaza_vip_desconocido" {
  command = plan

  variables {
    google_apis_vip = "public"
  }

  expect_failures = [var.google_apis_vip]
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
