# Pruebas unitarias sin GCP: proveedor simulado y solo plan.

mock_provider "google" {}

variables {
  project_id     = "example-prod-app"
  prefix         = "bnt"
  environment    = "prod"
  location       = "us-central1"
  network        = "projects/example-prod-net-spoke/global/networks/bnt-prod-net-vpc"
  subnet         = "projects/example-prod-net-spoke/regions/us-central1/subnetworks/bnt-prod-net-app-usc1"
  pods_range     = "pods"
  services_range = "services"
  master_cidr    = "10.30.38.0/28"

  gke_node_pools = {
    general = {
      machine_type   = "e2-standard-4"
      min_node_count = 1
      max_node_count = 3
    }
  }

  node_service_account         = "bnt-prod-app-gke-nodes@example-prod-app.iam.gserviceaccount.com"
  kms_key                      = "projects/example-common-security/locations/us-central1/keyRings/bnt-prod-sec-kr-usc1/cryptoKeys/gke"
  authenticator_security_group = "gke-security-groups@example.com"

  labels = {
    env         = "prod"
    app         = "app"
    owner       = "plataforma"
    cost_center = "ti-001"
    managed_by  = "terraform"
  }
}

run "nombres_siguen_la_convencion" {
  command = plan

  assert {
    condition     = google_container_cluster.this.name == "bnt-prod-app-gke-usc1"
    error_message = "El nombre del clúster no sigue <prefix>-<env>-app-<name>-<región>."
  }
  assert {
    condition     = google_container_node_pool.this["general"].name == "bnt-prod-app-np-general"
    error_message = "El nombre del pool no sigue la convención."
  }
  assert {
    condition     = google_container_cluster.this.location == "us-central1"
    error_message = "El clúster de prod debe ser regional."
  }
}

run "exige_configuracion_de_la_especificacion" {
  command = plan

  # Nodos privados y endpoint privado por defecto.
  assert {
    condition     = google_container_cluster.this.private_cluster_config[0].enable_private_nodes == true
    error_message = "Los nodos deben ser privados."
  }
  assert {
    condition     = google_container_cluster.this.private_cluster_config[0].enable_private_endpoint == true
    error_message = "El endpoint privado debe estar activo por defecto."
  }
  assert {
    condition     = google_container_cluster.this.private_cluster_config[0].master_ipv4_cidr_block == "10.30.38.0/28"
    error_message = "master_cidr no llega al clúster."
  }
  assert {
    condition     = google_container_cluster.this.master_authorized_networks_config[0].gcp_public_cidrs_access_enabled == false
    error_message = "No se debe permitir el acceso desde rangos públicos de Google Cloud."
  }
  # VPC nativa con rangos secundarios con nombre.
  assert {
    condition     = google_container_cluster.this.networking_mode == "VPC_NATIVE"
    error_message = "El clúster debe ser VPC nativo."
  }
  assert {
    condition     = google_container_cluster.this.ip_allocation_policy[0].cluster_secondary_range_name == "pods" && google_container_cluster.this.ip_allocation_policy[0].services_secondary_range_name == "services"
    error_message = "Los rangos secundarios no llegan al clúster."
  }
  # Workload Identity.
  assert {
    condition     = google_container_cluster.this.workload_identity_config[0].workload_pool == "example-prod-app.svc.id.goog"
    error_message = "Workload Identity debe usar <proyecto>.svc.id.goog."
  }
  assert {
    condition     = output.workload_pool == "example-prod-app.svc.id.goog"
    error_message = "La salida workload_pool no es la esperada."
  }
  assert {
    condition     = output.subnetwork == var.subnet && output.kms_key == var.kms_key && output.master_cidr == var.master_cidr
    error_message = "subnetwork, kms_key y master_cidr deben publicar lo configurado en el clúster."
  }
  # Binary Authorization.
  assert {
    condition     = google_container_cluster.this.binary_authorization[0].evaluation_mode == "PROJECT_SINGLETON_POLICY_ENFORCE"
    error_message = "Binary Authorization debe aplicarse."
  }
  # Shielded nodes y arranque seguro.
  assert {
    condition     = google_container_cluster.this.enable_shielded_nodes == true
    error_message = "Shielded nodes debe estar activo."
  }
  assert {
    condition = alltrue([
      for p in google_container_node_pool.this : p.node_config[0].shielded_instance_config[0].enable_secure_boot && p.node_config[0].shielded_instance_config[0].enable_integrity_monitoring
    ])
    error_message = "Los pools deben tener arranque seguro y monitoreo de integridad."
  }
  # CMEK en secretos y discos de arranque.
  assert {
    condition     = google_container_cluster.this.database_encryption[0].state == "ENCRYPTED" && google_container_cluster.this.database_encryption[0].key_name == var.kms_key
    error_message = "Los secretos deben cifrarse con la llave CMEK."
  }
  assert {
    condition     = alltrue([for p in google_container_node_pool.this : p.node_config[0].boot_disk_kms_key == var.kms_key])
    error_message = "Los discos de arranque de los nodos deben usar CMEK."
  }
  # Dataplane V2, canal de versiones, pool por defecto eliminado.
  assert {
    condition     = google_container_cluster.this.datapath_provider == "ADVANCED_DATAPATH"
    error_message = "Debe usarse Dataplane V2."
  }
  assert {
    condition     = google_container_cluster.this.release_channel[0].channel == "REGULAR"
    error_message = "El canal de versiones por defecto debe ser REGULAR."
  }
  assert {
    condition     = google_container_cluster.this.remove_default_node_pool == true
    error_message = "El pool por defecto debe eliminarse."
  }
  # Pools: autoescalado, autorreparación, autoactualización, cuenta dedicada, metadatos de GKE.
  assert {
    condition = alltrue([
      for p in google_container_node_pool.this : p.management[0].auto_repair && p.management[0].auto_upgrade
    ])
    error_message = "Los pools deben tener autorreparación y autoactualización."
  }
  assert {
    condition     = google_container_node_pool.this["general"].autoscaling[0].min_node_count == 1 && google_container_node_pool.this["general"].autoscaling[0].max_node_count == 3
    error_message = "El autoescalado del pool no refleja gke_node_pools."
  }
  assert {
    condition = alltrue([
      for p in google_container_node_pool.this : p.node_config[0].service_account == var.node_service_account && p.node_config[0].workload_metadata_config[0].mode == "GKE_METADATA"
    ])
    error_message = "Los pools deben usar la cuenta de servicio dedicada y GKE_METADATA."
  }
  # Etiquetas y protección contra borrado en prod.
  assert {
    condition     = google_container_cluster.this.resource_labels["managed_by"] == "terraform" && google_container_cluster.this.resource_labels["env"] == "prod"
    error_message = "Las etiquetas del clúster van en resource_labels."
  }
  assert {
    condition     = google_container_cluster.this.deletion_protection == true
    error_message = "En prod la protección contra borrado debe estar activa."
  }
}

