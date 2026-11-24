terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

# Valores de ejemplo: proyecto y cliente de directorio son marcadores. El módulo solo se usa
# cuando el proyecto está dentro de una organización (ADR 0029 §1).
module "org" {
  source = "../.."

  project_id                   = "example-project-id"
  allowed_regions              = ["us-central1", "us-east4"]
  additional_allowed_locations = ["us"]
  directory_customer_id        = "C00000000"
}

output "policy_names" {
  description = "Políticas de organización aplicadas al proyecto."
  value       = module.org.policy_names
}
