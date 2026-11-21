variable "parent" {
  description = "Padre de las carpetas: \"organizations/<número>\" o \"folders/<número>\"."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^(organizations|folders)/[0-9]+$", var.parent))
    error_message = "parent debe tener la forma \"organizations/<número>\" o \"folders/<número>\"."
  }
}

variable "names" {
  description = "Nombres de las carpetas, uno por entorno de la convención de nombres: bootstrap, common, dev, qa o prod. Cada nombre es el nombre visible y la llave del mapa de salida."
  type        = set(string)
  nullable    = false

  validation {
    condition     = length(var.names) > 0
    error_message = "names debe tener al menos una carpeta."
  }
  validation {
    condition     = alltrue([for n in var.names : contains(["bootstrap", "common", "dev", "qa", "prod"], n)])
    error_message = "Cada carpeta corresponde a un entorno: bootstrap, common, dev, qa o prod."
  }
}

variable "deletion_protection" {
  description = "Si es true, Terraform no puede borrar las carpetas. Solo se apaga para desmontar un entorno de pruebas."
  type        = bool
  default     = true
  nullable    = false
}
