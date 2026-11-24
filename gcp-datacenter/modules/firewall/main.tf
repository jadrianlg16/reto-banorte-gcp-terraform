locals {
  # <empresa>-<entorno>-net-fw[-<name_suffix>] (convención de nombres del contrato).
  name = var.name_suffix == "" ? "${var.prefix}-${var.environment}-net-fw" : "${var.prefix}-${var.environment}-net-fw-${var.name_suffix}"

  # Proyecto y nombre de la VPC: la política, sus reglas y las llaves de etiqueta viven en el
  # proyecto de la VPC (ADR 0029 §6: todo en el proyecto único).
  network_parts = regex("projects/([^/]+)/global/networks/([^/]+)$", var.parent)
  project_id    = local.network_parts[0]
  network_id    = "projects/${local.network_parts[0]}/global/networks/${local.network_parts[1]}"

  # Prioridades reservadas para las reglas que el módulo crea siempre.
  default_deny_ingress_priority = 65000
  default_deny_egress_priority  = 65001
}

# ---------------------------------------------------------------------------------------
# Etiquetas seguras

# Una llave por entrada de secure_tags, con un solo valor (enabled): un recurso admite un
# solo valor por llave, y una VM puede necesitar varias etiquetas a la vez (por ejemplo
# lb_backend e iap_ssh). Nombre de la llave: <empresa>-<entorno>-net-fw-<entrada>. El padre es
# el proyecto de la VPC y la llave queda ligada a esa VPC (purpose_data.network), como pide la
# guía de etiquetas para firewalls: una llave con padre proyecto y propósito de red debe
# apuntar a una VPC del mismo proyecto.
# VERIFICAR-EN-APPLY: que las llaves de etiqueta con padre proyecto se creen y se puedan usar
# en las reglas en un proyecto sin organización (HYPOTHESIS del ADR 0029 §6: la guía dice que
# las llaves pueden tener padre proyecto, pero no lo dice para un proyecto sin organización),
# y el formato de purpose_data (network = "<proyecto>/<red>").
resource "google_tags_tag_key" "this" {
  for_each = var.secure_tags

  parent       = "projects/${local.project_id}"
  short_name   = "${local.name}-${replace(each.key, "_", "-")}"
  description  = coalesce(each.value.description, "Etiqueta segura de firewall ${each.key} administrada por Terraform.")
  purpose      = "GCE_FIREWALL"
  purpose_data = { network = "${local.network_parts[0]}/${local.network_parts[1]}" }
}

resource "google_tags_tag_value" "this" {
  for_each = var.secure_tags

  parent      = google_tags_tag_key.this[each.key].id
  short_name  = "enabled"
  description = "La etiqueta ${each.key} está activa en el recurso."
}

# ---------------------------------------------------------------------------------------
# Política de firewall de red global, asociada a una VPC

resource "google_compute_network_firewall_policy" "this" {
  project     = local.project_id
  name        = local.name
  description = "Política de red administrada por Terraform: deniega la entrada por defecto."
}

resource "google_compute_network_firewall_policy_association" "this" {
  project           = local.project_id
  name              = "${local.name}-assoc"
  firewall_policy   = google_compute_network_firewall_policy.this.id
  attachment_target = local.network_id
}

resource "google_compute_network_firewall_policy_rule" "this" {
  for_each = var.rules

  project                 = local.project_id
  firewall_policy         = google_compute_network_firewall_policy.this.name
  rule_name               = each.key
  description             = each.value.description
  priority                = each.value.priority
  direction               = each.value.direction
  action                  = each.value.action
  enable_logging          = each.value.enable_logging
  target_service_accounts = length(each.value.target_service_accounts) > 0 ? each.value.target_service_accounts : null

  dynamic "target_secure_tags" {
    for_each = toset(each.value.target_secure_tags)
    content {
      name = google_tags_tag_value.this[target_secure_tags.value].id
    }
  }

  match {
    src_ip_ranges  = length(each.value.src_ip_ranges) > 0 ? each.value.src_ip_ranges : null
    dest_ip_ranges = length(each.value.dest_ip_ranges) > 0 ? each.value.dest_ip_ranges : null

    dynamic "src_secure_tags" {
      for_each = toset(each.value.src_secure_tags)
      content {
        name = google_tags_tag_value.this[src_secure_tags.value].id
      }
    }

    dynamic "layer4_configs" {
      for_each = each.value.layer4_configs
      content {
        ip_protocol = layer4_configs.value.ip_protocol
        ports       = length(layer4_configs.value.ports) > 0 ? layer4_configs.value.ports : null
      }
    }
  }
}

# Denegación por defecto de la entrada: la crea siempre el módulo, con registro, y ninguna
# regla del llamador puede quedar después (prioridad máxima 64999). Reemplaza a la
# denegación por defecto de la antigua política jerárquica (ADR 0029 §6).
resource "google_compute_network_firewall_policy_rule" "default_deny_ingress" {
  project         = local.project_id
  firewall_policy = google_compute_network_firewall_policy.this.name
  rule_name       = "default-deny-ingress"
  description     = "Denegar toda la entrada por defecto."
  priority        = local.default_deny_ingress_priority
  direction       = "INGRESS"
  action          = "deny"
  enable_logging  = true

  match {
    src_ip_ranges = ["0.0.0.0/0"]
    layer4_configs {
      ip_protocol = "all"
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "default_deny_egress" {
  count = var.enable_egress_default_deny ? 1 : 0

  project         = local.project_id
  firewall_policy = google_compute_network_firewall_policy.this.name
  rule_name       = "default-deny-egress"
  description     = "Denegar toda la salida por defecto."
  priority        = local.default_deny_egress_priority
  direction       = "EGRESS"
  action          = "deny"
  enable_logging  = true

  match {
    dest_ip_ranges = ["0.0.0.0/0"]
    layer4_configs {
      ip_protocol = "all"
    }
  }
}
