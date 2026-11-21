# Regla 2 (§9.1): instancia, plantilla o nodo de GKE sin Shielded VM.
#
# VM y plantillas de Compute: se exige el bloque `shielded_instance_config` con arranque
# seguro, vTPM y supervisión de integridad encendidos. El proveedor solo enciende por defecto
# vTPM e integridad; el arranque seguro viene apagado, así que omitir el bloque se rechaza.
#
# GKE (`google_container_node_pool` y `google_container_cluster`): el bloque
# `node_config[0].shielded_instance_config` de GKE solo tiene `enable_secure_boot` y
# `enable_integrity_monitoring` (el vTPM lo da `enable_shielded_nodes` del clúster, que no
# puede ser false). Se revisa el `node_config` del pool, el del clúster (el pool por defecto,
# que existe aunque se elimine después con `remove_default_node_pool`) y el de cada
# `node_pool[i]` en línea del clúster. Un clúster Autopilot (`enable_autopilot = true`) no
# tiene `node_config` propio y queda fuera de esa parte.
#
# Un indicador desconocido hasta el apply también se rechaza: debe ser una constante.
package main

shielded_vm_types := {
	"google_compute_instance",
	"google_compute_instance_template",
	"google_compute_region_instance_template",
}

shielded_vm_flags := ["enable_secure_boot", "enable_vtpm", "enable_integrity_monitoring"]

gke_shielded_flags := ["enable_secure_boot", "enable_integrity_monitoring"]

shielded_flag_on(after, flag) if after.shielded_instance_config[0][flag] == true

deny contains msg if {
	some rc in planned_resources
	rc.type in shielded_vm_types
	missing := [flag | some flag in shielded_vm_flags; not shielded_flag_on(rc.change.after, flag)]
	count(missing) > 0
	msg := message("shielded_vm", rc, sprintf(
		"Shielded VM incompleta: shielded_instance_config debe tener en true %s",
		[concat(", ", missing)],
	))
}

# --- GKE -------------------------------------------------------------------------------------

gke_flag_on(after, node_config_path, flag) if {
	path_value(after, array.concat(node_config_path, ["shielded_instance_config", 0, flag])) == true
}

# Rutas de `node_config` que deben llevar Shielded VM.
gke_node_config_paths(rc) := {["node_config", 0]} if {
	rc.type == "google_container_node_pool"
} else := {["node_config", 0]} | {["node_pool", i, "node_config", 0] |
	some i, _ in object.get(rc.change.after, "node_pool", [])
} if {
	rc.type == "google_container_cluster"
	object.get(rc.change.after, "enable_autopilot", null) != true
}

deny contains msg if {
	some rc in planned_resources
	some node_config_path in gke_node_config_paths(rc)
	missing := [flag | some flag in gke_shielded_flags; not gke_flag_on(rc.change.after, node_config_path, flag)]
	count(missing) > 0
	msg := message("shielded_vm", rc, sprintf(
		"Shielded VM incompleta en los nodos de GKE: %s.shielded_instance_config debe tener en true %s",
		[node_config_text(node_config_path), concat(", ", missing)],
	))
}

deny contains msg if {
	some rc in planned_resources
	rc.type == "google_container_cluster"
	object.get(rc.change.after, "enable_shielded_nodes", null) == false
	msg := message("shielded_vm", rc, "enable_shielded_nodes = false: los nodos de GKE deben ser Shielded VM")
}

node_config_text(path) := concat(".", [segment |
	some i, part in path
	is_string(part)
	segment := sprintf("%s[%v]", [part, path[i + 1]])
])
