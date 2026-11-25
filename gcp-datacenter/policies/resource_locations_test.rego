# Pruebas de la regla 11: ubicaciones permitidas. `good_bucket` está en
# bucket_public_access_test.rego.
package main

test_locations_allowed_pass if {
	plan := mk_plan([
		mk_create("google_storage_bucket.this", "google_storage_bucket", good_bucket),
		mk_create("google_storage_bucket.dual", "google_storage_bucket", with_fields(good_bucket, {
			"name": "bnt-dev-data-dual-us",
			"location": "US",
			"custom_placement_config": [{"data_locations": ["US-CENTRAL1", "US-EAST4"]}],
		})),
		mk_create("google_compute_subnetwork.dr", "google_compute_subnetwork", {"name": "bnt-dev-net-app-use4", "region": "us-east4"}),
		mk_create("google_kms_key_ring.us", "google_kms_key_ring", {"name": "bnt-dev-sec-kr-us", "location": "us"}),
		mk_create("google_kms_key_ring.global", "google_kms_key_ring", {"name": "bnt-dev-sec-kr-global", "location": "global"}),
		mk_create("google_compute_instance_group_manager.zonal", "google_compute_instance_group_manager", {"name": "bnt-dev-app-mig-usc1-a", "zone": "us-central1-a"}),
		mk_create("google_filestore_instance.nfs", "google_filestore_instance", {
			"name": "bnt-dev-data-nfs-use4",
			"location": "us-east4-c",
			"labels": mk_labels,
		}),
		mk_create("google_secret_manager_secret.replicated", "google_secret_manager_secret", {
			"secret_id": "bnt-dev-sec-db-config",
			"labels": mk_labels,
			"replication": [{"auto": [], "user_managed": [{"replicas": [{"location": "us-central1"}, {"location": "us-east4"}]}]}],
		}),
	])
	count(all_denials(plan)) == 0
}

# Caso de la revisión de seguridad (con acceso uniforme, para aislar la regla).
test_locations_bucket_asia_denied if {
	rc := mk_create("google_storage_bucket.b", "google_storage_bucket", with_fields(good_bucket, {"location": "ASIA-EAST1"}))
	plan := mk_plan([rc])
	rule_denials(plan, "resource_locations") == {
		"[resource_locations] google_storage_bucket.b: location = ASIA-EAST1 está fuera de las ubicaciones permitidas (us-central1, us-east4 y sus zonas, us, global)",
	}
	count(all_denials(plan)) == 1
}

test_locations_region_denied if {
	rc := mk_create("module.spoke.google_compute_subnetwork.this[\"app\"]", "google_compute_subnetwork", {"name": "bnt-dev-net-app-euw1", "region": "europe-west1"})
	count(rule_denials(mk_plan([rc]), "resource_locations")) == 1
}

test_locations_multiregion_other_than_us_denied if {
	rc := mk_create("google_kms_key_ring.asia", "google_kms_key_ring", {"name": "bnt-dev-sec-kr-asia", "location": "asia"})
	count(rule_denials(mk_plan([rc]), "resource_locations")) == 1
}

test_locations_zone_of_other_region_denied if {
	rc := mk_create("google_compute_instance_group_manager.zonal", "google_compute_instance_group_manager", {"name": "bnt-dev-app-mig-usw1-a", "zone": "us-west1-a"})
	count(rule_denials(mk_plan([rc]), "resource_locations")) == 1
}

# `us-central10-a` no es una zona de us-central1; `us-central1-ab` tampoco.
test_locations_zone_lookalikes_denied if {
	plan := mk_plan([
		mk_create("google_compute_disk.a", "google_compute_disk", {"name": "bnt-dev-app-disk-a", "zone": "us-central10-a", "labels": mk_labels}),
		mk_create("google_compute_disk.b", "google_compute_disk", {"name": "bnt-dev-app-disk-b", "zone": "us-central1-ab", "labels": mk_labels}),
	])
	count(rule_denials(plan, "resource_locations")) == 2
}

