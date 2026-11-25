mock_provider "google" {}

variables {
  project_id        = "example-prod-app"
  prefix            = "bnt"
  environment       = "prod"
  region            = "us-central1"
  memory_gb         = 5
  network           = "projects/example-prod-net-spoke/global/networks/bnt-prod-net-vpc"
  reserved_ip_range = "bnt-prod-net-psa"
  kms_key           = "projects/example-common-security/locations/us-central1/keyRings/bnt-prod-sec-usc1/cryptoKeys/redis"
  labels = {
    env         = "prod"
    app         = "app"
    owner       = "example-team"
    cost_center = "example-cc"
    managed_by  = "terraform"
  }
}

run "prod_cumple_exige" {
  command = plan

  assert {
    condition     = google_redis_instance.this.name == "bnt-prod-data-redis-usc1"
    error_message = "El nombre no sigue <prefix>-<env>-data-<recurso>-<región>."
  }
  # HA en prod.
  assert {
    condition     = google_redis_instance.this.tier == "STANDARD_HA"
    error_message = "En prod el tier por defecto debe ser STANDARD_HA."
  }
  # IP privada por PSA.
  assert {
    condition     = google_redis_instance.this.connect_mode == "PRIVATE_SERVICE_ACCESS"
    error_message = "La conexión debe ser por Private Service Access."
  }
  assert {
    condition     = google_redis_instance.this.authorized_network == var.network
    error_message = "La red autorizada debe ser la indicada."
  }
  assert {
    condition     = google_redis_instance.this.reserved_ip_range == "bnt-prod-net-psa"
    error_message = "La IP debe salir del rango de PSA indicado."
  }
  # CMEK.
  assert {
    condition     = google_redis_instance.this.customer_managed_key == var.kms_key
    error_message = "La instancia debe usar CMEK."
  }
  # TLS en tránsito y sin AUTH (ADR 0015).
  assert {
    condition     = google_redis_instance.this.transit_encryption_mode == "SERVER_AUTHENTICATION"
    error_message = "El cifrado en tránsito debe estar activo."
  }
  assert {
    condition     = google_redis_instance.this.auth_enabled == false
    error_message = "AUTH debe estar apagado para no dejar un secreto en el estado."
  }
  assert {
    condition     = google_redis_instance.this.labels == var.labels
    error_message = "Las etiquetas deben aplicarse."
  }
  assert {
    condition     = google_redis_instance.this.persistence_config[0].persistence_mode == "RDB"
    error_message = "La persistencia RDB debe estar activa por defecto."
  }
}

run "dev_basico" {
  command = plan

  variables {
    environment = "dev"
    memory_gb   = 1
    labels = {
      env         = "dev"
      app         = "app"
      owner       = "example-team"
      cost_center = "example-cc"
      managed_by  = "terraform"
    }
  }

  assert {
    condition     = google_redis_instance.this.tier == "BASIC"
    error_message = "En dev el tier por defecto es BASIC."
  }
  assert {
    condition     = google_redis_instance.this.name == "bnt-dev-data-redis-usc1"
    error_message = "Nombre de dev incorrecto."
  }
  assert {
    condition     = google_redis_instance.this.auth_enabled == false && google_redis_instance.this.customer_managed_key == var.kms_key
    error_message = "dev también lleva CMEK y AUTH apagado."
  }
}

run "rechaza_basic_en_prod" {
  command = plan
  variables {
    tier = "BASIC"
  }
  expect_failures = [var.tier]
}

run "rechaza_llave_de_otra_region" {
  command = plan
  variables {
    kms_key = "projects/example-common-security/locations/us-east4/keyRings/bnt-prod-sec-use4/cryptoKeys/redis"
  }
  expect_failures = [var.kms_key]
}

run "rechaza_sin_cmek" {
  command = plan
  variables {
    kms_key = ""
  }
  expect_failures = [var.kms_key]
}

run "rechaza_memoria_fuera_de_rango" {
  command = plan
  variables {
    memory_gb = 0
  }
  expect_failures = [var.memory_gb]
}

run "rechaza_red_mal_formada" {
  command = plan
  variables {
    network = "default"
  }
  expect_failures = [var.network]
}

run "rechaza_etiquetas_en_mayusculas" {
  command = plan
  variables {
    labels = {
      env         = "prod"
      app         = "app"
      owner       = "Example-Team"
      cost_center = "example-cc"
      managed_by  = "terraform"
    }
  }
  expect_failures = [var.labels]
}
