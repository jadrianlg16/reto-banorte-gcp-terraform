# Prueba de la raíz 1-base sin GCP: mock_provider, override_data del estado de 0-bootstrap (con
# la forma de su tabla de interfaces en el ADR 0029) y command = plan.

mock_provider "google" {
  mock_data "google_storage_project_service_account" {
    defaults = {
      email_address = "service-222222222222@gs-project-accounts.iam.gserviceaccount.com"
    }
  }
}

override_data {
  target = data.terraform_remote_state.bootstrap
  values = {
    outputs = {
      project_id       = "example-project-id"
      project_number   = "222222222222"
      state_bucket     = "bnt-bootstrap-ops-tfstate"
      state_kms_key_id = "projects/example-project-id/locations/us/keyRings/bnt-bootstrap-sec-keyring-us/cryptoKeys/bnt-bootstrap-sec-state"
      stage_service_accounts = {
        "1-base"           = "bnt-tf-base@example-project-id.iam.gserviceaccount.com"
        "2-networks"       = "bnt-tf-net@example-project-id.iam.gserviceaccount.com"
        "2-networks/dev"   = "bnt-tf-net-dev@example-project-id.iam.gserviceaccount.com"
        "2-networks/qa"    = "bnt-tf-net-qa@example-project-id.iam.gserviceaccount.com"
        "2-networks/prod"  = "bnt-tf-net-prod@example-project-id.iam.gserviceaccount.com"
        "3-workloads/dev"  = "bnt-tf-wl-dev@example-project-id.iam.gserviceaccount.com"
        "3-workloads/qa"   = "bnt-tf-wl-qa@example-project-id.iam.gserviceaccount.com"
        "3-workloads/prod" = "bnt-tf-wl-prod@example-project-id.iam.gserviceaccount.com"
      }
      read_service_account       = "bnt-tf-read@example-project-id.iam.gserviceaccount.com"
      workload_identity_provider = "projects/222222222222/locations/global/workloadIdentityPools/bnt-bootstrap-sec-wif-pool/providers/bnt-bootstrap-sec-github"
      workload_identity_pool     = "projects/222222222222/locations/global/workloadIdentityPools/bnt-bootstrap-sec-wif-pool"
      custom_role_ids = {
        secret_container_admin  = "projects/example-project-id/roles/bntTfSecretContainerAdmin"
        kms_secret_iam_granter  = "projects/example-project-id/roles/bntTfKmsSecretIamGranter"
        service_account_manager = "projects/example-project-id/roles/bntTfServiceAccountManager"
        repository_iam_granter  = "projects/example-project-id/roles/bntTfRepositoryIamGranter"
        off_hours_scheduler     = "projects/example-project-id/roles/bntOffHoursScheduler"
      }
      state_iam_conditions = {}
    }
  }
}

# Mismos valores que terraform.tfvars.example.
variables {
  project_id           = "example-project-id"
  state_bucket         = "bnt-bootstrap-ops-tfstate"
  prefix               = "bnt"
  primary_region       = "us-central1"
  dr_region            = "us-east4"
  security_alert_email = "seguridad@example.com"
  secret_names = {
    dev  = ["db-password"]
    prod = ["db-password", "api-key"]
  }
  groups = {
    readers  = "gcp-readers@example.com"
    auditors = "gcp-auditors@example.com"
  }
  essential_contacts = {
    "admin@example.com"     = ["LEGAL", "SUSPENSION", "TECHNICAL"]
    "seguridad@example.com" = ["SECURITY", "TECHNICAL"]
  }
  artifact_registry_publishers = {
    dev = { app = ["serviceAccount:ci-app@example-project-id.iam.gserviceaccount.com"] }
  }
  labels = {
    app         = "landing-zone"
    owner       = "plataforma"
    cost_center = "ti-001"
  }
}

