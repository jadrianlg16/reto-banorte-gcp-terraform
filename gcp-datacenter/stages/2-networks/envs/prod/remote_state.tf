# Lectura de etapas anteriores (ADR 0029 §2: el spoke puede leer 1-base y 2-networks/hub). Solo
# se lee el hub: de 1-base el spoke no usa ninguna salida (las alertas de auditoría viven allí,
# una vez por proyecto) y el proyecto entra por project_id.
data "terraform_remote_state" "hub" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "2-networks/hub"
  }
}

locals {
  # VPC hub (salida hub_network_self_link del hub), para el peering y la zona de peering DNS.
  hub_network_self_link = data.terraform_remote_state.hub.outputs.hub_network_self_link

  # /16 que el hub anuncia a on-premises para este entorno (salida spoke_supernets del hub,
  # interfaz del ADR 0029). Si el hub no lo anuncia, la validación de spoke_supernet falla.
  hub_spoke_supernet = lookup(data.terraform_remote_state.hub.outputs.spoke_supernets, var.environment, null)
}
