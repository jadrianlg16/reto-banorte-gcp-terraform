# Pruebas sin GCP de la etapa 5 (idénticas en dev, qa y prod): proveedores simulados, solo plan
# y salidas de las etapas 2, 3 y 4 simuladas con la forma exacta de §7.2, §7.4 y §7.5. Los
# escenarios fijan el entorno por variables, así que no dependen de la raíz donde corren.

mock_provider "google" {
  # Valores con el formato que validan los módulos (los simulados serían cadenas al azar).
  mock_resource "google_container_cluster" {
    defaults = {
      id = "projects/example-svc-app/locations/us-central1/clusters/bnt-prod-app-gke-usc1"
    }
  }
}

mock_provider "google-beta" {}

# §7.2 (2-security): kms_key_ids[entorno][ubicación][uso].
override_data {
  target = data.terraform_remote_state.security
  values = {
    outputs = {
      kms_key_ids = {
        prod = {
          "us-central1" = {
            gke       = "projects/example-security/locations/us-central1/keyRings/bnt-prod-sec-kr-usc1/cryptoKeys/gke"
            compute   = "projects/example-security/locations/us-central1/keyRings/bnt-prod-sec-kr-usc1/cryptoKeys/compute"
            sql       = "projects/example-security/locations/us-central1/keyRings/bnt-prod-sec-kr-usc1/cryptoKeys/sql"
            storage   = "projects/example-security/locations/us-central1/keyRings/bnt-prod-sec-kr-usc1/cryptoKeys/storage"
            filestore = "projects/example-security/locations/us-central1/keyRings/bnt-prod-sec-kr-usc1/cryptoKeys/filestore"
            redis     = "projects/example-security/locations/us-central1/keyRings/bnt-prod-sec-kr-usc1/cryptoKeys/redis"
            secrets   = "projects/example-security/locations/us-central1/keyRings/bnt-prod-sec-kr-usc1/cryptoKeys/secrets"
            backup    = "projects/example-security/locations/us-central1/keyRings/bnt-prod-sec-kr-usc1/cryptoKeys/backup"
            run       = "projects/example-security/locations/us-central1/keyRings/bnt-prod-sec-kr-usc1/cryptoKeys/run"
          }
          "us-east4" = {
            gke       = "projects/example-security/locations/us-east4/keyRings/bnt-prod-sec-kr-use4/cryptoKeys/gke"
            compute   = "projects/example-security/locations/us-east4/keyRings/bnt-prod-sec-kr-use4/cryptoKeys/compute"
            sql       = "projects/example-security/locations/us-east4/keyRings/bnt-prod-sec-kr-use4/cryptoKeys/sql"
            storage   = "projects/example-security/locations/us-east4/keyRings/bnt-prod-sec-kr-use4/cryptoKeys/storage"
            filestore = "projects/example-security/locations/us-east4/keyRings/bnt-prod-sec-kr-use4/cryptoKeys/filestore"
            redis     = "projects/example-security/locations/us-east4/keyRings/bnt-prod-sec-kr-use4/cryptoKeys/redis"
            secrets   = "projects/example-security/locations/us-east4/keyRings/bnt-prod-sec-kr-use4/cryptoKeys/secrets"
            backup    = "projects/example-security/locations/us-east4/keyRings/bnt-prod-sec-kr-use4/cryptoKeys/backup"
            run       = "projects/example-security/locations/us-east4/keyRings/bnt-prod-sec-kr-use4/cryptoKeys/run"
          }
          us = {
            storage = "projects/example-security/locations/us/keyRings/bnt-prod-sec-kr-us/cryptoKeys/storage"
            backup  = "projects/example-security/locations/us/keyRings/bnt-prod-sec-kr-us/cryptoKeys/backup"
          }
        }
        qa = {
          "us-central1" = {
            gke       = "projects/example-security/locations/us-central1/keyRings/bnt-qa-sec-kr-usc1/cryptoKeys/gke"
            compute   = "projects/example-security/locations/us-central1/keyRings/bnt-qa-sec-kr-usc1/cryptoKeys/compute"
            sql       = "projects/example-security/locations/us-central1/keyRings/bnt-qa-sec-kr-usc1/cryptoKeys/sql"
            storage   = "projects/example-security/locations/us-central1/keyRings/bnt-qa-sec-kr-usc1/cryptoKeys/storage"
            filestore = "projects/example-security/locations/us-central1/keyRings/bnt-qa-sec-kr-usc1/cryptoKeys/filestore"
            redis     = "projects/example-security/locations/us-central1/keyRings/bnt-qa-sec-kr-usc1/cryptoKeys/redis"
            secrets   = "projects/example-security/locations/us-central1/keyRings/bnt-qa-sec-kr-usc1/cryptoKeys/secrets"
            backup    = "projects/example-security/locations/us-central1/keyRings/bnt-qa-sec-kr-usc1/cryptoKeys/backup"
            run       = "projects/example-security/locations/us-central1/keyRings/bnt-qa-sec-kr-usc1/cryptoKeys/run"
          }
          "us-east4" = {
            gke       = "projects/example-security/locations/us-east4/keyRings/bnt-qa-sec-kr-use4/cryptoKeys/gke"
            compute   = "projects/example-security/locations/us-east4/keyRings/bnt-qa-sec-kr-use4/cryptoKeys/compute"
            sql       = "projects/example-security/locations/us-east4/keyRings/bnt-qa-sec-kr-use4/cryptoKeys/sql"
            storage   = "projects/example-security/locations/us-east4/keyRings/bnt-qa-sec-kr-use4/cryptoKeys/storage"
            filestore = "projects/example-security/locations/us-east4/keyRings/bnt-qa-sec-kr-use4/cryptoKeys/filestore"
            redis     = "projects/example-security/locations/us-east4/keyRings/bnt-qa-sec-kr-use4/cryptoKeys/redis"
            secrets   = "projects/example-security/locations/us-east4/keyRings/bnt-qa-sec-kr-use4/cryptoKeys/secrets"
            backup    = "projects/example-security/locations/us-east4/keyRings/bnt-qa-sec-kr-use4/cryptoKeys/backup"
            run       = "projects/example-security/locations/us-east4/keyRings/bnt-qa-sec-kr-use4/cryptoKeys/run"
          }
          us = {
            storage = "projects/example-security/locations/us/keyRings/bnt-qa-sec-kr-us/cryptoKeys/storage"
            backup  = "projects/example-security/locations/us/keyRings/bnt-qa-sec-kr-us/cryptoKeys/backup"
          }
        }
        dev = {
          "us-central1" = {
            gke       = "projects/example-security/locations/us-central1/keyRings/bnt-dev-sec-kr-usc1/cryptoKeys/gke"
            compute   = "projects/example-security/locations/us-central1/keyRings/bnt-dev-sec-kr-usc1/cryptoKeys/compute"
            sql       = "projects/example-security/locations/us-central1/keyRings/bnt-dev-sec-kr-usc1/cryptoKeys/sql"
            storage   = "projects/example-security/locations/us-central1/keyRings/bnt-dev-sec-kr-usc1/cryptoKeys/storage"
            filestore = "projects/example-security/locations/us-central1/keyRings/bnt-dev-sec-kr-usc1/cryptoKeys/filestore"
            redis     = "projects/example-security/locations/us-central1/keyRings/bnt-dev-sec-kr-usc1/cryptoKeys/redis"
            secrets   = "projects/example-security/locations/us-central1/keyRings/bnt-dev-sec-kr-usc1/cryptoKeys/secrets"
            backup    = "projects/example-security/locations/us-central1/keyRings/bnt-dev-sec-kr-usc1/cryptoKeys/backup"
            run       = "projects/example-security/locations/us-central1/keyRings/bnt-dev-sec-kr-usc1/cryptoKeys/run"
          }
          "us-east4" = {
            gke       = "projects/example-security/locations/us-east4/keyRings/bnt-dev-sec-kr-use4/cryptoKeys/gke"
            compute   = "projects/example-security/locations/us-east4/keyRings/bnt-dev-sec-kr-use4/cryptoKeys/compute"
            sql       = "projects/example-security/locations/us-east4/keyRings/bnt-dev-sec-kr-use4/cryptoKeys/sql"
            storage   = "projects/example-security/locations/us-east4/keyRings/bnt-dev-sec-kr-use4/cryptoKeys/storage"
            filestore = "projects/example-security/locations/us-east4/keyRings/bnt-dev-sec-kr-use4/cryptoKeys/filestore"
            redis     = "projects/example-security/locations/us-east4/keyRings/bnt-dev-sec-kr-use4/cryptoKeys/redis"
            secrets   = "projects/example-security/locations/us-east4/keyRings/bnt-dev-sec-kr-use4/cryptoKeys/secrets"
            backup    = "projects/example-security/locations/us-east4/keyRings/bnt-dev-sec-kr-use4/cryptoKeys/backup"
            run       = "projects/example-security/locations/us-east4/keyRings/bnt-dev-sec-kr-use4/cryptoKeys/run"
          }
          us = {
            storage = "projects/example-security/locations/us/keyRings/bnt-dev-sec-kr-us/cryptoKeys/storage"
            backup  = "projects/example-security/locations/us/keyRings/bnt-dev-sec-kr-us/cryptoKeys/backup"
          }
        }
      }
      secret_ids       = { prod = {}, qa = {}, dev = {} }
      access_policy_id = "000000000000"
      perimeter_name   = "accessPolicies/000000000000/servicePerimeters/bnt_prod"
      vpc_sc_enforced  = false
    }
  }
}

