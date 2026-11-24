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
        service_account_manager = "projects/example-project-id/roles/bntTfServiceAccountManager"
        network_tag_manager     = "projects/example-project-id/roles/bntTfNetworkTagManager"
        off_hours_scheduler     = "projects/example-project-id/roles/bntOffHoursScheduler"
      }
      state_iam_conditions  = {}
      org_policies_enabled  = false
      vpc_sc_perimeter_name = null
      onprem_dns_vm_enabled = false
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
    condition     = output.security_alert_email == "seguridad@example.com" && keys(output.notification_channel_ids) == ["security"]
    error_message = "Las salidas de avisos deben publicar el correo y solo el canal security (sin operations_alert_email no hay canal de operaciones)."
  }

  # --- Llaves por entorno ---
  # Solo las llaves que alguien usa (H9): las de dr_region y storage de us solo en
  # dr_environments (prod), artifacts solo en artifact_registry_location (us).
  assert {
    condition = alltrue([
      toset(keys(module.kms)) == toset(["dev/us-central1", "dev/us", "qa/us-central1", "qa/us", "prod/us-central1", "prod/us-east4", "prod/us"]),
      module.kms["dev/us-central1"].keyring_name == "bnt-dev-sec-keyring-usc1",
      module.kms["prod/us-east4"].keyring_name == "bnt-prod-sec-keyring-use4",
      module.kms["qa/us"].keyring_name == "bnt-qa-sec-keyring-us",
      toset(keys(module.kms["dev/us-central1"].key_names)) == toset(["gke", "compute", "run", "sql", "storage", "redis", "filestore", "secrets"]),
      toset(keys(module.kms["prod/us-east4"].key_names)) == toset(["gke", "compute", "run", "sql", "backup", "secrets"]),
      toset(keys(module.kms["prod/us"].key_names)) == toset(["storage", "artifacts"]),
      toset(keys(module.kms["qa/us"].key_names)) == toset(["artifacts"]),
    ])
    error_message = "Un llavero por entorno y ubicación con llaves, y solo las llaves que usan 3-workloads y esta etapa."
  }
  assert {
    condition = alltrue([
      contains(local.keyrings["dev/us-central1"].keys["gke"].encrypter_decrypters, "serviceAccount:service-222222222222@container-engine-robot.iam.gserviceaccount.com"),
      contains(local.keyrings["dev/us-central1"].keys["gke"].encrypter_decrypters, "serviceAccount:service-222222222222@compute-system.iam.gserviceaccount.com"),
      local.keyrings["prod/us-east4"].keys["sql"].encrypter_decrypters == ["serviceAccount:service-222222222222@gcp-sa-cloud-sql.iam.gserviceaccount.com"],
      local.keyrings["qa/us"].keys["artifacts"].encrypter_decrypters == ["serviceAccount:service-222222222222@gcp-sa-artifactregistry.iam.gserviceaccount.com"],
      local.keyrings["prod/us-central1"].keys["secrets"].encrypter_decrypters == ["serviceAccount:service-222222222222@gcp-sa-secretmanager.iam.gserviceaccount.com"],
      local.keyrings["prod/us-east4"].keys["backup"].encrypter_decrypters == ["serviceAccount:service-222222222222@gcp-sa-gkebackup.iam.gserviceaccount.com"],
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
      google_artifact_registry_repository_iam_member.writer["dev/app/serviceAccount:ci-app@example-project-id.iam.gserviceaccount.com"].role == "roles/artifactregistry.writer",
    ])
    error_message = "El agente de Cloud Run lee los repositorios y el publicador escribe solo en el suyo."
  }

  # --- Cuentas de ejecución de los entornos (hallazgos 2 y 4) ---
  assert {
    condition = alltrue([
      # 3 entornos × 1 aplicación × 4 usos, más la cuenta del apagado en dev y qa.
      length(google_service_account.runtime) == 14,
      google_service_account.runtime["prod/app/gke_nodes"].account_id == "bnt-prod-app-gke-nodes",
      google_service_account.runtime["prod/app/gke_nodes"].project == "example-project-id",
      google_service_account.runtime["dev/app/scheduler"].account_id == "bnt-dev-app-sched",
      !contains(keys(google_service_account.runtime), "prod/app/scheduler"),
      output.runtime_service_accounts["qa"]["app"] == {
        gke_nodes = "bnt-qa-app-gke-nodes@example-project-id.iam.gserviceaccount.com"
        mig       = "bnt-qa-app-mig@example-project-id.iam.gserviceaccount.com"
        run       = "bnt-qa-app-run@example-project-id.iam.gserviceaccount.com"
        scheduler = "bnt-qa-app-sched@example-project-id.iam.gserviceaccount.com"
        workload  = "bnt-qa-app-workload@example-project-id.iam.gserviceaccount.com"
      },
      !contains(keys(output.runtime_service_accounts["prod"]["app"]), "scheduler"),
    ])
    error_message = "1-base crea <prefix>-<env>-<app>-<uso> por entorno y aplicación (sched solo en dev y qa) y publica sus correos."
  }
  assert {
    condition = alltrue([
      module.iam.bindings["runtime|prod/app/gke_nodes|roles/logging.logWriter"].member == "serviceAccount:bnt-prod-app-gke-nodes@example-project-id.iam.gserviceaccount.com",
      module.iam.bindings["runtime|dev/app/scheduler|projects/example-project-id/roles/bntOffHoursScheduler"].member == "serviceAccount:bnt-dev-app-sched@example-project-id.iam.gserviceaccount.com",
      # Por entorno: 13 roles de telemetría, 6 de Cloud SQL (workload, run y mig) y el del apagado
      # en dev y qa.
      length([for k, b in module.iam.bindings : k if startswith(k, "runtime|")]) == 59,
      !anytrue([for k, b in module.iam.bindings : strcontains(b.role, "admin") || strcontains(b.role, "Admin") if startswith(k, "runtime|")]),
    ])
    error_message = "Cada cuenta de ejecución recibe solo sus roles mínimos de proyecto."
  }
  assert {
    condition = alltrue([
      module.iam.conditions["runtime|dev/app/run|roles/cloudsql.client"].expression == "resource.type == \"sqladmin.googleapis.com/Instance\" && resource.name.startsWith(\"projects/example-project-id/instances/bnt-dev-data-\")",
      module.iam.conditions["runtime|prod/app/mig|roles/cloudsql.instanceUser"].expression == "resource.type == \"sqladmin.googleapis.com/Instance\" && resource.name.startsWith(\"projects/example-project-id/instances/bnt-prod-data-\")",
      !contains(keys(module.iam.bindings), "runtime|prod/app/gke_nodes|roles/cloudsql.client"),
    ])
    error_message = "Cloud SQL por IAM solo para workload, run y mig, limitado a las instancias de su entorno."
  }
  assert {
    condition = alltrue([
      toset(keys(google_secret_manager_secret_iam_member.runtime)) == toset([
        "dev/app/workload/db-password", "dev/app/run/db-password",
        "prod/app/workload/db-password", "prod/app/run/db-password",
        "prod/app/workload/api-key", "prod/app/run/api-key",
      ]),
      google_secret_manager_secret_iam_member.runtime["prod/app/run/api-key"].member == "serviceAccount:bnt-prod-app-run@example-project-id.iam.gserviceaccount.com",
      google_secret_manager_secret_iam_member.runtime["prod/app/run/api-key"].role == "roles/secretmanager.secretAccessor",
    ])
    error_message = "workload y run leen solo los secretos de su entorno."
  }
  assert {
    condition = alltrue([
      toset(keys(google_artifact_registry_repository_iam_member.runtime_reader)) == toset(["dev/app/gke_nodes", "dev/app/mig", "qa/app/gke_nodes", "qa/app/mig", "prod/app/gke_nodes", "prod/app/mig"]),
      google_artifact_registry_repository_iam_member.runtime_reader["prod/app/mig"].repository == "bnt-prod-app",
      google_artifact_registry_repository_iam_member.runtime_reader["prod/app/mig"].member == "serviceAccount:bnt-prod-app-mig@example-project-id.iam.gserviceaccount.com",
      google_artifact_registry_repository_iam_member.runtime_reader["prod/app/mig"].role == "roles/artifactregistry.reader",
    ])
    error_message = "Los nodos de GKE y las VM del MIG leen solo el repositorio de su entorno y aplicación."
  }
  # tf-wl-<env> solo usa (actAs) las cuentas de su entorno que adjunta, nunca workload.
  assert {
    condition = alltrue([
      toset(keys(google_service_account_iam_member.workloads_user)) == toset([
        "dev/app/gke_nodes", "dev/app/mig", "dev/app/run", "dev/app/scheduler",
        "qa/app/gke_nodes", "qa/app/mig", "qa/app/run", "qa/app/scheduler",
        "prod/app/gke_nodes", "prod/app/mig", "prod/app/run",
      ]),
      alltrue([for k, m in google_service_account_iam_member.workloads_user : m.role == "roles/iam.serviceAccountUser" && m.member == "serviceAccount:bnt-tf-wl-${split("/", k)[0]}@example-project-id.iam.gserviceaccount.com"]),
    ])
    error_message = "tf-wl-<env> recibe serviceAccountUser solo sobre gke_nodes, mig, run y sched de su entorno."
  }
  # Sin gke_workload_identity_bindings no hay enlace (el pool lo crea GKE con el primer clúster).
  assert {
    condition     = length(google_service_account_iam_member.workload_identity) == 0 && output.gke_workload_identity_members["prod"]["app"] == null
    error_message = "Sin gke_workload_identity_bindings no hay enlace de Workload Identity y la salida es null."
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
  # Sin atestadores por entorno: la lista global admite el repositorio de dev en cualquier clúster
  # (riesgo del ADR 0024 escrito en artifacts.tf).
  assert {
    condition = alltrue([
      contains([for p in google_binary_authorization_policy.this.admission_whitelist_patterns : p.name_pattern], "us-docker.pkg.dev/example-project-id/bnt-dev-app/**"),
      alltrue([for r in google_binary_authorization_policy.this.cluster_admission_rules : r.evaluation_mode == "ALWAYS_DENY"]),
    ])
    error_message = "Sin atestadores por entorno se conserva el comportamiento de hoy: lista global con los tres repositorios."
  }

  # --- IAM de personas y agentes ---
  assert {
    condition = alltrue([
      module.iam.bindings["group|readers|roles/viewer"].member == "group:gcp-readers@example.com",
      module.iam.bindings["group|auditors|roles/logging.privateLogViewer"].scope == "project",
      module.iam.bindings["group|auditors|bucket:audit_logs|roles/storage.objectViewer"].resource == "bnt-common-ops-audit-logs",
      # El tagUser de los agentes lo da 0-bootstrap: esta etapa no asigna roles de etiquetas.
      length([for k, b in module.iam.bindings : k if strcontains(b.role, "resourcemanager.tag")]) == 0,
    ])
    error_message = "Grupos de solo lectura y ningún rol de etiquetas (el tagUser de los agentes es de 0-bootstrap)."
  }
  # La cuenta de 1-base solo puede asignar los roles de sus dos condiciones en 0-bootstrap
  # (base_grantable_roles y runtime_grantable_roles).
  assert {
    condition = alltrue([for b in values(module.iam.bindings) : contains([
      "roles/cloudkms.viewer", "roles/iam.securityReviewer", "roles/logging.privateLogViewer", "roles/logging.viewer",
      "roles/monitoring.viewer", "roles/viewer",
      "roles/autoscaling.metricsWriter", "roles/cloudsql.client", "roles/cloudsql.instanceUser", "roles/cloudtrace.agent",
      "roles/logging.logWriter", "roles/monitoring.metricWriter", "roles/stackdriver.resourceMetadata.writer",
      "projects/example-project-id/roles/bntOffHoursScheduler",
    ], b.role) if b.scope == "project"])
    error_message = "Un rol de proyecto fuera de las listas de la concesión delegada de 0-bootstrap fallaría en el apply."
  }
  assert {
    condition     = alltrue([for b in values(module.iam.bindings) : b.scope != "organization"])
    error_message = "1-base no asigna roles de organización ni de la política de acceso: las políticas de organización y el perímetro los aplica 0-bootstrap."
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
      toset(keys(output.kms_key_ids["dev"])) == toset(["gke", "compute", "run", "sql", "storage", "redis", "filestore", "secrets", "artifacts_us"]),
      toset(keys(output.kms_key_ids["prod"])) == toset([
        "gke", "compute", "run", "sql", "storage", "redis", "filestore", "secrets",
        "gke_dr", "compute_dr", "run_dr", "sql_dr", "backup_dr", "secrets_dr",
        "storage_us", "artifacts_us",
      ]),
    ])
    error_message = "kms_key_ids debe tener <uso>, <uso>_dr y <uso>_us, solo con las llaves que se usan (sin backup ni artifacts regionales, sin redis, filestore ni storage en DR, y _dr y storage_us solo en dr_environments)."
  }
}

