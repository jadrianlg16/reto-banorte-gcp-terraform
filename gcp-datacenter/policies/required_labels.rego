# Regla 3 (§9.1 y §4.3): recurso etiquetable sin las cinco etiquetas obligatorias o con
# `managed_by` distinto de "terraform".
#
# Solo se exige en los tipos de la lista de abajo, que admiten etiquetas en el proveedor
# `hashicorp/google` 6.x (revisado contra la documentación de la versión v6.50.0). Los tipos
# que no las admiten (redes, subredes, routers, llaveros de KMS, políticas, IAM...) quedan fuera.
#
# Dónde viven las etiquetas en el plan:
# - `labels`: solo las declaradas en el recurso.
# - `terraform_labels`: `labels` más las `default_labels` del bloque `provider`. Se conoce en el
#   plan, así que una etiqueta puesta solo en `default_labels` cuenta.
# - `effective_labels`: además incluye etiquetas puestas fuera de Terraform; no se usa.
# - GKE usa `resource_labels` (las `labels` de `node_config` son de Kubernetes).
# - Cloud SQL usa `settings[0].user_labels` y no recibe `default_labels`.
#
# Valores desconocidos: una etiqueta cuya llave existe pero cuyo valor se calcula en el apply
# cuenta como presente; `managed_by` debe ser conocido e igual a "terraform".
package main

required_label_keys := ["env", "app", "owner", "cost_center", "managed_by"]

standard_label_paths := [["labels"], ["terraform_labels"]]

label_paths_by_type := {
	"google_storage_bucket": standard_label_paths,
	"google_compute_instance": standard_label_paths,
	"google_compute_instance_template": standard_label_paths,
	"google_compute_region_instance_template": standard_label_paths,
	"google_compute_disk": standard_label_paths,
	"google_compute_region_disk": standard_label_paths,
	"google_compute_image": standard_label_paths,
	"google_compute_snapshot": standard_label_paths,
	"google_compute_address": standard_label_paths,
	"google_compute_global_address": standard_label_paths,
	"google_compute_forwarding_rule": standard_label_paths,
	"google_compute_global_forwarding_rule": standard_label_paths,
	"google_container_cluster": [["resource_labels"], ["terraform_labels"]],
	"google_sql_database_instance": [["settings", 0, "user_labels"]],
	"google_redis_instance": standard_label_paths,
	"google_filestore_instance": standard_label_paths,
	"google_cloud_run_v2_service": standard_label_paths,
	"google_cloud_run_v2_job": standard_label_paths,
	"google_kms_crypto_key": standard_label_paths,
	"google_secret_manager_secret": standard_label_paths,
	"google_project": standard_label_paths,
	"google_dns_managed_zone": standard_label_paths,
	"google_pubsub_topic": standard_label_paths,
	"google_pubsub_subscription": standard_label_paths,
	"google_bigquery_dataset": standard_label_paths,
}

# Llaves de etiqueta presentes en el plan, conocidas o con valor desconocido.
label_keys_present(rc, paths) := {key |
	some path in paths
	some source in [rc.change.after, after_unknown(rc)]
	labels := path_value(source, path)
	is_object(labels)
	some key, _ in labels
}

# Valores conocidos de `managed_by`.
managed_by_values(rc, paths) := {value |
	some path in paths
	labels := path_value(rc.change.after, path)
	is_object(labels)
	value := labels.managed_by
	is_string(value)
}

deny contains msg if {
	some rc in planned_resources
	paths := label_paths_by_type[rc.type]
	present := label_keys_present(rc, paths)
	missing := [key | some key in required_label_keys; not key in present]
	count(missing) > 0
	msg := message("required_labels", rc, sprintf(
		"faltan etiquetas obligatorias: %s (se exigen env, app, owner, cost_center, managed_by)",
		[concat(", ", missing)],
	))
}

deny contains msg if {
	some rc in planned_resources
	paths := label_paths_by_type[rc.type]
	"managed_by" in label_keys_present(rc, paths)
	values := managed_by_values(rc, paths)
	values != {"terraform"}
	msg := message("required_labels", rc, sprintf(
		"managed_by debe ser \"terraform\" (valor en el plan: %s)",
		[managed_by_text(values)],
	))
}

managed_by_text(values) := "desconocido hasta el apply" if {
	count(values) == 0
} else := concat(", ", sort(values))
