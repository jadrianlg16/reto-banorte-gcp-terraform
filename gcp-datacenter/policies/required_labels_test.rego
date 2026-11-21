# Pruebas de la regla 3: etiquetas obligatorias.
package main

labeled_secret := {
	"secret_id": "bnt-dev-sec-db-config",
	"labels": mk_labels,
	"terraform_labels": mk_labels,
}

test_labels_complete_passes if {
	rc := mk_create("google_secret_manager_secret.this", "google_secret_manager_secret", labeled_secret)
	count(all_denials(mk_plan([rc]))) == 0
}

test_labels_missing_owner_denied if {
	labels := object.remove(mk_labels, ["owner", "cost_center"])
	after := with_fields(labeled_secret, {"labels": labels, "terraform_labels": labels})
	rc := mk_create("google_secret_manager_secret.this", "google_secret_manager_secret", after)
	rule_denials(mk_plan([rc]), "required_labels") == {
		"[required_labels] google_secret_manager_secret.this: faltan etiquetas obligatorias: owner, cost_center (se exigen env, app, owner, cost_center, managed_by)",
	}
}

test_labels_managed_by_wrong_denied if {
	labels := object.union(mk_labels, {"managed_by": "consola"})
	after := with_fields(labeled_secret, {"labels": labels, "terraform_labels": labels})
	rc := mk_create("google_secret_manager_secret.this", "google_secret_manager_secret", after)
	denials := rule_denials(mk_plan([rc]), "required_labels")
	count(denials) == 1
	some msg in denials
	contains(msg, "valor en el plan: consola")
}

# Etiquetas puestas solo en default_labels del proveedor: llegan en terraform_labels.
test_labels_only_in_terraform_labels_passes if {
	after := with_fields(labeled_secret, {"labels": {}})
	rc := mk_create("google_secret_manager_secret.this", "google_secret_manager_secret", after)
	count(all_denials(mk_plan([rc]))) == 0
}

test_labels_null_map_denied if {
	after := {"secret_id": "bnt-dev-sec-db-config", "labels": null, "terraform_labels": {}}
	rc := mk_create("google_secret_manager_secret.this", "google_secret_manager_secret", after)
	count(rule_denials(mk_plan([rc]), "required_labels")) == 1
}

# Valor de etiqueta calculado en el apply: la llave cuenta como presente.
test_labels_value_unknown_passes if {
	labels := object.remove(mk_labels, ["app"])
	after := with_fields(labeled_secret, {"labels": labels, "terraform_labels": labels})
	rc := mk_change("google_secret_manager_secret.this", "google_secret_manager_secret", ["create"], after, {
		"labels": {"app": true},
		"terraform_labels": {"app": true},
	})
	count(all_denials(mk_plan([rc]))) == 0
}

test_labels_managed_by_unknown_denied if {
	labels := object.remove(mk_labels, ["managed_by"])
	after := with_fields(labeled_secret, {"labels": labels, "terraform_labels": labels})
	rc := mk_change("google_secret_manager_secret.this", "google_secret_manager_secret", ["create"], after, {
		"labels": {"managed_by": true},
		"terraform_labels": {"managed_by": true},
	})
	denials := rule_denials(mk_plan([rc]), "required_labels")
	count(denials) == 1
	some msg in denials
	contains(msg, "desconocido hasta el apply")
}

test_labels_gke_resource_labels_passes if {
	rc := mk_create("module.gke.google_container_cluster.this", "google_container_cluster", {
		"name": "bnt-dev-app-gke-usc1",
		"resource_labels": mk_labels,
		"terraform_labels": mk_labels,
	})
	# Solo la regla de etiquetas: este clúster mínimo no trae nodos privados ni Shielded VM.
	count(rule_denials(mk_plan([rc]), "required_labels")) == 0
}

test_labels_gke_node_labels_do_not_count if {
	rc := mk_create("module.gke.google_container_cluster.this", "google_container_cluster", {
		"name": "bnt-dev-app-gke-usc1",
		"resource_labels": {},
		"terraform_labels": {},
		"node_config": [{"labels": mk_labels}],
	})
	denials := rule_denials(mk_plan([rc]), "required_labels")
	count(denials) == 1
	some msg in denials
	contains(msg, "module.gke.google_container_cluster.this")
}

