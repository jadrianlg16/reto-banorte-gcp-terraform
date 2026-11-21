# Regla 4 (§9.1): instancia o plantilla con IP pública.
#
# Una interfaz de red tiene IP externa si declara algún bloque `access_config` (IPv4) o
# `ipv6_access_config` (IPv6 externa). Si la lista de bloques es desconocida en el plan (por
# ejemplo, un bloque `dynamic` sobre un valor calculado), no se puede probar que no haya IP
# pública y se rechaza.
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
	msg := message("compute_public_ip", rc, sprintf(
		"network_interface[%d].%s es desconocido en el plan; no se puede probar que no haya IP pública",
		[i, block],
	))
}

deny contains msg if {
	some rc in planned_resources
	rc.type in public_ip_types
	is_unknown(rc, ["network_interface"])
	msg := message("compute_public_ip", rc, "network_interface es desconocido en el plan; no se puede probar que no haya IP pública")
}
