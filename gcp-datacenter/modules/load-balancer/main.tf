locals {
  is_external = var.type == "external"
  is_internal = var.type == "internal"

  # Conjuntos de una sola llave para crear los recursos de cada tipo sin count ni moved.
  external = local.is_external ? toset(["this"]) : toset([])
  internal = local.is_internal ? toset(["this"]) : toset([])

  region_code = var.region == null ? null : var.region_short_codes[var.region]

  # §4.2: <empresa>-<entorno>-app-<nombre>-<xlb|ilb>[-<región>].
  base_name = (
    local.is_external
    ? "${var.prefix}-${var.environment}-app-${var.name}-xlb"
    : "${var.prefix}-${var.environment}-app-${var.name}-ilb-${coalesce(local.region_code, "none")}"
  )

  # Grupos activos según la conmutación a DR.
  active_groups = {
    for k, b in var.backends : k => (var.dr_active ? b.dr_groups : b.groups)
  }

  # Verificaciones de salud que crea el módulo.
  created_health_checks = {
    for k, b in var.backends : k => b.health_check if b.health_check != null
  }

  module_health_check_ids = merge(
    { for k, h in google_compute_health_check.this : k => h.id },
    { for k, h in google_compute_region_health_check.this : k => h.id },
  )

  health_check_ids = {
    for k, b in var.backends : k => (
      b.serverless ? null : coalesce(b.health_check_id, lookup(local.module_health_check_ids, k, null))
    )
  }

  path_backends = { for k, b in var.backends : k => b.paths if length(b.paths) > 0 }

  # Certificado del balanceador externo: el nombre cambia con los dominios para poder
  # reemplazarlo con create_before_destroy.
  cert_suffix = substr(sha256(join(",", sort(var.domain_names))), 0, 8)

  create_internal_cert = local.is_internal && length(var.certificate_manager_certificates) == 0
  internal_cert_domains = local.create_internal_cert ? {
    for d in var.domain_names : replace(d, ".", "-") => d
  } : {}
}

# ---------------------------------------------------------------------------------------------
# Verificaciones de salud creadas por el módulo (global para external, regional para internal)
# ---------------------------------------------------------------------------------------------

resource "google_compute_health_check" "this" {
  for_each = local.is_external ? local.created_health_checks : {}

  project             = var.project_id
  name                = "${local.base_name}-hc-${each.key}"
  check_interval_sec  = each.value.check_interval_sec
  timeout_sec         = each.value.timeout_sec
  healthy_threshold   = each.value.healthy_threshold
  unhealthy_threshold = each.value.unhealthy_threshold

  dynamic "http_health_check" {
    for_each = each.value.protocol == "HTTP" ? [1] : []
    content {
      port               = each.value.port
      port_specification = each.value.port == null ? "USE_SERVING_PORT" : "USE_FIXED_PORT"
      request_path       = each.value.request_path
    }
  }

  dynamic "https_health_check" {
    for_each = each.value.protocol == "HTTPS" ? [1] : []
    content {
      port               = each.value.port
      port_specification = each.value.port == null ? "USE_SERVING_PORT" : "USE_FIXED_PORT"
      request_path       = each.value.request_path
    }
  }

  dynamic "http2_health_check" {
    for_each = each.value.protocol == "HTTP2" ? [1] : []
    content {
      port               = each.value.port
      port_specification = each.value.port == null ? "USE_SERVING_PORT" : "USE_FIXED_PORT"
      request_path       = each.value.request_path
    }
  }

  log_config {
    enable = true
  }
}