test_labels_sql_user_labels_missing_denied if {
	rc := mk_create("google_sql_database_instance.this", "google_sql_database_instance", {
		"name": "bnt-dev-data-sql",
		"labels": mk_labels,
		"settings": [{"tier": "db-custom-2-7680", "user_labels": {"env": "dev"}}],
	})
	count(rule_denials(mk_plan([rc]), "required_labels")) == 1
}

test_labels_not_labelable_type_ignored if {
	rc := mk_create("google_kms_key_ring.this", "google_kms_key_ring", {"name": "bnt-dev-sec-kr-usc1", "location": "us-central1"})
	count(all_denials(mk_plan([rc]))) == 0
}

test_labels_pure_delete_ignored if {
	rc := mk_change("google_secret_manager_secret.old", "google_secret_manager_secret", ["delete"], null, {})
	count(all_denials(mk_plan([rc]))) == 0
}

# Defensa: aunque un plan hecho a mano traiga `after` en una eliminación pura, no se revisa.
test_labels_pure_delete_with_after_ignored if {
	rc := mk_change("google_secret_manager_secret.old", "google_secret_manager_secret", ["delete"], {"secret_id": "old", "labels": {}}, {})
	count(all_denials(mk_plan([rc]))) == 0
}

# --- Tipos agregados tras la revisión (rutas del esquema de google 6.50.0) -------------------

# Tipo -> ruta de las etiquetas. Cada caso: sin etiquetas se rechaza; con ellas pasa.
new_label_cases := {
	"google_backup_dr_backup_vault": ["labels"],
	"google_gke_backup_backup_plan": ["labels"],
	"google_certificate_manager_certificate": ["labels"],
	"google_certificate_manager_dns_authorization": ["labels"],
	"google_compute_ha_vpn_gateway": ["labels"],
	"google_compute_external_vpn_gateway": ["labels"],
	"google_compute_vpn_tunnel": ["labels"],
	"google_compute_interconnect_attachment": ["labels"],
	"google_monitoring_alert_policy": ["user_labels"],
	"google_monitoring_custom_service": ["user_labels"],
	"google_monitoring_slo": ["user_labels"],
	"google_monitoring_uptime_check_config": ["user_labels"],
	"google_monitoring_notification_channel": ["user_labels"],
	"google_container_node_pool": ["node_config", 0, "resource_labels"],
}

labels_at(path, labels) := {path[0]: labels} if {
	count(path) == 1
} else := {path[0]: [{path[2]: labels}]}

test_labels_new_types_missing_denied if {
	denied := {type |
		some type, path in new_label_cases
		rc := mk_create(sprintf("%s.this", [type]), type, labels_at(path, {"env": "dev"}))
		count(rule_denials(mk_plan([rc]), "required_labels")) == 1
	}
	denied == object.keys(new_label_cases)
}

test_labels_new_types_complete_pass if {
	passed := {type |
		some type, path in new_label_cases
		rc := mk_create(sprintf("%s.this", [type]), type, labels_at(path, mk_labels))
		count(rule_denials(mk_plan([rc]), "required_labels")) == 0
	}
	passed == object.keys(new_label_cases)
}

# Monitoring: `labels` del canal es su configuración (por ejemplo, el correo) y no cuenta.
test_labels_notification_channel_config_labels_do_not_count if {
	rc := mk_create("google_monitoring_notification_channel.email", "google_monitoring_notification_channel", {
		"type": "email",
		"labels": object.union(mk_labels, {"email_address": "alertas@example.com"}),
		"user_labels": {},
	})
	count(rule_denials(mk_plan([rc]), "required_labels")) == 1
}

# Node pool: las `labels` de Kubernetes del nodo no cuentan, solo `resource_labels`.
test_labels_node_pool_kubernetes_labels_do_not_count if {
	rc := mk_create("google_container_node_pool.this", "google_container_node_pool", {
		"node_config": [{"labels": mk_labels, "resource_labels": {}}],
	})
	count(rule_denials(mk_plan([rc]), "required_labels")) == 1
}
