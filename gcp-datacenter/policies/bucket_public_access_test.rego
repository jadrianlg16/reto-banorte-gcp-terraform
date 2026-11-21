# Pruebas de la regla 1: bucket público.
package main

good_bucket := {
	"name": "bnt-dev-data-bucket",
	"location": "US-CENTRAL1",
	"public_access_prevention": "enforced",
	"uniform_bucket_level_access": true,
	"labels": mk_labels,
	"terraform_labels": mk_labels,
}

test_bucket_enforced_passes if {
	plan := mk_plan([mk_create("google_storage_bucket.this", "google_storage_bucket", good_bucket)])
	count(all_denials(plan)) == 0
}

test_bucket_inherited_denied if {
	after := object.union(good_bucket, {"public_access_prevention": "inherited"})
	plan := mk_plan([mk_create("google_storage_bucket.this", "google_storage_bucket", after)])
	rule_denials(plan, "bucket_public_access") == {
		"[bucket_public_access] google_storage_bucket.this: el bucket debe declarar public_access_prevention = \"enforced\" (valor en el plan: inherited)",
	}
}

# Sin declarar, el atributo es calculado: aparece solo en after_unknown.
test_bucket_unknown_prevention_denied if {
	after := object.remove(good_bucket, ["public_access_prevention"])
	rc := mk_change("module.storage.google_storage_bucket.this", "google_storage_bucket", ["create"], after, {"public_access_prevention": true})
	denials := rule_denials(mk_plan([rc]), "bucket_public_access")
	count(denials) == 1
	some msg in denials
	contains(msg, "module.storage.google_storage_bucket.this")
	contains(msg, "desconocido hasta el apply")
}

test_bucket_pure_delete_ignored if {
	after := object.union(good_bucket, {"public_access_prevention": "inherited"})
	rc := mk_change("google_storage_bucket.old", "google_storage_bucket", ["delete"], null, {})
	rc2 := object.union(rc, {"change": {"before": after}})
	count(all_denials(mk_plan([rc2]))) == 0
}

test_bucket_replace_checked if {
	after := object.union(good_bucket, {"public_access_prevention": "inherited"})
	rc := mk_change("google_storage_bucket.this", "google_storage_bucket", ["delete", "create"], after, {})
	count(rule_denials(mk_plan([rc]), "bucket_public_access")) == 1
}

test_bucket_iam_member_all_users_denied if {
	rc := mk_create("google_storage_bucket_iam_member.public", "google_storage_bucket_iam_member", {
		"bucket": "bnt-dev-data-bucket",
		"role": "roles/storage.objectViewer",
		"member": "allUsers",
	})
	count(rule_denials(mk_plan([rc]), "bucket_public_access")) == 1
}

test_bucket_iam_binding_all_authenticated_denied if {
	rc := mk_create("google_storage_bucket_iam_binding.public", "google_storage_bucket_iam_binding", {
		"bucket": "bnt-dev-data-bucket",
		"role": "roles/storage.objectViewer",
		"members": ["group:data-readers@example.com", "allAuthenticatedUsers"],
	})
	count(rule_denials(mk_plan([rc]), "bucket_public_access")) == 1
}

test_bucket_iam_policy_all_users_denied if {
	policy := json.marshal({"bindings": [{"role": "roles/storage.objectViewer", "members": ["allUsers"]}]})
	rc := mk_create("google_storage_bucket_iam_policy.this", "google_storage_bucket_iam_policy", {
		"bucket": "bnt-dev-data-bucket",
		"policy_data": policy,
	})
	count(rule_denials(mk_plan([rc]), "bucket_public_access")) == 1
}

test_bucket_iam_group_passes if {
	rc := mk_create("google_storage_bucket_iam_member.readers", "google_storage_bucket_iam_member", {
		"bucket": "bnt-dev-data-bucket",
		"role": "roles/storage.objectViewer",
		"member": "group:data-readers@example.com",
	})
	count(all_denials(mk_plan([rc]))) == 0
}

test_bucket_acl_all_users_denied if {
	rc := mk_create("google_storage_bucket_acl.this", "google_storage_bucket_acl", {
		"bucket": "bnt-dev-data-bucket",
		"role_entity": ["OWNER:project-owners-123456789012", "READER:allUsers"],
	})
	count(rule_denials(mk_plan([rc]), "bucket_public_access")) == 1
}

test_bucket_access_control_all_users_denied if {
	rc := mk_create("google_storage_bucket_access_control.this", "google_storage_bucket_access_control", {
		"bucket": "bnt-dev-data-bucket",
		"role": "READER",
		"entity": "allUsers",
	})
	count(rule_denials(mk_plan([rc]), "bucket_public_access")) == 1
}
