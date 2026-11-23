# Política de Access Context Manager (opcional), perímetro de VPC Service Controls y alta de
# proyectos en él. La membresía de proyectos y las reglas de entrada se manejan SIEMPRE con
# recursos separados (..._service_perimeter_resource / ..._dry_run_resource y
# ..._ingress_policy / ..._dry_run_ingress_policy), tanto las de este módulo como las que
# agrega la etapa 4 (ADR 0009); el perímetro ignora sus listas de recursos y de reglas de
# entrada. Las reglas de salida siguen en línea: nadie más las agrega.

locals {
  create_policy    = var.access_policy_id == null
  access_policy_id = local.create_policy ? google_access_context_manager_access_policy.this[0].name : var.access_policy_id
  short_name       = coalesce(var.perimeter_name, "${var.prefix}_${var.environment}_sec_perimeter")
  full_name        = "accessPolicies/${local.access_policy_id}/servicePerimeters/${local.short_name}"

  # Configuración común: va en status (forzado) o en spec (dry-run), nunca en los dos.
  config = {
    restricted_services = sort(var.restricted_services)
    egress_policies     = var.egress_policies
  }

  # Regla de entrada de las cuentas del pipeline: una sola, en status (forzado) o en spec
  # (dry-run), según el modo.
  pipeline_ingress = length(var.ingress_identities) > 0 ? { pipeline = sort(var.ingress_identities) } : {}

  # Título de la regla: único dentro del perímetro (lo exige la API) y distinto para cada
  # conjunto de identidades. Todos los campos de la regla fuerzan reemplazo y la regla usa
  # create_before_destroy: con un título fijo, el reemplazo agregaría una segunda regla con el
  # mismo título antes de quitar la vieja. Con el hash, la nueva convive un momento con la
  # vieja y después se quita la vieja (el proveedor la busca por título y contenido).
  pipeline_ingress_title = "${local.short_name}-pipeline-${substr(sha256(join(",", sort(var.ingress_identities))), 0, 8)}"
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

      # Reglas de entrada: recursos aparte (abajo y en la etapa 4).

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

      # Reglas de entrada: recursos aparte (abajo y en la etapa 4).

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
    # Los proyectos y las reglas de entrada entran por recursos separados (abajo y en la
    # etapa 4). Sin esto, cada apply de la raíz que llama al módulo quitaría los proyectos y
    # las reglas de entrada que agregó otra etapa (la documentación del proveedor de los
    # recursos ..._ingress_policy y ..._dry_run_ingress_policy exige este ignore_changes).
    ignore_changes = [
      status[0].resources,
      spec[0].resources,
      status[0].ingress_policies,
      spec[0].ingress_policies,
    ]
  }
}

# Regla de entrada de las cuentas del pipeline: desde cualquier origen (el pipeline corre fuera
# de GCP), a todos los servicios y proyectos del perímetro. Forzado → status; dry-run → spec.
# create_before_destroy: el proveedor quita y vuelve a agregar la regla al cambiarla; así la
# nueva entra antes de quitar la vieja (recomendación de la documentación del proveedor) y el
# título lleva un hash de las identidades para que las dos no choquen (local.pipeline_ingress_title).
# Se prefiere a quitar create_before_destroy: si la creación de la regla nueva falla, la vieja
# sigue y el pipeline conserva su acceso; sin create_before_destroy, un fallo dejaría el
# perímetro forzado sin la regla del pipeline y las etapas 4 y 5 no podrían usar los servicios
# restringidos de los proyectos de prod hasta un apply correcto de esta etapa (la API de Access
# Context Manager es de organización y el perímetro no la restringe).
# VERIFICAR-EN-APPLY: regla de entrada de las cuentas del pipeline (pendiente 5).
resource "google_access_context_manager_service_perimeter_ingress_policy" "pipeline" {
  for_each = var.enforced ? local.pipeline_ingress : {}

  perimeter = google_access_context_manager_service_perimeter.this.name
  title     = local.pipeline_ingress_title

  ingress_from {
    identities = each.value
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

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_access_context_manager_service_perimeter_dry_run_ingress_policy" "pipeline" {
  for_each = var.enforced ? {} : local.pipeline_ingress

  perimeter = google_access_context_manager_service_perimeter.this.name
  title     = local.pipeline_ingress_title

  ingress_from {
    identities = each.value
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

  lifecycle {
    create_before_destroy = true
  }
}

# Los proyectos entran DESPUÉS de la regla de entrada del pipeline (depends_on): el perímetro
# recién creado no tiene proyectos y no restringe nada, así que no hay ventana en que el
# pipeline quede fuera de un proyecto ya protegido.
resource "google_access_context_manager_service_perimeter_resource" "this" {
  for_each = var.enforced ? toset(var.resources) : toset([])

  perimeter_name = google_access_context_manager_service_perimeter.this.name
  resource       = each.value

  depends_on = [google_access_context_manager_service_perimeter_ingress_policy.pipeline]
}

resource "google_access_context_manager_service_perimeter_dry_run_resource" "this" {
  for_each = var.enforced ? toset([]) : toset(var.resources)

  perimeter_name = google_access_context_manager_service_perimeter.this.name
  resource       = each.value

  depends_on = [google_access_context_manager_service_perimeter_dry_run_ingress_policy.pipeline]
}