# §7.4 (3-networks/<env>): spoke con DR (las llaves *_dr existen).
override_data {
  target = data.terraform_remote_state.network
  values = {
    outputs = {
      host_project_id   = "example-net-spoke"
      network_name      = "bnt-net-vpc"
      network_self_link = "https://www.googleapis.com/compute/v1/projects/example-net-spoke/global/networks/bnt-net-vpc"
      subnets = {
        app = {
          self_link        = "https://www.googleapis.com/compute/v1/projects/example-net-spoke/regions/us-central1/subnetworks/bnt-net-app-usc1"
          name             = "bnt-net-app-usc1"
          region           = "us-central1"
          cidr             = "10.30.0.0/20"
          secondary_ranges = { pods = "10.30.64.0/18", services = "10.30.128.0/20" }
        }
        app_dr = {
          self_link        = "https://www.googleapis.com/compute/v1/projects/example-net-spoke/regions/us-east4/subnetworks/bnt-net-app-use4"
          name             = "bnt-net-app-use4"
          region           = "us-east4"
          cidr             = "10.30.16.0/20"
          secondary_ranges = { pods = "10.30.192.0/18", services = "10.30.160.0/20" }
        }
        run = {
          self_link        = "https://www.googleapis.com/compute/v1/projects/example-net-spoke/regions/us-central1/subnetworks/bnt-net-run-usc1"
          name             = "bnt-net-run-usc1"
          region           = "us-central1"
          cidr             = "10.30.36.0/24"
          secondary_ranges = {}
        }
        run_dr = {
          self_link        = "https://www.googleapis.com/compute/v1/projects/example-net-spoke/regions/us-east4/subnetworks/bnt-net-run-use4"
          name             = "bnt-net-run-use4"
          region           = "us-east4"
          cidr             = "10.30.37.0/24"
          secondary_ranges = {}
        }
        proxy = {
          self_link        = "https://www.googleapis.com/compute/v1/projects/example-net-spoke/regions/us-central1/subnetworks/bnt-net-proxy-usc1"
          name             = "bnt-net-proxy-usc1"
          region           = "us-central1"
          cidr             = "10.30.32.0/23"
          secondary_ranges = {}
        }
        proxy_dr = {
          self_link        = "https://www.googleapis.com/compute/v1/projects/example-net-spoke/regions/us-east4/subnetworks/bnt-net-proxy-use4"
          name             = "bnt-net-proxy-use4"
          region           = "us-east4"
          cidr             = "10.30.34.0/23"
          secondary_ranges = {}
        }
      }
      psa_range_name   = "bnt-net-psa"
      secure_tags      = { lb_backend = "tagValues/111111", iap_ssh = "tagValues/222222" }
      secure_tag_keys  = { lb_backend = "tagKeys/333333", iap_ssh = "tagKeys/444444" }
      reserved_cidrs   = { gke_master = "10.30.38.0/28", gke_master_dr = "10.30.38.16/28" }
      lb_backend_ports = ["80", "443", "8080"]
    }
  }
}

# §7.5 (4-projects/<env>).
override_data {
  target = data.terraform_remote_state.projects
  values = {
    outputs = {
      service_project_ids     = { app = "example-svc-app" }
      service_project_numbers = { app = "000000000000" }
      service_accounts = {
        app = {
          gke_nodes = "bnt-app-gke-nodes@example-svc-app.iam.gserviceaccount.com"
          workload  = "bnt-app-workload@example-svc-app.iam.gserviceaccount.com"
          mig       = "bnt-app-mig@example-svc-app.iam.gserviceaccount.com"
          run       = "bnt-app-run@example-svc-app.iam.gserviceaccount.com"
        }
      }
      # enable_off_hours_shutdown de 4-projects (dev y qa).
      scheduler_service_accounts = {
        app = "bnt-app-sched@example-svc-app.iam.gserviceaccount.com"
      }
    }
  }
}

# Valores de terraform.tfvars.example de prod.
variables {
  prefix       = "bnt"
  environment  = "prod"
  application  = "app"
  state_bucket = "bnt-bootstrap-tfstate-000000000000"

  primary_region = "us-central1"
  dr_region      = "us-east4"
  enable_dr      = true
  dr_active      = false

  enable_gke         = true
  enable_mig         = true
  enable_cloud_run   = true
  enable_filestore   = true
  enable_memorystore = true
  enable_internal_lb = true
  enable_backup      = true

  gke_authenticator_security_group = "gke-security-groups@example.com"
  gke_release_channel              = "STABLE"
  gke_master_authorized_networks   = [{ cidr_block = "192.168.0.0/16", display_name = "onprem" }]
  gke_node_pools = {
    general = {
      machine_type   = "e2-standard-4"
      min_node_count = 1
      max_node_count = 3
    }
  }
  gke_lb_negs = {
    primary = []
    dr      = []
  }

  mig_image        = "projects/example-images/global/images/family/app-hardened"
  mig_machine_type = "e2-standard-2"
  mig_min_replicas = 2
  mig_max_replicas = 6

  cloud_run_image = "us-docker.pkg.dev/example-svc-app/bnt-prod-app-app-images-us/api:1.0.0"

  sql_tier             = "db-custom-2-7680"
  sql_database_version = "POSTGRES_16"
  sql_databases        = ["app"]

  memorystore_memory_gb = 5
  filestore_tier        = "REGIONAL"
  filestore_capacity_gb = 1024

  domain_names          = ["app.example.com"]
  internal_domain_names = ["app.prod.example.com"]
  lb_backend_paths      = { mig = ["/legacy/*"] }

  notification_emails = ["alertas-prod@example.com"]

  labels = {
    app         = "app"
    owner       = "plataforma"
    cost_center = "ti-001"
  }
}

