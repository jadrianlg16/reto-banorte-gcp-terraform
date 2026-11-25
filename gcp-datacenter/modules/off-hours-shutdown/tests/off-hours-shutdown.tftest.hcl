# Pruebas unitarias sin GCP: proveedor simulado y solo plan.

mock_provider "google" {}

variables {
  project_id     = "example-qa-app"
  prefix         = "bnt"
  environment    = "qa"
  region         = "us-central1"
  time_zone      = "America/Monterrey"
  start_schedule = "0 7 * * 1-5"
  stop_schedule  = "0 20 * * 1-5"

  service_account_email = "bnt-qa-app-sched@example-qa-app.iam.gserviceaccount.com"

  sql_instances = {
    primary = "bnt-qa-data-sql-usc1"
  }
  gke_node_pools = {
    general = {
      location       = "us-central1"
      cluster        = "bnt-qa-app-gke-usc1"
      node_pool      = "bnt-qa-app-nps-general"
      min_node_count = 1
      max_node_count = 3
    }
  }
}

run "qa_crea_los_trabajos_esperados" {
  command = plan

  # Dos trabajos por instancia de Cloud SQL y cuatro por pool de GKE: si falta uno, el entorno
  # queda encendido (o apagado) sin que nadie lo note.
  assert {
    condition = toset(keys(google_cloud_scheduler_job.this)) == toset([
      "sql-primary-stop",
      "sql-primary-start",
      "gke-general-stop-autoscaling",
      "gke-general-stop-resize",
      "gke-general-start-resize",
      "gke-general-start-autoscaling",
    ])
    error_message = "Faltan o sobran trabajos: se esperan sql-<llave>-stop|start y gke-<llave>-stop-autoscaling|stop-resize|start-resize|start-autoscaling."
  }
  assert {
    condition     = google_cloud_scheduler_job.this["sql-primary-stop"].name == "bnt-qa-ops-sql-primary-stop-usc1"
    error_message = "El nombre del trabajo no sigue <prefix>-<env>-ops-<trabajo>-<región>."
  }

  # Mismo proyecto, región, zona horaria y cuenta dedicada en todos; ninguno pausado.
  assert {
    condition = alltrue([
      for j in google_cloud_scheduler_job.this :
      j.project == "example-qa-app" && j.region == "us-central1" && j.time_zone == "America/Monterrey" && j.paused == false
    ])
    error_message = "Todos los trabajos van en el proyecto y la región del entorno, con time_zone y sin pausa."
  }
  assert {
    condition = alltrue([
      for j in google_cloud_scheduler_job.this :
      j.http_target[0].oauth_token[0].service_account_email == var.service_account_email &&
      j.http_target[0].oauth_token[0].scope == "https://www.googleapis.com/auth/cloud-platform" &&
      length(j.http_target[0].oidc_token) == 0
    ])
    error_message = "Todos los trabajos usan el token OAuth de la cuenta dedicada (las APIs de Google no aceptan OIDC)."
  }
  assert {
    condition     = alltrue([for j in google_cloud_scheduler_job.this : j.retry_config[0].retry_count == 5 && j.http_target[0].headers["Content-Type"] == "application/json"])
    error_message = "Todos los trabajos reintentan y mandan JSON."
  }

  # Cloud SQL: instances.patch con activationPolicy.
  assert {
    condition = (
      google_cloud_scheduler_job.this["sql-primary-stop"].schedule == "0 20 * * 1-5" &&
      google_cloud_scheduler_job.this["sql-primary-stop"].http_target[0].http_method == "PATCH" &&
      google_cloud_scheduler_job.this["sql-primary-stop"].http_target[0].uri == "https://sqladmin.googleapis.com/v1/projects/example-qa-app/instances/bnt-qa-data-sql-usc1" &&
      base64decode(google_cloud_scheduler_job.this["sql-primary-stop"].http_target[0].body) == jsonencode({ settings = { activationPolicy = "NEVER" } })
    )
    error_message = "El apagado de Cloud SQL debe ser un PATCH de la instancia con activationPolicy NEVER a la hora de stop_schedule."
  }
  assert {
    condition = (
      google_cloud_scheduler_job.this["sql-primary-start"].schedule == "0 7 * * 1-5" &&
      base64decode(google_cloud_scheduler_job.this["sql-primary-start"].http_target[0].body) == jsonencode({ settings = { activationPolicy = "ALWAYS" } })
    )
    error_message = "El encendido de Cloud SQL debe poner activationPolicy ALWAYS a la hora de start_schedule."
  }

  # GKE: desactivar el autoescalado, 10 minutos después llevar a 0; al encender, tamaño mínimo y
  # 10 minutos después el autoescalado con sus límites.
  assert {
    condition = (
      google_cloud_scheduler_job.this["gke-general-stop-autoscaling"].schedule == "0 20 * * 1-5" &&
      google_cloud_scheduler_job.this["gke-general-stop-autoscaling"].http_target[0].uri == "https://container.googleapis.com/v1/projects/example-qa-app/locations/us-central1/clusters/bnt-qa-app-gke-usc1/nodePools/bnt-qa-app-nps-general:setAutoscaling" &&
      base64decode(google_cloud_scheduler_job.this["gke-general-stop-autoscaling"].http_target[0].body) == jsonencode({ autoscaling = { enabled = false } })
    )
    error_message = "El paso 1 del apagado de GKE debe desactivar el autoescalado del pool a la hora de stop_schedule."
  }
  assert {
    condition = (
      google_cloud_scheduler_job.this["gke-general-stop-resize"].schedule == "10 20 * * 1-5" &&
      endswith(google_cloud_scheduler_job.this["gke-general-stop-resize"].http_target[0].uri, "/nodePools/bnt-qa-app-nps-general:setSize") &&
      base64decode(google_cloud_scheduler_job.this["gke-general-stop-resize"].http_target[0].body) == jsonencode({ nodeCount = 0 })
    )
    error_message = "El paso 2 del apagado de GKE debe llevar el pool a 0 nodos gke_step_minutes después."
  }
  assert {
    condition = (
      google_cloud_scheduler_job.this["gke-general-start-resize"].schedule == "0 7 * * 1-5" &&
      base64decode(google_cloud_scheduler_job.this["gke-general-start-resize"].http_target[0].body) == jsonencode({ nodeCount = 1 })
    )
    error_message = "El paso 1 del encendido de GKE debe devolver el pool a min_node_count a la hora de start_schedule."
  }
  assert {
    condition = (
      google_cloud_scheduler_job.this["gke-general-start-autoscaling"].schedule == "10 7 * * 1-5" &&
      base64decode(google_cloud_scheduler_job.this["gke-general-start-autoscaling"].http_target[0].body) == jsonencode({ autoscaling = { enabled = true, minNodeCount = 1, maxNodeCount = 3 } })
    )
    error_message = "El paso 2 del encendido de GKE debe reactivar el autoescalado con min y max del pool."
  }

  # Ventana que usa la etapa 5 para el MIG y los respaldos.
  assert {
    condition = (
      output.window.duration_sec == 46800 &&
      output.window.start_minute == 420 &&
      output.window.stop_minute == 1200 &&
      output.window.days == "1-5" &&
      output.window.time_zone == "America/Monterrey"
    )
    error_message = "window debe publicar 13 h encendidas (07:00 a 20:00) de lunes a viernes en America/Monterrey."
  }
}

