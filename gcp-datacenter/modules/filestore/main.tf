locals {
  region        = var.tier == "ZONAL" ? replace(var.location, "/-[a-z]$/", "") : var.location
  instance_name = "${var.prefix}-${var.environment}-data-${var.name}-${var.region_short_codes[local.region]}"

  # Filestore espera la ruta projects/<proyecto>/global/networks/<red>; se quita el prefijo
  # https://... si llega un self link.
  network = regex("projects/[^/]+/global/networks/[^/]+$", var.network)
}

resource "google_filestore_instance" "this" {
  project     = var.project_id
  name        = local.instance_name
  description = "Filestore ${local.instance_name} (${var.tier})"
  location    = var.location
  tier        = var.tier
  labels      = var.labels

  # CMEK obligatorio (el tier ya se limitó a los que lo admiten).
  kms_key_name = var.kms_key

  deletion_protection_enabled = var.deletion_protection
  deletion_protection_reason  = var.deletion_protection ? "Datos de ${var.environment}: protección exigida por el módulo." : null

  file_shares {
    name        = var.share_name
    capacity_gb = var.capacity_gb

    dynamic "nfs_export_options" {
      for_each = var.nfs_export_options
      content {
        ip_ranges   = nfs_export_options.value.ip_ranges
        access_mode = nfs_export_options.value.access_mode
        squash_mode = nfs_export_options.value.squash_mode
        anon_uid    = nfs_export_options.value.anon_uid
        anon_gid    = nfs_export_options.value.anon_gid
      }
    }
  }

  # Red por Private Service Access sobre la VPC del spoke del entorno; solo IP privada.
  networks {
    network           = local.network
    modes             = ["MODE_IPV4"]
    connect_mode      = "PRIVATE_SERVICE_ACCESS"
    reserved_ip_range = var.reserved_ip_range
  }

  # VERIFICAR-EN-APPLY: el agente de servicio de Filestore tiene
  # roles/cloudkms.cryptoKeyEncrypterDecrypter sobre kms_key (lo otorga 1-base, kms.tf), la
  # instancia se crea con PRIVATE_SERVICE_ACCESS sobre la red del spoke, y
  # deletion_protection_enabled se acepta en el tier elegido.
}
