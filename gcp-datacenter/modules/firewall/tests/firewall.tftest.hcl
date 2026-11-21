mock_provider "google" {}

variables {
  prefix      = "bnt"
  environment = "dev"
  policy_type = "network"
  parent      = "projects/example-dev-net-spoke/global/networks/bnt-dev-net-spoke"
  secure_tags = {
    lb_backend = {}
    iap_ssh    = {}
  }
  rules = {
    allow-lb-to-backends = {
      priority           = 1000
      action             = "allow"
      src_ip_ranges      = ["35.191.0.0/16", "130.211.0.0/22"]
      target_secure_tags = ["lb_backend"]
      layer4_configs     = [{ ip_protocol = "tcp", ports = ["80", "443"] }]
    }
    allow-iap-ssh = {
      priority           = 1010
      action             = "allow"
      src_ip_ranges      = ["35.235.240.0/20"]
      target_secure_tags = ["iap_ssh"]
      layer4_configs     = [{ ip_protocol = "tcp", ports = ["22"] }]
    }
  }
}

run "politica_de_red" {
  command = plan

  assert {
    condition     = length(google_compute_network_firewall_policy.this) == 1 && length(google_compute_firewall_policy.this) == 0
    error_message = "policy_type = network debe crear solo la política de red."
  }

  assert {
    condition     = google_compute_network_firewall_policy.this[0].name == "bnt-dev-net-fw" && google_compute_network_firewall_policy.this[0].project == "example-dev-net-spoke"
    error_message = "La política debe llamarse bnt-dev-net-fw y vivir en el proyecto de la VPC."
  }

  assert {
    condition     = google_compute_network_firewall_policy_association.this[0].attachment_target == "projects/example-dev-net-spoke/global/networks/bnt-dev-net-spoke"
    error_message = "La política debe asociarse a la VPC."
  }

  assert {
    condition = (
      google_compute_network_firewall_policy_rule.default_deny_ingress[0].action == "deny" &&
      google_compute_network_firewall_policy_rule.default_deny_ingress[0].direction == "INGRESS" &&
      google_compute_network_firewall_policy_rule.default_deny_ingress[0].priority == 65000 &&
      google_compute_network_firewall_policy_rule.default_deny_ingress[0].enable_logging == true &&
      google_compute_network_firewall_policy_rule.default_deny_ingress[0].match[0].src_ip_ranges == tolist(["0.0.0.0/0"])
    )
    error_message = "Falta la denegación por defecto de la entrada con registro."
  }

  assert {
    condition     = length(google_compute_network_firewall_policy_rule.default_deny_egress) == 0
    error_message = "La denegación de salida solo se crea con enable_egress_default_deny."
  }

  assert {
    condition = alltrue([
      for k in ["lb_backend", "iap_ssh"] :
      google_tags_tag_key.this[k].purpose == "GCE_FIREWALL" && google_tags_tag_key.this[k].purpose_data == tomap({ network = "example-dev-net-spoke/bnt-dev-net-spoke" })
    ])
    error_message = "Cada llave de etiqueta debe tener propósito GCE_FIREWALL ligado a la VPC."
  }

  assert {
    condition = (
      length(google_tags_tag_key.this) == 2 &&
      google_tags_tag_key.this["lb_backend"].parent == "projects/example-dev-net-spoke" &&
      google_tags_tag_key.this["lb_backend"].short_name == "bnt-dev-net-fw-lb-backend" &&
      google_tags_tag_key.this["iap_ssh"].short_name == "bnt-dev-net-fw-iap-ssh"
    )
    error_message = "Debe haber una llave de etiqueta por entrada, en el proyecto de la VPC y con nombre <prefijo>-<entorno>-net-fw-<entrada>."
  }

  assert {
    condition     = google_tags_tag_value.this["lb_backend"].short_name == "enabled" && google_tags_tag_value.this["iap_ssh"].short_name == "enabled"
    error_message = "Cada llave debe tener un solo valor enabled."
  }

  assert {
    condition     = toset(keys(output.secure_tag_key_ids)) == toset(["lb_backend", "iap_ssh"])
    error_message = "secure_tag_key_ids debe tener una entrada por etiqueta."
  }

  assert {
    condition     = length(google_compute_network_firewall_policy_rule.this["allow-lb-to-backends"].target_secure_tags) == 1 && google_compute_network_firewall_policy_rule.this["allow-lb-to-backends"].enable_logging == true
    error_message = "La regla del balanceador debe apuntar a su etiqueta segura y registrar."
  }

  assert {
    condition     = toset(keys(output.secure_tag_ids)) == toset(["lb_backend", "iap_ssh"])
    error_message = "secure_tag_ids debe tener una entrada por etiqueta."
  }
}

