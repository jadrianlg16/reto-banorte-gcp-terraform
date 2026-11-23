# Raíz del spoke de un entorno (contrato §7.4, ADR 0003, 0004 y 0014): proyecto net-spoke
# como host de Shared VPC, VPC spoke unida al hub por peering, política de firewall de red
# con etiquetas seguras y DNS. Las tres raíces envs/{dev,qa,prod} son idénticas salvo
# backend.tf y terraform.tfvars.example.
#
# Archivos: main.tf (proyecto y red), firewall.tf (política de red) y dns.tf (zonas).
#
# Los spokes se aplican de uno en uno: cada uno crea su peering sobre la VPC hub y GCP no
# admite dos operaciones de peering a la vez sobre la misma red.

locals {
  labels = merge(var.labels, {
    env        = var.environment
    managed_by = "terraform"
  })

  # Llaves *_dr activas solo con enable_dr (en dev y qa se reservan pero no se crean).
  active_keys = [
    for k in keys(var.subnet_cidrs) : k if var.enable_dr || !endswith(k, "_dr")
  ]
  active_cidrs = { for k in local.active_keys : k => var.subnet_cidrs[k] }
}

# Proyecto <prefix>-<env>-net-spoke en la carpeta del entorno, habilitado como host de
# Shared VPC. APIs: Compute (red), DNS, Service Networking (Private Service Access), GKE
# (un clúster de un proyecto de servicio sobre Shared VPC exige la API también en el host) y
# Network Management: las Connectivity Tests de la prueba de humo de dev (apply.yml, trabajo
# "dev / prueba de humo", tests/e2e) se crean en este proyecto, y la API tiene que estar
# habilitada en el proyecto donde se crean. Se declara aquí y no a mano: una API habilitada a
# mano la reporta el trabajo de recursos no administrados de drift.yml (pendiente 50).
module "project" {
  source = "../../../../modules/project-factory"

  prefix          = var.prefix
  environment     = var.environment
  name            = "net-spoke"
  project_suffix  = var.project_suffix
  folder_id       = local.folder_id
  billing_account = var.billing_account
  shared_vpc_host = true
  deletion_policy = var.project_deletion_policy
  labels          = local.labels

  apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "dns.googleapis.com",
    "networkmanagement.googleapis.com",
    "servicenetworking.googleapis.com",
  ]
}

# VPC spoke: subredes de §5 con Private Google Access y flow logs, proxy-only, Private
# Service Access, peering con el hub en los dos sentidos (el hub exporta rutas
# personalizadas y el spoke las importa), rutas al VIP restringido y de salida, y un Cloud
# Router con Cloud NAT por región activa (ADR 0004).
module "spoke" {
  source = "../../../../modules/network-spoke"

  project_id            = module.project.project_id
  prefix                = var.prefix
  environment           = var.environment
  enable_dr             = var.enable_dr
  subnet_cidrs          = var.subnet_cidrs
  hub_network_self_link = local.hub_network_self_link
  flow_log_sampling     = var.flow_log_sampling
  region_short_names    = var.region_short_names
  labels                = local.labels

  regions = {
    primary = var.primary_region
    dr      = var.dr_region
  }
}
