# Pruebas de la regla 12: recursos únicos y nombres en las raíces de entorno (ADR 0029 §4).
# `good_bucket` está en bucket_public_access_test.rego.
package main

env_dev := {"environment": "dev", "prefix": "bnt"}

env_sa(account) := sprintf("serviceAccount:%s@example-landing-zone.iam.gserviceaccount.com", [account])

# Lo que declaran hoy las raíces de entorno (nombres de los planes reales de destroy del spoke y de
# cargas de dev, scripts/testdata/destroy/).
env_root_compliant := [
	mk_create("module.spoke.google_compute_network.this", "google_compute_network", {"name": "bnt-dev-net-spoke"}),
	mk_create("module.spoke.google_compute_subnetwork.this[\"app\"]", "google_compute_subnetwork", {"name": "bnt-dev-net-app-usc1", "region": "us-central1"}),
	mk_create("module.spoke.google_compute_router.this[\"primary\"]", "google_compute_router", {"name": "bnt-dev-net-spoke-router-usc1", "region": "us-central1"}),
	mk_create("module.firewall.google_compute_network_firewall_policy.this", "google_compute_network_firewall_policy", {"name": "bnt-dev-net-fw"}),
	mk_create("google_service_account.runtime[\"run\"]", "google_service_account", {"account_id": "bnt-dev-app-run"}),
	mk_create("google_service_account.scheduler[\"this\"]", "google_service_account", {"account_id": "bnt-dev-app-sched"}),
	mk_create("google_project_iam_member.runtime[\"run/roles/logging.logWriter\"]", "google_project_iam_member", {
		"project": "example-landing-zone",
		"role": "roles/logging.logWriter",
		"member": env_sa("bnt-dev-app-run"),
	}),
	mk_create("module.cloud_sql.google_project_iam_member.login[\"run\"]", "google_project_iam_member", {
		"project": "example-landing-zone",
		"role": "roles/cloudsql.instanceUser",
		"member": env_sa("bnt-dev-app-run"),
	}),
	mk_create("google_secret_manager_secret_iam_member.runtime[\"app-api-token/run\"]", "google_secret_manager_secret_iam_member", {
		"secret_id": "projects/example-landing-zone/secrets/bnt-dev-sec-app-api-token",
		"role": "roles/secretmanager.secretAccessor",
		"member": env_sa("bnt-dev-app-run"),
	}),
	mk_create("google_artifact_registry_repository_iam_member.reader[\"mig\"]", "google_artifact_registry_repository_iam_member", {
		"location": "us",
		"repository": "bnt-dev-app",
		"role": "roles/artifactregistry.reader",
		"member": env_sa("bnt-dev-app-mig"),
	}),
	mk_create("module.storage.google_storage_bucket.this", "google_storage_bucket", with_fields(good_bucket, {"name": "bnt-dev-data-app-usc1"})),
	mk_create("module.cloud_sql.google_sql_database.this[\"app\"]", "google_sql_database", {"name": "app", "instance": "bnt-dev-data-sql-usc1"}),
	mk_create("module.dns.google_dns_record_set.this[\"pkg/apex\"]", "google_dns_record_set", {"name": "pkg.dev.", "managed_zone": "bnt-dev-net-dns-pkg"}),
	mk_create("module.firewall.google_tags_tag_key.this[\"iap_ssh\"]", "google_tags_tag_key", {"short_name": "bnt-dev-net-fw-iap-ssh"}),
]

test_env_root_compliant_passes if {
	count(all_denials(mk_plan_vars(env_root_compliant, env_dev))) == 0
}

# Caso de la revisión de seguridad: auditoría y API declaradas en una raíz dev.
test_env_root_review_case_denied if {
	plan := mk_plan_vars(
		[
			mk_create("google_project_iam_audit_config.x", "google_project_iam_audit_config", {
				"project": "example-landing-zone",
				"service": "allServices",
				"audit_log_config": [{"log_type": "ADMIN_READ", "exempted_members": [env_sa("bnt-tf-wl-dev")]}],
			}),
			mk_create("google_project_service.s", "google_project_service", {"project": "example-landing-zone", "service": "deploymentmanager.googleapis.com"}),
		],
		env_dev,
	)
	rule_denials(plan, "env_root_scope") == {
		"[env_root_scope] google_project_iam_audit_config.x: google_project_iam_audit_config existe una vez por proyecto: lo declaran 0-bootstrap o 1-base, nunca la raíz del entorno dev (ADR 0029 §4)",
		"[env_root_scope] google_project_service.s: google_project_service existe una vez por proyecto: lo declaran 0-bootstrap o 1-base, nunca la raíz del entorno dev (ADR 0029 §4)",
	}
}