run "plan_con_valores_de_ejemplo" {
  command = plan

  # --- Auditoría del proyecto (ADR 0029 §7) ---
  assert {
    condition = alltrue([
      google_project_iam_audit_config.all_services.service == "allServices",
      length(google_project_iam_audit_config.all_services.audit_log_config) == 1,
      toset(keys(google_project_iam_audit_config.data_access)) == toset(["cloudkms.googleapis.com", "iam.googleapis.com", "secretmanager.googleapis.com", "sqladmin.googleapis.com", "storage.googleapis.com"]),
      alltrue([for c in google_project_iam_audit_config.data_access : length(c.audit_log_config) == 2]),
    ])
    error_message = "ADMIN_READ para allServices y DATA_READ/DATA_WRITE para KMS, Secret Manager, IAM, Cloud SQL y Storage."
  }

  # --- Logs: llave, bucket y sink de proyecto con exclusión ---
  assert {
    condition = alltrue([
      module.common_kms.keyring_name == "bnt-common-sec-keyring-usc1",
      module.audit_logs.bucket_name == "bnt-common-ops-audit-logs",
      output.log_bucket == "bnt-common-ops-audit-logs",
      module.audit_logs.sink_name == "bnt-common-ops-audit-logs-sink",
    ])
    error_message = "Llavero común, bucket de logs y sink de proyecto fuera de convención."
  }
  # --- Alertas, contactos y SCC ---
  assert {
    condition     = length(module.audit_alerts.metric_names) == 9 && module.audit_alerts.metric_names["owner"] == "bnt-common-ops-audit-owner"
    error_message = "Las nueve métricas de auditoría de CIS 2.5 a 2.12 se crean una sola vez, en common."
  }
  assert {
    condition = alltrue([
      google_essential_contacts_contact.this["seguridad@example.com"].parent == "projects/example-project-id",
      google_essential_contacts_contact.this["seguridad@example.com"].notification_category_subscriptions == tolist(["SECURITY", "TECHNICAL"]),
    ])
    error_message = "Los contactos esenciales van en el proyecto."
  }
  assert {
    condition     = length(google_pubsub_topic.scc_findings) == 0 && length(google_scc_v2_project_notification_config.findings) == 0
    error_message = "Sin enable_scc_notification no se crea la notificación de SCC."
  }
  assert {
    condition     = output.security_alert_email == "seguridad@example.com" && contains(keys(output.notification_channel_ids), "security")
    error_message = "Las salidas de avisos deben publicar el correo y el canal security."
  }

  # --- Llaves por entorno ---
  assert {
    condition = alltrue([
      length(module.kms) == 9,
      module.kms["dev/us-central1"].keyring_name == "bnt-dev-sec-keyring-usc1",
      module.kms["prod/us-east4"].keyring_name == "bnt-prod-sec-keyring-use4",
      module.kms["qa/us"].keyring_name == "bnt-qa-sec-keyring-us",
      toset(keys(module.kms["qa/us"].key_names)) == toset(["storage", "backup", "artifacts"]),
      length(module.kms["dev/us-central1"].key_names) == 10,
    ])
    error_message = "Un llavero por entorno y ubicación con los usos de la etapa 2 anterior."
  }
  assert {
    condition = alltrue([
      contains(local.keyrings["dev/us-central1"].keys["gke"].encrypter_decrypters, "serviceAccount:service-222222222222@container-engine-robot.iam.gserviceaccount.com"),
      contains(local.keyrings["dev/us-central1"].keys["gke"].encrypter_decrypters, "serviceAccount:service-222222222222@compute-system.iam.gserviceaccount.com"),
      local.keyrings["prod/us-east4"].keys["sql"].encrypter_decrypters == ["serviceAccount:service-222222222222@gcp-sa-cloud-sql.iam.gserviceaccount.com"],
      local.keyrings["qa/us"].keys["artifacts"].encrypter_decrypters == ["serviceAccount:service-222222222222@gcp-sa-artifactregistry.iam.gserviceaccount.com"],
      local.keyrings["prod/us-central1"].keys["secrets"].encrypter_decrypters == ["serviceAccount:service-222222222222@gcp-sa-secretmanager.iam.gserviceaccount.com"],
      local.keyrings["dev/us"].keys["backup"].encrypter_decrypters == ["serviceAccount:service-222222222222@gcp-sa-gkebackup.iam.gserviceaccount.com"],
    ])
    error_message = "Cada agente de servicio recibe permiso sobre las llaves de su uso en los tres entornos."
  }

  # --- Secretos ---
  assert {
    condition = alltrue([
      toset(keys(module.secrets)) == toset(["dev", "prod"]),
      module.secrets["prod"].secret_names["api-key"] == "bnt-prod-sec-api-key",
    ])
    error_message = "Contenedores de secretos <prefix>-<env>-sec-<nombre> solo en los entornos con secretos."
  }

  # --- Imágenes y Binary Authorization ---
  assert {
    condition = alltrue([
      length(google_artifact_registry_repository.this) == 3,
      google_artifact_registry_repository.this["prod/app"].repository_id == "bnt-prod-app",
      google_artifact_registry_repository.this["prod/app"].location == "us",
      google_artifact_registry_repository.this["dev/app"].docker_config[0].immutable_tags == true,
      output.artifact_registry_repositories["qa"]["app"] == "us-docker.pkg.dev/example-project-id/bnt-qa-app",
    ])
    error_message = "Un repositorio <prefix>-<env>-<app> por entorno en la multirregión, con etiquetas inmutables."
  }
  assert {
    condition = alltrue([
      google_artifact_registry_repository_iam_member.run_agent_reader["dev/app"].member == "serviceAccount:service-222222222222@serverless-robot-prod.iam.gserviceaccount.com",
      google_artifact_registry_repository_iam_member.workloads_iam_granter["qa/app"].member == "serviceAccount:bnt-tf-wl-qa@example-project-id.iam.gserviceaccount.com",
      google_artifact_registry_repository_iam_member.workloads_iam_granter["qa/app"].role == "projects/example-project-id/roles/bntTfRepositoryIamGranter",
      google_artifact_registry_repository_iam_member.writer["dev/app/serviceAccount:ci-app@example-project-id.iam.gserviceaccount.com"].role == "roles/artifactregistry.writer",
    ])
    error_message = "El agente de Cloud Run lee los repositorios; cada cuenta de cargas puede dar IAM solo sobre los de su entorno."
  }
  assert {
    condition = alltrue([
      google_binary_authorization_policy.this.default_admission_rule[0].evaluation_mode == "ALWAYS_DENY",
      length(google_binary_authorization_policy.this.admission_whitelist_patterns) == 3,
      contains([for p in google_binary_authorization_policy.this.admission_whitelist_patterns : p.name_pattern], "us-docker.pkg.dev/example-project-id/bnt-prod-app/**"),
      toset([for r in google_binary_authorization_policy.this.cluster_admission_rules : r.cluster]) == toset(["us-central1.bnt-prod-app-gke", "us-east4.bnt-prod-app-gke-dr"]),
    ])
    error_message = "Una sola política: repositorios del proyecto permitidos, lo demás negado y reglas por clúster de prod por convención."
  }

  # --- IAM de personas y agentes ---
  assert {
    condition = alltrue([
      module.iam.bindings["group|readers|roles/viewer"].member == "group:gcp-readers@example.com",
      module.iam.bindings["group|auditors|roles/logging.privateLogViewer"].scope == "project",
      module.iam.bindings["group|auditors|bucket:audit_logs|roles/storage.objectViewer"].resource == "bnt-common-ops-audit-logs",
      module.iam.bindings["agent|gke|roles/resourcemanager.tagUser"].member == "serviceAccount:service-222222222222@container-engine-robot.iam.gserviceaccount.com",
      module.iam.bindings["agent|apis|roles/resourcemanager.tagUser"].member == "serviceAccount:222222222222@cloudservices.gserviceaccount.com",
    ])
    error_message = "Grupos de solo lectura y tagUser para el agente de GKE y la cuenta de las APIs de Google."
  }
  # La cuenta de 1-base solo puede asignar los roles de su condición en 0-bootstrap.
  assert {
    condition = alltrue([for b in values(module.iam.bindings) : contains([
      "roles/cloudkms.viewer", "roles/iam.securityReviewer", "roles/logging.privateLogViewer", "roles/logging.viewer",
      "roles/monitoring.viewer", "roles/resourcemanager.tagUser", "roles/viewer",
    ], b.role) if b.scope == "project"])
    error_message = "Un rol de proyecto fuera de base_grantable_roles de 0-bootstrap fallaría en el apply."
  }

  # --- Sin organización ---
  assert {
    condition = alltrue([
      length(module.org_policies) == 0,
      length(module.vpc_sc) == 0,
      output.org_policies_enabled == false,
      output.vpc_sc_perimeter_name == null,
    ])
    error_message = "Sin org_id ni access_policy_id no hay políticas de organización ni perímetro."
  }

  # --- Interfaz ---
  assert {
    condition = alltrue([
      output.off_hours_role_id == "projects/example-project-id/roles/bntOffHoursScheduler",
      toset(keys(output.kms_key_ids)) == toset(["dev", "qa", "prod"]),
      toset(keys(output.secret_ids)) == toset(["dev", "qa", "prod"]),
      length(output.secret_ids["qa"]) == 0,
    ])
    error_message = "Salidas de la interfaz del ADR 0029 fuera de forma."
  }
}

