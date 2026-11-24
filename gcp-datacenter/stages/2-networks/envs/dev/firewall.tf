# Política de firewall de red del spoke, asociada a su VPC (contrato §7.4, ADR 0029 §6). Sin
# política jerárquica, esta política es la única que decide la entrada al spoke, con la misma
# intención que antes: lo que la organización delegaba (verificaciones de salud, IAP, tráfico
# interno y de on-premises) lo permiten estas reglas solo hacia donde hace falta, es decir, las
# verificaciones de salud solo hacia lb_backend y el SSH por IAP solo hacia iap_ssh. Con
# enable_filestore_nfs_lock_callbacks también entran las llamadas de Filestore (rango psa) a
# los clientes NFS. Lo demás, incluido lo que la organización negaba por defecto, lo deniega
# la regla por defecto del módulo (prioridad 65000, con registro).
#
# Etiquetas seguras: lb_backend e iap_ssh, cada una con su propia llave (padre: el proyecto;
# ligada a esta VPC) y un solo valor, para que una VM pueda llevar las dos. Quien crea las
# instancias necesita roles/resourcemanager.tagUser sobre los valores (salida secure_tags): esta
# raíz se lo da a la cuenta de cargas del entorno solo sobre sus valores (hallazgo 1: tf-wl-<env>
# ya no tiene tagUser de proyecto).

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

  # Llamadas de Filestore a los clientes NFS para el bloqueo de archivos (statd y
  # nlockmgr): Filestore toma su IP del rango de Private Service Access.
  # https://cloud.google.com/filestore/docs/configure-firewall
  spoke_firewall_rules_filestore = {
    for k, r in {
      allow-filestore-nfs-callbacks = {
        description        = "Filestore (rango de Private Service Access) hacia los clientes NFS: portmapper, statd y nlockmgr."
        priority           = 1050
        action             = "allow"
        src_ip_ranges      = [local.active_cidrs["psa"]]
        target_secure_tags = []
        layer4_configs = concat(
          [{ ip_protocol = "tcp", ports = var.filestore_nfs_lock_ports.tcp }],
          length(var.filestore_nfs_lock_ports.udp) > 0 ? [{ ip_protocol = "udp", ports = var.filestore_nfs_lock_ports.udp }] : [],
        )
      }
    } : k => r if var.enable_filestore_nfs_lock_callbacks
  }
}

module "firewall" {
  source = "../../../../modules/firewall"

  prefix      = var.prefix
  environment = var.environment
  # Se arma con valores que se conocen en el plan; la referencia a module.spoke ordena la
  # creación después de la VPC.
  parent = "projects/${var.project_id}/global/networks/${module.spoke.network_name}"

  secure_tags = {
    lb_backend = { description = "Backends de los balanceadores (externo e interno)." }
    iap_ssh    = { description = "VM que admiten SSH por Identity-Aware Proxy." }
  }

  rules = merge(local.spoke_firewall_rules, local.spoke_firewall_rules_filestore)
}

# Número del proyecto, para el correo del agente de GKE.
data "google_project" "this" {
  project_id = var.project_id
}

locals {
  # Cuenta de cargas del entorno: la crea 0-bootstrap como <prefix>-tf-wl-<env> en project_id
  # (stages/0-bootstrap/service_accounts.tf). Se arma igual porque el spoke no lee el estado de
  # 0-bootstrap.
  workloads_account = "serviceAccount:${var.prefix}-tf-wl-${var.environment}@${var.project_id}.iam.gserviceaccount.com"

  # Valor → miembro → rol sobre ese valor de etiqueta:
  # - tf-wl-<env>: tagUser sobre lb_backend e iap_ssh, para crear la plantilla del MIG y los
  #   pools de GKE con esas etiquetas;
  # - agente de GKE: tagHoldAdmin sobre lb_backend (la etiqueta de los nodos), que la guía de GKE
  #   "Use Tags for firewalls" pide dar sobre cada valor que usan los clústeres
  #   (https://cloud.google.com/kubernetes-engine/docs/how-to/tags-firewall-policies). Su
  #   tagUser de proyecto lo da 0-bootstrap.
  tag_value_bindings = {
    "lb_backend|workloads" = { tag = "lb_backend", role = "roles/resourcemanager.tagUser", member = local.workloads_account }
    "iap_ssh|workloads"    = { tag = "iap_ssh", role = "roles/resourcemanager.tagUser", member = local.workloads_account }
    "lb_backend|gke_agent" = {
      tag    = "lb_backend"
      role   = "roles/resourcemanager.tagHoldAdmin"
      member = "serviceAccount:service-${data.google_project.this.number}@container-engine-robot.iam.gserviceaccount.com"
    }
  }
}

# VERIFICAR-EN-APPLY: que tf-wl-<env> cree la plantilla del MIG y los pools de GKE con
# lb_backend e iap_ssh con este tagUser sobre los valores y sin tagUser de proyecto (gcloud
# resource-manager tags bindings list --parent=<recurso> muestra el enlace), y que tf-net-<env>
# pueda asignarlo con TfNetworkTagManager (tagValues.setIamPolicy).
resource "google_tags_tag_value_iam_member" "this" {
  for_each = local.tag_value_bindings

  tag_value = module.firewall.secure_tag_ids[each.value.tag]
  role      = each.value.role
  member    = each.value.member
}
