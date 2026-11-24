# Credenciales: la cuenta de servicio <prefix>-tf-net-<env> por Workload Identity Federation
# (pipeline, entorno de GitHub del mismo nombre; ADR 0029 §3) o la que indique
# GOOGLE_IMPERSONATE_SERVICE_ACCOUNT al correr a mano.
provider "google" {
  region = var.primary_region
}

provider "google-beta" {
  region = var.primary_region
}
