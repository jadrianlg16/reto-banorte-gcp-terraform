# Se arma con una plantilla y no con f.name: así, aunque el número no se conozca en el plan,
# Terraform sabe que el valor empieza con "folders/" y quien lo consuma (por ejemplo,
# log-export) puede decidir el tipo de padre en el plan.
output "ids" {
  description = "Mapa nombre de carpeta → ID completo (\"folders/<número>\")."
  value       = { for k, f in google_folder.this : k => "folders/${f.folder_id}" }
}

output "folder_numbers" {
  description = "Mapa nombre de carpeta → número de carpeta (sin el prefijo \"folders/\")."
  value       = { for k, f in google_folder.this : k => f.folder_id }
}
