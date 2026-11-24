# Permisos de proyecto para principales compartidos (ADR 0029 §4): grupos de personas de solo
# lectura y agentes de servicio, más los de las cuentas de ejecución de los entornos
# (runtime_accounts.tf). Ninguna raíz de entorno asigna roles de proyecto.
#
# La cuenta de 1-base solo puede asignar estos roles: su projectIamAdmin está condicionado en
# 0-bootstrap (local.base_grantable_roles y local.runtime_grantable_roles de
# stages/0-bootstrap/service_accounts.tf). Un rol nuevo aquí exige agregarlo también allí.

locals {
  # Grupo → roles de solo lectura en el proyecto.
  group_roles = {
    readers         = ["roles/viewer", "roles/logging.viewer", "roles/monitoring.viewer"]
    security_admins = ["roles/viewer", "roles/iam.securityReviewer", "roles/logging.viewer", "roles/cloudkms.viewer"]
    auditors        = ["roles/viewer", "roles/iam.securityReviewer", "roles/logging.privateLogViewer"]
  }

  # Etiquetas seguras de la red (lb_backend, iap_ssh) en nodos de GKE y VM de MIG: el agente de
  # GKE y la cuenta de las APIs de Google (crea las VM de los MIG y los nodos) las aplican.
  tag_user_agents = ["gke", "apis"]

  project_bindings = concat(
    flatten([
      for g, email in var.groups : [
        for r in local.group_roles[g] : {
          key      = "group|${g}|${r}"
          scope    = "project"
          resource = local.project_id
          role     = r
          member   = "group:${email}"
        }
      ]
    ]),
    [
      for a in local.tag_user_agents : {
        key      = "agent|${a}|roles/resourcemanager.tagUser"
        scope    = "project"
        resource = local.project_id
        role     = "roles/resourcemanager.tagUser"
        member   = local.service_agents[a]
      }
    ],
    # Auditoría: lectura de los objetos del bucket de logs.
    contains(keys(var.groups), "auditors") ? [{
      key      = "group|auditors|bucket:audit_logs|roles/storage.objectViewer"
      scope    = "storage_bucket"
      resource = module.audit_logs.bucket_name
      role     = "roles/storage.objectViewer"
      member   = "group:${var.groups["auditors"]}"
    }] : [],
    local.runtime_project_bindings,
  )
}

# VERIFICAR-EN-APPLY: que tagUser en el proyecto baste al agente de GKE y a
# <número>@cloudservices para crear nodos y VM con resource_manager_tags.
module "iam" {
  source = "../../modules/iam"

  bindings = local.project_bindings
}
