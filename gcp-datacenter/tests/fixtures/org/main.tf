# Fixture de integración del módulo org (TEST_ALLOW_ORG=true y TERRATEST_ORG_ID): aplica las
# políticas de organización al proyecto de la prueba (padre projects/<id>, ADR 0029 §1), como
# hace 1-base cuando el proyecto está dentro de una organización. El destroy borra las
# políticas y el proyecto vuelve a heredar las de su padre. Mientras dura la prueba las
# políticas valen para todo el proyecto: por eso TestOrg no corre en paralelo con las demás.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {}

variable "project_id" {
  description = "Proyecto de la prueba (padre de las políticas)."
  type        = string
}

variable "region" {
  description = "Región permitida por gcp.resourceLocations."
  type        = string
}

variable "dr_region" {
  description = "Segunda región permitida."
  type        = string
}

variable "directory_customer_id" {
  description = "Cliente de Cloud Identity (Cxxxxxxxx) para iam.allowedPolicyMemberDomains. null: esa política no se crea."
  type        = string
  default     = null
}

module "org" {
  source = "../../../modules/org"

  project_id                   = var.project_id
  allowed_regions              = [var.region, var.dr_region]
  additional_allowed_locations = ["us"]
  directory_customer_id        = var.directory_customer_id
}

output "policy_names" {
  description = "Políticas aplicadas."
  value       = module.org.policy_names
}

output "policy_parent" {
  description = "Recurso donde se aplicaron (projects/<id>)."
  value       = module.org.policy_parent
}
