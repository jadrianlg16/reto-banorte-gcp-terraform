# Plantilla regional de instancias (Shielded VM, sin IP pública, disco CMEK, cuenta de servicio
# dedicada), MIG regional con autocuración y actualización progresiva, autoescalador regional y
# verificación de salud. Lo que exige la especificación queda fijo, no como opción.

locals {
  region_code = lookup(var.region_codes, var.region, "")
  base_name   = "${var.prefix}-${var.environment}-app-${var.name}-${local.region_code}"

  subnet_region = regex("regions/([^/]+)/subnetworks/", var.subnet)[0]
  kms_location  = regex("locations/([^/]+)/keyRings/", var.kms_key)[0]

  # Metadatos endurecidos: van al final para que no se puedan sobrescribir.
  metadata = merge(var.metadata, {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
    serial-port-enable     = "FALSE"
  })

  # Un MIG regional sin zonas explícitas reparte en tres zonas. Con valores fijos, el
  # sobreaprovisionamiento de la actualización debe ser 0 o al menos el número de zonas.
  zone_count = length(var.distribution_zones) > 0 ? length(var.distribution_zones) : 3
}

resource "google_compute_region_instance_template" "this" {
  project     = var.project_id
  region      = var.region
  name_prefix = "${local.base_name}-"
  description = "Plantilla ${var.environment} de ${var.name} (administrada por Terraform)."

  machine_type   = var.machine_type
  can_ip_forward = false

  disk {
    boot         = true
    auto_delete  = true
    source_image = var.image
    disk_size_gb = var.disk_size_gb
    disk_type    = var.disk_type
    labels       = var.labels

    disk_encryption_key {
      kms_key_self_link = var.kms_key
    }
  }

  # Solo IP interna: no hay access_config ni ipv6_access_config.
  network_interface {
    subnetwork = var.subnet
  }

  service_account {
    email  = var.service_account
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
  }

  metadata = local.metadata
  tags     = var.network_tags
  # VERIFICAR-EN-APPLY: que las etiquetas seguras de la plantilla queden en las instancias del MIG y las reglas de firewall del spoke (lb_backend) las apliquen.
  resource_manager_tags = var.resource_manager_tags
  labels                = var.labels

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = local.region_code != ""
      error_message = "La región no está en region_codes."
    }
    precondition {
      condition     = length(local.base_name) <= 36
      error_message = "El nombre base supera 36 caracteres (límite de name_prefix de la plantilla); acorta prefix o name."
    }
    precondition {
      condition     = local.subnet_region == var.region
      error_message = "La subred debe estar en la misma región que el MIG."
    }
    precondition {
      condition     = local.kms_location == var.region
      error_message = "La llave KMS debe estar en la misma región que el MIG."
    }
  }
}

# Verificación de salud global: sirve para la autocuración del MIG y la puede reutilizar un
# servicio de backend global. Un balanceador interno regional necesita su propia verificación
# regional (la crea el módulo load-balancer).
resource "google_compute_health_check" "this" {
  project = var.project_id
  name    = "${local.base_name}-hc"

  check_interval_sec  = var.health_check.check_interval_sec
  timeout_sec         = var.health_check.timeout_sec
  healthy_threshold   = var.health_check.healthy_threshold
  unhealthy_threshold = var.health_check.unhealthy_threshold

  dynamic "http_health_check" {
    for_each = var.health_check.protocol == "HTTP" ? [1] : []
    content {
      port         = var.health_check.port
      request_path = var.health_check.request_path
    }
  }

  dynamic "https_health_check" {
    for_each = var.health_check.protocol == "HTTPS" ? [1] : []
    content {
      port         = var.health_check.port
      request_path = var.health_check.request_path
    }
  }

  dynamic "tcp_health_check" {
    for_each = var.health_check.protocol == "TCP" ? [1] : []
    content {
      port = var.health_check.port
    }
  }

  log_config {
    enable = true
  }
}

resource "google_compute_region_instance_group_manager" "this" {
  project            = var.project_id
  region             = var.region
  name               = local.base_name
  base_instance_name = local.base_name
  description        = "MIG ${var.environment} de ${var.name} (administrado por Terraform)."

  distribution_policy_zones = length(var.distribution_zones) > 0 ? var.distribution_zones : null

  version {
    instance_template = google_compute_region_instance_template.this.self_link
  }

  dynamic "named_port" {
    for_each = var.named_ports
    content {
      name = named_port.key
      port = named_port.value
    }
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.this.id
    initial_delay_sec = var.health_check.initial_delay_sec
  }

  # VERIFICAR-EN-APPLY: que GCP acepte max_surge_fixed igual al número de zonas del MIG regional.
  update_policy {
    type                         = "PROACTIVE"
    minimal_action               = "REPLACE"
    instance_redistribution_type = "PROACTIVE"
    replacement_method           = "SUBSTITUTE"
    max_surge_fixed              = local.zone_count
    max_unavailable_fixed        = 0
  }

  # El tamaño lo decide el autoescalador; no se fija target_size.
  wait_for_instances = false
}

resource "google_compute_region_autoscaler" "this" {
  project = var.project_id
  region  = var.region
  name    = "${local.base_name}-as"
  target  = google_compute_region_instance_group_manager.this.id

  autoscaling_policy {
    min_replicas    = var.min_replicas
    max_replicas    = var.max_replicas
    cooldown_period = var.cooldown_period
    mode            = "ON"

    cpu_utilization {
      target = var.cpu_target
    }
  }
}
