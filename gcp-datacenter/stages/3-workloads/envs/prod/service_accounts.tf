# Cuentas de ejecución de la aplicación y cuenta del apagado fuera de horario (ADR 0029 §4: son
# principales del entorno, así que esta raíz los crea y les da permisos de proyecto), y sus
# permisos sobre recursos del entorno que crea 1-base (secretos y repositorio de imágenes).
# Ningún permiso de proyecto para un principal que esta raíz no crea: los de los agentes de
# servicio, del pipeline y de las personas están en 0-bootstrap y 1-base.

locals {
  # Usos de las cuentas de ejecución → roles mínimos en el proyecto. gke_nodes sigue la lista
  # mínima de la cuenta de nodos de GKE; workload es la cuenta de los pods (Workload Identity) y
  # run la del servicio de Cloud Run: telemetría y nada más. Los secretos se dan uno por uno, la
  # lectura de imágenes sobre el repositorio del entorno y Cloud SQL lo da el módulo cloud-sql
  # limitado a la instancia.
  runtime_roles = {
    gke_nodes = [
      "roles/autoscaling.metricsWriter",
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
      "roles/monitoring.viewer",
      "roles/stackdriver.resourceMetadata.writer",
    ]
    workload = [
      "roles/cloudtrace.agent",
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
    ]
    mig = [
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
    ]
    run = [
      "roles/cloudtrace.agent",
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
    ]
  }

  runtime_project_roles = {
    for pair in flatten([
      for use, roles in local.runtime_roles : [for role in roles : { use = use, role = role }]
    ]) : "${pair.use}/${pair.role}" => pair
  }

  # Correos armados con los atributos configurados (account_id y project) y no con email, que
  # solo se conoce al crear la cuenta: varios módulos usan el correo como llave de for_each
  # (usuarios IAM de Cloud SQL) y el primer plan debe conocerlo. La referencia al recurso
  # mantiene el orden (la cuenta existe antes que lo que la usa).
  service_accounts = {
    for use, sa in google_service_account.runtime : use => "${sa.account_id}@${sa.project}.iam.gserviceaccount.com"
  }
  scheduler_service_account = local.off_hours_enabled ? "${google_service_account.scheduler["this"].account_id}@${google_service_account.scheduler["this"].project}.iam.gserviceaccount.com" : null

  # Quién descarga imágenes del repositorio del entorno: nodos de GKE y VM del MIG. Cloud Run
  # descarga con su agente de servicio, que es del proyecto y recibe permisos en 1-base.
  artifact_readers = toset(["gke_nodes", "mig"])

  # Secreto × cuenta que lo lee.
  secret_readers = {
    for pair in setproduct(sort(tolist(var.application_secrets)), ["workload", "run"]) :
    "${pair[0]}/${pair[1]}" => { secret = pair[0], use = pair[1] }
  }
}

# VERIFICAR-EN-APPLY: que una cuenta recién creada se pueda usar en el mismo apply (nodos de GKE,
# plantilla del MIG, Cloud Run, usuarios IAM de Cloud SQL y trabajos de Cloud Scheduler) sin
# errores de propagación; antes la creaba otra etapa, minutos antes.
resource "google_service_account" "runtime" {
  for_each = local.runtime_roles

  project      = var.project_id
  account_id   = "${var.prefix}-${var.environment}-${var.application}-${replace(each.key, "_", "-")}"
  display_name = "${var.application} ${each.key} (${var.environment})"
  description  = "Cuenta de ejecución ${each.key} de la aplicación ${var.application} en ${var.environment}. Administrada por Terraform (3-workloads)."

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", "${var.prefix}-${var.environment}-${var.application}-${replace(each.key, "_", "-")}"))
      error_message = "El ID de cuenta de servicio <prefix>-<environment>-<application>-<uso> debe tener de 6 a 30 caracteres (ADR 0017)."
    }
  }
}

resource "google_project_iam_member" "runtime" {
  for_each = local.runtime_project_roles

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${local.service_accounts[each.value.use]}"
}

# Lectura de los secretos de la aplicación por las cuentas workload y run (ADR 0015: los valores
# los carga una persona fuera de Terraform). Los contenedores son del entorno y los crea 1-base.
resource "google_secret_manager_secret_iam_member" "runtime" {
  for_each = local.secret_readers

  secret_id = local.secret_ids[each.value.secret]
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.service_accounts[each.value.use]}"
}

# Lectura del repositorio de imágenes del entorno y la aplicación (lo crea 1-base); solo ese
# repositorio, no el proyecto: los nodos de dev no leen las imágenes de prod.
resource "google_artifact_registry_repository_iam_member" "reader" {
  for_each = local.artifact_readers

  project    = local.artifact_repository.project
  location   = local.artifact_repository.location
  repository = local.artifact_repository.repository
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${local.service_accounts[each.key]}"

  # La URL del repositorio se comprueba antes (terraform_data.upstream_checks).
  depends_on = [terraform_data.upstream_checks]
}

# Cuenta de los trabajos de Cloud Scheduler del apagado fuera de horario (ADR 0028), solo con
# off_hours_shutdown.enabled (nunca en prod). Su único permiso es el rol personalizado que crea
# 1-base una sola vez (off_hours_role_id): detener y encender Cloud SQL y cambiar autoescalado y
# tamaño de los pools de GKE.
resource "google_service_account" "scheduler" {
  for_each = local.off_hours_enabled ? toset(["this"]) : toset([])

  project      = var.project_id
  account_id   = "${var.prefix}-${var.environment}-${var.application}-sched"
  display_name = "${var.application} apagado fuera de horario (${var.environment})"
  description  = "Token OAuth de los trabajos de Cloud Scheduler que detienen y encienden Cloud SQL y los pools de GKE de ${var.application} en ${var.environment} (ADR 0028). Administrada por Terraform (3-workloads)."

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", "${var.prefix}-${var.environment}-${var.application}-sched"))
      error_message = "El ID de cuenta de servicio <prefix>-<environment>-<application>-sched debe tener de 6 a 30 caracteres (ADR 0017)."
    }
  }
}

# VERIFICAR-EN-APPLY: que el rol de 1-base baste para las tres llamadas de los trabajos (gcloud
# scheduler jobs run de cada uno con respuesta 2xx). Sin condición: el rol junta permisos de
# Cloud SQL y de GKE, y una condición por nombre sobre un tipo que no la admite niega todo
# (ADR 0029 §3). Por eso la cuenta del apagado de dev también podría detener la instancia o
# cambiar los pools de otro entorno del proyecto; los trabajos solo apuntan a los de su entorno.
resource "google_project_iam_member" "scheduler" {
  for_each = local.off_hours_enabled ? toset(["this"]) : toset([])

  project = var.project_id
  role    = local.off_hours_role_id
  member  = "serviceAccount:${local.scheduler_service_account}"
}
