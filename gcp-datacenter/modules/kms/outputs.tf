output "keyring_id" {
  description = "ID del llavero (projects/<proyecto>/locations/<ubicación>/keyRings/<nombre>)."
  value       = google_kms_key_ring.this.id
}

output "keyring_name" {
  description = "Nombre corto del llavero."
  value       = google_kms_key_ring.this.name
}

output "key_ids" {
  description = "Mapa uso → ID de la llave (projects/.../keyRings/.../cryptoKeys/<nombre>), el formato que piden los argumentos de CMEK."
  value       = { for use, key in google_kms_crypto_key.this : use => key.id }
}

output "key_names" {
  description = "Mapa uso → nombre corto de la llave."
  value       = { for use, key in google_kms_crypto_key.this : use => key.name }
}

output "location" {
  description = "Ubicación del llavero y sus llaves."
  value       = google_kms_key_ring.this.location
}
