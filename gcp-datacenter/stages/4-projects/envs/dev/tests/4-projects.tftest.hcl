# Prueba sin GCP de la raíz 4-projects/envs/<env> (idéntica en dev, qa y prod). Los estados
# remotos se reemplazan con salidas de la forma exacta de §7.1, §7.2 y §7.4. override_during =
# plan hace que los valores simulados (números de proyecto, correos) se conozcan en el plan.

mock_provider "google" {
  override_during = plan

  mock_resource "google_project" {
    defaults = {
      number = "123456789012"
    }
  }
  mock_resource "google_service_account" {
    defaults = {
      email  = "mock-sa@bnt-dev-app.iam.gserviceaccount.com"
      member = "serviceAccount:mock-sa@bnt-dev-app.iam.gserviceaccount.com"
      name   = "projects/bnt-dev-app/serviceAccounts/mock-sa@bnt-dev-app.iam.gserviceaccount.com"
    }
  }
  mock_data "google_project" {
    defaults = {
      number = "987654321098"
    }
  }
  mock_data "google_folder" {
    defaults = {
      name         = "folders/000000000000"
      organization = "organizations/000000000000"
    }
  }
  mock_data "google_storage_project_service_account" {
    defaults = {
      email_address = "service-123456789012@gs-project-accounts.iam.gserviceaccount.com"
    }
  }
}

mock_provider "google-beta" {
  override_during = plan
}

# Primer apply real: sin override_during = plan, los atributos calculados de los recursos que se
# crean en el mismo plan (número de proyecto, correos de cuentas, agentes) quedan desconocidos,
# como en GCP. Solo se fijan las fuentes de datos de recursos que ya existen (carpeta y host).
mock_provider "google" {
  alias = "primer_apply"

  mock_data "google_project" {
    defaults = {
      number = "987654321098"
    }
  }
  mock_data "google_folder" {
    defaults = {
      name         = "folders/000000000000"
      organization = "organizations/000000000000"
    }
  }
}

mock_provider "google-beta" {
  alias = "primer_apply"
}

variables {
  org_id                    = "000000000000"
  billing_account           = "000000-000000-000000"
  prefix                    = "bnt"
  environment               = "dev"
  primary_region            = "us-central1"
  dr_region                 = "us-east4"
  state_bucket              = "bnt-bootstrap-tfstate"
  workloads_service_account = "bnt-tf-5-workloads@bnt-bootstrap-seed.iam.gserviceaccount.com"
  deletion_policy           = "DELETE"
  applications = {
    app = {
      apis    = ["pubsub.googleapis.com"]
      secrets = ["db-app"]
    }
  }
  labels = {
    owner       = "example-team"
    cost_center = "example-000"
  }
}

# §7.1
override_data {
  target          = data.terraform_remote_state.org
  override_during = plan
  values = {
    outputs = {
      folder_ids = {
        common = "folders/000000000001"
        dev    = "folders/000000000002"
        qa     = "folders/000000000003"
        prod   = "folders/000000000004"
      }
      common_project_ids = {
        net_hub  = "bnt-common-net-hub"
        logging  = "bnt-common-logging"
        security = "bnt-common-security"
        backup   = "bnt-common-backup"
      }
      common_project_numbers = {
        net_hub  = "000000000011"
        logging  = "000000000012"
        security = "000000000013"
        backup   = "000000000014"
      }
      log_bucket = "bnt-common-ops-audit-logs"
    }
  }
}

# §7.2 (dry-run, como arranca el perímetro por el ADR 0009)
override_data {
  target          = data.terraform_remote_state.security
  override_during = plan
  values = {
    outputs = {
      kms_key_ids = {
        for env in ["dev", "qa", "prod"] : env => merge(
          {
            for loc in ["us-central1", "us-east4"] : loc => {
              for use in ["gke", "compute", "sql", "storage", "filestore", "redis", "secrets", "backup", "run", "artifacts"] :
              use => "projects/bnt-common-security/locations/${loc}/keyRings/bnt-${env}-sec-${loc}/cryptoKeys/bnt-${env}-sec-${use}"
            }
          },
          {
            us = {
              for use in ["storage", "backup", "artifacts"] :
              use => "projects/bnt-common-security/locations/us/keyRings/bnt-${env}-sec-us/cryptoKeys/bnt-${env}-sec-${use}"
            }
          },
        )
      }
      secret_ids = {
        for env in ["dev", "qa", "prod"] : env => {
          db-app = "projects/bnt-common-security/secrets/bnt-${env}-sec-db-app"
          api    = "projects/bnt-common-security/secrets/bnt-${env}-sec-api"
        }
      }
      access_policy_id = "000000000000"
      perimeter_name   = "accessPolicies/000000000000/servicePerimeters/bnt_prod_sec_perimeter"
      vpc_sc_enforced  = false
    }
  }
}