run "prod_operacion_normal" {
  command = plan

  # Cómputo solo en la región primaria y nombres de §4.2.
  assert {
    condition     = output.gke_cluster_names == { "us-central1" = "bnt-prod-app-gke-usc1" }
    error_message = "Sin dr_active debe haber un solo clúster, en la región primaria, con el nombre de §4.2."
  }
  assert {
    condition     = keys(module.mig) == ["primary"] && module.mig["primary"].instance_group_manager_name == "bnt-prod-app-mig-usc1"
    error_message = "El MIG debe existir solo en la región primaria con el nombre de §4.2."
  }
  assert {
    condition     = keys(module.cloud_run) == ["primary"] && module.cloud_run["primary"].service_name == "bnt-prod-app-run-usc1"
    error_message = "Cloud Run debe existir solo en la región primaria con el nombre de §4.2."
  }
  assert {
    condition     = output.active_region == "us-central1"
    error_message = "Sin dr_active el tráfico va a la región primaria."
  }

  # El plano de control de GKE usa el /28 que publica la etapa 3 (reserved_cidrs).
  assert {
    condition     = module.gke["primary"].master_cidr == "10.30.38.0/28"
    error_message = "master_cidr del clúster primario debe salir de reserved_cidrs[\"gke_master\"] de la etapa 3."
  }

  # Etiquetas de §4.3.
  assert {
    condition     = local.labels == { app = "app", owner = "plataforma", cost_center = "ti-001", env = "prod", managed_by = "terraform" }
    error_message = "local.labels debe tener app, owner, cost_center, env y managed_by."
  }
  # Etiquetas seguras de la etapa 3 en el MIG y en los nodos de GKE.
  assert {
    condition     = local.mig_secure_tags == { "tagKeys/333333" = "tagValues/111111", "tagKeys/444444" = "tagValues/222222" }
    error_message = "El MIG debe llevar lb_backend e iap_ssh como tagKeys → tagValues."
  }
  assert {
    condition     = local.gke_node_secure_tags == { "tagKeys/333333" = "tagValues/111111" }
    error_message = "Los nodos de GKE deben llevar lb_backend."
  }

  # Datos con DR: réplica de Cloud SQL y bucket de doble región con turbo replication.
  assert {
    condition     = module.cloud_sql.instance_name == "bnt-prod-data-sql-usc1" && module.cloud_sql.replica_name == "bnt-prod-data-sql-use4"
    error_message = "Con enable_dr debe existir la réplica de Cloud SQL en la región de DR."
  }
  assert {
    condition     = output.bucket_names == { data = "bnt-prod-data-app-usc1-use4" }
    error_message = "Con enable_dr el bucket debe ser de doble región (usc1-use4)."
  }
  assert {
    condition     = join(",", module.storage.data_locations) == "US-CENTRAL1,US-EAST4" && module.storage.location == "US"
    error_message = "El bucket de doble región debe estar en la multirregión US con las dos regiones."
  }
  assert {
    condition     = keys(module.memorystore) == ["primary"] && keys(module.filestore) == ["primary"]
    error_message = "Memorystore y Filestore deben existir en la región primaria."
  }

  # Cloud SQL por IAM: las tres cuentas de ejecución con cómputo encendido son usuarios de la base.
  assert {
    condition = module.cloud_sql.iam_user_names == {
      "bnt-app-workload@example-svc-app.iam.gserviceaccount.com" = "bnt-app-workload@example-svc-app.iam"
      "bnt-app-run@example-svc-app.iam.gserviceaccount.com"      = "bnt-app-run@example-svc-app.iam"
      "bnt-app-mig@example-svc-app.iam.gserviceaccount.com"      = "bnt-app-mig@example-svc-app.iam"
    }
    error_message = "GKE (workload), Cloud Run (run) y el MIG (mig) deben entrar a Cloud SQL por IAM."
  }

  # Workload Identity: la cuenta de Kubernetes app/app actúa como la cuenta workload.
  assert {
    condition = (
      google_service_account_iam_member.workload_identity["workload"].service_account_id == "projects/example-svc-app/serviceAccounts/bnt-app-workload@example-svc-app.iam.gserviceaccount.com" &&
      google_service_account_iam_member.workload_identity["workload"].role == "roles/iam.workloadIdentityUser" &&
      google_service_account_iam_member.workload_identity["workload"].member == "serviceAccount:example-svc-app.svc.id.goog[app/app]"
    )
    error_message = "Debe existir el enlace de Workload Identity de app/app a la cuenta workload."
  }

  # Balanceador externo con Cloud Armor y backends de los cómputos habilitados (GKE sin NEG aún).
  assert {
    condition     = join(",", sort(keys(module.external_lb["external"].backend_service_ids))) == "mig,run"
    error_message = "El balanceador externo debe tener backends mig y run (gke entra cuando hay NEG)."
  }
  assert {
    condition     = module.external_lb["external"].url_map_name == "bnt-prod-app-app-xlb-um"
    error_message = "El mapa de URL externo no sigue el nombre de §4.2."
  }
  assert {
    condition     = module.cloud_armor["external"].policy_name == "bnt-prod-app-app-armor"
    error_message = "La política de Cloud Armor no sigue el nombre de §4.2."
  }
  assert {
    condition     = local.external_backends["run"].serverless && length(local.external_backends["run"].dr_groups) == 0
    error_message = "Cloud Run entra como NEG sin servidor y sin grupos de DR fuera de una conmutación."
  }
  # Balanceador interno solo en la región primaria.
  assert {
    condition     = keys(module.internal_lb) == ["primary"] && module.internal_lb["primary"].url_map_name == "bnt-prod-app-app-ilb-usc1-um"
    error_message = "Sin dr_active debe existir solo el balanceador interno de la región primaria."
  }

  # Observabilidad: verificación de disponibilidad sobre el primer dominio.
  assert {
    condition     = keys(module.observability.uptime_check_ids) == ["web"]
    error_message = "Debe existir la verificación de disponibilidad del dominio."
  }
  # Respaldo: plan de Cloud SQL y, con DR y GKE, plan de Backup for GKE.
  assert {
    condition     = join(",", sort(keys(module.backup["this"].plan_ids))) == "gke,sql"
    error_message = "Con enable_dr y GKE deben existir los planes sql y gke."
  }

  # Sin apagado fuera de horario en prod (ADR 0028): ni trabajos, ni pools "scheduled", ni
  # programa del MIG; ventana de respaldo por defecto.
  assert {
    condition     = length(module.off_hours_shutdown) == 0 && output.off_hours_shutdown == null
    error_message = "prod no tiene trabajos de apagado."
  }
  assert {
    condition     = module.gke["primary"].node_pools["general"].scheduled == false && module.gke["primary"].node_pools["general"].name == "bnt-prod-app-np-general"
    error_message = "En prod Terraform administra el autoscaling de los pools."
  }
  assert {
    condition     = module.mig["primary"].autoscaling.signal == "cpu" && module.mig["primary"].autoscaling.min_replicas == 2 && module.mig["primary"].autoscaling.scaling_schedules == {}
    error_message = "En prod el MIG autoescala por CPU con su mínimo y sin programas."
  }
  assert {
    condition     = local.backup_window == { start_hour = 1, time_zone = "America/Mexico_City" }
    error_message = "Sin apagado la ventana de respaldo es la del módulo backup-dr."
  }
}

