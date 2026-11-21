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

# --- ipv6_access_config desconocido (forma real de google 6.50.0) ---------------------------
#
# `google_compute_region_instance_template` deja `ipv6_access_config` desconocido aunque no se
# declare. Formas copiadas del plan real del ejemplo de compute-mig y de la sonda
# (policies/fixtures/compute_public_ip_*_real_mig_*.json).

real_nic_after := {
	"access_config": [], "alias_ip_range": [], "network_ip": null, "nic_type": null,
	"queue_count": null, "subnetwork": "projects/example-prod-net-spoke/regions/us-central1/subnetworks/bnt-prod-net-app-usc1",
}

real_nic_unknown := {
	"access_config": [], "alias_ip_range": [], "internal_ipv6_prefix_length": true,
	"ipv6_access_config": true, "ipv6_access_type": true, "ipv6_address": true, "name": true,
	"network": true, "stack_type": true, "subnetwork_project": true,
}

# Plan con la sección `configuration` del módulo `mig` y el bloque network_interface dado.
mig_plan(nic_after, nic_unknown, nic_config) := object.union(mk_plan([object.union(
	mk_change(
		"module.mig.google_compute_region_instance_template.this",
		"google_compute_region_instance_template", ["create"],
		object.union(private_template, {"network_interface": [nic_after]}),
		{"network_interface": [nic_unknown]},
	),
	{"module_address": "module.mig"},
)]), {"configuration": {"root_module": {"module_calls": {"mig": {"module": {"resources": [{
	"address": "google_compute_region_instance_template.this",
	"mode": "managed",
	"type": "google_compute_region_instance_template",
	"name": "this",
	"expressions": {"network_interface": [nic_config]},
}]}}}}}})

# Regresión del hallazgo de revisión: la plantilla conforme del MIG se rechazaba.
test_public_ip_real_template_without_stack_type_passes if {
	plan := mig_plan(real_nic_after, real_nic_unknown, {"subnetwork": {"references": ["var.subnet"]}})
	count(rule_denials(plan, "compute_public_ip")) == 0
}

test_public_ip_real_template_ipv4_only_passes if {
	after := object.union(real_nic_after, {"stack_type": "IPV4_ONLY"})
	unknown := object.remove(real_nic_unknown, ["stack_type"])
	plan := mig_plan(after, unknown, {"subnetwork": {"references": ["var.subnet"]}, "stack_type": {"constant_value": "IPV4_ONLY"}})
	count(rule_denials(plan, "compute_public_ip")) == 0
}

# IPV4_ONLY planeado basta aunque el plan no traiga configuración.
test_public_ip_ipv4_only_without_configuration_passes if {
	after := object.union(real_nic_after, {"stack_type": "IPV4_ONLY"})
	rc := mk_change("google_compute_region_instance_template.this", "google_compute_region_instance_template", ["create"],
		object.union(private_template, {"network_interface": [after]}),
		{"network_interface": [object.remove(real_nic_unknown, ["stack_type"])]})
	count(rule_denials(mk_plan([rc]), "compute_public_ip")) == 0
}

test_public_ip_real_template_dual_stack_denied if {
	after := object.union(real_nic_after, {"stack_type": "IPV4_IPV6"})
	unknown := object.remove(real_nic_unknown, ["stack_type"])
	plan := mig_plan(after, unknown, {"subnetwork": {"references": ["var.subnet"]}, "stack_type": {"constant_value": "IPV4_IPV6"}})
	rule_denials(plan, "compute_public_ip") == {
		"[compute_public_ip] module.mig.google_compute_region_instance_template.this: network_interface[0].ipv6_access_config es desconocido en el plan; no se puede probar que no haya IP pública (declare stack_type = \"IPV4_ONLY\")",
	}
}

# stack_type calculado desde una variable: se declara, así que no aplica la segunda excepción.
test_public_ip_stack_type_from_variable_unknown_denied if {
	plan := mig_plan(real_nic_after, real_nic_unknown, {"subnetwork": {"references": ["var.subnet"]}, "stack_type": {"references": ["var.stack_type"]}})
	count(rule_denials(plan, "compute_public_ip")) == 1
}

# ipv6_access_config declarado (con valores calculados) en la configuración: se rechaza.
test_public_ip_ipv6_declared_unknown_denied if {
	plan := mig_plan(real_nic_after, real_nic_unknown, {
		"subnetwork": {"references": ["var.subnet"]},
		"ipv6_access_config": [{"network_tier": {"references": ["var.tier"]}}],
	})
	count(rule_denials(plan, "compute_public_ip")) == 1
}

# Sin sección configuration no se puede saber si se declaró: se rechaza.
test_public_ip_unknown_ipv6_without_configuration_denied if {
	rc := mk_change("google_compute_region_instance_template.this", "google_compute_region_instance_template", ["create"],
		object.union(private_template, {"network_interface": [real_nic_after]}),
		{"network_interface": [real_nic_unknown]})
	count(rule_denials(mk_plan([rc]), "compute_public_ip")) == 1
}

