mock_provider "google" {}

variables {
  project_id  = "example-prod-app"
  prefix      = "bnt"
  environment = "prod"
  labels = {
    env         = "prod"
    app         = "web"
    owner       = "plataforma"
    cost_center = "cc-0000"
    managed_by  = "terraform"
  }
  default_backend = "web"
  backends = {
    web = {
      groups          = [{ group = "projects/example-prod-app/regions/us-central1/instanceGroups/mig-usc1" }]
      dr_groups       = [{ group = "projects/example-prod-app/regions/us-east4/instanceGroups/mig-use4" }]
      health_check_id = "projects/example-prod-app/global/healthChecks/hc"
    }
    api = {
      serverless = true
      paths      = ["/api/*"]
      groups     = [{ group = "projects/example-prod-app/regions/us-central1/networkEndpointGroups/neg-usc1" }]
      dr_groups  = [{ group = "projects/example-prod-app/regions/us-east4/networkEndpointGroups/neg-use4" }]
    }
  }
}

run "externo_cumple_lo_exigido" {
  command = plan

  variables {
    type            = "external"
    domain_names    = ["app.example.com"]
    security_policy = "projects/example-prod-app/global/securityPolicies/armor"
  }

  assert {
    condition     = google_compute_global_address.this["this"].name == "bnt-prod-app-web-xlb-ip"
    error_message = "El nombre de la IP no sigue §4.2."
  }

  assert {
    condition     = google_compute_backend_service.this["web"].name == "bnt-prod-app-web-xlb-be-web"
    error_message = "El nombre del backend no sigue §4.2."
  }

  assert {
    condition     = alltrue([for b in google_compute_backend_service.this : b.load_balancing_scheme == "EXTERNAL_MANAGED"])
    error_message = "El externo debe ser EXTERNAL_MANAGED."
  }

  assert {
    condition     = alltrue([for b in google_compute_backend_service.this : b.security_policy == "projects/example-prod-app/global/securityPolicies/armor"])
    error_message = "Todos los backends deben llevar la política de Cloud Armor."
  }

  assert {
    condition     = alltrue([for b in google_compute_backend_service.this : b.log_config[0].enable])
    error_message = "Los backends deben registrar solicitudes."
  }

  assert {
    condition     = google_compute_managed_ssl_certificate.this["this"].managed[0].domains == tolist(["app.example.com"])
    error_message = "Falta el certificado administrado con los dominios."
  }

  assert {
    condition     = google_compute_ssl_policy.this["this"].min_tls_version == "TLS_1_2" && google_compute_ssl_policy.this["this"].profile == "MODERN"
    error_message = "La política SSL debe exigir TLS 1.2 o superior."
  }

  assert {
    condition     = google_compute_global_forwarding_rule.https["this"].port_range == "443" && google_compute_global_forwarding_rule.http["this"].port_range == "80"
    error_message = "Faltan las reglas de 443 y 80."
  }

  assert {
    condition     = google_compute_url_map.redirect["this"].default_url_redirect[0].https_redirect == true
    error_message = "Falta la redirección de HTTP a HTTPS."
  }

  assert {
    condition     = google_compute_global_forwarding_rule.https["this"].labels["managed_by"] == "terraform"
    error_message = "Las reglas de reenvío deben llevar etiquetas."
  }

  assert {
    condition     = [for b in google_compute_backend_service.this["web"].backend : b.group] == ["projects/example-prod-app/regions/us-central1/instanceGroups/mig-usc1"]
    error_message = "Sin dr_active los backends deben apuntar a la región primaria."
  }

  assert {
    condition     = google_compute_backend_service.this["api"].health_checks == null
    error_message = "El backend serverless no lleva verificación de salud."
  }

  assert {
    condition     = length(google_compute_url_map.this["this"].path_matcher[0].path_rule) == 1
    error_message = "Falta la regla de ruta /api/*."
  }

  assert {
    condition     = length(google_compute_region_backend_service.this) == 0 && length(google_compute_address.this) == 0
    error_message = "El externo no debe crear recursos del interno."
  }
}

