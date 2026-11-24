# Estado remoto (ADR 0029 §2): solo el prefijo; el bucket llega con
#   terraform init -backend-config="bucket=<bucket de estado>"
terraform {
  backend "gcs" {
    prefix = "3-workloads/qa"
  }
}
