# Pruebas de la regla 8: IAM a `allUsers` o `allAuthenticatedUsers`.
package main

test_public_sa_and_group_passes if {
	plan := mk_plan([
		mk_create("module.cloud_run.google_cloud_run_v2_service_iam_member.invoker[\"lb\"]", "google_cloud_run_v2_service_iam_member", {
			"name": "bnt-dev-app-run-usc1",
			"location": "us-central1",
			"role": "roles/run.invoker",
			"member": "serviceAccount:bnt-dev-app-run@example-project.iam.gserviceaccount.com",
		}),
		mk_create("google_secret_manager_secret_iam_member.reader", "google_secret_manager_secret_iam_member", {
			"secret_id": "projects/example-project/secrets/bnt-dev-sec-db-config",
			"role": "roles/secretmanager.secretAccessor",
			"member": "group:platform-devops@example.com",
		}),
	])
	count(all_denials(plan)) == 0
}

# Caso de la revisión de seguridad: secreto abierto a allUsers.
test_public_secret_all_users_denied if {
	rc := mk_create("google_secret_manager_secret_iam_member.public", "google_secret_manager_secret_iam_member", {
		"secret_id": "projects/000000000000/secrets/bnt-dev-db",
		"role": "roles/secretmanager.secretAccessor",
		"member": "allUsers",
	})
	rule_denials(mk_plan([rc]), "iam_public_principal") == {
		"[iam_public_principal] google_secret_manager_secret_iam_member.public: asigna un rol a allUsers: ningún recurso se abre a principales públicos (allUsers, allAuthenticatedUsers)",
	}
}

# Caso de la revisión de seguridad: rol de proyecto para allAuthenticatedUsers.
test_public_project_all_authenticated_denied if {
	rc := mk_create("google_project_iam_member.external", "google_project_iam_member", {
		"project": "example-project",
		"role": "roles/cloudsql.client",
		"member": "allAuthenticatedUsers",
	})
	count(rule_denials(mk_plan([rc]), "iam_public_principal")) == 1
}

test_public_binding_members_denied if {
	rc := mk_create("google_cloud_run_v2_service_iam_binding.invoker", "google_cloud_run_v2_service_iam_binding", {
		"name": "bnt-dev-app-run-usc1",
		"location": "us-central1",
		"role": "roles/run.invoker",
		"members": ["serviceAccount:bnt-dev-app-run@example-project.iam.gserviceaccount.com", "allUsers"],
	})
	denials := rule_denials(mk_plan([rc]), "iam_public_principal")
	count(denials) == 1
	some msg in denials
	contains(msg, "allUsers")
}

test_public_policy_data_denied if {
	policy := json.marshal({"bindings": [
		{"role": "roles/cloudkms.cryptoKeyEncrypterDecrypter", "members": ["serviceAccount:app@example-project.iam.gserviceaccount.com"]},
		{"role": "roles/cloudkms.viewer", "members": ["allAuthenticatedUsers"]},
	]})
	rc := mk_create("google_kms_crypto_key_iam_policy.this", "google_kms_crypto_key_iam_policy", {
		"crypto_key_id": "projects/example-project/locations/us-central1/keyRings/kr/cryptoKeys/k",
		"policy_data": policy,
	})
	count(rule_denials(mk_plan([rc]), "iam_public_principal")) == 1
}

test_public_mixed_case_denied if {
	rc := mk_create("google_pubsub_topic_iam_member.this", "google_pubsub_topic_iam_member", {
		"topic": "projects/example-project/topics/bnt-dev-ops-events",
		"role": "roles/pubsub.subscriber",
		"member": "AllUsers",
	})
	count(rule_denials(mk_plan([rc]), "iam_public_principal")) == 1
}

# Cloud Storage lo rechaza la regla 1, una sola vez.
test_public_storage_left_to_bucket_rule if {
	rc := mk_create("google_storage_bucket_iam_member.public", "google_storage_bucket_iam_member", {
		"bucket": "bnt-dev-data-app",
		"role": "roles/storage.objectViewer",
		"member": "allUsers",
	})
	plan := mk_plan([rc])
	count(rule_denials(plan, "iam_public_principal")) == 0
	count(rule_denials(plan, "bucket_public_access")) == 1
}

test_public_unknown_member_not_denied if {
	rc := mk_change(
		"google_project_iam_member.runtime", "google_project_iam_member", ["create"], {
			"project": "example-project",
			"role": "roles/logging.logWriter",
		},
		{"member": true},
	)
	count(all_denials(mk_plan([rc]))) == 0
}

test_public_pure_delete_ignored if {
	rc := mk_change("google_project_iam_member.old", "google_project_iam_member", ["delete"], null, {})
	rc2 := object.union(rc, {"change": {"before": {"project": "example-project", "role": "roles/viewer", "member": "allUsers"}}})
	count(all_denials(mk_plan([rc2]))) == 0
}
