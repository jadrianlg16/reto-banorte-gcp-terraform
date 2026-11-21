# Lecturas de etapas anteriores (§6.1: 1-org lee solo 0-bootstrap).

data "terraform_remote_state" "bootstrap" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "0-bootstrap"
  }
}

locals {
  seed_project_id        = data.terraform_remote_state.bootstrap.outputs.seed_project_id
  stage_service_accounts = data.terraform_remote_state.bootstrap.outputs.stage_service_accounts
  # Salidas adicionales de 0-bootstrap (no están en la tabla de §7.0): roles personalizados
  # de organización. secret_container_admin_role_id: contenedores de secretos sin acceso a
  # valores (2-security); kms_secret_iam_role_id: el que 2-security asigna a 4-projects.
  secret_container_admin_role_id = data.terraform_remote_state.bootstrap.outputs.secret_container_admin_role_id
  kms_secret_iam_role_id         = data.terraform_remote_state.bootstrap.outputs.kms_secret_iam_role_id
}