# Todos los tipos únicos, incluidas las familias por patrón. Sin prefijo en el plan: los tipos se
# revisan igual.
test_env_root_singleton_types_denied if {
	types := [
		"google_project", "google_project_service", "google_project_services",
		"google_compute_project_metadata", "google_compute_project_metadata_item",
		"google_project_iam_audit_config", "google_project_iam_binding", "google_project_iam_policy",
		"google_project_iam_custom_role", "google_project_default_service_accounts",
		"google_project_organization_policy", "google_org_policy_policy",
		"google_binary_authorization_policy", "google_essential_contacts_contact",
		"google_logging_project_sink", "google_logging_project_bucket_config", "google_logging_project_exclusion",
		"google_billing_budget", "google_scc_project_notification_config", "google_scc_v2_project_notification_config",
		"google_iam_deny_policy", "google_iam_workload_identity_pool", "google_iam_workload_identity_pool_provider",
		"google_access_context_manager_service_perimeter",
		"google_access_context_manager_service_perimeter_resource",
		"google_access_context_manager_service_perimeter_dry_run_resource",
	]
	changes := [mk_create(sprintf("%s.this", [t]), t, {}) | some t in types]
	count(rule_denials(mk_plan_vars(changes, {"environment": "qa"}), "env_root_scope")) == count(types)
}

# Llaves, secretos y repositorios por entorno: los crea 1-base.
test_env_root_base_types_denied if {
	plan := mk_plan_vars(
		[
			mk_create("module.kms.google_kms_key_ring.this", "google_kms_key_ring", {"name": "bnt-dev-sec-kr-usc1", "location": "us-central1"}),
			mk_create("module.kms.google_kms_crypto_key.this[\"app\"]", "google_kms_crypto_key", {"name": "app", "purpose": "ENCRYPT_DECRYPT", "rotation_period": "7776000s", "labels": mk_labels}),
			mk_create("module.secrets.google_secret_manager_secret.this[\"db\"]", "google_secret_manager_secret", {"secret_id": "bnt-dev-sec-db", "labels": mk_labels}),
			mk_create("google_artifact_registry_repository.app", "google_artifact_registry_repository", {"repository_id": "bnt-dev-app", "location": "us", "labels": mk_labels}),
		],
		env_dev,
	)
	denials := rule_denials(plan, "env_root_scope")
	count(denials) == 4
	every msg in denials {
		contains(msg, "lo crea 1-base")
	}
	count(all_denials(plan)) == 4
}

# Permisos de proyecto para principales que la raíz no creó (§4.2).
test_env_root_foreign_project_members_denied if {
	members := [
		env_sa("bnt-tf-wl-dev"),
		env_sa("bnt-prod-app-run"),
		"group:platform-devops@example.com",
		"serviceAccount:service-000000000000@gcp-sa-cloudscheduler.iam.gserviceaccount.com",
		"serviceAccount:000000000000-compute@developer.gserviceaccount.com",
		"principalSet://iam.googleapis.com/projects/000000000000/locations/global/workloadIdentityPools/github/attribute.repository/example/repo",
	]
	changes := [mk_create(sprintf("google_project_iam_member.m[%d]", [i]), "google_project_iam_member", {
		"project": "example-landing-zone",
		"role": "roles/viewer",
		"member": m,
	}) |
		some i, m in members
	]
	count(rule_denials(mk_plan_vars(changes, env_dev), "env_root_scope")) == count(members)
}

test_env_root_foreign_member_message if {
	rc := mk_create("google_project_iam_member.pipeline", "google_project_iam_member", {
		"project": "example-landing-zone",
		"role": "roles/editor",
		"member": env_sa("bnt-tf-wl-dev"),
	})
	rule_denials(mk_plan_vars([rc], env_dev), "env_root_scope") == {
		"[env_root_scope] google_project_iam_member.pipeline: permiso de proyecto para serviceAccount:bnt-tf-wl-dev@example-landing-zone.iam.gserviceaccount.com: una raíz de entorno solo da roles de proyecto a las cuentas que crea (serviceAccount:bnt-dev-...) (ADR 0029 §4)",
	}
}

# Quitar un rol de proyecto a una cuenta ajena también es un permiso de proyecto.
test_env_root_member_remove_denied if {
	rc := mk_create("google_project_iam_member_remove.this", "google_project_iam_member_remove", {
		"project": "example-landing-zone",
		"role": "roles/editor",
		"member": env_sa("bnt-tf-base"),
	})
	count(rule_denials(mk_plan_vars([rc], env_dev), "env_root_scope")) == 1
}

