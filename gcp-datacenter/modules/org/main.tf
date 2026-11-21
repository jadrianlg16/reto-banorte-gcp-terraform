locals {
  policy_parent = coalesce(var.policy_parent, "organizations/${var.org_id}")

  # Las nueve políticas de organización. Son fijas: el módulo no permite apagar ninguna.
  # Booleanas: enforce = "TRUE". De lista: deny_all o allowed_values.
  policies = {
    "compute.vmExternalIpAccess" = {
      enforce        = null
      deny_all       = "TRUE"
      allowed_values = null
    }
    "iam.disableServiceAccountKeyCreation" = {
      enforce        = "TRUE"
      deny_all       = null
      allowed_values = null
    }
    "gcp.resourceLocations" = {
      enforce  = null
      deny_all = null
      # VERIFICAR-EN-APPLY: que los grupos in:<región>-locations y las ubicaciones extra admitan
      # el bucket de doble región, los llaveros de la multirregión us y los recursos globales.
      allowed_values = distinct(concat(
        [for r in var.allowed_regions : "in:${r}-locations"],
        var.additional_allowed_locations,
      ))
    }
    "compute.requireShieldedVm" = {
      enforce        = "TRUE"
      deny_all       = null
      allowed_values = null
    }
    "storage.publicAccessPrevention" = {
      enforce        = "TRUE"
      deny_all       = null
      allowed_values = null
    }
    "storage.uniformBucketLevelAccess" = {
      enforce        = "TRUE"
      deny_all       = null
      allowed_values = null
    }
    "compute.skipDefaultNetworkCreation" = {
      enforce        = "TRUE"
      deny_all       = null
      allowed_values = null
    }
    "iam.allowedPolicyMemberDomains" = {
      enforce  = null
      deny_all = null
      # VERIFICAR-EN-APPLY: que los agentes de servicio de Google (Logging, Cloud Storage, GKE)
      # sigan recibiendo roles con esta restricción activa.
      allowed_values = [var.directory_customer_id]
    }
    "sql.restrictPublicIp" = {
      enforce        = "TRUE"
      deny_all       = null
      allowed_values = null
    }
  }

  sink_name = "${var.prefix}-common-ops-audit-sink"

  # Bucket del destino, si es de Cloud Storage. startswith da un resultado conocido aunque el
  # nombre del bucket se calcule en el mismo plan.
  sink_to_storage = startswith(var.log_sink_destination, "storage.googleapis.com/")
}

# --- Políticas de organización (API v2) -----------------------------------------------------

resource "google_org_policy_policy" "this" {
  for_each = local.policies

  name   = "${local.policy_parent}/policies/${each.key}"
  parent = local.policy_parent

  spec {
    rules {
      enforce  = each.value.enforce
      deny_all = each.value.deny_all

      dynamic "values" {
        for_each = each.value.allowed_values == null ? [] : [each.value.allowed_values]
        content {
          allowed_values = values.value
        }
      }
    }
  }
}

# --- Sink agregado de la organización -------------------------------------------------------

resource "google_logging_organization_sink" "this" {
  name             = local.sink_name
  org_id           = var.org_id
  description      = "Sink agregado de auditoría de toda la organización."
  destination      = var.log_sink_destination
  filter           = var.log_sink_filter
  include_children = true
}

resource "google_storage_bucket_iam_member" "sink_writer" {
  for_each = var.grant_sink_writer && local.sink_to_storage ? toset(["this"]) : toset([])

  bucket = trimprefix(var.log_sink_destination, "storage.googleapis.com/")
  role   = "roles/storage.objectCreator"
  member = google_logging_organization_sink.this.writer_identity
}
