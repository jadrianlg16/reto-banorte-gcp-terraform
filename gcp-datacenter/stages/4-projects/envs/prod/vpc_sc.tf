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

# Publicación de imágenes a través del perímetro (solo prod): artifactregistry.googleapis.com
# está restringido y la regla de entrada de la etapa 2 solo admite a las cuentas de las etapas.
# Una regla por aplicación con publicadores: sus identidades (artifact_registry_publishers),
# desde cualquier origen de red (igual que la regla de las cuentas de etapa: el pipeline corre
# fuera de GCP), solo hacia el proyecto de servicio de esa aplicación y solo Artifact Registry.
# Mismo patrón de modo que las altas: forzado → ..._ingress_policy (status); dry-run →
# ..._dry_run_ingress_policy (spec).
# Requiere que el perímetro de la etapa 2 ignore sus ingress_policies (lifecycle del módulo
# vpc-sc) y que la regla de las cuentas de etapa pase a un recurso de política aparte; sin eso,
# el siguiente apply de la etapa 2 quitaría estas reglas (pendientes-apply).
# VERIFICAR-EN-APPLY: docker push de una cuenta publicadora al repositorio de prod con el
# perímetro forzado (y su entrada en el registro de infracciones en dry-run), y que un grupo en
# identities se acepte (VPC-SC tiene límites para grupos en reglas de entrada).
locals {
  artifact_ingress = local.is_prod ? {
    for app, members in var.artifact_registry_publishers : app => {
      identities = sort(distinct(members))
      resource   = "projects/${module.project[app].project_number}"
    } if length(members) > 0
  } : {}
}

resource "google_access_context_manager_service_perimeter_ingress_policy" "artifact_publishers" {
  for_each = local.vpc_sc_enforced ? local.artifact_ingress : {}

  perimeter = local.perimeter_name
  title     = "${var.prefix}-${var.environment}-${each.key}-artifact-push"

  ingress_from {
    identities = each.value.identities
    sources {
      access_level = "*"
    }
  }

  ingress_to {
    resources = [each.value.resource]
    operations {
      service_name = "artifactregistry.googleapis.com"
      method_selectors {
        method = "*"
      }
    }
  }
}

resource "google_access_context_manager_service_perimeter_dry_run_ingress_policy" "artifact_publishers" {
  for_each = local.vpc_sc_enforced ? {} : local.artifact_ingress

  perimeter = local.perimeter_name
  title     = "${var.prefix}-${var.environment}-${each.key}-artifact-push"

  ingress_from {
    identities = each.value.identities
    sources {
      access_level = "*"
    }
  }

  ingress_to {
    resources = [each.value.resource]
    operations {
      service_name = "artifactregistry.googleapis.com"
      method_selectors {
        method = "*"
      }
    }
  }
}
