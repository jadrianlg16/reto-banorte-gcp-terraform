# Prueba de la raíz 1-org sin GCP: mock_provider, override_data del estado de 0-bootstrap
# (con la forma de su tabla de §7.0) y command = plan.

mock_provider "google" {
  mock_resource "google_folder" {
    defaults = {
      folder_id = "111111111111"
      name      = "folders/111111111111"
    }
  }
  mock_resource "google_project" {
    defaults = {
      number = "333333333333"
    }
  }
  mock_resource "google_kms_crypto_key" {
    defaults = {
      id = "projects/bnt-common-logging/locations/us-central1/keyRings/bnt-common-sec-keyring-usc1/cryptoKeys/bnt-common-sec-logs"
    }
  }
  mock_resource "google_logging_organization_sink" {
    defaults = {
      writer_identity = "serviceAccount:o000000000000-000000@gcp-sa-logging.iam.gserviceaccount.com"
    }
  }
  mock_data "google_storage_project_service_account" {
    defaults = {
      email_address = "service-333333333333@gs-project-accounts.iam.gserviceaccount.com"
    }
  }
}

mock_provider "google-beta" {
  mock_resource "google_project_service_identity" {
    defaults = {
      email  = "service-333333333333@gcp-sa-pubsub.iam.gserviceaccount.com"
      member = "serviceAccount:service-333333333333@gcp-sa-pubsub.iam.gserviceaccount.com"
    }
  }
}

override_data {
  target = data.terraform_remote_state.bootstrap
  values = {
    outputs = {
      seed_project_id     = "bnt-bootstrap-seed"
      bootstrap_folder_id = "folders/100000000000"
      state_bucket        = "bnt-bootstrap-ops-tfstate"
      state_kms_key_id    = "projects/bnt-bootstrap-seed/locations/us-central1/keyRings/bnt-bootstrap-sec-keyring-usc1/cryptoKeys/bnt-bootstrap-sec-state"
      stage_service_accounts = {
        "1-org"       = "bnt-tf-1-org@bnt-bootstrap-seed.iam.gserviceaccount.com"
        "2-security"  = "bnt-tf-2-security@bnt-bootstrap-seed.iam.gserviceaccount.com"
        "3-networks"  = "bnt-tf-3-networks@bnt-bootstrap-seed.iam.gserviceaccount.com"
        "4-projects"  = "bnt-tf-4-projects@bnt-bootstrap-seed.iam.gserviceaccount.com"
        "5-workloads" = "bnt-tf-5-workloads@bnt-bootstrap-seed.iam.gserviceaccount.com"
      }
      workload_identity_provider     = "projects/222222222222/locations/global/workloadIdentityPools/bnt-bootstrap-sec-wif-pool/providers/bnt-bootstrap-sec-github"
      kms_secret_iam_role_id         = "organizations/000000000000/roles/bntTfKmsSecretIamGranter"
      secret_container_admin_role_id = "organizations/000000000000/roles/bntTfSecretContainerAdmin"
    }
  }
}

# Mismos valores que terraform.tfvars.example.
variables {
  org_id                = "000000000000"
  billing_account       = "000000-000000-000000"
  prefix                = "bnt"
  project_suffix        = ""
  primary_region        = "us-central1"
  dr_region             = "us-east4"
  directory_customer_id = "C00000000"
  state_bucket          = "bnt-bootstrap-ops-tfstate"
  groups = {
    org_admins      = "gcp-org-admins@example.com"
    billing_admins  = "gcp-billing-admins@example.com"
    security_admins = "gcp-security-admins@example.com"
    network_admins  = "gcp-network-admins@example.com"
    platform_devops = "gcp-platform-devops@example.com"
    developers      = "gcp-developers@example.com"
    auditors        = "gcp-auditors@example.com"
  }
  log_retention_days   = 365
  log_retention_locked = false
  budget_amount        = 1000
  labels = {
    app         = "landing-zone"
    owner       = "plataforma"
    cost_center = "ti-001"
  }
}

