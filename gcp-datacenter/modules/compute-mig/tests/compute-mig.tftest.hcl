# Pruebas unitarias sin GCP: proveedor simulado y solo plan.

mock_provider "google" {}

variables {
  project_id      = "example-prod-app"
  prefix          = "bnt"
  environment     = "prod"
  region          = "us-central1"
  subnet          = "projects/example-prod-net-spoke/regions/us-central1/subnetworks/bnt-prod-net-app-usc1"
  image           = "projects/example-images/global/images/family/example-hardened-linux"
  machine_type    = "e2-standard-2"
  min_replicas    = 2
  max_replicas    = 6
  service_account = "bnt-prod-app-mig@example-prod-app.iam.gserviceaccount.com"
  kms_key         = "projects/example-common-security/locations/us-central1/keyRings/bnt-prod-sec-kr-usc1/cryptoKeys/compute"

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
    condition     = google_compute_region_instance_group_manager.this.name == "bnt-prod-app-mig-usc1"
    error_message = "El nombre del MIG no sigue <prefix>-<env>-app-<name>-<región>."
  }
  assert {
    condition     = google_compute_region_instance_template.this.name_prefix == "bnt-prod-app-mig-usc1-"
    error_message = "El prefijo de la plantilla no sigue la convención."
  }
  assert {
    condition     = google_compute_health_check.this.name == "bnt-prod-app-mig-usc1-hc"
    error_message = "El nombre de la verificación de salud no sigue la convención."
  }
  assert {
    condition     = google_compute_region_autoscaler.this.name == "bnt-prod-app-mig-usc1-as"
    error_message = "El nombre del autoescalador no sigue la convención."
  }
}

run "exige_configuracion_de_la_especificacion" {
  command = plan

  # Shielded VM completo.
  assert {
    condition = (
      google_compute_region_instance_template.this.shielded_instance_config[0].enable_secure_boot &&
      google_compute_region_instance_template.this.shielded_instance_config[0].enable_vtpm &&
      google_compute_region_instance_template.this.shielded_instance_config[0].enable_integrity_monitoring
    )
    error_message = "La plantilla debe tener arranque seguro, vTPM y monitoreo de integridad."
  }
  # Sin IP pública.
  assert {
    condition     = length(google_compute_region_instance_template.this.network_interface[0].access_config) == 0 && length(google_compute_region_instance_template.this.network_interface[0].ipv6_access_config) == 0
    error_message = "La plantilla no debe tener access_config (IP pública)."
  }
  assert {
    condition     = google_compute_region_instance_template.this.can_ip_forward == false
    error_message = "El reenvío de IP debe estar apagado."
  }
  # Imagen por variable y disco con CMEK.
  assert {
    condition     = google_compute_region_instance_template.this.disk[0].source_image == var.image
    error_message = "La imagen debe venir de la variable image."
  }
  assert {
    condition     = google_compute_region_instance_template.this.disk[0].disk_encryption_key[0].kms_key_self_link == var.kms_key
    error_message = "El disco de arranque debe cifrarse con la llave CMEK."
  }
  # Cuenta de servicio dedicada.
  assert {
    condition     = google_compute_region_instance_template.this.service_account[0].email == var.service_account
    error_message = "La plantilla debe usar la cuenta de servicio dedicada."
  }
  # Metadatos endurecidos.
  assert {
    condition = (
      google_compute_region_instance_template.this.metadata["enable-oslogin"] == "TRUE" &&
      google_compute_region_instance_template.this.metadata["block-project-ssh-keys"] == "TRUE" &&
      google_compute_region_instance_template.this.metadata["serial-port-enable"] == "FALSE"
    )
    error_message = "Los metadatos de OS Login, llaves SSH y puerto serie no son los esperados."
  }
  # Autoescalado y autocuración.
  assert {
    condition     = google_compute_region_autoscaler.this.autoscaling_policy[0].min_replicas == 2 && google_compute_region_autoscaler.this.autoscaling_policy[0].max_replicas == 6
    error_message = "El autoescalador no refleja min_replicas y max_replicas."
  }
  assert {
    condition     = length(google_compute_region_instance_group_manager.this.auto_healing_policies) == 1 && google_compute_region_instance_group_manager.this.auto_healing_policies[0].initial_delay_sec == 300
    error_message = "El MIG debe tener autocuración."
  }
  assert {
    condition     = google_compute_region_instance_group_manager.this.update_policy[0].type == "PROACTIVE" && google_compute_region_instance_group_manager.this.update_policy[0].max_surge_fixed == 3 && google_compute_region_instance_group_manager.this.update_policy[0].max_unavailable_fixed == 0
    error_message = "La política de actualización no es la esperada."
  }
  assert {
    condition     = one([for p in google_compute_region_instance_group_manager.this.named_port : p.port if p.name == "http"]) == 80
    error_message = "El MIG debe exponer los puertos con nombre."
  }
  assert {
    condition     = length(google_compute_health_check.this.http_health_check) == 1 && google_compute_health_check.this.http_health_check[0].request_path == "/healthz"
    error_message = "La verificación de salud HTTP no es la esperada."
  }
  # Etiquetas.
  assert {
    condition     = google_compute_region_instance_template.this.labels["managed_by"] == "terraform" && google_compute_region_instance_template.this.labels["env"] == "prod"
    error_message = "La plantilla debe llevar las etiquetas."
  }
}

