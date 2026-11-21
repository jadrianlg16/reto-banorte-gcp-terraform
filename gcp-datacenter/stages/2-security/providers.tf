# La etapa corre con la cuenta <prefix>-tf-2-security (WIF desde GitHub Actions). Las APIs de
# nivel organización (Access Context Manager) se cobran al proyecto semilla, proyecto de cuota
# de las cuentas de etapa.
# VERIFICAR-EN-APPLY: que todas las APIs que usa la etapa acepten el proyecto de cuota.
provider "google" {
  billing_project       = local.seed_project_id
  user_project_override = true
}

provider "google-beta" {
  billing_project       = local.seed_project_id
  user_project_override = true
}
