locals {
  location = lower(var.location)

  # Código de ubicación del nombre (§4.2): el código corto de la región, el de las dos regiones
  # de una doble región, o la multirregión tal cual (us, eu, asia).
  location_code = (
    var.dual_region != null ? join("-", [for r in var.dual_region.regions : var.region_short_codes[lower(r)]]) :
    lookup(var.region_short_codes, local.location, local.location)
  )

  bucket_name = "${var.prefix}-${var.environment}-data-${var.name}-${local.location_code}${var.name_suffix}"
}

resource "google_storage_bucket" "this" {
  # checkov:skip=CKV_GCP_62: el registro de uso heredado de Cloud Storage no se usa; el acceso a objetos queda en los registros de auditoría de acceso a datos (etapa 1) y en el sink agregado hacia el bucket de logs.
  project       = var.project_id
  name          = local.bucket_name
  location      = upper(var.location)
  storage_class = var.storage_class
  labels        = var.labels
  force_destroy = var.force_destroy

  # Fijos: acceso uniforme, sin acceso público y versionado.
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  # CMEK obligatorio. Para doble región la llave vive en la multirregión (anillo "us" de la etapa 2).
  encryption {
    default_kms_key_name = var.kms_key
  }

  # Doble región configurable con turbo replication (RPO de 15 minutos para objetos nuevos).
  dynamic "custom_placement_config" {
    for_each = var.dual_region == null ? [] : [var.dual_region]
    content {
      data_locations = [for r in custom_placement_config.value.regions : upper(r)]
    }
  }
  rpo = var.dual_region == null ? null : (var.dual_region.turbo_replication ? "ASYNC_TURBO" : "DEFAULT")

  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = lifecycle_rule.value.action.storage_class
      }
      condition {
        age                        = lifecycle_rule.value.condition.age
        created_before             = lifecycle_rule.value.condition.created_before
        with_state                 = lifecycle_rule.value.condition.with_state
        matches_storage_class      = lifecycle_rule.value.condition.matches_storage_class
        matches_prefix             = lifecycle_rule.value.condition.matches_prefix
        matches_suffix             = lifecycle_rule.value.condition.matches_suffix
        num_newer_versions         = lifecycle_rule.value.condition.num_newer_versions
        days_since_noncurrent_time = lifecycle_rule.value.condition.days_since_noncurrent_time
        noncurrent_time_before     = lifecycle_rule.value.condition.noncurrent_time_before
        days_since_custom_time     = lifecycle_rule.value.condition.days_since_custom_time
      }
    }
  }

  dynamic "retention_policy" {
    for_each = var.retention_policy == null ? [] : [var.retention_policy]
    content {
      retention_period = retention_policy.value.retention_period
      is_locked        = retention_policy.value.is_locked
    }
  }

  soft_delete_policy {
    retention_duration_seconds = var.soft_delete_retention_seconds
  }

  lifecycle {
    precondition {
      condition     = length(local.bucket_name) <= 63 && !strcontains(local.bucket_name, "google")
      error_message = "El nombre del bucket debe tener como máximo 63 caracteres y no contener \"google\"."
    }
  }

  # VERIFICAR-EN-APPLY: el agente de servicio de Cloud Storage del proyecto tiene
  # roles/cloudkms.cryptoKeyEncrypterDecrypter sobre kms_key (lo otorga 1-base, kms.tf); para doble
  # región, que la llave de la multirregión "us" sirva para un bucket con custom_placement_config.
  # VERIFICAR-EN-APPLY: la restricción gcp.resourceLocations admite la doble región (§12, punto 3).
}
