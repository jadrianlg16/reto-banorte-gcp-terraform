# DNS del spoke (contrato §7.4):
# - zona privada <environment>.<dns_domain_base> (por defecto <env>.empresa.internal.),
#   adjunta a la VPC spoke y a la VPC hub: así on-premises la resuelve por el reenvío
#   entrante del hub, y ningún otro entorno la ve;
# - zona de peering del dominio on-premises hacia la VPC hub (allí está la zona de reenvío);
# - zonas privadas de las API de Google hacia el VIP de google_apis_vip (restricted por
#   defecto), según la guía de Private Google Access de Google:
#   - googleapis.com.: A de restricted|private.googleapis.com → VIP y comodín CNAME hacia ese
#     nombre (la ruta al VIP restringido la crea network-spoke; la del VIP privado
#     199.36.153.8/30 la cubre la ruta 0.0.0.0/0 del spoke);
#   - gcr.io. y pkg.dev. (imágenes de Container Registry y Artifact Registry) y run.app.
#     (llamadas a servicios de Cloud Run): A del dominio → VIP y comodín CNAME hacia el
#     dominio. Sin ellas esos nombres resuelven a IP públicas de Google y el tráfico sale por
#     la ruta de internet sin pasar por el VIP;
# - política de servidor solo con registro de consultas (sin reenvío entrante: on-premises
#   entra por el hub).
locals {
  private_dns_domain = "${var.environment}.${var.dns_domain_base}"

  google_vip_ips = {
    restricted = ["199.36.153.4", "199.36.153.5", "199.36.153.6", "199.36.153.7"]
    private    = ["199.36.153.8", "199.36.153.9", "199.36.153.10", "199.36.153.11"]
  }
  google_vip_name = "${var.google_apis_vip}.googleapis.com."

  # Dominios de Google que se resuelven al VIP además de googleapis.com (llave de zona → dominio).
  # VERIFICAR-EN-APPLY: que un nodo de GKE descargue imágenes de pkg.dev y que una llamada a
  # un servicio *.run.app desde el spoke llegue por el VIP elegido (en prod, dentro del
  # perímetro de VPC-SC).
  google_vip_domains = {
    gcr = "gcr.io."
    pkg = "pkg.dev."
    run = "run.app."
  }

  google_vip_zones = {
    for k, d in local.google_vip_domains : k => {
      type        = "private"
      domain      = d
      description = "${d} por el VIP ${var.google_apis_vip}.googleapis.com."
      records = {
        apex     = { name = "", type = "A", rrdatas = local.google_vip_ips[var.google_apis_vip] }
        wildcard = { name = "*", type = "CNAME", rrdatas = [d] }
      }
    }
  }
}

module "dns" {
  source = "../../../../modules/dns"

  project_id  = module.project.project_id
  prefix      = var.prefix
  environment = var.environment
  networks    = [module.spoke.network_id]
  labels      = local.labels

  zones = merge({
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
      description = "API de Google por el VIP ${var.google_apis_vip}.googleapis.com."
      records = {
        vip = {
          name    = var.google_apis_vip
          type    = "A"
          rrdatas = local.google_vip_ips[var.google_apis_vip]
        }
        wildcard = {
          name    = "*"
          type    = "CNAME"
          rrdatas = [local.google_vip_name]
        }
      }
    }
  }, local.google_vip_zones)

  server_policy = {
    enable_inbound_forwarding = false
    enable_logging            = true
  }
}