resource "google_compute_region_health_check" "this" {
  for_each = local.is_internal ? local.created_health_checks : {}

  project             = var.project_id
  region              = var.region
  name                = "${local.base_name}-hc-${each.key}"
  check_interval_sec  = each.value.check_interval_sec
  timeout_sec         = each.value.timeout_sec
  healthy_threshold   = each.value.healthy_threshold
  unhealthy_threshold = each.value.unhealthy_threshold

  dynamic "http_health_check" {
    for_each = each.value.protocol == "HTTP" ? [1] : []
    content {
      port               = each.value.port
      port_specification = each.value.port == null ? "USE_SERVING_PORT" : "USE_FIXED_PORT"
      request_path       = each.value.request_path
    }
  }

  dynamic "https_health_check" {
    for_each = each.value.protocol == "HTTPS" ? [1] : []
    content {
      port               = each.value.port
      port_specification = each.value.port == null ? "USE_SERVING_PORT" : "USE_FIXED_PORT"
      request_path       = each.value.request_path
    }
  }

  dynamic "http2_health_check" {
    for_each = each.value.protocol == "HTTP2" ? [1] : []
    content {
      port               = each.value.port
      port_specification = each.value.port == null ? "USE_SERVING_PORT" : "USE_FIXED_PORT"
      request_path       = each.value.request_path
    }
  }

  log_config {
    enable = true
  }
}

# ---------------------------------------------------------------------------------------------
# Balanceador de aplicaciones externo global (EXTERNAL_MANAGED)
# ---------------------------------------------------------------------------------------------

resource "google_compute_backend_service" "this" {
  for_each = local.is_external ? var.backends : {}

  project               = var.project_id
  name                  = "${local.base_name}-be-${each.key}"
  description           = each.value.description
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = each.value.protocol
  port_name             = each.value.serverless ? null : each.value.port_name
  timeout_sec           = each.value.serverless ? null : each.value.timeout_sec
  health_checks         = each.value.serverless ? null : [local.health_check_ids[each.key]]
  security_policy       = var.security_policy

  connection_draining_timeout_sec = each.value.serverless ? null : each.value.connection_draining_timeout_sec

  dynamic "backend" {
    for_each = local.active_groups[each.key]
    content {
      group                 = backend.value.group
      balancing_mode        = each.value.serverless ? null : coalesce(backend.value.balancing_mode, "UTILIZATION")
      capacity_scaler       = backend.value.capacity_scaler
      max_utilization       = backend.value.max_utilization
      max_rate_per_instance = backend.value.max_rate_per_instance
      max_rate_per_endpoint = backend.value.max_rate_per_endpoint
    }
  }

  log_config {
    enable      = true
    sample_rate = each.value.log_sample_rate
  }
}

resource "google_compute_global_address" "this" {
  for_each = local.external

  project      = var.project_id
  name         = "${local.base_name}-ip"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
  labels       = var.labels
}

