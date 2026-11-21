locals {
  # §4.2: <empresa>-<entorno>-<dominio>-<recurso>. Cloud Armor acompaña al balanceador (dominio app).
  name = "${var.prefix}-${var.environment}-app-${var.name}-armor"

  # Expresión de cada conjunto WAF preconfigurado, con sensibilidad y firmas excluidas.
  owasp_expressions = {
    for k, r in var.owasp_rules : k => (
      length(r.opt_out_rule_ids) == 0
      ? "evaluatePreconfiguredWaf('${k}', {'sensitivity': ${r.sensitivity}})"
      : "evaluatePreconfiguredWaf('${k}', {'sensitivity': ${r.sensitivity}, 'opt_out_rule_ids': [${join(", ", [for id in r.opt_out_rule_ids : "'${id}'"])}]})"
    )
  }

  all_priorities = concat(
    [for r in values(var.owasp_rules) : r.priority],
    [var.rate_limit.priority, var.cve_canary_priority],
  )
}

resource "google_compute_security_policy" "this" {
  project     = var.project_id
  name        = local.name
  description = "Política de Cloud Armor del balanceador externo ${var.name} (${var.environment}): WAF OWASP y límite de tasa."
  type        = "CLOUD_ARMOR"

  # Reglas WAF OWASP preconfiguradas. Siempre en modo de aplicación: preview = false fijo.
  dynamic "rule" {
    for_each = var.owasp_rules
    content {
      action      = rule.value.action
      priority    = rule.value.priority
      description = coalesce(rule.value.description, "WAF preconfigurado ${rule.key}")
      preview     = false

      match {
        expr {
          expression = local.owasp_expressions[rule.key]
        }
      }
    }
  }

  # CVE críticas, incluida Log4Shell (CVE-2021-44228). Regla fija: no se puede quitar.
  rule {
    action      = "deny(403)"
    priority    = var.cve_canary_priority
    description = "CVE críticas (cve-canary, incluye Log4Shell)"
    preview     = false

    match {
      expr {
        expression = "evaluatePreconfiguredWaf('cve-canary')"
      }
    }
  }

  # Límite de tasa por cliente (throttle o bloqueo temporal).
  rule {
    action      = var.rate_limit.action
    priority    = var.rate_limit.priority
    description = "Límite de tasa: ${var.rate_limit.count} solicitudes cada ${var.rate_limit.interval_sec} s por ${var.rate_limit.enforce_on_key}"
    preview     = false

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }

    rate_limit_options {
      conform_action   = "allow"
      exceed_action    = var.rate_limit.exceed_action
      enforce_on_key   = var.rate_limit.enforce_on_key
      ban_duration_sec = var.rate_limit.action == "rate_based_ban" ? var.rate_limit.ban_duration_sec : null

      rate_limit_threshold {
        count        = var.rate_limit.count
        interval_sec = var.rate_limit.interval_sec
      }
    }
  }

  # Regla por defecto obligatoria de Cloud Armor.
  rule {
    action      = var.default_rule_action
    priority    = 2147483647
    description = "Regla por defecto"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable          = var.enable_adaptive_protection
      rule_visibility = "STANDARD"
    }
  }

  advanced_options_config {
    json_parsing            = "STANDARD"
    log_level               = var.log_level
    user_ip_request_headers = var.user_ip_request_headers
  }

  lifecycle {
    precondition {
      condition     = length(distinct(local.all_priorities)) == length(local.all_priorities)
      error_message = "Las prioridades de owasp_rules, rate_limit y cve_canary_priority deben ser distintas."
    }
  }
}
