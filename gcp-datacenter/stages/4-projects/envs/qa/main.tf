# Etapa 4 (§7.5): proyectos de servicio por aplicación, unidos al host de Shared VPC del spoke
# del entorno, y sus cuentas de servicio de ejecución. Los permisos están en iam.tf y el alta en
# el perímetro de VPC-SC en vpc_sc.tf.

locals {
  # §4.3. Cada proyecto agrega app = <llave de la aplicación>.
  labels = merge(var.labels, {
    env        = var.environment
    managed_by = "terraform"
  })

  is_prod = var.environment == "prod"

  # APIs que la raíz habilita siempre en cada proyecto de servicio: las de los agentes de
  # servicio que reciben permisos aquí y las que usan los módulos de la etapa 5. apis de cada
  # aplicación se suma a esta lista. compute.googleapis.com la agrega además project-factory
  # por ser proyecto de servicio de Shared VPC.
  base_apis = toset([
    "artifactregistry.googleapis.com",    # imágenes de GKE, MIG y Cloud Run
    "backupdr.googleapis.com",            # bóveda y planes de Backup and DR (módulo backup-dr)
    "binaryauthorization.googleapis.com", # Binary Authorization de GKE y Cloud Run
    "certificatemanager.googleapis.com",  # certificado administrado del balanceador
    "cloudresourcemanager.googleapis.com",
    "cloudtrace.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "file.googleapis.com",
    "gkebackup.googleapis.com", # Backup for GKE
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "iap.googleapis.com", # túneles de IAP para SSH (etiqueta iap_ssh)
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "oslogin.googleapis.com", # OS Login fijo en compute-mig
    "redis.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
  ])

  # Usos de las cuentas de servicio de ejecución (§7.5) → roles mínimos en su proyecto.
  # gke_nodes sigue la lista mínima de la cuenta de nodos de GKE; workload es la cuenta de los
  # pods (Workload Identity) y run la del servicio de Cloud Run: telemetría y nada más, los
  # secretos se dan uno por uno en iam.tf y Cloud SQL lo da el módulo cloud-sql en la etapa 5.
  # La lectura de imágenes (artifactregistry.reader) va sobre el repositorio de la aplicación,
  # no sobre el proyecto (artifacts.tf).
  runtime_roles = {
    gke_nodes = [
      "roles/autoscaling.metricsWriter",
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
      "roles/monitoring.viewer",
      "roles/stackdriver.resourceMetadata.writer",
    ]
    workload = [
      "roles/cloudtrace.agent",
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
    ]
    mig = [
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
    ]
    run = [
      "roles/cloudtrace.agent",
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
    ]
  }

  # Una cuenta por aplicación y uso: "<app>/<uso>".
  runtime_service_accounts = {
    for pair in setproduct(keys(var.applications), keys(local.runtime_roles)) :
    "${pair[0]}/${pair[1]}" => {
      app        = pair[0]
      use        = pair[1]
      account_id = "${var.prefix}-${var.environment}-${pair[0]}-${replace(pair[1], "_", "-")}"
    }
  }
}

# La carpeta del entorno viene del estado de 1-org; se comprueba que pertenezca a org_id para
# no crear proyectos en otra organización si el estado o las variables se cruzan.
data "google_folder" "env" {
  folder              = local.folder_id
  lookup_organization = true

  lifecycle {
    postcondition {
      condition     = self.organization == "organizations/${var.org_id}"
      error_message = "La carpeta del entorno (folder_ids de 1-org) no pertenece a la organización org_id."
    }
  }
}

module "project" {
  source   = "../../../../modules/project-factory"
  for_each = var.applications

  prefix                  = var.prefix
  environment             = var.environment
  name                    = each.key
  project_suffix          = var.project_suffix
  folder_id               = data.google_folder.env.name
  billing_account         = var.billing_account
  apis                    = setunion(local.base_apis, each.value.apis)
  shared_vpc_host_project = local.host_project_id
  deletion_policy         = var.deletion_policy
  labels                  = merge(local.labels, { app = each.key })
}

resource "google_service_account" "runtime" {
  for_each = local.runtime_service_accounts

  project      = module.project[each.value.app].project_id
  account_id   = each.value.account_id
  display_name = "${each.value.app} ${each.value.use} (${var.environment})"
  description  = "Cuenta de ejecución ${each.value.use} de la aplicación ${each.value.app} en ${var.environment}. Administrada por Terraform (etapa 4)."

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", each.value.account_id))
      error_message = "El ID de cuenta de servicio <prefix>-<environment>-<app>-<uso> debe tener de 6 a 30 caracteres (ADR 0017)."
    }
  }
}
