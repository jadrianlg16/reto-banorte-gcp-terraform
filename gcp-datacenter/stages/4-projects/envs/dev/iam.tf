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
  # artifacts: el agente de Artifact Registry cifra el repositorio de imágenes (artifacts.tf).
  kms_consumers = {
    artifacts = ["artifactregistry"]
    backup    = ["gkebackup"]
    compute   = ["compute"]
    filestore = ["filestore"]
    gke       = ["gke", "compute"]
    redis     = ["redis"]
    run       = ["run"]
    sql       = ["sql"]
    storage   = ["storage"]
  }

  # Ubicaciones de kms_key_ids en las que se otorga cada uso: las regiones primaria y de DR
  # salvo storage (también la multirregión, bucket de doble región) y artifacts (solo la
  # ubicación del repositorio).
  kms_grant_locations = {
    for use in keys(local.kms_consumers) : use => (
      use == "artifacts" ? [var.artifact_registry_location] :
      use == "storage" ? keys(local.kms_key_ids) :
      local.regional_locations
    )
  }

  # Roles de la cuenta del pipeline de la etapa 5 en cada proyecto de servicio (no en la
  # carpeta del entorno, que también contiene el host de la Shared VPC). Uno por tipo de
  # recurso que crea la etapa 5:
  workloads_project_roles = [
    "roles/backupdr.admin",            # bóveda, planes y asociaciones de Backup and DR
    "roles/certificatemanager.editor", # certificado y autorizaciones DNS del balanceador interno
    "roles/cloudsql.admin",            # instancia, réplica, bases y usuarios IAM
    "roles/compute.instanceAdmin.v1",  # plantillas, MIG y autoescaladores
    "roles/compute.loadBalancerAdmin", # balanceadores, NEG, verificaciones de salud, IP y SSL
    "roles/compute.securityAdmin",     # políticas de Cloud Armor
    "roles/container.admin",           # clústeres y pools de GKE
    "roles/file.editor",               # Filestore
    "roles/gkebackup.admin",           # plan de Backup for GKE
    "roles/monitoring.editor",         # canales, alertas, uptime checks, tableros y SLO
    "roles/redis.admin",               # Memorystore
    "roles/run.admin",                 # servicios de Cloud Run y su IAM de invocador
    "roles/storage.admin",             # bucket de la aplicación
  ]

  # Lo único que la etapa 5 puede otorgar en el proyecto: el acceso a Cloud SQL por IAM de las
  # cuentas de ejecución (módulo cloud-sql). Misma forma de CEL que stages/1-org/iam.tf.
  workloads_iam_admin_condition = {
    title       = "solo-login-de-cloud-sql"
    description = "La etapa 5 solo puede otorgar roles/cloudsql.client y roles/cloudsql.instanceUser."
    expression  = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly(['roles/cloudsql.client', 'roles/cloudsql.instanceUser'])"
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

  # Apagado fuera de horario (ADR 0028). El nombre del rol se arma aquí (en el plan se conoce) y
  # module.iam espera al rol con depends_on.
  off_hours_role_id = "${var.prefix}OffHoursScheduler"

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
    # la usan la réplica, el plan de Backup for GKE y la conmutación con dr_active); para
    # Cloud Storage también en la multirregión (bucket de doble región) y para Artifact
    # Registry solo en la ubicación del repositorio.
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
          ] if contains(lookup(local.kms_grant_locations, use, []), location)
        ]
      ]
    ]),

    # Decisión de la ronda de correcciones: los permisos de la etapa 5 viven en cada proyecto
    # de servicio, no en la carpeta del entorno.
    flatten([
      for app in keys(var.applications) : [
        for role in local.workloads_project_roles : {
          key      = "workloads/${app}/${role}"
          scope    = "project"
          resource = module.project[app].project_id
          role     = role
          member   = local.workloads_member
        }
      ]
    ]),
    [
      for app in keys(var.applications) : {
        key       = "workloads/${app}/roles/resourcemanager.projectIamAdmin"
        scope     = "project"
        resource  = module.project[app].project_id
        role      = "roles/resourcemanager.projectIamAdmin"
        member    = local.workloads_member
        condition = local.workloads_iam_admin_condition
      }
    ],

    # Workload Identity: la etapa 5 enlaza la cuenta de Kubernetes con la cuenta workload
    # (iam.serviceAccounts.setIamPolicy) una vez que existe el clúster. Solo sobre esa cuenta.
    [
      for app in keys(var.applications) : {
        key      = "saadmin/${app}/workload"
        scope    = "service_account"
        resource = google_service_account.runtime["${app}/workload"].name
        role     = "roles/iam.serviceAccountAdmin"
        member   = local.workloads_member
      }
    ],

    # Host de la Shared VPC, sin networkUser de proyecto (el uso de subredes va por subred):
    # - Cloud Run con salida directa a la VPC: su agente necesita compute.networks.get en el
    #   host (Compute Network Viewer) además de networkUser en la subred ("Direct VPC egress
    #   with a Shared VPC network", opción 2).
    # - Pipeline de la etapa 5: Memorystore pide compute.networks.list en el proyecto local y en
    #   el host ("Memorystore for Redis networking"); Cloud SQL y Filestore leen la red del host
    #   para la IP privada por PSA.
    # VERIFICAR-EN-APPLY: que networkViewer en el host más networkUser por subred basten para
    # crear Cloud SQL, Memorystore y Filestore con IP privada (PSA) desde el proyecto de
    # servicio; si piden compute.networks.use, la alternativa documentada es networkUser en el
    # host (más amplio: todas las subredes) y se decide en revisión.
    [
      for app in keys(var.applications) : {
        key      = "host/${app}/run"
        scope    = "project"
        resource = local.host_project_id
        role     = "roles/compute.networkViewer"
        member   = local.service_agents[app]["run"]
      }
    ],
    [{
      key      = "host/workloads"
      scope    = "project"
      resource = local.host_project_id
      role     = "roles/compute.networkViewer"
      member   = local.workloads_member
    }],

    # Apagado fuera de horario (ADR 0028), solo con enable_off_hours_shutdown (nunca en prod):
    # - la cuenta del scheduler recibe el rol personalizado, y nada más, en su proyecto;
    # - la etapa 5 administra los trabajos de Cloud Scheduler del proyecto (no hay un rol
    #   predefinido más chico que cree y cambie trabajos) y adjunta esa cuenta a los trabajos
    #   (actAs solo sobre ella, no sobre el proyecto: el actAs de proyecto alcanzaría también a la
    #   cuenta de Compute por defecto y a las de ejecución).
    [
      for app in local.off_hours_apps : {
        key      = "offhours/${app}/scheduler"
        scope    = "project"
        resource = module.project[app].project_id
        role     = "projects/${module.project[app].project_id}/roles/${local.off_hours_role_id}"
        member   = google_service_account.scheduler[app].member
      }
    ],
    [
      for app in local.off_hours_apps : {
        key      = "offhours/${app}/workloads/roles/cloudscheduler.admin"
        scope    = "project"
        resource = module.project[app].project_id
        role     = "roles/cloudscheduler.admin"
        member   = local.workloads_member
      }
    ],
    [
      for app in local.off_hours_apps : {
        key      = "offhours/${app}/workloads/actas"
        scope    = "service_account"
        resource = google_service_account.scheduler[app].name
        role     = "roles/iam.serviceAccountUser"
        member   = local.workloads_member
      }
    ],

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

  # Los agentes de sqladmin, file, redis y gkebackup deben existir antes de recibir permisos, y
  # el rol personalizado del apagado antes de asignarse.
  depends_on = [google_project_service_identity.this, google_project_iam_custom_role.off_hours_scheduler]
}

