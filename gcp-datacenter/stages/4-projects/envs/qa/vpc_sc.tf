# Solo en prod (ADR 0009, §7.5): alta en el perímetro de VPC-SC que creó la etapa 2 de cada
# proyecto de servicio y del proyecto host de la Shared VPC (VPC-SC exige que el host esté en el
# mismo perímetro que sus proyectos de servicio). El recurso depende del modo del perímetro
# (vpc_sc_enforced del estado de 2-security): forzado → status
# (..._service_perimeter_resource); dry-run → spec (..._service_perimeter_dry_run_resource). El
# perímetro ignora sus listas de recursos (módulo vpc-sc), así que estas altas no generan drift
# en la etapa 2.
# Al pasar de dry-run a forzado: se aplica la etapa 2 y después esta, que cambia cada alta de un
# recurso al otro.
# VERIFICAR-EN-APPLY: uso de las llaves CMEK del proyecto security desde estos proyectos con el
# perímetro forzado (§12, punto 4).

# El estado del spoke solo publica el ID del host; el perímetro pide projects/<número>.
data "google_project" "host" {
  for_each = local.is_prod ? toset(["host"]) : toset([])

  project_id = local.host_project_id
}

locals {
  # Llave estable → projects/<número>. "service/<app>" para cada proyecto de servicio y "host"
  # para el host del spoke.
  perimeter_projects = local.is_prod ? merge(
    { for app, p in module.project : "service/${app}" => "projects/${p.project_number}" },
    { host = "projects/${data.google_project.host["host"].number}" },
  ) : {}
}

resource "google_access_context_manager_service_perimeter_resource" "this" {
  for_each = local.vpc_sc_enforced ? local.perimeter_projects : {}

  perimeter_name = local.perimeter_name
  resource       = each.value
}

resource "google_access_context_manager_service_perimeter_dry_run_resource" "this" {
  for_each = local.vpc_sc_enforced ? {} : local.perimeter_projects

  perimeter_name = local.perimeter_name
  resource       = each.value
}
