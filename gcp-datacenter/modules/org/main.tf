locals {
  policy_parent = "projects/${var.project_id}"

  # Políticas de organización de la línea base, aplicadas al proyecto único (ADR 0029 §1). Son
  # fijas: el módulo no permite apagar ninguna. Booleanas: enforce = "TRUE". De lista: deny_all o
  # allowed_values. compute.skipDefaultNetworkCreation ya no está: solo actúa al crear un
  # proyecto, y el proyecto ya existe (ADR 0029 §6; la red default se borra a mano).
  base_policies = {
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
    "sql.restrictPublicIp" = {
      enforce        = "TRUE"
      deny_all       = null
      allowed_values = null
    }
  }

  # Solo con cliente de Cloud Identity: sin él no hay dominio que admitir.
  domain_policy = var.directory_customer_id == null ? {} : {
    "iam.allowedPolicyMemberDomains" = {
      enforce  = null
      deny_all = null
      # VERIFICAR-EN-APPLY: que los agentes de servicio de Google (Logging, Cloud Storage, GKE)
      # sigan recibiendo roles con esta restricción activa.
      allowed_values = [var.directory_customer_id]
    }
  }

  policies = merge(local.base_policies, local.domain_policy)
}

# --- Políticas de organización (API v2) sobre el proyecto ------------------------------------

# VERIFICAR-EN-APPLY: que una política con padre projects/<id> se cree con
# roles/orgpolicy.policyAdmin dado en la organización a la cuenta que aplica.
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
