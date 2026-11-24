# Regla 10 (ADR 0029 §1; reemplaza `storage.uniformBucketLevelAccess`): bucket sin acceso
# uniforme a nivel de bucket.
#
# Con acceso uniforme, el acceso al bucket y a sus objetos solo se da por IAM y las ACL quedan
# desactivadas. La regla 1 (`bucket_public_access`) revisa `public_access_prevention` y las ACL o
# asignaciones públicas, no este atributo. Los tres buckets del código (módulos `storage` y
# `log-export` y el bucket de estado de `0-bootstrap`) lo declaran en `true`.
#
# Valores desconocidos: si el atributo no se declara, el plan lo deja desconocido y se rechaza:
# debe ser `true` en el código.
package main

deny contains msg if {
	some rc in planned_resources
	rc.type == "google_storage_bucket"
	object.get(rc.change.after, "uniform_bucket_level_access", null) != true
	msg := message("bucket_uniform_access", rc, sprintf(
		"el bucket debe declarar uniform_bucket_level_access = true (valor en el plan: %s)",
		[value_text(rc, ["uniform_bucket_level_access"])],
	))
}