# Los nombres de llave de kms_key_ids siguen el formato de la etapa 2 anterior: <uso>, <uso>_dr y
# <uso>_us (3-workloads toma el uso de la primera palabra y la ubicación del ID).
run "nombres_de_llave_de_la_salida" {
  # En el plan los ID son desconocidos, pero las llaves del mapa ya se conocen.
  command = plan

  assert {
    condition = alltrue([
      length(output.kms_key_ids["dev"]) == 23,
      alltrue([for k in ["sql", "sql_dr", "gke", "gke_dr", "secrets_dr", "storage_us", "backup_us", "artifacts_us"] : contains(keys(output.kms_key_ids["prod"]), k)]),
      !contains(keys(output.kms_key_ids["prod"]), "sql_us"),
    ])
    error_message = "kms_key_ids debe tener <uso>, <uso>_dr y <uso>_us (en us solo storage, backup y artifacts)."
  }
}

run "con_organizacion_y_perimetro" {
  command = plan

  variables {
    org_id                = "000000000000"
    directory_customer_id = "C00000000"
    access_policy_id      = "555555555555"
  }

  assert {
    condition = alltrue([
      module.org_policies[0].policy_parent == "projects/example-project-id",
      length(module.org_policies[0].policy_names) == 8,
      output.org_policies_enabled == true,
      output.vpc_sc_perimeter_name == "accessPolicies/555555555555/servicePerimeters/bnt_common_sec_perimeter",
      module.vpc_sc[0].enforced == false,
      length(module.vpc_sc[0].spec_ingress_policies) == 1,
    ])
    error_message = "Con organización: políticas en el proyecto y perímetro en dry-run alrededor de todo el proyecto."
  }
}

