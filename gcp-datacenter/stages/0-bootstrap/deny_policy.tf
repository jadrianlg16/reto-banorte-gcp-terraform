# Protección del estado y de la etapa 0 (ADR 0029 §5): etiqueta <prefix>-proteccion = etapa-0
# y política de denegación del proyecto contra las nueve cuentas del pipeline.
#
# Sin carpeta, la denegación va en el proyecto y distingue lo protegido por etiqueta: las
# condiciones de una política de denegación solo reconocen funciones de etiquetas.
#
# Qué lleva la etiqueta: el bucket de estado, el llavero del estado y las nueve cuentas del
# pipeline. Las etiquetas se admiten en buckets, llaveros de KMS (no en llaves sueltas) y
# cuentas de servicio; que las llaves hereden la etiqueta de su llavero es HYPOTHESIS.
#
# Límites conocidos (la denegación no los cubre):
# - iam.serviceAccounts.createTagBinding/deleteTagBinding, cloudkms.keyRings.deleteTagBinding y
#   resourcemanager.tagValueBindings.* no se pueden negar. Por eso ninguna cuenta del pipeline
#   tiene esos permisos sobre lo protegido: ninguna tiene tagUser ni tagAdmin de proyecto, la de
#   1-base usa un rol de cuentas de servicio sin etiquetas (custom_roles.tf) y no tiene KMS sobre
#   el llavero del estado, y las de spoke usan TfNetworkTagManager, que administra claves, valores
#   y su IAM pero no liga etiquetas. Aunque una cuenta de spoke se diera tagUser sobre el valor
#   de protección, le faltaría deleteTagBinding sobre la cuenta, el bucket o el llavero (prueba
#   ningun_rol_del_pipeline_liga_etiquetas).
# - Los permisos de las políticas de denegación (iam.denypolicies.*) no se pueden negar; ninguna
#   cuenta del pipeline tiene roles/iam.denyAdmin.
# - Los permisos de objeto de Cloud Storage no se niegan: los prefijos del estado se separan con
#   condiciones de IAM (service_accounts.tf).
# Si las etiquetas no funcionan en el proyecto (HYPOTHESIS: proyecto sin organización), la
# protección queda en que ninguna cuenta tiene storage.admin sin condición, serviceAccountAdmin
# ni projectIamAdmin sin condición (ADR 0029 §5), y enable_protection_tags = false.

locals {
  protection_tags = var.enable_protection_tags ? toset(["this"]) : toset([])

  # principal://.../serviceAccounts/<correo> de las nueve cuentas.
  denied_principals = concat(
    [for k in sort(keys(local.stage_roots)) : "principal://iam.googleapis.com/projects/-/serviceAccounts/${google_service_account.stage[k].email}"],
    ["principal://iam.googleapis.com/projects/-/serviceAccounts/${google_service_account.read.email}"],
  )

  # Sobre lo que tenga la etiqueta. Formato: <servicio>.googleapis.com/<recurso>.<verbo>; todos
  # figuran en la lista de permisos admitidos en políticas de denegación.
  tagged_denied_permissions = [
    # Bucket de estado: borrarlo, su configuración, su IAM y sus etiquetas.
    "storage.googleapis.com/buckets.delete",
    "storage.googleapis.com/buckets.update",
    "storage.googleapis.com/buckets.setIamPolicy",
    "storage.googleapis.com/buckets.createTagBinding",
    "storage.googleapis.com/buckets.deleteTagBinding",
    "storage.googleapis.com/managedFolders.setIamPolicy",
    "storage.googleapis.com/objects.setIamPolicy",
    # Llavero y llave del estado: su IAM, cambiar la llave o destruir versiones.
    "cloudkms.googleapis.com/keyRings.setIamPolicy",
    "cloudkms.googleapis.com/cryptoKeys.setIamPolicy",
    "cloudkms.googleapis.com/cryptoKeys.update",
    "cloudkms.googleapis.com/cryptoKeyVersions.destroy",
    # Cuentas del pipeline: su IAM, suplantarlas, cambiarlas o borrarlas.
    "iam.googleapis.com/serviceAccounts.setIamPolicy",
    "iam.googleapis.com/serviceAccounts.actAs",
    "iam.googleapis.com/serviceAccounts.getAccessToken",
    "iam.googleapis.com/serviceAccounts.getOpenIdToken",
    "iam.googleapis.com/serviceAccounts.implicitDelegation",
    "iam.googleapis.com/serviceAccounts.signBlob",
    "iam.googleapis.com/serviceAccounts.signJwt",
    "iam.googleapis.com/serviceAccounts.update",
    "iam.googleapis.com/serviceAccounts.delete",
    "iam.googleapis.com/serviceAccounts.disable",
  ]

  # Valores de los secretos (ADR 0015): ninguna cuenta del pipeline los lee, salvo tf-net, que lee
  # la llave compartida de la VPN real en el hub (stages/2-networks/vpn.tf). 1-base administra el
  # IAM de los secretos (custom_roles.tf) y podría darse secretAccessor: esta regla se lo niega.
  # Todo en la lista de permisos admitidos en políticas de denegación
  # (https://cloud.google.com/iam/docs/deny-permissions-support).
  secret_value_denied_principals = concat(
    [for k in sort(keys(local.stage_roots)) : "principal://iam.googleapis.com/projects/-/serviceAccounts/${google_service_account.stage[k].email}" if k != "2-networks"],
    ["principal://iam.googleapis.com/projects/-/serviceAccounts/${google_service_account.read.email}"],
  )
  secret_value_denied_permissions = [
    "secretmanager.googleapis.com/versions.access",
  ]

  # En todo el proyecto: WIF, roles personalizados, llaves de cuentas y borrar el proyecto.
  # Ninguna cuenta del pipeline los necesita.
  untagged_denied_permissions = [
    "iam.googleapis.com/workloadIdentityPools.create",
    "iam.googleapis.com/workloadIdentityPools.update",
    "iam.googleapis.com/workloadIdentityPools.delete",
    "iam.googleapis.com/workloadIdentityPoolProviders.create",
    "iam.googleapis.com/workloadIdentityPoolProviders.update",
    "iam.googleapis.com/workloadIdentityPoolProviders.delete",
    "iam.googleapis.com/roles.create",
    "iam.googleapis.com/roles.update",
    "iam.googleapis.com/roles.delete",
    "iam.googleapis.com/serviceAccountKeys.create",
    "cloudresourcemanager.googleapis.com/projects.delete",
  ]
}