# La configuración se busca por el módulo sin índices de for_each.
test_public_ip_config_lookup_through_for_each_module if {
	rc := object.union(mk_change(
		"module.apps[\"web\"].module.mig.google_compute_region_instance_template.this",
		"google_compute_region_instance_template", ["create"],
		object.union(private_template, {"network_interface": [real_nic_after]}),
		{"network_interface": [real_nic_unknown]},
	), {"module_address": "module.apps[\"web\"].module.mig"})
	plan := object.union(mk_plan([rc]), {"configuration": {"root_module": {"module_calls": {"apps": {"module": {"module_calls": {"mig": {"module": {"resources": [{
		"address": "google_compute_region_instance_template.this",
		"mode": "managed",
		"expressions": {"network_interface": [{"subnetwork": {"references": ["var.subnet"]}}]},
	}]}}}}}}}}})
	count(rule_denials(plan, "compute_public_ip")) == 0
}

# Una plantilla de otro módulo con el mismo tipo y nombre no presta su configuración.
test_public_ip_config_of_other_module_not_used if {
	rc := object.union(mk_change(
		"module.other.google_compute_region_instance_template.this",
		"google_compute_region_instance_template", ["create"],
		object.union(private_template, {"network_interface": [real_nic_after]}),
		{"network_interface": [real_nic_unknown]},
	), {"module_address": "module.other"})
	plan := object.union(mk_plan([rc]), {"configuration": {"root_module": {"module_calls": {"mig": {"module": {"resources": [{
		"address": "google_compute_region_instance_template.this",
		"mode": "managed",
		"expressions": {"network_interface": [{"subnetwork": {"references": ["var.subnet"]}}]},
	}]}}}}}})
	count(rule_denials(plan, "compute_public_ip")) == 1
}

# --- GKE: nodos privados ---------------------------------------------------------------------

gke_cluster := {
	"name": "bnt-dev-app-gke-usc1",
	"resource_labels": mk_labels,
	"terraform_labels": mk_labels,
	"private_cluster_config": [{"enable_private_nodes": true, "enable_private_endpoint": true}],
	"node_config": [{"shielded_instance_config": [{"enable_secure_boot": true, "enable_integrity_monitoring": true}]}],
}

gke_pool := {
	"name": "general",
	"node_config": [{
		"resource_labels": mk_labels,
		"shielded_instance_config": [{"enable_secure_boot": true, "enable_integrity_monitoring": true}],
	}],
}

test_gke_private_cluster_passes if {
	plan := mk_plan([
		mk_create("module.gke.google_container_cluster.this", "google_container_cluster", gke_cluster),
		mk_change("module.gke.google_container_node_pool.this[\"general\"]", "google_container_node_pool", ["create"], gke_pool, {"network_config": true}),
	])
	count(all_denials(plan)) == 0
}

# El proveedor planea enable_private_nodes = false como null (sonda real).
test_gke_cluster_public_nodes_denied if {
	after := with_fields(gke_cluster, {"private_cluster_config": [{"enable_private_nodes": null, "enable_private_endpoint": null}]})
	rc := mk_create("module.gke.google_container_cluster.this", "google_container_cluster", after)
	rule_denials(mk_plan([rc]), "compute_public_ip") == {
		"[compute_public_ip] module.gke.google_container_cluster.this: private_cluster_config[0].enable_private_nodes debe ser true (valor en el plan: sin definir): los nodos de GKE no llevan IP pública",
	}
}

test_gke_cluster_without_private_config_denied if {
	after := with_fields(gke_cluster, {"private_cluster_config": []})
	rc := mk_create("google_container_cluster.this", "google_container_cluster", after)
	count(rule_denials(mk_plan([rc]), "compute_public_ip")) == 1
}

test_gke_cluster_private_nodes_unknown_denied if {
	after := with_fields(gke_cluster, {"private_cluster_config": [{}]})
	rc := mk_change("google_container_cluster.this", "google_container_cluster", ["create"], after, {"private_cluster_config": [{"enable_private_nodes": true}]})
	denials := rule_denials(mk_plan([rc]), "compute_public_ip")
	count(denials) == 1
	some msg in denials
	contains(msg, "desconocido hasta el apply")
}

test_gke_node_pool_public_nodes_denied if {
	after := with_fields(gke_pool, {"network_config": [{"enable_private_nodes": false}]})
	rc := mk_create("google_container_node_pool.this", "google_container_node_pool", after)
	rule_denials(mk_plan([rc]), "compute_public_ip") == {
		"[compute_public_ip] google_container_node_pool.this: network_config[0].enable_private_nodes = false: los nodos de GKE no llevan IP pública",
	}
}

test_gke_inline_node_pool_public_nodes_denied if {
	after := with_fields(gke_cluster, {"node_pool": [
		{"name": "a", "network_config": [{"enable_private_nodes": true}]},
		{"name": "b", "network_config": [{"enable_private_nodes": false}]},
	]})
	rc := mk_create("google_container_cluster.this", "google_container_cluster", after)
	denials := rule_denials(mk_plan([rc]), "compute_public_ip")
	count(denials) == 1
	some msg in denials
	contains(msg, "node_pool[1].network_config[0]")
}
