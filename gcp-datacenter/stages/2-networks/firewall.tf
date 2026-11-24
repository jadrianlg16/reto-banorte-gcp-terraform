# Políticas de firewall de red de las VPC comunes (ADR 0029 §6). Sin organización ni carpetas
# no hay política jerárquica: cada VPC (hub, onprem-sim y cada spoke) tiene su propia política
# de red global con la denegación por defecto de la entrada (módulo firewall, prioridad 65000,
# con registro). Orden de evaluación en cada VPC: reglas de VPC (no hay ninguna) → política de
# red → reglas implícitas.
#
# Misma intención que la política jerárquica anterior:
# - Lo que la organización negaba por defecto lo niega ahora la política de cada VPC.
# - Lo que delegaba con goto_next (verificaciones de salud, IAP, tráfico interno y de
#   on-premises) lo decidía la política de red de cada VPC: los spokes lo permiten solo hacia
#   sus etiquetas seguras (envs/<env>/firewall.tf) y onprem-sim solo el DNS del reenvío y el
#   SSH por IAP (abajo). La VPC hub no tenía política de red y lo delegado terminaba en la
#   denegación implícita de la VPC: su política nueva no permite nada.

locals {
  iap_range = "35.235.240.0/20"
}

# Política de red de la VPC hub: solo la denegación por defecto. El hub no tiene cargas.
# HYPOTHESIS: la VPN (IKE y BGP con el Cloud Router) y el tráfico de paso por el peering no se
# evalúan contra las reglas del hub, sino contra las de la VM de destino (las del spoke).
# VERIFICAR-EN-APPLY: que los túneles y las sesiones BGP suban con esta política, y que las
# consultas de on-premises a las IP de reenvío entrante de Cloud DNS (salida
# dns_inbound_forwarder_ips) no las corte esta denegación (la guía de políticas de servidor DNS
# no habla de firewall para el reenvío entrante). Si las corta, agregar una regla allow desde
# onprem_cidrs, TCP y UDP 53; antes las cortaba igual la denegación implícita de la VPC.
module "firewall_hub" {
  source = "../../modules/firewall"

  prefix      = var.prefix
  environment = local.environment
  name_suffix = "hub"
  # Se arma con valores que se conocen en el plan; la referencia a module.hub ordena la
  # creación después de la VPC.
  parent = "projects/${var.project_id}/global/networks/${module.hub.network_name}"
}

# Política de red de la VPC onprem-sim (solo con simulate_onprem = true): permite exactamente
# lo necesario para probar el reenvío DNS, es decir, las consultas de Cloud DNS (TCP y UDP 53
# desde 35.199.192.0/19) y el SSH por IAP para administrar la VM DNS de prueba. Lo demás lo
# deniega la regla por defecto del módulo.
# VERIFICAR-EN-APPLY: que una VM DNS en onprem_dns_servers responda a una consulta de un
# spoke (zona de peering → zona de reenvío del hub → VPN → onprem-sim) y que la respuesta
# vuelva a 35.199.192.0/19 por la ruta que el hub anuncia por BGP.
module "firewall_onprem_sim" {
  source = "../../modules/firewall"
  count  = var.simulate_onprem ? 1 : 0

  prefix      = var.prefix
  environment = local.environment
  name_suffix = "onprem-sim"
  parent      = "projects/${var.project_id}/global/networks/${module.onprem_sim[0].network_name}"

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
