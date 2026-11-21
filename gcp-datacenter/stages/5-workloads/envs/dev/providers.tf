# Los proveedores se autentican con la cuenta de servicio <prefix>-tf-5-workloads (WIF en CI,
# §6.3). Cada recurso fija su proyecto (el de servicio de la aplicación, de la etapa 4), por eso
# aquí no hay proyecto por defecto.

provider "google" {
  region = var.primary_region
}

provider "google-beta" {
  region = var.primary_region
}
