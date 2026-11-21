# Prueba de la raíz 2-security sin GCP: mock_provider, override_data de los estados de
# 0-bootstrap y 1-org (con la forma de sus tablas de §7.0 y §7.1) y command = plan.

mock_provider "google" {
  mock_resource "google_access_context_manager_access_policy" {
    defaults = {
      name = "555555555555"
    }
  }
}

mock_provider "google-beta" {}

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
      workload_identity_provider = "projects/222222222222/locations/global/workloadIdentityPools/bnt-bootstrap-sec-wif-pool/providers/bnt-bootstrap-sec-github"
      kms_secret_iam_role_id     = "organizations/000000000000/roles/bntTfKmsSecretIamGranter"
    }
  }
}

override_data {
  target = data.terraform_remote_state.org
  values = {
    outputs = {
      folder_ids = {
        common = "folders/200000000001"
        dev    = "folders/200000000002"
        qa     = "folders/200000000003"
        prod   = "folders/200000000004"
      }
      common_project_ids = {
        net_hub  = "bnt-common-net-hub"
        logging  = "bnt-common-logging"
        security = "bnt-common-security"
        backup   = "bnt-common-backup"
      }
      common_project_numbers = {
        net_hub  = "400000000001"
        logging  = "400000000002"
        security = "400000000003"
        backup   = "400000000004"
      }
      log_bucket = "bnt-common-ops-audit-logs"
    }
  }
}

# Mismos valores que terraform.tfvars.example.
variables {
  org_id         = "000000000000"
  prefix         = "bnt"
  primary_region = "us-central1"
  dr_region      = "us-east4"
  environments   = ["dev", "qa", "prod"]
  state_bucket   = "bnt-bootstrap-ops-tfstate"
  secret_names = {
    dev  = ["app-api-token"]
    qa   = ["app-api-token"]
    prod = ["app-api-token"]
  }
  key_rotation_period = "7776000s"
  access_policy_id    = null
  vpc_sc_enforced     = false
  labels = {
    app         = "landing-zone"
    owner       = "seguridad"
    cost_center = "ti-001"
  }
}

run "plan_con_valores_de_ejemplo" {
  command = plan

  # kms_key_ids[entorno][ubicación][uso] (§7.2).
  assert {
    condition     = toset(keys(output.kms_key_ids)) == toset(["dev", "qa", "prod"])
    error_message = "kms_key_ids debe tener un mapa por entorno."
  }
  assert {
    condition = alltrue([for e in ["dev", "qa", "prod"] :
      toset(keys(output.kms_key_ids[e])) == toset(["us-central1", "us-east4", "us"])
    ])
    error_message = "Cada entorno debe tener llaves en la región primaria, la de DR y la multirregión us."
  }
  assert {
    condition = alltrue(flatten([for e in ["dev", "qa", "prod"] : [for r in ["us-central1", "us-east4"] :
      toset(keys(output.kms_key_ids[e][r])) == toset(["gke", "compute", "sql", "storage", "filestore", "redis", "secrets", "backup", "run"])
    ]]))
    error_message = "En cada región se crean las nueve llaves de uso."
  }
  assert {
    condition     = alltrue([for e in ["dev", "qa", "prod"] : toset(keys(output.kms_key_ids[e]["us"])) == toset(["storage", "backup"])])
    error_message = "En la multirregión us solo se crean storage y backup."
  }

  # Nombres (§4.2).
  assert {
    condition     = module.kms["prod/us-east4"].keyring_name == "bnt-prod-sec-keyring-use4" && module.kms["prod/us-east4"].key_names["sql"] == "bnt-prod-sec-sql"
    error_message = "Llaveros <prefix>-<env>-sec-keyring-<código> y llaves <prefix>-<env>-sec-<uso>."
  }
  assert {
    condition     = module.kms["dev/us"].keyring_name == "bnt-dev-sec-keyring-us"
    error_message = "El llavero de la multirregión usa el código us."
  }

  # Agente de Secret Manager con encrypter/decrypter solo en las llaves secrets regionales.
  assert {
    condition = alltrue([for k, r in local.keyrings :
      tolist(r.keys["secrets"].encrypter_decrypters) == tolist(["serviceAccount:service-400000000003@gcp-sa-secretmanager.iam.gserviceaccount.com"])
      if r.location != "us"
    ])
    error_message = "El agente de Secret Manager del proyecto security debe poder usar las llaves secrets."
  }
  assert {
    condition = alltrue(flatten([for k, r in local.keyrings : [
      for u, o in r.keys : length(o.encrypter_decrypters) == 0 if u != "secrets"
    ]]))
    error_message = "Las demás llaves no dan permisos en esta etapa (los da la etapa 4)."
  }

  # Secretos por entorno, sin valores.
  assert {
    condition     = toset(keys(output.secret_ids)) == toset(["dev", "qa", "prod"]) && module.secrets["prod"].secret_names["app-api-token"] == "bnt-prod-sec-app-api-token"
    error_message = "Contenedores de secretos <prefix>-<env>-sec-<nombre> por entorno."
  }

  # VPC-SC (ADR 0009): perímetro de prod en dry-run por defecto.
  assert {
    condition     = output.vpc_sc_enforced == false && module.vpc_sc.perimeter_short_name == "bnt_prod_sec_perimeter"
    error_message = "El perímetro de prod arranca en modo dry-run."
  }
  assert {
    condition = alltrue([
      !contains(var.vpc_sc_restricted_services, "cloudkms.googleapis.com"),
      !contains(var.vpc_sc_restricted_services, "secretmanager.googleapis.com"),
      contains(var.vpc_sc_restricted_services, "storage.googleapis.com"),
    ])
    error_message = "Por defecto KMS y Secret Manager no son servicios restringidos (ADR 0019)."
  }

  # Permisos para la etapa 4.
  assert {
    condition     = google_access_context_manager_access_policy_iam_member.projects_stage.member == "serviceAccount:bnt-tf-4-projects@bnt-bootstrap-seed.iam.gserviceaccount.com"
    error_message = "4-projects debe poder editar la política de acceso (alta de proyectos de prod)."
  }
  assert {
    condition     = module.iam.bindings["sa|4-projects|project:security|kms-secret-iam-granter"].role == "organizations/000000000000/roles/bntTfKmsSecretIamGranter"
    error_message = "4-projects recibe el rol personalizado de la etapa 0 sobre el proyecto security."
  }
}

run "perimetro_forzado_con_politica_existente" {
  command = plan

  variables {
    vpc_sc_enforced  = true
    access_policy_id = "123456789"
    environments     = ["prod"]
    secret_names     = {}
  }

  assert {
    condition     = output.vpc_sc_enforced == true && output.access_policy_id == "123456789"
    error_message = "Con vpc_sc_enforced = true y una política existente, el perímetro se fuerza en esa política."
  }
  assert {
    condition     = output.perimeter_name == "accessPolicies/123456789/servicePerimeters/bnt_prod_sec_perimeter"
    error_message = "El perímetro se crea en la política recibida."
  }
  assert {
    condition     = output.secret_ids == { prod = {} } && toset(keys(output.kms_key_ids)) == toset(["prod"])
    error_message = "Solo se crean los entornos pedidos; sin secretos, el mapa del entorno queda vacío."
  }
}

run "rotacion_mayor_a_90_dias" {
  command = plan

  variables {
    key_rotation_period = "8640000s"
  }

  expect_failures = [var.key_rotation_period]
}

run "secretos_de_entorno_desconocido" {
  command = plan

  variables {
    environments = ["prod"]
    secret_names = {
      dev = ["app-api-token"]
    }
  }

  expect_failures = [var.secret_names]
}
