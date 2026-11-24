# Pruebas de la regla 10: acceso uniforme a nivel de bucket. `good_bucket` está en
# bucket_public_access_test.rego.
package main

test_uniform_true_passes if {
	plan := mk_plan([mk_create("google_storage_bucket.this", "google_storage_bucket", good_bucket)])
	count(all_denials(plan)) == 0
}

# Caso de la revisión de seguridad (con la ubicación permitida, para aislar la regla).
test_uniform_false_denied if {
	after := with_fields(good_bucket, {"uniform_bucket_level_access": false})
	rc := mk_create("google_storage_bucket.b", "google_storage_bucket", after)
	plan := mk_plan([rc])
	rule_denials(plan, "bucket_uniform_access") == {
		"[bucket_uniform_access] google_storage_bucket.b: el bucket debe declarar uniform_bucket_level_access = true (valor en el plan: false)",
	}
	count(all_denials(plan)) == 1
}

# Sin declarar, el atributo es calculado: aparece solo en after_unknown (comprobado con un plan
# real de google 6.50.0, fixtures/bucket_uniform_access_fail_real_sin_declarar.json).
test_uniform_unknown_denied if {
	after := object.remove(good_bucket, ["uniform_bucket_level_access"])
	rc := mk_change("module.storage.google_storage_bucket.this", "google_storage_bucket", ["create"], after, {"uniform_bucket_level_access": true})
	denials := rule_denials(mk_plan([rc]), "bucket_uniform_access")
	count(denials) == 1
	some msg in denials
	contains(msg, "desconocido hasta el apply")
}

test_uniform_missing_denied if {
	after := object.remove(good_bucket, ["uniform_bucket_level_access"])
	rc := mk_create("google_storage_bucket.this", "google_storage_bucket", after)
	denials := rule_denials(mk_plan([rc]), "bucket_uniform_access")
	count(denials) == 1
	some msg in denials
	contains(msg, "sin definir")
}

test_uniform_replace_checked if {
	after := with_fields(good_bucket, {"uniform_bucket_level_access": false})
	rc := mk_change("google_storage_bucket.this", "google_storage_bucket", ["delete", "create"], after, {})
	count(rule_denials(mk_plan([rc]), "bucket_uniform_access")) == 1
}

test_uniform_pure_delete_ignored if {
	rc := mk_change("google_storage_bucket.old", "google_storage_bucket", ["delete"], null, {})
	rc2 := object.union(rc, {"change": {"before": with_fields(good_bucket, {"uniform_bucket_level_access": false})}})
	count(all_denials(mk_plan([rc2]))) == 0
}
