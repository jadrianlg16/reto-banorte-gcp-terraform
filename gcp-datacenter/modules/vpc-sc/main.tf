# Política de Access Context Manager (opcional), perímetro de VPC Service Controls y alta de
# proyectos en él. La membresía de proyectos se maneja SIEMPRE con recursos separados
# (..._service_perimeter_resource o ..._dry_run_resource), tanto la de este módulo como la
# que agrega la etapa 4 (ADR 0009); el perímetro ignora sus listas de recursos.

locals {
  create_policy    = var.access_policy_id == null
  access_policy_id = local.create_policy ? google_access_context_manager_access_policy.this[0].name : var.access_policy_id
  short_name       = coalesce(var.perimeter_name, "${var.prefix}_${var.environment}_sec_perimeter")
  full_name        = "accessPolicies/${local.access_policy_id}/servicePerimeters/${local.short_name}"

  # Configuración común: va en status (forzado) o en spec (dry-run), nunca en los dos.
  config = {
    restricted_services = sort(var.restricted_services)
    ingress_identities  = sort(var.ingress_identities)
    egress_policies     = var.egress_policies
  }
}

# Solo puede haber una política de organización. Si ya existe, se pasa access_policy_id.
resource "google_access_context_manager_access_policy" "this" {
  count = local.create_policy ? 1 : 0

  parent = "organizations/${var.org_id}"
  title  = coalesce(var.access_policy_title, "${var.prefix}-org-access-policy")
}

resource "google_access_context_manager_service_perimeter" "this" {
  parent         = "accessPolicies/${local.access_policy_id}"
  name           = local.full_name
  title          = local.short_name
  description    = "Perímetro de VPC Service Controls de ${var.environment}. Administrado por Terraform."
  perimeter_type = "PERIMETER_TYPE_REGULAR"

  # Con dry-run, la configuración vive solo en spec y status queda vacío: no se bloquea nada,
  # solo se registran violaciones en los logs de auditoría.
  # VERIFICAR-EN-APPLY: que la API acepte el perímetro en dry-run sin bloque status y que el
  # cambio a forzado (spec → status) se aplique en un solo plan.
  use_explicit_dry_run_spec = !var.enforced

  dynamic "status" {
    for_each = var.enforced ? [local.config] : []
    content {
      restricted_services = status.value.restricted_services

      # VERIFICAR-EN-APPLY: regla de entrada de las cuentas del pipeline (pendiente 5).
      dynamic "ingress_policies" {
        for_each = length(status.value.ingress_identities) > 0 ? [status.value.ingress_identities] : []
        content {
          ingress_from {
            identities = ingress_policies.value
            sources {
              access_level = "*"
            }
          }
          ingress_to {
            resources = ["*"]
            operations {
              service_name = "*"
            }
          }
        }
      }

      dynamic "egress_policies" {
        for_each = status.value.egress_policies
        content {
          egress_from {
            identities    = length(egress_policies.value.identities) > 0 ? egress_policies.value.identities : null
            identity_type = egress_policies.value.identity_type
          }
          egress_to {
            resources          = length(egress_policies.value.resources) > 0 ? egress_policies.value.resources : null
            external_resources = length(egress_policies.value.external_resources) > 0 ? egress_policies.value.external_resources : null
            dynamic "operations" {
              for_each = egress_policies.value.operations
              content {
                service_name = operations.key
                dynamic "method_selectors" {
                  for_each = operations.key == "*" ? [] : (length(operations.value) > 0 ? operations.value : ["*"])
                  content {
                    method = method_selectors.value
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  dynamic "spec" {
    for_each = var.enforced ? [] : [local.config]
    content {
      restricted_services = spec.value.restricted_services

      dynamic "ingress_policies" {
        for_each = length(spec.value.ingress_identities) > 0 ? [spec.value.ingress_identities] : []
        content {
          ingress_from {
            identities = ingress_policies.value
            sources {
              access_level = "*"
            }
          }
          ingress_to {
            resources = ["*"]
            operations {
              service_name = "*"
            }
          }
        }
      }

      dynamic "egress_policies" {
        for_each = spec.value.egress_policies
        content {
          egress_from {
            identities    = length(egress_policies.value.identities) > 0 ? egress_policies.value.identities : null
            identity_type = egress_policies.value.identity_type
          }
          egress_to {
            resources          = length(egress_policies.value.resources) > 0 ? egress_policies.value.resources : null
            external_resources = length(egress_policies.value.external_resources) > 0 ? egress_policies.value.external_resources : null
            dynamic "operations" {
              for_each = egress_policies.value.operations
              content {
                service_name = operations.key
                dynamic "method_selectors" {
                  for_each = operations.key == "*" ? [] : (length(operations.value) > 0 ? operations.value : ["*"])
                  content {
                    method = method_selectors.value
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  lifecycle {
    # Los proyectos entran por recursos separados (abajo y en la etapa 4). Sin esto, cada plan
    # de esta raíz querría sacar los proyectos que agregó otra etapa (drift falso).
    ignore_changes = [
      status[0].resources,
      spec[0].resources,
    ]
  }
}

resource "google_access_context_manager_service_perimeter_resource" "this" {
  for_each = var.enforced ? toset(var.resources) : toset([])

  perimeter_name = google_access_context_manager_service_perimeter.this.name
  resource       = each.value
}

resource "google_access_context_manager_service_perimeter_dry_run_resource" "this" {
  for_each = var.enforced ? toset([]) : toset(var.resources)

  perimeter_name = google_access_context_manager_service_perimeter.this.name
  resource       = each.value
}