# §7.4 (dev y qa: sin subredes *_dr)
override_data {
  target          = data.terraform_remote_state.network
  override_during = plan
  values = {
    outputs = {
      host_project_id   = "bnt-dev-net-spoke"
      network_name      = "bnt-dev-net-vpc"
      network_self_link = "https://www.googleapis.com/compute/v1/projects/bnt-dev-net-spoke/global/networks/bnt-dev-net-vpc"
      subnets = {
        for k, s in {
          app   = { region = "us-central1", cidr = "10.10.0.0/20", secondary_ranges = { pods = "10.10.64.0/18", services = "10.10.128.0/20" } }
          proxy = { region = "us-central1", cidr = "10.10.32.0/23", secondary_ranges = {} }
          run   = { region = "us-central1", cidr = "10.10.36.0/24", secondary_ranges = {} }
          } : k => merge(s, {
            name      = "bnt-dev-net-${k}-usc1"
            self_link = "https://www.googleapis.com/compute/v1/projects/bnt-dev-net-spoke/regions/${s.region}/subnetworks/bnt-dev-net-${k}-usc1"
        })
      }
      psa_range_name = "bnt-dev-net-psa"
      secure_tags = {
        lb_backend = "tagValues/000000000101"
        iap_ssh    = "tagValues/000000000102"
      }
      secure_tag_keys = {
        lb_backend = "tagKeys/000000000201"
        iap_ssh    = "tagKeys/000000000202"
      }
    }
  }
}