# Conmutación con los NEG del clúster de DR ya declarados (paso 6 del runbook 04). Los grupos del
# MIG y de Cloud Run tienen valores fijos por región para comprobar qué grupo usa cada backend.
run "prod_conmutacion_a_dr" {
  command = plan

  variables {
    dr_active = true
    gke_lb_negs = {
      primary = ["projects/example-svc-app/zones/us-central1-a/networkEndpointGroups/k8s1-web"]
      dr      = ["projects/example-svc-app/zones/us-east4-a/networkEndpointGroups/k8s1-web"]
    }
  }

  override_resource {
    target          = google_certificate_manager_certificate.internal["primary"]
    override_during = plan
    values          = { id = "projects/example-svc-app/locations/us-central1/certificates/ilb-usc1" }
  }
  override_resource {
    target          = google_certificate_manager_certificate.internal["dr"]
    override_during = plan
    values          = { id = "projects/example-svc-app/locations/us-east4/certificates/ilb-use4" }
  }
  override_resource {
    target          = module.cloud_run["primary"].google_compute_region_network_endpoint_group.this
    override_during = plan
    values          = { id = "projects/example-svc-app/regions/us-central1/networkEndpointGroups/neg-usc1" }
  }
  override_resource {
    target          = module.cloud_run["dr"].google_compute_region_network_endpoint_group.this
    override_during = plan
    values          = { id = "projects/example-svc-app/regions/us-east4/networkEndpointGroups/neg-use4" }
  }
  override_resource {
    target          = module.mig["primary"].google_compute_region_instance_group_manager.this
    override_during = plan
    values          = { instance_group = "projects/example-svc-app/regions/us-central1/instanceGroups/mig-usc1" }
  }
  override_resource {
    target          = module.mig["dr"].google_compute_region_instance_group_manager.this
    override_during = plan
    values          = { instance_group = "projects/example-svc-app/regions/us-east4/instanceGroups/mig-use4" }
  }

  # El cómputo se agrega en la región de DR con sus nombres.
  assert {
    condition     = output.gke_cluster_names == { "us-central1" = "bnt-prod-app-gke-usc1", "us-east4" = "bnt-prod-app-gke-use4" }
    error_message = "Con dr_active debe existir el clúster de la región de DR."
  }
  assert {
    condition     = module.mig["dr"].instance_group_manager_name == "bnt-prod-app-mig-use4"
    error_message = "Con dr_active debe existir el MIG en la región de DR."
  }
  assert {
    condition     = module.cloud_run["dr"].service_name == "bnt-prod-app-run-use4"
    error_message = "Con dr_active debe existir Cloud Run en la región de DR."
  }
  assert {
    condition     = output.active_region == "us-east4"
    error_message = "Con dr_active el tráfico va a la región de DR."
  }

  # Cada cómputo de DR usa las subredes y las llaves KMS de la región de DR (y el primario las suyas).
  assert {
    condition = (
      module.gke["dr"].subnetwork == "https://www.googleapis.com/compute/v1/projects/example-net-spoke/regions/us-east4/subnetworks/bnt-net-app-use4" &&
      module.gke["dr"].kms_key == "projects/example-security/locations/us-east4/keyRings/bnt-prod-sec-kr-use4/cryptoKeys/gke" &&
      module.gke["dr"].master_cidr == "10.30.38.16/28" &&
      module.gke["primary"].subnetwork == "https://www.googleapis.com/compute/v1/projects/example-net-spoke/regions/us-central1/subnetworks/bnt-net-app-usc1" &&
      module.gke["primary"].master_cidr == "10.30.38.0/28"
    )
    error_message = "El clúster de DR debe usar app_dr, la llave gke de us-east4 y gke_master_dr; el primario, las suyas."
  }
  assert {
    condition = (
      module.mig["dr"].subnetwork == "https://www.googleapis.com/compute/v1/projects/example-net-spoke/regions/us-east4/subnetworks/bnt-net-app-use4" &&
      module.mig["dr"].kms_key == "projects/example-security/locations/us-east4/keyRings/bnt-prod-sec-kr-use4/cryptoKeys/compute" &&
      module.mig["primary"].kms_key == "projects/example-security/locations/us-central1/keyRings/bnt-prod-sec-kr-usc1/cryptoKeys/compute"
    )
    error_message = "El MIG de DR debe usar app_dr y la llave compute de us-east4."
  }
  assert {
    condition = (
      module.cloud_run["dr"].subnetwork == "projects/example-net-spoke/regions/us-east4/subnetworks/bnt-net-run-use4" &&
      module.cloud_run["dr"].kms_key == "projects/example-security/locations/us-east4/keyRings/bnt-prod-sec-kr-use4/cryptoKeys/run" &&
      module.cloud_run["primary"].subnetwork == "projects/example-net-spoke/regions/us-central1/subnetworks/bnt-net-run-usc1"
    )
    error_message = "Cloud Run de DR debe usar run_dr y la llave run de us-east4."
  }

  # Los servicios de backend del externo usan solo los grupos de la región de DR.
  assert {
    condition = module.external_lb["external"].backend_groups == {
      gke = tolist(["projects/example-svc-app/zones/us-east4-a/networkEndpointGroups/k8s1-web"])
      mig = tolist(["projects/example-svc-app/regions/us-east4/instanceGroups/mig-use4"])
      run = tolist(["projects/example-svc-app/regions/us-east4/networkEndpointGroups/neg-use4"])
    }
    error_message = "Con dr_active cada servicio de backend del externo debe tener solo el grupo de la región de DR."
  }

  # Balanceador interno por región: se agrega el de DR con los grupos de DR y el primario sigue
  # igual (mismo nombre y mismos grupos de la región primaria).
  assert {
    condition = (
      toset(keys(module.internal_lb)) == toset(["primary", "dr"]) &&
      module.internal_lb["primary"].url_map_name == "bnt-prod-app-app-ilb-usc1-um" &&
      module.internal_lb["dr"].url_map_name == "bnt-prod-app-app-ilb-use4-um"
    )
    error_message = "Con dr_active debe agregarse el balanceador interno de la región de DR sin tocar el primario."
  }
  assert {
    condition = (
      module.internal_lb["dr"].backend_groups == {
        mig = tolist(["projects/example-svc-app/regions/us-east4/instanceGroups/mig-use4"])
        run = tolist(["projects/example-svc-app/regions/us-east4/networkEndpointGroups/neg-use4"])
      } &&
      module.internal_lb["primary"].backend_groups == {
        mig = tolist(["projects/example-svc-app/regions/us-central1/instanceGroups/mig-usc1"])
        run = tolist(["projects/example-svc-app/regions/us-central1/networkEndpointGroups/neg-usc1"])
      }
    )
    error_message = "Cada balanceador interno debe usar los grupos de su propia región."
  }
  # Un proxy regional solo acepta un certificado de su región: cada interno recibe el suyo.
  assert {
    condition = (
      module.internal_lb["primary"].internal_certificate_ids == tolist(["projects/example-svc-app/locations/us-central1/certificates/ilb-usc1"]) &&
      module.internal_lb["dr"].internal_certificate_ids == tolist(["projects/example-svc-app/locations/us-east4/certificates/ilb-use4"])
    )
    error_message = "Cada balanceador interno debe recibir el certificado de su propia región."
  }
  # Los datos no se mueven: la primaria de Cloud SQL sigue igual (la réplica se promueve por runbook).
  assert {
    condition     = module.cloud_sql.instance_name == "bnt-prod-data-sql-usc1"
    error_message = "La conmutación no debe cambiar la instancia primaria de Cloud SQL."
  }
  # Un solo enlace de Workload Identity: el pool es del proyecto y sirve a los dos clústeres.
  assert {
    condition     = length(google_service_account_iam_member.workload_identity) == 1
    error_message = "El enlace de Workload Identity es uno por proyecto, no por clúster."
  }
}

# Paso 5 del runbook 04 con los tfvars normales: NEG de GKE solo en primary (los de DR no existen
# todavía). Debe planear: GKE sale del externo hasta que se llenen los NEG de DR.
run "prod_conmutacion_sin_neg_de_dr" {
  command = plan

  variables {
    dr_active          = true
    lb_default_backend = "gke"
    lb_backend_paths   = { gke = ["/k8s/*"], mig = ["/legacy/*"] }
    gke_lb_negs = {
      primary = ["projects/example-svc-app/zones/us-central1-a/networkEndpointGroups/k8s1-web"]
    }
  }

  assert {
    condition     = join(",", sort(keys(module.external_lb["external"].backend_service_ids))) == "mig,run"
    error_message = "Sin NEG de DR, el backend gke debe quedar fuera del externo durante la conmutación."
  }
  assert {
    condition     = local.external_default_backend == "run"
    error_message = "Con lb_default_backend = gke y sin NEG de DR, el backend por defecto debe pasar al primero habilitado (run)."
  }
  assert {
    condition     = toset(keys(module.internal_lb)) == toset(["primary", "dr"]) && output.gke_cluster_names["us-east4"] == "bnt-prod-app-gke-use4"
    error_message = "La conmutación crea el clúster y el balanceador interno de DR aunque falten los NEG."
  }
}

