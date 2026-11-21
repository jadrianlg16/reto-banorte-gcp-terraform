# Una carpeta por entorno bajo el mismo padre. La llave del for_each es el nombre de la
# carpeta, que es conocido en el plan y no cambia si se agregan o quitan otras carpetas.
resource "google_folder" "this" {
  for_each = var.names

  display_name        = each.value
  parent              = var.parent
  deletion_protection = var.deletion_protection
}
