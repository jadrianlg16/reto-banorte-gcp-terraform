terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

# Valores de ejemplo: organización, carpeta, proyectos y correos son marcadores.
module "iam" {
  source = "../.."

  bindings = [
    {
      scope    = "organization"
      resource = "organizations/000000000000"
      role     = "roles/iam.securityReviewer"
      member   = "group:example-auditors@example.com"
    },
    {
      scope    = "folder"
      resource = "folders/000000000000"
      role     = "roles/viewer"
      member   = "group:example-developers@example.com"
    },
    {
      scope    = "project"
      resource = "example-project-id"
      role     = "roles/logging.viewer"
      member   = "serviceAccount:example-sa@example-project-id.iam.gserviceaccount.com"
    },
    {
      scope    = "subnetwork"
      resource = "projects/example-host-project/regions/us-central1/subnetworks/example-subnet"
      role     = "roles/compute.networkUser"
      member   = "serviceAccount:example-sa@example-project-id.iam.gserviceaccount.com"
    },
    {
      key      = "state-writer-1-org"
      scope    = "storage_bucket"
      resource = "example-state-bucket"
      role     = "roles/storage.objectAdmin"
      member   = "serviceAccount:example-sa@example-project-id.iam.gserviceaccount.com"
      condition = {
        title      = "solo-prefijo-1-org"
        expression = "resource.name.startsWith(\"projects/_/buckets/example-state-bucket/objects/1-org/\")"
      }
    },
  ]
}

output "members" {
  description = "Miembros con algún rol."
  value       = module.iam.members
}
