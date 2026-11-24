# Workload Identity Federation para GitHub Actions (§6.3, ADR 0007 y 0023). Sin llaves JSON: el
# pipeline cambia el token OIDC de GitHub por un token de la cuenta de su raíz. Qué entorno de
# GitHub puede tomar cada cuenta está en service_accounts.tf (ADR 0029 §3). La política de
# denegación niega a las nueve cuentas cambiar el pool y el proveedor (deny_policy.tf).

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

  # attribute.environment es el atributo del principalSet de las cuentas que escriben y
  # attribute.repository_id el de tf-read; attribute.repository se conserva solo para leer los
  # registros de auditoría.
  # VERIFICAR-EN-APPLY: que el mapeo de attribute.environment no falle en trabajos sin
  # entorno de GitHub (el token no trae la afirmación environment) y que esos trabajos solo
  # obtengan tf-read.
  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.repository"          = "assertion.repository"
    "attribute.ref"                 = "assertion.ref"
    "attribute.environment"         = "assertion.environment"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}
