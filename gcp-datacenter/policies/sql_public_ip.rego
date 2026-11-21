# Regla 5 (§9.1): Cloud SQL con IP pública.
#
# Se exige `settings[0].ip_configuration[0].ipv4_enabled = false` y una red privada
# (`private_network`, la VPC con Private Service Access). En el proveedor `ipv4_enabled`
# vale true por defecto, así que omitirlo (o omitir `ip_configuration`) se rechaza.
#
# Valores desconocidos: `ipv4_enabled` desconocido se rechaza (debe ser una constante).
# `private_network` desconocido se acepta, porque suele ser el enlace de una VPC que se crea
# en el mismo plan.
package main

sql_ip_configuration(rc) := path_value(rc.change.after, ["settings", 0, "ip_configuration", 0])

sql_ipv4_disabled(rc) if sql_ip_configuration(rc).ipv4_enabled == false

sql_has_private_network(rc) if {
	network := sql_ip_configuration(rc).private_network
	is_string(network)
	network != ""
}

sql_has_private_network(rc) if is_unknown(rc, ["settings", 0, "ip_configuration", 0, "private_network"])

deny contains msg if {
	some rc in planned_resources
	rc.type == "google_sql_database_instance"
	not sql_ipv4_disabled(rc)
	msg := message("sql_public_ip", rc, sprintf(
		"Cloud SQL debe declarar settings.ip_configuration.ipv4_enabled = false (valor en el plan: %s)",
		[value_text(rc, ["settings", 0, "ip_configuration", 0, "ipv4_enabled"])],
	))
}

deny contains msg if {
	some rc in planned_resources
	rc.type == "google_sql_database_instance"
	not sql_has_private_network(rc)
	msg := message("sql_public_ip", rc, "Cloud SQL debe declarar settings.ip_configuration.private_network (IP privada por Private Service Access)")
}