# Los entornos de DR se eligen con dr_environments: qa con DR tiene sus llaves _dr y storage_us.
run "dr_environments_con_qa" {
  command = plan

  variables {
    dr_environments = ["qa", "prod"]
  }

  assert {
    condition = alltrue([
      alltrue([for k in ["gke_dr", "sql_dr", "backup_dr", "secrets_dr", "storage_us"] : contains(keys(output.kms_key_ids["qa"]), k)]),
      length([for k in keys(output.kms_key_ids["dev"]) : k if endswith(k, "_dr")]) == 0,
    ])
    error_message = "Con qa en dr_environments, qa tiene llaves de DR y dev no."
  }
}

run "rechaza_entorno_de_dr_desconocido" {
  command = plan

  variables {
    dr_environments = ["prod", "staging"]
  }

  expect_failures = [var.dr_environments]
}

run "con_canal_de_operaciones" {
  command = plan

  variables {
    operations_alert_email = "Operaciones@example.com"
  }

  assert {
    condition = alltrue([
      google_monitoring_notification_channel.operations["this"].labels["email_address"] == "operaciones@example.com",
      google_monitoring_notification_channel.operations["this"].display_name == "bnt-common-ops-operations",
      toset(keys(output.notification_channel_ids)) == toset(["security", "operations"]),
    ])
    error_message = "Con operations_alert_email hay un canal de operaciones aparte del de seguridad."
  }
  assert {
    condition     = length(google_service_account.onprem_dns) == 0 && output.onprem_dns_service_account == null && !contains(keys(module.iam.bindings), "onprem-dns|roles/logging.logWriter")
    error_message = "Sin onprem_dns_vm en 0-bootstrap no hay cuenta de la VM DNS."
  }
}

