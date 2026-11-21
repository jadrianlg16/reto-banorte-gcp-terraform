mock_provider "google" {}

variables {
  project_id  = "example-prod-app"
  prefix      = "bnt"
  environment = "prod"
}

run "defaults_cumplen_lo_exigido" {
  command = plan

  assert {
    condition     = google_compute_security_policy.this.name == "bnt-prod-app-web-armor"
    error_message = "El nombre no sigue §4.2."
  }

  assert {
    condition     = anytrue([for r in google_compute_security_policy.this.rule : try(strcontains(r.match[0].expr[0].expression, "evaluatePreconfiguredWaf('sqli-"), false)])
    error_message = "Falta la regla OWASP de inyección SQL."
  }

  assert {
    condition     = anytrue([for r in google_compute_security_policy.this.rule : try(strcontains(r.match[0].expr[0].expression, "evaluatePreconfiguredWaf('xss-"), false)])
    error_message = "Falta la regla OWASP de XSS."
  }

  assert {
    condition     = anytrue([for r in google_compute_security_policy.this.rule : try(r.match[0].expr[0].expression == "evaluatePreconfiguredWaf('cve-canary')" && r.action == "deny(403)", false)])
    error_message = "Falta la regla fija cve-canary (Log4Shell)."
  }

  assert {
    condition     = alltrue([for r in google_compute_security_policy.this.rule : r.preview == false if r.priority != 2147483647])
    error_message = "Ninguna regla debe quedar en modo preview."
  }

  assert {
    condition     = anytrue([for r in google_compute_security_policy.this.rule : r.action == "rate_based_ban" && r.rate_limit_options[0].rate_limit_threshold[0].count == 500 && r.rate_limit_options[0].ban_duration_sec == 600])
    error_message = "Falta el límite de tasa con bloqueo."
  }

  assert {
    condition     = anytrue([for r in google_compute_security_policy.this.rule : r.priority == 2147483647 && r.action == "allow"])
    error_message = "Falta la regla por defecto."
  }

  assert {
    condition     = google_compute_security_policy.this.adaptive_protection_config[0].layer_7_ddos_defense_config[0].enable == true
    error_message = "Adaptive Protection debe estar activo por defecto."
  }

  assert {
    condition     = google_compute_security_policy.this.advanced_options_config[0].log_level == "VERBOSE"
    error_message = "El registro detallado debe estar activo por defecto."
  }
}

run "throttle_sin_bloqueo" {
  command = plan

  variables {
    rate_limit = { action = "throttle", count = 100, interval_sec = 10 }
  }

  assert {
    condition     = anytrue([for r in google_compute_security_policy.this.rule : r.action == "throttle" && r.rate_limit_options[0].ban_duration_sec == null])
    error_message = "throttle no debe llevar ban_duration_sec."
  }
}

run "exclusiones_de_firmas" {
  command = plan

  variables {
    owasp_rules = {
      "sqli-v33-stable" = { priority = 10, sensitivity = 2, opt_out_rule_ids = ["owasp-crs-v030301-id942350-sqli"] }
      "xss-v33-stable"  = { priority = 20 }
    }
  }

  assert {
    condition     = anytrue([for r in google_compute_security_policy.this.rule : try(r.match[0].expr[0].expression == "evaluatePreconfiguredWaf('sqli-v33-stable', {'sensitivity': 2, 'opt_out_rule_ids': ['owasp-crs-v030301-id942350-sqli']})", false)])
    error_message = "La expresión con exclusiones no se armó bien."
  }
}

run "rechaza_quitar_sqli" {
  command = plan

  variables {
    owasp_rules = {
      "xss-v33-stable" = { priority = 20 }
    }
  }

  expect_failures = [var.owasp_rules]
}

run "rechaza_quitar_xss" {
  command = plan

  variables {
    owasp_rules = {
      "sqli-v33-stable" = { priority = 10 }
    }
  }

  expect_failures = [var.owasp_rules]
}

run "rechaza_accion_allow_en_owasp" {
  command = plan

  variables {
    owasp_rules = {
      "sqli-v33-stable" = { priority = 10, action = "allow" }
      "xss-v33-stable"  = { priority = 20 }
    }
  }

  expect_failures = [var.owasp_rules]
}

run "rechaza_sensibilidad_cero" {
  command = plan

  variables {
    owasp_rules = {
      "sqli-v33-stable" = { priority = 10, sensitivity = 0 }
      "xss-v33-stable"  = { priority = 20 }
    }
  }

  expect_failures = [var.owasp_rules]
}

run "rechaza_accion_de_tasa_desconocida" {
  command = plan

  variables {
    rate_limit = { action = "allow" }
  }

  expect_failures = [var.rate_limit]
}

run "rechaza_prioridad_repetida" {
  command = plan

  variables {
    rate_limit = { priority = 1000 }
  }

  expect_failures = [google_compute_security_policy.this]
}

run "rechaza_cve_canary_duplicada" {
  command = plan

  variables {
    owasp_rules = {
      "sqli-v33-stable" = { priority = 10 }
      "xss-v33-stable"  = { priority = 20 }
      "cve-canary"      = { priority = 30 }
    }
  }

  expect_failures = [var.owasp_rules]
}

run "rechaza_entorno_invalido" {
  command = plan

  variables {
    environment = "staging"
  }

  expect_failures = [var.environment]
}
