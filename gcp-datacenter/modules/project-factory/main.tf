locals {
  # <empresa>-<entorno>-<dominio>-<recurso>[-<sufijo>] (convención de nombres).
  project_id = join("-", compact([var.prefix, var.environment, var.name, var.project_suffix]))

  shared_vpc_service = var.shared_vpc_host_project != null

  # Shared VPC (host o servicio) necesita la API de Compute en el proyecto.
  apis = setunion(
    var.apis,
    var.shared_vpc_host || local.shared_vpc_service ? ["compute.googleapis.com"] : [],
  )

  # Entornos donde destruir el proyecto por error sería grave.
  protected_environments = ["bootstrap", "common", "prod"]
}

resource "google_project" "this" {
  # checkov:skip=CKV2_GCP_5: los registros de Data Access se activan en la carpeta prod (etapa 1-org, por diseño del contrato) y se heredan; activarlos por proyecto en dev y qa contradice ese diseño y su costo
  project_id      = local.project_id
  name            = coalesce(var.display_name, local.project_id)
  folder_id       = var.folder_id
  billing_account = var.billing_account
  labels          = var.labels

  # Sin red default: valor fijo (lo exige la especificación). La política de organización
  # compute.skipDefaultNetworkCreation lo refuerza.
  # VERIFICAR-EN-APPLY: que el proyecto se cree sin red default y sin error del proveedor al
  # intentar borrarla cuando la política de organización ya impidió crearla.
  auto_create_network = false

  deletion_policy = var.deletion_policy

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", local.project_id))
      error_message = "El ID de proyecto <prefix>-<environment>-<name>[-<project_suffix>] debe tener de 6 a 30 caracteres, empezar con letra y no terminar en guion."
    }
    precondition {
      condition     = !contains(local.protected_environments, var.environment) || var.deletion_policy == "PREVENT"
      error_message = "En bootstrap, common y prod deletion_policy debe ser PREVENT."
    }
    precondition {
      condition     = !(var.shared_vpc_host && local.shared_vpc_service)
      error_message = "Un proyecto no puede ser host de Shared VPC y servicio a la vez."
    }
  }
}

resource "google_project_service" "this" {
  for_each = local.apis

  project                    = google_project.this.project_id
  service                    = each.value
  disable_on_destroy         = var.disable_services_on_destroy
  disable_dependent_services = false
}

resource "google_compute_shared_vpc_host_project" "this" {
  for_each = var.shared_vpc_host ? toset(["this"]) : toset([])

  project = google_project.this.project_id

  depends_on = [google_project_service.this]
}

# El host debe tener ya la API de Compute y estar habilitado como host (lo hace su propia
# instancia de este módulo, en una etapa anterior).
resource "google_compute_shared_vpc_service_project" "this" {
  for_each = local.shared_vpc_service ? toset(["this"]) : toset([])

  host_project    = var.shared_vpc_host_project
  service_project = google_project.this.project_id

  depends_on = [google_project_service.this]
}
