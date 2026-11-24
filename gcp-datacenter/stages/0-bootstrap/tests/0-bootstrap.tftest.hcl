# Prueba de la raíz 0-bootstrap sin GCP: mock_provider y command = plan. Los valores
# calculados que los módulos validan por formato (carpeta, llave KMS, correos de cuentas de
# servicio) tienen valores simulados con el formato real.

mock_provider "google" {
  # Los valores simulados se usan ya en el plan (Terraform >= 1.11): así se comprueban el
  # principalSet exacto, la llave del bucket y el principal de la denegación.
  override_during = plan

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
      id = "projects/bnt-bootstrap-seed/locations/us/keyRings/bnt-bootstrap-sec-keyring-us"
    }
  }
  mock_resource "google_kms_crypto_key" {
    defaults = {
      id = "projects/bnt-bootstrap-seed/locations/us/keyRings/bnt-bootstrap-sec-keyring-us/cryptoKeys/bnt-bootstrap-sec-state"
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

# Mismos valores que terraform.tfvars.example, salvo los IDs de GitHub: aquí son distintos
# entre sí para que la prueba distinga el ID del repositorio del de su dueño.
variables {
  org_id                     = "000000000000"
  billing_account            = "000000-000000-000000"
  prefix                     = "bnt"
  project_suffix             = ""
  primary_region             = "us-central1"
  github_repository          = "example-org/example-repo"
  github_repository_id       = "100000001"
  github_repository_owner_id = "200000002"
  state_bucket_location      = "US"
  security_alert_email       = "gcp-security-admins@example.com"
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

  # CIS (docs/cumplimiento-cis.md): Cloud Asset (2.14) y Essential Contacts (API del proyecto
  # de cuota de la etapa 1, 1.17) en el semilla; métricas y alertas de auditoría (2.5 a 2.12)
  # hacia security_admins; y el rol de contactos de la cuenta de 1-org en la organización.
  assert {
    condition     = alltrue([for a in ["cloudasset.googleapis.com", "essentialcontacts.googleapis.com", "monitoring.googleapis.com"] : contains(module.seed_project.enabled_apis, a)])
    error_message = "El proyecto semilla debe habilitar Cloud Asset, Essential Contacts y Monitoring."
  }
  assert {
    condition     = length(module.seed_audit_alerts.metric_names) == 9 && module.seed_audit_alerts.metric_names["owner"] == "bnt-bootstrap-ops-audit-owner"
    error_message = "El proyecto semilla debe tener las métricas de auditoría de CIS 2.5 a 2.12."
  }
  assert {
    condition     = module.stage_iam.bindings["org|1-org|roles/essentialcontacts.admin"].scope == "organization"
    error_message = "La cuenta de 1-org necesita roles/essentialcontacts.admin en la organización (CIS 1.17)."
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
    ])
    error_message = "El bucket de estado debe ser versionado, uniforme, sin acceso público y sin borrado forzado."
  }
  # CMEK: exactamente la llave state de la etapa 0, no otra.
  assert {
    condition     = google_storage_bucket.state.encryption[0].default_kms_key_name == "projects/bnt-bootstrap-seed/locations/us/keyRings/bnt-bootstrap-sec-keyring-us/cryptoKeys/bnt-bootstrap-sec-state" && google_storage_bucket.state.encryption[0].default_kms_key_name == module.state_kms.key_ids["state"]
    error_message = "El bucket de estado debe cifrarse con la llave state de la etapa 0."
  }
  # Sobrevive a la caída de la región primaria: bucket multirregional y llave en la
  # multirregión de KMS correspondiente (la CMEK de Cloud Storage exige la misma ubicación).
  assert {
    condition = alltrue([
      google_storage_bucket.state.location == "US",
      length(google_storage_bucket.state.custom_placement_config) == 0,
      module.state_kms.keyring_name == "bnt-bootstrap-sec-keyring-us",
      module.state_kms.location == "us",
    ])
    error_message = "El bucket de estado debe ser multirregional (US) y su llave estar en la ubicación us de KMS."
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
  # La confianza se basa en los IDs numéricos (no reutilizables), no en el nombre.
  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.repository_id == \"100000001\" && assertion.repository_owner_id == \"200000002\""
    error_message = "attribute_condition debe exigir los IDs numéricos del repositorio y de su dueño."
  }
  assert {
    condition = alltrue([
      google_iam_workload_identity_pool_provider.github.attribute_mapping["attribute.repository_id"] == "assertion.repository_id",
      google_iam_workload_identity_pool_provider.github.attribute_mapping["attribute.repository_owner_id"] == "assertion.repository_owner_id",
      google_iam_workload_identity_pool_provider.github.attribute_mapping["google.subject"] == "assertion.sub",
      alltrue([for a in ["attribute.repository", "attribute.ref", "attribute.environment"] :
        contains(keys(google_iam_workload_identity_pool_provider.github.attribute_mapping), a)
      ]),
    ])
    error_message = "El proveedor debe mapear repository_id, repository_owner_id, repository, ref y environment."
  }
  assert {
    # Exactamente el principalSet del ID del repositorio en el pool de la etapa: ni el pool
    # entero (/*) ni el atributo por nombre.
    condition = alltrue([for k in keys(local.stages) :
      module.stage_iam.bindings["wif|${k}|roles/iam.workloadIdentityUser"].member == "principalSet://iam.googleapis.com/projects/222222222222/locations/global/workloadIdentityPools/bnt-bootstrap-sec-wif-pool/attribute.repository_id/100000001" &&
      module.stage_iam.bindings["wif|${k}|roles/iam.workloadIdentityUser"].scope == "service_account"
    ])
    error_message = "Cada cuenta de etapa acepta workloadIdentityUser solo desde el ID del repositorio autorizado."
  }

  # Política de denegación de la carpeta bootstrap contra la cuenta de 1-org.
  assert {
    condition = alltrue([
      google_iam_deny_policy.bootstrap_folder.parent == "cloudresourcemanager.googleapis.com%2Ffolders%2F111111111111",
      google_iam_deny_policy.bootstrap_folder.name == "bnt-bootstrap-sec-deny-1-org",
      google_iam_deny_policy.bootstrap_folder.rules[0].deny_rule[0].denied_principals == tolist(["principal://iam.googleapis.com/projects/-/serviceAccounts/${google_service_account.stage["1-org"].email}"]),
    ])
    error_message = "La política de denegación va en la carpeta bootstrap y solo contra la cuenta de 1-org."
  }
  assert {
    condition = alltrue([for p in [
      "iam.googleapis.com/serviceAccounts.setIamPolicy",
      "iam.googleapis.com/serviceAccounts.getAccessToken",
      "iam.googleapis.com/serviceAccounts.implicitDelegation",
      "iam.googleapis.com/serviceAccounts.signJwt",
      "storage.googleapis.com/buckets.setIamPolicy",
      "cloudresourcemanager.googleapis.com/projects.setIamPolicy",
      "cloudresourcemanager.googleapis.com/folders.setIamPolicy",
      "cloudkms.googleapis.com/cryptoKeys.setIamPolicy",
    ] : contains(google_iam_deny_policy.bootstrap_folder.rules[0].deny_rule[0].denied_permissions, p)])
    error_message = "1-org no debe poder cambiar el IAM ni tomar la identidad de nada en la carpeta bootstrap."
  }
  assert {
    # Lo que 1-org sí hace en la carpeta: leer y escribir objetos de estado y usar el proyecto
    # semilla como proyecto de cuota. Nada de eso se niega.
    condition = alltrue([for p in google_iam_deny_policy.bootstrap_folder.rules[0].deny_rule[0].denied_permissions :
      !startswith(p, "storage.googleapis.com/objects.") || p == "storage.googleapis.com/objects.setIamPolicy"
      ]) && alltrue([for p in google_iam_deny_policy.bootstrap_folder.rules[0].deny_rule[0].denied_permissions :
      !startswith(p, "serviceusage.googleapis.com/")
    ])
    error_message = "La denegación no puede quitarle a 1-org la lectura y escritura de su estado ni el proyecto de cuota."
  }

  # Rol de 2-security para los secretos: sin acceso a valores ni IAM de secretos.
  assert {
    condition = alltrue([
      contains(google_organization_iam_custom_role.secret_container_admin.permissions, "secretmanager.secrets.create"),
      length([for p in google_organization_iam_custom_role.secret_container_admin.permissions : p if startswith(p, "secretmanager.versions.")]) == 0,
      !contains(google_organization_iam_custom_role.secret_container_admin.permissions, "secretmanager.secrets.setIamPolicy"),
    ])
    error_message = "El rol de contenedores de secretos no puede leer versiones ni cambiar el IAM de los secretos."
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
  # Solo lo que sus raíces leen de verdad (remote_state.tf): 3-networks no lee 0-bootstrap y
  # 5-workloads no lee 1-org.
  assert {
    condition = alltrue([
      local.stages["3-networks"].reads == ["1-org"],
      !contains(local.stages["5-workloads"].reads, "1-org"),
      !strcontains(module.stage_iam.conditions["state|3-networks|roles/storage.objectViewer"].expression, "/objects/0-bootstrap/"),
      !strcontains(module.stage_iam.conditions["state|5-workloads|roles/storage.objectViewer"].expression, "/objects/1-org/"),
    ])
    error_message = "3-networks no lee 0-bootstrap y 5-workloads no lee 1-org."
  }
  # Cada asignación del bucket lleva su condición (aislamiento por prefijo).
  assert {
    condition = alltrue([for k in keys(local.stages) :
      module.stage_iam.bindings["state|${k}|roles/storage.objectAdmin"].resource == "bnt-bootstrap-ops-tfstate" &&
      module.stage_iam.conditions["state|${k}|roles/storage.objectAdmin"].expression == local.state_admin_expression[k] &&
      module.stage_iam.conditions["state|${k}|roles/storage.objectViewer"].expression == local.state_viewer_expression[k]
    ])
    error_message = "Cada cuenta recibe objectAdmin y objectViewer condicionados a sus prefijos sobre el bucket de estado."
  }
  assert {
    condition = module.stage_iam.conditions["state|4-projects|roles/storage.objectAdmin"].expression == join(" || ", [
      "resource.type == \"storage.googleapis.com/Bucket\"",
      "resource.name.startsWith(\"projects/_/buckets/bnt-bootstrap-ops-tfstate/objects/4-projects/dev/\")",
      "resource.name.startsWith(\"projects/_/buckets/bnt-bootstrap-ops-tfstate/objects/4-projects/qa/\")",
      "resource.name.startsWith(\"projects/_/buckets/bnt-bootstrap-ops-tfstate/objects/4-projects/prod/\")",
    ])
    error_message = "La condición de escritura de 4-projects debe cubrir solo sus tres prefijos."
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
    prefix = "Empresa1"
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

run "estado_en_doble_region" {
  command = plan

  variables {
    state_bucket_dual_regions = ["us-central1", "us-east4"]
  }

  assert {
    condition = alltrue([
      google_storage_bucket.state.location == "US",
      google_storage_bucket.state.custom_placement_config[0].data_locations == toset(["US-CENTRAL1", "US-EAST4"]),
      google_storage_bucket.state.rpo == "ASYNC_TURBO",
      module.state_kms.location == "us",
    ])
    error_message = "Doble región configurable: primaria y DR dentro de US, replicación turbo y llave en us."
  }
}

run "doble_region_sin_la_primaria" {
  command = plan

  variables {
    state_bucket_dual_regions = ["us-east4", "us-west1"]
  }

  expect_failures = [google_storage_bucket.state]
}

run "ubicacion_regional_del_estado" {
  command = plan

  variables {
    state_bucket_location = "us-central1"
  }

  expect_failures = [var.state_bucket_location]
}

run "id_de_repositorio_invalido" {
  command = plan

  variables {
    github_repository_id = "example-org/example-repo"
  }

  expect_failures = [var.github_repository_id]
}
