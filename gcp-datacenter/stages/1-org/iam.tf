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
      # KMS, contenedores de secretos (rol personalizado de la etapa 0, sin
      # secretmanager.versions.access: el pipeline no lee valores de secretos) y agente de
      # Secret Manager. Su projectIamAdmin va condicionado (stage_delegated_security_iam).
      projects = {
        security = [
          "roles/cloudkms.admin",
          local.secret_container_admin_role_id,
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
      # Proyectos de servicio, alta en Shared VPC y permisos de uso de subred. tagAdmin: dar
      # tagUser sobre los valores de las etiquetas seguras del spoke (las llaves viven en el
      # proyecto net-spoke, dentro de la carpeta del entorno).
      env_folder_roles = [
        "roles/compute.xpnAdmin",
        "roles/resourcemanager.projectCreator",
        "roles/resourcemanager.tagAdmin",
      ]
    }
    # 5-workloads no recibe nada aquí: sus roles van sobre cada proyecto de servicio y los da
    # 4-projects, que crea esos proyectos (las carpetas de entorno también contienen el host
    # net-spoke de 3-networks, y un rol de carpeta lo cubriría).
  }

  # Cuenta de etapa → roles/resourcemanager.projectIamAdmin en las carpetas de entorno, limitado
  # por condición a los roles que su etapa asigna sobre proyectos que no crea (concesión
  # delegada: solo puede agregar o quitar esos roles, nada más).
  # - 4-projects, en el host net-spoke (lo crea 3-networks): compute.networkUser y
  #   compute.networkViewer (identidades de los proyectos de servicio sobre la Shared VPC) y
  #   container.hostServiceAgentUser (agente de GKE).
  # VERIFICAR-EN-APPLY: que la condición con iam.googleapis.com/modifiedGrantsByRole se acepte
  # en una carpeta y se evalúe al cambiar el IAM de los proyectos de abajo.
  stage_delegated_project_iam = {
    "4-projects" = [
      "roles/compute.networkUser",
      "roles/compute.networkViewer",
      "roles/container.hostServiceAgentUser",
    ]
  }

  # 2-security en el proyecto security: projectIamAdmin limitado al único rol que asigna ahí
  # (el rol personalizado de 4-projects para el IAM de llaves y secretos). Sin la condición
  # podría darse secretAccessor a sí misma.
  # VERIFICAR-EN-APPLY: que hasOnly acepte el nombre completo de un rol personalizado de
  # organización (organizations/<n>/roles/<id>); la documentación no da ejemplo.
  stage_delegated_security_iam = {
    "2-security" = [local.kms_secret_iam_role_id]
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
    flatten([
      for s, roles in local.stage_delegated_project_iam : [
        for e in local.environments : {
          key      = "sa|${s}|folder:${e}|roles/resourcemanager.projectIamAdmin"
          scope    = "folder"
          resource = module.folders.ids[e]
          role     = "roles/resourcemanager.projectIamAdmin"
          member   = "serviceAccount:${local.stage_service_accounts[s]}"
          condition = {
            title       = "solo-${replace(s, "-", "")}-roles"
            description = "Solo asignar ${join(", ", roles)} (concesión delegada)."
            expression  = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([${join(", ", [for r in roles : "'${r}'"])}])"
          }
        }
      ]
    ]),
    [
      for s, roles in local.stage_delegated_security_iam : {
        key      = "sa|${s}|project:security|roles/resourcemanager.projectIamAdmin"
        scope    = "project"
        resource = module.common_project["security"].project_id
        role     = "roles/resourcemanager.projectIamAdmin"
        member   = "serviceAccount:${local.stage_service_accounts[s]}"
        condition = {
          title       = "solo-${replace(s, "-", "")}-roles"
          description = "Solo asignar ${join(", ", roles)} (concesión delegada)."
          expression  = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([${join(", ", [for r in roles : "'${r}'"])}])"
        }
      }
    ],
  )
}

module "iam" {
  source = "../../modules/iam"

  bindings = local.iam_bindings
}
