# Permisos de la etapa 4, todos aditivos y por el módulo iam salvo los de etiquetas seguras
# (el módulo no tiene scope de valor de etiqueta). Las llaves del for_each son explícitas: los
# miembros (correos de cuentas y agentes) se calculan en el mismo plan.

locals {
  regional_locations = [var.primary_region, var.dr_region]

  # Uso de llave de 2-security → agentes del proyecto de servicio que la usan.
  # gke: el agente de GKE cifra los secretos de Kubernetes y el de Compute los discos de
  # arranque de los nodos (el módulo gke usa la misma llave para los dos).
  # secrets no aparece: los secretos viven en el proyecto security y su agente lo maneja la
  # etapa 2.
  kms_consumers = {
    backup    = ["gkebackup"]
    compute   = ["compute"]
    filestore = ["filestore"]
    gke       = ["gke", "compute"]
    redis     = ["redis"]
    run       = ["run"]
    sql       = ["sql"]
    storage   = ["storage"]
  }

  # Subred del spoke (llave de §5) → agentes que crean recursos en ella desde el proyecto de
  # servicio. apis (<número>@cloudservices) crea las VM de los MIG y los nodos de GKE; gke es el
  # agente de GKE; run es el agente de Cloud Run para la salida directa a la VPC. Las subredes
  # proxy-only no se otorgan: nadie las referencia desde el proyecto de servicio.
  subnet_agents = {
    app    = ["apis", "gke"]
    app_dr = ["apis", "gke"]
    run    = ["run"]
    run_dr = ["run"]
  }

  # Solo las subredes que existen en el estado del spoke (sin DR en dev y qa).
  granted_subnets = {
    for k, agents in local.subnet_agents : k => {
      agents   = agents
      resource = "projects/${local.host_project_id}/regions/${local.subnets[k].region}/subnetworks/${local.subnets[k].name}"
    } if contains(keys(local.subnets), k)
  }

  workloads_member = "serviceAccount:${var.workloads_service_account}"

  bindings = concat(
    # Roles mínimos de cada cuenta de ejecución en su proyecto.
    flatten([
      for k, sa in local.runtime_service_accounts : [
        for role in local.runtime_roles[sa.use] : {
          key      = "runtime/${k}/${role}"
          scope    = "project"
          resource = module.project[sa.app].project_id
          role     = role
          member   = google_service_account.runtime[k].member
        }
      ]
    ]),

    # El pipeline de la etapa 5 adjunta las cuentas de ejecución a nodos, plantillas y
    # servicios (actAs), solo sobre cada cuenta y no sobre todo el proyecto.
    [
      for k, sa in local.runtime_service_accounts : {
        key      = "actas/${k}"
        scope    = "service_account"
        resource = google_service_account.runtime[k].name
        role     = "roles/iam.serviceAccountUser"
        member   = local.workloads_member
      }
    ],

    # Uso de subredes de la Shared VPC por los agentes de cada proyecto de servicio.
    flatten([
      for app in keys(var.applications) : [
        for subnet, s in local.granted_subnets : [
          for agent in s.agents : {
            key      = "subnet/${app}/${subnet}/${agent}"
            scope    = "subnetwork"
            resource = s.resource
            role     = "roles/compute.networkUser"
            member   = local.service_agents[app][agent]
          }
        ]
      ]
    ]),

    # El pipeline de la etapa 5 crea en esas subredes plantillas, nodos, reglas de reenvío del
    # balanceador interno y servicios de Cloud Run: necesita compute.subnetworks.use.
    [
      for subnet, s in local.granted_subnets : {
        key      = "subnet/workloads/${subnet}"
        scope    = "subnetwork"
        resource = s.resource
        role     = "roles/compute.networkUser"
        member   = local.workloads_member
      }
    ],

    # GKE en Shared VPC: el agente de GKE del proyecto de servicio administra en el host lo que
    # el clúster necesita (por ejemplo, el acceso del plano de control a la red).
    [
      for app in keys(var.applications) : {
        key      = "host/${app}/gke"
        scope    = "project"
        resource = local.host_project_id
        role     = "roles/container.hostServiceAgentUser"
        member   = local.service_agents[app]["gke"]
      }
    ],

    # CMEK: cada agente sobre las llaves de su uso, en las regiones primaria y de DR (la de DR
    # la usan la réplica, el plan de Backup for GKE y la conmutación con dr_active) y, para
    # Cloud Storage, también en la multirregión us (bucket de doble región).
    flatten([
      for app in keys(var.applications) : [
        for location, keys_by_use in local.kms_key_ids : [
          for use, key_id in keys_by_use : [
            for agent in lookup(local.kms_consumers, use, []) : {
              key      = "kms/${app}/${location}/${use}/${agent}"
              scope    = "kms_crypto_key"
              resource = key_id
              role     = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
              member   = local.service_agents[app][agent]
            }
          ] if contains(local.regional_locations, location) || use == "storage"
        ]
      ]
    ]),

    # Lectura de los secretos de cada aplicación por sus cuentas workload y run (ADR 0015: los
    # valores los carga una persona fuera de Terraform).
    flatten([
      for app, a in var.applications : [
        for name in a.secrets : [
          for use in ["workload", "run"] : {
            key      = "secret/${app}/${name}/${use}"
            scope    = "secret"
            resource = local.secret_ids[name]
            role     = "roles/secretmanager.secretAccessor"
            member   = google_service_account.runtime["${app}/${use}"].member
          }
        ]
      ]
    ]),
  )

  # Etiquetas seguras del spoke: quien crea instancias con ellas necesita tagUser sobre el
  # valor. El pipeline de la etapa 5 las pone en plantillas y pools; apis crea las VM del MIG y
  # los nodos de GKE con esas etiquetas; el agente de GKE las aplica a los nodos.
  tag_users = merge(
    { for tag in keys(local.secure_tags) : "${tag}/workloads" => { tag = tag, member = local.workloads_member } },
    merge([
      for app in keys(var.applications) : {
        for pair in setproduct(keys(local.secure_tags), ["apis", "gke"]) :
        "${pair[0]}/${app}/${pair[1]}" => { tag = pair[0], member = local.service_agents[app][pair[1]] }
      }
    ]...),
  )
}

module "iam" {
  source = "../../../../modules/iam"

  bindings = local.bindings

  # Los agentes de sqladmin, file, redis y gkebackup deben existir antes de recibir permisos.
  depends_on = [google_project_service_identity.this]
}

# VERIFICAR-EN-APPLY: que tagUser sobre el valor baste al agente de GKE y a <número>@cloudservices
# para crear nodos y VM con resource_manager_tags (la documentación de GKE puede pedir además
# tagUser sobre la llave o roles/resourcemanager.tagHoldAdmin).
resource "google_tags_tag_value_iam_member" "tag_user" {
  for_each = local.tag_users

  tag_value = local.secure_tags[each.value.tag]
  role      = "roles/resourcemanager.tagUser"
  member    = each.value.member
}