run "plan_con_valores_de_ejemplo" {
  command = plan

  # Salidas de §7.1 y nombres (§4.2).
  assert {
    condition     = toset(keys(output.folder_ids)) == toset(["common", "dev", "qa", "prod"])
    error_message = "folder_ids debe tener las llaves common, dev, qa y prod."
  }
  assert {
    condition     = alltrue([for id in values(output.folder_ids) : startswith(id, "folders/")])
    error_message = "Los IDs de carpeta conservan el prefijo literal folders/."
  }
  assert {
    condition = output.common_project_ids == {
      net_hub  = "bnt-common-net-hub"
      logging  = "bnt-common-logging"
      security = "bnt-common-security"
      backup   = "bnt-common-backup"
    }
    error_message = "Los proyectos de common deben llamarse <prefix>-common-<nombre>."
  }
  assert {
    condition     = toset(keys(output.common_project_numbers)) == toset(["net_hub", "logging", "security", "backup"])
    error_message = "common_project_numbers debe tener las mismas llaves que common_project_ids."
  }
  assert {
    condition     = output.log_bucket == "bnt-common-ops-audit-logs"
    error_message = "El bucket de logs debe llamarse <prefix>-common-ops-audit-logs."
  }

  # Políticas de organización: las nueve; gcp.resourceLocations con primaria + DR.
  assert {
    condition     = length(module.org.policy_names) == 9
    error_message = "Deben existir las nueve políticas de organización."
  }
  assert {
    condition     = module.org.policy_parent == "organizations/000000000000"
    error_message = "Las políticas se aplican en la organización."
  }

  # Un solo sink: el del módulo org, hacia el bucket de log-export.
  assert {
    condition     = module.audit_logs.sink_name == null && module.org.sink_name == "bnt-common-ops-audit-sink"
    error_message = "Debe haber un solo sink agregado (módulo org); log-export solo crea el bucket."
  }
  assert {
    condition     = module.audit_logs.destination == "storage.googleapis.com/bnt-common-ops-audit-logs"
    error_message = "El sink debe apuntar al bucket de logs."
  }

  # Llaves del proyecto logging (ADR 0018).
  assert {
    condition     = module.logging_kms.keyring_name == "bnt-common-sec-keyring-usc1" && toset(keys(module.logging_kms.key_names)) == toset(["logs", "pubsub"])
    error_message = "La etapa crea en logging el llavero con las llaves logs y pubsub."
  }

  # Data Access en la carpeta prod.
  assert {
    condition = alltrue([
      google_folder_iam_audit_config.prod.service == "allServices",
      contains([for c in google_folder_iam_audit_config.prod.audit_log_config : c.log_type], "DATA_READ"),
      contains([for c in google_folder_iam_audit_config.prod.audit_log_config : c.log_type], "DATA_WRITE"),
    ])
    error_message = "La carpeta prod debe registrar DATA_READ y DATA_WRITE de todos los servicios."
  }

  # SCC y presupuesto.
  assert {
    condition     = google_scc_v2_organization_notification_config.findings.config_id == "bnt-common-ops-scc-findings" && google_pubsub_topic.scc_findings.name == "bnt-common-ops-scc-findings"
    error_message = "Notificación de hallazgos de SCC fuera de convención."
  }
  assert {
    condition     = length(google_billing_budget.org.threshold_rules) == 5 && google_billing_budget.org.amount[0].specified_amount[0].units == "1000"
    error_message = "El presupuesto debe tener el monto y sus umbrales de alerta (4 reales + 1 pronosticado)."
  }

  # IAM por grupos: sin user:, solo lectura, developers solo en dev y qa.
  assert {
    condition     = alltrue([for b in local.iam_bindings : !startswith(b.member, "user:")])
    error_message = "Ningún rol se asigna a user:."
  }
  assert {
    condition = alltrue([for b in local.iam_bindings :
      can(regex("(?i)(viewer|reader|reviewer|browser)", b.role)) if startswith(b.member, "group:")
    ])
    error_message = "Las personas (grupos) solo reciben roles de lectura."
  }
  assert {
    condition = alltrue([for b in local.iam_bindings :
      strcontains(b.key, "|folder:dev|") || strcontains(b.key, "|folder:qa|")
      if b.member == "group:gcp-developers@example.com"
    ])
    error_message = "developers solo recibe roles en las carpetas dev y qa."
  }
  assert {
    condition     = length([for b in local.iam_bindings : b if b.member == "group:gcp-developers@example.com"]) == 6
    error_message = "developers recibe 3 roles en dev y 3 en qa."
  }

  # Permisos de carpeta y proyecto de las cuentas de etapa, leídas del estado de 0-bootstrap.
  assert {
    condition     = module.iam.bindings["sa|2-security|project:security|roles/cloudkms.admin"].member == "serviceAccount:bnt-tf-2-security@bnt-bootstrap-seed.iam.gserviceaccount.com"
    error_message = "La cuenta de 2-security administra KMS en el proyecto security."
  }
  assert {
    condition     = module.iam.bindings["sa|4-projects|folder:prod|roles/resourcemanager.projectCreator"].scope == "folder"
    error_message = "La cuenta de 4-projects crea proyectos en las carpetas de entorno."
  }
  # 5-workloads no recibe nada en las carpetas de entorno (contienen también el host
  # net-spoke): sus roles van por proyecto de servicio y los da 4-projects.
  assert {
    condition     = length([for k, b in module.iam.bindings : k if b.member == "serviceAccount:bnt-tf-5-workloads@bnt-bootstrap-seed.iam.gserviceaccount.com"]) == 0
    error_message = "La cuenta de 5-workloads no debe recibir ningún rol en 1-org."
  }
  assert {
    condition = alltrue([for e in ["dev", "qa", "prod"] :
      module.iam.bindings["sa|4-projects|folder:${e}|roles/resourcemanager.tagAdmin"].scope == "folder"
    ])
    error_message = "La cuenta de 4-projects necesita tagAdmin en las carpetas de entorno (tagUser sobre las etiquetas seguras del spoke)."
  }
  # projectIamAdmin delegado de 4-projects en las carpetas de entorno: exactamente sus tres roles.
  assert {
    condition = alltrue([for e in ["dev", "qa", "prod"] :
      module.iam.conditions["sa|4-projects|folder:${e}|roles/resourcemanager.projectIamAdmin"].expression == "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly(['roles/compute.networkUser', 'roles/compute.networkViewer', 'roles/container.hostServiceAgentUser'])"
    ])
    error_message = "projectIamAdmin de 4-projects debe quedar limitado a networkUser, networkViewer y hostServiceAgentUser."
  }
  assert {
    condition     = length([for b in local.iam_bindings : b if b.role == "roles/resourcemanager.projectIamAdmin" && b.scope == "folder"]) == 3
    error_message = "projectIamAdmin condicionado en carpetas: solo 4-projects en dev, qa y prod (3 asignaciones)."
  }

  # 2-security: sin secretmanager.admin (incluye versions.access) y con projectIamAdmin
  # condicionado en el proyecto security al único rol que asigna ahí.
  assert {
    condition = alltrue([
      module.iam.bindings["sa|2-security|project:security|organizations/000000000000/roles/bntTfSecretContainerAdmin"].resource == "bnt-common-security",
      length([for b in local.iam_bindings : b if b.role == "roles/secretmanager.admin"]) == 0,
    ])
    error_message = "2-security administra los secretos con el rol personalizado sin acceso a valores, no con secretmanager.admin."
  }
  assert {
    condition = alltrue([
      module.iam.bindings["sa|2-security|project:security|roles/resourcemanager.projectIamAdmin"].resource == "bnt-common-security",
      module.iam.conditions["sa|2-security|project:security|roles/resourcemanager.projectIamAdmin"].expression == "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly(['organizations/000000000000/roles/bntTfKmsSecretIamGranter'])",
      length([for b in local.iam_bindings : b if b.role == "roles/resourcemanager.projectIamAdmin" && b.condition == null]) == 0,
    ])
    error_message = "projectIamAdmin de 2-security en security debe quedar limitado al rol personalizado de 4-projects; ningún projectIamAdmin sin condición."
  }

  # Tema de SCC: llave regional, así que el almacenamiento se limita a su región y se impone
  # en tránsito.
  assert {
    condition = alltrue([
      google_pubsub_topic.scc_findings.message_storage_policy[0].allowed_persistence_regions == toset(["us-central1"]),
      google_pubsub_topic.scc_findings.message_storage_policy[0].enforce_in_transit == true,
    ])
    error_message = "El tema de SCC guarda mensajes solo en primary_region, con imposición en tránsito."
  }
}

run "grupos_incompletos" {
  command = plan

  variables {
    groups = {
      org_admins = "gcp-org-admins@example.com"
    }
  }

  expect_failures = [var.groups]
}

run "dr_igual_a_primaria" {
  command = plan

  variables {
    dr_region = "us-central1"
  }

  expect_failures = [var.dr_region]
}

run "prefix_invalido" {
  command = plan

  variables {
    prefix = "bnt-x"
  }

  expect_failures = [var.prefix]
}
