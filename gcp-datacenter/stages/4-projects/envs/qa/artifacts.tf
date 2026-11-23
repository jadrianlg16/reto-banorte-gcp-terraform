# Imágenes de contenedor de cada aplicación y la política de Binary Authorization que solo admite
# esas imágenes. Un repositorio Docker por proyecto de servicio en la multirregión
# artifact_registry_location (sobrevive a la pérdida de una región, runbook de conmutación),
# cifrado con la llave artifacts de la etapa 2 de esa ubicación.

locals {
  # [app] → ID del repositorio (§4.2: dominio app; la multirregión va en lugar del código de región).
  artifact_repository_ids = {
    for app in keys(var.applications) : app => "${var.prefix}-${var.environment}-app-${app}-images-${var.artifact_registry_location}"
  }

  # [app] → ruta Docker del repositorio: <ubicación>-docker.pkg.dev/<proyecto>/<repositorio>.
  artifact_repository_paths = {
    for app in keys(var.applications) : app => "${var.artifact_registry_location}-docker.pkg.dev/${module.project[app].project_id}/${local.artifact_repository_ids[app]}"
  }

  # Quién descarga imágenes del repositorio: nodos de GKE, VM del MIG y el agente de Cloud Run
  # (Cloud Run descarga la imagen con su agente de servicio, no con la cuenta del servicio).
  artifact_readers = merge([
    for app in keys(var.applications) : {
      "${app}/gke_nodes" = { app = app, member = google_service_account.runtime["${app}/gke_nodes"].member }
      "${app}/mig"       = { app = app, member = google_service_account.runtime["${app}/mig"].member }
      "${app}/run_agent" = { app = app, member = local.service_agents[app]["run"] }
    }
  ]...)

  # "<app>/<miembro>" → quién publica imágenes en el repositorio de la aplicación.
  artifact_writers = merge([
    for app, members in var.artifact_registry_publishers : {
      # distinct: un miembro repetido en la lista no debe duplicar la llave del mapa.
      for m in distinct(members) : "${app}/${m}" => { app = app, member = m }
    }
  ]...)

  # Sin atestadores: se niega todo lo que no esté en la lista de permitidos. Con atestadores:
  # además de la lista, cualquier imagen con la atestación de todos ellos.
  binauthz_evaluation_mode = length(var.binary_authorization_attestors) > 0 ? "REQUIRE_ATTESTATION" : "ALWAYS_DENY"
}

# VERIFICAR-EN-APPLY: que el agente de Artifact Registry tenga cryptoKeyEncrypterDecrypter sobre
# la llave antes de crear el repositorio (depends_on module.iam) y que la llave de la
# multirregión se acepte para un repositorio de esa misma multirregión.
resource "google_artifact_registry_repository" "this" {
  for_each = var.applications

  project       = module.project[each.key].project_id
  location      = var.artifact_registry_location
  repository_id = local.artifact_repository_ids[each.key]
  description   = "Imágenes de contenedor de ${each.key} en ${var.environment} (administrado por Terraform, etapa 4)."
  format        = "DOCKER"
  kms_key_name  = local.kms_key_ids[var.artifact_registry_location]["artifacts"]
  labels        = merge(local.labels, { app = each.key })

  # Etiquetas inmutables: una etiqueta publicada no se puede mover a otra imagen.
  docker_config {
    immutable_tags = true
  }

  depends_on = [module.iam]
}

resource "google_artifact_registry_repository_iam_member" "reader" {
  for_each = local.artifact_readers

  project    = google_artifact_registry_repository.this[each.value.app].project
  location   = google_artifact_registry_repository.this[each.value.app].location
  repository = google_artifact_registry_repository.this[each.value.app].repository_id
  role       = "roles/artifactregistry.reader"
  member     = each.value.member
}

# Publicación: writer solo sobre el repositorio de su aplicación (no sobre el proyecto). Es la
# única vía para que una imagen llegue al registro que Binary Authorization admite.
resource "google_artifact_registry_repository_iam_member" "writer" {
  for_each = local.artifact_writers

  project    = google_artifact_registry_repository.this[each.value.app].project
  location   = google_artifact_registry_repository.this[each.value.app].location
  repository = google_artifact_registry_repository.this[each.value.app].repository_id
  role       = "roles/artifactregistry.writer"
  member     = each.value.member
}

# Política de Binary Authorization del proyecto (la usan GKE con
# PROJECT_SINGLETON_POLICY_ENFORCE y Cloud Run con use_default = true). Por defecto niega todo;
# admite el repositorio de la aplicación y los patrones extra. La política global de Google
# (imágenes de sistema de GKE) se evalúa antes.
# VERIFICAR-EN-APPLY: que un despliegue de Cloud Run y un pod de GKE con una imagen del
# repositorio pasen y que una imagen de otro registro se rechace con ENFORCED_BLOCK_AND_AUDIT_LOG.
resource "google_binary_authorization_policy" "this" {
  for_each = var.applications

  project                       = module.project[each.key].project_id
  description                   = "Política de ${each.key} en ${var.environment}: solo imágenes del repositorio de la aplicación (administrada por Terraform, etapa 4)."
  global_policy_evaluation_mode = "ENABLE"

  # La barra antes de ** evita que el patrón cubra otro repositorio cuyo nombre empiece igual.
  dynamic "admission_whitelist_patterns" {
    for_each = concat(["${local.artifact_repository_paths[each.key]}/**"], var.binary_authorization_allowlist_patterns)
    content {
      name_pattern = admission_whitelist_patterns.value
    }
  }

  default_admission_rule {
    evaluation_mode         = local.binauthz_evaluation_mode
    enforcement_mode        = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    require_attestations_by = length(var.binary_authorization_attestors) > 0 ? var.binary_authorization_attestors : null
  }
}
