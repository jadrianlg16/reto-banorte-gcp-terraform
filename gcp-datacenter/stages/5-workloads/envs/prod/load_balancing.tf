# Balanceadores en el proyecto de servicio (ADR 0005): HTTPS global externo con Cloud Armor y
# certificado administrado para domain_names, y, con enable_internal_lb, uno interno regional en
# la Shared VPC (subred proxy-only del spoke).
#
# Backends del externo, según lo que esté habilitado:
#   run  NEG sin servidor de cada servicio de Cloud Run (sin verificación de salud).
#   mig  grupo de instancias del MIG regional, con la verificación de salud del propio MIG.
#   gke  NEG zonales que crea GKE al desplegar un Service con la anotación cloud.google.com/neg.
#        No existen hasta que la carga se despliega (fuera de Terraform): sus self links entran
#        por var.gke_lb_negs después del primer despliegue y se aplica otra vez. Vacío: sin
#        backend de GKE.
# Con dr_active cada servicio de backend pasa de groups (región primaria) a dr_groups (región de
# DR), con el mecanismo dr_active del módulo load-balancer.

locals {
  # Catálogo completo; los valores de un cómputo apagado quedan en null y se filtran abajo.
  external_backend_catalog = {
    run = {
      description = "Cloud Run (NEG sin servidor)"
      serverless  = true
      groups      = [{ group = try(module.cloud_run["primary"].neg_id, null) }]
      dr_groups   = var.dr_active ? [{ group = try(module.cloud_run["dr"].neg_id, null) }] : []
      paths       = lookup(var.lb_backend_paths, "run", [])
    }
    mig = {
      description     = "MIG regional de VM"
      port_name       = "http"
      groups          = [{ group = try(module.mig["primary"].instance_group, null) }]
      dr_groups       = var.dr_active ? [{ group = try(module.mig["dr"].instance_group, null) }] : []
      health_check_id = try(module.mig[local.active_key].health_check_id, null)
      paths           = lookup(var.lb_backend_paths, "mig", [])
    }
    gke = {
      description = "NEG zonales de GKE"
      port_name   = "http"
      groups = [
        for n in var.gke_lb_negs.primary : {
          group                 = n
          balancing_mode        = "RATE"
          max_rate_per_endpoint = var.gke_lb_negs.max_rate_per_endpoint
        }
      ]
      dr_groups = var.dr_active ? [
        for n in var.gke_lb_negs.dr : {
          group                 = n
          balancing_mode        = "RATE"
          max_rate_per_endpoint = var.gke_lb_negs.max_rate_per_endpoint
        }
      ] : []
      health_check = {
        protocol     = "HTTP"
        request_path = var.gke_lb_negs.health_check_path
      }
      paths = lookup(var.lb_backend_paths, "gke", [])
    }
  }

  external_backend_enabled = {
    run = var.enable_cloud_run
    mig = var.enable_mig
    gke = var.enable_gke && length(var.gke_lb_negs.primary) > 0
  }

  external_backends = {
    for k, b in local.external_backend_catalog : k => b if local.external_backend_enabled[k]
  }

  # Sin ningún backend (por ejemplo, solo GKE antes de conocer sus NEG) no se crea el balanceador.
  external_lb_enabled = anytrue(values(local.external_backend_enabled))

  external_default_backend = coalesce(
    var.lb_default_backend,
    try([for k in ["run", "mig", "gke"] : k if local.external_backend_enabled[k]][0], "run"),
  )

  # El interno atiende a clientes de la VPC y on-premises (por el hub) con los mismos MIG y
  # Cloud Run; GKE expone sus servicios internos con su propio Ingress/Gateway interno.
  # VERIFICAR-EN-APPLY: que el mismo grupo de instancias y el mismo NEG sin servidor se acepten a la vez como backend del balanceador externo global y del interno regional.
  internal_backend_catalog = {
    run = {
      description = "Cloud Run (NEG sin servidor)"
      serverless  = true
      groups      = [{ group = try(module.cloud_run["primary"].neg_id, null) }]
      dr_groups   = var.dr_active ? [{ group = try(module.cloud_run["dr"].neg_id, null) }] : []
      paths       = lookup(var.lb_backend_paths, "run", [])
    }
    mig = {
      description = "MIG regional de VM"
      port_name   = "http"
      groups      = [{ group = try(module.mig["primary"].instance_group, null) }]
      dr_groups   = var.dr_active ? [{ group = try(module.mig["dr"].instance_group, null) }] : []
      # El interno regional necesita una verificación de salud regional: la crea el módulo.
      health_check = {
        protocol     = "HTTP"
        port         = var.mig_http_port
        request_path = var.mig_health_check_path
      }
      paths = lookup(var.lb_backend_paths, "mig", [])
    }
  }

  internal_backend_enabled = {
    run = var.enable_cloud_run
    mig = var.enable_mig
  }

  internal_backends = {
    for k, b in local.internal_backend_catalog : k => b if local.internal_backend_enabled[k]
  }

  internal_lb_enabled = var.enable_internal_lb && anytrue(values(local.internal_backend_enabled))

  # El mismo backend por defecto que el externo si el interno lo tiene; si no, run o mig.
  internal_default_backend = (
    lookup(local.internal_backend_enabled, coalesce(var.lb_default_backend, "run"), false)
    ? coalesce(var.lb_default_backend, "run")
    : (var.enable_cloud_run ? "run" : "mig")
  )
}

module "cloud_armor" {
  source   = "../../../../modules/cloud-armor"
  for_each = local.external_lb_enabled ? toset(["external"]) : toset([])

  project_id  = local.project_id
  prefix      = var.prefix
  environment = var.environment
  name        = var.application

  depends_on = [terraform_data.upstream_checks]
}

module "external_lb" {
  source   = "../../../../modules/load-balancer"
  for_each = local.external_lb_enabled ? toset(["external"]) : toset([])

  project_id         = local.project_id
  prefix             = var.prefix
  environment        = var.environment
  name               = var.application
  type               = "external"
  region_short_codes = var.region_codes

  backends        = local.external_backends
  default_backend = local.external_default_backend
  dr_active       = var.dr_active

  # VERIFICAR-EN-APPLY: el certificado administrado solo se activa cuando los registros DNS A de domain_names apuntan a lb_ip_address (zona pública fuera de este repositorio).
  domain_names    = var.domain_names
  security_policy = module.cloud_armor["external"].policy_self_link

  labels = local.labels
}

module "internal_lb" {
  source   = "../../../../modules/load-balancer"
  for_each = local.internal_lb_enabled ? toset(["internal"]) : toset([])

  project_id         = local.project_id
  prefix             = var.prefix
  environment        = var.environment
  name               = var.application
  type               = "internal"
  region_short_codes = var.region_codes

  # Región activa: la primaria o, con dr_active, la de DR (sus subredes app_dr y proxy_dr). Al
  # conmutar, el balanceador interno se recrea en la región de DR (su nombre lleva la región).
  region  = local.active_region
  network = local.network_self_link
  subnet  = local.subnets[local.subnet_keys[local.active_key].app].self_link

  backends        = local.internal_backends
  default_backend = local.internal_default_backend
  dr_active       = var.dr_active

  # VERIFICAR-EN-APPLY: crear en la zona DNS pública del dominio los registros de dns_authorization_records para que se emita el certificado interno.
  domain_names = var.internal_domain_names

  labels = local.labels

  depends_on = [terraform_data.upstream_checks]
}
