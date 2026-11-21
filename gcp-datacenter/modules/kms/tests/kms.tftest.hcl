# Pruebas unitarias sin GCP: proveedor simulado y solo plan.
# prevent_destroy no estorba porque con command = plan nada llega al estado y no hay destroy
# al final; una prueba con command = apply fallaría al limpiar.

mock_provider "google" {}

variables {
  project_id  = "example-security-project"
  prefix      = "bnt"
  environment = "prod"
  location    = "us-central1"
  keys = {
    sql     = {}
    storage = { encrypter_decrypters = ["serviceAccount:example-sa@example-project.iam.gserviceaccount.com"] }
  }
  labels = {
    env         = "prod"
    app         = "security"
    owner       = "example-team"
    cost_center = "cc-000"
    managed_by  = "terraform"
  }
}

run "nombres_y_exigencias" {
  command = plan

  assert {
    condition     = google_kms_key_ring.this.name == "bnt-prod-sec-keyring-usc1"
    error_message = "El llavero no sigue <prefix>-<env>-sec-keyring-<código corto>."
  }
  assert {
    condition     = google_kms_crypto_key.this["sql"].name == "bnt-prod-sec-sql"
    error_message = "La llave no sigue <prefix>-<env>-sec-<uso>."
  }
  assert {
    condition     = alltrue([for k in google_kms_crypto_key.this : k.rotation_period == "7776000s"])
    error_message = "Las llaves deben rotar cada 90 días por defecto."
  }
  assert {
    condition     = alltrue([for k in google_kms_crypto_key.this : k.purpose == "ENCRYPT_DECRYPT"])
    error_message = "Las llaves deben ser simétricas (las únicas que rotan)."
  }
  assert {
    condition = alltrue([
      for k in google_kms_crypto_key.this : alltrue([
        for l in ["env", "app", "owner", "cost_center", "managed_by"] : contains(keys(k.labels), l)
      ])
    ])
    error_message = "Las llaves deben llevar las cinco etiquetas obligatorias."
  }
  assert {
    condition     = google_kms_crypto_key_iam_member.encrypter_decrypter["storage|serviceAccount:example-sa@example-project.iam.gserviceaccount.com"].role == "roles/cloudkms.cryptoKeyEncrypterDecrypter"
    error_message = "Falta el permiso de cifrado sobre la llave storage."
  }
  assert {
    condition     = length(google_kms_crypto_key_iam_member.encrypter_decrypter) == 1
    error_message = "Solo debe haber un permiso de cifrado."
  }
}

run "multirregion_us" {
  command = plan

  variables {
    environment = "dev"
    location    = "us"
    keys        = { storage = {} }
  }

  assert {
    condition     = google_kms_key_ring.this.name == "bnt-dev-sec-keyring-us"
    error_message = "El llavero multirregional debe terminar en -us."
  }
}

run "rotacion_menor_valida" {
  command = plan

  variables {
    rotation_period = "2592000s"
  }

  assert {
    condition     = google_kms_crypto_key.this["sql"].rotation_period == "2592000s"
    error_message = "La rotación de la variable no se aplicó."
  }
}

run "rechaza_rotacion_mayor_a_90_dias" {
  command = plan

  variables {
    rotation_period = "7776001s"
  }

  expect_failures = [var.rotation_period]
}

run "rechaza_rotacion_sin_formato" {
  command = plan

  variables {
    rotation_period = "90d"
  }

  expect_failures = [var.rotation_period]
}

run "rechaza_proteccion_desconocida" {
  command = plan

  variables {
    keys = { sql = { protection_level = "EXTERNAL" } }
  }

  expect_failures = [var.keys]
}

run "rechaza_miembro_user" {
  command = plan

  variables {
    keys = { sql = { encrypter_decrypters = ["user:alguien@example.com"] } }
  }

  expect_failures = [var.keys]
}

run "rechaza_ubicacion_sin_codigo" {
  command = plan

  variables {
    location = "europe-west1"
  }

  expect_failures = [var.location]
}

run "rechaza_etiquetas_incompletas" {
  command = plan

  variables {
    labels = { env = "prod", managed_by = "terraform" }
  }

  expect_failures = [var.labels]
}