# Rol personalizado de la cuenta del apagado fuera de horario (ADR 0028): exactamente los
# permisos de las tres llamadas que hacen sus trabajos, según las tablas de permisos de Cloud SQL
# y de GKE: instances.patch de Cloud SQL Admin (cloudsql.instances.get y .update) y
# nodePools.setAutoscaling y nodePools.setSize de GKE (container.clusters.update). Sin permisos
# de borrar, crear ni leer datos. La etapa 4 es dueña del proyecto de servicio (lo creó), así que
# puede crear el rol.
# VERIFICAR-EN-APPLY: que los tres permisos se admitan en roles personalizados y basten para las
# tres llamadas (gcloud scheduler jobs run de cada trabajo con respuesta 2xx), y que la cuenta de
# la etapa 4 pueda crear roles en el proyecto de servicio.
resource "google_project_iam_custom_role" "off_hours_scheduler" {
  for_each = local.off_hours_apps

  project     = module.project[each.key].project_id
  role_id     = local.off_hours_role_id
  title       = "Apagado fuera de horario"
  description = "Detener y encender Cloud SQL (activationPolicy) y cambiar autoescalado y tamaño de pools de GKE (ADR 0028). Sin crear, borrar ni leer datos."
  stage       = "GA"
  permissions = [
    "cloudsql.instances.get",
    "cloudsql.instances.update",
    "container.clusters.update",
  ]
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
