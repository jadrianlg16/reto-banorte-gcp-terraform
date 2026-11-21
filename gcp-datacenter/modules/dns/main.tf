locals {
  # <empresa>-<entorno>-net-dns-<zona> (convención de nombres del contrato).
  name_base = "${var.prefix}-${var.environment}-net-dns"

  records = merge([
    for zk, z in var.zones : {
      for rk, r in z.records : "${zk}/${rk}" => merge(r, {
        zone = zk
        fqdn = r.name == "" ? z.domain : "${r.name}.${z.domain}"
      })
    }
  ]...)
}

# Todas las zonas son privadas (visibles solo desde las VPC indicadas); el tipo cambia cómo
# resuelven: registros propios, reenvío a servidores on-premises o peering con otra VPC.
resource "google_dns_managed_zone" "this" {
  for_each = var.zones

  project     = var.project_id
  name        = "${local.name_base}-${each.key}"
  dns_name    = each.value.domain
  description = coalesce(each.value.description, "Zona ${each.value.type} administrada por Terraform.")
  visibility  = "private"
  labels      = var.labels

  private_visibility_config {
    dynamic "networks" {
      for_each = toset(coalesce(each.value.networks, var.networks))
      content {
        network_url = networks.value
      }
    }
  }

  dynamic "forwarding_config" {
    for_each = each.value.type == "forwarding" ? [1] : []
    content {
      dynamic "target_name_servers" {
        for_each = each.value.target_name_servers
        content {
          ipv4_address    = target_name_servers.value.ipv4_address
          forwarding_path = target_name_servers.value.forwarding_path
        }
      }
    }
  }

  dynamic "peering_config" {
    for_each = each.value.type == "peering" ? [1] : []
    content {
      target_network {
        network_url = each.value.peer_network
      }
    }
  }
}

resource "google_dns_record_set" "this" {
  for_each = local.records

  project      = var.project_id
  managed_zone = google_dns_managed_zone.this[each.value.zone].name
  name         = each.value.fqdn
  type         = each.value.type
  ttl          = each.value.ttl
  rrdatas      = each.value.rrdatas
}

# Política de servidor: reenvío entrante (on-premises consulta a Cloud DNS por la VPN) y
# registro de consultas. Una VPC admite una sola política de servidor.
resource "google_dns_policy" "this" {
  count = var.server_policy != null ? 1 : 0

  project                   = var.project_id
  name                      = "${local.name_base}-policy"
  description               = "Política de servidor DNS administrada por Terraform."
  enable_inbound_forwarding = var.server_policy.enable_inbound_forwarding
  enable_logging            = var.server_policy.enable_logging

  dynamic "networks" {
    for_each = toset(var.networks)
    content {
      network_url = networks.value
    }
  }
}

# Las direcciones de reenvío entrante las asigna GCP al aplicar la política (una por región
# con subred); el proveedor no las expone en google_dns_policy y se leen como direcciones
# con propósito DNS_RESOLVER.
# VERIFICAR-EN-APPLY: que el filtro devuelva las direcciones de reenvío entrante de la
# política (y solo esas) y que estén disponibles al terminar el apply de la política.
data "google_compute_addresses" "inbound_forwarders" {
  count = var.server_policy != null && try(var.server_policy.enable_inbound_forwarding, false) ? 1 : 0

  project = var.project_id
  filter  = "purpose = \"DNS_RESOLVER\""

  depends_on = [google_dns_policy.this]
}
