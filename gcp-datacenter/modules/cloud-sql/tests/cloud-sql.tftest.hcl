mock_provider "google" {}

variables {
  project_id         = "example-prod-app"
  prefix             = "bnt"
  environment        = "prod"
  region             = "us-central1"
  dr_region          = "us-east4"
  enable_dr          = true
  network            = "projects/example-prod-net-spoke/global/networks/bnt-prod-net-vpc"
  allocated_ip_range = "bnt-prod-net-psa"
  kms_key            = "projects/example-common-security/locations/us-central1/keyRings/bnt-prod-sec-usc1/cryptoKeys/sql"
  dr_kms_key         = "projects/example-common-security/locations/us-east4/keyRings/bnt-prod-sec-use4/cryptoKeys/sql"
  databases          = ["app"]
  iam_users = [
    { email = "bnt-prod-app-workload@example-prod-app.iam.gserviceaccount.com", type = "CLOUD_IAM_SERVICE_ACCOUNT" },
    { email = "dba-team@example.com", type = "CLOUD_IAM_GROUP" },
    { email = "persona@example.com", type = "CLOUD_IAM_USER" },
  ]
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

  # Nombres de §4.2 con el código corto de la región.
  assert {
    condition     = google_sql_database_instance.this.name == "bnt-prod-data-sql-usc1"
    error_message = "El nombre de la primaria no sigue <prefix>-<env>-data-<recurso>-<región>."
  }
  assert {
    condition     = google_sql_database_instance.replica["dr"].name == "bnt-prod-data-sql-use4"
    error_message = "El nombre de la réplica no sigue §4.2."
  }

  # IP privada únicamente.
  assert {
    condition     = google_sql_database_instance.this.settings[0].ip_configuration[0].ipv4_enabled == false
    error_message = "La primaria no debe tener IP pública."
  }
  assert {
    condition     = google_sql_database_instance.this.settings[0].ip_configuration[0].private_network == var.network
    error_message = "La primaria debe usar la red privada indicada."
  }
  assert {
    condition     = google_sql_database_instance.this.settings[0].ip_configuration[0].allocated_ip_range == "bnt-prod-net-psa"
    error_message = "La primaria debe tomar la IP del rango de PSA."
  }
  assert {
    condition     = google_sql_database_instance.replica["dr"].settings[0].ip_configuration[0].ipv4_enabled == false
    error_message = "La réplica no debe tener IP pública."
  }

  # HA regional en prod.
  assert {
    condition     = google_sql_database_instance.this.settings[0].availability_type == "REGIONAL"
    error_message = "En prod la primaria debe ser REGIONAL."
  }

  # Respaldos con PITR.
  assert {
    condition     = google_sql_database_instance.this.settings[0].backup_configuration[0].enabled
    error_message = "Los respaldos deben estar activos."
  }
  assert {
    condition     = google_sql_database_instance.this.settings[0].backup_configuration[0].point_in_time_recovery_enabled
    error_message = "PITR debe estar activo."
  }

  # SSL obligatorio.
  assert {
    condition     = google_sql_database_instance.this.settings[0].ip_configuration[0].ssl_mode == "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"
    error_message = "El SSL debe ser obligatorio con certificado de cliente por defecto."
  }

  # CMEK en la primaria y en la réplica, cada una con la llave de su región.
  assert {
    condition     = google_sql_database_instance.this.encryption_key_name == var.kms_key
    error_message = "La primaria debe usar kms_key."
  }
  assert {
    condition     = google_sql_database_instance.replica["dr"].encryption_key_name == var.dr_kms_key
    error_message = "La réplica debe usar dr_kms_key."
  }

  # Réplica en DR.
  assert {
    condition     = google_sql_database_instance.replica["dr"].region == "us-east4"
    error_message = "La réplica debe estar en dr_region."
  }
  assert {
    condition     = google_sql_database_instance.replica["dr"].master_instance_name == "bnt-prod-data-sql-usc1"
    error_message = "La réplica debe replicar de la primaria."
  }
  assert {
    condition     = output.replica_name == "bnt-prod-data-sql-use4"
    error_message = "replica_name debe ser el nombre de la réplica."
  }
  # failover_target no aplica a PostgreSQL: la réplica no declara replica_configuration.
  assert {
    condition     = length(google_sql_database_instance.replica["dr"].replica_configuration) == 0
    error_message = "La réplica de PostgreSQL no debe declarar replica_configuration (failover_target no se admite)."
  }
  # Sin plan de Backup and DR, el módulo fija horario, retención y días de registros de PITR.
  assert {
    condition = (
      google_sql_database_instance.this.settings[0].backup_configuration[0].transaction_log_retention_days == 7 &&
      google_sql_database_instance.this.settings[0].backup_configuration[0].backup_retention_settings[0].retained_backups == 30 &&
      google_sql_database_instance.this.settings[0].backup_configuration[0].start_time == "06:00"
    )
    error_message = "Sin backup_plan_managed el módulo declara la retención de respaldos y de registros."
  }

  # Autenticación IAM y sin contraseñas.
  assert {
    condition = anytrue([
      for f in google_sql_database_instance.this.settings[0].database_flags :
      f.name == "cloudsql.iam_authentication" && f.value == "on"
    ])
    error_message = "La autenticación IAM debe estar activa en la primaria."
  }
  assert {
    condition = anytrue([
      for f in google_sql_database_instance.replica["dr"].settings[0].database_flags :
      f.name == "cloudsql.iam_authentication" && f.value == "on"
    ])
    error_message = "La autenticación IAM debe estar activa en la réplica."
  }
  assert {
    condition     = google_sql_database_instance.this.root_password == null
    error_message = "No debe haber contraseña del usuario predeterminado."
  }
  assert {
    condition     = google_sql_user.iam["bnt-prod-app-workload@example-prod-app.iam.gserviceaccount.com"].name == "bnt-prod-app-workload@example-prod-app.iam"
    error_message = "El usuario de una cuenta de servicio va sin .gserviceaccount.com."
  }
  assert {
    condition     = alltrue([for u in google_sql_user.iam : u.password == null && startswith(u.type, "CLOUD_IAM_")])
    error_message = "Todos los usuarios deben ser IAM y sin contraseña."
  }

  # Roles de entrada: cuentas de servicio y grupos sí; personas (user:) nunca.
  assert {
    condition     = length(google_project_iam_member.login) == 4
    error_message = "Se esperaban dos roles para la cuenta de servicio y dos para el grupo."
  }
  assert {
    condition     = alltrue([for m in google_project_iam_member.login : !startswith(m.member, "user:")])
    error_message = "Ningún rol se asigna a user:."
  }

  # Banderas de auditoría.
  assert {
    condition = alltrue([
      for n in ["log_checkpoints", "log_connections", "log_disconnections", "log_lock_waits", "log_hostname", "log_duration", "cloudsql.enable_pgaudit"] :
      anytrue([for f in google_sql_database_instance.this.settings[0].database_flags : f.name == n && f.value == "on"])
    ])
    error_message = "Faltan banderas de auditoría de PostgreSQL."
  }

  # Protección contra borrado y etiquetas.
  assert {
    condition     = google_sql_database_instance.this.deletion_protection && google_sql_database_instance.this.settings[0].deletion_protection_enabled
    error_message = "La protección contra borrado debe estar activa."
  }

  # Encendida al crear; sin apagado programado en prod (ADR 0028).
  assert {
    condition     = google_sql_database_instance.this.settings[0].activation_policy == "ALWAYS" && output.activation_policy == "ALWAYS"
    error_message = "La primaria se crea con activation_policy ALWAYS y la salida lo publica."
  }
  assert {
    condition     = var.allow_scheduled_stop == false
    error_message = "allow_scheduled_stop vale false por defecto."
  }
  assert {
    condition     = google_sql_database_instance.this.settings[0].user_labels == var.labels
    error_message = "Las etiquetas van en settings.user_labels."
  }
}

