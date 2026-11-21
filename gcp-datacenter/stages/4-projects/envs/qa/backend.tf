# Solo el prefijo (§6.1); el bucket llega por
#   terraform init -backend-config="bucket=<state_bucket>"
terraform {
  backend "gcs" {
    prefix = "4-projects/qa"
  }
}