# Solo GKE con NEG primarios: al conmutar sin NEG de DR el externo no se destruye (sigue con los
# NEG primarios hasta que se declaren los de DR).
run "prod_conmutacion_solo_gke_sin_neg_de_dr" {
  command = plan

  variables {
    dr_active          = true
    enable_mig         = false
    enable_cloud_run   = false
    enable_internal_lb = false
    lb_backend_paths   = {}
    gke_lb_negs = {
      primary = ["projects/example-svc-app/zones/us-central1-a/networkEndpointGroups/k8s1-web"]
    }
  }

  assert {
    condition     = module.external_lb["external"].backend_groups == { gke = tolist(["projects/example-svc-app/zones/us-central1-a/networkEndpointGroups/k8s1-web"]) }
    error_message = "Si GKE es el único backend, el externo se queda con los NEG primarios en lugar de destruirse."
  }
  assert {
    condition     = keys(module.cloud_sql.iam_user_names) == ["bnt-app-workload@example-svc-app.iam.gserviceaccount.com"]
    error_message = "Solo con GKE, solo la cuenta workload entra a Cloud SQL."
  }
}

# Vuelta a la región primaria (runbook 04, reversión), paso 1: con dr_active todavía en true,
# dr_teardown quita la protección contra borrado solo del cómputo de DR (cambio en el lugar). El
# proveedor solo destruye un clúster o un servicio cuya protección ya está en false en el estado.
# Con los NEG de DR del paso 6 de la conmutación (el mismo -var-file): el backend gke sigue en
# el externo, así que el plan no lo quita.
run "prod_vuelta_paso_1_retiro_del_computo_de_dr" {
  command = plan

  variables {
    dr_active   = true
    dr_teardown = true
    gke_lb_negs = {
      primary = ["projects/example-svc-app/zones/us-central1-a/networkEndpointGroups/k8s1-web"]
      dr      = ["projects/example-svc-app/zones/us-east4-a/networkEndpointGroups/k8s1-web"]
    }
  }

  assert {
    condition     = module.gke["dr"].deletion_protection == false && module.cloud_run["dr"].deletion_protection == false
    error_message = "Con dr_teardown el clúster y el servicio de DR deben quedar sin protección contra borrado."
  }
  assert {
    condition     = module.gke["primary"].deletion_protection == true && module.cloud_run["primary"].deletion_protection == true
    error_message = "dr_teardown nunca quita la protección del cómputo de la región primaria."
  }
  assert {
    condition     = toset(keys(module.gke)) == toset(["primary", "dr"]) && toset(keys(module.internal_lb)) == toset(["primary", "dr"])
    error_message = "El paso 1 no destruye nada: el cómputo y el balanceador interno de DR siguen."
  }
  assert {
    condition     = output.active_region == "us-east4"
    error_message = "El paso 1 no mueve el tráfico: sigue en la región de DR."
  }
  assert {
    condition     = join(",", sort(keys(module.external_lb["external"].backend_service_ids))) == "gke,mig,run"
    error_message = "Con los NEG de DR el paso 1 conserva el backend gke del externo."
  }
}

# Paso 2: dr_active = false y dr_teardown = false en el mismo apply (el proveedor lee la
# protección del estado al borrar). Planea destruir solo el cómputo de DR y su balanceador
# interno; la primaria queda protegida y los datos de DR no se tocan.
run "prod_vuelta_paso_2_sin_dr_active" {
  command = plan

  variables {
    dr_active   = false
    dr_teardown = false
  }

  assert {
    condition     = keys(module.gke) == ["primary"] && keys(module.cloud_run) == ["primary"] && keys(module.mig) == ["primary"] && keys(module.internal_lb) == ["primary"]
    error_message = "Con dr_active = false solo queda el cómputo y el balanceador interno de la región primaria."
  }
  assert {
    condition     = module.gke["primary"].deletion_protection == true && module.cloud_run["primary"].deletion_protection == true
    error_message = "La región primaria sigue protegida durante la vuelta."
  }
  assert {
    condition     = output.active_region == "us-central1" && module.cloud_sql.replica_name == "bnt-prod-data-sql-use4"
    error_message = "El tráfico vuelve a la primaria y la réplica de Cloud SQL (enable_dr) no se destruye."
  }
  assert {
    condition     = toset(keys(google_certificate_manager_certificate.internal)) == toset(["primary", "dr"])
    error_message = "El certificado interno de DR depende de enable_dr, no de dr_active: la vuelta no lo destruye."
  }
}

# Certificado interno de DR antes de un incidente: con enable_dr y sin dr_active existen la
# autorización DNS y el certificado de us-east4, pero no el balanceador interno de DR.
run "prod_certificado_interno_de_dr_antes_del_incidente" {
  command = plan

  override_resource {
    target          = module.internal_lb["primary"].google_compute_address.this["this"]
    override_during = plan
    values          = { address = "10.10.0.50" }
  }

  assert {
    condition     = keys(module.internal_lb) == ["primary"]
    error_message = "Sin dr_active no existe el balanceador interno de DR."
  }
  assert {
    condition = (
      google_certificate_manager_certificate.internal["primary"].location == "us-central1" &&
      google_certificate_manager_certificate.internal["dr"].location == "us-east4" &&
      startswith(google_certificate_manager_certificate.internal["dr"].name, "bnt-prod-app-app-ilb-use4-cert-")
    )
    error_message = "Con enable_dr debe existir el certificado interno de cada región, con el nombre de §4.2."
  }
  assert {
    condition = (
      google_certificate_manager_dns_authorization.internal["dr/app-prod-example-com"].location == "us-east4" &&
      google_certificate_manager_dns_authorization.internal["dr/app-prod-example-com"].domain == "app.prod.example.com" &&
      google_certificate_manager_dns_authorization.internal["primary/app-prod-example-com"].location == "us-central1"
    )
    error_message = "Cada región debe tener la autorización DNS de cada dominio interno."
  }
  assert {
    condition     = toset(keys(output.internal_lb_dns_authorization_records_by_region)) == toset(["us-central1", "us-east4"])
    error_message = "Los registros de autorización de DR deben publicarse antes de un incidente."
  }
  assert {
    condition     = output.internal_lb_dns_records == { "app.prod.example.com" = { type = "A", rrdatas = ["10.10.0.50"] } }
    error_message = "El registro DNS interno debe apuntar a la IP del balanceador interno de la región activa."
  }
}

# Sin enable_dr solo existe el certificado interno de la región primaria.
run "sin_dr_solo_certificado_interno_primario" {
  command = plan

  variables {
    enable_dr = false
  }

  assert {
    condition     = keys(google_certificate_manager_certificate.internal) == ["primary"] && keys(google_certificate_manager_dns_authorization.internal) == ["primary/app-prod-example-com"]
    error_message = "Sin enable_dr no se crea el certificado interno de la región de DR."
  }
}

# dr_teardown no puede quedar encendido después de la vuelta: desprotegería el cómputo de DR de
# la siguiente conmutación.
run "rechaza_dr_teardown_sin_dr_active" {
  command = plan

  variables {
    dr_active   = false
    dr_teardown = true
  }

  expect_failures = [var.dr_teardown]
}

run "rechaza_dr_teardown_sin_enable_dr" {
  command = plan

  variables {
    enable_dr   = false
    dr_teardown = true
  }

  expect_failures = [var.dr_teardown]
}

