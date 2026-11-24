mock_provider "google" {}

variables {
  bindings = [
    {
      scope    = "organization"
      resource = "organizations/000000000000"
      role     = "roles/iam.securityReviewer"
      member   = "group:example-auditors@example.com"
    },
    {
      scope    = "project"
      resource = "example-project-id"
      role     = "roles/logging.viewer"
      member   = "serviceAccount:example-sa@example-project-id.iam.gserviceaccount.com"
    },
    {
      key      = "storage-admin-dev"
      scope    = "project"
      resource = "example-project-id"
      role     = "roles/storage.admin"
      member   = "serviceAccount:example-sa@example-project-id.iam.gserviceaccount.com"
      condition = {
        title      = "solo-buckets-dev"
        expression = "resource.name.startsWith(\"projects/_/buckets/example-dev-\")"
      }
    },
    {
      scope    = "service_account"
      resource = "projects/example-project-id/serviceAccounts/example-sa@example-project-id.iam.gserviceaccount.com"
      role     = "roles/iam.workloadIdentityUser"
      member   = "principalSet://iam.googleapis.com/projects/000000000000/locations/global/workloadIdentityPools/example-pool/attribute.repository/example-org/example-repo"
    },
    {
      key      = "state-writer"
      scope    = "storage_bucket"
      resource = "example-state-bucket"
      role     = "roles/storage.objectAdmin"
      member   = "serviceAccount:example-sa@example-project-id.iam.gserviceaccount.com"
      condition = {
        title      = "solo-prefijo"
        expression = "resource.name.startsWith(\"projects/_/buckets/example-state-bucket/objects/1-org/\")"
      }
    },
    {
      scope    = "kms_key_ring"
      resource = "projects/example-project-id/locations/us-central1/keyRings/example-ring"
      role     = "roles/cloudkms.viewer"
      member   = "group:example-auditors@example.com"
    },
    {
      scope    = "kms_crypto_key"
      resource = "projects/example-project-id/locations/us-central1/keyRings/example-ring/cryptoKeys/example-key"
      role     = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
      member   = "serviceAccount:example-sa@example-project-id.iam.gserviceaccount.com"
    },
    {
      scope    = "secret"
      resource = "projects/example-project-id/secrets/example-secret"
      role     = "roles/secretmanager.secretAccessor"
      member   = "serviceAccount:example-sa@example-project-id.iam.gserviceaccount.com"
    },
    {
      scope    = "subnetwork"
      resource = "projects/example-host-project/regions/us-central1/subnetworks/example-subnet"
      role     = "roles/compute.networkUser"
      member   = "serviceAccount:example-sa@example-project-id.iam.gserviceaccount.com"
    },
  ]
}

run "una_asignacion_aditiva_por_scope" {
  command = plan

  assert {
    condition = alltrue([
      length(google_organization_iam_member.this) == 1,
      length(google_project_iam_member.this) == 2,
      length(google_service_account_iam_member.this) == 1,
      length(google_storage_bucket_iam_member.this) == 1,
      length(google_kms_key_ring_iam_member.this) == 1,
      length(google_kms_crypto_key_iam_member.this) == 1,
      length(google_secret_manager_secret_iam_member.this) == 1,
      length(google_compute_subnetwork_iam_member.this) == 1,
    ])
    error_message = "Cada asignación debe ir al recurso *_iam_member de su scope."
  }
  assert {
    condition     = google_organization_iam_member.this["organization|organizations/000000000000|roles/iam.securityReviewer|group:example-auditors@example.com"].org_id == "000000000000"
    error_message = "La llave por defecto es scope|resource|role|member y org_id va sin prefijo."
  }
  assert {
    condition     = google_storage_bucket_iam_member.this["state-writer"].condition[0].title == "solo-prefijo"
    error_message = "La llave explícita se usa y la condición se pasa al recurso."
  }
  assert {
    condition     = google_project_iam_member.this["storage-admin-dev"].condition[0].expression == "resource.name.startsWith(\"projects/_/buckets/example-dev-\")"
    error_message = "Un rol de proyecto condicionado (storage.admin por prefijo del entorno) lleva su condición."
  }
  assert {
    condition     = length(google_project_iam_member.this["project|example-project-id|roles/logging.viewer|serviceAccount:example-sa@example-project-id.iam.gserviceaccount.com"].condition) == 0
    error_message = "Sin condición, el recurso no lleva bloque condition."
  }
  assert {
    condition = alltrue([
      output.conditions["state-writer"].expression == google_storage_bucket_iam_member.this["state-writer"].condition[0].expression,
      output.conditions["project|example-project-id|roles/logging.viewer|serviceAccount:example-sa@example-project-id.iam.gserviceaccount.com"] == null,
    ])
    error_message = "La salida conditions debe reflejar la condición que lleva cada recurso."
  }
  assert {
    condition = alltrue([for s in google_compute_subnetwork_iam_member.this : (
      s.project == "example-host-project" && s.region == "us-central1" && s.subnetwork == "example-subnet"
    )])
    error_message = "La subred se separa en proyecto, región y nombre."
  }
  assert {
    condition     = length(output.members) == 3
    error_message = "members lista cada miembro una sola vez."
  }
}

run "rechaza_user" {
  command = plan

  variables {
    bindings = [{
      scope    = "project"
      resource = "example-project-id"
      role     = "roles/viewer"
      member   = "user:someone@example.com"
    }]
  }

  expect_failures = [var.bindings]
}

run "rechaza_user_en_mayusculas" {
  command = plan

  variables {
    bindings = [{
      scope    = "project"
      resource = "example-project-id"
      role     = "roles/viewer"
      member   = "User:someone@example.com"
    }]
  }

  expect_failures = [var.bindings]
}

run "rechaza_miembros_publicos" {
  command = plan

  variables {
    bindings = [{
      scope    = "storage_bucket"
      resource = "example-bucket"
      role     = "roles/storage.objectViewer"
      member   = "allUsers"
    }]
  }

  expect_failures = [var.bindings]
}

run "rechaza_rol_basico" {
  command = plan

  variables {
    bindings = [{
      scope    = "project"
      resource = "example-project-id"
      role     = "roles/owner"
      member   = "group:example-admins@example.com"
    }]
  }

  expect_failures = [var.bindings]
}

run "rechaza_scope_desconocido" {
  command = plan

  variables {
    bindings = [{
      scope    = "dataset"
      resource = "example"
      role     = "roles/viewer"
      member   = "group:example@example.com"
    }]
  }

  expect_failures = [var.bindings]
}

# ADR 0029: sin carpetas ni cuentas de facturación administradas por el pipeline.
run "rechaza_scope_folder" {
  command = plan

  variables {
    bindings = [{
      scope    = "folder"
      resource = "folders/111111111111"
      role     = "roles/viewer"
      member   = "group:example@example.com"
    }]
  }

  expect_failures = [var.bindings]
}

run "rechaza_recurso_mal_formado" {
  command = plan

  variables {
    bindings = [{
      scope    = "subnetwork"
      resource = "example-subnet"
      role     = "roles/compute.networkUser"
      member   = "group:example@example.com"
    }]
  }

  expect_failures = [var.bindings]
}

run "rechaza_repetidas" {
  command = plan

  variables {
    bindings = [
      {
        scope    = "project"
        resource = "example-project-id"
        role     = "roles/viewer"
        member   = "group:example@example.com"
      },
      {
        scope    = "project"
        resource = "example-project-id"
        role     = "roles/viewer"
        member   = "group:example@example.com"
      },
    ]
  }

  expect_failures = [var.bindings]
}