run "dev_con_valores_de_ejemplo" {
  command = plan

  assert {
    condition     = output.service_project_ids == { app = "bnt-dev-app" }
    error_message = "El proyecto de servicio debe llamarse <prefix>-<environment>-<app> (§4.2)."
  }
  assert {
    condition     = output.service_project_numbers == { app = "123456789012" }
    error_message = "service_project_numbers debe publicar el número de cada proyecto."
  }
  assert {
    condition     = module.project["app"].shared_vpc_host_project == "bnt-dev-net-spoke"
    error_message = "El proyecto de servicio debe unirse al host del spoke del entorno."
  }
  assert {
    condition = alltrue([
      for api in ["container.googleapis.com", "run.googleapis.com", "sqladmin.googleapis.com", "gkebackup.googleapis.com", "pubsub.googleapis.com", "compute.googleapis.com"] :
      contains(module.project["app"].enabled_apis, api)
    ])
    error_message = "Deben habilitarse las APIs base y las de applications[app].apis."
  }
  assert {
    condition = toset([for k, sa in google_service_account.runtime : sa.account_id]) == toset([
      "bnt-dev-app-gke-nodes", "bnt-dev-app-workload", "bnt-dev-app-mig", "bnt-dev-app-run",
    ])
    error_message = "Las cuentas de ejecución deben llamarse <prefix>-<env>-<app>-<uso> (ADR 0017)."
  }
  assert {
    condition     = alltrue([for sa in google_service_account.runtime : sa.project == "bnt-dev-app"])
    error_message = "Las cuentas de ejecución viven en el proyecto de servicio."
  }
  assert {
    condition     = keys(output.service_accounts) == ["app"] && toset(keys(output.service_accounts["app"])) == toset(["gke_nodes", "workload", "mig", "run"])
    error_message = "service_accounts debe ser [aplicación][uso] con los usos de §7.5."
  }
  assert {
    condition     = toset(keys(google_project_service_identity.this)) == toset(["app/artifactregistry.googleapis.com", "app/file.googleapis.com", "app/gkebackup.googleapis.com", "app/redis.googleapis.com", "app/sqladmin.googleapis.com"])
    error_message = "Deben crearse los agentes de servicio que no existen hasta el primer uso."
  }

  # Uso de subredes y host de Shared VPC.
  assert {
    condition = module.iam.bindings["subnet/app/app/gke"] == {
      scope    = "subnetwork"
      resource = "projects/bnt-dev-net-spoke/regions/us-central1/subnetworks/bnt-dev-net-app-usc1"
      role     = "roles/compute.networkUser"
      member   = "serviceAccount:service-123456789012@container-engine-robot.iam.gserviceaccount.com"
    }
    error_message = "El agente de GKE debe tener networkUser sobre la subred app del host."
  }
  assert {
    condition     = module.iam.bindings["subnet/app/app/apis"].member == "serviceAccount:123456789012@cloudservices.gserviceaccount.com"
    error_message = "El agente de APIs de Google debe tener networkUser sobre la subred app."
  }
  assert {
    condition     = module.iam.bindings["subnet/app/run/run"].member == "serviceAccount:service-123456789012@serverless-robot-prod.iam.gserviceaccount.com"
    error_message = "El agente de Cloud Run debe tener networkUser sobre la subred run."
  }
  assert {
    condition     = !anytrue([for k, b in module.iam.bindings : b.scope == "subnetwork" && strcontains(b.resource, "proxy")])
    error_message = "Las subredes proxy-only no se otorgan."
  }
  assert {
    condition     = !anytrue([for k in keys(module.iam.bindings) : strcontains(k, "_dr")])
    error_message = "Sin subredes de DR en el estado no hay permisos sobre ellas."
  }
  assert {
    condition = module.iam.bindings["host/app/gke"] == {
      scope    = "project"
      resource = "bnt-dev-net-spoke"
      role     = "roles/container.hostServiceAgentUser"
      member   = "serviceAccount:service-123456789012@container-engine-robot.iam.gserviceaccount.com"
    }
    error_message = "El agente de GKE debe tener hostServiceAgentUser en el host."
  }

  # KMS
  assert {
    condition = alltrue([
      for k in [
        "kms/app/us-central1/gke/gke", "kms/app/us-central1/gke/compute", "kms/app/us-central1/compute/compute",
        "kms/app/us-central1/sql/sql", "kms/app/us-central1/storage/storage", "kms/app/us/storage/storage",
        "kms/app/us-central1/filestore/filestore", "kms/app/us-central1/redis/redis", "kms/app/us-central1/run/run",
        "kms/app/us-central1/backup/gkebackup", "kms/app/us-east4/sql/sql",
      ] : module.iam.bindings[k].role == "roles/cloudkms.cryptoKeyEncrypterDecrypter"
    ])
    error_message = "Cada agente debe recibir encrypterDecrypter sobre la llave de su uso."
  }
  assert {
    condition     = module.iam.bindings["kms/app/us/storage/storage"].resource == "projects/bnt-common-security/locations/us/keyRings/bnt-dev-sec-us/cryptoKeys/bnt-dev-sec-storage"
    error_message = "La llave de Cloud Storage de la multirregión us debe salir de kms_key_ids[env][us][storage]."
  }
  assert {
    condition     = !anytrue([for k in keys(module.iam.bindings) : startswith(k, "kms/app/us/backup") || strcontains(k, "/secrets/")])
    error_message = "Ni la llave backup de us ni la de secrets se otorgan a agentes del proyecto de servicio."
  }

  # Secretos y cuentas de ejecución.
  assert {
    condition = (
      module.iam.bindings["secret/app/db-app/workload"].resource == "projects/bnt-common-security/secrets/bnt-dev-sec-db-app" &&
      module.iam.bindings["secret/app/db-app/run"].role == "roles/secretmanager.secretAccessor" &&
      length([for k in keys(module.iam.bindings) : k if startswith(k, "secret/")]) == 2
    )
    error_message = "Solo workload y run leen los secretos de la aplicación."
  }
  assert {
    condition     = contains(keys(module.iam.bindings), "runtime/app/gke_nodes/roles/logging.logWriter")
    error_message = "La cuenta de nodos de GKE debe tener sus roles mínimos."
  }
  assert {
    condition     = !anytrue([for b in values(module.iam.bindings) : b.role == "roles/artifactregistry.reader"])
    error_message = "artifactregistry.reader va sobre el repositorio, no sobre el proyecto."
  }

  # Permisos de la etapa 5 en el proyecto de servicio (no en la carpeta del entorno).
  assert {
    condition = alltrue([
      for role in [
        "roles/backupdr.admin", "roles/certificatemanager.editor", "roles/cloudsql.admin", "roles/compute.instanceAdmin.v1",
        "roles/compute.loadBalancerAdmin", "roles/compute.securityAdmin", "roles/container.admin", "roles/file.editor",
        "roles/gkebackup.admin", "roles/monitoring.editor", "roles/redis.admin", "roles/run.admin", "roles/storage.admin",
        ] : module.iam.bindings["workloads/app/${role}"] == {
        scope    = "project"
        resource = "bnt-dev-app"
        role     = role
        member   = "serviceAccount:bnt-tf-5-workloads@bnt-bootstrap-seed.iam.gserviceaccount.com"
      }
    ])
    error_message = "La cuenta de la etapa 5 debe recibir en el proyecto de servicio los roles de las cargas que crea."
  }
  assert {
    condition = (
      module.iam.bindings["workloads/app/roles/resourcemanager.projectIamAdmin"].resource == "bnt-dev-app" &&
      module.iam.conditions["workloads/app/roles/resourcemanager.projectIamAdmin"].expression == "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly(['roles/cloudsql.client', 'roles/cloudsql.instanceUser'])"
    )
    error_message = "projectIamAdmin de la etapa 5 debe limitarse a otorgar cloudsql.client y cloudsql.instanceUser."
  }
  assert {
    condition     = !anytrue([for b in values(module.iam.bindings) : b.member == "serviceAccount:bnt-tf-5-workloads@bnt-bootstrap-seed.iam.gserviceaccount.com" && b.scope == "project" && b.resource == "bnt-dev-net-spoke" && b.role != "roles/compute.networkViewer"])
    error_message = "En el host la etapa 5 solo recibe networkViewer (el uso de subredes va por subred)."
  }
  assert {
    condition     = module.iam.bindings["host/workloads"].role == "roles/compute.networkViewer" && module.iam.bindings["host/workloads"].resource == "bnt-dev-net-spoke"
    error_message = "La etapa 5 necesita compute.networks.list/get en el host (Memorystore, Cloud SQL y Filestore por PSA)."
  }

  # Workload Identity: la etapa 5 administra la política IAM de la cuenta workload y de ninguna otra.
  assert {
    condition = (
      module.iam.bindings["saadmin/app/workload"].scope == "service_account" &&
      module.iam.bindings["saadmin/app/workload"].role == "roles/iam.serviceAccountAdmin" &&
      module.iam.bindings["saadmin/app/workload"].member == "serviceAccount:bnt-tf-5-workloads@bnt-bootstrap-seed.iam.gserviceaccount.com" &&
      length([for b in values(module.iam.bindings) : b if b.role == "roles/iam.serviceAccountAdmin"]) == 1
    )
    error_message = "serviceAccountAdmin solo sobre la cuenta workload de cada aplicación."
  }

  # Cloud Run con salida directa a la VPC en Shared VPC: networkViewer del agente en el host.
  assert {
    condition = module.iam.bindings["host/app/run"] == {
      scope    = "project"
      resource = "bnt-dev-net-spoke"
      role     = "roles/compute.networkViewer"
      member   = "serviceAccount:service-123456789012@serverless-robot-prod.iam.gserviceaccount.com"
    }
    error_message = "El agente de Cloud Run debe tener compute.networkViewer en el host de la Shared VPC."
  }

  # Artifact Registry: repositorio multirregional con CMEK y lectores.
  assert {
    condition = (
      google_artifact_registry_repository.this["app"].repository_id == "bnt-dev-app-app-images-us" &&
      google_artifact_registry_repository.this["app"].location == "us" &&
      google_artifact_registry_repository.this["app"].format == "DOCKER" &&
      google_artifact_registry_repository.this["app"].kms_key_name == "projects/bnt-common-security/locations/us/keyRings/bnt-dev-sec-us/cryptoKeys/bnt-dev-sec-artifacts"
    )
    error_message = "Un repositorio Docker por aplicación en la multirregión, cifrado con kms_key_ids[env][us][artifacts]."
  }
  assert {
    condition     = module.iam.bindings["kms/app/us/artifacts/artifactregistry"].member == "serviceAccount:service-123456789012@gcp-sa-artifactregistry.iam.gserviceaccount.com" && !contains(keys(module.iam.bindings), "kms/app/us-central1/artifacts/artifactregistry")
    error_message = "El agente de Artifact Registry recibe solo la llave artifacts de la ubicación del repositorio."
  }
  assert {
    condition = (
      toset(keys(google_artifact_registry_repository_iam_member.reader)) == toset(["app/gke_nodes", "app/mig", "app/run_agent"]) &&
      google_artifact_registry_repository_iam_member.reader["app/run_agent"].member == "serviceAccount:service-123456789012@serverless-robot-prod.iam.gserviceaccount.com" &&
      alltrue([for r in google_artifact_registry_repository_iam_member.reader : r.role == "roles/artifactregistry.reader" && r.repository == "bnt-dev-app-app-images-us"])
    )
    error_message = "Nodos de GKE, MIG y el agente de Cloud Run leen el repositorio de su aplicación."
  }
  assert {
    condition     = output.artifact_registry_repositories == { app = "us-docker.pkg.dev/bnt-dev-app/bnt-dev-app-app-images-us" }
    error_message = "artifact_registry_repositories debe dar la URL Docker del repositorio."
  }

  # Binary Authorization: niega todo salvo el repositorio de la aplicación.
  assert {
    condition = (
      google_binary_authorization_policy.this["app"].project == "bnt-dev-app" &&
      google_binary_authorization_policy.this["app"].global_policy_evaluation_mode == "ENABLE" &&
      google_binary_authorization_policy.this["app"].default_admission_rule[0].evaluation_mode == "ALWAYS_DENY" &&
      google_binary_authorization_policy.this["app"].default_admission_rule[0].enforcement_mode == "ENFORCED_BLOCK_AND_AUDIT_LOG" &&
      [for p in google_binary_authorization_policy.this["app"].admission_whitelist_patterns : p.name_pattern] == ["us-docker.pkg.dev/bnt-dev-app/bnt-dev-app-app-images-us/**"]
    )
    error_message = "La política de Binary Authorization debe negar todo salvo el repositorio de la aplicación y aplicarse con bloqueo."
  }
  assert {
    condition     = alltrue([for k in ["gke_nodes", "workload", "mig", "run"] : module.iam.bindings["actas/app/${k}"].member == "serviceAccount:bnt-tf-5-workloads@bnt-bootstrap-seed.iam.gserviceaccount.com"])
    error_message = "El pipeline de la etapa 5 debe poder adjuntar cada cuenta de ejecución."
  }
  assert {
    condition     = alltrue([for b in values(module.iam.bindings) : !startswith(b.member, "user:")])
    error_message = "Ningún permiso a user:."
  }

  # Etiquetas seguras.
  assert {
    condition = toset(keys(google_tags_tag_value_iam_member.tag_user)) == toset([
      "lb_backend/workloads", "iap_ssh/workloads",
      "lb_backend/app/apis", "lb_backend/app/gke", "iap_ssh/app/apis", "iap_ssh/app/gke",
    ])
    error_message = "tagUser debe darse al pipeline de la etapa 5 y a los agentes que crean VM y nodos."
  }
  assert {
    condition     = google_tags_tag_value_iam_member.tag_user["lb_backend/workloads"].tag_value == "tagValues/000000000101" && google_tags_tag_value_iam_member.tag_user["lb_backend/workloads"].role == "roles/resourcemanager.tagUser"
    error_message = "tagUser va sobre el valor de etiqueta del estado del spoke."
  }

  # Fuera de prod no se toca el perímetro.
  assert {
    condition     = length(google_access_context_manager_service_perimeter_resource.this) == 0 && length(google_access_context_manager_service_perimeter_dry_run_resource.this) == 0 && length(data.google_project.host) == 0
    error_message = "Solo prod se agrega al perímetro (ni servicio ni host)."
  }
}

