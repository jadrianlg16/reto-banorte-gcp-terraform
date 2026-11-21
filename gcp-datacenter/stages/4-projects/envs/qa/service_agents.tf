# Agentes de servicio de Google de cada proyecto de servicio. Sus correos tienen formato fijo a
# partir del número del proyecto; se arman aquí y no se leen del atributo email de
# google_project_service_identity porque ese atributo no lo llenan todos los servicios.

locals {
  # Servicios cuyo agente no existe hasta el primer uso del servicio: se crea antes de darle
  # permisos con google_project_service_identity (solo en google-beta en el proveedor 6.x).
  # Los de container, compute y run aparecen al habilitar la API; el de Cloud Storage lo crea
  # la fuente de datos google_storage_project_service_account.
  # VERIFICAR-EN-APPLY: que generateServiceIdentity acepte sqladmin, file, redis y gkebackup; si
  # algún servicio no lo admite, quitarlo de esta lista (su agente existe al habilitar la API).
  # VERIFICAR-EN-APPLY: que los agentes de container (container-engine-robot), compute
  # (compute-system) y run (serverless-robot-prod) existan justo después de habilitar sus APIs;
  # si no, agregar esos servicios a esta lista.
  generated_identity_services = toset([
    "file.googleapis.com",
    "gkebackup.googleapis.com",
    "redis.googleapis.com",
    "sqladmin.googleapis.com",
  ])

  service_identities = {
    for pair in setproduct(keys(var.applications), local.generated_identity_services) :
    "${pair[0]}/${pair[1]}" => { app = pair[0], service = pair[1] }
  }

  # [app][agente] → miembro de IAM (serviceAccount:<correo>).
  service_agents = {
    for app, p in module.project : app => {
      apis      = "serviceAccount:${p.project_number}@cloudservices.gserviceaccount.com"
      compute   = "serviceAccount:service-${p.project_number}@compute-system.iam.gserviceaccount.com"
      filestore = "serviceAccount:service-${p.project_number}@cloud-filer.iam.gserviceaccount.com"
      gke       = "serviceAccount:service-${p.project_number}@container-engine-robot.iam.gserviceaccount.com"
      gkebackup = "serviceAccount:service-${p.project_number}@gcp-sa-gkebackup.iam.gserviceaccount.com"
      redis     = "serviceAccount:service-${p.project_number}@cloud-redis.iam.gserviceaccount.com"
      run       = "serviceAccount:service-${p.project_number}@serverless-robot-prod.iam.gserviceaccount.com"
      sql       = "serviceAccount:service-${p.project_number}@gcp-sa-cloud-sql.iam.gserviceaccount.com"
      storage   = "serviceAccount:${data.google_storage_project_service_account.this[app].email_address}"
    }
  }
}

resource "google_project_service_identity" "this" {
  provider = google-beta
  for_each = local.service_identities

  # project_id de project-factory se publica después de habilitar las APIs.
  project = module.project[each.value.app].project_id
  service = each.value.service
}

# Leerla crea el agente de Cloud Storage del proyecto si todavía no existe. Se consulta con el
# número del proyecto: el ID se conoce en el plan y la lectura correría en el plan del primer
# apply contra un proyecto que todavía no existe; el número solo se conoce al crearlo.
# VERIFICAR-EN-APPLY: que el API de Cloud Storage acepte el número de proyecto.
data "google_storage_project_service_account" "this" {
  for_each = var.applications

  project = module.project[each.key].project_number
}
