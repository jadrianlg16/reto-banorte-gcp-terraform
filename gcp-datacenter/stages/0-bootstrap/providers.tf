# La etapa 0 la corre una sola vez una persona con sus credenciales de aplicación
# (gcloud auth application-default login), con rol owner en el proyecto, roles/iam.denyAdmin y
# roles/billing.costsManager en la cuenta de facturación (runbook 01). El proyecto ya existe: es
# el proyecto de cuota de las llamadas, como en las demás raíces.
# VERIFICAR-EN-APPLY: que el primer plan funcione con cloudresourcemanager, serviceusage y
# storage ya habilitadas en el proyecto (si falta alguna: gcloud services enable antes del
# primer plan).
provider "google" {
  billing_project       = var.project_id
  user_project_override = true
}

provider "google-beta" {
  billing_project       = var.project_id
  user_project_override = true
}
