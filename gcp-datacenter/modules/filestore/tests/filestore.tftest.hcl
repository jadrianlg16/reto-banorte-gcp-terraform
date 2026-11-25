mock_provider "google" {}

variables {
  project_id        = "example-prod-app"
  prefix            = "bnt"
  environment       = "prod"
  tier              = "ZONAL"
  location          = "us-central1-a"
  capacity_gb       = 1024
  network           = "https://www.googleapis.com/compute/v1/projects/example-prod-net-spoke/global/networks/bnt-prod-net-vpc"
  reserved_ip_range = "bnt-prod-net-psa"
  kms_key           = "projects/example-common-security/locations/us-central1/keyRings/bnt-prod-sec-usc1/cryptoKeys/filestore"
  labels = {
    env         = "prod"
    app         = "app"
    owner       = "example-team"
    cost_center = "example-cc"
    managed_by  = "terraform"
  }
}

run "zonal_cumple_exige" {
  command = plan

  assert {
    condition     = google_filestore_instance.this.name == "bnt-prod-data-nfs-usc1"
    error_message = "El nombre no sigue <prefix>-<env>-data-<recurso>-<región> (región derivada de la zona)."
  }
  assert {
    condition     = google_filestore_instance.this.kms_key_name == var.kms_key
    error_message = "La instancia debe usar CMEK."
  }
  assert {
    condition     = google_filestore_instance.this.networks[0].connect_mode == "PRIVATE_SERVICE_ACCESS"
    error_message = "La red debe conectarse por Private Service Access."
  }
  assert {
    condition     = google_filestore_instance.this.networks[0].network == "projects/example-prod-net-spoke/global/networks/bnt-prod-net-vpc"
    error_message = "La red debe pasarse como ruta projects/<host>/global/networks/<red>."
  }
  assert {
    condition     = google_filestore_instance.this.networks[0].reserved_ip_range == "bnt-prod-net-psa"
    error_message = "La IP debe salir del rango de PSA indicado."
  }
  assert {
    condition     = google_filestore_instance.this.networks[0].modes == tolist(["MODE_IPV4"])
    error_message = "Solo IPv4 privada."
  }
  assert {
    condition     = google_filestore_instance.this.deletion_protection_enabled
    error_message = "La protección contra borrado debe estar activa."
  }
  assert {
    condition     = google_filestore_instance.this.labels == var.labels
    error_message = "Las etiquetas deben aplicarse."
  }
  assert {
    condition     = google_filestore_instance.this.file_shares[0].capacity_gb == 1024 && google_filestore_instance.this.file_shares[0].name == "data"
    error_message = "El recurso compartido debe tener el nombre y la capacidad indicados."
  }
}

run "regional_con_exportacion" {
  command = plan

  variables {
    tier               = "REGIONAL"
    location           = "us-central1"
    capacity_gb        = 512
    nfs_export_options = [{ ip_ranges = ["10.30.0.0/20"] }]
  }

  assert {
    condition     = google_filestore_instance.this.location == "us-central1" && google_filestore_instance.this.tier == "REGIONAL"
    error_message = "Una instancia REGIONAL se ubica en la región."
  }
  assert {
    condition     = google_filestore_instance.this.file_shares[0].nfs_export_options[0].squash_mode == "ROOT_SQUASH"
    error_message = "La exportación usa ROOT_SQUASH por defecto."
  }
}

run "rechaza_tier_sin_cmek" {
  command = plan
  variables {
    tier = "BASIC_HDD"
  }
  expect_failures = [var.tier]
}

run "rechaza_capacidad_fuera_de_paso" {
  command = plan
  variables {
    capacity_gb = 1100
  }
  expect_failures = [var.capacity_gb]
}

run "rechaza_region_para_zonal" {
  command = plan
  variables {
    location = "us-central1"
  }
  expect_failures = [var.location]
}

run "rechaza_llave_de_otra_region" {
  command = plan
  variables {
    kms_key = "projects/example-common-security/locations/us-east4/keyRings/bnt-prod-sec-use4/cryptoKeys/filestore"
  }
  expect_failures = [var.kms_key]
}

run "rechaza_prod_sin_proteccion" {
  command = plan
  variables {
    deletion_protection = false
  }
  expect_failures = [var.deletion_protection]
}

run "rechaza_etiquetas_incompletas" {
  command = plan
  variables {
    labels = { env = "prod", app = "app", managed_by = "terraform" }
  }
  expect_failures = [var.labels]
}
