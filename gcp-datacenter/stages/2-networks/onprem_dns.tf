# VM DNS de prueba de onprem-sim (solo con onprem_dns_vm = true, que exige simulate_onprem): el
# servidor DNS "de on-premises" que espera la zona de reenvío del hub (dns.tf) en la primera IP de
# onprem_dns_servers. Así la prueba de resolución desde un entorno no necesita recursos creados a
# mano.
#
# - e2-micro, sin IP pública (sin access_config) y solo IPv4, Shielded VM, OS Login, sin llaves SSH
#   del proyecto ni puerto serie interactivo.
# - Cuenta <prefix>-common-net-dns: la crea 1-base con solo logging.logWriter y le da a esta raíz
#   serviceAccountUser sobre ella (stages/1-base/onprem_dns.tf); el correo se arma con el nombre
#   (ADR 0017). Crear la VM pide además compute.instanceAdmin.v1, que 0-bootstrap le da al hub con
#   onprem_dns_vm = true.
# - El script de arranque instala files/onprem-dns.py, un servidor DNS con autoridad solo sobre
#   onprem_dns_domain hecho con la biblioteca estándar de Python 3: la VPC onprem-sim no tiene
#   ruta a internet, así que no se puede instalar dnsmasq. Registro: dns.<dominio> → la IP de la VM.
# - El firewall de onprem-sim (firewall.tf) ya admite las consultas de Cloud DNS
#   (35.199.192.0/19, TCP y UDP 53) y el SSH por IAP.
#
# VERIFICAR-EN-APPLY: que la imagen debian-12 traiga python3 y systemd (el servicio onprem-dns
# arranca: systemctl status onprem-dns por SSH con IAP), y que desde una VM de un spoke
# `dig dns.<onprem_dns_domain>` devuelva la IP de la VM por zona de peering → zona de reenvío →
# VPN → onprem-sim.
# VERIFICAR-EN-APPLY: que los registros del arranque lleguen a Cloud Logging; onprem-sim no tiene
# ruta a las API de Google, así que quizá solo queden en la salida del puerto serie 1
# (gcloud compute instances get-serial-port-output).

locals {
  onprem_dns_vm_ip    = var.onprem_dns_servers[0]
  onprem_dns_vm_zone  = coalesce(var.onprem_dns_vm_zone, "${var.primary_region}-b")
  onprem_dns_vm_email = "${var.prefix}-${local.environment}-net-dns@${var.project_id}.iam.gserviceaccount.com"

  # Configuración del servidor (files/onprem-dns.py): zona, dirección de escucha y registros A.
  onprem_dns_vm_config = jsonencode({
    zone    = lower(var.onprem_dns_domain)
    bind    = local.onprem_dns_vm_ip
    port    = 53
    ttl     = 300
    records = { dns = local.onprem_dns_vm_ip }
  })
}

resource "google_compute_instance" "onprem_dns" {
  # checkov:skip=CKV_GCP_38: VM de prueba sin datos en la VPC simulada; el disco usa cifrado de Google porque no hay llave KMS de common para Compute (las llaves de 1-base son por entorno)
  count = var.onprem_dns_vm ? 1 : 0

  project      = var.project_id
  name         = "${var.prefix}-${local.environment}-net-dns-${var.region_short_names[var.primary_region]}"
  description  = "Servidor DNS de prueba de onprem-sim para el reenvío de Cloud DNS (administrado por Terraform)."
  zone         = local.onprem_dns_vm_zone
  machine_type = "e2-micro"

  can_ip_forward      = false
  deletion_protection = false
  labels              = local.labels

  boot_disk {
    auto_delete = true

    initialize_params {
      image  = "debian-cloud/debian-12"
      size   = 10
      type   = "pd-standard"
      labels = local.labels
    }
  }

  # Solo IP interna fija (la que espera la zona de reenvío): sin access_config.
  network_interface {
    subnetwork = module.onprem_sim[0].subnets["onprem_sim"].self_link
    network_ip = local.onprem_dns_vm_ip
    stack_type = "IPV4_ONLY"
  }

  service_account {
    email  = local.onprem_dns_vm_email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
    serial-port-enable     = "FALSE"
    # Fin de línea LF aunque la copia de trabajo tenga CRLF (Windows): bash no acepta CRLF y el
    # metadato no debe cambiar según la máquina que planea.
    startup-script = replace(templatefile("${path.module}/files/onprem-dns-startup.sh.tftpl", {
      server = file("${path.module}/files/onprem-dns.py")
      config = local.onprem_dns_vm_config
    }), "\r\n", "\n")
  }
}
