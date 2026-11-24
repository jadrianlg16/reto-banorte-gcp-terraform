# Lecturas de etapas anteriores (ADR 0029 §2, fila 3-workloads/envs/<env>): solo 1-base y
# 2-networks/<env>. Los nombres y tipos son los de la tabla "Interfaces entre etapas" del ADR.

data "terraform_remote_state" "base" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "1-base"
  }

  lifecycle {
    postcondition {
      condition     = can(self.outputs.kms_key_ids[var.environment])
      error_message = "El estado de 1-base no tiene kms_key_ids[environment] (llaves del entorno)."
    }
    postcondition {
      condition     = alltrue([for s in var.application_secrets : can(self.outputs.secret_ids[var.environment][s])])
      error_message = "Algún secreto de application_secrets no existe en secret_ids[environment] del estado de 1-base."
    }
    postcondition {
      condition     = can(self.outputs.artifact_registry_repositories[var.environment][var.application])
      error_message = "El estado de 1-base no tiene artifact_registry_repositories[environment][application]: 1-base crea el repositorio de imágenes de cada entorno y aplicación."
    }
    postcondition {
      condition     = !var.off_hours_shutdown.enabled || try(self.outputs.off_hours_role_id, null) != null
      error_message = "off_hours_shutdown.enabled exige la salida off_hours_role_id de 1-base (rol personalizado del apagado fuera de horario, ADR 0028)."
    }
  }
}

data "terraform_remote_state" "network" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "2-networks/${var.environment}"
  }

  lifecycle {
    # Sin Shared VPC (ADR 0029 §6) la VPC del spoke está en el mismo proyecto que las cargas: si
    # no, el estado o las variables apuntan a otro proyecto.
    postcondition {
      condition     = strcontains(self.outputs.network_self_link, "projects/${var.project_id}/")
      error_message = "La VPC del estado de 2-networks/<environment> no está en project_id: el bucket de estado o project_id apuntan a otro proyecto."
    }
    # El plano de control de GKE usa el /28 que reserva el spoke (un solo dato para la regla de
    # firewall del spoke y el clúster).
    postcondition {
      condition = !var.enable_gke || alltrue([
        for k in(var.dr_active ? ["gke_master", "gke_master_dr"] : ["gke_master"]) :
        can(cidrhost(self.outputs.reserved_cidrs[k], 0)) && endswith(self.outputs.reserved_cidrs[k], "/28")
      ])
      error_message = "Con enable_gke, el estado de 2-networks/<environment> debe publicar reserved_cidrs[\"gke_master\"] (y gke_master_dr con dr_active) como /28: el spoke los reserva con su subnet_cidrs (y enable_dr)."
    }
    # Los puertos de los backends deben estar abiertos en la regla de firewall del spoke para el
    # balanceador (lb_backend_ports del spoke). Si el spoke no publica la salida, no se comprueba.
    postcondition {
      condition = try(self.outputs.lb_backend_ports, null) == null || alltrue([
        for port in local.backend_ports : anytrue([
          for entry in(try(self.outputs.lb_backend_ports, null) == null ? [] : self.outputs.lb_backend_ports) : (
            length(split("-", entry)) == 1
            ? tonumber(entry) == port
            : tonumber(split("-", entry)[0]) <= port && port <= tonumber(split("-", entry)[1])
          )
        ])
      ])
      error_message = "Algún puerto de backend (mig_http_port con enable_mig) no está en lb_backend_ports del spoke: el firewall bloquearía al balanceador y a sus verificaciones de salud."
    }
  }
}

