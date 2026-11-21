# Funciones compartidas por las políticas de §9.1 del contrato.
#
# Todas las reglas se evalúan sobre el plan en JSON (`terraform show -json`). Se recorre
# `resource_changes[*]` y se mira el estado posterior (`change.after`). Los valores que
# Terraform todavía no conoce en el plan no aparecen en `after`: se marcan con `true` en
# `change.after_unknown`, por eso cada regla decide explícitamente qué hacer con ellos.
#
# Ningún nombre de este archivo empieza con `deny`, `warn` ni `violation`: Conftest trataría
# esas reglas como resultados.
package main

# Recursos que la política debe revisar: administrados por Terraform (no fuentes de datos),
# con estado posterior y que no se están eliminando. Un reemplazo (["delete", "create"] o
# ["create", "delete"]) sí se revisa, porque deja un recurso nuevo.
planned_resources contains rc if {
	some rc in input.resource_changes
	rc.mode == "managed"
	not is_pure_delete(rc)
	is_object(rc.change.after)
}

is_pure_delete(rc) if rc.change.actions == ["delete"]

# `after_unknown` puede faltar en planes viejos o hechos a mano.
after_unknown(rc) := object.get(rc.change, "after_unknown", {})

# Valor de una ruta dentro de un objeto, o `null` si no existe. La ruta es una lista de
# llaves de objeto o índices de lista.
path_value(obj, path) := value if {
	value := object.get(obj, path, null)
} else := null

# Verdadero si Terraform marca la ruta como desconocida hasta el apply.
is_unknown(rc, path) if object.get(after_unknown(rc), path, false) == true

# Texto para mensajes: el valor del plan, o por qué no lo hay.
value_text(rc, path) := sprintf("%v", [v]) if {
	v := path_value(rc.change.after, path)
	v != null
} else := "desconocido hasta el apply" if {
	is_unknown(rc, path)
} else := "sin definir"

# Formato común de los mensajes: "[regla] dirección: explicación".
message(rule, rc, text) := sprintf("[%s] %s: %s", [rule, rc.address, text])

# Tipos de asignación de IAM del proveedor: `*_iam_member`, `*_iam_binding` y `*_iam_policy`
# (proyecto, carpeta, organización, bucket, cuenta de servicio, KMS, secreto, etc.).
is_iam_type(type) if regex.match(`^google_[a-z0-9_]+_iam_(member|binding|policy)$`, type)

# Principales conocidos en el plan para una asignación de IAM, en cualquiera de las tres formas:
# `member` (string), `members` (lista) y `policy_data` (JSON con `bindings[*].members[*]`).
# Los principales desconocidos hasta el apply no aparecen (ver README, limitaciones).
iam_members(after) := (single_member(after) | binding_members(after)) | policy_members(after)

single_member(after) := {m | m := after.member; is_string(m)}

binding_members(after) := {m | some m in after.members; is_string(m)}

policy_members(after) := {m |
	is_string(after.policy_data)
	policy := json.unmarshal(after.policy_data)
	some binding in policy.bindings
	some m in binding.members
	is_string(m)
}
