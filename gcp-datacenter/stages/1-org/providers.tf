# La etapa corre con la cuenta <prefix>-tf-1-org (WIF desde GitHub Actions). Las APIs de
# nivel organización y facturación se cobran al proyecto semilla, que es el proyecto de cuota
# de las cuentas de etapa (la etapa 0 les da serviceusage.serviceUsageConsumer en él).
# VERIFICAR-EN-APPLY: que todas las APIs que usa la etapa acepten el proyecto de cuota.
provider "google" {
  billing_project       = local.seed_project_id
  user_project_override = true
}

provider "google-beta" {
  billing_project       = local.seed_project_id
  user_project_override = true
}