run "prod_perimetro_en_dry_run_y_dr" {
  command = plan

  variables {
    environment     = "prod"
    deletion_policy = "PREVENT"
  }

  override_data {
    target          = data.terraform_remote_state.network
    override_during = plan
    values = {
      outputs = {
        host_project_id   = "bnt-prod-net-spoke"
        network_name      = "bnt-prod-net-vpc"
        network_self_link = "https://www.googleapis.com/compute/v1/projects/bnt-prod-net-spoke/global/networks/bnt-prod-net-vpc"
        subnets = {
          for k, s in {
            app    = { region = "us-central1", code = "usc1" }
            app_dr = { region = "us-east4", code = "use4" }
            run    = { region = "us-central1", code = "usc1" }
            run_dr = { region = "us-east4", code = "use4" }
            } : k => {
            name             = "bnt-prod-net-${trimsuffix(k, "_dr")}-${s.code}"
            region           = s.region
            cidr             = "10.30.0.0/24"
            secondary_ranges = {}
            self_link        = "https://www.googleapis.com/compute/v1/projects/bnt-prod-net-spoke/regions/${s.region}/subnetworks/bnt-prod-net-${trimsuffix(k, "_dr")}-${s.code}"
          }
        }
        psa_range_name = "bnt-prod-net-psa"
        secure_tags = {
          lb_backend = "tagValues/000000000301"
          iap_ssh    = "tagValues/000000000302"
        }
        secure_tag_keys = {
          lb_backend = "tagKeys/000000000401"
          iap_ssh    = "tagKeys/000000000402"
        }
      }
    }
  }

  assert {
    condition     = output.service_project_ids == { app = "bnt-prod-app" }
    error_message = "El proyecto de prod debe llamarse bnt-prod-app."
  }
  assert {
    condition     = length(google_access_context_manager_service_perimeter_resource.this) == 0
    error_message = "Con vpc_sc_enforced = false no se usa el recurso de alta forzada."
  }
  assert {
    condition = google_access_context_manager_service_perimeter_dry_run_resource.this["service/app"].resource == "projects/123456789012" && (
      google_access_context_manager_service_perimeter_dry_run_resource.this["service/app"].perimeter_name == "accessPolicies/000000000000/servicePerimeters/bnt_prod_sec_perimeter"
    )
    error_message = "En dry-run el proyecto de servicio entra al spec del perímetro de 2-security como projects/<número>."
  }
  assert {
    condition     = google_access_context_manager_service_perimeter_dry_run_resource.this["host"].resource == "projects/987654321098" && data.google_project.host["host"].project_id == "bnt-prod-net-spoke"
    error_message = "El proyecto host del spoke debe entrar al mismo perímetro (VPC-SC exige host y servicio juntos)."
  }
  assert {
    condition     = length(google_access_context_manager_service_perimeter_dry_run_resource.this) == 2
    error_message = "En prod entran al perímetro solo el proyecto de servicio y el host."
  }
  assert {
    condition     = module.iam.bindings["subnet/app/app_dr/gke"].resource == "projects/bnt-prod-net-spoke/regions/us-east4/subnetworks/bnt-prod-net-app-use4"
    error_message = "Con subredes de DR en el estado, los agentes reciben networkUser también en ellas."
  }
  assert {
    condition     = contains(keys(module.iam.bindings), "subnet/app/run_dr/run") && contains(keys(module.iam.bindings), "subnet/workloads/app_dr")
    error_message = "El agente de Cloud Run y el pipeline deben poder usar las subredes de DR."
  }
}

