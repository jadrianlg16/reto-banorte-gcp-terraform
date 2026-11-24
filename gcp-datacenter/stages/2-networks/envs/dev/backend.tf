# El bucket llega por: terraform init -backend-config="bucket=<bucket de estado>"
terraform {
  backend "gcs" {
    prefix = "3-networks/dev"
  }
}
