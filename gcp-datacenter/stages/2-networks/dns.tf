# DNS del hub (contrato §7.3):
# - zona de reenvío del dominio on-premises hacia onprem_dns_servers por la VPN
#   (forwarding_path = private: las consultas salen de 35.199.192.0/19, que se anuncia por BGP);
# - política de servidor con reenvío entrante, para que on-premises resuelva las zonas de
#   Cloud DNS visibles desde el hub (incluidas las privadas de cada entorno, que los spokes
#   adjuntan también a la VPC hub), y registro de consultas.
# Los spokes resuelven el dominio on-premises con una zona de peering hacia la VPC hub.
# Con simulate_onprem = true no existe servidor DNS en onprem_dns_servers (la VPC onprem-sim
# no tiene VM): para probar el reenvío se crea a mano una VM DNS en onprem-sim con esa IP. El
# firewall ya lo admite: la organización delega 35.199.192.0/19 (TCP/UDP 53) solo hacia
# onprem-sim y la política de red de onprem-sim lo permite, junto con SSH por IAP
# (firewall.tf).
# VERIFICAR-EN-APPLY: resolución de onprem_dns_domain desde un spoke con esa VM DNS.
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

# Registro de consultas de Cloud DNS también en la VPC onprem-sim (CIS 2.13: el detector
# DNS_LOGGING_DISABLED busca, por red, una política DNS con registro). Solo registro: sin
# reenvío entrante, porque onprem-sim no resuelve por Cloud DNS (simula on-premises). Una red
# admite una sola política, y onprem-sim no tiene otra.
# VERIFICAR-EN-APPLY: que el detector deje de marcar onprem-sim (pendiente 61).
resource "google_dns_policy" "onprem_sim" {
  count = var.simulate_onprem ? 1 : 0

  project                   = local.hub_project_id
  name                      = "${var.prefix}-${local.environment}-net-dns-onprem-sim-policy"
  description               = "Registro de consultas DNS de la VPC onprem-sim (CIS 2.13)."
  enable_inbound_forwarding = false
  enable_logging            = true

  networks {
    network_url = module.onprem_sim[0].network_id
  }

  depends_on = [google_project_service.hub]
}