run "externo_conmutado_a_dr" {
  command = plan

  variables {
    type            = "external"
    domain_names    = ["app.example.com"]
    security_policy = "projects/example-prod-app/global/securityPolicies/armor"
    dr_active       = true
  }

  assert {
    condition     = [for b in google_compute_backend_service.this["web"].backend : b.group] == ["projects/example-prod-app/regions/us-east4/instanceGroups/mig-use4"]
    error_message = "Con dr_active los backends deben apuntar a la región de DR."
  }

  assert {
    condition     = [for b in google_compute_backend_service.this["api"].backend : b.group] == ["projects/example-prod-app/regions/us-east4/networkEndpointGroups/neg-use4"]
    error_message = "Con dr_active el NEG serverless debe ser el de DR."
  }
}

run "interno_cumple_lo_exigido" {
  command = plan

  variables {
    type         = "internal"
    region       = "us-central1"
    network      = "projects/example-net/global/networks/vpc"
    subnet       = "projects/example-net/regions/us-central1/subnetworks/app"
    domain_names = ["core.example.com"]
    backends = {
      web = {
        groups       = [{ group = "projects/example-prod-app/regions/us-central1/instanceGroups/mig-usc1" }]
        health_check = { port = 8080 }
      }
    }
  }

  assert {
    condition     = google_compute_region_backend_service.this["web"].name == "bnt-prod-app-web-ilb-usc1-be-web"
    error_message = "El nombre del backend interno no sigue §4.2 (con código de región)."
  }

  assert {
    condition     = google_compute_region_backend_service.this["web"].load_balancing_scheme == "INTERNAL_MANAGED"
    error_message = "El interno debe ser INTERNAL_MANAGED."
  }

  assert {
    condition     = google_compute_region_health_check.this["web"].http_health_check[0].port == 8080
    error_message = "El módulo debe crear la verificación de salud regional."
  }

  assert {
    condition     = google_compute_address.this["this"].address_type == "INTERNAL" && google_compute_address.this["this"].purpose == "SHARED_LOADBALANCER_VIP"
    error_message = "La IP del interno debe ser interna y compartida entre 443 y 80."
  }

  assert {
    condition     = google_compute_forwarding_rule.https["this"].load_balancing_scheme == "INTERNAL_MANAGED" && google_compute_forwarding_rule.https["this"].port_range == "443"
    error_message = "Falta la regla de reenvío HTTPS interna."
  }

  # Acceso global: on-premises y otras regiones llegan al balanceador de cualquier región.
  assert {
    condition     = google_compute_forwarding_rule.https["this"].allow_global_access == true && google_compute_forwarding_rule.http["this"].allow_global_access == true
    error_message = "Las reglas de reenvío internas (443 y 80) deben tener allow_global_access = true."
  }

  assert {
    condition     = output.backend_groups["web"] == tolist(["projects/example-prod-app/regions/us-central1/instanceGroups/mig-usc1"]) && keys(output.backend_groups) == ["web"]
    error_message = "backend_groups debe publicar los grupos configurados en cada servicio de backend."
  }

  assert {
    condition     = google_compute_region_url_map.redirect["this"].default_url_redirect[0].https_redirect == true
    error_message = "Falta la redirección de HTTP a HTTPS en el interno."
  }

  assert {
    condition     = google_compute_region_ssl_policy.this["this"].min_tls_version == "TLS_1_2"
    error_message = "La política SSL regional debe exigir TLS 1.2."
  }

  assert {
    condition     = google_certificate_manager_certificate.this["this"].managed[0].domains == tolist(["core.example.com"])
    error_message = "Falta el certificado administrado regional."
  }

  assert {
    condition     = length(google_compute_backend_service.this) == 0 && length(google_compute_global_address.this) == 0
    error_message = "El interno no debe crear recursos del externo."
  }
}

