# Estado remoto (§6.1): solo el prefijo; el bucket llega con
#   terraform init -backend-config="bucket=<bucket de estado>"
terraform {
  backend "gcs" {
    prefix = "5-workloads/qa"
  }
}