run "dev_sin_dr" {
  command = plan

  variables {
    environment = "dev"
    enable_dr   = false
    dr_region   = null
    dr_kms_key  = null
    labels = {
      env         = "dev"
      app         = "app"
      owner       = "example-team"
      cost_center = "example-cc"
      managed_by  = "terraform"
    }
  }

  assert {
    condition     = google_sql_database_instance.this.settings[0].availability_type == "ZONAL"
    error_message = "En dev el valor por defecto es ZONAL."
  }
  assert {
    condition     = length(google_sql_database_instance.replica) == 0
    error_message = "Sin enable_dr no hay réplica."
  }
  assert {
    condition     = output.replica_name == null
    error_message = "replica_name debe ser null sin réplica."
  }
  assert {
    condition     = google_sql_database_instance.this.name == "bnt-dev-data-sql-usc1"
    error_message = "Nombre de dev incorrecto."
  }
}

# Con un plan de Backup and DR (respaldos mejorados) el plan es el dueño del horario y de la
# retención: el módulo no los declara, pero los respaldos y PITR siguen encendidos al crear.
run "respaldos_administrados_por_el_plan" {
  command = plan

  variables {
    backup_plan_managed = true
  }

  assert {
    condition = (
      google_sql_database_instance.this.settings[0].backup_configuration[0].enabled &&
      google_sql_database_instance.this.settings[0].backup_configuration[0].point_in_time_recovery_enabled
    )
    error_message = "Con el plan, respaldos y PITR siguen encendidos en la instancia."
  }
  assert {
    condition     = length(google_sql_database_instance.this.settings[0].backup_configuration[0].backup_retention_settings) == 0
    error_message = "Con el plan, el módulo no declara retención de respaldos ni días de registros (los define el plan)."
  }
}

