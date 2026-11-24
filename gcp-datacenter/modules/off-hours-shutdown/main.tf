# Apagado fuera de horario de dev y qa (ADR 0028): trabajos de Cloud Scheduler con destino HTTP
# que llaman directo a las APIs de Cloud SQL Admin y de GKE con el token OAuth de una cuenta de
# servicio dedicada. Sin funciones ni código propio: cada trabajo es una sola llamada a la API.
# El MIG no pasa por aquí: usa el programa de escalado nativo de su autoescalador (módulo
# compute-mig, business_hours) con la ventana que publica la salida window.

locals {
  # La validación de region exige que esté en region_codes; lookup evita un segundo error.
  region_code = lookup(var.region_codes, var.region, "")
  base_name   = "${var.prefix}-${var.environment}-ops"

  # Las validaciones exigen la forma "M H * * D": minuto y hora se leen por posición. try()
  # solo evita un segundo error cuando la validación ya rechazó el cron.
  start_parts  = split(" ", var.start_schedule)
  stop_parts   = split(" ", var.stop_schedule)
  start_minute = try(tonumber(local.start_parts[1]) * 60 + tonumber(local.start_parts[0]), 0)
  stop_minute  = try(tonumber(local.stop_parts[1]) * 60 + tonumber(local.stop_parts[0]), 0)
  days         = try(local.start_parts[4], "*")

  # Segundo paso de GKE: gke_step_minutes después de cada horario, el mismo día (la validación
  # de stop_schedule lo garantiza).
  stop_step_minute    = local.stop_minute + var.gke_step_minutes
  start_step_minute   = local.start_minute + var.gke_step_minutes
  stop_step_schedule  = format("%d %d * * %s", local.stop_step_minute % 60, floor(local.stop_step_minute / 60), local.days)
  start_step_schedule = format("%d %d * * %s", local.start_step_minute % 60, floor(local.start_step_minute / 60), local.days)

  sql_api = "https://sqladmin.googleapis.com/v1/projects/${var.project_id}/instances"
  gke_api = "https://container.googleapis.com/v1/projects/${var.project_id}/locations"

  # Cloud SQL: instances.patch con settings.activationPolicy (NEVER detiene, ALWAYS enciende).
  # El patch fusiona el cuerpo con la configuración actual: solo cambia la política.
  sql_jobs = merge({}, [
    for k, instance in var.sql_instances : {
      "sql-${k}-stop" = {
        description = "Detiene la instancia de Cloud SQL ${instance} (activationPolicy NEVER) fuera de horario."
        schedule    = var.stop_schedule
        method      = "PATCH"
        uri         = "${local.sql_api}/${instance}"
        body        = { settings = { activationPolicy = "NEVER" } }
      }
      "sql-${k}-start" = {
        description = "Enciende la instancia de Cloud SQL ${instance} (activationPolicy ALWAYS) al empezar el horario."
        schedule    = var.start_schedule
        method      = "PATCH"
        uri         = "${local.sql_api}/${instance}"
        body        = { settings = { activationPolicy = "ALWAYS" } }
      }
    }
  ]...)

  # GKE: el autoescalador de clúster puede deshacer un cambio manual de tamaño, así que el
  # apagado primero lo desactiva y después lleva el pool a 0; el encendido devuelve el tamaño
  # mínimo y después reactiva el autoescalado con los límites de la configuración. Así, un
  # cambio de min o max en gke_node_pools entra con el siguiente encendido.
  gke_jobs = merge({}, [
    for k, p in var.gke_node_pools : {
      "gke-${k}-stop-autoscaling" = {
        description = "Apagado, paso 1: desactiva el autoescalado del pool ${p.node_pool}."
        schedule    = var.stop_schedule
        method      = "POST"
        uri         = "${local.gke_api}/${p.location}/clusters/${p.cluster}/nodePools/${p.node_pool}:setAutoscaling"
        body        = { autoscaling = { enabled = false } }
      }
      "gke-${k}-stop-resize" = {
        description = "Apagado, paso 2: lleva el pool ${p.node_pool} a 0 nodos."
        schedule    = local.stop_step_schedule
        method      = "POST"
        uri         = "${local.gke_api}/${p.location}/clusters/${p.cluster}/nodePools/${p.node_pool}:setSize"
        body        = { nodeCount = 0 }
      }
      "gke-${k}-start-resize" = {
        description = "Encendido, paso 1: devuelve el pool ${p.node_pool} a su tamaño mínimo (al menos 1 nodo por zona)."
        schedule    = var.start_schedule
        method      = "POST"
        uri         = "${local.gke_api}/${p.location}/clusters/${p.cluster}/nodePools/${p.node_pool}:setSize"
        body        = { nodeCount = max(p.min_node_count, 1) }
      }
      "gke-${k}-start-autoscaling" = {
        description = "Encendido, paso 2: reactiva el autoescalado del pool ${p.node_pool} con sus límites."
        schedule    = local.start_step_schedule
        method      = "POST"
        uri         = "${local.gke_api}/${p.location}/clusters/${p.cluster}/nodePools/${p.node_pool}:setAutoscaling"
        body = {
          autoscaling = {
            enabled      = true
            minNodeCount = p.min_node_count
            maxNodeCount = p.max_node_count
          }
        }
      }
    }
  ]...)

  jobs = merge(local.sql_jobs, local.gke_jobs)
}

# VERIFICAR-EN-APPLY: que cada trabajo, lanzado a mano con gcloud scheduler jobs run, termine en
# 2xx con el token de service_account_email (agente de servicio de Cloud Scheduler configurado al
# habilitar la API) y que la operación que devuelve la API (Cloud SQL o GKE) termine en DONE; el
# trabajo solo ve la respuesta inicial, no el final de la operación.
# VERIFICAR-EN-APPLY: que setSize de un pool regional cuente nodeCount por zona (como
# initial_node_count) y que el paso 2 de cada lado encuentre libre la operación del paso 1
# (gke_step_minutes y los reintentos cubren operaciones de hasta unos 7 minutos).
resource "google_cloud_scheduler_job" "this" {
  for_each = local.jobs

  project     = var.project_id
  region      = var.region
  name        = "${local.base_name}-${each.key}-${local.region_code}"
  description = each.value.description
  schedule    = each.value.schedule
  time_zone   = var.time_zone

  # Explícito para que drift.yml marque un trabajo pausado a mano (el apagado dejaría de correr
  # sin que nadie lo note).
  paused = false

  # Las APIs responden enseguida con una operación de larga duración; 3 minutos sobran.
  attempt_deadline = "180s"

  # Reintentos ante 5xx o una operación en curso del mismo clúster o instancia: 30 s, 60 s y
  # luego 120 s (unos 7.5 minutos en total), menos que gke_step_minutes por defecto.
  retry_config {
    retry_count          = 5
    min_backoff_duration = "30s"
    max_backoff_duration = "120s"
    max_doublings        = 2
  }

  http_target {
    uri         = each.value.uri
    http_method = each.value.method
    headers = {
      "Content-Type" = "application/json"
    }
    body = base64encode(jsonencode(each.value.body))

    # El token OAuth solo sirve para APIs de Google (*.googleapis.com).
    oauth_token {
      service_account_email = var.service_account_email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
}
