output "instance_group" {
  description = "URL del grupo de instancias del MIG regional; es el backend que recibe el módulo load-balancer."
  value       = google_compute_region_instance_group_manager.this.instance_group
}

output "health_check_id" {
  description = "ID de la verificación de salud global de la autocuración."
  value       = google_compute_health_check.this.id
}

output "health_check_self_link" {
  description = "Self link de la verificación de salud global."
  value       = google_compute_health_check.this.self_link
}

output "instance_group_manager_id" {
  description = "ID del MIG regional."
  value       = google_compute_region_instance_group_manager.this.id
}

output "instance_group_manager_name" {
  description = "Nombre del MIG regional."
  value       = google_compute_region_instance_group_manager.this.name
}

output "instance_template_self_link" {
  description = "Self link de la plantilla de instancias vigente."
  value       = google_compute_region_instance_template.this.self_link
}

output "subnetwork" {
  description = "Subred de la interfaz de la plantilla (la que se configuró en el recurso)."
  value       = google_compute_region_instance_template.this.network_interface[0].subnetwork
}

output "kms_key" {
  description = "Llave KMS del disco de arranque de la plantilla."
  value       = google_compute_region_instance_template.this.disk[0].disk_encryption_key[0].kms_key_self_link
}

output "named_ports" {
  description = "Puertos con nombre del grupo (nombre → puerto)."
  value       = var.named_ports
}
