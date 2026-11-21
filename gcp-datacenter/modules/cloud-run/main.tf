# Servicio de Cloud Run v2 con salida directa a la VPC compartida, entrada solo interna y del
# balanceador, cuenta de servicio propia y CMEK; más el NEG sin servidor que usa el balanceador.

locals {
  region_code = lookup(var.region_codes, var.region, "")
  base_name   = "${var.prefix}-${var.environment}-app-${var.name}-${local.region_code}"

  # Cloud Run espera rutas de recurso (projects/...), no URL de la API de Compute.
  # VERIFICAR-EN-APPLY: que la salida directa a la VPC acepte la red y la subred del proyecto host como rutas projects/<host>/... (VPC compartida).
  network_path = trimprefix(var.network, "https://www.googleapis.com/compute/v1/")
  subnet_path  = trimprefix(var.subnet, "https://www.googleapis.com/compute/v1/")

  subnet_region = regex("regions/([^/]+)/subnetworks/", var.subnet)[0]
  kms_location  = regex("locations/([^/]+)/keyRings/", var.kms_key)[0]

  deletion_protection = var.environment == "prod" ? true : var.deletion_protection
}

resource "google_cloud_run_v2_service" "this" {
  project     = var.project_id
  location    = var.region
  name        = local.base_name
  description = "Servicio ${var.environment} de ${var.name} (administrado por Terraform)."

  # Solo tráfico interno y del balanceador de cargas; nunca la URL pública run.app abierta.
  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  # La verificación de IAM del invocador queda activa: sin permiso run.invoker no hay acceso.
  invoker_iam_disabled = false

  deletion_protection = local.deletion_protection
  labels              = var.labels

  dynamic "binary_authorization" {
    for_each = var.enable_binary_authorization ? [1] : []
    content {
      use_default = true
    }
  }

  template {
    service_account                  = var.service_account
    encryption_key                   = var.kms_key
    execution_environment            = "EXECUTION_ENVIRONMENT_GEN2"
    max_instance_request_concurrency = var.concurrency
    timeout                          = var.request_timeout
    labels                           = var.labels

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    # Salida directa a la VPC (sin conector de Acceso a VPC sin servidor).
    vpc_access {
      egress = var.vpc_egress
      network_interfaces {
        network    = local.network_path
        subnetwork = local.subnet_path
        tags       = var.network_tags
      }
    }

    containers {
      image = var.image

      ports {
        container_port = var.container_port
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      dynamic "env" {
        for_each = var.env_vars
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.secret_env
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret
              version = env.value.version
            }
          }
        }
      }

      dynamic "startup_probe" {
        for_each = var.health_check_path == null ? [] : [var.health_check_path]
        content {
          http_get {
            path = startup_probe.value
            port = var.container_port
          }
        }
      }

      dynamic "liveness_probe" {
        for_each = var.health_check_path == null ? [] : [var.health_check_path]
        content {
          http_get {
            path = liveness_probe.value
            port = var.container_port
          }
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    precondition {
      condition     = local.region_code != ""
      error_message = "La región no está en region_codes."
    }
    precondition {
      condition     = length(local.base_name) <= 45
      error_message = "El nombre del servicio supera 45 caracteres (Cloud Run admite 49 y el NEG agrega -neg); acorta prefix o name."
    }
    precondition {
      condition     = local.subnet_region == var.region
      error_message = "La subred debe estar en la misma región que el servicio."
    }
    precondition {
      condition     = local.kms_location == var.region
      error_message = "La llave KMS debe estar en la misma región que el servicio."
    }
  }
}

# Invocadores explícitos; la validación de var.invokers impide allUsers, allAuthenticatedUsers y user:.
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  for_each = toset(var.invokers)

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = each.value
}

# NEG sin servidor: el módulo load-balancer lo recibe como backend genérico (salida neg_id).
resource "google_compute_region_network_endpoint_group" "this" {
  project               = var.project_id
  region                = var.region
  name                  = "${local.base_name}-neg"
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.this.name
  }
}
