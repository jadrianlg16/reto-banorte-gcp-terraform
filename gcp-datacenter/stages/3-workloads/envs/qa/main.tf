# Etapa 3-workloads (ADR 0029 §2): cuentas de ejecución y cargas de trabajo de un entorno en el
# proyecto único (project_id), sobre la VPC del spoke del entorno (2-networks/<env>), sin
# proyectos de servicio ni Shared VPC. Los recursos están repartidos por tema:
#   service_accounts.tf  cuentas de ejecución y del apagado, y sus permisos
#   compute.tf           GKE, MIG y Cloud Run (por región activa)
#   data.tf              Cloud SQL, Memorystore, Filestore y Cloud Storage
#   load_balancing.tf    Cloud Armor, balanceador HTTPS externo y balanceador interno
#   operations.tf        observabilidad y respaldo
#   off_hours.tf         apagado fuera de horario de dev y qa (ADR 0028)
# Lo que existe una vez por proyecto (APIs, Binary Authorization, repositorios de imágenes,
# llaves y secretos, el rol del apagado, permisos de agentes de servicio, auditoría) lo crea
# 1-base; esta raíz no lo declara (ADR 0029 §4). Todo nombre empieza con <prefix>-<env>-.
# Este archivo tiene los valores comunes y las comprobaciones de las salidas de otras etapas.

locals {
  # §4.3 tal cual (var.labels valida app = application, owner y cost_center).
  labels = merge(var.labels, {
    env        = var.environment
    managed_by = "terraform"
  })

  regions = {
    primary = var.primary_region
    dr      = var.dr_region
  }

  # Regiones con cómputo. Con dr_active (conmutación) se agrega la de DR; la primaria se queda
  # para no destruir sus recursos durante el incidente y para volver sin recrearlos. Las llaves
  # son estables (primary, dr): el interruptor agrega instancias, no las renombra.
  compute_regions = var.dr_active ? local.regions : { primary = var.primary_region }

  # Región cuyos backends atiende el tráfico de los balanceadores.
  active_key    = var.dr_active ? "dr" : "primary"
  active_region = local.regions[local.active_key]

  # Llaves de §5 por región (gke_master* son llaves de reserved_cidrs del spoke).
  subnet_keys = {
    primary = { app = "app", run = "run", proxy = "proxy", gke_master = "gke_master" }
    dr      = { app = "app_dr", run = "run_dr", proxy = "proxy_dr", gke_master = "gke_master_dr" }
  }

  # Rangos secundarios de las subredes app/app_dr: el spoke los nombra con las mismas llaves de
  # secondary_ranges.
  pods_range_name     = "pods"
  services_range_name = "services"

  # Nombres de los clústeres por convención (ADR 0029 §4): 1-base los usa en la regla por
  # clúster de Binary Authorization antes de que existan.
  gke_cluster_names = {
    primary = "${var.prefix}-${var.environment}-${var.application}-gke"
    dr      = "${var.prefix}-${var.environment}-${var.application}-gke-dr"
  }

  # Namespace de la cuenta de Kubernetes de Workload Identity (ADR 0029 §9): <app>-<env> por
  # defecto; la variable valida que termine en -<env>.
  gke_workload_namespace = coalesce(var.gke_workload_namespace, "${var.application}-${var.environment}")

  # Etiquetas seguras del spoke: llave tagKeys/… → valor tagValues/… (ver resource_manager_tags).
  # El tagUser sobre los valores no se declara aquí: se lo da 0-bootstrap a tf-wl-<env>.
  # VERIFICAR-EN-APPLY: que con el tagUser de tf-wl-<env> basten para crear la plantilla del MIG
  # y los pools de GKE con estas etiquetas, o si el agente de GKE y <número>@cloudservices también
  # necesitan tagUser sobre los valores (antes se lo daba la etapa 4).
  mig_secure_tags = {
    for k in ["lb_backend", "iap_ssh"] : local.secure_tag_keys[k] => local.secure_tags[k]
  }
  gke_node_secure_tags = {
    (local.secure_tag_keys["lb_backend"]) = local.secure_tags["lb_backend"]
  }

  # Llaves KMS que la configuración va a pedir: [ubicación][uso].
  required_kms = concat(
    [for r in values(local.compute_regions) : [r, "gke"] if var.enable_gke],
    [for r in values(local.compute_regions) : [r, "compute"] if var.enable_mig],
    [for r in values(local.compute_regions) : [r, "run"] if var.enable_cloud_run],
    [[var.primary_region, "sql"]],
    var.enable_dr ? [[var.dr_region, "sql"], [var.multi_region, "storage"]] : [[var.primary_region, "storage"]],
    var.enable_memorystore ? [[var.primary_region, "redis"]] : [],
    var.enable_filestore ? [[var.primary_region, "filestore"]] : [],
    var.enable_gke && var.enable_dr && var.enable_backup ? [[var.dr_region, "backup"]] : [],
  )

  # Subredes que la configuración va a pedir (la proxy-only de cada región con balanceador
  # interno no se referencia, pero el balanceador no funciona sin ella).
  required_subnets = distinct(concat(
    [for k in keys(local.compute_regions) : local.subnet_keys[k].app if var.enable_gke || var.enable_mig || var.enable_internal_lb],
    [for k in keys(local.compute_regions) : local.subnet_keys[k].run if var.enable_cloud_run],
    [for k in keys(local.compute_regions) : local.subnet_keys[k].proxy if var.enable_internal_lb],
  ))
}

