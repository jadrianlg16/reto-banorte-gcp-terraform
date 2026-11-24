# Roles personalizados del proyecto (ADR 0029 §2). Viven aquí, y no en la raíz que los usa,
# para que ninguna cuenta del pipeline necesite roles/iam.roleAdmin: con él podría ampliar el
# rol que ella misma usa. La política de denegación (deny_policy.tf) les niega además crear,
# cambiar o borrar roles. Todos llevan el prefijo de la empresa en el ID (los IDs de roles
# borrados no se reutilizan de inmediato; esta raíz no tiene destroy).
# VERIFICAR-EN-APPLY: que todos los permisos estén admitidos en roles personalizados de proyecto.

locals {
  custom_roles = {
    # 1-base: contenedores de secretos (ADR 0015) y su IAM (secretAccessor de las cuentas de
    # ejecución de cada entorno), sin leer sus valores. roles/secretmanager.admin incluye
    # secretmanager.versions.access; este rol no tiene permisos de versiones. Con
    # secrets.setIamPolicy la cuenta podría darse secretAccessor a sí misma: la política de
    # denegación niega secretmanager.versions.access a las cuentas del pipeline salvo tf-net
    # (deny_policy.tf), así que ese permiso no le sirve para leer un valor.
    secret_container_admin = {
      role_id     = "${var.prefix}TfSecretContainerAdmin"
      title       = "Terraform: contenedores de secretos sin acceso a valores"
      description = "Crear, cambiar y borrar secretos de Secret Manager y administrar su IAM (1-base). Sin leer ni agregar versiones."
      permissions = [
        "secretmanager.locations.get",
        "secretmanager.locations.list",
        "secretmanager.secrets.create",
        "secretmanager.secrets.delete",
        "secretmanager.secrets.get",
        "secretmanager.secrets.getIamPolicy",
        "secretmanager.secrets.list",
        "secretmanager.secrets.setIamPolicy",
        "secretmanager.secrets.update",
      ]
    }
    # 1-base: lo que necesita de roles/iam.serviceAccountAdmin (crear las cuentas de ejecución
    # de los entornos y administrar su IAM: serviceAccountUser de tf-wl-<env> y el enlace de
    # Workload Identity) SIN iam.serviceAccounts.createTagBinding ni deleteTagBinding.
    # serviceAccountAdmin los incluye, y deleteTagBinding no se puede negar en una política de
    # denegación: con él y tagUser, una cuenta podría quitar la etiqueta de protección a las
    # cuentas del pipeline y después cambiar su IAM (ADR 0029 §5).
    service_account_manager = {
      role_id     = "${var.prefix}TfServiceAccountManager"
      title       = "Terraform: cuentas de servicio sin etiquetas"
      description = "Crear, cambiar, borrar y administrar el IAM de cuentas de servicio (1-base). Sin crear ni quitar etiquetas de las cuentas."
      permissions = [
        "iam.serviceAccounts.create",
        "iam.serviceAccounts.delete",
        "iam.serviceAccounts.disable",
        "iam.serviceAccounts.enable",
        "iam.serviceAccounts.get",
        "iam.serviceAccounts.getIamPolicy",
        "iam.serviceAccounts.list",
        "iam.serviceAccounts.setIamPolicy",
        "iam.serviceAccounts.undelete",
        "iam.serviceAccounts.update",
        "resourcemanager.projects.get",
      ]
    }
    # Apagado fuera de horario (ADR 0028, ADR 0029 §4): exactamente los permisos de las tres
    # llamadas de sus trabajos (instances.patch de Cloud SQL Admin y nodePools.setAutoscaling y
    # setSize de GKE). Sin crear, borrar ni leer datos. El ADR 0029 lo pone en 1-base; va aquí
    # para que la cuenta de 1-base no necesite roles/iam.roleAdmin (1-base lo vuelve a publicar
    # como off_hours_role_id).
    # VERIFICAR-EN-APPLY: que los tres permisos basten para las tres llamadas (gcloud scheduler
    # jobs run de cada trabajo con respuesta 2xx).
    off_hours_scheduler = {
      role_id     = "${var.prefix}OffHoursScheduler"
      title       = "Apagado fuera de horario"
      description = "Detener y encender Cloud SQL (activationPolicy) y cambiar autoescalado y tamaño de pools de GKE (ADR 0028). Sin crear, borrar ni leer datos."
      permissions = [
        "cloudsql.instances.get",
        "cloudsql.instances.update",
        "container.clusters.update",
      ]
    }
  }

  # ID completo de cada rol, armado con valores conocidos en el plan (el atributo name del
  # recurso solo se conoce después del apply).
  custom_role_ids = { for k, r in local.custom_roles : k => "projects/${var.project_id}/roles/${r.role_id}" }
}

resource "google_project_iam_custom_role" "this" {
  for_each = local.custom_roles

  project     = var.project_id
  role_id     = each.value.role_id
  title       = each.value.title
  description = each.value.description
  stage       = "GA"
  permissions = each.value.permissions

  depends_on = [google_project_service.this]
}
