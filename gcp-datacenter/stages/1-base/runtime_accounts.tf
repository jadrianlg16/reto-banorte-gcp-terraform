# Cuentas de ejecución de las cargas, por entorno y aplicación (hallazgos 2 y 4 de la revisión de
# seguridad del ADR 0029): las crea 1-base con sus permisos, y 3-workloads/<env> solo las usa
# (las lee de la salida runtime_service_accounts). Así la cuenta de cargas de un entorno
# (tf-wl-<env>) no administra cuentas de servicio ni asigna roles de proyecto: solo recibe
# serviceAccountUser sobre las cuentas de su entorno que adjunta a sus recursos.
#
# Cuentas (<prefix>-<env>-<app>-<uso>, ADR 0017):
#   gke_nodes  nodos de GKE           workload  pods (Workload Identity)
#   mig        VM del MIG             run       servicio de Cloud Run
#   scheduler  trabajos del apagado fuera de horario (<prefix>-<env>-<app>-sched, ADR 0028),
#              solo en off_hours_environments (nunca prod).
#
# Los roles de proyecto los asigna la concesión delegada de 1-base (lista
# runtime_grantable_roles de stages/0-bootstrap/service_accounts.tf, que debe coincidir con
# local.runtime_roles, local.sql_login_roles y el rol del apagado de este archivo).