run "interno_con_certificado_propio" {
  command = plan

  variables {
    type                             = "internal"
    region                           = "us-east4"
    network                          = "projects/example-net/global/networks/vpc"
    subnet                           = "projects/example-net/regions/us-east4/subnetworks/app-dr"
    certificate_manager_certificates = ["projects/example-prod-app/locations/us-east4/certificates/core-internal"]
    backends = {
      web = {
        groups       = [{ group = "projects/example-prod-app/regions/us-east4/instanceGroups/mig-use4" }]
        health_check = {}
      }
    }
  }

  assert {
    condition     = length(google_certificate_manager_certificate.this) == 0
    error_message = "Con certificados propios no se crea uno nuevo."
  }

  assert {
    condition     = google_compute_region_target_https_proxy.this["this"].certificate_manager_certificates == tolist(["projects/example-prod-app/locations/us-east4/certificates/core-internal"])
    error_message = "El proxy debe usar los certificados propios."
  }

  assert {
    condition     = output.internal_certificate_ids == tolist(["projects/example-prod-app/locations/us-east4/certificates/core-internal"])
    error_message = "La salida internal_certificate_ids debe publicar los certificados del proxy."
  }

  assert {
    condition     = google_compute_address.this["this"].name == "bnt-prod-app-web-ilb-use4-ip"
    error_message = "El nombre debe llevar el código de la región de DR."
  }
}

run "rechaza_externo_sin_cloud_armor" {
  command = plan

  variables {
    type         = "external"
    domain_names = ["app.example.com"]
  }

  expect_failures = [var.security_policy]
}

run "rechaza_externo_sin_dominios" {
  command = plan

  variables {
    type            = "external"
    security_policy = "projects/example-prod-app/global/securityPolicies/armor"
  }

  expect_failures = [var.domain_names]
}

run "rechaza_interno_sin_red" {
  command = plan

  variables {
    type         = "internal"
    region       = "us-central1"
    domain_names = ["core.example.com"]
    backends = {
      web = {
        groups       = [{ group = "projects/example-prod-app/regions/us-central1/instanceGroups/mig-usc1" }]
        health_check = {}
      }
    }
  }

  expect_failures = [var.network, var.subnet]
}

run "rechaza_backend_sin_verificacion_de_salud" {
  command = plan

  variables {
    type            = "external"
    domain_names    = ["app.example.com"]
    security_policy = "projects/example-prod-app/global/securityPolicies/armor"
    backends = {
      web = {
        groups = [{ group = "projects/example-prod-app/regions/us-central1/instanceGroups/mig-usc1" }]
      }
    }
  }

  expect_failures = [var.backends]
}

# "" no es un modo válido (coalesce lo trataría como null y lo dejaría pasar).
run "rechaza_modo_de_balanceo_vacio" {
  command = plan

  variables {
    type            = "external"
    domain_names    = ["app.example.com"]
    security_policy = "projects/example-prod-app/global/securityPolicies/armor"
    backends = {
      web = {
        groups          = [{ group = "projects/example-prod-app/regions/us-central1/instanceGroups/mig-usc1", balancing_mode = "" }]
        health_check_id = "projects/example-prod-app/global/healthChecks/hc"
      }
    }
  }

  expect_failures = [var.backends]
}

run "rechaza_registro_apagado" {
  command = plan

  variables {
    type            = "external"
    domain_names    = ["app.example.com"]
    security_policy = "projects/example-prod-app/global/securityPolicies/armor"
    backends = {
      web = {
        groups          = [{ group = "projects/example-prod-app/regions/us-central1/instanceGroups/mig-usc1" }]
        health_check_id = "projects/example-prod-app/global/healthChecks/hc"
        log_sample_rate = 0
      }
    }
  }

  expect_failures = [var.backends]
}

run "rechaza_dr_activo_sin_grupos_de_dr" {
  command = plan

  variables {
    type            = "external"
    domain_names    = ["app.example.com"]
    security_policy = "projects/example-prod-app/global/securityPolicies/armor"
    dr_active       = true
    backends = {
      web = {
        groups          = [{ group = "projects/example-prod-app/regions/us-central1/instanceGroups/mig-usc1" }]
        health_check_id = "projects/example-prod-app/global/healthChecks/hc"
      }
    }
  }

  expect_failures = [var.dr_active]
}

run "rechaza_backend_por_defecto_inexistente" {
  command = plan

  variables {
    type            = "external"
    domain_names    = ["app.example.com"]
    security_policy = "projects/example-prod-app/global/securityPolicies/armor"
    default_backend = "otro"
  }

  expect_failures = [var.default_backend]
}