# VM DNS de onprem-sim: 0-bootstrap con onprem_dns_vm = true.
run "con_cuenta_de_la_vm_dns" {
  command = plan

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
          service_account_manager = "projects/example-project-id/roles/bntTfServiceAccountManager"
          network_tag_manager     = "projects/example-project-id/roles/bntTfNetworkTagManager"
          off_hours_scheduler     = "projects/example-project-id/roles/bntOffHoursScheduler"
        }
        state_iam_conditions  = {}
        org_policies_enabled  = false
        vpc_sc_perimeter_name = null
        onprem_dns_vm_enabled = true
      }
    }
  }

  assert {
    condition = alltrue([
      google_service_account.onprem_dns["this"].account_id == "bnt-common-net-dns",
      output.onprem_dns_service_account == "bnt-common-net-dns@example-project-id.iam.gserviceaccount.com",
      google_service_account_iam_member.onprem_dns_hub_user["this"].role == "roles/iam.serviceAccountUser",
      google_service_account_iam_member.onprem_dns_hub_user["this"].member == "serviceAccount:bnt-tf-net@example-project-id.iam.gserviceaccount.com",
      module.iam.bindings["onprem-dns|roles/logging.logWriter"].member == "serviceAccount:bnt-common-net-dns@example-project-id.iam.gserviceaccount.com",
      length([for k, b in module.iam.bindings : k if b.member == "serviceAccount:bnt-common-net-dns@example-project-id.iam.gserviceaccount.com"]) == 1,
    ])
    error_message = "Con onprem_dns_vm, 1-base crea <prefix>-common-net-dns con solo logWriter y le da al hub serviceAccountUser sobre ella."
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

# Con un atestador por entorno: los repositorios salen de la lista de permitidos, cada clúster
# exige el atestador de su entorno y la regla por defecto (Cloud Run) el del primer entorno.
run "atestadores_por_entorno" {
  command = plan

  variables {
    binary_authorization_env_attestors = {
      dev  = "projects/example-project-id/attestors/bnt-dev"
      qa   = "projects/example-project-id/attestors/bnt-qa"
      prod = "projects/example-project-id/attestors/bnt-prod"
    }
    binary_authorization_allowlist_patterns = ["us-docker.pkg.dev/cloudrun/container/hello*"]
  }

  assert {
    condition     = [for p in google_binary_authorization_policy.this.admission_whitelist_patterns : p.name_pattern] == ["us-docker.pkg.dev/cloudrun/container/hello*"]
    error_message = "Con atestadores por entorno la lista de permitidos solo tiene binary_authorization_allowlist_patterns."
  }
  assert {
    condition = alltrue([
      google_binary_authorization_policy.this.default_admission_rule[0].evaluation_mode == "REQUIRE_ATTESTATION",
      toset(google_binary_authorization_policy.this.default_admission_rule[0].require_attestations_by) == toset(["projects/example-project-id/attestors/bnt-dev"]),
    ])
    error_message = "La regla por defecto exige el atestador del primer entorno de la promoción (dev)."
  }
  assert {
    condition = alltrue([
      toset([for r in google_binary_authorization_policy.this.cluster_admission_rules : r.cluster]) == toset([
        "us-central1.bnt-dev-app-gke", "us-east4.bnt-dev-app-gke-dr",
        "us-central1.bnt-qa-app-gke", "us-east4.bnt-qa-app-gke-dr",
        "us-central1.bnt-prod-app-gke", "us-east4.bnt-prod-app-gke-dr",
      ]),
      alltrue([for r in google_binary_authorization_policy.this.cluster_admission_rules : r.evaluation_mode == "REQUIRE_ATTESTATION" && r.enforcement_mode == "ENFORCED_BLOCK_AND_AUDIT_LOG"]),
      alltrue([
        for r in google_binary_authorization_policy.this.cluster_admission_rules :
        toset(r.require_attestations_by) == toset(["projects/example-project-id/attestors/bnt-${split("-", split(".", r.cluster)[1])[1]}"])
      ]),
    ])
    error_message = "Cada clúster de cada entorno exige solo el atestador de su entorno."
  }
}

# Atestadores comunes (por ejemplo, el de un análisis de vulnerabilidades) junto con los de
# entorno: la regla por defecto exige los comunes y cada clúster los suyos más los comunes.
run "atestadores_por_entorno_y_comunes" {
  command = plan

  variables {
    binary_authorization_attestors = ["projects/example-project-id/attestors/bnt-scan"]
    binary_authorization_env_attestors = {
      dev  = "projects/example-project-id/attestors/bnt-dev"
      qa   = "projects/example-project-id/attestors/bnt-qa"
      prod = "projects/example-project-id/attestors/bnt-prod"
    }
  }

  assert {
    condition = alltrue([
      length(google_binary_authorization_policy.this.admission_whitelist_patterns) == 0,
      toset(google_binary_authorization_policy.this.default_admission_rule[0].require_attestations_by) == toset(["projects/example-project-id/attestors/bnt-scan"]),
      toset([for r in google_binary_authorization_policy.this.cluster_admission_rules : r.require_attestations_by if r.cluster == "us-central1.bnt-prod-app-gke"][0]) == toset(["projects/example-project-id/attestors/bnt-prod", "projects/example-project-id/attestors/bnt-scan"]),
    ])
    error_message = "La regla por defecto exige los atestadores comunes y cada clúster el de su entorno más los comunes."
  }
}

run "rechaza_atestadores_de_entorno_incompletos" {
  command = plan

  variables {
    binary_authorization_env_attestors = {
      prod = "projects/example-project-id/attestors/bnt-prod"
    }
  }

  expect_failures = [var.binary_authorization_env_attestors]
}

run "sin_prod_no_hay_reglas_de_cluster" {
  command = plan

  variables {
    environments                 = ["dev"]
    dr_environments              = []
    secret_names                 = {}
    artifact_registry_publishers = {}
  }

  assert {
    condition     = length(google_binary_authorization_policy.this.cluster_admission_rules) == 0 && toset(keys(module.kms)) == toset(["dev/us-central1", "dev/us"])
    error_message = "Sin prod no hay reglas de clúster de prod; sin entornos de DR no hay llavero en dr_region."
  }
}

# Después del primer clúster de GKE: la cuenta de Kubernetes <app>-<env>/<cuenta> actúa como
# workload, y cada entorno con su namespace.
run "con_enlace_de_workload_identity" {
  command = plan

  variables {
    gke_workload_identity_bindings = true
    gke_workload_ksa_name          = "api"
    applications                   = ["app", "pagos"]
    off_hours_environments         = ["dev"]
  }

  assert {
    condition = alltrue([
      length(google_service_account_iam_member.workload_identity) == 6,
      google_service_account_iam_member.workload_identity["prod/pagos"].member == "serviceAccount:example-project-id.svc.id.goog[pagos-prod/api]",
      google_service_account_iam_member.workload_identity["prod/pagos"].role == "roles/iam.workloadIdentityUser",
      output.gke_workload_identity_members["dev"]["app"] == "serviceAccount:example-project-id.svc.id.goog[app-dev/api]",
    ])
    error_message = "Con gke_workload_identity_bindings, un enlace por entorno y aplicación con el namespace <app>-<env>."
  }
  assert {
    condition = alltrue([
      length(google_service_account.runtime) == 26,
      google_service_account.runtime["dev/pagos/scheduler"].account_id == "bnt-dev-pagos-sched",
      !contains(keys(google_service_account.runtime), "qa/app/scheduler"),
      output.runtime_service_accounts["prod"]["pagos"]["workload"] == "bnt-prod-pagos-workload@example-project-id.iam.gserviceaccount.com",
      # Los secretos son del entorno: las dos aplicaciones de prod leen los mismos.
      contains(keys(google_secret_manager_secret_iam_member.runtime), "prod/pagos/run/api-key"),
    ])
    error_message = "Cuentas por aplicación y apagado solo en off_hours_environments."
  }
}

# Con 9 caracteres, <prefix>-prod-<app>-gke-nodes pasaría de 30 con un prefijo de 6.
run "rechaza_aplicacion_de_mas_de_8_caracteres" {
  command = plan

  variables {
    applications = ["pagosweb1"]
  }

  expect_failures = [var.applications]
}

# Con el prefijo y la aplicación más largos, la cuenta más larga cabe justo en 30.
run "admite_prefijo_y_aplicacion_maximos" {
  command = plan

  variables {
    prefix                       = "bntlzx"
    applications                 = ["pagosweb"]
    artifact_registry_publishers = {}
  }

  assert {
    condition     = google_service_account.runtime["prod/pagosweb/gke_nodes"].account_id == "bntlzx-prod-pagosweb-gke-nodes"
    error_message = "La cuenta más larga debe caber en 30 caracteres."
  }
}

run "rechaza_apagado_en_prod" {
  command = plan

  variables {
    off_hours_environments = ["dev", "prod"]
  }

  expect_failures = [var.off_hours_environments]
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

run "rechaza_secretos_de_common" {
  command = plan

  variables {
    secret_names = { common = ["vpn"] }
  }

  expect_failures = [var.secret_names]
}

run "admite_patrones_de_imagen_validos" {
  command = plan

  variables {
    binary_authorization_allowlist_patterns = [
      "us-docker.pkg.dev/cloudrun/container/hello*",
      "us-docker.pkg.dev/otro-proyecto/base/**",
      "registry.example.com:5000/equipo/imagen",
    ]
  }

  assert {
    condition = alltrue([
      length(google_binary_authorization_policy.this.admission_whitelist_patterns) == 6,
      contains([for p in google_binary_authorization_policy.this.admission_whitelist_patterns : p.name_pattern], "us-docker.pkg.dev/cloudrun/container/hello*"),
    ])
    error_message = "Los patrones válidos se suman a los repositorios del proyecto en la lista de permitidos."
  }
}

# Un registro entero (gcr.io/*) admitiría las imágenes de cualquier proyecto.
run "rechaza_patron_de_registro_entero" {
  command = plan

  variables {
    binary_authorization_allowlist_patterns = ["gcr.io/*"]
  }

  expect_failures = [var.binary_authorization_allowlist_patterns]
}
