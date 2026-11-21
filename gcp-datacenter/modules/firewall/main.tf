locals {
  is_hierarchical = var.policy_type == "hierarchical"
  is_network      = var.policy_type == "network"

  # <empresa>-<entorno>-net-fw (convención de nombres del contrato).
  name = "${var.prefix}-${var.environment}-net-fw"

  # Proyecto y nombre de la VPC cuando la política es de red.
  network_parts = local.is_network ? regex("projects/([^/]+)/global/networks/([^/]+)$", var.parent) : ["", ""]
  project_id    = local.network_parts[0]
  network_id    = "projects/${local.network_parts[0]}/global/networks/${local.network_parts[1]}"

  # Prioridades reservadas para las reglas que el módulo crea siempre.
  default_deny_ingress_priority = 65000
  default_deny_egress_priority  = 65001

  tag_parent = coalesce(var.secure_tag_parent, local.is_network ? "projects/${local.project_id}" : "-")

  # En network la etiqueta queda ligada a la VPC; en hierarchical, a la organización
  # (único alcance que aceptan las reglas de una política jerárquica).
  # VERIFICAR-EN-APPLY: formato de purpose_data (network = "<proyecto>/<red>" y
  # organization = "auto") y que la política jerárquica acepte etiquetas de la organización.
  tag_purpose_data = local.is_network ? { network = "${local.network_parts[0]}/${local.network_parts[1]}" } : { organization = "auto" }

  # Las reglas goto_next se crean sin registro: solo delegan la decisión al siguiente nivel,
  # que es el que registra. VERIFICAR-EN-APPLY: si el API admite enable_logging en goto_next.
  rules = {
    for k, r in var.rules : k => merge(r, {
      enable_logging = r.action == "goto_next" ? false : r.enable_logging
    })
  }
}

# ---------------------------------------------------------------------------------------
# Etiquetas seguras

# Una llave por entrada de secure_tags, con un solo valor (enabled): un recurso admite un
# solo valor por llave, y una VM puede necesitar varias etiquetas a la vez (por ejemplo
# lb_backend e iap_ssh). Nombre de la llave: <empresa>-<entorno>-net-fw-<entrada>.
resource "google_tags_tag_key" "this" {
  for_each = var.secure_tags

  parent       = local.tag_parent
  short_name   = "${local.name}-${replace(each.key, "_", "-")}"
  description  = coalesce(each.value.description, "Etiqueta segura de firewall ${each.key} (${var.policy_type}) administrada por Terraform.")
  purpose      = "GCE_FIREWALL"
  purpose_data = local.tag_purpose_data
}

resource "google_tags_tag_value" "this" {
  for_each = var.secure_tags

  parent      = google_tags_tag_key.this[each.key].id
  short_name  = "enabled"
  description = "La etiqueta ${each.key} está activa en el recurso."
}

# ---------------------------------------------------------------------------------------
# Política jerárquica (organización o carpeta)

resource "google_compute_firewall_policy" "this" {
  count = local.is_hierarchical ? 1 : 0

  parent      = var.parent
  short_name  = local.name
  description = "Política jerárquica administrada por Terraform: deniega la entrada por defecto."
}

resource "google_compute_firewall_policy_association" "this" {
  count = local.is_hierarchical ? 1 : 0

  name              = "${local.name}-assoc"
  firewall_policy   = google_compute_firewall_policy.this[0].id
  attachment_target = var.parent
}

resource "google_compute_firewall_policy_rule" "this" {
  for_each = local.is_hierarchical ? local.rules : {}

  firewall_policy         = google_compute_firewall_policy.this[0].name
  description             = each.value.description
  priority                = each.value.priority
  direction               = each.value.direction
  action                  = each.value.action
  enable_logging          = each.value.enable_logging
  target_resources        = length(each.value.target_resources) > 0 ? each.value.target_resources : null
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
# regla del llamador puede quedar después (prioridad máxima 64999). Lo que deba decidir la
# política de red del spoke se delega antes con reglas goto_next.
resource "google_compute_firewall_policy_rule" "default_deny_ingress" {
  count = local.is_hierarchical ? 1 : 0

  firewall_policy = google_compute_firewall_policy.this[0].name
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

resource "google_compute_firewall_policy_rule" "default_deny_egress" {
  count = local.is_hierarchical && var.enable_egress_default_deny ? 1 : 0

  firewall_policy = google_compute_firewall_policy.this[0].name
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

# ---------------------------------------------------------------------------------------
# Política de firewall de red global (una VPC)

resource "google_compute_network_firewall_policy" "this" {
  count = local.is_network ? 1 : 0

  project     = local.project_id
  name        = local.name
  description = "Política de red administrada por Terraform: deniega la entrada por defecto."
}

resource "google_compute_network_firewall_policy_association" "this" {
  count = local.is_network ? 1 : 0

  project           = local.project_id
  name              = "${local.name}-assoc"
  firewall_policy   = google_compute_network_firewall_policy.this[0].id
  attachment_target = local.network_id
}

resource "google_compute_network_firewall_policy_rule" "this" {
  for_each = local.is_network ? local.rules : {}

  project                 = local.project_id
  firewall_policy         = google_compute_network_firewall_policy.this[0].name
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

resource "google_compute_network_firewall_policy_rule" "default_deny_ingress" {
  count = local.is_network ? 1 : 0

  project         = local.project_id
  firewall_policy = google_compute_network_firewall_policy.this[0].name
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
  count = local.is_network && var.enable_egress_default_deny ? 1 : 0

  project         = local.project_id
  firewall_policy = google_compute_network_firewall_policy.this[0].name
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
