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

  # Condición del rol del apagado (hallazgo N4 de la segunda revisión): solo la instancia de
  # Cloud SQL y los clústeres de GKE del entorno. Cloud SQL (sqladmin.googleapis.com/Instance) y
  # GKE (container.googleapis.com/Cluster, nombre projects/<id>/locations/<ubicación>/clusters/<c>)
  # admiten resource.name ("Resource attributes for IAM Conditions"); la forma
  # resource.type != … || nombre de "Attribute reference for IAM Conditions" limita cada parte a
  # su tipo y deja pasar lo que se evalúa sobre otro tipo. Sin ella, la cuenta del apagado de dev
  # (que tf-wl-dev adjunta a sus trabajos de Cloud Scheduler) podría parchear la instancia o
  # cambiar los clústeres de prod con un trabajo que llame a esas API.
  # VERIFICAR-EN-APPLY: que los tres trabajos (instances.patch, nodePools.setAutoscaling y
  # setSize) respondan 2xx con esta condición sobre la instancia y el clúster del entorno, y que
  # un trabajo de dev contra la instancia de qa reciba 403.
  off_hours_condition = {
    for e in var.environments : e => {
      title       = "apagado-${e}"
      description = "Solo la instancia de Cloud SQL ${var.prefix}-${e}-data- y los clústeres de GKE ${var.prefix}-${e}-."
      expression = join(" && ", [
        "(resource.type != \"sqladmin.googleapis.com/Instance\" || resource.name.startsWith(\"projects/${local.project_id}/instances/${var.prefix}-${e}-data-\"))",
        "(${join(" || ", concat(
          ["resource.type != \"container.googleapis.com/Cluster\""],
          [for r in [var.primary_region, var.dr_region] : "resource.name.startsWith(\"projects/${local.project_id}/locations/${r}/clusters/${var.prefix}-${e}-\")"],
        ))})",
      ])
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
    # (gcloud scheduler jobs run de cada uno con respuesta 2xx). Condicionado a la instancia y los
    # clústeres del entorno (local.off_hours_condition).
    [
      for k, a in local.runtime_accounts : {
        key       = "runtime|${k}|${local.custom_role_ids["off_hours_scheduler"]}"
        scope     = "project"
        resource  = local.project_id
        role      = local.custom_role_ids["off_hours_scheduler"]
        member    = "serviceAccount:${local.runtime_emails[k]}"
        condition = local.off_hours_condition[a.environment]
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

  # Workload Identity por clúster (hallazgo N1 de la segunda revisión). El pool
  # <proyecto>.svc.id.goog es uno solo para el proyecto, y un principal por namespace y cuenta de
  # Kubernetes (serviceAccount:<proyecto>.svc.id.goog[<ns>/<ksa>]) vale desde cualquier clúster
  # del proyecto: quien administre otro clúster crea el mismo namespace y obtiene la cuenta
  # ("Identity sameness" de la documentación de Workload Identity Federation for GKE). Por eso el
  # enlace usa el principalSet de "todos los pods de un clúster":
  #   principalSet://iam.googleapis.com/projects/<número>/locations/global/workloadIdentityPools/
  #   <proyecto>.svc.id.goog/kubernetes.cluster/https://container.googleapis.com/v1/projects/
  #   <proyecto>/locations/<ubicación>/clusters/<clúster>
  # (tabla de tipos de principal de "About Workload Identity Federation for GKE", actualizada el
  # 2026-11-23, y "Principal identifiers" de IAM). La documentación no ofrece un identificador
  # que combine clúster, namespace y cuenta de Kubernetes (el de la cuenta por UID sí lo limita a
  # un objeto de un clúster, pero el UID solo existe después de crear la cuenta en el clúster).
  # CONSECUENCIA: cualquier pod del clúster, de cualquier namespace, que use una cuenta de
  # Kubernetes anotada con la cuenta workload obtiene esa cuenta. Cada clúster es de un solo
  # entorno y una sola aplicación (<prefix>-<env>-<app>-gke[-dr], ADR 0029 §4), así que la
  # frontera es el clúster.
  #
  # Clústeres por convención: el primario en primary_region y, en dr_environments, el de DR en
  # dr_region (3-workloads solo crea el de DR en esos entornos: necesita sus llaves de DR).
  workload_identity_clusters = {
    for c in flatten([
      for t in setproduct(var.environments, sort(tolist(var.applications))) : concat(
        [{ environment = t[0], application = t[1], key = "primary", location = var.primary_region, name = "${var.prefix}-${t[0]}-${t[1]}-gke" }],
        contains(var.dr_environments, t[0]) ? [{ environment = t[0], application = t[1], key = "dr", location = var.dr_region, name = "${var.prefix}-${t[0]}-${t[1]}-gke-dr" }] : [],
      )
    ]) : "${c.environment}/${c.application}/${c.key}" => c
  }

  workload_identity_members = {
    for k, c in local.workload_identity_clusters :
    k => "principalSet://iam.googleapis.com/projects/${local.project_number}/locations/global/workloadIdentityPools/${local.project_id}.svc.id.goog/kubernetes.cluster/https://container.googleapis.com/v1/projects/${local.project_id}/locations/${c.location}/clusters/${c.name}"
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

# Workload Identity: los pods del clúster del entorno y la aplicación actúan como la cuenta
# workload (local.workload_identity_members). El pool <proyecto>.svc.id.goog lo crea GKE al
# activar Workload Identity en el primer clúster del proyecto y no lo borra aunque se borren
# todos los clústeres (documentación de Workload Identity Federation for GKE,
# https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity). Antes de que
# exista, la asignación falla (HYPOTHESIS): por eso solo se crea con
# gke_workload_identity_bindings = true, después del primer clúster. El principalSet del clúster
# de DR se enlaza antes de que el clúster exista (se crea con dr_active).
# VERIFICAR-EN-APPLY: que la asignación falle sin el pool y funcione después del primer clúster
# (gcloud iam workload-identity-pools describe <proyecto>.svc.id.goog --location=global); que IAM
# acepte el principalSet kubernetes.cluster/… de un clúster que todavía no existe; que un pod del
# clúster <prefix>-<env>-<app>-gke con una cuenta de Kubernetes anotada
# (iam.gke.io/gcp-service-account) obtenga el token de la cuenta workload, y que un pod de otro
# clúster con el mismo namespace y la misma cuenta de Kubernetes reciba un rechazo.
resource "google_service_account_iam_member" "workload_identity" {
  for_each = var.gke_workload_identity_bindings ? local.workload_identity_clusters : {}

  service_account_id = google_service_account.runtime["${each.value.environment}/${each.value.application}/workload"].name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.workload_identity_members[each.key]
}
