# Pruebas de la regla 2: Shielded VM.
package main

good_shielded := [{
	"enable_secure_boot": true,
	"enable_vtpm": true,
	"enable_integrity_monitoring": true,
}]

good_instance := {
	"name": "bnt-dev-app-vm",
	"machine_type": "e2-medium",
	"zone": "us-central1-a",
	"labels": mk_labels,
	"terraform_labels": mk_labels,
	"network_interface": [{"subnetwork": "bnt-dev-net-app-usc1", "access_config": [], "ipv6_access_config": []}],
	"shielded_instance_config": good_shielded,
}

test_shielded_instance_passes if {
	plan := mk_plan([mk_create("google_compute_instance.this", "google_compute_instance", good_instance)])
	count(all_denials(plan)) == 0
}

test_shielded_block_missing_denied if {
	after := object.union(good_instance, {"shielded_instance_config": []})
	rc := mk_change("google_compute_instance.this", "google_compute_instance", ["create"], after, {"shielded_instance_config": true})
	rule_denials(mk_plan([rc]), "shielded_vm") == {
		"[shielded_vm] google_compute_instance.this: Shielded VM incompleta: shielded_instance_config debe tener en true enable_secure_boot, enable_vtpm, enable_integrity_monitoring",
	}
}

test_shielded_secure_boot_off_template_denied if {
	after := object.union(good_instance, {"shielded_instance_config": [{
		"enable_secure_boot": false,
		"enable_vtpm": true,
		"enable_integrity_monitoring": true,
	}]})
	rc := mk_create("module.mig.google_compute_region_instance_template.this", "google_compute_region_instance_template", after)
	denials := rule_denials(mk_plan([rc]), "shielded_vm")
	count(denials) == 1
	some msg in denials
	contains(msg, "module.mig.google_compute_region_instance_template.this")
	not contains(msg, "enable_vtpm")
}

# Indicador calculado en el apply: no se puede probar, se rechaza.
test_shielded_flag_unknown_denied if {
	after := object.union(good_instance, {"shielded_instance_config": [{"enable_vtpm": true, "enable_integrity_monitoring": true}]})
	rc := mk_change("google_compute_instance_template.this", "google_compute_instance_template", ["create"], after, {"shielded_instance_config": [{"enable_secure_boot": true}]})
	count(rule_denials(mk_plan([rc]), "shielded_vm")) == 1
}

# --- GKE (gke_cluster y gke_pool están en compute_public_ip_test.rego) -----------------------

test_shielded_gke_pool_passes if {
	rc := mk_create("google_container_node_pool.this", "google_container_node_pool", gke_pool)
	count(rule_denials(mk_plan([rc]), "shielded_vm")) == 0
}

test_shielded_gke_pool_secure_boot_off_denied if {
	after := with_fields(gke_pool, {"node_config": [{
		"resource_labels": mk_labels,
		"shielded_instance_config": [{"enable_secure_boot": false, "enable_integrity_monitoring": true}],
	}]})
	rc := mk_create("module.gke.google_container_node_pool.this[\"general\"]", "google_container_node_pool", after)
	rule_denials(mk_plan([rc]), "shielded_vm") == {
		"[shielded_vm] module.gke.google_container_node_pool.this[\"general\"]: Shielded VM incompleta en los nodos de GKE: node_config[0].shielded_instance_config debe tener en true enable_secure_boot",
	}
}

# Sin bloque: el proveedor deja el arranque seguro apagado.
test_shielded_gke_pool_block_missing_denied if {
	after := with_fields(gke_pool, {"node_config": [{"resource_labels": mk_labels, "shielded_instance_config": []}]})
	rc := mk_create("google_container_node_pool.this", "google_container_node_pool", after)
	denials := rule_denials(mk_plan([rc]), "shielded_vm")
	count(denials) == 1
	some msg in denials
	contains(msg, "enable_secure_boot, enable_integrity_monitoring")
}

test_shielded_gke_cluster_passes if {
	rc := mk_create("google_container_cluster.this", "google_container_cluster", gke_cluster)
	count(rule_denials(mk_plan([rc]), "shielded_vm")) == 0
}

# El pool por defecto se crea aunque remove_default_node_pool lo elimine después.
test_shielded_gke_cluster_default_pool_missing_denied if {
	after := with_fields(gke_cluster, {"node_config": [], "remove_default_node_pool": true})
	rc := mk_create("google_container_cluster.this", "google_container_cluster", after)
	count(rule_denials(mk_plan([rc]), "shielded_vm")) == 1
}

test_shielded_gke_cluster_inline_pool_denied if {
	after := with_fields(gke_cluster, {"node_pool": [{"name": "a", "node_config": [{"shielded_instance_config": [{"enable_secure_boot": false, "enable_integrity_monitoring": false}]}]}]})
	rc := mk_create("google_container_cluster.this", "google_container_cluster", after)
	denials := rule_denials(mk_plan([rc]), "shielded_vm")
	count(denials) == 1
	some msg in denials
	contains(msg, "node_pool[0].node_config[0].shielded_instance_config")
}

test_shielded_gke_shielded_nodes_off_denied if {
	after := with_fields(gke_cluster, {"enable_shielded_nodes": false})
	rc := mk_create("google_container_cluster.this", "google_container_cluster", after)
	rule_denials(mk_plan([rc]), "shielded_vm") == {"[shielded_vm] google_container_cluster.this: enable_shielded_nodes = false: los nodos de GKE deben ser Shielded VM"}
}

test_shielded_gke_autopilot_without_node_config_ignored if {
	after := with_fields(gke_cluster, {"node_config": [], "enable_autopilot": true})
	rc := mk_create("google_container_cluster.this", "google_container_cluster", after)
	count(rule_denials(mk_plan([rc]), "shielded_vm")) == 0
}

test_shielded_gke_flag_unknown_denied if {
	after := with_fields(gke_pool, {"node_config": [{"resource_labels": mk_labels, "shielded_instance_config": [{"enable_integrity_monitoring": true}]}]})
	rc := mk_change("google_container_node_pool.this", "google_container_node_pool", ["create"], after, {"node_config": [{"shielded_instance_config": [{"enable_secure_boot": true}]}]})
	count(rule_denials(mk_plan([rc]), "shielded_vm")) == 1
}

test_shielded_other_type_ignored if {
	rc := mk_create("google_compute_network.this", "google_compute_network", {"name": "bnt-dev-net-vpc"})
	count(all_denials(mk_plan([rc]))) == 0
}
