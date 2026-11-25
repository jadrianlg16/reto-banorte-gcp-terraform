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

  # --- Binary Authorization (ADR 0024 y 0029 §4) ---------------------------------------------
  # Dos modos, según binary_authorization_env_attestors:
  #
  # Por entorno (con un atestador por entorno): los repositorios salen de la lista de permitidos,
  # que queda solo con binary_authorization_allowlist_patterns. Cada clúster de GKE de cada
  # entorno, por convención de nombres, exige el atestador de su entorno (más los de
  # binary_authorization_attestors). Así una imagen de dev sin la atestación de prod no entra a
  # un clúster de prod.
  #
  # Sin atestadores por entorno (el de hoy): los repositorios de los tres entornos están en la
  # lista de permitidos, que es global, y una imagen que coincide con ella se admite en cualquier
  # clúster y en Cloud Run sin mirar las reglas. RIESGO (ADR 0024): una imagen del repositorio de
  # dev se puede desplegar en prod; nada lo impide salvo quién publica en cada repositorio
  # (artifact_registry_publishers) y la revisión del cambio en 3-workloads.
  binauthz_per_environment = length(var.binary_authorization_env_attestors) > 0

  binauthz_allowlist = local.binauthz_per_environment ? var.binary_authorization_allowlist_patterns : concat(
    [for k in sort(keys(local.repository_paths)) : "${local.repository_paths[k]}/**"],
    var.binary_authorization_allowlist_patterns,
  )

  # Regla por defecto (Cloud Run, que no admite reglas por clúster, y todo clúster que no siga la
  # convención). Binary Authorization exige las atestaciones de TODOS los atestadores de
  # require_attestations_by, así que "cualquiera de los atestadores de entorno" no se puede
  # expresar. Con atestadores por entorno y sin binary_authorization_attestors, la regla por
  # defecto exige el del primer entorno de la promoción (dev, qa, prod) que tenga uno: toda imagen
  # promovida lo trae. RIESGO: Cloud Run de qa y prod solo exige ese atestador (no hay reglas por
  # servicio de Cloud Run); separar Cloud Run por entorno exige binary_authorization_attestors o
  # proyectos separados.
  binauthz_default_attestors = length(var.binary_authorization_attestors) > 0 ? var.binary_authorization_attestors : (
    local.binauthz_per_environment ? [
      [for e in ["dev", "qa", "prod"] : var.binary_authorization_env_attestors[e] if contains(keys(var.binary_authorization_env_attestors), e)][0]
    ] : []
  )
  binauthz_evaluation_mode = length(local.binauthz_default_attestors) > 0 ? "REQUIRE_ATTESTATION" : "ALWAYS_DENY"

  # Clústeres de GKE por convención (ADR 0029 §4): <prefix>-<env>-<app>-gke en la región primaria
  # y <prefix>-<env>-<app>-gke-dr en la de DR (identificador <ubicación>.<clúster>). Una regla de
  # un clúster que no existe no tiene efecto.
  # Por entorno: los clústeres de todos los entornos, cada uno con el atestador de su entorno.
  # Sin atestadores por entorno: solo los de prod, con la misma evaluación que la regla por defecto.
  binauthz_rule_environments = local.binauthz_per_environment ? var.environments : [for e in var.environments : e if e == "prod"]
  binauthz_cluster_rules = merge({}, [
    for e in local.binauthz_rule_environments : merge([
      for a in var.applications : {
        "${var.primary_region}.${var.prefix}-${e}-${a}-gke" = e
        "${var.dr_region}.${var.prefix}-${e}-${a}-gke-dr"   = e
      }
    ]...)
  ]...)
  binauthz_cluster_attestors = {
    for c, e in local.binauthz_cluster_rules : c => (
      local.binauthz_per_environment
      ? distinct(concat([var.binary_authorization_env_attestors[e]], var.binary_authorization_attestors))
      : local.binauthz_default_attestors
    )
  }
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
# Cloud Run con use_default = true). La política global de Google (imágenes de sistema de GKE) se
# evalúa antes. Los dos modos (por entorno o con la lista global) están en los locals de arriba.
#
# Fuentes: "Policy" de la API v1 (una imagen de admissionWhitelistPatterns "will always be
# permitted"; la regla exige que "all the attestors listed in requireAttestationsBy" atestigüen)
# y "Key concepts" (Cloud Run solo admite la regla por defecto), Google Cloud,
# https://docs.cloud.google.com/binary-authorization/docs/reference/rest/v1/projects.policy y
# https://docs.cloud.google.com/binary-authorization/docs/key-concepts.
#
# Sin atestadores por entorno, desviación del ADR 0029 §4: las reglas de los clústeres de prod
# existen por convención de nombres pero no limitan prod al repositorio de prod (la lista es
# global); con binary_authorization_attestors exigen atestación a lo que no esté en la lista.
# VERIFICAR-EN-APPLY: que un pod de GKE y un despliegue de Cloud Run con una imagen del
# repositorio pasen y que una imagen de otro registro se rechace con
# ENFORCED_BLOCK_AND_AUDIT_LOG. Con atestadores por entorno: que una imagen con solo la
# atestación de dev se rechace en un clúster de prod y que el agente de Binary Authorization del
# proyecto pueda leer cada atestador (si está en otro proyecto necesita
# roles/binaryauthorization.attestorsVerifier allí; los atestadores no los crea esta etapa).
resource "google_binary_authorization_policy" "this" {
  project                       = local.project_id
  description                   = local.binauthz_per_environment ? "Política del proyecto: cada clúster exige la atestación de su entorno; Cloud Run, la regla por defecto (administrada por Terraform, 1-base)." : "Política del proyecto: solo imágenes de los repositorios de Artifact Registry del proyecto y de los patrones aprobados (administrada por Terraform, 1-base)."
  global_policy_evaluation_mode = "ENABLE"

  # La barra antes de ** evita que el patrón cubra otro repositorio cuyo nombre empiece igual.
  dynamic "admission_whitelist_patterns" {
    for_each = local.binauthz_allowlist
    content {
      name_pattern = admission_whitelist_patterns.value
    }
  }

  default_admission_rule {
    evaluation_mode         = local.binauthz_evaluation_mode
    enforcement_mode        = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    require_attestations_by = length(local.binauthz_default_attestors) > 0 ? local.binauthz_default_attestors : null
  }

  dynamic "cluster_admission_rules" {
    for_each = local.binauthz_cluster_attestors
    content {
      cluster                 = cluster_admission_rules.key
      evaluation_mode         = length(cluster_admission_rules.value) > 0 ? "REQUIRE_ATTESTATION" : "ALWAYS_DENY"
      enforcement_mode        = "ENFORCED_BLOCK_AND_AUDIT_LOG"
      require_attestations_by = length(cluster_admission_rules.value) > 0 ? cluster_admission_rules.value : null
    }
  }

  depends_on = [google_artifact_registry_repository.this]
}
