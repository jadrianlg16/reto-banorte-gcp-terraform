# Permisos de proyecto para principales compartidos (ADR 0029 §4): grupos de personas de solo
# lectura, más los de las cuentas de ejecución de los entornos (runtime_accounts.tf). Ninguna raíz
# de entorno asigna roles de proyecto.
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

  # El tagUser del agente de GKE y de <número>@cloudservices (etiquetas seguras de nodos y VM) lo
  # da 0-bootstrap (main.tf): si esta etapa pudiera asignar tagUser, su cuenta podría dárselo a sí
  # misma y quitar la etiqueta de protección (hallazgo 1).
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

module "iam" {
  source = "../../modules/iam"

  bindings = local.project_bindings
}
