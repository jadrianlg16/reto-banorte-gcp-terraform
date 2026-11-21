# IAM por grupos (§7.1) y permisos de carpeta y proyecto de las cuentas de etapa.
#
# Personas: solo roles de lectura, siempre a grupos (nunca user:; el módulo iam lo rechaza).
# developers solo en las carpetas dev y qa. Los cambios los hace el pipeline.
#
# Cuentas de etapa: la etapa 0 les dio los roles de organización y facturación; aquí se dan
# los de las carpetas y proyectos que crea esta etapa (no existían en la etapa 0).
#
# Todas las asignaciones llevan key fija: las carpetas y proyectos se crean en el mismo plan y
# sus IDs no se conocen hasta el apply.

locals {
  # Grupo → roles en la organización.
  group_org_roles = {
    org_admins = [
      "roles/browser",
      "roles/iam.securityReviewer",
      "roles/orgpolicy.policyViewer",
      "roles/resourcemanager.organizationViewer",
    ]
    billing_admins = [
      "roles/billing.viewer",
      "roles/resourcemanager.organizationViewer",
    ]
    security_admins = [
      "roles/accesscontextmanager.policyReader",
      "roles/cloudkms.viewer",
      "roles/iam.securityReviewer",
      "roles/logging.viewer",
      "roles/orgpolicy.policyViewer",
      "roles/securitycenter.adminViewer",
    ]
    network_admins = [
      "roles/browser",
      "roles/compute.networkViewer",
      "roles/dns.reader",
    ]
    auditors = [
      "roles/browser",
      "roles/iam.securityReviewer",
      "roles/logging.privateLogViewer",
      "roles/orgpolicy.policyViewer",
      "roles/securitycenter.findingsViewer",
    ]
  }

  # Grupo → carpetas y roles en ellas. developers nunca en common ni prod.
  group_folder_roles = {
    platform_devops = {
      folders = concat([local.environment], local.environments)
      roles   = ["roles/browser", "roles/logging.viewer", "roles/monitoring.viewer"]
    }
    developers = {
      folders = ["dev", "qa"]
      roles   = ["roles/browser", "roles/logging.viewer", "roles/monitoring.viewer"]
    }
  }

  # Cuenta de etapa → roles en proyectos de common y en las carpetas de entorno.
  stage_grants = {
    "2-security" = {
      # KMS, secretos, agente de Secret Manager e IAM del proyecto (rol personalizado de 4-projects).
      projects = {
        security = [
          "roles/cloudkms.admin",
          "roles/resourcemanager.projectIamAdmin",
          "roles/secretmanager.admin",
          "roles/serviceusage.serviceUsageAdmin",
        ]
      }
      env_folder_roles = []
    }
    "3-networks" = {
      projects = {
        net_hub = [
          "roles/compute.networkAdmin",
          "roles/compute.securityAdmin",
          "roles/dns.admin",
          "roles/serviceusage.serviceUsageAdmin",
        ]
      }
      # Crear el proyecto net-spoke de cada entorno y habilitarlo como host de Shared VPC.
      env_folder_roles = ["roles/compute.xpnAdmin", "roles/resourcemanager.projectCreator"]
    }
    "4-projects" = {
      projects = {}
      # Proyectos de servicio, alta en Shared VPC y permisos de uso de subred.
      env_folder_roles = ["roles/compute.xpnAdmin", "roles/resourcemanager.projectCreator"]
    }
    "5-workloads" = {
      projects = {}
      # Cargas de la etapa 5 en los proyectos de servicio (y uso de las subredes del host).
      env_folder_roles = [
        "roles/backupdr.admin",
        "roles/cloudsql.admin",
        "roles/compute.instanceAdmin.v1",
        "roles/compute.loadBalancerAdmin",
        "roles/compute.networkUser",
        "roles/compute.securityAdmin",
        "roles/container.admin",
        "roles/file.editor",
        "roles/gkebackup.admin",
        "roles/iam.serviceAccountUser",
        "roles/monitoring.editor",
        "roles/redis.admin",
        "roles/run.admin",
        "roles/storage.admin",
      ]
    }
  }

  iam_bindings = concat(
    flatten([
      for g, roles in local.group_org_roles : [
        for r in roles : {
          key      = "group|${g}|org|${r}"
          scope    = "organization"
          resource = var.org_id
          role     = r
          member   = "group:${var.groups[g]}"
        }
      ]
    ]),
    flatten([
      for g, cfg in local.group_folder_roles : [
        for pair in setproduct(cfg.folders, cfg.roles) : {
          key      = "group|${g}|folder:${pair[0]}|${pair[1]}"
          scope    = "folder"
          resource = module.folders.ids[pair[0]]
          role     = pair[1]
          member   = "group:${var.groups[g]}"
        }
      ]
    ]),
    [
      # Auditoría: lectura de los objetos del bucket de logs.
      {
        key      = "group|auditors|bucket:audit_logs|roles/storage.objectViewer"
        scope    = "storage_bucket"
        resource = module.audit_logs.bucket_name
        role     = "roles/storage.objectViewer"
        member   = "group:${var.groups["auditors"]}"
      },
    ],
    flatten([
      for s, cfg in local.stage_grants : [
        for p, roles in cfg.projects : [
          for r in roles : {
            key      = "sa|${s}|project:${p}|${r}"
            scope    = "project"
            resource = module.common_project[p].project_id
            role     = r
            member   = "serviceAccount:${local.stage_service_accounts[s]}"
          }
        ]
      ]
    ]),
    flatten([
      for s, cfg in local.stage_grants : [
        for pair in setproduct(local.environments, cfg.env_folder_roles) : {
          key      = "sa|${s}|folder:${pair[0]}|${pair[1]}"
          scope    = "folder"
          resource = module.folders.ids[pair[0]]
          role     = pair[1]
          member   = "serviceAccount:${local.stage_service_accounts[s]}"
        }
      ]
    ]),
  )
}

module "iam" {
  source = "../../modules/iam"

  bindings = local.iam_bindings
}