run "solo_cloud_sql_y_minutos_no_redondos" {
  command = plan

  variables {
    environment           = "dev"
    project_id            = "example-dev-app"
    service_account_email = "bnt-dev-app-sched@example-dev-app.iam.gserviceaccount.com"
    start_schedule        = "30 6 * * *"
    stop_schedule         = "55 22 * * *"
    gke_step_minutes      = 5
    sql_instances         = { primary = "bnt-dev-data-sql-usc1" }
    gke_node_pools        = {}
  }

  assert {
    condition     = toset(keys(google_cloud_scheduler_job.this)) == toset(["sql-primary-stop", "sql-primary-start"])
    error_message = "Sin pools de GKE solo se crean los dos trabajos de Cloud SQL."
  }
  assert {
    condition     = output.window.duration_sec == (22 * 60 + 55 - (6 * 60 + 30)) * 60 && output.window.days == "*"
    error_message = "La duración de la ventana se calcula en minutos desde los crons."
  }
}

run "pool_con_minimo_cero_enciende_con_un_nodo" {
  command = plan

  variables {
    gke_node_pools = {
      batch = {
        location       = "us-central1-a"
        cluster        = "bnt-qa-app-gke-usc1"
        node_pool      = "bnt-qa-app-nps-batch"
        min_node_count = 0
        max_node_count = 2
      }
    }
  }

  assert {
    condition     = base64decode(google_cloud_scheduler_job.this["gke-batch-start-resize"].http_target[0].body) == jsonencode({ nodeCount = 1 })
    error_message = "Con min_node_count = 0 el encendido deja un nodo para los pods del sistema (como initial_node_count del módulo gke)."
  }
  assert {
    condition     = base64decode(google_cloud_scheduler_job.this["gke-batch-start-autoscaling"].http_target[0].body) == jsonencode({ autoscaling = { enabled = true, minNodeCount = 0, maxNodeCount = 2 } })
    error_message = "El autoescalado se reactiva con el mínimo configurado, aunque sea 0."
  }
}

