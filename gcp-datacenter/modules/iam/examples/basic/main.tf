terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

# Valores de ejemplo: organización, proyecto y correos son marcadores.
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
      scope    = "project"
      resource = "example-project-id"
      role     = "roles/viewer"
      member   = "group:example-developers@example.com"
    },
    {
      key      = "storage-admin-dev"
      scope    = "project"
      resource = "example-project-id"
      role     = "roles/storage.admin"
      member   = "serviceAccount:example-sa@example-project-id.iam.gserviceaccount.com"
      condition = {
        title      = "solo-buckets-dev"
        expression = "resource.name.startsWith(\"projects/_/buckets/example-dev-\")"
      }
    },
    {
      scope    = "subnetwork"
      resource = "projects/example-project-id/regions/us-central1/subnetworks/example-subnet"
      role     = "roles/compute.networkUser"
      member   = "serviceAccount:example-sa@example-project-id.iam.gserviceaccount.com"
    },
    {
      key      = "state-writer-1-base"
      scope    = "storage_bucket"
      resource = "example-state-bucket"
      role     = "roles/storage.objectAdmin"
      member   = "serviceAccount:example-sa@example-project-id.iam.gserviceaccount.com"
      condition = {
        title      = "solo-prefijo-1-base"
        expression = "resource.name.startsWith(\"projects/_/buckets/example-state-bucket/objects/1-base/\")"
      }
    },
  ]
}

output "members" {
  description = "Miembros con algún rol."
  value       = module.iam.members
}
