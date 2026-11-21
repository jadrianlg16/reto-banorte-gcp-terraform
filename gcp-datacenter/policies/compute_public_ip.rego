# Regla 4 (§9.1): instancia, plantilla o nodo de GKE con IP pública.
#
# VM y plantillas: una interfaz de red tiene IP externa si declara algún bloque `access_config`
# (IPv4) o `ipv6_access_config` (IPv6 externa). Si la lista de bloques es desconocida en el
# plan (por ejemplo, un bloque `dynamic` sobre un valor calculado), no se puede probar que no
# haya IP pública y se rechaza, con dos excepciones para `ipv6_access_config`:
#
# - `stack_type` planeado es "IPV4_ONLY": la interfaz no tiene IPv6, así que no puede tener
#   IPv6 externa.
# - La interfaz es un bloque escrito en la configuración, no declara `ipv6_access_config` ni
#   `stack_type`, y `stack_type` no tiene valor en el plan (la API usa IPV4_ONLY por omisión).
#
# Las dos existen porque el proveedor google 6.50.0 deja `ipv6_access_config` desconocido en
# `google_compute_region_instance_template` aunque no se declare (plan real del ejemplo de
# compute-mig; planes de ejemplo `compute_public_ip_pass_real_*.json`).
#
# GKE: los nodos son VM de Compute. `google_container_cluster` debe tener
# `private_cluster_config[0].enable_private_nodes = true` (conocido); un pool, dentro del
# clúster o como `google_container_node_pool`, no puede declarar
# `network_config[0].enable_private_nodes = false`. Si el pool no lo declara, hereda el valor
# del clúster (atributo calculado) y se acepta.
package main

public_ip_types := {
	"google_compute_instance",
	"google_compute_instance_template",
	"google_compute_region_instance_template",
}

external_access_blocks := ["access_config", "ipv6_access_config"]

deny contains msg if {
	some rc in planned_resources
	rc.type in public_ip_types
	some i, nic in rc.change.after.network_interface
	some block in external_access_blocks
	count(object.get(nic, block, [])) > 0
	msg := message("compute_public_ip", rc, sprintf(
		"network_interface[%d] declara %s: las VM no llevan IP pública (salida por Cloud NAT, entrada por balanceador o IAP)",
		[i, block],
	))
}

deny contains msg if {
	some rc in planned_resources
	rc.type in public_ip_types
	some i, nic_unknown in after_unknown(rc).network_interface
	is_object(nic_unknown)
	some block in external_access_blocks
	nic_unknown[block] == true
	not unknown_block_allowed(rc, i, block)
	msg := message("compute_public_ip", rc, sprintf(
		"network_interface[%d].%s es desconocido en el plan; no se puede probar que no haya IP pública (declare stack_type = \"IPV4_ONLY\")",
		[i, block],
	))
}

deny contains msg if {
	some rc in planned_resources
	rc.type in public_ip_types
	is_unknown(rc, ["network_interface"])
	msg := message("compute_public_ip", rc, "network_interface es desconocido en el plan; no se puede probar que no haya IP pública")
}

# --- Excepciones para `ipv6_access_config` desconocido ---------------------------------------

unknown_block_allowed(rc, i, "ipv6_access_config") if {
	path_value(rc.change.after, ["network_interface", i, "stack_type"]) == "IPV4_ONLY"
}

unknown_block_allowed(rc, i, "ipv6_access_config") if {
	path_value(rc.change.after, ["network_interface", i, "stack_type"]) == null
	nic_config := resource_config_block(rc, "network_interface", i)
	not "ipv6_access_config" in object.keys(nic_config)
	not "stack_type" in object.keys(nic_config)
}

# Bloque `name[i]` de la configuración del recurso (sección `configuration` del plan). No
# existe si el plan no trae configuración o si el bloque se genera con `dynamic`: en ese caso
# la excepción no aplica.
resource_config_block(rc, name, i) := block if {
	some resource in module_config(rc).resources
	resource.mode == "managed"
	resource.address == sprintf("%s.%s", [rc.type, rc.name])
	block := resource.expressions[name][i]
	is_object(block)
}

# Módulo de `configuration` que declara el recurso: se sigue `module_calls` con los nombres
# de `module_address` sin índices de count o for_each.
module_config(rc) := object.get(input, array.concat(["configuration", "root_module"], module_config_path(rc)), {})

module_config_path(rc) := [step |
	some name in module_call_names(object.get(rc, "module_address", ""))
	some step in ["module_calls", name, "module"]
]

module_call_names(address) := [name |
	some match in regex.find_all_string_submatch_n(`module\.([^.]+)`, regex.replace(address, `\[[^\]]*\]`, ""), -1)
	name := match[1]
]

# --- GKE -------------------------------------------------------------------------------------

deny contains msg if {
	some rc in planned_resources
	rc.type == "google_container_cluster"
	path_value(rc.change.after, ["private_cluster_config", 0, "enable_private_nodes"]) != true
	msg := message("compute_public_ip", rc, sprintf(
		"private_cluster_config[0].enable_private_nodes debe ser true (valor en el plan: %s): los nodos de GKE no llevan IP pública",
		[value_text(rc, ["private_cluster_config", 0, "enable_private_nodes"])],
	))
}

deny contains msg if {
	some rc in planned_resources
	some pool_path in gke_pool_paths(rc)
	path_value(rc.change.after, array.concat(pool_path, ["network_config", 0, "enable_private_nodes"])) == false
	msg := message("compute_public_ip", rc, sprintf(
		"%snetwork_config[0].enable_private_nodes = false: los nodos de GKE no llevan IP pública",
		[pool_path_text(pool_path)],
	))
}

# Rutas de los pools de nodos de un recurso: el propio recurso para `google_container_node_pool`
# y cada `node_pool[i]` en línea de `google_container_cluster`.
gke_pool_paths(rc) := {[]} if {
	rc.type == "google_container_node_pool"
} else := {["node_pool", i] | some i, _ in object.get(rc.change.after, "node_pool", [])} if {
	rc.type == "google_container_cluster"
	is_array(object.get(rc.change.after, "node_pool", null))
}

pool_path_text(path) := "" if {
	count(path) == 0
} else := sprintf("%s[%v].", path)
