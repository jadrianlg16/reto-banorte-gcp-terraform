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
# Con dr_active cada servicio de backend del externo pasa de groups (región primaria) a
# dr_groups (región de DR), con el mecanismo dr_active del módulo load-balancer. GKE es la
# excepción: los NEG del clúster de DR solo existen después de desplegar la carga en él (paso 6
# del runbook de conmutación), así que mientras gke_lb_negs.dr esté vacío el backend gke queda
# fuera del externo (y el backend por defecto pasa al primero habilitado). Si GKE es el único
# backend, se queda con los NEG primarios: el balanceador y su IP no se destruyen.
# El interno es regional: uno por región con cómputo (local.compute_regions), cada uno con los
# backends de su región. Conmutar agrega el de DR y no toca el primario.

locals {
  gke_negs_active = var.dr_active ? var.gke_lb_negs.dr : var.gke_lb_negs.primary

  # Sin NEG de DR con dr_active, GKE sigue en el externo solo si no hay otro backend.
  gke_only_backend = !var.enable_cloud_run && !var.enable_mig
  gke_external_negs = (
    length(local.gke_negs_active) > 0 ? local.gke_negs_active :
    var.dr_active && local.gke_only_backend ? var.gke_lb_negs.primary : []
  )

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
    # groups y dr_groups llevan los NEG que de verdad se usan (local.gke_external_negs): con
    # dr_active el módulo toma dr_groups y exige groups no vacío.
    gke = {
      description = "NEG zonales de GKE"
      port_name   = "http"
      groups = [
        for n in local.gke_external_negs : {
          group                 = n
          balancing_mode        = "RATE"
          max_rate_per_endpoint = var.gke_lb_negs.max_rate_per_endpoint
        }
      ]
      dr_groups = var.dr_active ? [
        for n in local.gke_external_negs : {
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
    gke = var.enable_gke && length(local.gke_external_negs) > 0
  }

  external_backends = {
    for k, b in local.external_backend_catalog : k => b if local.external_backend_enabled[k]
  }

  # Sin ningún backend (por ejemplo, solo GKE antes de conocer sus NEG) no se crea el balanceador.
  external_lb_enabled = anytrue(values(local.external_backend_enabled))

  # lb_default_backend si está habilitado; si no (por ejemplo gke durante la conmutación antes
  # de tener NEG de DR), el primero habilitado en el orden run, mig, gke.
  external_default_backend = (
    lookup(local.external_backend_enabled, coalesce(var.lb_default_backend, "-"), false)
    ? var.lb_default_backend
    : try([for k in ["run", "mig", "gke"] : k if local.external_backend_enabled[k]][0], "run")
  )

  # El interno atiende a clientes de la VPC y on-premises (por el hub) con los mismos MIG y
  # Cloud Run; GKE expone sus servicios internos con su propio Ingress/Gateway interno.
  # VERIFICAR-EN-APPLY: que el mismo grupo de instancias y el mismo NEG sin servidor se acepten a la vez como backend del balanceador externo global y del interno regional.
  # Región (primary o dr) → backends con los grupos de esa región: un servicio de backend
  # regional solo admite backends de su región.
  internal_backend_catalog = {
    for region_key in keys(local.compute_regions) : region_key => {
      run = {
        description = "Cloud Run (NEG sin servidor)"
        serverless  = true
        groups      = [{ group = try(module.cloud_run[region_key].neg_id, null) }]
        paths       = lookup(var.lb_backend_paths, "run", [])
      }
      mig = {
        description = "MIG regional de VM"
        port_name   = "http"
        groups      = [{ group = try(module.mig[region_key].instance_group, null) }]
        # El interno regional necesita una verificación de salud regional: la crea el módulo.
        health_check = {
          protocol     = "HTTP"
          port         = var.mig_http_port
          request_path = var.mig_health_check_path
        }
        paths = lookup(var.lb_backend_paths, "mig", [])
      }
    }
  }

  internal_backend_enabled = {
    run = var.enable_cloud_run
    mig = var.enable_mig
  }

  internal_backends = {
    for region_key, catalog in local.internal_backend_catalog : region_key => {
      for k, b in catalog : k => b if local.internal_backend_enabled[k]
    }
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

# Uno por región con cómputo (llaves primary y dr, estables): con dr_active se agrega el de la
# región de DR (subredes app_dr y proxy_dr) y el primario no se destruye ni se recrea. Las
# reglas de reenvío tienen acceso global (módulo), así que on-premises llega a cualquiera de los
# dos por la VPN de cualquier región; el registro DNS interno decide a cuál va el tráfico.
module "internal_lb" {
  source   = "../../../../modules/load-balancer"
  for_each = local.internal_lb_enabled ? local.compute_regions : {}

  project_id         = local.project_id
  prefix             = var.prefix
  environment        = var.environment
  name               = var.application
  type               = "internal"
  region_short_codes = var.region_codes

  region  = each.value
  network = local.network_self_link
  subnet  = local.subnets[local.subnet_keys[each.key].app].self_link

  backends        = local.internal_backends[each.key]
  default_backend = local.internal_default_backend

  # VERIFICAR-EN-APPLY: crear en la zona DNS pública del dominio los registros de dns_authorization_records para que se emita el certificado interno (uno por región).
  domain_names = var.internal_domain_names

  labels = local.labels

  depends_on = [terraform_data.upstream_checks]
}

# Antes de esta versión el balanceador interno tenía la llave fija "internal" (región primaria).
moved {
  from = module.internal_lb["internal"]
  to   = module.internal_lb["primary"]
}
