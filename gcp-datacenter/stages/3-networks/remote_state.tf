# Lecturas de etapas anteriores (contrato §6.1: el hub puede leer 0-bootstrap y 1-org).
# Solo se lee 1-org: de 0-bootstrap el hub no necesita ningún valor.
data "terraform_remote_state" "org" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "1-org"
  }
}

locals {
  # Proyecto net-hub creado por 1-org (salida common_project_ids, llave net_hub).
  hub_project_id = data.terraform_remote_state.org.outputs.common_project_ids["net_hub"]
}
