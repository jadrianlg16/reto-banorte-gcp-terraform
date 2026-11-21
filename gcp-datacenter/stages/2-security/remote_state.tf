# Lecturas de etapas anteriores (§6.1: 2-security lee 0-bootstrap y 1-org).

data "terraform_remote_state" "bootstrap" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "0-bootstrap"
  }
}

data "terraform_remote_state" "org" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "1-org"
  }
}

locals {
  seed_project_id        = data.terraform_remote_state.bootstrap.outputs.seed_project_id
  stage_service_accounts = data.terraform_remote_state.bootstrap.outputs.stage_service_accounts

  security_project_id     = data.terraform_remote_state.org.outputs.common_project_ids["security"]
  security_project_number = data.terraform_remote_state.org.outputs.common_project_numbers["security"]
}