locals {
  # Uso → roles mínimos en el proyecto. gke_nodes sigue la lista mínima de la cuenta de nodos de
  # GKE; workload y run, telemetría y nada más. Los secretos se dan uno por uno, la lectura de
  # imágenes sobre el repositorio del entorno y la aplicación, y Cloud SQL limitado a las
  # instancias del entorno.
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

  # Cuentas que entran a Cloud SQL por IAM (las de los cómputos: pods de GKE, Cloud Run y VM del
  # MIG) y sus roles. Antes los daba el módulo cloud-sql desde 3-workloads, limitados a la
  # instancia; ahora 3-workloads le pasa grant_iam_login_roles = false.
  sql_login_uses  = ["workload", "run", "mig"]
  sql_login_roles = ["roles/cloudsql.client", "roles/cloudsql.instanceUser"]

  # Quién descarga imágenes del repositorio de su entorno y aplicación: nodos de GKE y VM del
  # MIG. Cloud Run descarga con su agente de servicio (artifacts.tf).
  artifact_reader_uses = ["gke_nodes", "mig"]

  # Quién lee los secretos de su entorno: los pods (workload) y Cloud Run (run). Con varias
  # aplicaciones en un entorno, cada una lee todos los secretos de ese entorno: la frontera es el
  # entorno (ADR 0029 §3).
  secret_reader_uses = ["workload", "run"]

  # Cuentas que tf-wl-<env> adjunta a sus recursos (actAs): nodos de GKE, plantilla del MIG,
  # Cloud Run y trabajos de Cloud Scheduler. workload no: la usan los pods por Workload
  # Identity, no Terraform.
  # VERIFICAR-EN-APPLY: que crear los usuarios IAM de Cloud SQL de workload, run y mig no exija
  # actAs sobre esas cuentas.
  attached_uses = ["gke_nodes", "mig", "run", "scheduler"]

  # Entornos con cuenta del apagado (ADR 0028).
  off_hours_envs = [for e in var.environments : e if contains(var.off_hours_environments, e)]

  # "<env>/<app>/<uso>" → cuenta.
  runtime_accounts = merge(
    {
      for t in setproduct(var.environments, sort(tolist(var.applications)), sort(keys(local.runtime_roles))) :
      "${t[0]}/${t[1]}/${t[2]}" => {
        environment = t[0]
        application = t[1]
        use         = t[2]
        account_id  = "${var.prefix}-${t[0]}-${t[1]}-${replace(t[2], "_", "-")}"
      }
    },
    {
      for t in setproduct(local.off_hours_envs, sort(tolist(var.applications))) :
      "${t[0]}/${t[1]}/scheduler" => {
        environment = t[0]
        application = t[1]
        use         = "scheduler"
        account_id  = "${var.prefix}-${t[0]}-${t[1]}-sched"
      }
    },
  )

  # Correos armados con los atributos configurados (account_id y project) y no con email, que
  # solo se conoce al crear la cuenta: 3-workloads usa el correo como llave de for_each (usuarios
  # IAM de Cloud SQL) y el primer plan debe conocerlo. La referencia al recurso mantiene el orden.
  runtime_emails = {
    for k, sa in google_service_account.runtime : k => "${sa.account_id}@${sa.project}.iam.gserviceaccount.com"
  }

  # Condición de Cloud SQL: solo las instancias del entorno (<prefix>-<env>-data-..., nombre del
  # módulo cloud-sql), con el formato de la documentación de condiciones de Cloud SQL
  # (https://cloud.google.com/sql/docs/postgres/iam-conditions). Antes el módulo la limitaba a
  # una instancia y su réplica; ahora cubre las del entorno, que 1-base no conoce por nombre.
  # VERIFICAR-EN-APPLY: que cloudsql.client e instanceUser con esta condición dejen entrar con un
  # token IAM a la instancia del entorno y nieguen la de otro entorno.
  sql_instances_condition = {
    for e in var.environments : e => {
      title       = "cloudsql-${e}"
      description = "Solo las instancias de Cloud SQL ${var.prefix}-${e}-data-."
      expression  = "resource.type == \"sqladmin.googleapis.com/Instance\" && resource.name.startsWith(\"projects/${local.project_id}/instances/${var.prefix}-${e}-data-\")"
    }
  }

  # Asignaciones de proyecto (las agrega iam.tf a module.iam, con las de personas y agentes).
  runtime_project_bindings = concat(
    flatten([
      for k, a in local.runtime_accounts : [
        for r in lookup(local.runtime_roles, a.use, []) : {
          key       = "runtime|${k}|${r}"
          scope     = "project"
          resource  = local.project_id
          role      = r
          member    = "serviceAccount:${local.runtime_emails[k]}"
          condition = null
        }
      ]
    ]),
    flatten([
      for k, a in local.runtime_accounts : [
        for r in local.sql_login_roles : {
          key       = "runtime|${k}|${r}"
          scope     = "project"
          resource  = local.project_id
          role      = r
          member    = "serviceAccount:${local.runtime_emails[k]}"
          condition = local.sql_instances_condition[a.environment]
        }
      ] if contains(local.sql_login_uses, a.use)
    ]),
    # VERIFICAR-EN-APPLY: que el rol del apagado baste para las tres llamadas de los trabajos
    # (gcloud scheduler jobs run de cada uno con respuesta 2xx). Sin condición: el rol junta
    # permisos de Cloud SQL y de GKE, y una condición por nombre sobre un tipo que no la admite
    # niega todo (ADR 0029 §3). La cuenta del apagado de dev podría detener la instancia o
    # cambiar los pools de otro entorno del proyecto; sus trabajos solo apuntan a los de dev.
    [
      for k, a in local.runtime_accounts : {
        key       = "runtime|${k}|${local.custom_role_ids["off_hours_scheduler"]}"
        scope     = "project"
        resource  = local.project_id
        role      = local.custom_role_ids["off_hours_scheduler"]
        member    = "serviceAccount:${local.runtime_emails[k]}"
        condition = null
      } if a.use == "scheduler"
    ],
  )

  # "<env>/<app>/<uso>/<secreto>" → lectura de un secreto del entorno.
  runtime_secret_readers = merge([
    for e, names in local.secret_envs : {
      for t in setproduct(sort(tolist(var.applications)), local.secret_reader_uses, names) :
      "${e}/${t[0]}/${t[1]}/${t[2]}" => { account = "${e}/${t[0]}/${t[1]}", environment = e, secret = t[2] }
    }
  ]...)

  # Cuenta de Kubernetes de Workload Identity: namespace <app>-<env> y gke_workload_ksa_name. El
  # pool <proyecto>.svc.id.goog es uno solo para el proyecto: lo que separa a los entornos es el
  # namespace (ADR 0029 §9).
  workload_identity_members = {
    for t in setproduct(var.environments, sort(tolist(var.applications))) :
    "${t[0]}/${t[1]}" => "serviceAccount:${local.project_id}.svc.id.goog[${t[1]}-${t[0]}/${var.gke_workload_ksa_name}]"
  }
}

