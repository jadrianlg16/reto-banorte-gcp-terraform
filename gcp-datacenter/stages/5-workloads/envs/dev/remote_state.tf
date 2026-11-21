# Lecturas de etapas anteriores (§6.1, fila 5-workloads/envs/<env>). Solo se leen 2-security,
# 3-networks/<env> y 4-projects/<env>; la fila admite también 1-org, pero esta etapa no usa
# ninguna de sus salidas y no lo lee. Los nombres y tipos de las salidas son los de §7.2, §7.4 y
# §7.5.

data "terraform_remote_state" "security" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "2-security"
  }
}

data "terraform_remote_state" "network" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "3-networks/${var.environment}"
  }

  lifecycle {
    # El plano de control de GKE usa el /28 que reserva el spoke (un solo dato para la regla de
    # firewall del spoke y el clúster).
    postcondition {
      condition = !var.enable_gke || alltrue([
        for k in(var.dr_active ? ["gke_master", "gke_master_dr"] : ["gke_master"]) :
        can(cidrhost(self.outputs.reserved_cidrs[k], 0)) && endswith(self.outputs.reserved_cidrs[k], "/28")
      ])
      error_message = "Con enable_gke, el estado de 3-networks/<env> debe publicar reserved_cidrs[\"gke_master\"] (y gke_master_dr con dr_active) como /28: el spoke los reserva con su subnet_cidrs (y enable_dr)."
    }
    # Los puertos de los backends deben estar abiertos en la regla de firewall del spoke para el
    # balanceador (lb_backend_ports de la etapa 3). Si la etapa 3 todavía no publica la salida, no
    # se comprueba.
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
      error_message = "Algún puerto de backend (mig_http_port con enable_mig) no está en lb_backend_ports de la etapa 3: el firewall del spoke bloquearía al balanceador y a sus verificaciones de salud."
    }
  }
}

data "terraform_remote_state" "projects" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "4-projects/${var.environment}"
  }
}

locals {
  # §7.5: proyecto de servicio y cuentas de servicio de la aplicación (usos gke_nodes, workload,
  # mig, run).
  project_id       = data.terraform_remote_state.projects.outputs.service_project_ids[var.application]
  service_accounts = data.terraform_remote_state.projects.outputs.service_accounts[var.application]

  # §7.2: llaves del entorno por ubicación (primary_region, dr_region y la multirregión) y uso.
  kms_key_ids = data.terraform_remote_state.security.outputs.kms_key_ids[var.environment]

  # §7.4: Shared VPC del spoke.
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
