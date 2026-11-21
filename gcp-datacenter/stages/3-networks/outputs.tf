# Salidas de la interfaz entre etapas (contrato §7.3).

output "hub_project_id" {
  description = "ID del proyecto net-hub."
  value       = local.hub_project_id
}

output "hub_network_name" {
  description = "Nombre de la VPC hub."
  value       = module.hub.network_name
}

output "hub_network_self_link" {
  description = "self_link de la VPC hub, para el peering y las zonas de peering DNS de los spokes."
  value       = module.hub.network_self_link
}

output "firewall_policy_id" {
  description = "ID de la política de firewall jerárquica de la organización (locations/global/firewallPolicies/<id>)."
  value       = module.firewall_org.policy_id
}

# Salidas adicionales (no forman parte del contrato).

output "spoke_supernets" {
  description = "Mapa entorno → /16 del spoke que el hub anuncia a on-premises. Cada spoke comprueba que su spoke_supernet coincida."
  value       = var.spoke_supernets
}

output "firewall_policy_rules" {
  description = "Reglas de la política jerárquica creadas por la raíz (nombre → prioridad, acción y orígenes). Además, el módulo crea la denegación por defecto de la entrada (prioridad 65000)."
  value = {
    for k, r in local.org_firewall_rules : k => {
      priority      = r.priority
      action        = r.action
      src_ip_ranges = r.src_ip_ranges
    }
  }
}

output "hub_routers" {
  description = "Mapa región → nombre del Cloud Router del hub."
  value       = module.hub.routers
}

output "bgp_advertised_ranges" {
  description = "Rangos que el hub anuncia a on-premises por BGP."
  value       = local.advertised_ranges
}

output "vpn_tunnel_names" {
  description = "Mapa interfaz → nombre del túnel HA VPN del hub hacia on-premises."
  value       = module.vpn_hub.tunnel_names
}

output "vpn_gateway_ip_addresses" {
  description = "IP externas del gateway HA VPN del hub, para configurar el equipo on-premises. Se conocen hasta el apply."
  value       = module.vpn_hub.gateway_ip_addresses
}

output "dns_inbound_forwarder_ips" {
  description = "IP de reenvío entrante de Cloud DNS en el hub, a las que on-premises reenvía las zonas de GCP. Se conocen hasta el apply."
  value       = module.dns.inbound_forwarder_ips
}

output "onprem_sim_network_name" {
  description = "Nombre de la VPC onprem-sim, o null con simulate_onprem = false."
  value       = var.simulate_onprem ? module.onprem_sim[0].network_name : null
}
