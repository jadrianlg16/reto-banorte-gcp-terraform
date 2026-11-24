locals {
  # <empresa>-<entorno>-<dominio>-<recurso>[-<sufijo>] (convención de nombres).
  project_id = join("-", compact([var.prefix, var.environment, var.name, var.project_suffix]))

  shared_vpc_service = var.shared_vpc_host_project != null

  # APIs de todo proyecto (docs/cumplimiento-cis.md): Cloud Asset Inventory (CIS 2.14, el
  # detector CLOUD_ASSET_API_DISABLED revisa cada proyecto) y Logging y Monitoring, que usan las
  # métricas y alertas de auditoría (módulo audit-alerts, CIS 2.5 a 2.12). Shared VPC (host o
  # servicio) necesita además la API de Compute.
  baseline_apis = ["cloudasset.googleapis.com", "logging.googleapis.com", "monitoring.googleapis.com"]
  apis = setunion(
    var.apis,
    local.baseline_apis,
    var.shared_vpc_host || local.shared_vpc_service ? ["compute.googleapis.com"] : [],
  )

  # OS Login en el proyecto (CIS 4.4): el detector OS_LOGIN_DISABLED lee el metadato
  # enable-oslogin del proyecto. Solo donde hay Compute Engine: sin la API no hay metadatos de
  # proyecto que escribir.
  enable_os_login = contains(local.apis, "compute.googleapis.com")

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

# OS Login en todo el proyecto (CIS 4.4), con un elemento de metadato y no con la política de
# organización compute.requireOsLogin: según la documentación de Google, la política escribe
# enable-oslogin solo en los proyectos nuevos (no en el semilla, creado antes de la etapa 1) e
# impide apagarlo; el metadato es lo que lee el detector y cubre todos los proyectos del
# repositorio. Las VM del MIG ya lo fijan por instancia (compute-mig) y los nodos de GKE
# Standard lo heredan sin reiniciar (documentación de OS Login para GKE).
# VERIFICAR-EN-APPLY: que el detector OS_LOGIN_DISABLED no marque los proyectos y que IAP + OS
# Login sigan dando SSH a quien tenga roles/compute.osLogin (pendiente 59).
resource "google_compute_project_metadata_item" "os_login" {
  for_each = local.enable_os_login ? toset(["enable-oslogin"]) : toset([])

  project = google_project.this.project_id
  key     = each.key
  value   = "TRUE"

  depends_on = [google_project_service.this]
}