# --- Etiqueta de protección -----------------------------------------------------------------

# VERIFICAR-EN-APPLY: que una clave de etiqueta con padre projects/<id> se cree en un proyecto sin
# organización y que la persona de la etapa 0 pueda ligarla (tagUser sobre el valor y
# createTagBinding sobre cada recurso).
resource "google_tags_tag_key" "protection" {
  for_each = local.protection_tags

  parent      = "projects/${var.project_id}"
  short_name  = "${var.prefix}-proteccion"
  description = "Recursos de la etapa 0 que las cuentas del pipeline no pueden cambiar (ADR 0029 §5)."

  depends_on = [google_project_service.this]
}

resource "google_tags_tag_value" "stage0" {
  for_each = local.protection_tags

  parent      = google_tags_tag_key.protection[each.key].id
  short_name  = "etapa-0"
  description = "Bucket y llavero del estado y cuentas del pipeline."
}

# Bucket y llavero: recursos con ubicación (enlace con location).
# VERIFICAR-EN-APPLY: que el bucket y el llavero del estado acepten la etiqueta y que la llave
# del estado la herede de su llavero (gcloud resource-manager tags bindings list --effective).
resource "google_tags_location_tag_binding" "state_bucket" {
  for_each = local.protection_tags

  parent    = "//storage.googleapis.com/projects/_/buckets/${google_storage_bucket.state.name}"
  tag_value = google_tags_tag_value.stage0[each.key].id
  location  = lower(var.state_bucket_location)
}

resource "google_tags_location_tag_binding" "state_keyring" {
  for_each = local.protection_tags

  parent    = "//cloudkms.googleapis.com/${module.state_kms.keyring_id}"
  tag_value = google_tags_tag_value.stage0[each.key].id
  location  = local.state_kms_location
}

# Cuentas del pipeline: recurso global. El nombre completo usa el ID único de la cuenta.
# VERIFICAR-EN-APPLY: el formato //iam.googleapis.com/projects/<id>/serviceAccounts/<id único>
# del enlace.
resource "google_tags_tag_binding" "pipeline_accounts" {
  for_each = var.enable_protection_tags ? merge(
    { for k in keys(local.stage_roots) : k => google_service_account.stage[k].unique_id },
    { read = google_service_account.read.unique_id },
  ) : {}

  parent    = "//iam.googleapis.com/projects/${var.project_id}/serviceAccounts/${each.value}"
  tag_value = google_tags_tag_value.stage0["this"].id
}

# --- Política de denegación -----------------------------------------------------------------

# Una denegación se impone sobre cualquier permiso de una política de permisos, venga de donde
# venga (incluso de un rol que una cuenta se dé a sí misma).
# VERIFICAR-EN-APPLY: que la persona de la etapa 0 tenga roles/iam.denyAdmin en el proyecto (el
# rol owner no lo incluye), que la API de denegación acepte el proyecto como padre y que, con la
# etiqueta, tf-wl-dev reciba un rechazo al intentar getIamPolicy/setIamPolicy sobre tf-base.
resource "google_iam_deny_policy" "pipeline" {
  for_each = var.enable_deny_policy ? toset(["this"]) : toset([])

  parent       = urlencode("cloudresourcemanager.googleapis.com/projects/${var.project_id}")
  name         = "${var.prefix}-${local.environment}-sec-deny-pipeline"
  display_name = "Protege el estado y la etapa 0 de las cuentas del pipeline"

  dynamic "rules" {
    for_each = google_tags_tag_key.protection
    content {
      description = "Las cuentas del pipeline no pueden cambiar, borrar ni suplantar lo que tenga la etiqueta etapa-0."
      deny_rule {
        denied_principals  = local.denied_principals
        denied_permissions = local.tagged_denied_permissions
        denial_condition {
          title       = "etiqueta-etapa-0"
          expression  = "resource.matchTag('${rules.value.namespaced_name}', 'etapa-0')"
          description = "Solo recursos con <prefix>-proteccion = etapa-0."
        }
      }
    }
  }

  rules {
    description = "Las cuentas del pipeline no pueden cambiar WIF, roles personalizados, crear llaves de cuentas ni borrar el proyecto."
    deny_rule {
      denied_principals  = local.denied_principals
      denied_permissions = local.untagged_denied_permissions
    }
  }

  rules {
    description = "Las cuentas del pipeline, salvo la del hub de red, no leen valores de secretos."
    deny_rule {
      denied_principals  = local.secret_value_denied_principals
      denied_permissions = local.secret_value_denied_permissions
    }
  }

  depends_on = [
    google_tags_location_tag_binding.state_bucket,
    google_tags_location_tag_binding.state_keyring,
    google_tags_tag_binding.pipeline_accounts,
  ]
}
