# Pruebas de la regla 6: rotación de llaves KMS.
package main

kms_key(extra) := object.union(
	{
		"name": "bnt-dev-sec-key-sql",
		"key_ring": "projects/example-project/locations/us-central1/keyRings/bnt-dev-sec-kr-usc1",
		"purpose": "ENCRYPT_DECRYPT",
		"rotation_period": "7776000s",
		"labels": mk_labels,
		"terraform_labels": mk_labels,
	},
	extra,
)

test_kms_90_days_passes if {
	rc := mk_create("google_kms_crypto_key.this", "google_kms_crypto_key", kms_key({}))
	count(all_denials(mk_plan([rc]))) == 0
}

test_kms_30_days_passes if {
	rc := mk_create("google_kms_crypto_key.this", "google_kms_crypto_key", kms_key({"rotation_period": "2592000s"}))
	count(all_denials(mk_plan([rc]))) == 0
}

test_kms_too_long_denied if {
	rc := mk_create("module.kms.google_kms_crypto_key.this[\"sql\"]", "google_kms_crypto_key", kms_key({"rotation_period": "7776001s"}))
	rule_denials(mk_plan([rc]), "kms_rotation") == {
		"[kms_rotation] module.kms.google_kms_crypto_key.this[\"sql\"]: rotation_period 7776001s supera el máximo de 7776000s (90 días)",
	}
}

test_kms_missing_rotation_denied if {
	after := object.remove(kms_key({}), ["rotation_period"])
	rc := mk_create("google_kms_crypto_key.this", "google_kms_crypto_key", after)
	denials := rule_denials(mk_plan([rc]), "kms_rotation")
	count(denials) == 1
	some msg in denials
	contains(msg, "sin definir")
}

# Sin `purpose` explícito el proveedor usa ENCRYPT_DECRYPT.
test_kms_default_purpose_missing_rotation_denied if {
	after := object.remove(kms_key({}), ["rotation_period", "purpose"])
	rc := mk_create("google_kms_crypto_key.this", "google_kms_crypto_key", after)
	count(rule_denials(mk_plan([rc]), "kms_rotation")) == 1
}

test_kms_rotation_unknown_denied if {
	after := object.remove(kms_key({}), ["rotation_period"])
	rc := mk_change("google_kms_crypto_key.this", "google_kms_crypto_key", ["create"], after, {"rotation_period": true})
	denials := rule_denials(mk_plan([rc]), "kms_rotation")
	count(denials) == 1
	some msg in denials
	contains(msg, "desconocido hasta el apply")
}

test_kms_bad_format_denied if {
	rc := mk_create("google_kms_crypto_key.this", "google_kms_crypto_key", kms_key({"rotation_period": "90d"}))
	count(rule_denials(mk_plan([rc]), "kms_rotation")) == 1
}

test_kms_asymmetric_without_rotation_passes if {
	after := object.remove(kms_key({"purpose": "ASYMMETRIC_SIGN"}), ["rotation_period"])
	rc := mk_create("google_kms_crypto_key.signing", "google_kms_crypto_key", after)
	count(all_denials(mk_plan([rc]))) == 0
}
