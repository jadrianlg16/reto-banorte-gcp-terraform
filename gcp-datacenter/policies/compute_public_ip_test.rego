# Pruebas de la regla 4: VM con IP pública.
package main

private_template := {
	"name_prefix": "bnt-dev-app-tpl-",
	"machine_type": "e2-medium",
	"region": "us-central1",
	"labels": mk_labels,
	"terraform_labels": mk_labels,
	"network_interface": [{"subnetwork": "bnt-dev-net-app-usc1", "access_config": [], "ipv6_access_config": []}],
	"shielded_instance_config": [{
		"enable_secure_boot": true,
		"enable_vtpm": true,
		"enable_integrity_monitoring": true,
	}],
}

test_public_ip_none_passes if {
	rc := mk_create("google_compute_region_instance_template.this", "google_compute_region_instance_template", private_template)
	count(all_denials(mk_plan([rc]))) == 0
}

test_public_ip_access_config_denied if {
	nic := {"subnetwork": "bnt-dev-net-app-usc1", "access_config": [{"network_tier": "PREMIUM"}], "ipv6_access_config": []}
	after := object.union(private_template, {"network_interface": [nic]})
	rc := mk_change("module.mig.google_compute_region_instance_template.this", "google_compute_region_instance_template", ["create"], after, {
		"network_interface": [{"access_config": [{"nat_ip": true}]}],
	})
	rule_denials(mk_plan([rc]), "compute_public_ip") == {
		"[compute_public_ip] module.mig.google_compute_region_instance_template.this: network_interface[0] declara access_config: las VM no llevan IP pública (salida por Cloud NAT, entrada por balanceador o IAP)",
	}
}

test_public_ip_ipv6_denied if {
	nic := {"subnetwork": "bnt-dev-net-app-usc1", "access_config": [], "ipv6_access_config": [{"network_tier": "PREMIUM"}]}
	after := object.union(private_template, {"network_interface": [nic]})
	rc := mk_create("google_compute_instance.this", "google_compute_instance", after)
	count(rule_denials(mk_plan([rc]), "compute_public_ip")) == 1
}

# Bloque dynamic sobre un valor calculado: la lista entera es desconocida.
test_public_ip_unknown_access_config_denied if {
	nic := {"subnetwork": "bnt-dev-net-app-usc1", "ipv6_access_config": []}
	after := object.union(private_template, {"network_interface": [nic]})
	rc := mk_change("google_compute_instance_template.this", "google_compute_instance_template", ["create"], after, {
		"network_interface": [{"access_config": true}],
	})
	denials := rule_denials(mk_plan([rc]), "compute_public_ip")
	count(denials) == 1
	some msg in denials
	contains(msg, "desconocido en el plan")
}

test_public_ip_second_nic_denied if {
	nics := [
		{"subnetwork": "bnt-dev-net-app-usc1", "access_config": []},
		{"subnetwork": "bnt-dev-net-dmz-usc1", "access_config": [{"nat_ip": "203.0.113.10"}]},
	]
	after := object.union(private_template, {"network_interface": nics})
	rc := mk_create("google_compute_instance.this", "google_compute_instance", after)
	denials := rule_denials(mk_plan([rc]), "compute_public_ip")
	count(denials) == 1
	some msg in denials
	contains(msg, "network_interface[1]")
}
