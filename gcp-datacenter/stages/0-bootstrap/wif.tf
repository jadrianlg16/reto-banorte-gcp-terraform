# Workload Identity Federation para GitHub Actions (§6.3, ADR 0007). Sin llaves JSON: el
# pipeline cambia el token OIDC de GitHub por un token de la cuenta de servicio de la etapa.

resource "google_iam_workload_identity_pool" "github" {
  project                   = module.seed_project.project_id
  workload_identity_pool_id = "${var.prefix}-${local.environment}-sec-wif-pool"
  display_name              = "GitHub Actions"
  description               = "Identidades de GitHub Actions del repositorio de infraestructura."
  disabled                  = false

  lifecycle {
    precondition {
      condition     = var.prefix != "gcp"
      error_message = "Los IDs de pools de WIF no pueden empezar con gcp-: elige otro prefix."
    }
  }
}

resource "google_iam_workload_identity_pool_provider" "github" {
  # checkov:skip=CKV_GCP_125: la revisión solo reconoce una igualdad exacta sobre assertion.sub (repo:<dueño>/<repo>:<ref o entorno>), que ataría el proveedor a una rama o entorno y rompería los plan de los PR; el contrato (§6.3) filtra por assertion.repository, que limita igual al repositorio autorizado
  project                            = module.seed_project.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "${var.prefix}-${local.environment}-sec-github"
  display_name                       = "GitHub OIDC"
  description                        = "Tokens OIDC de GitHub Actions, solo del repositorio autorizado."
  disabled                           = false

  # Solo se aceptan tokens del repositorio autorizado; cualquier otro repositorio de GitHub
  # recibe un rechazo en el intercambio de tokens, antes de llegar a IAM.
  attribute_condition = "assertion.repository == \"${var.github_repository}\""

  # VERIFICAR-EN-APPLY: que el mapeo de attribute.environment no falle en trabajos sin
  # entorno de GitHub (el token no trae la afirmación environment).
  attribute_mapping = {
    "google.subject"        = "assertion.sub"
    "attribute.repository"  = "assertion.repository"
    "attribute.ref"         = "assertion.ref"
    "attribute.environment" = "assertion.environment"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}