# Apagado fuera de horario (ADR 0028): en dev sin DR se admite y la instancia nace encendida;
# los trabajos de Cloud Scheduler la detienen y encienden después.
run "dev_admite_apagado_programado" {
  command = plan

  variables {
    environment          = "dev"
    enable_dr            = false
    dr_region            = null
    dr_kms_key           = null
    allow_scheduled_stop = true
    labels = {
      env         = "dev"
      app         = "app"
      owner       = "example-team"
      cost_center = "example-cc"
      managed_by  = "terraform"
    }
  }

  assert {
    condition     = google_sql_database_instance.this.settings[0].activation_policy == "ALWAYS"
    error_message = "Con allow_scheduled_stop la instancia se crea encendida igual."
  }
}

run "rechaza_apagado_programado_en_prod" {
  command = plan
  variables {
    enable_dr            = false
    dr_region            = null
    dr_kms_key           = null
    allow_scheduled_stop = true
  }
  expect_failures = [var.allow_scheduled_stop]
}

run "rechaza_apagado_programado_con_dr" {
  command = plan
  variables {
    environment          = "qa"
    allow_scheduled_stop = true
    labels = {
      env         = "qa"
      app         = "app"
      owner       = "example-team"
      cost_center = "example-cc"
      managed_by  = "terraform"
    }
  }
  expect_failures = [var.allow_scheduled_stop]
}

run "rechaza_zonal_en_prod" {
  command = plan
  variables {
    availability_type = "ZONAL"
  }
  expect_failures = [var.availability_type]
}

run "rechaza_dr_sin_llave" {
  command = plan
  variables {
    dr_kms_key = null
  }
  expect_failures = [var.dr_kms_key]
}

run "rechaza_llave_de_otra_region" {
  command = plan
  variables {
    kms_key = "projects/example-common-security/locations/us-east4/keyRings/bnt-prod-sec-use4/cryptoKeys/sql"
  }
  expect_failures = [var.kms_key]
}

run "rechaza_ssl_opcional" {
  command = plan
  variables {
    ssl_mode = "ALLOW_UNENCRYPTED_AND_ENCRYPTED"
  }
  expect_failures = [var.ssl_mode]
}

run "rechaza_motor_no_postgres" {
  command = plan
  variables {
    database_version = "MYSQL_8_0"
  }
  expect_failures = [var.database_version]
}

run "rechaza_tier_incompatible_con_edicion" {
  command = plan
  variables {
    edition = "ENTERPRISE_PLUS"
  }
  expect_failures = [var.sql_tier]
}

run "rechaza_prod_sin_proteccion" {
  command = plan
  variables {
    deletion_protection = false
  }
  expect_failures = [var.deletion_protection]
}

run "rechaza_cuenta_de_servicio_mal_tipada" {
  command = plan
  variables {
    iam_users = [{ email = "persona@example.com", type = "CLOUD_IAM_SERVICE_ACCOUNT" }]
  }
  expect_failures = [var.iam_users]
}

run "rechaza_etiquetas_incompletas" {
  command = plan
  variables {
    labels = { env = "prod", managed_by = "terraform" }
  }
  expect_failures = [var.labels]
}

run "banderas_obligatorias_no_se_reemplazan" {
  command = plan
  variables {
    additional_database_flags = {
      "cloudsql.iam_authentication" = "off"
      "max_connections"             = "200"
    }
  }

  assert {
    condition = anytrue([
      for f in google_sql_database_instance.this.settings[0].database_flags :
      f.name == "cloudsql.iam_authentication" && f.value == "on"
    ])
    error_message = "Una bandera adicional no debe apagar la autenticación IAM."
  }
  assert {
    condition = anytrue([
      for f in google_sql_database_instance.this.settings[0].database_flags :
      f.name == "max_connections" && f.value == "200"
    ])
    error_message = "Las banderas adicionales deben aplicarse."
  }
}
