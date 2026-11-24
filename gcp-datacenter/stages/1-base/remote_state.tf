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

  # Raíz → correo de la cuenta del pipeline (8 raíces) y la de lectura.
  stage_service_accounts = local.bootstrap.stage_service_accounts
  read_service_account   = local.bootstrap.read_service_account

  # Rol → ID completo de los roles personalizados de 0-bootstrap.
  custom_role_ids = local.bootstrap.custom_role_ids
}
