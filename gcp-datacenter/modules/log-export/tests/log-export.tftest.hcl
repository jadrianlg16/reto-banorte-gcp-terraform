mock_provider "google" {
  mock_data "google_storage_project_service_account" {
    defaults = {
      email_address = "service-000000000000@gs-project-accounts.iam.gserviceaccount.com"
    }
  }
}

variables {
  project_id     = "bnt-common-logging"
  prefix         = "bnt"
  environment    = "common"
  location       = "us-central1"
  kms_key        = "projects/example-security/locations/us-central1/keyRings/example-ring/cryptoKeys/example-key"
  retention_days = 365
  parent         = "projects/bnt-common-logging"
  labels = {
    env         = "common"
    app         = "logging"
    owner       = "example-team"
    cost_center = "example-000"
    managed_by  = "terraform"
  }
}

run "bucket_con_exigencias_y_sink_de_proyecto" {
  command = plan

  assert {
    condition     = google_storage_bucket.this.name == "bnt-common-ops-audit-logs"
    error_message = "El bucket debe llamarse <prefix>-<environment>-ops-<name>."
  }
  assert {
    condition     = google_storage_bucket.this.retention_policy[0].retention_period == 365 * 86400
    error_message = "La retención debe ser retention_days en segundos."
  }
  assert {
    condition     = google_storage_bucket.this.retention_policy[0].is_locked == false
    error_message = "Por defecto la retención no queda bloqueada."
  }
  assert {
    condition     = google_storage_bucket.this.encryption[0].default_kms_key_name == var.kms_key
    error_message = "El bucket debe cifrarse con la llave CMEK."
  }
  assert {
    condition     = google_storage_bucket.this.uniform_bucket_level_access == true && google_storage_bucket.this.public_access_prevention == "enforced"
    error_message = "Acceso uniforme y prevención de acceso público son obligatorios."
  }
  assert {
    condition     = google_storage_bucket.this.versioning[0].enabled == true && google_storage_bucket.this.force_destroy == false
    error_message = "Versionado activo y sin borrado forzado."
  }
  assert {
    condition     = google_storage_bucket.this.labels == var.labels
    error_message = "El bucket debe llevar las etiquetas."
  }
  assert {
    condition     = google_kms_crypto_key_iam_member.storage_agent["this"].member == "serviceAccount:service-000000000000@gs-project-accounts.iam.gserviceaccount.com"
    error_message = "El agente de Cloud Storage debe recibir permiso sobre la llave."
  }
  assert {
    condition = alltrue([
      google_logging_project_sink.this["this"].name == "bnt-common-ops-audit-logs-sink",
      google_logging_project_sink.this["this"].project == "bnt-common-logging",
      google_logging_project_sink.this["this"].unique_writer_identity == true,
      google_logging_project_sink.this["this"].destination == "storage.googleapis.com/bnt-common-ops-audit-logs",
    ])
    error_message = "El sink de proyecto debe tener identidad propia y apuntar al bucket."
  }
  assert {
    condition     = length(google_logging_project_sink.this["this"].exclusions) == 0
    error_message = "Sin exclusions, el sink no lleva exclusiones."
  }
  assert {
    condition     = google_storage_bucket_iam_member.writer["this"].role == "roles/storage.objectCreator"
    error_message = "La identidad del sink solo crea objetos."
  }
}

run "bloqueo_por_variable" {
  command = plan

  variables {
    retention_locked = true
  }

  assert {
    condition     = google_storage_bucket.this.retention_policy[0].is_locked == true
    error_message = "retention_locked debe bloquear la retención."
  }
}

run "sufijo_y_exclusiones" {
  command = plan

  variables {
    name_suffix = "x7k2"
    exclusions = [
      {
        name        = "bucket-de-logs"
        description = "Acceso a datos del bucket de logs."
        filter      = "logName:\"cloudaudit.googleapis.com%2Fdata_access\" AND resource.labels.bucket_name=\"bnt-common-ops-audit-logs-x7k2\""
      },
      {
        name     = "apagada"
        filter   = "severity<WARNING"
        disabled = true
      },
    ]
  }

  assert {
    condition     = google_storage_bucket.this.name == "bnt-common-ops-audit-logs-x7k2"
    error_message = "El sufijo se agrega al nombre del bucket."
  }
  assert {
    condition = alltrue([
      length(google_logging_project_sink.this["this"].exclusions) == 2,
      google_logging_project_sink.this["this"].exclusions[0].name == "bucket-de-logs",
      google_logging_project_sink.this["this"].exclusions[0].disabled == false,
      google_logging_project_sink.this["this"].exclusions[1].disabled == true,
    ])
    error_message = "Las exclusiones pasan al sink en orden, con disabled = false por defecto."
  }
}

run "solo_bucket" {
  command = plan

  variables {
    parent = null
  }

  assert {
    condition     = length(google_logging_project_sink.this) + length(google_storage_bucket_iam_member.writer) == 0
    error_message = "Sin parent no se crean sink ni permiso de escritura."
  }
  assert {
    condition     = output.writer_identity == null && output.sink_name == null && output.destination == "storage.googleapis.com/bnt-common-ops-audit-logs"
    error_message = "Sin parent, writer_identity y sink_name son null y destination sirve para otro sink."
  }
}

run "rechaza_padre_de_organizacion" {
  command = plan

  variables {
    parent = "organizations/000000000000"
  }

  expect_failures = [var.parent]
}

run "rechaza_exclusiones_repetidas" {
  command = plan

  variables {
    exclusions = [
      { name = "x", filter = "severity<WARNING" },
      { name = "x", filter = "severity<ERROR" },
    ]
  }

  expect_failures = [var.exclusions]
}

run "rechaza_retencion_corta" {
  command = plan

  variables {
    retention_days = 7
  }

  expect_failures = [var.retention_days]
}

run "rechaza_llave_mal_formada" {
  command = plan

  variables {
    kms_key = "example-key"
  }

  expect_failures = [var.kms_key]
}

run "rechaza_padre_mal_formado" {
  command = plan

  variables {
    parent = "billingAccounts/000000-000000-000000"
  }

  expect_failures = [var.parent]
}

run "agente_consultado_por_numero" {
  command = plan

  variables {
    project_number = "123456789012"
  }

  assert {
    condition     = data.google_storage_project_service_account.this.project == "123456789012"
    error_message = "Con project_number, el agente de Cloud Storage se consulta con el número del proyecto."
  }
}

run "rechaza_numero_de_proyecto_mal_formado" {
  command = plan

  variables {
    project_number = "bnt-common-logging"
  }

  expect_failures = [var.project_number]
}

run "rechaza_etiquetas_incompletas" {
  command = plan

  variables {
    labels = { env = "common", managed_by = "terraform" }
  }

  expect_failures = [var.labels]
}
