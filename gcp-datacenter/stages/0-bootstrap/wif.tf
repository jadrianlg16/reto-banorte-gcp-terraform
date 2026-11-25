# Workload Identity Federation para GitHub Actions (§6.3, ADR 0007 y 0023). Sin llaves JSON: el
# pipeline cambia el token OIDC de GitHub por un token de la cuenta de su raíz. Qué entorno de
# GitHub puede tomar cada cuenta está en service_accounts.tf (ADR 0029 §3). La política de
# denegación niega a las nueve cuentas cambiar el pool y el proveedor (deny_policy.tf).
#
# Fuentes: Google, "Configure Workload Identity Federation with deployment pipelines" y
# "Workload Identity Federation" (mapeo con CEL, operador ternario, hasta 2048 caracteres por
# expresión), https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines
# y https://docs.cloud.google.com/iam/docs/workload-identity-federation (actualizadas el 2026-11-17);
# GitHub, "OpenID Connect reference" y "Using OpenID Connect with reusable workflows"
# (afirmaciones ref, environment y job_workflow_ref),
# https://docs.github.com/en/actions/reference/security/oidc y
# https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-with-reusable-workflows.

locals {
  # Despliegue (hallazgo 3 de R1 y N3 de la segunda revisión): las cuentas que escriben solo
  # aceptan tokens de un trabajo que cumpla las cuatro condiciones:
  #   - es de una ejecución de main: ref = refs/heads/main (en un flujo reutilizable, ref y
  #     event_name describen al flujo que llama, según GitHub);
  #   - lo define exactamente _terraform-root.yml de este repositorio en main:
  #     job_workflow_ref = <dueño>/<repo>/.github/workflows/_terraform-root.yml@refs/heads/main
  #     (formato <dueño>/<repo>/.github/workflows/<archivo>@<ref> de "Using OpenID Connect with
  #     reusable workflows"). Otro archivo de flujo, o el mismo archivo en otra rama o etiqueta
  #     (uses: …/_terraform-root.yml@<rama>), no cumple;
  #   - lo disparó uno de los eventos de los flujos que escriben: push (apply.yml) o
  #     workflow_dispatch (apply.yml y destroy.yml), los únicos en sus bloques on:. Así un flujo
  #     nuevo con pull_request_target, workflow_run o issue_comment, cuyo ref también es la rama
  #     por defecto ("Events that trigger workflows"), no obtiene una cuenta que escribe;
  #   - tiene entorno de GitHub.
  # Cumplido todo, attribute.deploy es el entorno (common, dev, qa o prod); si no, 'none', que
  # ninguna cuenta acepta. La regla "Deployment branches: main" de cada entorno de GitHub queda
  # como segunda barrera. Si apply.yml o destroy.yml cambian de eventos, esta lista se cambia con
  # ellos (y se vuelve a aplicar esta etapa).
  #
  # Los trabajos que escriben son el trabajo apply de _terraform-root.yml, que apply.yml y
  # destroy.yml llaman como flujo reutilizable. Si un trabajo que no es de un flujo reutilizable
  # trae job_workflow_ref (GitHub solo lo documenta para flujos reutilizables), su valor nombra
  # otro archivo y la igualdad no se cumple.
  #
  # El nombre se compara tal cual (con mayúsculas y minúsculas) contra github_repository, que tiene
  # que coincidir con la afirmación repository. Si el repositorio se renombra, attribute.deploy
  # queda en 'none' (falla cerrado) hasta volver a aplicar esta etapa con el nombre nuevo. Lo
  # mismo si se renombra _terraform-root.yml. La validación de github_repository no admite
  # comillas, así que el nombre no altera la expresión, que cabe de sobra en los 2048 caracteres
  # (prueba en tests/0-bootstrap.tftest.hcl).
  # VERIFICAR-EN-APPLY: el valor de job_workflow_ref y de event_name en el trabajo apply de
  # _terraform-root.yml llamado con uses: ./.github/workflows/... desde apply.yml (push y
  # workflow_dispatch) y desde destroy.yml (se espera
  # <dueño>/<repo>/.github/workflows/_terraform-root.yml@refs/heads/main: GitHub no documenta el
  # ref de una llamada con ruta local; si fuera el SHA, attribute.deploy queda en 'none' y el
  # apply falla en la autenticación).
  wif_deploy_workflow = "${var.github_repository}/.github/workflows/_terraform-root.yml@refs/heads/main"
  wif_deploy_events   = ["push", "workflow_dispatch"]

  wif_deploy = join(" ", [
    "('environment' in assertion",
    "&& assertion.ref == 'refs/heads/main'",
    "&& 'job_workflow_ref' in assertion",
    "&& assertion.job_workflow_ref == '${local.wif_deploy_workflow}'",
    "&& 'event_name' in assertion",
    "&& (${join(" || ", [for e in local.wif_deploy_events : "assertion.event_name == '${e}'"])}))",
    "? assertion.environment : 'none'",
  ])
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "${var.prefix}-${local.environment}-sec-wif-pool"
  display_name              = "GitHub Actions"
  description               = "Identidades de GitHub Actions del repositorio de infraestructura."
  disabled                  = false

  depends_on = [google_project_service.this]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  # checkov:skip=CKV_GCP_125: la revisión solo reconoce una igualdad exacta sobre assertion.sub (repo:<dueño>/<repo>:<ref o entorno>), que ataría el proveedor a una rama o entorno y rompería los plan de los PR; la condición exige los IDs numéricos del repositorio y de su dueño, que limitan igual al repositorio autorizado y no se reutilizan
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "${var.prefix}-${local.environment}-sec-github"
  display_name                       = "GitHub OIDC"
  description                        = "Tokens OIDC de GitHub Actions, solo de ${var.github_repository} (repository_id ${var.github_repository_id})."
  disabled                           = false

  # Solo se aceptan tokens del repositorio autorizado, identificado por sus IDs numéricos y no
  # por su nombre: un nombre de repositorio o de dueño se puede volver a registrar si se borra
  # o se renombra (cybersquatting), un ID no. Cualquier otro repositorio recibe un rechazo en
  # el intercambio de tokens, antes de llegar a IAM.
  attribute_condition = "assertion.repository_id == \"${var.github_repository_id}\" && assertion.repository_owner_id == \"${var.github_repository_owner_id}\""

  # attribute.deploy es el atributo del principalSet de las cuentas que escriben (local.wif_deploy
  # abajo) y attribute.repository_id el de tf-read. attribute.repository, attribute.ref y
  # attribute.environment se conservan solo para leer los registros de auditoría.
  #
  # Las afirmaciones que el token puede no traer (environment en un trabajo sin entorno de
  # GitHub, job_workflow_ref en un trabajo que no es de un flujo reutilizable) se leen solo
  # después de comprobar que están ('<afirmación>' in assertion): una expresión de mapeo que
  # falla deja sin token a cualquier trabajo, también a los de tf-read.
  # VERIFICAR-EN-APPLY: que un trabajo sin entorno de GitHub (plan de un PR) obtenga tf-read con
  # attribute.environment y attribute.deploy en 'none', y que el trabajo apply de
  # _terraform-root.yml llamado desde main obtenga attribute.deploy igual a su entorno.
  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.repository"          = "assertion.repository"
    "attribute.ref"                 = "assertion.ref"
    "attribute.environment"         = "'environment' in assertion ? assertion.environment : 'none'"
    "attribute.deploy"              = local.wif_deploy
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}