# Doble región configurable: `US` está permitida, pero cada una de sus regiones se revisa.
test_locations_dual_region_data_location_denied if {
	rc := mk_create("google_storage_bucket.dual", "google_storage_bucket", with_fields(good_bucket, {
		"location": "US",
		"custom_placement_config": [{"data_locations": ["US-CENTRAL1", "US-WEST1"]}],
	}))
	rule_denials(mk_plan([rc]), "resource_locations") == {
		"[resource_locations] google_storage_bucket.dual: custom_placement_config[0].data_locations = US-WEST1 está fuera de las ubicaciones permitidas (us-central1, us-east4 y sus zonas, us, global)",
	}
}

test_locations_secret_replica_denied if {
	rc := mk_create("google_secret_manager_secret.replicated", "google_secret_manager_secret", {
		"secret_id": "bnt-dev-sec-db-config",
		"labels": mk_labels,
		"replication": [{"auto": [], "user_managed": [{"replicas": [{"location": "us-central1"}, {"location": "europe-west1"}]}]}],
	})
	denials := rule_denials(mk_plan([rc]), "resource_locations")
	count(denials) == 1
	some msg in denials
	contains(msg, "replication[0].user_managed[0].replicas[1].location = europe-west1")
}

# Región omitida: el plan la deja desconocida y la decide el proveedor (se revisa abajo).
test_locations_unknown_or_empty_not_denied if {
	plan := mk_plan([
		mk_change("google_compute_subnetwork.no_region", "google_compute_subnetwork", ["create"], {"name": "bnt-dev-net-run-usc1"}, {"region": true}),
		mk_create("google_compute_address.empty_zone", "google_compute_address", {"name": "bnt-dev-app-ip", "region": "us-central1", "zone": "", "labels": mk_labels}),
	])
	count(all_denials(plan)) == 0
}

test_locations_non_google_ignored if {
	rc := mk_create("terraform_data.marker", "terraform_data", {"location": "mars-north1"})
	count(all_denials(mk_plan([rc]))) == 0
}

test_locations_pure_delete_ignored if {
	rc := mk_change("google_storage_bucket.old", "google_storage_bucket", ["delete"], null, {})
	rc2 := object.union(rc, {"change": {"before": with_fields(good_bucket, {"location": "ASIA-EAST1"})}})
	count(all_denials(mk_plan([rc2]))) == 0
}

# --- Región del bloque provider ---------------------------------------------------------------

provider_plan(provider_config, vars) := object.union(
	mk_plan_vars([mk_create("google_compute_network.this", "google_compute_network", {"name": "bnt-dev-net-spoke"})], vars),
	{"configuration": {"provider_config": provider_config}},
)

test_locations_provider_region_from_variable_passes if {
	plan := provider_plan(
		{
			"google": {"name": "google", "expressions": {"region": {"references": ["var.primary_region"]}}},
			"google.dr": {"name": "google", "alias": "dr", "expressions": {"region": {"constant_value": "us-east4"}}},
		},
		{"primary_region": "us-central1"},
	)
	count(all_denials(plan)) == 0
}

test_locations_provider_region_from_variable_denied if {
	plan := provider_plan(
		{"google-beta": {"name": "google-beta", "expressions": {"region": {"references": ["var.primary_region"]}}}},
		{"primary_region": "europe-west1"},
	)
	rule_denials(plan, "resource_locations") == {
		"[resource_locations] provider[\"google-beta\"]: region = europe-west1 está fuera de las ubicaciones permitidas (us-central1, us-east4 y sus zonas, us, global); los recursos que no declaran la suya la usan",
	}
}

test_locations_provider_zone_constant_denied if {
	plan := provider_plan({"google": {"name": "google", "expressions": {"zone": {"constant_value": "asia-east1-a"}}}}, {})
	count(rule_denials(plan, "resource_locations")) == 1
}

# Referencias que no son una variable de la raíz (local, otro recurso) o bloques de un módulo: no
# se resuelven. Tampoco se revisan proveedores que no son de Google.
test_locations_provider_unresolved_ignored if {
	plan := provider_plan(
		{
			"google": {"name": "google", "expressions": {"region": {"references": ["local.region"]}}},
			"module.x:google": {"name": "google", "module_address": "module.x", "expressions": {"region": {"constant_value": "europe-west1"}}},
			"aws": {"name": "aws", "expressions": {"region": {"constant_value": "eu-west-1"}}},
		},
		{"region": "europe-west1"},
	)
	count(all_denials(plan)) == 0
}
