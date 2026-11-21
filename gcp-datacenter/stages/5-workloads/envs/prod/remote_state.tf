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
}