# Nombres sin `<prefix>-<env>-` (§4.3) en los tipos revisados.
test_env_root_names_denied if {
	plan := mk_plan_vars(
		[
			mk_create("module.spoke.google_compute_network.this", "google_compute_network", {"name": "bnt-net-spoke"}),
			mk_create("module.spoke.google_compute_subnetwork.this[\"app\"]", "google_compute_subnetwork", {"name": "bnt-qa-net-app-usc1", "region": "us-central1"}),
			mk_create("module.spoke.google_compute_router.this[\"primary\"]", "google_compute_router", {"name": "router-usc1", "region": "us-central1"}),
			mk_create("module.firewall.google_compute_network_firewall_policy.this", "google_compute_network_firewall_policy", {"name": "bnt-common-net-fw"}),
			mk_create("google_compute_region_network_firewall_policy.this", "google_compute_region_network_firewall_policy", {"name": "fw-usc1", "region": "us-central1"}),
			mk_create("google_service_account.runtime[\"run\"]", "google_service_account", {"account_id": "bnt-tf-wl-dev"}),
			mk_create("module.storage.google_storage_bucket.this", "google_storage_bucket", with_fields(good_bucket, {"name": "bnt-prod-data-app-usc1"})),
		],
		env_dev,
	)
	count(rule_denials(plan, "env_root_scope")) == 7
	count(all_denials(plan)) == 7
}

test_env_root_name_message if {
	rc := mk_create("google_service_account.bad", "google_service_account", {"account_id": "bnt-tf-wl-dev"})
	rule_denials(mk_plan_vars([rc], env_dev), "env_root_scope") == {
		"[env_root_scope] google_service_account.bad: account_id = bnt-tf-wl-dev no empieza con bnt-dev-: los recursos de la raíz del entorno llevan el prefijo del entorno (ADR 0029 §4)",
	}
}

# El entorno lo da la variable del plan: lo que es de dev se rechaza en prod.
test_env_root_prod_rejects_dev_names if {
	plan := mk_plan_vars(env_root_compliant, {"environment": "prod", "prefix": "bnt"})
	denials := rule_denials(plan, "env_root_scope")

	# Red, subred, router, firewall, 2 cuentas, 2 permisos de proyecto y el bucket.
	count(denials) == 9
	every msg in denials {
		contains(msg, "bnt-prod-")
	}
}

# Sin prefijo en el plan, los nombres y los principales no se revisan; los tipos sí.
test_env_root_without_prefix_checks_only_types if {
	changes := array.concat(
		[mk_create("google_compute_network.bad", "google_compute_network", {"name": "otra-red"})],
		[mk_create("google_project_service.s", "google_project_service", {"service": "compute.googleapis.com"})],
	)
	denials := rule_denials(mk_plan_vars(changes, {"environment": "dev"}), "env_root_scope")
	count(denials) == 1
	some msg in denials
	contains(msg, "google_project_service.s")
}

# 0-bootstrap, 1-base y el hub no tienen `environment`; un valor fuera de dev, qa y prod tampoco
# es una raíz de entorno.
test_env_root_other_roots_ignored if {
	changes := [
		mk_create("google_project_service.compute", "google_project_service", {"service": "compute.googleapis.com"}),
		mk_create("google_compute_network.hub", "google_compute_network", {"name": "bnt-common-net-hub"}),
		mk_create("google_project_iam_member.tf_base", "google_project_iam_member", {"project": "example-landing-zone", "role": "roles/viewer", "member": env_sa("bnt-tf-read")}),
		mk_create("google_kms_key_ring.dev", "google_kms_key_ring", {"name": "bnt-dev-sec-kr-usc1", "location": "us-central1"}),
	]
	count(rule_denials(mk_plan(changes), "env_root_scope")) == 0
	count(rule_denials(mk_plan_vars(changes, {"prefix": "bnt"}), "env_root_scope")) == 0
	count(rule_denials(mk_plan_vars(changes, {"environment": "common", "prefix": "bnt"}), "env_root_scope")) == 0
}

# Nombre o principal calculados en el apply: no se pueden leer.
test_env_root_unknown_values_not_denied if {
	plan := mk_plan_vars(
		[
			mk_change("google_project_iam_member.runtime", "google_project_iam_member", ["create"], {"project": "example-landing-zone", "role": "roles/logging.logWriter"}, {"member": true}),
			mk_change("google_compute_network.this", "google_compute_network", ["create"], {}, {"name": true}),
		],
		env_dev,
	)
	count(all_denials(plan)) == 0
}

# El destroy de una raíz de entorno (scripts/testdata/destroy) solo borra: no se revisa aquí.
test_env_root_pure_delete_ignored if {
	rc := mk_change("google_project_service.compute", "google_project_service", ["delete"], null, {})
	rc2 := object.union(rc, {"change": {"before": {"service": "compute.googleapis.com"}}})
	count(all_denials(mk_plan_vars([rc2], env_dev))) == 0
}
