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
}
