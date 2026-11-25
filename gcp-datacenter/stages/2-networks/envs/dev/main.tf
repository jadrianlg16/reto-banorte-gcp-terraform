# Raíz del spoke de un entorno (ADR 0029 §2 y §6; ADR 0003, 0004 y 0014): VPC spoke en el
# proyecto único de la landing zone (project_id), unida al hub por peering, política de
# firewall de red con etiquetas seguras y DNS. Sin Shared VPC: las cargas del entorno
# (3-workloads/<env>) usan esta VPC desde el mismo proyecto. Las tres raíces
# envs/{dev,qa,prod} son idénticas salvo backend.tf y terraform.tfvars.example.
#
# Archivos: main.tf (red), firewall.tf (política de red) y dns.tf (zonas).
#
# Regla de recursos únicos (ADR 0029 §4): esta raíz no declara APIs ni nada que exista una vez
# por proyecto (las APIs que usa, compute, dns y servicenetworking, debe habilitarlas
# 0-bootstrap; las métricas y alertas de auditoría viven en 1-base), ni permisos de proyecto.
# Lo que crea lleva <prefix>-<env>- en el nombre, salvo lo que GCP nombra dentro de un padre
# propio del entorno (reglas de la política, valores de etiqueta y registros DNS).
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

# VPC spoke: subredes de §5 con Private Google Access y flow logs, proxy-only, Private
# Service Access, peering con el hub en los dos sentidos (el hub exporta rutas
# personalizadas y el spoke las importa), rutas al VIP restringido y de salida, y un Cloud
# Router con Cloud NAT por región activa (ADR 0004).
module "spoke" {
  source = "../../../../modules/network-spoke"

  project_id            = var.project_id
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
