# Estado remoto (§6.1). El bucket llega por
#   terraform init -backend-config="bucket=<state_bucket>"
terraform {
  backend "gcs" {
    prefix = "1-org"
  }
}
