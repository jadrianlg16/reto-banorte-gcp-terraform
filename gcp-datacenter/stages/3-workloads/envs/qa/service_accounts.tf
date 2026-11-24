# Cuentas de ejecución de la aplicación y cuenta del apagado fuera de horario. Esta raíz no las
# crea ni les da permisos: las crea 1-base (stages/1-base/runtime_accounts.tf) con sus roles de
# proyecto, la lectura de los secretos del entorno y del repositorio de imágenes, Cloud SQL por
# IAM limitado a las instancias del entorno y el enlace de Workload Identity, y las publica en
# runtime_service_accounts (hallazgos 2 y 4 de la revisión de seguridad del ADR 0029). La cuenta
# de esta raíz (tf-wl-<env>) solo tiene serviceAccountUser sobre las que adjunta: gke_nodes, mig,
# run y scheduler. La postcondición de remote_state.tf exige que existan.

locals {
  # Uso → correo (<prefix>-<environment>-<application>-<uso>): gke_nodes, workload, mig, run y,
  # en los entornos de off_hours_environments de 1-base, scheduler (<...>-sched).
  runtime_service_accounts = local.base.runtime_service_accounts[var.environment][var.application]

  # Cuentas de ejecución que usan los módulos de cómputo y datos.
  service_accounts = {
    for use in ["gke_nodes", "workload", "mig", "run"] : use => local.runtime_service_accounts[use]
  }

  # Cuenta de los trabajos de Cloud Scheduler del apagado (ADR 0028), solo con
  # off_hours_shutdown.enabled.
  scheduler_service_account = local.off_hours_enabled ? local.runtime_service_accounts["scheduler"] : null

  # Miembro de Workload Identity enlazado a la cuenta workload por 1-base
  # (serviceAccount:<proyecto>.svc.id.goog[<application>-<environment>/<cuenta>]), o null
  # mientras gke_workload_identity_bindings de 1-base sea false.
  gke_workload_identity_member = try(local.base.gke_workload_identity_members[var.environment][var.application], null)
}

# Aviso (no error): con GKE y sin el enlace de Workload Identity los pods no obtienen el token de
# la cuenta workload. El pool <proyecto>.svc.id.goog lo crea GKE con el primer clúster, así que
# el orden es: apply de esta raíz con enable_gke, gke_workload_identity_bindings = true en 1-base
# y apply de 1-base.
check "workload_identity_enlazada" {
  assert {
    condition     = !var.enable_gke || local.gke_workload_identity_member != null
    error_message = "enable_gke sin enlace de Workload Identity: los pods de <application>-<environment> no pueden actuar como la cuenta workload. Después del primer clúster, ponga gke_workload_identity_bindings = true en 1-base y aplíquela."
  }
}