# VERIFICAR-EN-APPLY: que 3-workloads pueda usar una cuenta recién creada en el apply siguiente
# (nodos de GKE, plantilla del MIG, Cloud Run, usuarios IAM de Cloud SQL y trabajos de Cloud
# Scheduler) sin errores de propagación.
resource "google_service_account" "runtime" {
  for_each = local.runtime_accounts

  project      = local.project_id
  account_id   = each.value.account_id
  display_name = "${each.value.application} ${each.value.use} (${each.value.environment})"
  description  = "Cuenta de ejecución ${each.value.use} de la aplicación ${each.value.application} en ${each.value.environment}. Administrada por Terraform (1-base)."

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", each.value.account_id))
      error_message = "El ID de cuenta de servicio <prefix>-<entorno>-<aplicación>-<uso> debe tener de 6 a 30 caracteres (ADR 0017)."
    }
  }
}

# Lectura de los secretos del entorno por las cuentas workload y run (ADR 0015: los valores los
# carga una persona fuera de Terraform).
resource "google_secret_manager_secret_iam_member" "runtime" {
  for_each = local.runtime_secret_readers

  secret_id = module.secrets[each.value.environment].secret_ids[each.value.secret]
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.runtime_emails[each.value.account]}"
}

# Lectura del repositorio de imágenes del entorno y la aplicación; solo ese repositorio, no el
# proyecto: los nodos de dev no leen las imágenes de prod.
resource "google_artifact_registry_repository_iam_member" "runtime_reader" {
  for_each = { for k, a in local.runtime_accounts : k => a if contains(local.artifact_reader_uses, a.use) }

  project    = google_artifact_registry_repository.this["${each.value.environment}/${each.value.application}"].project
  location   = google_artifact_registry_repository.this["${each.value.environment}/${each.value.application}"].location
  repository = google_artifact_registry_repository.this["${each.value.environment}/${each.value.application}"].repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${local.runtime_emails[each.key]}"
}

# La cuenta de cargas del entorno adjunta estas cuentas a sus recursos: serviceAccountUser solo
# sobre cada una, nunca en el proyecto (hallazgo 2).
resource "google_service_account_iam_member" "workloads_user" {
  for_each = { for k, a in local.runtime_accounts : k => a if contains(local.attached_uses, a.use) }

  service_account_id = google_service_account.runtime[each.key].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${local.stage_service_accounts["3-workloads/${each.value.environment}"]}"
}

# Workload Identity: la cuenta de Kubernetes <app>-<env>/<gke_workload_ksa_name> actúa como la
# cuenta workload. El pool <proyecto>.svc.id.goog lo crea GKE al activar Workload Identity en el
# primer clúster del proyecto y no lo borra aunque se borren todos los clústeres (documentación
# de Workload Identity Federation for GKE,
# https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity). Antes de que
# exista, la asignación falla (HYPOTHESIS): por eso solo se crea con
# gke_workload_identity_bindings = true, después del primer clúster.
# VERIFICAR-EN-APPLY: que la asignación falle sin el pool y funcione después del primer clúster
# (gcloud iam workload-identity-pools describe <proyecto>.svc.id.goog --location=global), y que
# un pod de <app>-<env> con la cuenta de Kubernetes anotada obtenga el token de la cuenta workload.
resource "google_service_account_iam_member" "workload_identity" {
  for_each = var.gke_workload_identity_bindings ? local.workload_identity_members : {}

  service_account_id = google_service_account.runtime["${each.key}/workload"].name
  role               = "roles/iam.workloadIdentityUser"
  member             = each.value
}