run "dev_solo_cloud_run_y_sql" {
  command = plan

  # Valores de terraform.tfvars.example de dev.
  variables {
    environment         = "dev"
    enable_dr           = false
    dr_active           = false
    enable_gke          = false
    enable_mig          = false
    enable_cloud_run    = true
    enable_filestore    = false
    enable_memorystore  = false
    enable_internal_lb  = false
    deletion_protection = false
    gke_node_pools      = {}
    mig_image           = null
    cloud_run_image     = "us-docker.pkg.dev/example-dev-app/bnt-dev-app-app-images-us/api:latest"
    sql_tier            = "db-custom-1-3840"
    lb_backend_paths    = {}
    domain_names        = ["app.dev.example.com"]
    notification_emails = ["alertas-dev@example.com"]
    off_hours_shutdown = {
      enabled        = true
      time_zone      = "America/Monterrey"
      start_schedule = "0 7 * * 1-5"
      stop_schedule  = "0 20 * * 1-5"
    }
  }

  assert {
    condition     = output.gke_cluster_names == {} && length(google_service_account_iam_member.workload_identity) == 0
    error_message = "Sin GKE no hay clúster ni enlace de Workload Identity."
  }

  # Apagado fuera de horario (ADR 0028): en dev solo hay Cloud SQL que detener (Cloud Run ya
  # escala a 0 y no hay MIG ni GKE).
  assert {
    condition     = toset(keys(module.off_hours_shutdown["this"].job_names)) == toset(["sql-primary-stop", "sql-primary-start"])
    error_message = "En dev deben existir los trabajos de apagado y encendido de Cloud SQL, y solo esos."
  }
  assert {
    condition     = module.off_hours_shutdown["this"].job_names["sql-primary-stop"] == "bnt-dev-ops-sql-primary-stop-usc1"
    error_message = "Los trabajos siguen <prefix>-<env>-ops-<trabajo>-<región>."
  }
  assert {
    condition = (
      output.off_hours_shutdown.window.duration_sec == 46800 &&
      output.off_hours_shutdown.window.time_zone == "America/Monterrey" &&
      contains(keys(output.off_hours_shutdown.job_ids), "sql-primary-start")
    )
    error_message = "La salida off_hours_shutdown publica la ventana de 13 h y el trabajo de encendido de Cloud SQL."
  }
  assert {
    condition     = local.backup_window == { start_hour = 7, time_zone = "America/Monterrey" }
    error_message = "La ventana de respaldo debe empezar a la hora de encendido, en la zona horaria del apagado."
  }
  assert {
    condition     = module.cloud_sql.activation_policy == "ALWAYS" && local.mig_business_hours.duration_sec == 46800
    error_message = "Cloud SQL nace encendida y el programa del MIG (si lo hubiera) dura el horario encendido."
  }
  assert {
    condition     = length(module.mig) == 0 && length(module.memorystore) == 0 && length(module.filestore) == 0 && length(module.internal_lb) == 0
    error_message = "Los interruptores apagados no deben crear nada."
  }
  assert {
    condition     = module.cloud_run["primary"].service_name == "bnt-dev-app-run-usc1"
    error_message = "Cloud Run de dev no sigue el nombre de §4.2."
  }
  assert {
    condition     = module.cloud_sql.instance_name == "bnt-dev-data-sql-usc1" && module.cloud_sql.replica_name == null
    error_message = "Sin enable_dr no debe haber réplica de Cloud SQL."
  }
  # Cloud Run es el único cómputo: su cuenta entra a Cloud SQL por IAM (y solo ella).
  assert {
    condition     = keys(module.cloud_sql.iam_user_names) == ["bnt-app-run@example-svc-app.iam.gserviceaccount.com"]
    error_message = "En dev la cuenta run de Cloud Run debe ser el único usuario IAM de Cloud SQL."
  }
  assert {
    condition     = output.bucket_names == { data = "bnt-dev-data-app-usc1" } && module.storage.data_locations == []
    error_message = "Sin enable_dr el bucket debe ser regional."
  }
  assert {
    condition     = keys(module.external_lb["external"].backend_service_ids) == ["run"]
    error_message = "En dev el balanceador externo debe tener solo el backend de Cloud Run."
  }
  assert {
    condition     = keys(module.backup["this"].plan_ids) == ["sql"]
    error_message = "Sin DR ni GKE solo debe existir el plan de Cloud SQL."
  }
  assert {
    condition     = local.labels["env"] == "dev"
    error_message = "Las etiquetas deben llevar env = dev."
  }
}

# Primera ejecución del pipeline (runbook 01, "Primera ejecución de apply.yml"): el repositorio
# de imágenes lo crea la etapa 4 en esa misma ejecución, así que todavía no hay imagen que
# desplegar. Con todo el cómputo apagado el plan sigue siendo válido: datos, observabilidad y
# respaldo, sin balanceador (la salida lb_ip_address queda en null y la prueba de humo omite
# esa comprobación).
run "primera_ejecucion_sin_computo" {
  command = plan

  variables {
    environment         = "dev"
    enable_dr           = false
    dr_active           = false
    enable_gke          = false
    enable_mig          = false
    enable_cloud_run    = false
    enable_filestore    = false
    enable_memorystore  = false
    enable_internal_lb  = false
    deletion_protection = false
    gke_node_pools      = {}
    mig_image           = null
    cloud_run_image     = null
    sql_tier            = "db-custom-1-3840"
    lb_backend_paths    = {}
    domain_names        = ["app.dev.example.com"]
    notification_emails = ["alertas-dev@example.com"]
  }

  assert {
    condition     = length(module.gke) == 0 && length(module.mig) == 0 && length(module.cloud_run) == 0
    error_message = "Con los tres interruptores apagados no debe haber cómputo."
  }
  assert {
    condition     = length(module.external_lb) == 0 && length(module.internal_lb) == 0 && output.lb_ip_address == null
    error_message = "Sin backends no debe haber balanceador y lb_ip_address debe ser null."
  }
  assert {
    condition     = module.cloud_sql.instance_name == "bnt-dev-data-sql-usc1" && output.bucket_names == { data = "bnt-dev-data-app-usc1" }
    error_message = "Sin cómputo se siguen creando Cloud SQL y el bucket."
  }
  assert {
    condition     = keys(module.backup["this"].plan_ids) == ["sql"]
    error_message = "Sin cómputo debe quedar solo el plan de respaldo de Cloud SQL."
  }
}

# Lo mismo con los valores de prod (enable_dr, Memorystore y Filestore encendidos): el
# balanceador interno también se apaga, porque exige un backend mig o run.
run "prod_primera_ejecucion_sin_computo" {
  command = plan

  variables {
    enable_gke         = false
    enable_mig         = false
    enable_cloud_run   = false
    enable_internal_lb = false
    gke_node_pools     = {}
    mig_image          = null
    cloud_run_image    = null
    lb_backend_paths   = {}
  }

  assert {
    condition     = length(module.gke) == 0 && length(module.mig) == 0 && length(module.cloud_run) == 0
    error_message = "Con los tres interruptores apagados no debe haber cómputo."
  }
  assert {
    condition     = length(module.external_lb) == 0 && length(module.internal_lb) == 0 && length(google_certificate_manager_certificate.internal) == 0
    error_message = "Sin backends no debe haber balanceadores ni certificado interno."
  }
  assert {
    condition     = module.cloud_sql.instance_name == "bnt-prod-data-sql-usc1" && module.cloud_sql.replica_name != null
    error_message = "Sin cómputo se siguen creando Cloud SQL y su réplica de DR."
  }
  assert {
    condition     = length(module.memorystore) == 1 && length(module.filestore) == 1
    error_message = "Memorystore y Filestore no dependen del cómputo."
  }
}