# La salida rules se arma con los recursos de regla. Los ID de los valores de etiqueta se
# fijan en el plan para poder comprobar que cada regla apunta al valor correcto.
run "salida_rules_desde_recursos" {
  command = plan

  override_resource {
    target          = google_tags_tag_value.this["lb_backend"]
    override_during = plan
    values          = { id = "tagValues/1000000000001" }
  }

  override_resource {
    target          = google_tags_tag_value.this["iap_ssh"]
    override_during = plan
    values          = { id = "tagValues/1000000000002" }
  }

  assert {
    condition = (
      google_compute_network_firewall_policy_rule.this["allow-lb-to-backends"].target_secure_tags[0].name == "tagValues/1000000000001" &&
      google_compute_network_firewall_policy_rule.this["allow-iap-ssh"].target_secure_tags[0].name == "tagValues/1000000000002"
    )
    error_message = "Cada regla debe apuntar al valor de su propia etiqueta segura."
  }

  assert {
    condition = (
      jsonencode(output.rules["allow-lb-to-backends"].target_secure_tags) == jsonencode(["lb_backend"]) &&
      jsonencode(output.rules["allow-iap-ssh"].target_secure_tags) == jsonencode(["iap_ssh"]) &&
      jsonencode(output.rules["allow-iap-ssh"].src_ip_ranges) == jsonencode(["35.235.240.0/20"]) &&
      jsonencode(output.rules["allow-iap-ssh"].layer4_configs) == jsonencode([{ ip_protocol = "tcp", ports = ["22"] }]) &&
      output.rules["allow-lb-to-backends"].action == "allow" &&
      output.rules["allow-lb-to-backends"].priority == 1000 &&
      length(output.rules) == 2
    )
    error_message = "La salida rules debe reflejar las reglas creadas (etiquetas, orígenes y puertos)."
  }
}

run "nombre_con_sufijo" {
  command = plan

  variables {
    environment = "common"
    name_suffix = "onprem-sim"
    parent      = "projects/example-net-hub/global/networks/bnt-common-net-onprem-sim"
    secure_tags = {}
    rules = {
      allow-dns = {
        priority       = 1000
        action         = "allow"
        src_ip_ranges  = ["35.199.192.0/19"]
        layer4_configs = [{ ip_protocol = "tcp", ports = ["53"] }, { ip_protocol = "udp", ports = ["53"] }]
      }
    }
  }

  assert {
    condition     = google_compute_network_firewall_policy.this[0].name == "bnt-common-net-fw-onprem-sim" && google_compute_network_firewall_policy_association.this[0].name == "bnt-common-net-fw-onprem-sim-assoc"
    error_message = "Con name_suffix la política debe llamarse <prefijo>-<entorno>-net-fw-<sufijo>."
  }

  assert {
    condition     = jsonencode(output.rules["allow-dns"].layer4_configs) == jsonencode([{ ip_protocol = "tcp", ports = ["53"] }, { ip_protocol = "udp", ports = ["53"] }])
    error_message = "La regla debe permitir DNS por TCP y UDP."
  }
}

