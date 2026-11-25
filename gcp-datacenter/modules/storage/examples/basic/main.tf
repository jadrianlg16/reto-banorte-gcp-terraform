terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

locals {
  labels = {
    env         = "prod"
    app         = "app"
    owner       = "example-team"
    cost_center = "example-cc"
    managed_by  = "terraform"
  }
}

# Bucket regional. Todos los valores son de ejemplo.
module "bucket_regional" {
  source = "../.."

  project_id  = "example-prod-app"
  prefix      = "bnt"
  environment = "prod"
  name        = "assets"
  name_suffix = "-x1"
  location    = "us-central1"
  kms_key     = "projects/example-common-security/locations/us-central1/keyRings/bnt-prod-sec-usc1/cryptoKeys/storage"
  labels      = local.labels
}

# Bucket de doble región con turbo replication (DR de prod). La llave vive en la multirregión us.
module "bucket_dual" {
  source = "../.."

  project_id  = "example-prod-app"
  prefix      = "bnt"
  environment = "prod"
  name        = "docs"
  name_suffix = "-x1"
  location    = "us"
  dual_region = { regions = ["us-central1", "us-east4"] }
  kms_key     = "projects/example-common-security/locations/us/keyRings/bnt-prod-sec-us/cryptoKeys/storage"
  labels      = local.labels
}

output "bucket_names" {
  description = "Nombres de los buckets de ejemplo."
  value = {
    regional = module.bucket_regional.bucket_name
    dual     = module.bucket_dual.bucket_name
  }
}