run "qa_mig_cloud_run_y_redis" {
  command = plan

  # Valores de terraform.tfvars.example de qa.
  variables {
    environment         = "qa"
    enable_dr           = false
    dr_active           = false
    enable_gke          = false
    enable_mig          = true
    enable_cloud_run    = true
    enable_filestore    = false
    enable_memorystore  = true
    enable_internal_lb  = false
    deletion_protection = false
    gke_node_pools      = {}
    mig_min_replicas    = 1
    mig_max_replicas    = 3
    cloud_run_image     = "us-docker.pkg.dev/example-qa-app/bnt-qa-app-app-images-us/api:1.0.0"
    lb_backend_paths    = { mig = ["/legacy/*"] }
    domain_names        = ["app.qa.example.com"]
    notification_emails = ["alertas-qa@example.com"]
    off_hours_shutdown = {
      enabled        = true
      time_zone      = "America/Monterrey"
      start_schedule = "0 7 * * 1-5"
      stop_schedule  = "0 20 * * 1-5"
    }
  }

  # Apagado fuera de horario (ADR 0028): Cloud SQL por Cloud Scheduler y el MIG con el programa
  # de escalado nativo (sin CPU, 0 VM fuera del horario).
  assert {
    condition     = toset(keys(module.off_hours_shutdown["this"].job_names)) == toset(["sql-primary-stop", "sql-primary-start"])
    error_message = "En qa sin GKE solo hay trabajos de Cloud SQL (el MIG no usa Cloud Scheduler)."
  }
  assert {
    condition = module.mig["primary"].autoscaling == {
      min_replicas = 0
      max_replicas = 3
      signal       = "schedule"
      scaling_schedules = {
        business-hours = {
          schedule              = "0 7 * * 1-5"
          time_zone             = "America/Monterrey"
          duration_sec          = 46800
          min_required_replicas = 1
        }
      }
    }
    error_message = "El MIG de qa debe tener mig_min_replicas VM de 07:00 a 20:00 (lunes a viernes, Monterrey) y 0 fuera, sin señal de CPU."
  }

  assert {
    condition     = join(",", sort(keys(module.external_lb["external"].backend_service_ids))) == "mig,run"
    error_message = "En qa el balanceador externo debe tener los backends mig y run."
  }
  assert {
    condition     = module.mig["primary"].instance_group_manager_name == "bnt-qa-app-mig-usc1" && module.memorystore["primary"].instance_name == "bnt-qa-data-redis-usc1"
    error_message = "Los nombres de qa no siguen §4.2."
  }
  assert {
    condition     = output.gke_cluster_names == {} && module.cloud_sql.replica_name == null
    error_message = "qa no lleva GKE ni réplica de DR."
  }
  assert {
    condition     = toset(keys(module.cloud_sql.iam_user_names)) == toset(["bnt-app-run@example-svc-app.iam.gserviceaccount.com", "bnt-app-mig@example-svc-app.iam.gserviceaccount.com"])
    error_message = "En qa las cuentas run y mig deben entrar a Cloud SQL por IAM."
  }
}

# Un puerto dentro de un rango de lb_backend_ports de la etapa 3 está cubierto.
run "puerto_de_backend_dentro_de_un_rango" {
  command = plan

  variables {
    enable_gke    = false
    mig_http_port = 8000
  }

  override_data {
    target = data.terraform_remote_state.network
    values = {
      outputs = {
        host_project_id   = "example-net-spoke"
        network_name      = "bnt-net-vpc"
        network_self_link = "https://www.googleapis.com/compute/v1/projects/example-net-spoke/global/networks/bnt-net-vpc"
        subnets = {
          for k, s in {
            app      = { region = "us-central1", code = "usc1" }
            app_dr   = { region = "us-east4", code = "use4" }
            run      = { region = "us-central1", code = "usc1" }
            run_dr   = { region = "us-east4", code = "use4" }
            proxy    = { region = "us-central1", code = "usc1" }
            proxy_dr = { region = "us-east4", code = "use4" }
            } : k => {
            self_link        = "https://www.googleapis.com/compute/v1/projects/example-net-spoke/regions/${s.region}/subnetworks/bnt-net-${trimsuffix(k, "_dr")}-${s.code}"
            name             = "bnt-net-${trimsuffix(k, "_dr")}-${s.code}"
            region           = s.region
            cidr             = "10.30.0.0/24"
            secondary_ranges = {}
          }
        }
        psa_range_name   = "bnt-net-psa"
        secure_tags      = { lb_backend = "tagValues/111111", iap_ssh = "tagValues/222222" }
        secure_tag_keys  = { lb_backend = "tagKeys/333333", iap_ssh = "tagKeys/444444" }
        reserved_cidrs   = { gke_master = "10.30.38.0/28" }
        lb_backend_ports = ["443", "7990-8100"]
      }
    }
  }

  assert {
    condition     = module.mig["primary"].named_ports["http"] == 8000
    error_message = "Un puerto dentro de un rango de lb_backend_ports debe aceptarse."
  }
}

# Estado de la etapa 3 anterior a la salida lb_backend_ports: la comprobación de puertos se omite.
run "puertos_de_backend_sin_salida_de_la_etapa_3" {
  command = plan

  variables {
    enable_gke    = false
    mig_http_port = 8000
  }

  override_data {
    target = data.terraform_remote_state.network
    values = {
      outputs = {
        host_project_id   = "example-net-spoke"
        network_name      = "bnt-net-vpc"
        network_self_link = "https://www.googleapis.com/compute/v1/projects/example-net-spoke/global/networks/bnt-net-vpc"
        subnets = {
          for k, s in {
            app      = { region = "us-central1", code = "usc1" }
            app_dr   = { region = "us-east4", code = "use4" }
            run      = { region = "us-central1", code = "usc1" }
            run_dr   = { region = "us-east4", code = "use4" }
            proxy    = { region = "us-central1", code = "usc1" }
            proxy_dr = { region = "us-east4", code = "use4" }
            } : k => {
            self_link        = "https://www.googleapis.com/compute/v1/projects/example-net-spoke/regions/${s.region}/subnetworks/bnt-net-${trimsuffix(k, "_dr")}-${s.code}"
            name             = "bnt-net-${trimsuffix(k, "_dr")}-${s.code}"
            region           = s.region
            cidr             = "10.30.0.0/24"
            secondary_ranges = {}
          }
        }
        psa_range_name  = "bnt-net-psa"
        secure_tags     = { lb_backend = "tagValues/111111", iap_ssh = "tagValues/222222" }
        secure_tag_keys = { lb_backend = "tagKeys/333333", iap_ssh = "tagKeys/444444" }
        reserved_cidrs  = { gke_master = "10.30.38.0/28" }
      }
    }
  }

  assert {
    condition     = module.mig["primary"].named_ports["http"] == 8000
    error_message = "Sin lb_backend_ports en el estado de la etapa 3, el plan no debe fallar por el puerto."
  }
}

run "rechaza_puerto_de_backend_fuera_del_firewall" {
  command = plan

  variables {
    mig_http_port = 8000
  }

  expect_failures = [data.terraform_remote_state.network]
}

run "rechaza_gke_sin_rango_del_plano_de_control" {
  command = plan

  variables {
    enable_mig         = false
    enable_cloud_run   = false
    enable_internal_lb = false
  }

  override_data {
    target = data.terraform_remote_state.network
    values = {
      outputs = {
        host_project_id   = "example-net-spoke"
        network_name      = "bnt-net-vpc"
        network_self_link = "https://www.googleapis.com/compute/v1/projects/example-net-spoke/global/networks/bnt-net-vpc"
        subnets = {
          app = {
            self_link        = "https://www.googleapis.com/compute/v1/projects/example-net-spoke/regions/us-central1/subnetworks/bnt-net-app-usc1"
            name             = "bnt-net-app-usc1"
            region           = "us-central1"
            cidr             = "10.30.0.0/20"
            secondary_ranges = { pods = "10.30.64.0/18", services = "10.30.128.0/20" }
          }
        }
        psa_range_name   = "bnt-net-psa"
        secure_tags      = { lb_backend = "tagValues/111111", iap_ssh = "tagValues/222222" }
        secure_tag_keys  = { lb_backend = "tagKeys/333333", iap_ssh = "tagKeys/444444" }
        reserved_cidrs   = {}
        lb_backend_ports = ["80", "443", "8080"]
      }
    }
  }

  expect_failures = [data.terraform_remote_state.network]
}

