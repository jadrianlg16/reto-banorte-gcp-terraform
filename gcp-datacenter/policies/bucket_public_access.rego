# Regla 1 (§9.1): bucket sin `public_access_prevention = "enforced"` o con acceso para
# `allUsers` / `allAuthenticatedUsers`.
#
# Valores desconocidos: `public_access_prevention` es opcional y calculado; si no se declara,
# el plan lo deja desconocido y la regla lo rechaza (debe ser una constante en el código).
# Un principal de IAM desconocido hasta el apply no se puede revisar aquí.
package main

public_principals := {"allusers", "allauthenticatedusers"}

# Asignaciones de IAM sobre Cloud Storage (bucket y carpeta administrada).
is_storage_iam_type(type) if regex.match(`^google_storage_[a-z0-9_]+_iam_(member|binding|policy)$`, type)

# ACL heredadas: una sola entidad (`entity`) o una lista "ROL:entidad" (`role_entity`).
storage_acl_entity_types := {
	"google_storage_bucket_access_control",
	"google_storage_default_object_access_control",
	"google_storage_object_access_control",
}

storage_acl_list_types := {
	"google_storage_bucket_acl",
	"google_storage_default_object_acl",
	"google_storage_object_acl",
}

deny contains msg if {
	some rc in planned_resources
	rc.type == "google_storage_bucket"
	object.get(rc.change.after, "public_access_prevention", null) != "enforced"
	msg := message("bucket_public_access", rc, sprintf(
		"el bucket debe declarar public_access_prevention = \"enforced\" (valor en el plan: %s)",
		[value_text(rc, ["public_access_prevention"])],
	))
}

deny contains msg if {
	some rc in planned_resources
	is_storage_iam_type(rc.type)
	some member in iam_members(rc.change.after)
	lower(member) in public_principals
	msg := message("bucket_public_access", rc, sprintf(
		"la asignación de IAM sobre Cloud Storage otorga acceso público a %s",
		[member],
	))
}

deny contains msg if {
	some rc in planned_resources
	rc.type in storage_acl_entity_types
	entity := rc.change.after.entity
	is_string(entity)
	lower(entity) in public_principals
	msg := message("bucket_public_access", rc, sprintf("la ACL otorga acceso público a %s", [entity]))
}

deny contains msg if {
	some rc in planned_resources
	rc.type in storage_acl_list_types
	some role_entity in rc.change.after.role_entity
	is_string(role_entity)
	parts := split(role_entity, ":")
	lower(parts[count(parts) - 1]) in public_principals
	msg := message("bucket_public_access", rc, sprintf("la ACL otorga acceso público (%s)", [role_entity]))
}
