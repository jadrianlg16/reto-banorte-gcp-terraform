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

test_shielded_other_type_ignored if {
	rc := mk_create("google_compute_network.this", "google_compute_network", {"name": "bnt-dev-net-vpc"})
	count(all_denials(mk_plan([rc]))) == 0
}