run "rechaza_conmutacion_sin_rango_de_dr_del_plano_de_control" {
  command = plan

  variables {
    dr_active = true
  }

  override_data {
    target = data.terraform_remote_state.network
    values = {
      outputs = {
        host_project_id   = "example-net-spoke"
        network_name      = "bnt-net-vpc"
        network_self_link = "https://www.googleapis.com/compute/v1/projects/example-net-spoke/global/networks/bnt-net-vpc"
        subnets = {
          for k, s in {
            app      = { region = "us-central1", code = "usc1" }
            app_dr   = { region = "us-east4", code = "use4" }
            run      = { region = "us-central1", code = "usc1" }
            run_dr   = { region = "us-east4", code = "use4" }
            proxy    = { region = "us-central1", code = "usc1" }
            proxy_dr = { region = "us-east4", code = "use4" }
            } : k => {
            self_link        = "https://www.googleapis.com/compute/v1/projects/example-net-spoke/regions/${s.region}/subnetworks/bnt-net-${trimsuffix(k, "_dr")}-${s.code}"
            name             = "bnt-net-${trimsuffix(k, "_dr")}-${s.code}"
            region           = s.region
            cidr             = "10.30.0.0/24"
            secondary_ranges = { pods = "10.30.64.0/18", services = "10.30.128.0/20" }
          }
        }
        psa_range_name   = "bnt-net-psa"
        secure_tags      = { lb_backend = "tagValues/111111", iap_ssh = "tagValues/222222" }
        secure_tag_keys  = { lb_backend = "tagKeys/333333", iap_ssh = "tagKeys/444444" }
        reserved_cidrs   = { gke_master = "10.30.38.0/28" }
        lb_backend_ports = ["80", "443", "8080"]
      }
    }
  }

  expect_failures = [data.terraform_remote_state.network]
}

run "rechaza_etiqueta_app_distinta_de_application" {
  command = plan

  variables {
    labels = {
      app         = "otra"
      owner       = "plataforma"
      cost_center = "ti-001"
    }
  }

  expect_failures = [var.labels]
}

run "rechaza_dr_active_sin_enable_dr" {
  command = plan

  variables {
    enable_dr = false
    dr_active = true
  }

  expect_failures = [var.dr_active]
}

run "rechaza_mig_sin_imagen" {
  command = plan

  variables {
    mig_image = null
  }

  expect_failures = [var.mig_image]
}

run "rechaza_prefijo_invalido" {
  command = plan

  variables {
    prefix = "Empresa1"
  }

  expect_failures = [var.prefix]
}

run "rechaza_namespace_del_sistema_para_workload_identity" {
  command = plan

  variables {
    gke_workload_namespace = "kube-system"
  }

  expect_failures = [var.gke_workload_namespace]
}

run "rechaza_balanceador_interno_sin_backends" {
  command = plan

  variables {
    enable_mig       = false
    enable_cloud_run = false
  }

  expect_failures = [terraform_data.upstream_checks]
}

# --- Apagado fuera de horario (ADR 0028) ------------------------------------------------------

# dev con GKE encendido: los pools pasan a "scheduled" (Terraform ignora su autoscaling) y cada
# uno tiene sus cuatro trabajos, con la ubicación, el clúster y los límites del pool.
run "dev_gke_con_apagado_fuera_de_horario" {
  command = plan

  variables {
    environment         = "dev"
    enable_dr           = false
    dr_active           = false
    enable_gke          = true
    enable_mig          = false
    enable_cloud_run    = true
    enable_filestore    = false
    enable_memorystore  = false
    enable_internal_lb  = false
    deletion_protection = false
    mig_image           = null
    lb_backend_paths    = {}
    domain_names        = ["app.dev.example.com"]
    notification_emails = ["alertas-dev@example.com"]
    off_hours_shutdown = {
      enabled        = true
      time_zone      = "America/Monterrey"
      start_schedule = "30 7 * * 1-5"
      stop_schedule  = "0 21 * * 1-5"
    }
  }

  assert {
    condition = toset(keys(module.off_hours_shutdown["this"].job_names)) == toset([
      "sql-primary-stop", "sql-primary-start",
      "gke-general-stop-autoscaling", "gke-general-stop-resize",
      "gke-general-start-resize", "gke-general-start-autoscaling",
    ])
    error_message = "Con GKE deben existir los dos trabajos de Cloud SQL y los cuatro del pool general."
  }
  assert {
    condition = module.gke["primary"].node_pools["general"] == {
      name           = "bnt-dev-app-nps-general"
      location       = "us-central1"
      cluster        = "bnt-dev-app-gke-usc1"
      min_node_count = 1
      max_node_count = 3
      scheduled      = true
    }
    error_message = "Con el apagado los pools son los \"scheduled\" (<prefix>-<env>-app-nps-<llave>)."
  }
  # Encendido a las 07:30: la ventana de respaldo empieza a las 08:00.
  assert {
    condition     = local.backup_window.start_hour == 8 && output.off_hours_shutdown.window.duration_sec == (21 * 60 - (7 * 60 + 30)) * 60
    error_message = "La ventana de respaldo empieza en la primera hora cerrada desde el encendido."
  }
}

# Sin enable_dr, para que la única regla que falle sea la de prod.
run "rechaza_apagado_fuera_de_horario_en_prod" {
  command = plan

  variables {
    enable_dr          = false
    enable_internal_lb = false
    off_hours_shutdown = { enabled = true }
  }

  expect_failures = [var.off_hours_shutdown]
}

run "rechaza_apagado_fuera_de_horario_con_dr" {
  command = plan

  variables {
    environment         = "qa"
    deletion_protection = false
    off_hours_shutdown  = { enabled = true }
  }

  expect_failures = [var.off_hours_shutdown]
}

run "rechaza_cron_de_apagado_invalido" {
  command = plan

  variables {
    environment         = "dev"
    enable_dr           = false
    deletion_protection = false
    off_hours_shutdown = {
      enabled       = true
      stop_schedule = "0 25 * * 1-5"
    }
  }

  expect_failures = [var.off_hours_shutdown]
}

run "rechaza_cron_con_dia_del_mes" {
  command = plan

  variables {
    environment         = "dev"
    enable_dr           = false
    deletion_protection = false
    off_hours_shutdown = {
      enabled        = true
      start_schedule = "0 7 1 * *"
      stop_schedule  = "0 20 1 * *"
    }
  }

  expect_failures = [var.off_hours_shutdown]
}

run "rechaza_horario_sin_lugar_para_el_respaldo" {
  command = plan

  variables {
    environment         = "dev"
    enable_dr           = false
    deletion_protection = false
    off_hours_shutdown = {
      enabled        = true
      start_schedule = "15 9 * * 1-5"
      stop_schedule  = "0 15 * * 1-5"
    }
  }

  expect_failures = [var.off_hours_shutdown]
}

# Estado de 4-projects sin la cuenta del apagado (enable_off_hours_shutdown = false o etapa 4
# anterior a la salida): el plan falla con un mensaje claro en lugar de crear trabajos sin cuenta.
run "rechaza_apagado_sin_la_cuenta_de_la_etapa_4" {
  command = plan

  variables {
    environment         = "dev"
    enable_dr           = false
    deletion_protection = false
    off_hours_shutdown  = { enabled = true }
  }

  override_data {
    target = data.terraform_remote_state.projects
    values = {
      outputs = {
        service_project_ids     = { app = "example-svc-app" }
        service_project_numbers = { app = "000000000000" }
        service_accounts = {
          app = {
            gke_nodes = "bnt-app-gke-nodes@example-svc-app.iam.gserviceaccount.com"
            workload  = "bnt-app-workload@example-svc-app.iam.gserviceaccount.com"
            mig       = "bnt-app-mig@example-svc-app.iam.gserviceaccount.com"
            run       = "bnt-app-run@example-svc-app.iam.gserviceaccount.com"
          }
        }
      }
    }
  }

  expect_failures = [terraform_data.upstream_checks]
}
