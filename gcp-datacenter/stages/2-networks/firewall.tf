# Política de firewall jerárquica en la organización (contrato §7.3). Orden de evaluación:
# esta política → reglas de VPC → política de red de cada spoke.
#
# Una regla allow o deny aquí es final: las políticas de abajo no pueden cambiarla. Por eso
# esta política no tiene ninguna regla allow (contrato §7.3):
# - Las verificaciones de salud y proxies de Google (35.191.0.0/16, 130.211.0.0/22, TCP) y el
#   IAP (35.235.240.0/20, TCP 22 y 3389) se delegan con goto_next: los permite la política de
#   red de cada spoke solo hacia las VM con la etiqueta segura lb_backend o iap_ssh. Un allow
#   aquí dejaría sin efecto esas etiquetas.
# - El tráfico interno (hub y spokes) y el de on-premises también se delega con goto_next.
# - Con simulate_onprem = true, el reenvío de Cloud DNS (35.199.192.0/19, TCP/UDP 53) hacia
#   la VPC onprem-sim se delega solo a esa VPC, que tiene su propia política de red.
# - Lo demás lo deniega la regla por defecto del módulo (prioridad 65000, con registro).

locals {
  google_lb_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  iap_range        = "35.235.240.0/20"

  internal_ranges = distinct(concat(
    [var.hub_supernet],
    [for env in sort(keys(var.spoke_supernets)) : var.spoke_supernets[env]],
  ))

  org_firewall_rules = {
    delegate-health-checks = {
      description    = "Verificaciones de salud y proxies de Google: las permite el spoke hacia lb_backend."
      priority       = 1000
      action         = "goto_next"
      src_ip_ranges  = local.google_lb_ranges
      layer4_configs = [{ ip_protocol = "tcp", ports = [] }]
    }
    delegate-iap = {
      description    = "Identity-Aware Proxy (SSH y RDP): lo decide el spoke (SSH hacia iap_ssh)."
      priority       = 1010
      action         = "goto_next"
      src_ip_ranges  = [local.iap_range]
      layer4_configs = [{ ip_protocol = "tcp", ports = ["22", "3389"] }]
    }
    delegate-internal = {
      description    = "Tráfico interno del hub y los spokes: lo decide la política de red del spoke."
      priority       = 2000
      action         = "goto_next"
      src_ip_ranges  = local.internal_ranges
      layer4_configs = [{ ip_protocol = "all", ports = [] }]
    }
    delegate-onprem = {
      description    = "Tráfico de on-premises: lo decide la política de red del spoke."
      priority       = 2010
      action         = "goto_next"
      src_ip_ranges  = var.onprem_cidrs
      layer4_configs = [{ ip_protocol = "all", ports = [] }]
    }
  }

  # Solo con simulate_onprem = true: las consultas del reenvío de Cloud DNS (salen de
  # 35.199.192.0/19) hacia el servidor DNS de prueba en onprem-sim. Se delegan solo para esa
  # VPC (target_resources) y las permite su propia política de red (firewall_onprem_sim). El
  # IAP ya lo delega delegate-iap para todas las VPC.
  onprem_sim_network_url = var.simulate_onprem ? "https://www.googleapis.com/compute/v1/projects/${local.hub_project_id}/global/networks/${module.onprem_sim[0].network_name}" : null

  org_firewall_rules_sim = { for k, r in {
    delegate-dns-onprem-sim = {
      description      = "Reenvío de Cloud DNS hacia el DNS de prueba de onprem-sim: lo decide la política de red de onprem-sim."
      priority         = 1020
      action           = "goto_next"
      src_ip_ranges    = [local.cloud_dns_forwarding_range]
      target_resources = [local.onprem_sim_network_url]
      layer4_configs   = [{ ip_protocol = "tcp", ports = ["53"] }, { ip_protocol = "udp", ports = ["53"] }]
    }
  } : k => r if var.simulate_onprem }
}

# VERIFICAR-EN-APPLY: que el tráfico delegado con goto_next llegue a la política de red del
# spoke (y no a la denegación por defecto de esta política), que las verificaciones de salud
# lleguen a los backends con lb_backend y que IAP solo entre a las VM con iap_ssh.
module "firewall_org" {
  source = "../../modules/firewall"

  prefix      = var.prefix
  environment = local.environment
  policy_type = "hierarchical"
  parent      = "organizations/${var.org_id}"
  rules       = merge(local.org_firewall_rules, local.org_firewall_rules_sim)
}

# Política de red de la VPC onprem-sim (solo con simulate_onprem = true): permite exactamente
# lo que la organización le delega para probar el reenvío DNS, es decir, las consultas de
# Cloud DNS (TCP y UDP 53 desde 35.199.192.0/19) y el SSH por IAP para administrar la VM DNS
# de prueba. Lo demás lo deniega la regla por defecto del módulo.
# VERIFICAR-EN-APPLY: que una VM DNS en onprem_dns_servers responda a una consulta de un
# spoke (zona de peering → zona de reenvío del hub → VPN → onprem-sim) y que la respuesta
# vuelva a 35.199.192.0/19 por la ruta que el hub anuncia por BGP.
module "firewall_onprem_sim" {
  source = "../../modules/firewall"
  count  = var.simulate_onprem ? 1 : 0

  prefix      = var.prefix
  environment = local.environment
  name_suffix = "onprem-sim"
  policy_type = "network"
  parent      = "projects/${local.hub_project_id}/global/networks/${module.onprem_sim[0].network_name}"

  rules = {
    allow-dns-forwarding = {
      description    = "Consultas del reenvío de Cloud DNS hacia el servidor DNS de prueba."
      priority       = 1000
      action         = "allow"
      src_ip_ranges  = [local.cloud_dns_forwarding_range]
      layer4_configs = [{ ip_protocol = "tcp", ports = ["53"] }, { ip_protocol = "udp", ports = ["53"] }]
    }
    allow-iap-ssh = {
      description    = "SSH por Identity-Aware Proxy para administrar la VM DNS de prueba."
      priority       = 1010
      action         = "allow"
      src_ip_ranges  = [local.iap_range]
      layer4_configs = [{ ip_protocol = "tcp", ports = ["22"] }]
    }
  }
}
