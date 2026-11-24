# Credenciales (ADR 0029 §3): en el pipeline, la cuenta de las cargas del entorno
# (<prefix>-tf-wl-<env>) por Workload Identity Federation en el apply y la de solo lectura
# (<prefix>-tf-read) en los plan; Application Default Credentials en una ejecución manual. Sin
# llaves JSON. Todo vive en el proyecto único (project_id); cada recurso lo declara igual.

provider "google" {
  project = var.project_id
  region  = var.primary_region
}

provider "google-beta" {
  project = var.project_id
  region  = var.primary_region
}