# Comprobaciones de las salidas leídas de otras etapas: fallan en el plan con un mensaje claro en
# lugar de un error de índice dentro de un módulo.
resource "terraform_data" "upstream_checks" {
  input = {
    environment = var.environment
    application = var.application
  }

  lifecycle {
    precondition {
      condition     = alltrue([for p in local.required_kms : contains(keys(lookup(local.kms_key_ids, p[0], {})), p[1])])
      error_message = "Falta en kms_key_ids[environment] de 1-base alguna llave [ubicación][uso] que esta configuración necesita (la ubicación sale del ID de la llave)."
    }
    precondition {
      condition = alltrue(flatten([
        for loc, uses in local.kms_key_groups : [for use, ids in uses : length(distinct(ids)) == 1]
      ]))
      error_message = "kms_key_ids[environment] de 1-base tiene dos llaves distintas para el mismo uso en la misma ubicación: no se sabe cuál usar."
    }
    precondition {
      condition     = local.artifact_repository != null
      error_message = "artifact_registry_repositories[environment][application] de 1-base debe ser la URL <ubicación>-docker.pkg.dev/<proyecto>/<repositorio>."
    }
    precondition {
      condition     = try(local.artifact_repository.project, var.project_id) == var.project_id
      error_message = "El repositorio de imágenes de 1-base está en otro proyecto: todo vive en project_id (ADR 0029)."
    }
    precondition {
      condition     = alltrue([for s in local.required_subnets : contains(keys(local.subnets), s)])
      error_message = "Falta en subnets del spoke alguna subred necesaria (app, run, proxy con enable_internal_lb y, con dr_active, sus versiones _dr: el spoke debe tener enable_dr = true)."
    }
    precondition {
      condition = !var.enable_gke || alltrue([
        for k in keys(local.compute_regions) : alltrue([
          for r in [local.pods_range_name, local.services_range_name] : contains(keys(local.subnets[local.subnet_keys[k].app].secondary_ranges), r)
        ])
      ])
      error_message = "La subred app (y app_dr con dr_active) del spoke debe tener los rangos secundarios pods y services."
    }
    precondition {
      condition     = alltrue([for k in ["lb_backend", "iap_ssh"] : contains(keys(local.secure_tags), k) && contains(keys(local.secure_tag_keys), k)])
      error_message = "El spoke de 2-networks debe publicar secure_tags y secure_tag_keys con las llaves lb_backend e iap_ssh."
    }
    precondition {
      condition     = !var.enable_internal_lb || var.enable_mig || var.enable_cloud_run
      error_message = "enable_internal_lb exige enable_mig o enable_cloud_run: el balanceador interno necesita al menos un backend."
    }
  }
}
