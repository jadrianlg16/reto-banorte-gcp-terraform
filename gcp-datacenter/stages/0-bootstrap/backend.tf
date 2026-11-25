# Estado remoto (§6.1). El bucket llega por
#   terraform init -backend-config="bucket=<state_bucket>"
#
# Primera ejecución: el bucket todavía no existe. Se copia backend_override.tf.example a
# backend_override.tf (Terraform lo fusiona y reemplaza este bloque por un backend local),
# se aplica, se borra el override y se migra con terraform init -migrate-state. Ver README.
terraform {
  backend "gcs" {
    prefix = "0-bootstrap"
  }
}
