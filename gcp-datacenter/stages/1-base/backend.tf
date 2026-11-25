# Estado remoto (ADR 0029 §2): prefijo 1-base en el bucket de 0-bootstrap. El bucket llega por
#   terraform init -backend-config="bucket=<state_bucket>"
terraform {
  backend "gcs" {
    prefix = "1-base"
  }
}
