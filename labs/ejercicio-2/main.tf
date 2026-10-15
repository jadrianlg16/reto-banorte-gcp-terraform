# Ejercicio 2: genera tres archivos con for_each y observa las dependencias.
# Código de la diapositiva del socio formador. Única diferencia: la ruta.
# La diapositiva usa "/root/${each.key}.txt" (laboratorio Linux de KodeKloud); aquí se usa
# path.module para que funcione igual en Windows y macOS sin escribir fuera del repo.

resource "random_pet" "nombre" {
  length = 2
}

resource "local_file" "equipo" {
  for_each = toset(["front", "back", "db"])
  filename = "${path.module}/${each.key}.txt"
  content  = random_pet.nombre.id
}

output "archivos" {
  value = keys(local_file.equipo)
}