run "politica_jerarquica" {
  command = plan

  variables {
    environment = "common"
    policy_type = "hierarchical"
    parent      = "organizations/000000000000"
    secure_tags = {}
    rules = {
      allow-health-checks = {
        priority       = 1000
        action         = "allow"
        src_ip_ranges  = ["35.191.0.0/16", "130.211.0.0/22"]
        layer4_configs = [{ ip_protocol = "tcp" }]
      }
      delegate-internal = {
        priority      = 2000
        action        = "goto_next"
        src_ip_ranges = ["10.0.0.0/8"]
      }
    }
    enable_egress_default_deny = true
  }

  assert {
    condition     = length(google_compute_firewall_policy.this) == 1 && length(google_compute_network_firewall_policy.this) == 0
    error_message = "policy_type = hierarchical debe crear solo la política jerárquica."
  }

  assert {
    condition     = google_compute_firewall_policy.this[0].short_name == "bnt-common-net-fw" && google_compute_firewall_policy.this[0].parent == "organizations/000000000000"
    error_message = "La política jerárquica debe llamarse bnt-common-net-fw y vivir en la organización."
  }

  assert {
    condition     = google_compute_firewall_policy_association.this[0].attachment_target == "organizations/000000000000"
    error_message = "La política jerárquica debe asociarse a su padre."
  }

  assert {
    condition     = google_compute_firewall_policy_rule.default_deny_ingress[0].action == "deny" && google_compute_firewall_policy_rule.default_deny_ingress[0].priority == 65000 && google_compute_firewall_policy_rule.default_deny_ingress[0].enable_logging == true
    error_message = "Falta la denegación por defecto de la entrada en la política jerárquica."
  }

  assert {
    condition     = google_compute_firewall_policy_rule.default_deny_egress[0].direction == "EGRESS" && google_compute_firewall_policy_rule.default_deny_egress[0].priority == 65001
    error_message = "enable_egress_default_deny debe crear la denegación de salida."
  }

  assert {
    condition     = google_compute_firewall_policy_rule.this["delegate-internal"].enable_logging == false
    error_message = "Las reglas goto_next no registran."
  }

  assert {
    condition     = output.rules["delegate-internal"].action == "goto_next" && jsonencode(output.rules["delegate-internal"].src_ip_ranges) == jsonencode(["10.0.0.0/8"]) && length(output.rules["delegate-internal"].target_resources) == 0
    error_message = "La salida rules debe leer las reglas jerárquicas creadas."
  }

  assert {
    condition     = length(google_tags_tag_key.this) == 0 && length(output.secure_tag_key_ids) == 0
    error_message = "Sin secure_tags no se crea llave de etiqueta."
  }
}

run "jerarquica_con_etiquetas_de_organizacion" {
  command = plan

  variables {
    environment       = "common"
    policy_type       = "hierarchical"
    parent            = "folders/000000000000"
    secure_tag_parent = "organizations/000000000000"
    secure_tags       = { iap_ssh = {} }
    rules = {
      allow-iap = {
        priority           = 1000
        action             = "allow"
        src_ip_ranges      = ["35.235.240.0/20"]
        target_secure_tags = ["iap_ssh"]
        layer4_configs     = [{ ip_protocol = "tcp", ports = ["22"] }]
      }
    }
  }

  assert {
    condition     = google_tags_tag_key.this["iap_ssh"].parent == "organizations/000000000000" && google_tags_tag_key.this["iap_ssh"].purpose_data == tomap({ organization = "auto" }) && google_tags_tag_key.this["iap_ssh"].short_name == "bnt-common-net-fw-iap-ssh"
    error_message = "En hierarchical la llave de etiqueta debe ser de la organización."
  }
}

run "rechaza_jerarquica_con_etiquetas_sin_organizacion" {
  command = plan

  variables {
    environment = "common"
    policy_type = "hierarchical"
    parent      = "folders/000000000000"
  }

  expect_failures = [var.secure_tag_parent]
}

run "rechaza_entrada_desde_internet" {
  command = plan

  variables {
    rules = {
      allow-all = {
        priority      = 1000
        action        = "allow"
        src_ip_ranges = ["0.0.0.0/0"]
      }
    }
  }

  expect_failures = [var.rules]
}

run "rechaza_entrada_desde_medio_internet" {
  command = plan

  variables {
    rules = {
      allow-half = {
        priority      = 1000
        action        = "allow"
        src_ip_ranges = ["0.0.0.0/1", "128.0.0.0/1"]
      }
    }
  }

  expect_failures = [var.rules]
}

run "rechaza_prioridad_reservada" {
  command = plan

  variables {
    rules = {
      late-allow = {
        priority      = 65000
        action        = "allow"
        src_ip_ranges = ["10.0.0.0/8"]
      }
    }
  }

  expect_failures = [var.rules]
}

run "rechaza_etiqueta_desconocida" {
  command = plan

  variables {
    rules = {
      allow-x = {
        priority           = 1000
        action             = "allow"
        src_ip_ranges      = ["10.0.0.0/8"]
        target_secure_tags = ["no_existe"]
      }
    }
  }

  expect_failures = [var.rules]
}

run "rechaza_parent_que_no_coincide" {
  command = plan

  variables {
    parent = "organizations/000000000000"
  }

  expect_failures = [var.parent]
}
