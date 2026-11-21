# Prueba de la raíz 0-bootstrap sin GCP: mock_provider y command = plan. Los valores
# calculados que los módulos validan por formato (carpeta, llave KMS, correos de cuentas de
# servicio) tienen valores simulados con el formato real.

mock_provider "google" {
  mock_resource "google_folder" {
    defaults = {
      folder_id = "111111111111"
      name      = "folders/111111111111"
    }
  }
  mock_resource "google_project" {
    defaults = {
      number = "222222222222"
    }
  }
  mock_resource "google_kms_key_ring" {
    defaults = {
      id = "projects/bnt-bootstrap-seed/locations/us-central1/keyRings/bnt-bootstrap-sec-keyring-usc1"
    }
  }
  mock_resource "google_kms_crypto_key" {
    defaults = {
      id = "projects/bnt-bootstrap-seed/locations/us-central1/keyRings/bnt-bootstrap-sec-keyring-usc1/cryptoKeys/bnt-bootstrap-sec-state"
    }
  }
  mock_resource "google_service_account" {
    defaults = {
      email  = "bnt-tf-stage@bnt-bootstrap-seed.iam.gserviceaccount.com"
      member = "serviceAccount:bnt-tf-stage@bnt-bootstrap-seed.iam.gserviceaccount.com"
      name   = "projects/bnt-bootstrap-seed/serviceAccounts/bnt-tf-stage@bnt-bootstrap-seed.iam.gserviceaccount.com"
    }
  }
  mock_resource "google_iam_workload_identity_pool" {
    defaults = {
      name = "projects/222222222222/locations/global/workloadIdentityPools/bnt-bootstrap-sec-wif-pool"
    }
  }
  mock_resource "google_iam_workload_identity_pool_provider" {
    defaults = {
      name = "projects/222222222222/locations/global/workloadIdentityPools/bnt-bootstrap-sec-wif-pool/providers/bnt-bootstrap-sec-github"
    }
  }
  mock_resource "google_organization_iam_custom_role" {
    defaults = {
      name = "organizations/000000000000/roles/bntTfKmsSecretIamGranter"
    }
  }
  mock_data "google_storage_project_service_account" {
    defaults = {
      email_address = "service-222222222222@gs-project-accounts.iam.gserviceaccount.com"
    }
  }
}

mock_provider "google-beta" {}

# Mismos valores que terraform.tfvars.example.
variables {
  org_id            = "000000000000"
  billing_account   = "000000-000000-000000"
  prefix            = "bnt"
  project_suffix    = ""
  primary_region    = "us-central1"
  github_repository = "example-org/example-repo"
  labels = {
    app         = "landing-zone"
    owner       = "plataforma"
    cost_center = "ti-001"
  }
}