locals {
  base = data.terraform_remote_state.base.outputs

  # 1-base: kms_key_ids (ADR 0029, map(map(string)) entorno → uso → ID). Las llaves de una misma
  # función en otra ubicación (región de DR, multirregión) se distinguen por la ubicación de su
  # ID; el uso es la primera palabra de la llave (sql, sql_dr y sql-use4 son el uso sql). Se
  # acepta también la forma de la etapa 2 anterior ([entorno][ubicación][uso]). Resultado:
  # local.kms_key_ids[ubicación][uso] → ID, que es lo que piden los módulos.
  kms_key_entries = flatten([
    for k, v in local.base.kms_key_ids[var.environment] : try(
      [for use, id in v : { use = use, id = id }],
      [{ use = regex("^[a-z0-9]+", k), id = tostring(v) }],
    )
  ])
  kms_key_located = [
    for e in local.kms_key_entries : merge(e, { location = try(regex("/locations/([^/]+)/keyRings/", e.id)[0], "") })
  ]
  kms_key_groups = {
    for loc in distinct([for e in local.kms_key_located : e.location]) : loc => {
      for e in local.kms_key_located : e.use => e.id... if e.location == loc
    }
  }
  kms_key_ids = {
    for loc, uses in local.kms_key_groups : loc => { for use, ids in uses : use => ids[0] }
  }

  # 1-base: secret_ids (map(map(string)) entorno → secreto → ID).
  secret_ids = lookup(local.base.secret_ids, var.environment, {})

  # 1-base: artifact_registry_repositories[entorno][aplicación], la URL Docker del repositorio
  # (<ubicación>-docker.pkg.dev/<proyecto>/<repositorio>, como la etapa 4 anterior). Se acepta
  # también un objeto { id, url } o su JSON.
  artifact_repository_raw = local.base.artifact_registry_repositories[var.environment][var.application]
  artifact_repository_url = try(
    local.artifact_repository_raw.url,
    jsondecode(local.artifact_repository_raw).url,
    tostring(local.artifact_repository_raw),
  )
  artifact_repository_parts = try(regex("^([a-z0-9-]+)-docker\\.pkg\\.dev/([a-z][a-z0-9-]{4,28}[a-z0-9])/([a-z][a-z0-9-]*[a-z0-9])$", local.artifact_repository_url), null)
  artifact_repository = local.artifact_repository_parts == null ? null : {
    location   = local.artifact_repository_parts[0]
    project    = local.artifact_repository_parts[1]
    repository = local.artifact_repository_parts[2]
  }

  # 1-base: off_hours_role_id (rol personalizado del apagado, ADR 0028). Se acepta el ID
  # completo (projects/<p>/roles/<rol>) o solo el nombre del rol.
  off_hours_role_raw = try(local.base.off_hours_role_id, null)
  off_hours_role_id = local.off_hours_role_raw == null ? null : (
    startswith(local.off_hours_role_raw, "projects/") ? local.off_hours_role_raw : "projects/${var.project_id}/roles/${local.off_hours_role_raw}"
  )

  # 1-base: notification_channel_ids (map(string)): canales que ya existen y reciben también las
  # alertas del entorno (operations.tf).
  base_notification_channel_ids = sort(distinct(compact(try(values(local.base.notification_channel_ids), []))))

  # 2-networks/<env>: VPC del spoke en el proyecto único (sin host_project_id).
  network_self_link = data.terraform_remote_state.network.outputs.network_self_link
  subnets           = data.terraform_remote_state.network.outputs.subnets
  psa_range_name    = data.terraform_remote_state.network.outputs.psa_range_name
  secure_tags       = data.terraform_remote_state.network.outputs.secure_tags
  secure_tag_keys   = data.terraform_remote_state.network.outputs.secure_tag_keys
  # reserved_cidrs: map(string), llaves gke_master y (con enable_dr del spoke) gke_master_dr.
  reserved_cidrs = data.terraform_remote_state.network.outputs.reserved_cidrs

  # Puertos en los que sirven los backends con grupo de instancias (Cloud Run es un NEG sin
  # servidor, sin firewall; el puerto de los NEG de GKE lo fija el Service de Kubernetes, fuera
  # de Terraform).
  backend_ports = var.enable_mig ? [var.mig_http_port] : []
}
