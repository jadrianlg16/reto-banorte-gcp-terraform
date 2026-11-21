# Credenciales: la cuenta de servicio de la etapa (<prefix>-tf-4-projects) por Workload Identity
# Federation en el pipeline (§6.3), o Application Default Credentials en una ejecución manual.
# Sin llaves JSON ni proyecto fijo: cada recurso declara su proyecto.

provider "google" {
  region = var.primary_region
}

# google_project_service_identity (creación de agentes de servicio) solo existe en google-beta.
provider "google-beta" {
  region = var.primary_region
}