run "rechaza_prod" {
  command = plan

  variables {
    environment = "prod"
  }

  expect_failures = [var.environment]
}

run "rechaza_hora_invalida" {
  command = plan

  variables {
    stop_schedule = "0 25 * * 1-5"
  }

  expect_failures = [var.stop_schedule]
}

run "rechaza_dia_del_mes" {
  command = plan

  variables {
    start_schedule = "0 7 1 * 1-5"
  }

  expect_failures = [var.start_schedule]
}

run "rechaza_dias_distintos" {
  command = plan

  variables {
    stop_schedule = "0 20 * * 1-4"
  }

  expect_failures = [var.stop_schedule]
}

run "rechaza_ventana_menor_a_una_hora" {
  command = plan

  variables {
    start_schedule = "0 19 * * 1-5"
    stop_schedule  = "30 19 * * 1-5"
  }

  expect_failures = [var.stop_schedule]
}

run "rechaza_apagado_antes_del_encendido" {
  command = plan

  variables {
    start_schedule = "0 20 * * 1-5"
    stop_schedule  = "0 7 * * 1-5"
  }

  expect_failures = [var.stop_schedule]
}

run "rechaza_segundo_paso_al_dia_siguiente" {
  command = plan

  variables {
    stop_schedule = "55 23 * * 1-5"
  }

  expect_failures = [var.stop_schedule]
}

run "rechaza_zona_horaria_invalida" {
  command = plan

  variables {
    time_zone = "GMT-6"
  }

  expect_failures = [var.time_zone]
}

run "rechaza_cuenta_de_compute_por_defecto" {
  command = plan

  variables {
    service_account_email = "123456789012-compute@developer.gserviceaccount.com"
  }

  expect_failures = [var.service_account_email]
}

run "rechaza_sin_recursos" {
  command = plan

  variables {
    sql_instances  = {}
    gke_node_pools = {}
  }

  expect_failures = [var.gke_node_pools]
}

run "rechaza_pool_con_minimo_mayor_al_maximo" {
  command = plan

  variables {
    gke_node_pools = {
      general = {
        location       = "us-central1"
        cluster        = "bnt-qa-app-gke-usc1"
        node_pool      = "bnt-qa-app-nps-general"
        min_node_count = 4
        max_node_count = 3
      }
    }
  }

  expect_failures = [var.gke_node_pools]
}
