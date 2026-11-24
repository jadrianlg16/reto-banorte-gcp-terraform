# Imágenes (ADR 0029 §4 y ADR 0024): un repositorio Docker por entorno y aplicación
# (<prefix>-<env>-<app>) en artifact_registry_location, cifrado con la llave artifacts del
# entorno en esa ubicación, y la única política de Binary Authorization del proyecto.

locals {
  # "<env>/<app>" → repositorio.
  repositories = {
    for pair in setproduct(var.environments, var.applications) : "${pair[0]}/${pair[1]}" => {
      environment   = pair[0]
      app           = pair[1]
      repository_id = "${var.prefix}-${pair[0]}-${pair[1]}"
    }
  }

  # "<env>/<app>" → ruta Docker: <ubicación>-docker.pkg.dev/<proyecto>/<repositorio>.
  repository_paths = {
    for k, r in local.repositories : k => "${var.artifact_registry_location}-docker.pkg.dev/${local.project_id}/${r.repository_id}"
  }

  # "<env>/<app>/<miembro>" → quién publica imágenes en el repositorio.
  repository_writers = merge(flatten([
    for e, apps in var.artifact_registry_publishers : [
      for a, members in apps : {
        # distinct: un miembro repetido no debe duplicar la llave del mapa.
        for m in distinct(members) : "${e}/${a}/${m}" => { repository = "${e}/${a}", member = m }
      }
    ]
  ])...)

  # Sin atestadores: se niega todo lo que no esté en la lista de permitidos. Con atestadores:
  # además de la lista, cualquier imagen con la atestación de todos ellos.
  binauthz_evaluation_mode = length(var.binary_authorization_attestors) > 0 ? "REQUIRE_ATTESTATION" : "ALWAYS_DENY"

  # Clústeres de GKE de prod por convención (ADR 0029 §4): <prefix>-prod-<app>-gke en la región
  # primaria y <prefix>-prod-<app>-gke-dr en la de DR (identificador <ubicación>.<clúster>).
  prod_clusters = contains(var.environments, "prod") ? toset(flatten([
    for a in var.applications : [
      "${var.primary_region}.${var.prefix}-prod-${a}-gke",
      "${var.dr_region}.${var.prefix}-prod-${a}-gke-dr",
    ]
  ])) : toset([])
}

# VERIFICAR-EN-APPLY: que el agente de Artifact Registry tenga cryptoKeyEncrypterDecrypter sobre
# la llave antes de crear el repositorio (depends_on module.kms) y que la llave de la
# multirregión se acepte para un repositorio de esa misma multirregión.
resource "google_artifact_registry_repository" "this" {
  for_each = local.repositories

  project       = local.project_id
  location      = var.artifact_registry_location
  repository_id = each.value.repository_id
  description   = "Imágenes de contenedor de ${each.value.app} en ${each.value.environment} (administrado por Terraform, 1-base)."
  format        = "DOCKER"
  kms_key_name  = module.kms["${each.value.environment}/${var.artifact_registry_location}"].key_ids["artifacts"]
  labels        = merge(local.labels_by_env[each.value.environment], { app = each.value.app })

  # Etiquetas inmutables: una etiqueta publicada no se puede mover a otra imagen.
  docker_config {
    immutable_tags = true
  }

  lifecycle {
    precondition {
      condition     = contains(local.kms_locations, var.artifact_registry_location)
      error_message = "artifact_registry_location debe ser us, primary_region o dr_region: ahí hay llave artifacts."
    }
  }

  depends_on = [module.kms]
}

# Cloud Run descarga la imagen con su agente de servicio, que es uno por proyecto: lectura de los
# repositorios de los tres entornos (riesgo aceptado, ADR 0029 §9). Los nodos de GKE y las VM
# reciben la lectura de su repositorio en runtime_accounts.tf.
resource "google_artifact_registry_repository_iam_member" "run_agent_reader" {
  for_each = local.repositories

  project    = google_artifact_registry_repository.this[each.key].project
  location   = google_artifact_registry_repository.this[each.key].location
  repository = google_artifact_registry_repository.this[each.key].repository_id
  role       = "roles/artifactregistry.reader"
  member     = local.service_agents["run"]
}

# Publicación: writer solo sobre el repositorio de su entorno y aplicación. Es la única vía para
# que una imagen llegue a un registro que Binary Authorization admite.
resource "google_artifact_registry_repository_iam_member" "writer" {
  for_each = local.repository_writers

  project    = google_artifact_registry_repository.this[each.value.repository].project
  location   = google_artifact_registry_repository.this[each.value.repository].location
  repository = google_artifact_registry_repository.this[each.value.repository].repository_id
  role       = "roles/artifactregistry.writer"
  member     = each.value.member

  lifecycle {
    precondition {
      condition     = contains(keys(local.repositories), each.value.repository)
      error_message = "artifact_registry_publishers nombra un entorno o una aplicación sin repositorio."
    }
  }
}

# Política única de Binary Authorization del proyecto (GKE con PROJECT_SINGLETON_POLICY_ENFORCE y
# Cloud Run con use_default = true). La lista de permitidos tiene los repositorios del proyecto y
# los patrones extra; la regla por defecto niega lo demás (o exige atestaciones). La política
# global de Google (imágenes de sistema de GKE) se evalúa antes.
#
# Desviación del ADR 0029 §4: la lista de permitidos es global y una imagen que coincide con ella
# se admite "regardless of your admission rules" (descripción del campo en el proveedor 6.x).
# Por eso una regla por clúster no puede limitar los clústeres de prod al repositorio de prod sin
# atestaciones. Las reglas de los clústeres de prod existen por convención de nombres y aplican
# la misma evaluación que la regla por defecto: con binary_authorization_attestors exigen
# atestación a lo que no esté en la lista.
# VERIFICAR-EN-APPLY: que un pod de GKE y un despliegue de Cloud Run con una imagen del
# repositorio pasen y que una imagen de otro registro se rechace con
# ENFORCED_BLOCK_AND_AUDIT_LOG.
resource "google_binary_authorization_policy" "this" {
  project                       = local.project_id
  description                   = "Política del proyecto: solo imágenes de los repositorios de Artifact Registry del proyecto y de los patrones aprobados (administrada por Terraform, 1-base)."
  global_policy_evaluation_mode = "ENABLE"

  # La barra antes de ** evita que el patrón cubra otro repositorio cuyo nombre empiece igual.
  dynamic "admission_whitelist_patterns" {
    for_each = concat([for k in sort(keys(local.repository_paths)) : "${local.repository_paths[k]}/**"], var.binary_authorization_allowlist_patterns)
    content {
      name_pattern = admission_whitelist_patterns.value
    }
  }

  default_admission_rule {
    evaluation_mode         = local.binauthz_evaluation_mode
    enforcement_mode        = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    require_attestations_by = length(var.binary_authorization_attestors) > 0 ? var.binary_authorization_attestors : null
  }

  dynamic "cluster_admission_rules" {
    for_each = local.prod_clusters
    content {
      cluster                 = cluster_admission_rules.value
      evaluation_mode         = local.binauthz_evaluation_mode
      enforcement_mode        = "ENFORCED_BLOCK_AND_AUDIT_LOG"
      require_attestations_by = length(var.binary_authorization_attestors) > 0 ? var.binary_authorization_attestors : null
    }
  }

  depends_on = [google_artifact_registry_repository.this]
}
