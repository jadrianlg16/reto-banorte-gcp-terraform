# Pruebas de la regla 9: llaves de cuentas de servicio.
package main

sa_key_after := {"service_account_id": "projects/example-project/serviceAccounts/bnt-dev-app-run@example-project.iam.gserviceaccount.com"}

test_sa_without_key_passes if {
	plan := mk_plan([
		mk_create("google_service_account.runtime[\"run\"]", "google_service_account", {"account_id": "bnt-dev-app-run"}),
		mk_create("google_service_account_iam_member.wif", "google_service_account_iam_member", {
			"service_account_id": "projects/example-project/serviceAccounts/bnt-dev-app-workload@example-project.iam.gserviceaccount.com",
			"role": "roles/iam.workloadIdentityUser",
			"member": "serviceAccount:example-project.svc.id.goog[app-dev/app]",
		}),
	])
	count(all_denials(plan)) == 0
}

# Caso de la revisión de seguridad.
test_sa_key_create_denied if {
	rc := mk_create("google_service_account_key.k", "google_service_account_key", sa_key_after)
	rule_denials(mk_plan([rc]), "service_account_key") == {
		"[service_account_key] google_service_account_key.k: llave de la cuenta projects/example-project/serviceAccounts/bnt-dev-app-run@example-project.iam.gserviceaccount.com: las llaves de cuentas de servicio están prohibidas (usar WIF o la cuenta adjunta al recurso)",
	}
}

# Llave subida (iam.disableServiceAccountKeyUpload): el mismo tipo.
test_sa_key_upload_denied if {
	after := object.union(sa_key_after, {"public_key_data": "LS0tLS1CRUdJTi1FWEFNUExFLS0tLS0="})
	rc := mk_create("module.app.google_service_account_key.uploaded", "google_service_account_key", after)
	count(rule_denials(mk_plan([rc]), "service_account_key")) == 1
}

# Cuenta creada en el mismo plan: el mensaje lo dice.
test_sa_key_unknown_account_denied if {
	rc := mk_change("google_service_account_key.k", "google_service_account_key", ["create"], {}, {"service_account_id": true})
	denials := rule_denials(mk_plan([rc]), "service_account_key")
	count(denials) == 1
	some msg in denials
	contains(msg, "desconocido hasta el apply")
}

# Una llave que ya existe también bloquea: hay que borrarla.
test_sa_key_existing_noop_denied if {
	rc := mk_change("google_service_account_key.legacy", "google_service_account_key", ["no-op"], sa_key_after, {})
	count(rule_denials(mk_plan([rc]), "service_account_key")) == 1
}

test_sa_key_delete_allowed if {
	rc := mk_change("google_service_account_key.legacy", "google_service_account_key", ["delete"], null, {})
	count(all_denials(mk_plan([rc]))) == 0
}

# La fuente de datos solo lee una llave pública existente.
test_sa_key_data_source_ignored if {
	rc := object.union(mk_change("data.google_service_account_key.this", "google_service_account_key", ["read"], sa_key_after, {}), {"mode": "data"})
	count(all_denials(mk_plan([rc]))) == 0
}
