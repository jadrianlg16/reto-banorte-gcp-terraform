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
  rules       = local.org_firewall_rules
}