run "plan_con_valores_de_ejemplo" {
  command = plan

  # Nombres (§4.2 y ADR 0017).
  assert {
    condition     = output.seed_project_id == "bnt-bootstrap-seed"
    error_message = "El proyecto semilla debe llamarse <prefix>-bootstrap-seed."
  }
  assert {
    condition     = startswith(output.bootstrap_folder_id, "folders/")
    error_message = "bootstrap_folder_id debe tener la forma folders/<número>."
  }
  assert {
    condition     = output.state_bucket == "bnt-bootstrap-ops-tfstate"
    error_message = "El bucket de estado debe llamarse <prefix>-bootstrap-ops-tfstate."
  }
  assert {
    condition = alltrue([for k in keys(local.stages) :
      google_service_account.stage[k].account_id == "bnt-tf-${k}"
    ])
    error_message = "Las cuentas de servicio deben llamarse <prefix>-tf-<etapa>."
  }
  assert {
    condition     = google_iam_workload_identity_pool.github.workload_identity_pool_id == "bnt-bootstrap-sec-wif-pool"
    error_message = "Nombre del pool de WIF fuera de convención."
  }

  # Salida stage_service_accounts: exactamente las cinco llaves del contrato.
  assert {
    condition     = toset(keys(output.stage_service_accounts)) == toset(["1-org", "2-security", "3-networks", "4-projects", "5-workloads"])
    error_message = "stage_service_accounts debe tener las llaves 1-org … 5-workloads."
  }

  # Bucket de estado (§6.1): versionado, acceso uniforme, sin acceso público, CMEK propia.
  assert {
    condition = alltrue([
      google_storage_bucket.state.versioning[0].enabled,
      google_storage_bucket.state.uniform_bucket_level_access,
      google_storage_bucket.state.public_access_prevention == "enforced",
      google_storage_bucket.state.force_destroy == false,
      length(google_storage_bucket.state.encryption) == 1,
    ])
    error_message = "El bucket de estado debe ser versionado, uniforme, sin acceso público y con CMEK de la etapa 0."
  }
  assert {
    condition     = google_storage_bucket.state.labels["env"] == "bootstrap" && google_storage_bucket.state.labels["managed_by"] == "terraform"
    error_message = "El bucket debe llevar las etiquetas comunes."
  }

  # Llave del estado con rotación de 90 días (ADR 0008).
  assert {
    condition     = module.state_kms.key_names["state"] == "bnt-bootstrap-sec-state"
    error_message = "La llave del estado debe llamarse <prefix>-bootstrap-sec-state."
  }
  # El correo del agente no se conoce en el plan: la fuente de datos se consulta con el número
  # del proyecto semilla, que se crea en el mismo plan (así no corre contra un proyecto que aún
  # no existe). Se comprueba el rol; el correo lo da la fuente de datos en el apply.
  assert {
    condition     = google_kms_crypto_key_iam_member.state_storage_agent.role == "roles/cloudkms.cryptoKeyEncrypterDecrypter"
    error_message = "El agente de Cloud Storage del proyecto semilla debe poder usar la llave."
  }

  # WIF (§6.3).
  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.repository == \"example-org/example-repo\""
    error_message = "attribute_condition debe exigir el repositorio autorizado."
  }
  assert {
    condition = alltrue([for a in ["attribute.repository", "attribute.ref", "attribute.environment"] :
      contains(keys(google_iam_workload_identity_pool_provider.github.attribute_mapping), a)
    ])
    error_message = "El proveedor debe mapear repository, ref y environment."
  }
  assert {
    # El nombre del pool se conoce después del apply; se revisa el prefijo del principal y el rol.
    condition = alltrue([for k in keys(local.stages) :
      startswith(module.stage_iam.bindings["wif|${k}|roles/iam.workloadIdentityUser"].member, "principalSet://iam.googleapis.com/") &&
      module.stage_iam.bindings["wif|${k}|roles/iam.workloadIdentityUser"].scope == "service_account"
    ])
    error_message = "Cada cuenta de etapa acepta workloadIdentityUser solo desde el repositorio."
  }

  # IAM condicionado del estado (§6.2), derivado de la tabla de §6.1.
  assert {
    condition = local.state_admin_expression["1-org"] == join(" || ", [
      "resource.type == \"storage.googleapis.com/Bucket\"",
      "resource.name.startsWith(\"projects/_/buckets/bnt-bootstrap-ops-tfstate/objects/1-org/\")",
    ])
    error_message = "1-org solo escribe su prefijo (más el listado del bucket)."
  }
  assert {
    condition = local.state_viewer_expression["2-security"] == join(" || ", [
      "resource.type == \"storage.googleapis.com/Bucket\"",
      "resource.name.startsWith(\"projects/_/buckets/bnt-bootstrap-ops-tfstate/objects/0-bootstrap/\")",
      "resource.name.startsWith(\"projects/_/buckets/bnt-bootstrap-ops-tfstate/objects/1-org/\")",
    ])
    error_message = "2-security lee 0-bootstrap y 1-org."
  }
  assert {
    condition     = strcontains(local.state_admin_expression["3-networks"], "/objects/3-networks/hub/\")")
    error_message = "Los prefijos terminan en / para que 3-networks/hub no coincida con un hermano."
  }
  assert {
    condition = alltrue([
      contains(local.stages["4-projects"].reads, "3-networks/prod"),
      !contains(local.stages["4-projects"].reads, "0-bootstrap"),
      !contains(local.stages["4-projects"].reads, "3-networks/hub"),
      !contains(local.stages["5-workloads"].reads, "0-bootstrap"),
      contains(local.stages["5-workloads"].reads, "4-projects/dev"),
    ])
    error_message = "4-projects y 5-workloads leen solo lo de su fila de §6.1."
  }
  assert {
    condition = alltrue([for k in keys(local.stages) :
      module.stage_iam.bindings["state|${k}|roles/storage.objectAdmin"].resource == "bnt-bootstrap-ops-tfstate"
    ])
    error_message = "Cada cuenta recibe objectAdmin condicionado sobre el bucket de estado."
  }

  # Mínimo privilegio: ningún rol básico ni de dueño de organización.
  assert {
    condition = alltrue([for b in values(module.stage_iam.bindings) :
      !contains(["roles/owner", "roles/editor", "roles/resourcemanager.organizationAdmin"], b.role)
    ])
    error_message = "Las cuentas de etapa no reciben roles básicos ni organizationAdmin."
  }
}

run "prefix_invalido" {
  command = plan

  variables {
    prefix = "Banorte1"
  }

  expect_failures = [var.prefix]
}

run "repositorio_invalido" {
  command = plan

  variables {
    github_repository = "sin-barra"
  }

  expect_failures = [var.github_repository]
}