run "prod_perimetro_forzado" {
  command = plan

  variables {
    environment     = "prod"
    deletion_policy = "PREVENT"
  }

  override_data {
    target          = data.terraform_remote_state.security
    override_during = plan
    values = {
      outputs = {
        kms_key_ids = {
          prod = {
            for loc in ["us-central1", "us-east4", "us"] : loc => {
              for use in ["gke", "compute", "sql", "storage", "filestore", "redis", "secrets", "backup", "run", "artifacts"] :
              use => "projects/bnt-common-security/locations/${loc}/keyRings/bnt-prod-sec-${loc}/cryptoKeys/bnt-prod-sec-${use}"
            }
          }
        }
        secret_ids       = { prod = { db-app = "projects/bnt-common-security/secrets/bnt-prod-sec-db-app" } }
        access_policy_id = "000000000000"
        perimeter_name   = "accessPolicies/000000000000/servicePerimeters/bnt_prod_sec_perimeter"
        vpc_sc_enforced  = true
      }
    }
  }

  assert {
    condition     = google_access_context_manager_service_perimeter_resource.this["service/app"].resource == "projects/123456789012" && google_access_context_manager_service_perimeter_resource.this["host"].resource == "projects/987654321098" && length(google_access_context_manager_service_perimeter_dry_run_resource.this) == 0
    error_message = "Con vpc_sc_enforced = true el proyecto entra con el recurso de alta forzada."
  }
}

