# Credenciales: la cuenta de servicio <prefix>-tf-net por Workload Identity Federation (pipeline,
# entorno common de GitHub; ADR 0029 §3) o la que indique GOOGLE_IMPERSONATE_SERVICE_ACCOUNT al
# correr a mano.
provider "google" {
  region = var.primary_region
}

provider "google-beta" {
  region = var.primary_region
}

provider "random" {}