run "con_scc_y_atestadores" {
  command = plan

  variables {
    enable_scc_notification        = true
    binary_authorization_attestors = ["projects/example-project-id/attestors/example"]
  }

  assert {
    condition = alltrue([
      google_pubsub_topic.scc_findings["this"].name == "bnt-common-ops-scc-findings",
      google_pubsub_topic.scc_findings["this"].message_storage_policy[0].enforce_in_transit == true,
      google_scc_v2_project_notification_config.findings["this"].project == "example-project-id",
      google_binary_authorization_policy.this.default_admission_rule[0].evaluation_mode == "REQUIRE_ATTESTATION",
      alltrue([for r in google_binary_authorization_policy.this.cluster_admission_rules : r.evaluation_mode == "REQUIRE_ATTESTATION"]),
    ])
    error_message = "SCC opcional con tema CMEK; con atestadores, la política las exige."
  }
}

run "sin_prod_no_hay_reglas_de_cluster" {
  command = plan

  variables {
    environments                 = ["dev"]
    secret_names                 = {}
    artifact_registry_publishers = {}
  }

  assert {
    condition     = length(google_binary_authorization_policy.this.cluster_admission_rules) == 0 && length(module.kms) == 3
    error_message = "Sin prod no hay reglas de clúster de prod."
  }
}

run "rechaza_proyecto_distinto_del_de_0_bootstrap" {
  command = plan

  variables {
    project_id = "otro-proyecto"
  }

  expect_failures = [google_project_iam_audit_config.all_services]
}

run "rechaza_contactos_incompletos" {
  command = plan

  variables {
    essential_contacts = { "admin@example.com" = ["TECHNICAL"] }
  }

  expect_failures = [var.essential_contacts]
}

run "rechaza_grupo_desconocido" {
  command = plan

  variables {
    groups = { developers = "gcp-developers@example.com" }
  }

  expect_failures = [var.groups]
}

run "rechaza_publicador_user" {
  command = plan

  variables {
    artifact_registry_publishers = { dev = { app = ["user:alguien@example.com"] } }
  }

  expect_failures = [var.artifact_registry_publishers]
}

run "rechaza_politica_de_acceso_sin_organizacion" {
  command = plan

  variables {
    access_policy_id = "555555555555"
  }

  expect_failures = [var.access_policy_id]
}

run "rechaza_secretos_de_common" {
  command = plan

  variables {
    secret_names = { common = ["vpn"] }
  }

  expect_failures = [var.secret_names]
}
