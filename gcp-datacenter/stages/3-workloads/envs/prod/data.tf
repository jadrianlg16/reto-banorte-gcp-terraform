# Datos: Cloud SQL (siempre), Memorystore y Filestore (interruptores) y Cloud Storage (siempre).
# Las bases de datos y cachés viven solo en la región primaria; la DR de datos es la réplica de
# Cloud SQL y el bucket de doble región (enable_dr).

module "cloud_sql" {
  source = "../../../../modules/cloud-sql"

  project_id         = var.project_id
  prefix             = var.prefix
  environment        = var.environment
  name               = var.sql_instance_name
  region             = var.primary_region
  dr_region          = var.dr_region
  region_short_codes = var.region_codes

  # Con enable_dr: réplica de lectura en dr_region cifrada con la llave sql de esa región.
  # Promoverla durante una conmutación es un paso del runbook de DR, no de Terraform.
  enable_dr  = var.enable_dr
  kms_key    = local.kms_key_ids[var.primary_region]["sql"]
  dr_kms_key = var.enable_dr ? local.kms_key_ids[var.dr_region]["sql"] : null

  sql_tier         = var.sql_tier
  database_version = var.sql_database_version
  databases        = var.sql_databases

  # Solo IP privada en la VPC del spoke, tomada de su rango de Private Service Access.
  network            = local.network_self_link
  allocated_ip_range = local.psa_range_name

  # Sin contraseñas (ADR 0015): cada cuenta de ejecución cuyo cómputo está encendido entra por
  # IAM: workload con GKE (pods por Workload Identity), run con Cloud Run y mig con el MIG. Esta
  # raíz crea el usuario de base de datos; cloudsql.client e instanceUser (limitados a las
  # instancias del entorno) los da 1-base, porque tf-wl-<env> no asigna roles de proyecto.
  grant_iam_login_roles = false
  iam_users = [
    for use, enabled in {
      workload = var.enable_gke
      run      = var.enable_cloud_run
      mig      = var.enable_mig
      } : {
      email = local.service_accounts[use]
      type  = "CLOUD_IAM_SERVICE_ACCOUNT"
    } if enabled
  ]

  # Con enable_backup el plan de Backup and DR (operations.tf) es dueño del horario y la
  # retención de respaldos y de registros (respaldos mejorados).
  backup_plan_managed = var.enable_backup

  # Apagado fuera de horario (off_hours.tf): la instancia puede estar detenida sin que el plan
  # falle ni intente encenderla.
  allow_scheduled_stop = local.off_hours_enabled

  deletion_protection = var.deletion_protection
  labels              = local.labels

  depends_on = [terraform_data.upstream_checks]
}

module "memorystore" {
  source   = "../../../../modules/memorystore"
  for_each = var.enable_memorystore ? { primary = var.primary_region } : {}

  project_id         = var.project_id
  prefix             = var.prefix
  environment        = var.environment
  region             = each.value
  region_short_codes = var.region_codes

  memory_gb         = var.memorystore_memory_gb
  network           = local.network_self_link
  reserved_ip_range = local.psa_range_name
  kms_key           = local.kms_key_ids[each.value]["redis"]

  labels = local.labels

  depends_on = [terraform_data.upstream_checks]
}

module "filestore" {
  source   = "../../../../modules/filestore"
  for_each = var.enable_filestore ? { primary = var.primary_region } : {}

  project_id         = var.project_id
  prefix             = var.prefix
  environment        = var.environment
  region_short_codes = var.region_codes

  tier        = var.filestore_tier
  location    = var.filestore_tier == "ZONAL" ? "${each.value}-${var.filestore_zone_suffix}" : each.value
  capacity_gb = var.filestore_capacity_gb

  network           = local.network_self_link
  reserved_ip_range = local.psa_range_name
  kms_key           = local.kms_key_ids[each.value]["filestore"]

  deletion_protection = var.deletion_protection
  labels              = local.labels

  depends_on = [terraform_data.upstream_checks]
}

# Bucket de la aplicación. Con enable_dr es de doble región (primary_region + dr_region) dentro de
# la multirregión, con turbo replication y la llave storage de la multirregión (1-base); sin DR es
# regional en primary_region. Cambiar enable_dr reemplaza el bucket (cambian ubicación y nombre):
# se decide al crear el entorno, no durante un incidente.
module "storage" {
  source = "../../../../modules/storage"

  project_id         = var.project_id
  prefix             = var.prefix
  environment        = var.environment
  name               = var.application
  name_suffix        = var.bucket_name_suffix
  region_short_codes = var.region_codes

  location = var.enable_dr ? upper(var.multi_region) : var.primary_region
  dual_region = var.enable_dr ? {
    regions           = [var.primary_region, var.dr_region]
    turbo_replication = true
  } : null
  kms_key = var.enable_dr ? local.kms_key_ids[var.multi_region]["storage"] : local.kms_key_ids[var.primary_region]["storage"]

  labels = local.labels

  depends_on = [terraform_data.upstream_checks]
}
