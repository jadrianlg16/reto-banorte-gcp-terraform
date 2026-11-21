# Credenciales: la cuenta de servicio <prefix>-tf-3-networks por Workload Identity Federation
# (pipeline) o la que indique GOOGLE_IMPERSONATE_SERVICE_ACCOUNT al correr a mano.
provider "google" {
  region = var.primary_region
}

provider "google-beta" {
  region = var.primary_region
}
