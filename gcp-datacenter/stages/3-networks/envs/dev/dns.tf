# DNS del spoke (contrato §7.4):
# - zona privada <environment>.<dns_domain_base> (por defecto <env>.empresa.internal.),
#   adjunta a la VPC spoke y a la VPC hub: así on-premises la resuelve por el reenvío
#   entrante del hub, y ningún otro entorno la ve;
# - zona de peering del dominio on-premises hacia la VPC hub (allí está la zona de reenvío);
# - zona privada googleapis.com. con restricted.googleapis.com → 199.36.153.4/30 y el
#   comodín CNAME, para que las API de Google se alcancen por el VIP restringido (la ruta al
#   VIP la crea network-spoke);
# - política de servidor solo con registro de consultas (sin reenvío entrante: on-premises
#   entra por el hub).
locals {
  private_dns_domain = "${var.environment}.${var.dns_domain_base}"
  restricted_vip_ips = ["199.36.153.4", "199.36.153.5", "199.36.153.6", "199.36.153.7"]
}

module "dns" {
  source = "../../../../modules/dns"

  project_id  = module.project.project_id
  prefix      = var.prefix
  environment = var.environment
  networks    = [module.spoke.network_id]
  labels      = local.labels

  zones = {
    env = {
      type        = "private"
      domain      = local.private_dns_domain
      description = "Zona privada del entorno ${var.environment}."
      # VERIFICAR-EN-APPLY: que la cuenta de la etapa pueda adjuntar la zona a la VPC hub
      # (dns.networks.bindPrivateDNSZone en net-hub) y que on-premises la resuelva por el
      # reenvío entrante del hub.
      networks = [module.spoke.network_id, local.hub_network_self_link]
    }
    onprem = {
      type         = "peering"
      domain       = var.onprem_dns_domain
      description  = "Dominio on-premises: se resuelve con la VPC hub."
      peer_network = local.hub_network_self_link
    }
    googleapis = {
      type        = "private"
      domain      = "googleapis.com."
      description = "API de Google por el VIP restringido (restricted.googleapis.com)."
      records = {
        restricted = {
          name    = "restricted"
          type    = "A"
          rrdatas = local.restricted_vip_ips
        }
        wildcard = {
          name    = "*"
          type    = "CNAME"
          rrdatas = ["restricted.googleapis.com."]
        }
      }
    }
  }

  server_policy = {
    enable_inbound_forwarding = false
    enable_logging            = true
  }
}
