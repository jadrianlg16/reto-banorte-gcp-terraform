# Lecturas de otras etapas (ADR 0029 §2: 1-base lee solo 0-bootstrap).

data "terraform_remote_state" "bootstrap" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "0-bootstrap"
  }
}

locals {
  bootstrap = data.terraform_remote_state.bootstrap.outputs

  project_id     = var.project_id
  project_number = local.bootstrap.project_number

  # Raíz → correo de la cuenta del pipeline (8 raíces): solo para dar a tf-wl-<env> actAs sobre
  # las cuentas de ejecución de su entorno (runtime_accounts.tf). Las políticas de organización y
  # el perímetro de VPC-SC, que usaban también la cuenta de lectura, los aplica 0-bootstrap.
  stage_service_accounts = local.bootstrap.stage_service_accounts

  # Rol → ID completo de los roles personalizados de 0-bootstrap.
  custom_role_ids = local.bootstrap.custom_role_ids
}
