locals {
  instance_name = "${var.prefix}-${var.environment}-data-${var.name}-${var.region_short_codes[var.region]}"

  # En prod siempre STANDARD_HA (la validación de tier rechaza BASIC en prod).
  tier = coalesce(var.tier, var.environment == "prod" ? "STANDARD_HA" : "BASIC")
}

resource "google_redis_instance" "this" {
  # checkov:skip=CKV_GCP_95: AUTH apagado a propósito: la cadena AUTH es un valor generado que quedaría en el estado de Terraform, lo que prohíbe el ADR 0015. El acceso se limita por red privada (PSA), VPC-SC y TLS con autenticación del servidor.
  project        = var.project_id
  name           = local.instance_name
  display_name   = local.instance_name
  region         = var.region
  tier           = local.tier
  memory_size_gb = var.memory_gb
  redis_version  = var.redis_version
  redis_configs  = var.redis_configs
  labels         = var.labels

  location_id             = var.location_id
  alternative_location_id = local.tier == "STANDARD_HA" ? var.alternative_location_id : null

  # Solo IP privada: la instancia toma su IP del rango de Private Service Access de la VPC.
  authorized_network = var.network
  connect_mode       = "PRIVATE_SERVICE_ACCESS"
  reserved_ip_range  = var.reserved_ip_range

  # CMEK obligatorio.
  customer_managed_key = var.kms_key

  # TLS obligatorio en tránsito (el puerto pasa a 6378). Los clientes validan el certificado
  # del servidor con server_ca_certs.
  transit_encryption_mode = "SERVER_AUTHENTICATION"

  # Ver checkov:skip de arriba y el README: sin AUTH para no guardar un secreto en el estado.
  auth_enabled = false

  dynamic "persistence_config" {
    for_each = var.rdb_snapshot_period == null ? [] : [var.rdb_snapshot_period]
    content {
      persistence_mode    = "RDB"
      rdb_snapshot_period = persistence_config.value
    }
  }

  maintenance_policy {
    weekly_maintenance_window {
      day = var.maintenance_window.day
      start_time {
        hours   = var.maintenance_window.hour
        minutes = 0
        seconds = 0
        nanos   = 0
      }
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.instance_name) <= 40
      error_message = "El nombre de la instancia de Redis no puede pasar de 40 caracteres."
    }
  }

  # VERIFICAR-EN-APPLY: el agente de servicio de Memorystore tiene
  # roles/cloudkms.cryptoKeyEncrypterDecrypter sobre kms_key (lo otorga 1-base, kms.tf) y la
  # instancia se crea con PRIVATE_SERVICE_ACCESS sobre la red del spoke del entorno.
}
