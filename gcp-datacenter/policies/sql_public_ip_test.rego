# Pruebas de la regla 5: Cloud SQL con IP pública.
package main

private_sql(ip_configuration) := {
	"name": "bnt-dev-data-sql",
	"database_version": "POSTGRES_16",
	"region": "us-central1",
	"settings": [{
		"tier": "db-custom-2-7680",
		"user_labels": mk_labels,
		"ip_configuration": ip_configuration,
	}],
}

good_ip_configuration := [{
	"ipv4_enabled": false,
	"private_network": "projects/example-project/global/networks/bnt-dev-net-vpc",
	"ssl_mode": "ENCRYPTED_ONLY",
}]

test_sql_private_passes if {
	rc := mk_create("google_sql_database_instance.this", "google_sql_database_instance", private_sql(good_ip_configuration))
	count(all_denials(mk_plan([rc]))) == 0
}

test_sql_ipv4_enabled_denied if {
	ip := [object.union(good_ip_configuration[0], {"ipv4_enabled": true})]
	rc := mk_create("module.sql.google_sql_database_instance.this", "google_sql_database_instance", private_sql(ip))
	rule_denials(mk_plan([rc]), "sql_public_ip") == {
		"[sql_public_ip] module.sql.google_sql_database_instance.this: Cloud SQL debe declarar settings.ip_configuration.ipv4_enabled = false (valor en el plan: true)",
	}
}

# Sin bloque ip_configuration el proveedor deja ipv4_enabled en true.
test_sql_no_ip_configuration_denied if {
	rc := mk_create("google_sql_database_instance.this", "google_sql_database_instance", private_sql([]))
	count(rule_denials(mk_plan([rc]), "sql_public_ip")) == 2
}

test_sql_missing_private_network_denied if {
	ip := [object.remove(good_ip_configuration[0], ["private_network"])]
	rc := mk_create("google_sql_database_instance.this", "google_sql_database_instance", private_sql(ip))
	denials := rule_denials(mk_plan([rc]), "sql_public_ip")
	count(denials) == 1
	some msg in denials
	contains(msg, "private_network")
}

# La VPC se crea en el mismo plan: private_network es desconocido y se acepta.
test_sql_private_network_unknown_passes if {
	ip := [object.remove(good_ip_configuration[0], ["private_network"])]
	rc := mk_change("google_sql_database_instance.this", "google_sql_database_instance", ["create"], private_sql(ip), {
		"settings": [{"ip_configuration": [{"private_network": true}]}],
	})
	count(all_denials(mk_plan([rc]))) == 0
}

test_sql_ipv4_unknown_denied if {
	ip := [object.remove(good_ip_configuration[0], ["ipv4_enabled"])]
	rc := mk_change("google_sql_database_instance.this", "google_sql_database_instance", ["create"], private_sql(ip), {
		"settings": [{"ip_configuration": [{"ipv4_enabled": true}]}],
	})
	denials := rule_denials(mk_plan([rc]), "sql_public_ip")
	count(denials) == 1
	some msg in denials
	contains(msg, "desconocido hasta el apply")
}
