# Interfaz con las etapas siguientes (§7.2): nombres y tipos fijos.

output "kms_key_ids" {
  description = "Mapa [entorno][ubicación][uso] → ID de la llave KMS. Ubicaciones: primary_region, dr_region y us (en us solo storage y backup)."
  value = {
    for e in var.environments : e => {
      for l in local.locations : l => module.kms["${e}/${l}"].key_ids
    }
  }
}

output "secret_ids" {
  description = "Mapa [entorno][nombre] → ID del secreto (projects/<proyecto>/secrets/<id>). Un entorno sin secretos tiene un mapa vacío."
  value = {
    for e in var.environments : e => try(module.secrets[e].secret_ids, {})
  }
}

output "access_policy_id" {
  description = "ID numérico de la política de Access Context Manager (creada o recibida)."
  value       = module.vpc_sc.access_policy_id
}

output "perimeter_name" {
  description = "Nombre completo del perímetro de prod (accessPolicies/<política>/servicePerimeters/<nombre>)."
  value       = module.vpc_sc.perimeter_name
}

output "vpc_sc_enforced" {
  description = "true si el perímetro está forzado; false en dry-run. La etapa 4 elige con él el recurso de alta de proyectos."
  value       = module.vpc_sc.enforced
}

# --- Salidas adicionales ------------------------------------------------------------------

output "keyring_ids" {
  description = "Mapa [entorno][ubicación] → ID del llavero."
  value = {
    for e in var.environments : e => {
      for l in local.locations : l => module.kms["${e}/${l}"].keyring_id
    }
  }
}
