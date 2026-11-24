mock_provider "google" {}

variables {
  prefix      = "bnt"
  environment = "dev"
  parent      = "projects/example-landing-zone/global/networks/bnt-dev-net-spoke"
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
    condition     = google_compute_network_firewall_policy.this.name == "bnt-dev-net-fw" && google_compute_network_firewall_policy.this.project == "example-landing-zone"
    error_message = "La política debe llamarse bnt-dev-net-fw y vivir en el proyecto de la VPC."
  }

  assert {
    condition = (
      google_compute_network_firewall_policy_association.this.attachment_target == "projects/example-landing-zone/global/networks/bnt-dev-net-spoke" &&
      google_compute_network_firewall_policy_association.this.name == "bnt-dev-net-fw-assoc" &&
      output.network_id == "projects/example-landing-zone/global/networks/bnt-dev-net-spoke"
    )
    error_message = "La política debe asociarse a la VPC de parent."
  }

  assert {
    condition = (
      google_compute_network_firewall_policy_rule.default_deny_ingress.action == "deny" &&
      google_compute_network_firewall_policy_rule.default_deny_ingress.direction == "INGRESS" &&
      google_compute_network_firewall_policy_rule.default_deny_ingress.priority == 65000 &&
      google_compute_network_firewall_policy_rule.default_deny_ingress.enable_logging == true &&
      google_compute_network_firewall_policy_rule.default_deny_ingress.match[0].src_ip_ranges == tolist(["0.0.0.0/0"])
    )
    error_message = "Falta la denegación por defecto de la entrada con registro."
  }

  assert {
    condition = (
      jsonencode(keys(output.default_deny_rules)) == jsonencode(["ingress"]) &&
      output.default_deny_rules["ingress"].action == "deny" &&
      output.default_deny_rules["ingress"].priority == 65000 &&
      output.default_deny_rules["ingress"].enable_logging == true &&
      jsonencode(output.default_deny_rules["ingress"].src_ip_ranges) == jsonencode(["0.0.0.0/0"])
    )
    error_message = "La salida default_deny_rules debe leer la denegación de entrada del recurso."
  }

  assert {
    condition     = length(google_compute_network_firewall_policy_rule.default_deny_egress) == 0
    error_message = "La denegación de salida solo se crea con enable_egress_default_deny."
  }

  assert {
    condition = alltrue([
      for k in ["lb_backend", "iap_ssh"] :
      google_tags_tag_key.this[k].purpose == "GCE_FIREWALL" && google_tags_tag_key.this[k].purpose_data == tomap({ network = "example-landing-zone/bnt-dev-net-spoke" })
    ])
    error_message = "Cada llave de etiqueta debe tener propósito GCE_FIREWALL ligado a la VPC."
  }

  assert {
    condition = (
      length(google_tags_tag_key.this) == 2 &&
      google_tags_tag_key.this["lb_backend"].parent == "projects/example-landing-zone" &&
      google_tags_tag_key.this["iap_ssh"].parent == "projects/example-landing-zone" &&
      google_tags_tag_key.this["lb_backend"].short_name == "bnt-dev-net-fw-lb-backend" &&
      google_tags_tag_key.this["iap_ssh"].short_name == "bnt-dev-net-fw-iap-ssh"
    )
    error_message = "Debe haber una llave de etiqueta por entrada, con padre el proyecto de la VPC y nombre <prefijo>-<entorno>-net-fw-<entrada>."
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

# Política de la VPC hub: mismo proyecto, otro sufijo, sin etiquetas ni reglas propias. Solo
# la denegación por defecto (la que antes daba la política jerárquica de la organización).
run "politica_sin_reglas_propias" {
  command = plan

  variables {
    environment = "common"
    name_suffix = "hub"
    parent      = "https://www.googleapis.com/compute/v1/projects/example-landing-zone/global/networks/bnt-common-net-hub"
    secure_tags = {}
    rules       = {}
  }

  assert {
    condition = (
      google_compute_network_firewall_policy.this.name == "bnt-common-net-fw-hub" &&
      google_compute_network_firewall_policy.this.project == "example-landing-zone" &&
      output.network_id == "projects/example-landing-zone/global/networks/bnt-common-net-hub"
    )
    error_message = "Con name_suffix la política debe llamarse <prefijo>-<entorno>-net-fw-<sufijo> y asociarse a la VPC del self_link."
  }

  assert {
    condition     = length(output.rules) == 0 && length(google_tags_tag_key.this) == 0 && length(output.secure_tag_key_ids) == 0 && output.default_deny_rules["ingress"].action == "deny"
    error_message = "Sin reglas ni etiquetas solo queda la denegación por defecto."
  }
}

run "nombre_con_sufijo" {
  command = plan

  variables {
    environment = "common"
    name_suffix = "onprem-sim"
    parent      = "projects/example-landing-zone/global/networks/bnt-common-net-onprem-sim"
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
    condition     = google_compute_network_firewall_policy.this.name == "bnt-common-net-fw-onprem-sim" && google_compute_network_firewall_policy_association.this.name == "bnt-common-net-fw-onprem-sim-assoc"
    error_message = "Con name_suffix la política debe llamarse <prefijo>-<entorno>-net-fw-<sufijo>."
  }

  assert {
    condition     = jsonencode(output.rules["allow-dns"].layer4_configs) == jsonencode([{ ip_protocol = "tcp", ports = ["53"] }, { ip_protocol = "udp", ports = ["53"] }])
    error_message = "La regla debe permitir DNS por TCP y UDP."
  }
}

run "denegacion_de_salida" {
  command = plan

  variables {
    enable_egress_default_deny = true
    rules = {
      allow-egress-google-apis = {
        priority       = 1000
        direction      = "EGRESS"
        action         = "allow"
        dest_ip_ranges = ["199.36.153.4/30"]
        layer4_configs = [{ ip_protocol = "tcp", ports = ["443"] }]
      }
    }
  }

  assert {
    condition = (
      google_compute_network_firewall_policy_rule.default_deny_egress[0].direction == "EGRESS" &&
      google_compute_network_firewall_policy_rule.default_deny_egress[0].priority == 65001 &&
      output.default_deny_rules["egress"].action == "deny" &&
      jsonencode(output.default_deny_rules["egress"].dest_ip_ranges) == jsonencode(["0.0.0.0/0"])
    )
    error_message = "enable_egress_default_deny debe crear la denegación de salida."
  }

  assert {
    condition     = output.rules["allow-egress-google-apis"].direction == "EGRESS" && jsonencode(output.rules["allow-egress-google-apis"].dest_ip_ranges) == jsonencode(["199.36.153.4/30"])
    error_message = "La salida rules debe leer las reglas de salida."
  }
}

run "rechaza_goto_next" {
  command = plan

  variables {
    rules = {
      delegate-internal = {
        priority      = 2000
        action        = "goto_next"
        src_ip_ranges = ["10.0.0.0/8"]
      }
    }
  }

  expect_failures = [var.rules]
}

run "rechaza_nombre_reservado" {
  command = plan

  variables {
    rules = {
      default-deny-ingress = {
        priority      = 1000
        action        = "deny"
        src_ip_ranges = ["10.0.0.0/8"]
      }
    }
  }

  expect_failures = [var.rules]
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

# Sin organización ni carpetas (ADR 0029): parent ya no admite una política jerárquica.
run "rechaza_parent_de_organizacion" {
  command = plan

  variables {
    parent = "organizations/000000000000"
  }

  expect_failures = [var.parent]
}
