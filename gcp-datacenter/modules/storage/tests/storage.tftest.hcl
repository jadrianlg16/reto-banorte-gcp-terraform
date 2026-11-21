mock_provider "google" {}

variables {
  project_id  = "example-prod-app"
  prefix      = "bnt"
  environment = "prod"
  name        = "assets"
  location    = "us-central1"
  kms_key     = "projects/example-common-security/locations/us-central1/keyRings/bnt-prod-sec-usc1/cryptoKeys/storage"
  labels = {
    env         = "prod"
    app         = "app"
    owner       = "example-team"
    cost_center = "example-cc"
    managed_by  = "terraform"
  }
}

run "regional_cumple_exige" {
  command = plan

  assert {
    condition     = google_storage_bucket.this.name == "bnt-prod-data-assets-usc1"
    error_message = "El nombre no sigue <prefix>-<env>-data-<recurso>-<región>."
  }
  assert {
    condition     = google_storage_bucket.this.encryption[0].default_kms_key_name == var.kms_key
    error_message = "El bucket debe usar CMEK."
  }
  assert {
    condition     = google_storage_bucket.this.versioning[0].enabled
    error_message = "El versionado debe estar activo."
  }
  assert {
    condition     = length(google_storage_bucket.this.lifecycle_rule) == 2
    error_message = "Deben aplicarse las reglas de ciclo de vida por defecto."
  }
  assert {
    condition     = google_storage_bucket.this.uniform_bucket_level_access
    error_message = "El acceso uniforme debe estar activo."
  }
  assert {
    condition     = google_storage_bucket.this.public_access_prevention == "enforced"
    error_message = "El acceso público debe estar impedido."
  }
  assert {
    condition     = google_storage_bucket.this.force_destroy == false
    error_message = "force_destroy debe ser false por defecto."
  }
  assert {
    condition     = google_storage_bucket.this.location == "US-CENTRAL1"
    error_message = "La ubicación debe ser la región indicada."
  }
  assert {
    condition     = length(google_storage_bucket.this.custom_placement_config) == 0
    error_message = "Un bucket regional no lleva doble región."
  }
  assert {
    condition     = google_storage_bucket.this.labels == var.labels
    error_message = "Las etiquetas deben aplicarse."
  }
}

run "doble_region_con_turbo" {
  command = plan

  variables {
    name        = "docs"
    name_suffix = "-x1"
    location    = "us"
    dual_region = { regions = ["us-central1", "us-east4"] }
    kms_key     = "projects/example-common-security/locations/us/keyRings/bnt-prod-sec-us/cryptoKeys/storage"
    retention_policy = {
      retention_period = 2592000
    }
  }

  assert {
    condition     = google_storage_bucket.this.name == "bnt-prod-data-docs-usc1-use4-x1"
    error_message = "El nombre de doble región lleva los códigos de ambas regiones y el sufijo."
  }
  assert {
    condition     = google_storage_bucket.this.location == "US"
    error_message = "Un bucket de doble región se ubica en la multirregión."
  }
  assert {
    condition     = toset(google_storage_bucket.this.custom_placement_config[0].data_locations) == toset(["US-CENTRAL1", "US-EAST4"])
    error_message = "La doble región debe tener las dos regiones."
  }
  assert {
    condition     = google_storage_bucket.this.rpo == "ASYNC_TURBO"
    error_message = "Turbo replication debe estar activo por defecto."
  }
  assert {
    condition     = google_storage_bucket.this.retention_policy[0].retention_period == 2592000 && google_storage_bucket.this.retention_policy[0].is_locked == false
    error_message = "La política de retención debe aplicarse sin bloquear por defecto."
  }
}

run "rechaza_llave_de_otra_ubicacion" {
  command = plan
  variables {
    location    = "us"
    dual_region = { regions = ["us-central1", "us-east4"] }
  }
  expect_failures = [var.kms_key]
}

run "rechaza_doble_region_en_ubicacion_regional" {
  command = plan
  variables {
    dual_region = { regions = ["us-central1", "us-east4"] }
  }
  expect_failures = [var.location]
}

run "rechaza_doble_region_con_una_region" {
  command = plan
  variables {
    location    = "us"
    dual_region = { regions = ["us-central1", "us-central1"] }
    kms_key     = "projects/example-common-security/locations/us/keyRings/bnt-prod-sec-us/cryptoKeys/storage"
  }
  expect_failures = [var.dual_region]
}

run "rechaza_force_destroy_en_prod" {
  command = plan
  variables {
    force_destroy = true
  }
  expect_failures = [var.force_destroy]
}

run "rechaza_sin_reglas_de_ciclo_de_vida" {
  command = plan
  variables {
    lifecycle_rules = []
  }
  expect_failures = [var.lifecycle_rules]
}

run "rechaza_set_storage_class_sin_clase" {
  command = plan
  variables {
    lifecycle_rules = [{ action = { type = "SetStorageClass" }, condition = { age = 30 } }]
  }
  expect_failures = [var.lifecycle_rules]
}

run "rechaza_etiquetas_sin_managed_by_terraform" {
  command = plan
  variables {
    labels = {
      env         = "prod"
      app         = "app"
      owner       = "example-team"
      cost_center = "example-cc"
      managed_by  = "manual"
    }
  }
  expect_failures = [var.labels]
}
