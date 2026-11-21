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
  parent         = "organizations/000000000000"
  labels = {
    env         = "common"
    app         = "logging"
    owner       = "example-team"
    cost_center = "example-000"
    managed_by  = "terraform"
  }
}

run "bucket_con_exigencias_y_sink_de_organizacion" {
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
      google_logging_organization_sink.this["this"].name == "bnt-common-ops-audit-logs-sink",
      google_logging_organization_sink.this["this"].org_id == "000000000000",
      google_logging_organization_sink.this["this"].include_children == true,
      google_logging_organization_sink.this["this"].destination == "storage.googleapis.com/bnt-common-ops-audit-logs",
    ])
    error_message = "El sink de organización debe ser agregado y apuntar al bucket."
  }
  assert {
    condition     = length(google_logging_folder_sink.this) == 0 && length(google_logging_project_sink.this) == 0
    error_message = "Solo se crea el sink del tipo de padre."
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

run "sink_de_carpeta" {
  command = plan

  variables {
    parent      = "folders/111111111111"
    name_suffix = "x7k2"
  }

  assert {
    condition     = google_logging_folder_sink.this["this"].folder == "folders/111111111111" && length(google_logging_organization_sink.this) == 0
    error_message = "Con una carpeta como padre se crea el sink de carpeta."
  }
  assert {
    condition     = google_storage_bucket.this.name == "bnt-common-ops-audit-logs-x7k2"
    error_message = "El sufijo se agrega al nombre del bucket."
  }
}

run "sink_de_proyecto" {
  command = plan

  variables {
    parent = "projects/bnt-prod-app"
  }

  assert {
    condition     = google_logging_project_sink.this["this"].project == "bnt-prod-app" && google_logging_project_sink.this["this"].unique_writer_identity == true
    error_message = "Con un proyecto como padre se crea el sink de proyecto con identidad propia."
  }
}

run "solo_bucket" {
  command = plan

  variables {
    parent = null
  }

  assert {
    condition = (
      length(google_logging_organization_sink.this) + length(google_logging_folder_sink.this) +
      length(google_logging_project_sink.this) + length(google_storage_bucket_iam_member.writer) == 0
    )
    error_message = "Sin parent no se crean sink ni permiso de escritura."
  }
  assert {
    condition     = output.writer_identity == null && output.destination == "storage.googleapis.com/bnt-common-ops-audit-logs"
    error_message = "Sin parent, writer_identity es null y destination sirve para otro sink."
  }
}

# La carpeta padre se crea en el mismo plan: el for_each de los sinks debe seguir conocido.
run "padre_desconocido_en_el_plan" {
  command = plan

  module {
    source = "./tests/setup/unknown_parent"
  }

  assert {
    condition     = output.sink_name == "bnt-prod-ops-data-access-logs-sink"
    error_message = "Con una carpeta creada en el mismo plan se crea igual el sink de carpeta."
  }
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

run "rechaza_etiquetas_incompletas" {
  command = plan

  variables {
    labels = { env = "common", managed_by = "terraform" }
  }

  expect_failures = [var.labels]
}
