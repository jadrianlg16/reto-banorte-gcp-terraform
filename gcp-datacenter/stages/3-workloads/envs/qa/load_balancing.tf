# Balanceadores del entorno en el proyecto único (ADR 0005 y ADR 0029): HTTPS global externo con
# Cloud Armor y certificado administrado para domain_names, y, con enable_internal_lb, uno
# interno regional en la VPC del spoke (subred proxy-only del spoke).
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

  # Certificado del balanceador interno por región, separado del balanceador: existe en la
  # región primaria y, con enable_dr, también en la de DR aunque dr_active sea false. Así el
  # certificado de DR se emite antes de un incidente y la conmutación solo crea el balanceador.
  internal_cert_regions = local.internal_lb_enabled ? (var.enable_dr ? local.regions : { primary = var.primary_region }) : {}

  # "<región>/<dominio con guiones>" → región y dominio de cada autorización DNS.
  internal_cert_authorizations = merge([
    for region_key in keys(local.internal_cert_regions) : {
      for d in var.internal_domain_names : "${region_key}/${replace(d, ".", "-")}" => {
        region_key = region_key
        domain     = d
      }
    }
  ]...)

  # Mismo nombre base que el balanceador interno de cada región (§4.2, módulo load-balancer).
  internal_lb_base_names = {
    for k, r in local.regions : k => "${var.prefix}-${var.environment}-app-${var.application}-ilb-${var.region_codes[r]}"
  }
  internal_cert_suffix = substr(sha256(join(",", sort(var.internal_domain_names))), 0, 8)

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

  project_id  = var.project_id
  prefix      = var.prefix
  environment = var.environment
  name        = var.application

  depends_on = [terraform_data.upstream_checks]
}

module "external_lb" {
  source   = "../../../../modules/load-balancer"
  for_each = local.external_lb_enabled ? toset(["external"]) : toset([])

  project_id         = var.project_id
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

  project_id         = var.project_id
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

  # Certificado de su región, creado abajo y no por el módulo: el de DR ya existe (y está
  # emitido) antes de que dr_active cree este balanceador.
  certificate_manager_certificates = [google_certificate_manager_certificate.internal[each.key].id]

  labels = local.labels

  depends_on = [terraform_data.upstream_checks]
}

# Autorizaciones DNS y certificado administrado por Google del balanceador interno, uno por
# región de local.internal_cert_regions (primaria y, con enable_dr, DR). Mismos nombres que
# creaba el módulo load-balancer cuando no recibía certificados.
# VERIFICAR-EN-APPLY: crear en la zona DNS pública del dominio los registros de la salida
# internal_lb_dns_authorization_records_by_region (los de las dos regiones, antes de un
# incidente) y que el certificado regional de DR quede ACTIVE sin balanceador que lo use.
resource "google_certificate_manager_dns_authorization" "internal" {
  for_each = local.internal_cert_authorizations

  project  = var.project_id
  location = local.regions[each.value.region_key]
  name     = "${local.internal_lb_base_names[each.value.region_key]}-dnsauth-${substr(sha256(each.value.domain), 0, 8)}"
  domain   = each.value.domain
  type     = "PER_PROJECT_RECORD"
  labels   = local.labels

  depends_on = [terraform_data.upstream_checks]
}

resource "google_certificate_manager_certificate" "internal" {
  for_each = local.internal_cert_regions

  project  = var.project_id
  location = each.value
  name     = "${local.internal_lb_base_names[each.key]}-cert-${local.internal_cert_suffix}"
  labels   = local.labels

  managed {
    domains = var.internal_domain_names
    dns_authorizations = [
      for k, a in local.internal_cert_authorizations : google_certificate_manager_dns_authorization.internal[k].id if a.region_key == each.key
    ]
  }

  # El nombre cambia con los dominios: el nuevo se emite antes de soltar el anterior.
  lifecycle {
    create_before_destroy = true
  }
}
