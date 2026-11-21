# Etapa 2 (§7.2), en el proyecto security: llaveros y llaves por entorno y ubicación,
# contenedores de secretos por entorno (sin valores, ADR 0015) y perímetro de VPC-SC de prod
# (ADR 0009, dry-run por defecto).

locals {
  # Ubicaciones de los llaveros: las dos regiones y la multirregión us (buckets de doble región).
  multi_region = "us"
  locations    = [var.primary_region, var.dr_region, local.multi_region]

  # Usos de llave (§7.2). En la multirregión solo storage y backup.
  regional_key_uses     = ["gke", "compute", "sql", "storage", "filestore", "redis", "secrets", "backup", "run"]
  multi_region_key_uses = ["storage", "backup"]

  # Agente de servicio de Secret Manager del proyecto security. Se arma con el número del
  # proyecto leído del estado de 1-org (conocido en el plan), porque el miembro es la llave del
  # for_each de encrypter_decrypters en el módulo kms.
  secretmanager_agent = "serviceAccount:service-${local.security_project_number}@gcp-sa-secretmanager.iam.gserviceaccount.com"

  keyrings = {
    for pair in setproduct(var.environments, local.locations) : "${pair[0]}/${pair[1]}" => {
      environment = pair[0]
      location    = pair[1]
      # La llave secrets de cada región la usa el agente de Secret Manager (CMEK de las
      # réplicas); los demás permisos sobre las llaves los da la etapa 4.
      keys = {
        for u in(pair[1] == local.multi_region ? local.multi_region_key_uses : local.regional_key_uses) : u => {
          encrypter_decrypters = u == "secrets" ? [local.secretmanager_agent] : []
        }
      }
    }
  }

  # Entornos con al menos un secreto.
  secret_envs = { for e in var.environments : e => distinct(lookup(var.secret_names, e, [])) if length(lookup(var.secret_names, e, [])) > 0 }

  labels_by_env = {
    for e in var.environments : e => merge(var.labels, {
      env        = e
      managed_by = "terraform"
    })
  }
}

# --- Llaves KMS ---------------------------------------------------------------------------

# Crea el agente de Secret Manager del proyecto si todavía no existe, antes de darle permisos.
resource "google_project_service_identity" "secretmanager" {
  provider = google-beta

  project = local.security_project_id
  service = "secretmanager.googleapis.com"
}

module "kms" {
  source   = "../../modules/kms"
  for_each = local.keyrings

  project_id           = local.security_project_id
  prefix               = var.prefix
  environment          = each.value.environment
  location             = each.value.location
  location_short_codes = var.location_short_codes
  keys                 = each.value.keys
  rotation_period      = var.key_rotation_period
  labels               = merge(local.labels_by_env[each.value.environment], { app = "kms" })

  depends_on = [google_project_service_identity.secretmanager]
}

# --- Secretos (contenedores sin valores) ---------------------------------------------------

module "secrets" {
  source   = "../../modules/secrets"
  for_each = local.secret_envs

  project_id  = local.security_project_id
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

# --- VPC Service Controls (ADR 0009, 0019) -------------------------------------------------

module "vpc_sc" {
  source = "../../modules/vpc-sc"

  org_id           = var.org_id
  prefix           = var.prefix
  environment      = "prod"
  access_policy_id = var.access_policy_id
  # El proyecto security entra aquí; la etapa 4 agrega los proyectos de prod.
  resources           = ["projects/${local.security_project_number}"]
  restricted_services = var.vpc_sc_restricted_services
  # Regla de entrada para todas las cuentas de servicio del pipeline.
  ingress_identities = [for k in sort(keys(local.stage_service_accounts)) : "serviceAccount:${local.stage_service_accounts[k]}"]
  enforced           = var.vpc_sc_enforced
}

# --- Permisos para la etapa 4 --------------------------------------------------------------

# 4-projects agrega los proyectos de prod al perímetro (§7.5): editor solo de esta política.
resource "google_access_context_manager_access_policy_iam_member" "projects_stage" {
  name   = "accessPolicies/${module.vpc_sc.access_policy_id}"
  role   = "roles/accesscontextmanager.policyEditor"
  member = "serviceAccount:${local.stage_service_accounts["4-projects"]}"
}

# 4-projects da a los agentes de servicio permiso sobre las llaves y lectura de secretos
# (§7.5): rol personalizado de la etapa 0, solo IAM de llaves y secretos de este proyecto.
module "iam" {
  source = "../../modules/iam"

  bindings = [
    {
      key      = "sa|4-projects|project:security|kms-secret-iam-granter"
      scope    = "project"
      resource = local.security_project_id
      role     = local.kms_secret_iam_role_id
      member   = "serviceAccount:${local.stage_service_accounts["4-projects"]}"
    },
  ]
}
