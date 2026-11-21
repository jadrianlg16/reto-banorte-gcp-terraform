# DNS del hub (contrato §7.3):
# - zona de reenvío del dominio on-premises hacia onprem_dns_servers por la VPN
#   (forwarding_path = private: las consultas salen de 35.199.192.0/19, que se anuncia por BGP);
# - política de servidor con reenvío entrante, para que on-premises resuelva las zonas de
#   Cloud DNS visibles desde el hub (incluidas las privadas de cada entorno, que los spokes
#   adjuntan también a la VPC hub), y registro de consultas.
# Los spokes resuelven el dominio on-premises con una zona de peering hacia la VPC hub.
# VERIFICAR-EN-APPLY: con simulate_onprem = true no existe servidor DNS en onprem_dns_servers
# (la VPC onprem-sim no tiene VM); el reenvío solo se puede probar con un servidor real o una
# VM DNS creada a mano en onprem-sim.
module "dns" {
  source = "../../modules/dns"

  project_id  = local.hub_project_id
  prefix      = var.prefix
  environment = local.environment
  networks    = [module.hub.network_id]
  labels      = local.labels

  zones = {
    onprem = {
      type        = "forwarding"
      domain      = var.onprem_dns_domain
      description = "Reenvío condicional del dominio on-premises por la VPN."
      target_name_servers = [
        for ip in var.onprem_dns_servers : { ipv4_address = ip, forwarding_path = "private" }
      ]
    }
  }

  server_policy = {
    enable_inbound_forwarding = true
    enable_logging            = true
  }

  depends_on = [google_project_service.hub]
}
