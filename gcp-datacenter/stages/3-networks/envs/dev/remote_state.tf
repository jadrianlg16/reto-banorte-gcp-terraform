# Lecturas de etapas anteriores (contrato §6.1: el spoke puede leer 0-bootstrap, 1-org y
# 3-networks/hub). De 0-bootstrap no se necesita ningún valor.
data "terraform_remote_state" "org" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "1-org"
  }
}

data "terraform_remote_state" "hub" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "3-networks/hub"
  }
}

locals {
  # Carpeta del entorno (salida folder_ids de 1-org).
  folder_id = data.terraform_remote_state.org.outputs.folder_ids[var.environment]

  # Grupo security_admins (salida security_alert_email de 1-org): alertas de auditoría.
  security_alert_email = data.terraform_remote_state.org.outputs.security_alert_email

  # VPC hub (salida hub_network_self_link del hub), para el peering y la zona de peering DNS.
  hub_network_self_link = data.terraform_remote_state.hub.outputs.hub_network_self_link

  # /16 que el hub anuncia a on-premises para este entorno (salida adicional spoke_supernets
  # del hub). Si el hub no la publica, la comprobación de spoke_supernet se omite.
  hub_spoke_supernet = try(data.terraform_remote_state.hub.outputs.spoke_supernets[var.environment], null)
}
