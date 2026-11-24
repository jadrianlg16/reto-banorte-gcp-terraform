# Cómputo (ADR 0012): GKE para contenedores, MIG para VM y Cloud Run para servicios sin estado,
# cada uno con su interruptor. Un for_each por región activa (local.compute_regions, llaves
# primary y dr): con dr_active se agrega la instancia "dr" en dr_region, con subredes app_dr y
# run_dr y llaves KMS de esa región.

module "gke" {
  source   = "../../../../modules/gke"
  for_each = var.enable_gke ? local.compute_regions : {}

  project_id   = var.project_id
  prefix       = var.prefix
  environment  = var.environment
  location     = each.value
  region_codes = var.region_codes
  # <prefix>-<env>-<app>-gke[-dr] (ADR 0029 §4).
  cluster_name = local.gke_cluster_names[each.key]

  network        = local.network_self_link
  subnet         = local.subnets[local.subnet_keys[each.key].app].self_link
  pods_range     = local.pods_range_name
  services_range = local.services_range_name
  # /28 que reserva el spoke (salida reserved_cidrs de 2-networks/<env>): el mismo valor que usa
  # la regla de firewall del plano de control. La postcondición del estado de red lo exige.
  master_cidr                = try(local.reserved_cidrs[local.subnet_keys[each.key].gke_master], null)
  master_authorized_networks = var.gke_master_authorized_networks

  release_channel              = var.gke_release_channel
  gke_node_pools               = var.gke_node_pools
  node_service_account         = local.service_accounts["gke_nodes"]
  kms_key                      = local.kms_key_ids[each.value]["gke"]
  authenticator_security_group = var.gke_authenticator_security_group
  # lb_backend en los nodos: el firewall del spoke solo deja pasar al balanceador hacia esa etiqueta.
  node_resource_manager_tags = local.gke_node_secure_tags
  enable_backup_agent        = true
  deletion_protection        = var.deletion_protection
  # Solo la instancia de DR se puede retirar (vuelta a la primaria, runbook 04).
  teardown = each.key == "dr" && var.dr_teardown
  # Apagado fuera de horario (off_hours.tf): Terraform ignora el autoscaling de los pools, que
  # cambian los trabajos de Cloud Scheduler. Encenderlo o apagarlo reemplaza los pools.
  scheduled_scaling = local.off_hours_enabled

  labels = local.labels

  depends_on = [terraform_data.upstream_checks, google_project_iam_member.runtime]
}

# Workload Identity: la cuenta de Kubernetes <namespace>/<nombre> actúa como la cuenta workload
# de la aplicación (Cloud SQL por IAM, secretos, telemetría). El pool <proyecto>.svc.id.goog es
# uno solo para todo el proyecto, los tres entornos incluidos: lo que separa a los entornos es el
# namespace <app>-<env> (ADR 0029 §9). Se toma de module.gke para que el enlace espere al primer
# clúster; sirve a los clústeres primario y de DR.
resource "google_service_account_iam_member" "workload_identity" {
  for_each = var.enable_gke ? toset(["workload"]) : toset([])

  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.service_accounts["workload"]}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${module.gke["primary"].workload_pool}[${local.gke_workload_namespace}/${var.gke_workload_ksa_name}]"
}

module "mig" {
  source   = "../../../../modules/compute-mig"
  for_each = var.enable_mig ? local.compute_regions : {}

  project_id   = var.project_id
  prefix       = var.prefix
  environment  = var.environment
  region       = each.value
  region_codes = var.region_codes

  subnet          = local.subnets[local.subnet_keys[each.key].app].self_link
  image           = var.mig_image
  machine_type    = var.mig_machine_type
  min_replicas    = var.mig_min_replicas
  max_replicas    = var.mig_max_replicas
  service_account = local.service_accounts["mig"]

  # Apagado fuera de horario (off_hours.tf): mig_min_replicas VM durante el horario encendido y
  # 0 fuera de él, con el programa de escalado nativo del autoescalador (sin señal de CPU).
  business_hours = local.mig_business_hours
  kms_key        = local.kms_key_ids[each.value]["compute"]

  named_ports = { http = var.mig_http_port }
  health_check = {
    protocol     = "HTTP"
    port         = var.mig_http_port
    request_path = var.mig_health_check_path
  }
  # Etiquetas seguras lb_backend e iap_ssh del spoke (reglas de firewall de su VPC).
  resource_manager_tags = local.mig_secure_tags

  labels = local.labels

  depends_on = [terraform_data.upstream_checks, google_project_iam_member.runtime]
}

module "cloud_run" {
  source   = "../../../../modules/cloud-run"
  for_each = var.enable_cloud_run ? local.compute_regions : {}

  project_id   = var.project_id
  prefix       = var.prefix
  environment  = var.environment
  region       = each.value
  region_codes = var.region_codes

  image           = var.cloud_run_image
  container_port  = var.cloud_run_container_port
  max_instances   = var.cloud_run_max_instances
  network         = local.network_self_link
  subnet          = local.subnets[local.subnet_keys[each.key].run].self_link
  service_account = local.service_accounts["run"]
  kms_key         = local.kms_key_ids[each.value]["run"]

  # Siempre es backend del balanceador externo (load_balancing.tf): ADR 0020, entrada interna y
  # del balanceador, sin verificación de invocador y sin allUsers.
  public_via_load_balancer = true
  deletion_protection      = var.deletion_protection
  # Solo la instancia de DR se puede retirar (vuelta a la primaria, runbook 04).
  teardown = each.key == "dr" && var.dr_teardown

  labels = local.labels

  depends_on = [terraform_data.upstream_checks, google_project_iam_member.runtime, google_secret_manager_secret_iam_member.runtime]
}