run "verificacion_tcp_y_zonas_explicitas" {
  command = plan

  variables {
    health_check       = { protocol = "TCP", port = 443 }
    distribution_zones = ["us-central1-a", "us-central1-b", "us-central1-c", "us-central1-f"]
  }

  assert {
    condition     = length(google_compute_health_check.this.tcp_health_check) == 1 && length(google_compute_health_check.this.http_health_check) == 0
    error_message = "Con protocolo TCP solo debe existir tcp_health_check."
  }
  assert {
    condition     = google_compute_region_instance_group_manager.this.update_policy[0].max_surge_fixed == 4
    error_message = "max_surge_fixed debe igualar el número de zonas."
  }
}

run "rechaza_minimo_mayor_al_maximo" {
  command = plan

  variables {
    min_replicas = 5
    max_replicas = 3
  }

  expect_failures = [var.max_replicas]
}

run "rechaza_una_replica_en_prod" {
  command = plan

  variables {
    min_replicas = 1
  }

  expect_failures = [var.min_replicas]
}

run "rechaza_imagen_publica_en_prod" {
  command = plan

  variables {
    image = "projects/debian-cloud/global/images/family/debian-12"
  }

  expect_failures = [var.image]
}

run "dev_admite_imagen_publica_y_una_replica" {
  command = plan

  variables {
    environment  = "dev"
    image        = "projects/debian-cloud/global/images/family/debian-12"
    min_replicas = 1
    labels = {
      env         = "dev"
      app         = "app"
      owner       = "plataforma"
      cost_center = "ti-001"
      managed_by  = "terraform"
    }
  }

  assert {
    condition     = google_compute_region_instance_group_manager.this.name == "bnt-dev-app-mig-usc1"
    error_message = "El nombre del MIG de dev no es el esperado."
  }
}

run "rechaza_sobrescribir_metadatos_endurecidos" {
  command = plan

  variables {
    metadata = { enable-oslogin = "FALSE" }
  }

  expect_failures = [var.metadata]
}

run "rechaza_cuenta_de_compute_por_defecto" {
  command = plan

  variables {
    service_account = "123456789012-compute@developer.gserviceaccount.com"
  }

  expect_failures = [var.service_account]
}

run "rechaza_llave_en_otra_region" {
  command = plan

  variables {
    kms_key = "projects/example-common-security/locations/us-east4/keyRings/bnt-prod-sec-kr-use4/cryptoKeys/compute"
  }

  expect_failures = [google_compute_region_instance_template.this]
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
