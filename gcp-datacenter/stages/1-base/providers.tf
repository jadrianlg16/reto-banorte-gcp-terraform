# La raíz corre con la cuenta <prefix>-tf-base (WIF desde GitHub Actions, entorno common) y la
# planea <prefix>-tf-read. El proyecto único es el proyecto de cuota de todas las llamadas
# (0-bootstrap les da serviceusage.serviceUsageConsumer).
# VERIFICAR-EN-APPLY: que todas las APIs que usa la raíz acepten el proyecto de cuota.
provider "google" {
  billing_project       = var.project_id
  user_project_override = true
}
