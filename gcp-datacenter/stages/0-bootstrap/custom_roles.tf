# Roles personalizados del proyecto (ADR 0029 §2). Viven aquí, y no en la raíz que los usa,
# para que ninguna cuenta del pipeline necesite roles/iam.roleAdmin: con él podría ampliar el
# rol que ella misma usa. La política de denegación (deny_policy.tf) les niega además crear,
# cambiar o borrar roles. Todos llevan el prefijo de la empresa en el ID (los IDs de roles
# borrados no se reutilizan de inmediato; esta raíz no tiene destroy).
# VERIFICAR-EN-APPLY: que todos los permisos estén admitidos en roles personalizados de proyecto.

locals {
  custom_roles = {
    # 1-base: contenedores de secretos (ADR 0015) sin leer sus valores. roles/secretmanager.admin
    # incluye secretmanager.versions.access; este rol no tiene permisos de versiones ni
    # secrets.setIamPolicy (con él la cuenta podría darse secretAccessor a sí misma).
    secret_container_admin = {
      role_id     = "${var.prefix}TfSecretContainerAdmin"
      title       = "Terraform: contenedores de secretos sin acceso a valores"
      description = "Crear, cambiar y borrar secretos de Secret Manager (1-base). Sin leer ni agregar versiones y sin cambiar su IAM."
      permissions = [
        "secretmanager.locations.get",
        "secretmanager.locations.list",
        "secretmanager.secrets.create",
        "secretmanager.secrets.delete",
        "secretmanager.secrets.get",
        "secretmanager.secrets.list",
        "secretmanager.secrets.update",
      ]
    }
    # 3-workloads: leer y asignar IAM de llaves y secretos de su entorno, sin administrar, usar
    # ni destruir llaves ni leer valores. Se asigna condicionado a <prefix>-<env>-
    # (service_accounts.tf).
    kms_secret_iam_granter = {
      role_id     = "${var.prefix}TfKmsSecretIamGranter"
      title       = "Terraform: IAM de llaves KMS y secretos"
      description = "Leer y asignar IAM de llaves KMS y secretos (3-workloads, condicionado al entorno). Sin administrar ni usar las llaves."
      permissions = [
        "cloudkms.cryptoKeys.get",
        "cloudkms.cryptoKeys.getIamPolicy",
        "cloudkms.cryptoKeys.list",
        "cloudkms.cryptoKeys.setIamPolicy",
        "cloudkms.keyRings.get",
        "cloudkms.keyRings.list",
        "secretmanager.secrets.get",
        "secretmanager.secrets.getIamPolicy",
        "secretmanager.secrets.list",
        "secretmanager.secrets.setIamPolicy",
      ]
    }
    # 3-workloads: lo que necesita de roles/iam.serviceAccountAdmin (crear sus cuentas de
    # ejecución y administrar su IAM, incluido el enlace de Workload Identity) SIN
    # iam.serviceAccounts.createTagBinding ni deleteTagBinding. serviceAccountAdmin los incluye, y
    # deleteTagBinding no se puede negar en una política de denegación: con él y tagUser, una
    # cuenta de entorno podría quitar la etiqueta de protección a las cuentas del pipeline y
    # después cambiar su IAM (ADR 0029 §5).
    service_account_manager = {
      role_id     = "${var.prefix}TfServiceAccountManager"
      title       = "Terraform: cuentas de servicio sin etiquetas"
      description = "Crear, cambiar, borrar y administrar el IAM de cuentas de servicio (3-workloads). Sin crear ni quitar etiquetas de las cuentas."
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
    # 3-workloads: dar artifactregistry.reader sobre el repositorio de su entorno a sus cuentas de
    # ejecución. Lo asigna 1-base sobre cada repositorio del entorno (no en el proyecto), así que
    # no depende de condiciones sobre Artifact Registry.
    repository_iam_granter = {
      role_id     = "${var.prefix}TfRepositoryIamGranter"
      title       = "Terraform: IAM de repositorios de Artifact Registry"
      description = "Leer y asignar IAM de un repositorio de Artifact Registry (3-workloads, por repositorio). Sin leer ni publicar imágenes."
      permissions = [
        "artifactregistry.repositories.get",
        "artifactregistry.repositories.getIamPolicy",
        "artifactregistry.repositories.setIamPolicy",
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
