# Las nueve cuentas del pipeline (ADR 0029 §3), sus roles de PROYECTO, su acceso condicionado
# al bucket de estado y quién puede tomar su identidad por WIF.
#
# Todo sale de local.stage_roots, que codifica una sola vez la tabla del ADR 0029 §2 y la de
# estado de §3 (prefijo que escribe cada raíz y prefijos que lee), y de local.stage_roles, con
# los roles de cada cuenta. Los roles de proyecto se dan aquí y no en las raíces de entorno: un
# rol de proyecto para un principal compartido nunca se declara en una raíz de entorno (§4).
#
# Mínimo privilegio: que cada lista alcance para aplicar su raíz es HYPOTHESIS hasta el primer
# apply de cada raíz.
# VERIFICAR-EN-APPLY: que cada raíz aplique con su cuenta y estos roles; un permiso que falte
# se agrega aquí (con el rol predefinido más chico), nunca en la raíz.

locals {
  environments = ["dev", "qa", "prod"]

  # Entornos con apagado fuera de horario (ADR 0028: nunca prod).
  off_hours_environments = ["dev", "qa"]

  # Raíz → cuenta, entorno de GitHub que puede tomarla y prefijos de estado.
  # - writes: prefijos que la cuenta escribe (objectAdmin condicionado).
  # - reads: prefijos que además lee (objectViewer condicionado).
  # Las raíces de red no leen 1-base: no usan ninguna de sus salidas.
  stage_roots = merge(
    {
      "1-base" = {
        account_id         = "${var.prefix}-tf-base"
        github_environment = "common"
        writes             = ["1-base"]
        reads              = ["0-bootstrap"]
        description        = "Aplica 1-base: auditoría, avisos, llaves, secretos, imágenes, cuentas de ejecución de los entornos y controles únicos del proyecto (ADR 0029 §4)."
      }
      "2-networks" = {
        account_id         = "${var.prefix}-tf-net"
        github_environment = "common"
        writes             = ["2-networks/hub"]
        reads              = []
        description        = "Aplica el hub de 2-networks: VPC hub, onprem-sim, VPN y DNS (ADR 0029 §6)."
      }
    },
    {
      for e in local.environments : "2-networks/${e}" => {
        account_id         = "${var.prefix}-tf-net-${e}"
        github_environment = e
        writes             = ["2-networks/${e}"]
        reads              = ["2-networks/hub"]
        description        = "Aplica el spoke de ${e} de 2-networks (ADR 0029 §6)."
      }
    },
    {
      for e in local.environments : "3-workloads/${e}" => {
        account_id         = "${var.prefix}-tf-wl-${e}"
        github_environment = e
        writes             = ["3-workloads/${e}"]
        reads              = ["1-base", "2-networks/${e}"]
        description        = "Aplica 3-workloads de ${e}: cargas del entorno; las cuentas de ejecución las crea 1-base (ADR 0029 §2)."
      }
    },
  )

  # --- Condiciones de IAM ---------------------------------------------------------------------

  # KMS: todo salvo el llavero del estado (ADR 0008). El nombre de KMS en una condición lleva el
  # ID del proyecto (projects/<id>/locations/<l>/keyRings/<r>[/cryptoKeys/<k>]).
  kms_not_bootstrap = {
    title       = "kms-sin-llavero-del-estado"
    description = "Todo KMS del proyecto salvo el llavero del estado (0-bootstrap)."
    expression  = "!resource.name.startsWith(\"projects/${var.project_id}/locations/${local.state_kms_location}/keyRings/${var.prefix}-${local.environment}-\")"
  }

  # Buckets de un dominio de nombres: projects/_/buckets/<prefix>-<dominio>- (ADR 0029 §3).
  # VERIFICAR-EN-APPLY: que storage.buckets.create se evalúe con el nombre del bucket nuevo y la
  # condición lo admita; si se evalúa sobre el proyecto, agregar la cláusula
  # resource.type == "cloudresourcemanager.googleapis.com/Project" (pendiente nuevo).
  storage_prefix = {
    for d in concat(["common"], local.environments) : d => {
      title       = "buckets-${d}"
      description = "Solo los buckets <prefix>-${d}-."
      expression  = "resource.name.startsWith(\"projects/_/buckets/${var.prefix}-${d}-\")"
    }
  }

  # Recursos del entorno en los servicios que admiten resource.name en condiciones (hallazgo N1 de
  # la segunda revisión de seguridad). Solo Cloud SQL (Instance y BackupRun), GKE (Cluster) y
  # Backup and DR (BackupVaults) figuran en "Resource attributes for IAM Conditions"
  # (https://cloud.google.com/iam/docs/conditions-resource-attributes, actualizada el
  # 2026-11-17); Memorystore for Redis, Filestore, Backup for GKE y Cloud Monitoring no, así que
  # sus roles van sin condición (riesgo residual del ADR 0029 §9).
  #
  # Forma de la documentación de IAM para un rol con permisos de varios tipos ("Attribute
  # reference for IAM Conditions", atributo resource.type): la comprobación del nombre solo
  # aplica a los tipos que la admiten (resource.type != ... || nombre). Así los permisos que se
  # evalúan sobre el proyecto (crear un clúster, listar, operaciones) siguen permitidos y los que
  # se evalúan sobre un recurso de esos tipos quedan limitados a los del entorno.
  # Formatos del nombre (misma página): projects/<id>/instances/<instancia> (Cloud SQL, también
  # el prefijo de sus backupRuns), projects/<id>/locations/<ubicación>/clusters/<clúster> (GKE
  # regional) y projects/<id>/locations/<ubicación>/backupVaults/<bóveda>.
  # Nombres del entorno: instancias <prefix>-<env>-data-… (módulo cloud-sql), clústeres
  # <prefix>-<env>-<app>-gke[-dr] (ADR 0029 §4) y bóvedas <prefix>-<env>-bkp-vault-… (módulo
  # backup-dr), en primary_region o dr_region.
  #
  # Crear: la referencia de permisos de la API de GKE evalúa container.clusters.create sobre el
  # proyecto (https://cloud.google.com/kubernetes-engine/docs/reference/api-permissions), así
  # que la condición no limita el nombre de un clúster nuevo. Cloud SQL da como caso de uso
  # "crear instancias con un prefijo" (https://cloud.google.com/sql/docs/postgres/iam-conditions),
  # pero no dice cómo se evalúa al crear. La misma página dice que las condiciones no limitan
  # las operaciones de usuarios ni de bases de datos (cloudsql.users.*, cloudsql.databases.*).
  # VERIFICAR-EN-APPLY: que tf-wl-<env> cree y cambie su instancia de Cloud SQL (con réplica en
  # DR), sus bases y usuarios IAM, su clúster y sus pools de GKE, y su bóveda, plan y asociación
  # de Backup and DR con estas condiciones, y que tf-wl-dev reciba un rechazo al exportar o
  # parchear la instancia de prod, al cambiar el clúster de prod o al borrar la bóveda de prod.
  env_regions = [var.primary_region, var.dr_region]

  workloads_conditions = {
    for e in local.environments : e => {
      cloudsql = {
        title       = "cloudsql-${e}"
        description = "Instancias de Cloud SQL y sus respaldos: solo ${var.prefix}-${e}-data-."
        expression  = "(resource.type != \"sqladmin.googleapis.com/Instance\" && resource.type != \"sqladmin.googleapis.com/BackupRun\") || resource.name.startsWith(\"projects/${var.project_id}/instances/${var.prefix}-${e}-data-\")"
      }
      gke = {
        title       = "gke-${e}"
        description = "Clústeres de GKE: solo ${var.prefix}-${e}- en primary_region o dr_region."
        expression = join(" || ", concat(
          ["resource.type != \"container.googleapis.com/Cluster\""],
          [for r in local.env_regions : "resource.name.startsWith(\"projects/${var.project_id}/locations/${r}/clusters/${var.prefix}-${e}-\")"],
        ))
      }
      backupdr = {
        title       = "backupdr-${e}"
        description = "Bóvedas de Backup and DR: solo ${var.prefix}-${e}- en primary_region o dr_region."
        expression = join(" || ", concat(
          ["resource.type != \"backupdr.googleapis.com/BackupVaults\""],
          [for r in local.env_regions : "resource.name.startsWith(\"projects/${var.project_id}/locations/${r}/backupVaults/${var.prefix}-${e}-\")"],
        ))
      }
    }
  }

  # Concesión delegada (mismo patrón que la antigua 4-projects/iam.tf): projectIamAdmin que solo
  # puede agregar o quitar estos roles. Una llamada sin cambios de bindings (por ejemplo, la
  # configuración de auditoría) tiene modifiedGrantsByRole = [] y pasa. Solo la tiene 1-base: las
  # cuentas de los entornos ya no asignan roles de proyecto (las cuentas de ejecución y sus
  # roles están en 1-base).
  # VERIFICAR-EN-APPLY: que la condición con iam.googleapis.com/modifiedGrantsByRole se acepte en
  # el proyecto, que permita la configuración de auditoría de 1-base y que niegue otro rol.
  #
  # La documentación limita hasPermission/hasOnly a 10 roles por lista ("Set limits on granting
  # roles", https://cloud.google.com/iam/docs/setting-limits-on-granting-roles): por eso hay dos
  # asignaciones condicionadas de projectIamAdmin, una por lista, y no una con ||. Cada
  # google_project_iam_member cambia un solo rol por llamada, así que cada llamada cae en una de
  # las dos.
  #
  # Personas: IAM de solo lectura de los grupos (ADR 0029 §4). La lista debe coincidir con la de
  # stages/1-base/iam.tf. Sin tagUser: con él, la cuenta de 1-base podría dárselo a sí misma y
  # quitar la etiqueta de protección (el de los agentes lo da main.tf).
  base_grantable_roles = [
    "roles/cloudkms.viewer",
    "roles/iam.securityReviewer",
    "roles/logging.privateLogViewer",
    "roles/logging.viewer",
    "roles/monitoring.viewer",
    "roles/viewer",
  ]

  # Cuentas de ejecución (stages/1-base/runtime_accounts.tf): telemetría, Cloud SQL por IAM y el
  # rol del apagado. La lista debe coincidir con la de ese archivo.
  runtime_grantable_roles = [
    "roles/autoscaling.metricsWriter",
    "roles/cloudsql.client",
    "roles/cloudsql.instanceUser",
    "roles/cloudtrace.agent",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    local.custom_role_ids["off_hours_scheduler"],
  ]

  delegated_iam = {
    people = {
      title       = "solo-iam-de-lectura"
      description = "Solo asignar los roles de lectura de los grupos de personas (1-base, concesión delegada)."
      expression  = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([${join(", ", [for r in local.base_grantable_roles : "'${r}'"])}])"
    }
    runtime = {
      title       = "solo-roles-de-ejecucion"
      description = "Solo asignar los roles de las cuentas de ejecución, Cloud SQL por IAM y el apagado (1-base, concesión delegada)."
      expression  = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([${join(", ", [for r in local.runtime_grantable_roles : "'${r}'"])}])"
    }
  }

  # --- Roles de proyecto por raíz -------------------------------------------------------------
  # { role, condition } con condition null cuando el servicio no admite condiciones por nombre
  # (ADR 0029 §3: una condición sobre un tipo que no la admite niega todo). key solo cuando una
  # cuenta tiene el mismo rol dos veces (con condiciones distintas).

  base_roles = [
    { role = "roles/cloudkms.admin", condition = local.kms_not_bootstrap },       # llaveros y llaves de 1-base y sus permisos a agentes
    { role = local.custom_role_ids["secret_container_admin"], condition = null }, # contenedores de secretos sin valores y su IAM
    { role = "roles/artifactregistry.admin", condition = null },                  # repositorios y su IAM por repositorio
    { role = "roles/binaryauthorization.policyEditor", condition = null },        # la política única
    { role = "roles/logging.configWriter", condition = null },                    # sink, exclusiones y métricas de audit-alerts
    { role = "roles/monitoring.alertPolicyEditor", condition = null },            # alertas de audit-alerts
    { role = "roles/monitoring.notificationChannelEditor", condition = null },    # canales de avisos
    { role = "roles/essentialcontacts.admin", condition = null },                 # contactos esenciales (CIS 1.17)
    { role = "roles/pubsub.admin", condition = null },                            # tema de hallazgos de SCC
    { role = "roles/securitycenter.notificationConfigEditor", condition = null }, # notificación de SCC
    { role = "roles/storage.admin", condition = local.storage_prefix["common"] }, # bucket de logs
    # Cuentas de ejecución de los entornos: crearlas y administrar su IAM, sin etiquetas
    # (custom_roles.tf). Las cuentas de servicio no admiten condiciones por nombre
    # (HYPOTHESIS): va sin condición, y la etiqueta de protección y la denegación cubren a las
    # cuentas del pipeline.
    { role = local.custom_role_ids["service_account_manager"], condition = null },
    # Concesión delegada: auditoría e IAM de personas, y roles de las cuentas de ejecución.
    {
      key       = "project|1-base|roles/resourcemanager.projectIamAdmin|personas"
      role      = "roles/resourcemanager.projectIamAdmin"
      condition = local.delegated_iam.people
    },
    {
      key       = "project|1-base|roles/resourcemanager.projectIamAdmin|ejecucion"
      role      = "roles/resourcemanager.projectIamAdmin"
      condition = local.delegated_iam.runtime
    },
  ]

  # Hub y spokes de red. HYPOTHESIS de mínimo privilegio (pedido del bloque de redes).
  # VERIFICAR-EN-APPLY: que el hub (VPN, DNS, onprem-sim) y cada spoke (PSA, etiquetas seguras,
  # política de firewall de red) apliquen con estos roles.
  net_roles = [
    { role = "roles/compute.networkAdmin", condition = null },
    { role = "roles/compute.securityAdmin", condition = null },
    { role = "roles/dns.admin", condition = null },
  ]
  # Solo el hub, y solo con onprem_dns_vm = true: la VM DNS de onprem-sim
  # (stages/2-networks/onprem_dns.tf). Sin condición, como compute.instanceAdmin.v1 de las cuentas
  # de cargas: una condición por nombre sobre los tipos de Compute que crear una VM consulta y que
  # no la admiten negaría todo (ADR 0029 §3). Riesgo aceptado mientras la opción esté activa: el
  # hub podría cambiar o borrar las VM de los entornos. La cuenta de la VM la crea 1-base, que le
  # da a esta cuenta serviceAccountUser solo sobre ella (stages/1-base/onprem_dns.tf).
  # VERIFICAR-EN-APPLY: que el hub cree la VM DNS con este rol más networkAdmin (subred y dirección
  # interna) y serviceAccountUser sobre su cuenta, y sin él no.
  hub_roles = concat(local.net_roles, var.onprem_dns_vm ? [
    { role = "roles/compute.instanceAdmin.v1", condition = null },
  ] : [])
  net_env_roles = concat(local.net_roles, [
    # Etiquetas seguras del spoke y su IAM (tagUser de tf-wl-<env> sobre sus valores), sin
    # ligarlas a recursos ni retenerlas (custom_roles.tf).
    { role = local.custom_role_ids["network_tag_manager"], condition = null },
    { role = "roles/servicenetworking.networksAdmin", condition = null }, # conexión de PSA
  ])

  # Cargas (las que tenía la cuenta de la etapa 5). Cloud SQL, GKE y Backup and DR van
  # condicionados a los recursos del entorno (local.workloads_conditions) y Cloud Storage a sus
  # buckets. Compute, Cloud Run, Memorystore, Filestore, Backup for GKE, Certificate Manager y
  # Monitoring van sin condición: no admiten resource.name, o su rol abarca tipos que no lo
  # admiten (riesgo aceptado del ADR 0029 §3 y §9). Sin roles de cuentas de servicio ni de IAM de
  # proyecto: las cuentas de ejecución las crea 1-base, que le da a esta cuenta serviceAccountUser
  # solo sobre las de su entorno (stages/1-base/runtime_accounts.tf).
  #
  # GKE con container.clusterAdmin y no container.admin (hallazgo N1): clusterAdmin administra
  # clústeres y pools (container.clusters.create, get, list, update y delete, y
  # container.operations.*; los pools se crean y borran con container.clusters.update según la
  # referencia de permisos de la API de GKE) sin permisos sobre objetos de Kubernetes. container.admin
  # trae container.pods.create, pods.exec, secrets.get y serviceAccounts.createToken en todos
  # los clústeres del proyecto: con ellos una cuenta de dev leería los Secrets o tomaría la
  # identidad de los pods de prod. 3-workloads no usa el proveedor kubernetes. Backup for GKE
  # tiene su propio rol (gkebackup.admin).
  #
  # Monitoring con roles finos y no monitoring.editor (hallazgo N2): monitoring.editor trae
  # serviceusage.services.enable y serviceusage.consumerpolicy.update. El módulo observability
  # crea canales de correo (notificationChannelEditor), verificaciones de disponibilidad
  # (uptimeCheckConfigEditor), alertas (alertPolicyEditor), el servicio y el SLO
  # (servicesEditor) y el tablero (dashboardEditor). Ninguno de los cinco trae serviceusage.*;
  # sus únicos *TagBinding son de alertas y tableros (referencia de roles de Monitoring,
  # actualizada el 2026-11-17). VERIFICAR-EN-APPLY: que observability aplique con estos cinco
  # roles (alertas que citan canales y el SLO, y el tablero).
  workloads_roles = {
    for e in local.environments : e => concat([
      { role = "roles/backupdr.admin", condition = local.workloads_conditions[e].backupdr },    # bóveda, planes y asociaciones
      { role = "roles/certificatemanager.editor", condition = null },                           # certificados y autorizaciones DNS
      { role = "roles/cloudsql.admin", condition = local.workloads_conditions[e].cloudsql },    # instancias, réplicas, bases y usuarios IAM
      { role = "roles/compute.instanceAdmin.v1", condition = null },                            # plantillas, MIG y autoescaladores
      { role = "roles/compute.loadBalancerAdmin", condition = null },                           # balanceadores, NEG, IP y SSL
      { role = "roles/compute.securityAdmin", condition = null },                               # Cloud Armor
      { role = "roles/compute.networkUser", condition = null },                                 # subredes del spoke
      { role = "roles/container.clusterAdmin", condition = local.workloads_conditions[e].gke }, # clústeres y pools de GKE
      { role = "roles/file.editor", condition = null },                                         # Filestore
      { role = "roles/gkebackup.admin", condition = null },                                     # Backup for GKE
      { role = "roles/monitoring.alertPolicyEditor", condition = null },                        # alertas
      { role = "roles/monitoring.dashboardEditor", condition = null },                          # tablero
      { role = "roles/monitoring.notificationChannelEditor", condition = null },                # canales de correo
      { role = "roles/monitoring.servicesEditor", condition = null },                           # servicio y SLO
      { role = "roles/monitoring.uptimeCheckConfigEditor", condition = null },                  # verificaciones de disponibilidad
      { role = "roles/redis.admin", condition = null },                                         # Memorystore
      { role = "roles/run.admin", condition = null },                                           # Cloud Run y su IAM de invocador
      { role = "roles/storage.admin", condition = local.storage_prefix[e] },
      # Sin tagUser de proyecto: lo trae con iam.serviceAccounts.deleteTagBinding, que la
      # denegación no puede negar (hallazgo 1). El spoke del entorno le da tagUser solo sobre sus
      # valores lb_backend e iap_ssh (stages/2-networks/envs/<env>/firewall.tf).
      ],
      contains(local.off_hours_environments, e) ? [{ role = "roles/cloudscheduler.admin", condition = null }] : [],
    )
  }

  stage_roles = merge(
    { "1-base" = local.base_roles, "2-networks" = local.hub_roles },
    { for e in local.environments : "2-networks/${e}" => local.net_env_roles },
    { for e in local.environments : "3-workloads/${e}" => local.workloads_roles[e] },
  )

  # Solo lectura (ADR 0029 §3): plan de pr.yml y apply.yml, drift.yml, prueba de humo y huérfanos.
  # VERIFICAR-EN-APPLY: que roles/viewer alcance para refrescar todos los recursos de las raíces
  # (plan con -lock=false) y networkmanagement.admin para las Connectivity Tests.
  read_roles = [
    "roles/viewer",
    "roles/iam.securityReviewer",
    "roles/cloudasset.viewer",
    "roles/networkmanagement.admin",
  ]

  # --- Estado (§6.2) ----------------------------------------------------------------------------

  state_bucket_resource = "projects/_/buckets/${local.state_bucket_name}"

  # storage.objects.list se evalúa sobre el bucket, no sobre un objeto: cada condición empieza
  # con el tipo Bucket para que el backend pueda listar. Consecuencia aceptada: toda cuenta ve
  # los nombres de los objetos del bucket, no su contenido.
  state_list_clause = "resource.type == \"storage.googleapis.com/Bucket\""

  # La barra final da coincidencia exacta de prefijo: "2-networks/hub/" no coincide con
  # "2-networks/hub2/".
  state_prefix_clause = {
    for p in distinct(flatten([for r in values(local.stage_roots) : concat(r.writes, r.reads)])) :
    p => "resource.name.startsWith(\"${local.state_bucket_resource}/objects/${p}/\")"
  }

  # VERIFICAR-EN-APPLY (pendiente 1): que init/plan/apply del backend gcs funcionen con estas
  # condiciones.
  state_admin_expression = {
    for k, r in local.stage_roots : k => join(" || ", concat(
      [local.state_list_clause],
      [for p in r.writes : local.state_prefix_clause[p]],
    ))
  }
  state_viewer_expression = {
    for k, r in local.stage_roots : k => join(" || ", concat(
      [local.state_list_clause],
      [for p in r.reads : local.state_prefix_clause[p]],
    ))
  }

  # --- Principales de WIF (ADR 0029 §3) -----------------------------------------------------------
  # El proveedor solo acepta tokens del repositorio autorizado (attribute_condition por IDs
  # numéricos, wif.tf). Dentro de él: las cuentas de 1-base y del hub solo con attribute.deploy
  # common, las de entorno solo con su entorno (un trabajo de main, de un flujo de este
  # repositorio y con ese entorno de GitHub; local.wif_deploy en wif.tf) y tf-read con cualquier
  # trabajo.
  wif_pool_name = google_iam_workload_identity_pool.github.name
  wif_environment_principal = {
    for env in distinct([for r in values(local.stage_roots) : r.github_environment]) :
    env => "principalSet://iam.googleapis.com/${local.wif_pool_name}/attribute.deploy/${env}"
  }
  wif_repository_principal = "principalSet://iam.googleapis.com/${local.wif_pool_name}/attribute.repository_id/${var.github_repository_id}"

  # --- Asignaciones (llaves fijas: miembros y algunos recursos solo se conocen tras el apply) ---

  stage_bindings = concat(
    flatten([
      for k, roles in local.stage_roles : [
        for r in roles : {
          key       = try(r.key, "project|${k}|${r.role}")
          scope     = "project"
          resource  = var.project_id
          role      = r.role
          member    = google_service_account.stage[k].member
          condition = r.condition
        }
      ]
    ]),
    [
      # Proyecto de cuota de las llamadas (billing_project con user_project_override).
      for k in keys(local.stage_roots) : {
        key       = "project|${k}|roles/serviceusage.serviceUsageConsumer"
        scope     = "project"
        resource  = var.project_id
        role      = "roles/serviceusage.serviceUsageConsumer"
        member    = google_service_account.stage[k].member
        condition = null
      }
    ],
    [
      for k in keys(local.stage_roots) : {
        key      = "state|${k}|roles/storage.objectAdmin"
        scope    = "storage_bucket"
        resource = google_storage_bucket.state.name
        role     = "roles/storage.objectAdmin"
        member   = google_service_account.stage[k].member
        condition = {
          title       = "tfstate-${replace(k, "/", "-")}-escritura"
          description = "Solo los objetos del prefijo de estado de ${k}."
          expression  = local.state_admin_expression[k]
        }
      }
    ],
    [
      for k, r in local.stage_roots : {
        key      = "state|${k}|roles/storage.objectViewer"
        scope    = "storage_bucket"
        resource = google_storage_bucket.state.name
        role     = "roles/storage.objectViewer"
        member   = google_service_account.stage[k].member
        condition = {
          title       = "tfstate-${replace(k, "/", "-")}-lectura"
          description = "Listado del bucket y lectura de los prefijos que ${k} lee."
          expression  = local.state_viewer_expression[k]
        }
      } if length(r.reads) > 0
    ],
    [
      for k, r in local.stage_roots : {
        key       = "wif|${k}|roles/iam.workloadIdentityUser"
        scope     = "service_account"
        resource  = google_service_account.stage[k].name
        role      = "roles/iam.workloadIdentityUser"
        member    = local.wif_environment_principal[r.github_environment]
        condition = null
      }
    ],
    # Cuenta de solo lectura.
    [
      for r in concat(local.read_roles, ["roles/serviceusage.serviceUsageConsumer"]) : {
        key       = "project|read|${r}"
        scope     = "project"
        resource  = var.project_id
        role      = r
        member    = google_service_account.read.member
        condition = null
      }
    ],
    [
      {
        key       = "state|read|roles/storage.objectViewer"
        scope     = "storage_bucket"
        resource  = google_storage_bucket.state.name
        role      = "roles/storage.objectViewer"
        member    = google_service_account.read.member
        condition = null
      },
      {
        key       = "wif|read|roles/iam.workloadIdentityUser"
        scope     = "service_account"
        resource  = google_service_account.read.name
        role      = "roles/iam.workloadIdentityUser"
        member    = local.wif_repository_principal
        condition = null
      },
    ],
    # Ningún rol de organización ni de la política de acceso: las políticas de organización y el
    # perímetro de VPC-SC los aplica la persona de esta etapa (org.tf).
  )
}

resource "google_service_account" "stage" {
  for_each = local.stage_roots

  project      = var.project_id
  account_id   = each.value.account_id
  display_name = "Terraform ${each.key}"
  description  = each.value.description

  depends_on = [google_project_service.this]
}

resource "google_service_account" "read" {
  project      = var.project_id
  account_id   = "${var.prefix}-tf-read"
  display_name = "Terraform lectura"
  description  = "Solo lectura: plan de pr.yml y apply.yml, drift.yml, prueba de humo y búsqueda de huérfanos (ADR 0029 §3)."

  depends_on = [google_project_service.this]
}

module "stage_iam" {
  source = "../../modules/iam"

  bindings = local.stage_bindings

  # Los roles personalizados deben existir antes de asignarse (su ID se arma en el plan).
  depends_on = [google_project_iam_custom_role.this]
}
