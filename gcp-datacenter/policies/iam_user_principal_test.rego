# Pruebas de la regla 7: IAM a `user:`.
package main

test_iam_group_and_sa_passes if {
	plan := mk_plan([
		mk_create("google_project_iam_member.viewer", "google_project_iam_member", {
			"project": "example-project",
			"role": "roles/viewer",
			"member": "group:auditors@example.com",
		}),
		mk_create("google_folder_iam_binding.admins", "google_folder_iam_binding", {
			"folder": "folders/000000000000",
			"role": "roles/resourcemanager.folderViewer",
			"members": ["group:platform-devops@example.com", "serviceAccount:bnt-tf-1-org@example-project.iam.gserviceaccount.com"],
		}),
	])
	count(all_denials(plan)) == 0
}

test_iam_project_member_user_denied if {
	rc := mk_create("module.iam.google_project_iam_member.this[\"viewer\"]", "google_project_iam_member", {
		"project": "example-project",
		"role": "roles/viewer",
		"member": "user:someone@example.com",
	})
	rule_denials(mk_plan([rc]), "iam_user_principal") == {
		"[iam_user_principal] module.iam.google_project_iam_member.this[\"viewer\"]: asigna un rol a user:someone@example.com: los roles se otorgan a grupos o cuentas de servicio, nunca a user:",
	}
}

test_iam_binding_user_denied if {
	rc := mk_create("google_kms_crypto_key_iam_binding.this", "google_kms_crypto_key_iam_binding", {
		"crypto_key_id": "projects/example-project/locations/us-central1/keyRings/kr/cryptoKeys/k",
		"role": "roles/cloudkms.cryptoKeyEncrypterDecrypter",
		"members": ["group:security-admins@example.com", "user:someone@example.com"],
	})
	count(rule_denials(mk_plan([rc]), "iam_user_principal")) == 1
}

test_iam_policy_data_user_denied if {
	policy := json.marshal({"bindings": [
		{"role": "roles/secretmanager.secretAccessor", "members": ["serviceAccount:app@example-project.iam.gserviceaccount.com"]},
		{"role": "roles/secretmanager.admin", "members": ["user:someone@example.com"]},
	]})
	rc := mk_create("google_secret_manager_secret_iam_policy.this", "google_secret_manager_secret_iam_policy", {
		"secret_id": "bnt-dev-sec-db-config",
		"policy_data": policy,
	})
	count(rule_denials(mk_plan([rc]), "iam_user_principal")) == 1
}

test_iam_uppercase_prefix_denied if {
	rc := mk_create("google_organization_iam_member.this", "google_organization_iam_member", {
		"org_id": "000000000000",
		"role": "roles/viewer",
		"member": "User:someone@example.com",
	})
	count(rule_denials(mk_plan([rc]), "iam_user_principal")) == 1
}

# Principal calculado en el apply (correo de una cuenta creada en el mismo plan): no se lee.
test_iam_unknown_member_not_denied if {
	rc := mk_change(
		"google_service_account_iam_member.wif", "google_service_account_iam_member", ["create"], {
			"service_account_id": "projects/example-project/serviceAccounts/sa@example-project.iam.gserviceaccount.com",
			"role": "roles/iam.workloadIdentityUser",
		},
		{"member": true},
	)
	count(all_denials(mk_plan([rc]))) == 0
}

test_iam_pure_delete_ignored if {
	rc := mk_change("google_project_iam_member.legacy", "google_project_iam_member", ["delete"], null, {})
	count(all_denials(mk_plan([rc]))) == 0
}
