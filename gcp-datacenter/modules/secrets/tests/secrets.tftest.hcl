# Pruebas unitarias sin GCP: proveedor simulado y solo plan.

mock_provider "google" {}

variables {
  project_id  = "example-security-project"
  prefix      = "bnt"
  environment = "prod"
  names       = ["api-token", "partner-cert"]
  kms_keys = {
    "us-central1" = "projects/example-security-project/locations/us-central1/keyRings/bnt-prod-sec-keyring-usc1/cryptoKeys/bnt-prod-sec-secrets"
    "us-east4"    = "projects/example-security-project/locations/us-east4/keyRings/bnt-prod-sec-keyring-use4/cryptoKeys/bnt-prod-sec-secrets"
  }
  accessors = [
    "serviceAccount:example-sa@example-project.iam.gserviceaccount.com",
    "group:example-group@example.com",
  ]
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
    condition     = google_secret_manager_secret.this["api-token"].secret_id == "bnt-prod-sec-api-token"
    error_message = "El secreto no sigue <prefix>-<env>-sec-<nombre>."
  }
  assert {
    condition = alltrue([
      for s in google_secret_manager_secret.this : length(s.replication[0].user_managed[0].replicas) == 2
    ])
    error_message = "Debe haber una réplica por región de kms_keys."
  }
  assert {
    condition = alltrue(flatten([
      for s in google_secret_manager_secret.this : [
        for r in s.replication[0].user_managed[0].replicas :
        r.customer_managed_encryption[0].kms_key_name == var.kms_keys[r.location]
      ]
    ]))
    error_message = "Cada réplica debe cifrarse con la llave de su región (CMEK)."
  }
  assert {
    condition     = alltrue([for s in google_secret_manager_secret.this : length(s.replication[0].auto) == 0])
    error_message = "No se permite replicación automática: la llave debe ser por región."
  }
  assert {
    condition = alltrue([
      for s in google_secret_manager_secret.this : alltrue([
        for l in ["env", "app", "owner", "cost_center", "managed_by"] : contains(keys(s.labels), l)
      ])
    ])
    error_message = "Los secretos deben llevar las cinco etiquetas obligatorias."
  }
  assert {
    condition     = alltrue([for s in google_secret_manager_secret.this : s.deletion_protection])
    error_message = "La protección contra borrado debe estar activa por defecto."
  }
  assert {
    condition     = length(google_secret_manager_secret_iam_member.accessor) == 4
    error_message = "Debe haber un permiso por secreto y miembro (2 x 2)."
  }
  assert {
    condition     = alltrue([for b in google_secret_manager_secret_iam_member.accessor : b.role == "roles/secretmanager.secretAccessor"])
    error_message = "Los accesores solo reciben secretAccessor."
  }
}

run "sin_accesores" {
  command = plan

  variables {
    accessors = []
  }

  assert {
    condition     = length(google_secret_manager_secret_iam_member.accessor) == 0
    error_message = "Sin accesores no debe haber permisos."
  }
}

run "rechaza_miembro_user" {
  command = plan

  variables {
    accessors = ["user:alguien@example.com"]
  }

  expect_failures = [var.accessors]
}

run "rechaza_all_users" {
  command = plan

  variables {
    accessors = ["allUsers"]
  }

  expect_failures = [var.accessors]
}

run "rechaza_sin_cmek" {
  command = plan

  variables {
    kms_keys = {}
  }

  expect_failures = [var.kms_keys]
}

run "rechaza_llave_de_otra_region" {
  command = plan

  variables {
    kms_keys = {
      "us-east4" = "projects/example-security-project/locations/us-central1/keyRings/bnt-prod-sec-keyring-usc1/cryptoKeys/bnt-prod-sec-secrets"
    }
  }

  expect_failures = [var.kms_keys]
}

run "rechaza_multirregion" {
  command = plan

  variables {
    kms_keys = {
      "us" = "projects/example-security-project/locations/us/keyRings/bnt-prod-sec-keyring-us/cryptoKeys/bnt-prod-sec-secrets"
    }
  }

  expect_failures = [var.kms_keys]
}

run "rechaza_nombre_invalido" {
  command = plan

  variables {
    names = ["Api_Token"]
  }

  expect_failures = [var.names]
}
