# Llaves y secretos de cada entorno (ADR 0029 §4). Los llaveros llevan <prefix>-<env>- en el
# nombre: las cuentas de cargas solo pueden dar IAM sobre los de su entorno (condición de
# 0-bootstrap). Los agentes de servicio son uno por proyecto y reciben permiso sobre las llaves de
# los tres entornos (riesgo aceptado, ADR 0029 §4 y §9).

locals {
  # Ubicaciones de los llaveros: las dos regiones y la multirregión us (buckets de doble región y
  # repositorios multirregionales).
  multi_region  = "us"
  kms_locations = distinct([var.primary_region, var.dr_region, local.multi_region])

  # Usos de llave. En la multirregión solo storage, backup y artifacts.
  regional_key_uses     = ["gke", "compute", "sql", "storage", "filestore", "redis", "secrets", "backup", "run", "artifacts"]
  multi_region_key_uses = ["storage", "backup", "artifacts"]

  # Uso → agentes que cifran con esa llave. gke: el agente de GKE cifra los secretos de
  # Kubernetes y el de Compute los discos de los nodos (el módulo gke usa la misma llave).
  # backup: Backup for GKE (el plan de respaldo del clúster); la bóveda de Backup and DR de
  # 3-workloads no usa llave propia.
  kms_consumers = {
    artifacts = ["artifactregistry"]
    backup    = ["gkebackup"]
    compute   = ["compute"]
    filestore = ["filestore"]
    gke       = ["gke", "compute"]
    redis     = ["redis"]
    run       = ["run"]
    secrets   = ["secretmanager"]
    sql       = ["sql"]
    storage   = ["storage"]
  }

  # Sufijo del nombre de la llave en la salida kms_key_ids (formato de la etapa 2 anterior, que
  # 3-workloads ya lee): sin sufijo en la región primaria, _dr en la de DR y _us en la
  # multirregión.
  location_suffix = {
    (var.primary_region) = ""
    (var.dr_region)      = "_dr"
    (local.multi_region) = "_us"
  }

  keyrings = {
    for pair in setproduct(var.environments, local.kms_locations) : "${pair[0]}/${pair[1]}" => {
      environment = pair[0]
      location    = pair[1]
      # VERIFICAR-EN-APPLY: que cada agente exista antes de recibir el permiso (los crea
      # 0-bootstrap o aparecen al habilitar la API) y pueda cifrar con su llave.
      keys = {
        for u in(pair[1] == local.multi_region ? local.multi_region_key_uses : local.regional_key_uses) : u => {
          encrypter_decrypters = [for a in local.kms_consumers[u] : local.service_agents[a]]
        }
      }
    }
  }

  # Entornos con al menos un secreto.
  secret_envs = { for e in var.environments : e => distinct(lookup(var.secret_names, e, [])) if length(lookup(var.secret_names, e, [])) > 0 }
}

module "kms" {
  source   = "../../modules/kms"
  for_each = local.keyrings

  project_id           = local.project_id
  prefix               = var.prefix
  environment          = each.value.environment
  location             = each.value.location
  location_short_codes = var.location_short_codes
  keys                 = each.value.keys
  rotation_period      = var.key_rotation_period
  labels               = merge(local.labels_by_env[each.value.environment], { app = "kms" })
}

# --- Secretos (contenedores sin valores, ADR 0015) --------------------------------------------------

module "secrets" {
  source   = "../../modules/secrets"
  for_each = local.secret_envs

  project_id  = local.project_id
  prefix      = var.prefix
  environment = each.key
  names       = each.value
  # Una réplica por región, cada una con la llave secrets de su región.
  kms_keys = {
    (var.primary_region) = module.kms["${each.key}/${var.primary_region}"].key_ids["secrets"]
    (var.dr_region)      = module.kms["${each.key}/${var.dr_region}"].key_ids["secrets"]
  }
  labels = merge(local.labels_by_env[each.key], { app = "secrets" })

  # El agente de Secret Manager debe tener ya encrypter/decrypter sobre las llaves (lo da el
  # módulo kms con encrypter_decrypters); key_ids no depende de esas asignaciones.
  depends_on = [module.kms]
}