run "prod_no_puede_apagar_la_proteccion_contra_borrado" {
  command = plan

  variables {
    deletion_protection = false
  }

  assert {
    condition     = google_container_cluster.this.deletion_protection == true
    error_message = "En prod deletion_protection debe seguir en true."
  }
}

run "dev_zonal_sin_proteccion" {
  command = plan

  variables {
    environment = "dev"
    location    = "us-central1-a"
    labels = {
      env         = "dev"
      app         = "app"
      owner       = "plataforma"
      cost_center = "ti-001"
      managed_by  = "terraform"
    }
  }

  assert {
    condition     = google_container_cluster.this.name == "bnt-dev-app-gke-usc1"
    error_message = "El nombre del clúster zonal debe usar el código de su región."
  }
  assert {
    condition     = google_container_cluster.this.deletion_protection == false
    error_message = "Fuera de prod la protección contra borrado sigue la variable."
  }
}

run "nodos_con_etiquetas_seguras" {
  command = plan

  variables {
    node_resource_manager_tags = { "tagKeys/111" = "tagValues/222" }
  }

  assert {
    condition     = alltrue([for p in google_container_node_pool.this : p.node_config[0].resource_manager_tags["tagKeys/111"] == "tagValues/222"])
    error_message = "Cada pool debe llevar las etiquetas seguras de node_resource_manager_tags."
  }
}

run "rechaza_etiqueta_segura_mal_formada" {
  command = plan

  variables {
    node_resource_manager_tags = { "lb_backend" = "tagValues/222" }
  }

  expect_failures = [var.node_resource_manager_tags]
}

run "rechaza_zona_en_prod" {
  command = plan

  variables {
    location = "us-central1-a"
  }

  expect_failures = [var.location]
}

run "rechaza_canal_rapid_en_prod" {
  command = plan

  variables {
    release_channel = "RAPID"
  }

  expect_failures = [var.release_channel]
}

run "rechaza_endpoint_publico_en_prod" {
  command = plan

  variables {
    enable_private_endpoint    = false
    master_authorized_networks = [{ cidr_block = "10.30.0.0/20", display_name = "subred-app" }]
  }

  expect_failures = [var.enable_private_endpoint]
}

run "rechaza_endpoint_publico_sin_redes_autorizadas" {
  command = plan

  variables {
    environment             = "dev"
    enable_private_endpoint = false
    labels = {
      env         = "dev"
      app         = "app"
      owner       = "plataforma"
      cost_center = "ti-001"
      managed_by  = "terraform"
    }
  }

  expect_failures = [var.master_authorized_networks]
}

run "rechaza_red_abierta" {
  command = plan

  variables {
    master_authorized_networks = [{ cidr_block = "0.0.0.0/0", display_name = "todo" }]
  }

  expect_failures = [var.master_authorized_networks]
}

run "rechaza_cuenta_de_compute_por_defecto" {
  command = plan

  variables {
    node_service_account = "123456789012-compute@developer.gserviceaccount.com"
  }

  expect_failures = [var.node_service_account]
}

run "rechaza_pool_con_minimo_mayor_al_maximo" {
  command = plan

  variables {
    gke_node_pools = {
      general = {
        machine_type   = "e2-standard-4"
        min_node_count = 4
        max_node_count = 2
      }
    }
  }

  expect_failures = [var.gke_node_pools]
}

run "rechaza_llave_en_otra_region" {
  command = plan

  variables {
    kms_key = "projects/example-common-security/locations/us-east4/keyRings/bnt-prod-sec-kr-use4/cryptoKeys/gke"
  }

  expect_failures = [google_container_cluster.this]
}

run "rechaza_etiquetas_incompletas" {
  command = plan

  variables {
    labels = {
      env        = "prod"
      managed_by = "terraform"
    }
  }

  expect_failures = [var.labels]
}
