# Ejercicio 1: crea un archivo con init, plan y apply y comprueba la idempotencia.
# Código de la diapositiva del socio formador. Única diferencia: la ruta.
# La diapositiva usa "/root/saludo.txt" (laboratorio Linux de KodeKloud); aquí se usa
# path.module para que funcione igual en Windows y macOS sin escribir fuera del repo.

variable "mensaje" {
  default = "Hola TEC"
}

resource "local_file" "saludo" {
  filename = "${path.module}/saludo.txt"
  content  = var.mensaje
}

output "ruta" {
  value = local_file.saludo.filename
}