run "varias_aplicaciones" {
  command = plan

  variables {
    applications = {
      app = {}
      pay = { secrets = ["api"] }
    }
  }

  assert {
    condition     = output.service_project_ids == { app = "bnt-dev-app", pay = "bnt-dev-pay" }
    error_message = "Un proyecto de servicio por aplicación."
  }
  assert {
    condition     = length(google_service_account.runtime) == 8 && contains(keys(module.iam.bindings), "secret/pay/api/run") && !anytrue([for k in keys(module.iam.bindings) : startswith(k, "secret/app/")])
    error_message = "Cuentas y secretos por aplicación."
  }
  assert {
    condition     = length(google_tags_tag_value_iam_member.tag_user) == 10
    error_message = "tagUser del pipeline una vez por etiqueta y de los agentes por aplicación."
  }
}

run "binary_authorization_con_atestadores_y_patrones" {
  command = plan

  variables {
    binary_authorization_allowlist_patterns = ["us-docker.pkg.dev/bnt-common-images/base/**"]
    binary_authorization_attestors          = ["projects/bnt-common-security/attestors/ci-build"]
  }

  assert {
    condition = (
      google_binary_authorization_policy.this["app"].default_admission_rule[0].evaluation_mode == "REQUIRE_ATTESTATION" &&
      google_binary_authorization_policy.this["app"].default_admission_rule[0].require_attestations_by == toset(["projects/bnt-common-security/attestors/ci-build"]) &&
      [for p in google_binary_authorization_policy.this["app"].admission_whitelist_patterns : p.name_pattern] == [
        "us-docker.pkg.dev/bnt-dev-app/bnt-dev-app-app-images-us/**",
        "us-docker.pkg.dev/bnt-common-images/base/**",
      ]
    )
    error_message = "Con atestadores la regla por defecto exige atestación y los patrones extra se suman al repositorio propio."
  }
}