# VERIFICAR-EN-APPLY: el certificado administrado solo pasa a ACTIVE cuando los registros DNS A de
# domain_names apuntan a la IP del balanceador (salida ip_address); puede tardar hasta 60 min.
resource "google_compute_managed_ssl_certificate" "this" {
  for_each = local.external

  project = var.project_id
  name    = "${local.base_name}-cert-${local.cert_suffix}"

  managed {
    domains = var.domain_names
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_ssl_policy" "this" {
  for_each = local.external

  project         = var.project_id
  name            = "${local.base_name}-ssl"
  profile         = var.ssl_policy_profile
  min_tls_version = "TLS_1_2"
}

resource "google_compute_url_map" "this" {
  for_each = local.external

  project         = var.project_id
  name            = "${local.base_name}-um"
  default_service = google_compute_backend_service.this[var.default_backend].id

  dynamic "host_rule" {
    for_each = length(local.path_backends) > 0 ? [1] : []
    content {
      hosts        = ["*"]
      path_matcher = "paths"
    }
  }

  dynamic "path_matcher" {
    for_each = length(local.path_backends) > 0 ? [1] : []
    content {
      name            = "paths"
      default_service = google_compute_backend_service.this[var.default_backend].id

      dynamic "path_rule" {
        for_each = local.path_backends
        content {
          paths   = path_rule.value
          service = google_compute_backend_service.this[path_rule.key].id
        }
      }
    }
  }
}

resource "google_compute_target_https_proxy" "this" {
  for_each = local.external

  project          = var.project_id
  name             = "${local.base_name}-https-proxy"
  url_map          = google_compute_url_map.this["this"].id
  ssl_certificates = [google_compute_managed_ssl_certificate.this["this"].id]
  ssl_policy       = google_compute_ssl_policy.this["this"].id
}

resource "google_compute_global_forwarding_rule" "https" {
  for_each = local.external

  project               = var.project_id
  name                  = "${local.base_name}-https"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol           = "TCP"
  port_range            = "443"
  ip_address            = google_compute_global_address.this["this"].id
  target                = google_compute_target_https_proxy.this["this"].id
  labels                = var.labels
}

# Redirección de HTTP a HTTPS en la misma IP.
resource "google_compute_url_map" "redirect" {
  for_each = local.external

  project = var.project_id
  name    = "${local.base_name}-redirect-um"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  for_each = local.external

  project = var.project_id
  name    = "${local.base_name}-http-proxy"
  url_map = google_compute_url_map.redirect["this"].id
}

resource "google_compute_global_forwarding_rule" "http" {
  for_each = local.external

  project               = var.project_id
  name                  = "${local.base_name}-http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol           = "TCP"
  port_range            = "80"
  ip_address            = google_compute_global_address.this["this"].id
  target                = google_compute_target_http_proxy.redirect["this"].id
  labels                = var.labels
}

# ---------------------------------------------------------------------------------------------
# Balanceador de aplicaciones interno regional (INTERNAL_MANAGED) en la Shared VPC.
# Precondición: la subred proxy-only (purpose REGIONAL_MANAGED_PROXY) de var.region existe en la
# VPC (la crea network-spoke, llaves proxy y proxy_dr de §5). El módulo no la crea.
# ---------------------------------------------------------------------------------------------

resource "google_compute_region_backend_service" "this" {
  for_each = local.is_internal ? var.backends : {}

  project               = var.project_id
  region                = var.region
  name                  = "${local.base_name}-be-${each.key}"
  description           = each.value.description
  load_balancing_scheme = "INTERNAL_MANAGED"
  protocol              = each.value.protocol
  port_name             = each.value.serverless ? null : each.value.port_name
  timeout_sec           = each.value.serverless ? null : each.value.timeout_sec
  health_checks         = each.value.serverless ? null : [local.health_check_ids[each.key]]

  connection_draining_timeout_sec = each.value.serverless ? null : each.value.connection_draining_timeout_sec

  dynamic "backend" {
    for_each = local.active_groups[each.key]
    content {
      group                 = backend.value.group
      balancing_mode        = each.value.serverless ? null : coalesce(backend.value.balancing_mode, "UTILIZATION")
      capacity_scaler       = backend.value.capacity_scaler
      max_utilization       = backend.value.max_utilization
      max_rate_per_instance = backend.value.max_rate_per_instance
      max_rate_per_endpoint = backend.value.max_rate_per_endpoint
    }
  }

  log_config {
    enable      = true
    sample_rate = each.value.log_sample_rate
  }
}

# IP interna compartida por las reglas de 443 y 80.
resource "google_compute_address" "this" {
  for_each = local.internal

  project      = var.project_id
  region       = var.region
  name         = "${local.base_name}-ip"
  address_type = "INTERNAL"
  purpose      = "SHARED_LOADBALANCER_VIP"
  subnetwork   = var.subnet
  address      = var.internal_ip_address
  labels       = var.labels
}

# Certificado regional administrado por Google con autorización DNS (solo si no se pasan
# certificados propios). VERIFICAR-EN-APPLY: el certificado se emite solo después de crear en la
# zona DNS pública los registros de la salida dns_authorization_records; una CA pública no emite
# para dominios privados (*.internal): para esos se pasan certificate_manager_certificates.
resource "google_certificate_manager_dns_authorization" "this" {
  for_each = local.internal_cert_domains

  project  = var.project_id
  location = var.region
  name     = "${local.base_name}-dnsauth-${substr(sha256(each.value), 0, 8)}"
  domain   = each.value
  type     = "PER_PROJECT_RECORD"
  labels   = var.labels
}

resource "google_certificate_manager_certificate" "this" {
  for_each = local.create_internal_cert ? local.internal : toset([])

  project  = var.project_id
  location = var.region
  name     = "${local.base_name}-cert-${local.cert_suffix}"
  labels   = var.labels

  managed {
    domains            = var.domain_names
    dns_authorizations = [for k in keys(local.internal_cert_domains) : google_certificate_manager_dns_authorization.this[k].id]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_region_ssl_policy" "this" {
  for_each = local.internal

  project         = var.project_id
  region          = var.region
  name            = "${local.base_name}-ssl"
  profile         = var.ssl_policy_profile
  min_tls_version = "TLS_1_2"
}

resource "google_compute_region_url_map" "this" {
  for_each = local.internal

  project         = var.project_id
  region          = var.region
  name            = "${local.base_name}-um"
  default_service = google_compute_region_backend_service.this[var.default_backend].id

  dynamic "host_rule" {
    for_each = length(local.path_backends) > 0 ? [1] : []
    content {
      hosts        = ["*"]
      path_matcher = "paths"
    }
  }

  dynamic "path_matcher" {
    for_each = length(local.path_backends) > 0 ? [1] : []
    content {
      name            = "paths"
      default_service = google_compute_region_backend_service.this[var.default_backend].id

      dynamic "path_rule" {
        for_each = local.path_backends
        content {
          paths   = path_rule.value
          service = google_compute_region_backend_service.this[path_rule.key].id
        }
      }
    }
  }
}

resource "google_compute_region_target_https_proxy" "this" {
  for_each = local.internal

  project    = var.project_id
  region     = var.region
  name       = "${local.base_name}-https-proxy"
  url_map    = google_compute_region_url_map.this["this"].id
  ssl_policy = google_compute_region_ssl_policy.this["this"].id
  certificate_manager_certificates = (
    local.create_internal_cert
    ? [google_certificate_manager_certificate.this["this"].id]
    : var.certificate_manager_certificates
  )
}

resource "google_compute_forwarding_rule" "https" {
  for_each = local.internal

  project               = var.project_id
  region                = var.region
  name                  = "${local.base_name}-https"
  load_balancing_scheme = "INTERNAL_MANAGED"
  ip_protocol           = "TCP"
  port_range            = "443"
  network               = var.network
  subnetwork            = var.subnet
  ip_address            = google_compute_address.this["this"].id
  target                = google_compute_region_target_https_proxy.this["this"].id
  # Acceso global: clientes de otras regiones de la VPC y on-premises por túneles o adjuntos de
  # VLAN de otra región llegan al balanceador (sin esto, solo los de var.region). Hace falta para
  # que la conmutación a DR no deje sin servicio a on-premises.
  # VERIFICAR-EN-APPLY: on-premises llega a la IP del balanceador de la región de DR por la VPN
  # de la región primaria y por la de DR.
  allow_global_access = true
  labels              = var.labels
}

resource "google_compute_region_url_map" "redirect" {
  for_each = local.internal

  project = var.project_id
  region  = var.region
  name    = "${local.base_name}-redirect-um"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_region_target_http_proxy" "redirect" {
  for_each = local.internal

  project = var.project_id
  region  = var.region
  name    = "${local.base_name}-http-proxy"
  url_map = google_compute_region_url_map.redirect["this"].id
}

resource "google_compute_forwarding_rule" "http" {
  for_each = local.internal

  project               = var.project_id
  region                = var.region
  name                  = "${local.base_name}-http"
  load_balancing_scheme = "INTERNAL_MANAGED"
  ip_protocol           = "TCP"
  port_range            = "80"
  network               = var.network
  subnetwork            = var.subnet
  ip_address            = google_compute_address.this["this"].id
  target                = google_compute_region_target_http_proxy.redirect["this"].id
  # Las dos reglas comparten la IP (SHARED_LOADBALANCER_VIP): mismo acceso global que la de 443.
  allow_global_access = true
  labels              = var.labels
}
