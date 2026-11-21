mock_provider "google" {}

variables {
  project_id  = "example-prod-app"
  prefix      = "bnt"
  environment = "prod"
  region      = "us-central1"
  dr_region   = "us-east4"
  labels = {
    env         = "prod"
    app         = "web"
    owner       = "plataforma"
    cost_center = "cc-0000"
    managed_by  = "terraform"
  }
}

run "base_cumple_lo_exigido" {
  command = plan

  assert {
    condition     = google_backup_dr_backup_vault.this.location == "us-east4"
    error_message = "La bóveda debe estar en la región secundaria."
  }

  assert {
    condition     = google_backup_dr_backup_vault.this.backup_vault_id == "bnt-prod-bkp-vault-use4"
    error_message = "El nombre de la bóveda no sigue §4.2."
  }

  assert {
    condition     = google_backup_dr_backup_vault.this.backup_minimum_enforced_retention_duration == "2592000s"
    error_message = "La retención mínima forzada debe ser de 30 días."
  }

  assert {
    condition     = google_backup_dr_backup_vault.this.access_restriction == "WITHIN_ORGANIZATION"
    error_message = "La bóveda debe restringirse a la organización."
  }

  assert {
    condition     = alltrue([for p in google_backup_dr_backup_plan.this : p.backup_rules[0].standard_schedule[0].recurrence_type == "DAILY" && p.backup_rules[0].backup_retention_days == 30])
    error_message = "Los planes deben ser diarios con 30 días de retención."
  }

  assert {
    condition     = google_backup_dr_backup_plan.this["vm"].location == "us-central1" && google_backup_dr_backup_plan.this["vm"].backup_plan_id == "bnt-prod-bkp-vm-plan-usc1"
    error_message = "El plan de VM debe estar en la región primaria con nombre §4.2."
  }

  assert {
    condition     = google_backup_dr_backup_plan.this["sql"].resource_type == "sqladmin.googleapis.com/Instance"
    error_message = "Falta el plan de Cloud SQL."
  }

  assert {
    condition     = length(google_gke_backup_backup_plan.this) == 0
    error_message = "Sin enable_gke_backup no se crea el plan de GKE."
  }
}

run "con_backup_de_gke" {
  command = plan

  variables {
    enable_gke_backup  = true
    gke_cluster_id     = "projects/example-prod-app/locations/us-central1/clusters/gke"
    gke_backup_kms_key = "projects/example-sec/locations/us-east4/keyRings/kr/cryptoKeys/backup"
    retention_days     = 35
    protected_resources = {
      db = { resource = "projects/example-prod-app/instances/sql", plan = "sql" }
    }
  }

  assert {
    condition     = google_gke_backup_backup_plan.this["gke"].location == "us-east4" && google_gke_backup_backup_plan.this["gke"].name == "bnt-prod-bkp-gke-plan-use4"
    error_message = "El plan de GKE debe estar en la región secundaria con nombre §4.2."
  }

  assert {
    condition     = google_gke_backup_backup_plan.this["gke"].retention_policy[0].backup_retain_days == 35
    error_message = "La retención de GKE debe seguir retention_days."
  }

  assert {
    condition     = google_gke_backup_backup_plan.this["gke"].backup_config[0].encryption_key[0].gcp_kms_encryption_key == "projects/example-sec/locations/us-east4/keyRings/kr/cryptoKeys/backup"
    error_message = "El respaldo de GKE debe cifrarse con CMEK."
  }

  assert {
    condition     = google_gke_backup_backup_plan.this["gke"].backup_schedule[0].cron_schedule == "0 7 * * *"
    error_message = "El respaldo de GKE debe ser diario."
  }

  assert {
    condition     = google_backup_dr_backup_plan_association.this["db"].resource_type == "sqladmin.googleapis.com/Instance"
    error_message = "La asociación debe heredar el tipo del plan."
  }
}

run "rechaza_retencion_menor_a_30" {
  command = plan

  variables {
    retention_days = 7
  }

  expect_failures = [var.retention_days]
}

run "rechaza_retencion_sql_sobre_186" {
  command = plan

  variables {
    retention_days = 200
  }

  expect_failures = [var.retention_days]
}

run "rechaza_misma_region" {
  command = plan

  variables {
    dr_region = "us-central1"
  }

  expect_failures = [var.dr_region]
}

run "rechaza_gke_sin_cmek" {
  command = plan

  variables {
    enable_gke_backup = true
    gke_cluster_id    = "projects/example-prod-app/locations/us-central1/clusters/gke"
  }

  expect_failures = [var.gke_backup_kms_key]
}

run "rechaza_llave_gke_fuera_de_dr" {
  command = plan

  variables {
    enable_gke_backup  = true
    gke_cluster_id     = "projects/example-prod-app/locations/us-central1/clusters/gke"
    gke_backup_kms_key = "projects/example-sec/locations/us-central1/keyRings/kr/cryptoKeys/backup"
  }

  expect_failures = [google_gke_backup_backup_plan.this]
}

run "rechaza_plan_inexistente" {
  command = plan

  variables {
    protected_resources = {
      db = { resource = "projects/example-prod-app/instances/sql", plan = "otro" }
    }
  }

  expect_failures = [var.protected_resources]
}

run "rechaza_cron_no_diario" {
  command = plan

  variables {
    gke_backup_cron = "0 7 * * 1"
  }

  expect_failures = [var.gke_backup_cron]
}