run "rechaza_patron_que_admite_todo" {
  command = plan

  variables {
    binary_authorization_allowlist_patterns = ["*"]
  }

  expect_failures = [var.binary_authorization_allowlist_patterns]
}

run "rechaza_patron_de_registro_entero" {
  command = plan

  variables {
    binary_authorization_allowlist_patterns = ["gcr.io/*"]
  }

  expect_failures = [var.binary_authorization_allowlist_patterns]
}

run "rechaza_patron_que_cubre_otros_proyectos" {
  command = plan

  variables {
    binary_authorization_allowlist_patterns = ["us-docker.pkg.dev/bnt-prod-app**"]
  }

  expect_failures = [var.binary_authorization_allowlist_patterns]
}

run "rechaza_estado_sin_llave_de_artefactos" {
  command = plan

  variables {
    artifact_registry_location = "eu"
  }

  expect_failures = [data.terraform_remote_state.security]
}

run "rechaza_nombre_de_cuenta_largo" {
  command = plan

  variables {
    applications = { paymentsapp01 = {} }
  }

  expect_failures = [var.applications]
}

run "rechaza_secreto_inexistente" {
  command = plan

  variables {
    applications = { app = { secrets = ["no-existe"] } }
  }

  expect_failures = [data.terraform_remote_state.security]
}

