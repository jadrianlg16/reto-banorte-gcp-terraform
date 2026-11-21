# Clúster de GKE estándar, privado y VPC nativo sobre una VPC compartida, con pools de nodos
# administrados aparte. Los valores que exige la especificación (nodos privados, Workload
# Identity, Binary Authorization, Shielded nodes, CMEK) son fijos y no se exponen como opción.

locals {
  # Región de la ubicación: "us-central1-a" → "us-central1"; una región queda igual.
  region       = regex("^[a-z]+-[a-z]+[0-9]+", var.location)
  region_code  = lookup(var.region_codes, local.region, "")
  cluster_name = "${var.prefix}-${var.environment}-app-${var.name}-${local.region_code}"

  subnet_region = regex("regions/([^/]+)/subnetworks/", var.subnet)[0]
  kms_location  = regex("locations/([^/]+)/keyRings/", var.kms_key)[0]

  # En prod la protección contra borrado es fija, salvo el retiro deliberado (teardown) de una
  # instancia que se va a destruir, como el clúster de DR en la vuelta a la región primaria.
  deletion_protection = var.teardown ? false : (var.environment == "prod" ? true : var.deletion_protection)

  workload_pool = "${var.project_id}.svc.id.goog"

  oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  node_metadata = {
    disable-legacy-endpoints = "true"
  }
}

resource "google_container_cluster" "this" {
  # checkov:skip=CKV_GCP_12: Con Dataplane V2 (ADVANCED_DATAPATH) la política de red de Kubernetes la aplica el plano de datos y el bloque network_policy no se puede declarar

  project     = var.project_id
  name        = local.cluster_name
  location    = var.location
  description = "Clúster ${var.environment} de ${var.name} (administrado por Terraform)."

  # Red: VPC compartida del proyecto host, VPC nativa con rangos secundarios con nombre.
  network         = var.network
  subnetwork      = var.subnet
  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range
    services_secondary_range_name = var.services_range
  }

  # Dataplane V2: aplica las NetworkPolicy de Kubernetes sin el bloque network_policy.
  datapath_provider           = "ADVANCED_DATAPATH"
  enable_intranode_visibility = true

  # VERIFICAR-EN-APPLY: si la versión de GKE crea el plano de control con Private Service Connect, master_ipv4_cidr_block (gke_master) queda reservado sin uso (pendiente 8 del contrato).
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_cidr

    # Permite llegar al endpoint privado desde otras regiones de la VPC (por ejemplo, la de DR).
    master_global_access_config {
      enabled = true
    }
  }

  # VERIFICAR-EN-APPLY: que el endpoint privado sea alcanzable desde la VPC compartida y desde los rangos autorizados (el peering del plano de control no es transitivo hacia el hub ni on-premises).
  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false

    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  authenticator_groups_config {
    security_group = var.authenticator_security_group
  }

  workload_identity_config {
    workload_pool = local.workload_pool
  }

  # La política de Binary Authorization es del proyecto (google_binary_authorization_policy) y
  # no la crea este módulo; aquí se fija que el clúster la aplique.
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  enable_shielded_nodes = true
  enable_legacy_abac    = false

  # Cifrado de los secretos de Kubernetes en la capa de aplicación con CMEK.
  database_encryption {
    state    = "ENCRYPTED"
    key_name = var.kms_key
  }

  release_channel {
    channel = var.release_channel
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
    }
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    gke_backup_agent_config {
      enabled = var.enable_backup_agent
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  # El pool por defecto se elimina en cuanto se crea el clúster; los pools reales son
  # google_container_node_pool.this. Mientras existe, usa la misma configuración endurecida.
  remove_default_node_pool = true
  initial_node_count       = 1

  # VERIFICAR-EN-APPLY: que node_config del pool por defecto (ya eliminado) no produzca diferencias en el segundo plan; por eso se ignora en lifecycle.
  node_config {
    service_account   = var.node_service_account
    oauth_scopes      = local.oauth_scopes
    image_type        = "COS_CONTAINERD"
    boot_disk_kms_key = var.kms_key
    metadata          = local.node_metadata

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  resource_labels     = var.labels
  deletion_protection = local.deletion_protection

  lifecycle {
    ignore_changes = [node_config, initial_node_count]

    precondition {
      condition     = local.region_code != ""
      error_message = "La región del clúster no está en region_codes."
    }
    precondition {
      condition     = length(local.cluster_name) <= 40
      error_message = "El nombre del clúster supera 40 caracteres; acorta prefix o name."
    }
    precondition {
      condition     = local.subnet_region == local.region
      error_message = "La subred debe estar en la misma región que el clúster."
    }
    precondition {
      condition     = local.kms_location == local.region
      error_message = "La llave KMS debe estar en la misma región que el clúster."
    }
  }
}

resource "google_container_node_pool" "this" {
  for_each = var.gke_node_pools

  project  = var.project_id
  location = var.location
  cluster  = google_container_cluster.this.name
  name     = "${var.prefix}-${var.environment}-app-np-${each.key}"

  node_locations     = each.value.node_locations
  initial_node_count = max(each.value.min_node_count, 1)

  autoscaling {
    min_node_count = each.value.min_node_count
    max_node_count = each.value.max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = each.value.max_surge
    max_unavailable = each.value.max_unavailable
  }

  node_config {
    machine_type      = each.value.machine_type
    image_type        = "COS_CONTAINERD"
    disk_size_gb      = each.value.disk_size_gb
    disk_type         = each.value.disk_type
    boot_disk_kms_key = var.kms_key
    spot              = each.value.spot

    service_account = var.node_service_account
    oauth_scopes    = local.oauth_scopes
    metadata        = local.node_metadata

    labels          = each.value.k8s_labels
    resource_labels = var.labels

    # Etiquetas seguras de las VM de los nodos (por ejemplo lb_backend de la etapa 3, para que
    # el firewall del spoke deje pasar al balanceador y sus verificaciones de salud hacia los NEG).
    # VERIFICAR-EN-APPLY: que los nodos de un proyecto de servicio acepten etiquetas seguras del proyecto host (roles/resourcemanager.tagUser de la etapa 4 al agente de servicio de GKE).
    resource_manager_tags = var.node_resource_manager_tags

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    kubelet_config {
      insecure_kubelet_readonly_port_enabled = "FALSE"
    }
  }

  lifecycle {
    # El autoescalador cambia el tamaño; initial_node_count solo cuenta al crear.
    ignore_changes = [initial_node_count]

    precondition {
      condition     = length("${var.prefix}-${var.environment}-app-np-${each.key}") <= 40
      error_message = "El nombre del pool supera 40 caracteres; acorta prefix o la llave del pool."
    }
  }
}
