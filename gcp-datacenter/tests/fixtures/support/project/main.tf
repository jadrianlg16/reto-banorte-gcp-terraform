# Proyecto de una prueba de integración (helpers.NewTestProject). Crea un proyecto efímero o,
# con create_project = false, solo habilita APIs en un proyecto existente.
# Lo aplica y lo destruye Go; no lo llama ningún otro fixture.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {}

variable "create_project" {
  description = "true: crea el proyecto project_id. false: usa uno existente y solo habilita APIs."
  type        = bool
}

variable "project_id" {
  description = "ID del proyecto (efímero o existente)."
  type        = string
}

variable "folder_id" {
  description = "Número de la carpeta del proyecto efímero. Vacío: se usa org_id."
  type        = string
  default     = ""
}

variable "org_id" {
  description = "Número de la organización del proyecto efímero si no hay carpeta."
  type        = string
  default     = ""
}

variable "billing_account" {
  description = "Cuenta de facturación del proyecto efímero."
  type        = string
  default     = ""
}

variable "apis" {
  description = "APIs que necesita la prueba."
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Etiquetas del proyecto efímero (las cinco obligatorias y terratest_run)."
  type        = map(string)
}

resource "google_project" "this" {
  count = var.create_project ? 1 : 0

  project_id          = var.project_id
  name                = var.project_id
  folder_id           = var.folder_id == "" ? null : var.folder_id
  org_id              = var.folder_id == "" ? var.org_id : null
  billing_account     = var.billing_account
  auto_create_network = false
  deletion_policy     = "DELETE"
  labels              = var.labels
}

resource "google_project_service" "this" {
  for_each = toset(var.apis)

  project = var.create_project ? google_project.this[0].project_id : var.project_id
  service = each.value

  # En un proyecto reutilizado no se apagan APIs que otras pruebas pueden estar usando; en uno
  # efímero no hace falta porque el proyecto se borra.
  disable_on_destroy         = false
  disable_dependent_services = false
}

data "google_project" "this" {
  project_id = var.create_project ? google_project.this[0].project_id : var.project_id

  depends_on = [google_project_service.this]
}

output "project_id" {
  description = "ID del proyecto de la prueba."
  value       = data.google_project.this.project_id
}

output "project_number" {
  description = "Número del proyecto de la prueba (para armar correos de agentes de servicio)."
  value       = data.google_project.this.number
}
