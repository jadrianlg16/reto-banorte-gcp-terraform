# Política de firewall de red del spoke, asociada a su VPC (contrato §7.4). Recibe lo que la
# política jerárquica de la organización delega con goto_next: verificaciones de salud, IAP,
# tráfico interno y de on-premises (la organización no tiene reglas allow, contrato §7.3).
# Estas reglas son las que de verdad permiten las verificaciones de salud (solo hacia
# lb_backend) y el SSH por IAP (solo hacia iap_ssh). Lo demás lo deniega la regla por
# defecto del módulo (prioridad 65000, con registro).
#
# Etiquetas seguras: lb_backend e iap_ssh, cada una con su propia llave y un solo valor, para
# que una VM pueda llevar las dos. La etapa 4 otorga roles/resourcemanager.tagUser sobre los
# valores a quien crea las instancias.

locals {
  google_lb_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  iap_range        = "35.235.240.0/20"

  # Rangos internos que necesitan entrar a las cargas.
  proxy_ranges      = [for k in ["proxy", "proxy_dr"] : local.active_cidrs[k] if contains(keys(local.active_cidrs), k)]
  gke_master_ranges = [for k in ["gke_master", "gke_master_dr"] : local.active_cidrs[k] if contains(keys(local.active_cidrs), k)]
  workload_ranges = [
    for k in ["app", "pods", "run", "app_dr", "pods_dr", "run_dr"] : local.active_cidrs[k] if contains(keys(local.active_cidrs), k)
  ]

  spoke_firewall_rules = {
    allow-lb-health-checks = {
      description        = "Verificaciones de salud y proxies de los balanceadores de Google hacia los backends."
      priority           = 1000
      action             = "allow"
      src_ip_ranges      = local.google_lb_ranges
      target_secure_tags = ["lb_backend"]
      layer4_configs     = [{ ip_protocol = "tcp", ports = var.lb_backend_ports }]
    }
    allow-iap-ssh = {
      description        = "SSH por Identity-Aware Proxy hacia las VM con la etiqueta iap_ssh."
      priority           = 1010
      action             = "allow"
      src_ip_ranges      = [local.iap_range]
      target_secure_tags = ["iap_ssh"]
      layer4_configs     = [{ ip_protocol = "tcp", ports = ["22"] }]
    }
    allow-proxy-to-backends = {
      description        = "Subredes proxy-only del balanceador interno hacia los backends."
      priority           = 1020
      action             = "allow"
      src_ip_ranges      = local.proxy_ranges
      target_secure_tags = ["lb_backend"]
      layer4_configs     = [{ ip_protocol = "tcp", ports = var.lb_backend_ports }]
    }
    allow-gke-control-plane = {
      description        = "Plano de control de GKE hacia los nodos (kubelet y webhooks)."
      priority           = 1030
      action             = "allow"
      src_ip_ranges      = local.gke_master_ranges
      target_secure_tags = []
      layer4_configs     = [{ ip_protocol = "tcp", ports = ["443", "10250"] }]
    }
    allow-workload-internal = {
      description        = "Tráfico este-oeste del entorno: VM y nodos (app), pods de GKE y salida de Cloud Run (run)."
      priority           = 1040
      action             = "allow"
      src_ip_ranges      = local.workload_ranges
      target_secure_tags = []
      layer4_configs     = [{ ip_protocol = "all", ports = [] }]
    }
  }
}

module "firewall" {
  source = "../../../../modules/firewall"

  prefix      = var.prefix
  environment = var.environment
  policy_type = "network"
  # Se arma con valores que se conocen en el plan; la referencia a module.spoke ordena la
  # creación después de la VPC.
  parent = "projects/${module.project.project_id}/global/networks/${module.spoke.network_name}"

  secure_tags = {
    lb_backend = { description = "Backends de los balanceadores (externo e interno)." }
    iap_ssh    = { description = "VM que admiten SSH por Identity-Aware Proxy." }
  }

  rules = local.spoke_firewall_rules
}