run "rechaza_carpeta_de_otra_organizacion" {
  command = plan

  variables {
    org_id = "999999999999"
  }

  expect_failures = [data.google_folder.env]
}

run "rechaza_cuenta_de_pipeline_invalida" {
  command = plan

  variables {
    workloads_service_account = "user@example.com"
  }

  expect_failures = [var.workloads_service_account]
}

run "rechaza_cuenta_de_otra_etapa" {
  command = plan

  variables {
    workloads_service_account = "bnt-tf-4-projects@bnt-bootstrap-seed.iam.gserviceaccount.com"
  }

  expect_failures = [var.workloads_service_account]
}

# Valores desconocidos en el plan (primer apply): todas las llaves de for_each deben conocerse
# aunque los números de proyecto, los correos de las cuentas y de los agentes no se conozcan.
run "primer_apply_con_valores_desconocidos" {
  command = plan

  providers = {
    google      = google.primer_apply
    google-beta = google-beta.primer_apply
  }

  variables {
    environment     = "prod"
    deletion_policy = "PREVENT"
    applications = {
      app = { secrets = ["db-app"] }
      pay = { secrets = ["api"] }
    }
  }

  override_data {
    target          = data.terraform_remote_state.network
    override_during = plan
    values = {
      outputs = {
        host_project_id   = "bnt-prod-net-spoke"
        network_name      = "bnt-prod-net-vpc"
        network_self_link = "https://www.googleapis.com/compute/v1/projects/bnt-prod-net-spoke/global/networks/bnt-prod-net-vpc"
        subnets = {
          for k, s in {
            app    = { region = "us-central1", code = "usc1" }
            app_dr = { region = "us-east4", code = "use4" }
            run    = { region = "us-central1", code = "usc1" }
            run_dr = { region = "us-east4", code = "use4" }
            } : k => {
            name             = "bnt-prod-net-${trimsuffix(k, "_dr")}-${s.code}"
            region           = s.region
            cidr             = "10.30.0.0/24"
            secondary_ranges = {}
            self_link        = "https://www.googleapis.com/compute/v1/projects/bnt-prod-net-spoke/regions/${s.region}/subnetworks/bnt-prod-net-${trimsuffix(k, "_dr")}-${s.code}"
          }
        }
        psa_range_name = "bnt-prod-net-psa"
        secure_tags = {
          lb_backend = "tagValues/000000000301"
          iap_ssh    = "tagValues/000000000302"
        }
        secure_tag_keys = {
          lb_backend = "tagKeys/000000000401"
          iap_ssh    = "tagKeys/000000000402"
        }
      }
    }
  }

  assert {
    condition     = length(google_service_account.runtime) == 8 && length(google_project_service_identity.this) == 10
    error_message = "Cuentas de ejecución y agentes: llaves conocidas en el plan."
  }
  assert {
    condition = (
      length(google_artifact_registry_repository_iam_member.reader) == 6 && length(google_binary_authorization_policy.this) == 2 &&
      alltrue([for k in ["host/pay/run", "host/workloads", "saadmin/pay/workload", "workloads/pay/roles/run.admin", "kms/pay/us/artifacts/artifactregistry"] : contains(keys(module.iam.bindings), k)])
    )
    error_message = "Repositorios, lectores, políticas y permisos nuevos: llaves conocidas en el plan."
  }
  assert {
    condition     = length(google_tags_tag_value_iam_member.tag_user) == 10
    error_message = "tagUser: llaves conocidas aunque los correos de los agentes no lo sean."
  }
  assert {
    condition     = contains(keys(module.iam.bindings), "kms/pay/us-east4/gke/compute") && contains(keys(module.iam.bindings), "actas/pay/run") && contains(keys(module.iam.bindings), "host/app/gke")
    error_message = "Las llaves del módulo iam deben conocerse en el plan (key explícita)."
  }
  assert {
    condition     = toset(keys(google_access_context_manager_service_perimeter_dry_run_resource.this)) == toset(["service/app", "service/pay", "host"])
    error_message = "Altas en el perímetro con llaves estables aunque los números de proyecto no se conozcan."
  }
}
