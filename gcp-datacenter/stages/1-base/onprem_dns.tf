# Cuenta de la VM DNS de onprem-sim (stages/2-networks/onprem_dns.tf). La crea 1-base, como las
# cuentas de ejecución, porque la cuenta del hub (<prefix>-tf-net) no administra cuentas de
# servicio ni su IAM: solo recibe serviceAccountUser sobre esta cuenta para adjuntarla a la VM.
#
# Existe solo si 0-bootstrap tiene onprem_dns_vm = true (salida onprem_dns_vm_enabled), que es
# también lo que le da al hub compute.instanceAdmin.v1. Un estado de 0-bootstrap anterior a esa
# salida cuenta como false. El hub arma el correo con el nombre <prefix>-common-net-dns (ADR 0017):
# si esta cuenta no existe, crear la VM falla.
#
# Rol de proyecto: solo logging.logWriter, para que los registros del arranque y del servidor DNS
# lleguen a Cloud Logging. Está en la lista runtime_grantable_roles de la concesión delegada de
# 0-bootstrap.

locals {
  onprem_dns_vm         = try(local.bootstrap.onprem_dns_vm_enabled, false) == true
  onprem_dns_account_id = "${var.prefix}-common-net-dns"
  onprem_dns_email      = "${local.onprem_dns_account_id}@${local.project_id}.iam.gserviceaccount.com"

  # Se agrega a module.iam en iam.tf.
  onprem_dns_project_bindings = [
    for sa in google_service_account.onprem_dns : {
      key       = "onprem-dns|roles/logging.logWriter"
      scope     = "project"
      resource  = local.project_id
      role      = "roles/logging.logWriter"
      member    = "serviceAccount:${sa.account_id}@${sa.project}.iam.gserviceaccount.com"
      condition = null
    }
  ]
}

resource "google_service_account" "onprem_dns" {
  for_each = local.onprem_dns_vm ? toset(["this"]) : toset([])

  project      = local.project_id
  account_id   = local.onprem_dns_account_id
  display_name = "VM DNS de onprem-sim"
  description  = "Cuenta de la VM DNS de prueba de la VPC onprem-sim (hub). Solo escribe registros. Administrada por Terraform (1-base)."

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", local.onprem_dns_account_id))
      error_message = "El ID de cuenta <prefix>-common-net-dns debe tener de 6 a 30 caracteres (ADR 0017)."
    }
  }
}

# La cuenta del hub adjunta esta cuenta a la VM DNS: serviceAccountUser solo sobre ella.
resource "google_service_account_iam_member" "onprem_dns_hub_user" {
  for_each = google_service_account.onprem_dns

  service_account_id = each.value.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${local.stage_service_accounts["2-networks"]}"
}
