# Regla 12 (ADR 0029 §4): regla de recursos únicos en las raíces de entorno.
#
# Solo se aplica al plan de una raíz de entorno (`2-networks/envs/<env>` y
# `3-workloads/envs/<env>`): el que trae la variable `environment` con `dev`, `qa` o `prod` en la
# sección `variables` de `terraform show -json`. `0-bootstrap`, `1-base` y el hub no declaran esa
# variable, y los planes de ejemplo sin variables no se revisan aquí.
#
# En esas raíces rechaza:
# 1. Tipos que existen una vez por proyecto (§4.1 y la tabla de §2): la lista PROJECT_SINGLETONS
#    de `scripts/destroy-plan-check.py`, más `google_project` (§1) y las familias
#    `google_compute_project_metadata*` y `google_scc_*notification*`.
# 2. Tipos por entorno que el ADR pasa a `1-base` (§4, "Llaves y secretos" e "Imágenes"):
#    llaveros y llaves de KMS, contenedores de secretos y repositorios de Artifact Registry. La
#    raíz del entorno solo da permisos sobre ellos.
# 3. IAM de proyecto y de cuentas de servicio (§4.2, hallazgo N5 de la revisión R1): todo
#    `google_project_iam_member` y `google_project_iam_member_remove`, sea cual sea el principal
#    (también las cuentas `<prefix>-<env>-...`), y todo `google_service_account_iam_*` (`_member`,
#    `_binding`, `_policy`). Los roles de proyecto de las cuentas de ejecución, Cloud SQL por IAM y
#    el enlace de Workload Identity los da `1-base`; los de las cuentas del pipeline, `0-bootstrap`.
#    `google_project_iam_binding` y `_policy` ya los rechaza la regla 1 (una vez por proyecto). El
#    IAM de un recurso (secretos, repositorios, valores de etiqueta, servicios de Cloud Run,
#    buckets...) sí se permite: no da permisos sobre otros recursos del proyecto.
# 4. Nombres sin `<prefix>-<env>-` (§4.3), solo en los tipos que el ADR identifica por el nombre:
#    los que no llevan etiquetas y se reconocen por él al buscar huérfanos (§8: VPC, subredes,
#    routers, políticas de firewall de red y cuentas de servicio), y los buckets, porque el
#    `storage.admin` de la cuenta del entorno va condicionado a ese prefijo (§3). Los demás tipos
#    no se revisan: GCP les da el nombre (alertas, claves de etiqueta), son hijos que llevan el
#    nombre del padre (bases de datos de Cloud SQL, registros DNS) o se reconocen por la etiqueta
#    `env`.
# 1, 2 y 3 se revisan por tipo; 4 toma el prefijo de la variable `prefix` del plan y sin ella no se
# revisa.
#
# Valores desconocidos: un nombre que se calcula en el apply no se puede leer y no se rechaza (1, 2
# y 3 no leen valores).
package main

env_root_environments := {"dev", "qa", "prod"}

# Entorno de la raíz, si el plan es de una raíz de entorno.
env_root_env := env if {
	env := input.variables.environment.value
	env in env_root_environments
}

# Inicio obligatorio de los nombres del entorno: `<prefix>-<env>-`.
env_root_marker := sprintf("%s-%s-", [prefix, env_root_env]) if {
	prefix := input.variables.prefix.value
	is_string(prefix)
	regex.match(`^[a-z][a-z0-9]*$`, prefix)
}

env_root_singleton_types := {
	"google_project",
	"google_project_service",
	"google_project_services",
	"google_project_iam_audit_config",
	"google_project_iam_binding",
	"google_project_iam_policy",
	"google_project_iam_custom_role",
	"google_project_default_service_accounts",
	"google_project_organization_policy",
	"google_org_policy_policy",
	"google_binary_authorization_policy",
	"google_essential_contacts_contact",
	"google_logging_project_sink",
	"google_logging_project_bucket_config",
	"google_logging_project_exclusion",
	"google_billing_budget",
	"google_iam_deny_policy",
	"google_iam_workload_identity_pool",
	"google_iam_workload_identity_pool_provider",
	"google_access_context_manager_service_perimeter",
	"google_access_context_manager_service_perimeter_resource",
	"google_access_context_manager_service_perimeter_dry_run_resource",
}

env_root_singleton(type) if type in env_root_singleton_types

env_root_singleton(type) if startswith(type, "google_compute_project_metadata")

env_root_singleton(type) if regex.match(`^google_scc_[a-z0-9_]*notification`, type)

env_root_base_types := {
	"google_kms_key_ring",
	"google_kms_crypto_key",
	"google_secret_manager_secret",
	"google_artifact_registry_repository",
}

env_root_project_member_types := {"google_project_iam_member", "google_project_iam_member_remove"}

# IAM de proyecto o de cuentas de servicio (regla 3). binding y policy de proyecto van en
# env_root_singleton_types (regla 1), que se compara con scripts/destroy-plan-check.py.
env_root_iam_grant(type) if type in env_root_project_member_types

env_root_iam_grant(type) if startswith(type, "google_service_account_iam_")

# Atributo con el nombre, por tipo (§4.3).
env_root_name_attrs := {
	"google_compute_network": "name",
	"google_compute_subnetwork": "name",
	"google_compute_router": "name",
	"google_compute_network_firewall_policy": "name",
	"google_compute_region_network_firewall_policy": "name",
	"google_service_account": "account_id",
	"google_storage_bucket": "name",
}

deny contains msg if {
	env := env_root_env
	some rc in planned_resources
	env_root_singleton(rc.type)
	msg := message("env_root_scope", rc, sprintf(
		"%s existe una vez por proyecto: lo declaran 0-bootstrap o 1-base, nunca la raíz del entorno %s (ADR 0029 §4)",
		[rc.type, env],
	))
}

deny contains msg if {
	env := env_root_env
	some rc in planned_resources
	rc.type in env_root_base_types
	msg := message("env_root_scope", rc, sprintf(
		"%s del entorno lo crea 1-base; la raíz del entorno %s solo da permisos sobre él (ADR 0029 §4)",
		[rc.type, env],
	))
}

deny contains msg if {
	env := env_root_env
	some rc in planned_resources
	env_root_iam_grant(rc.type)
	msg := message("env_root_scope", rc, sprintf(
		"%s: la raíz del entorno %s no da roles de proyecto ni administra el IAM de cuentas de servicio; lo hacen 0-bootstrap y 1-base (ADR 0029 §4)",
		[rc.type, env],
	))
}

deny contains msg if {
	marker := env_root_marker
	some rc in planned_resources
	attr := env_root_name_attrs[rc.type]
	name := object.get(rc.change.after, attr, null)
	is_string(name)
	not startswith(name, marker)
	msg := message("env_root_scope", rc, sprintf(
		"%s = %s no empieza con %s: los recursos de la raíz del entorno llevan el prefijo del entorno (ADR 0029 §4)",
		[attr, name, marker],
	))
}
