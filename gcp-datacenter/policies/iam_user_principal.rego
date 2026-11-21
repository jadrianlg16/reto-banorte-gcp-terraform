# Regla 7 (§9.1 y §7.1): asignación de IAM a un principal `user:`.
#
# Los roles se asignan a grupos y cuentas de servicio, nunca a personas. Aplica a cualquier
# recurso `*_iam_member`, `*_iam_binding` o `*_iam_policy` del proveedor (proyecto, carpeta,
# organización, bucket, cuenta de servicio, KMS, secreto...), en sus tres formas: `member`,
# `members` y `policy_data`.
#
# Valores desconocidos: un principal que se calcula en el apply (por ejemplo, el correo de una
# cuenta de servicio creada en el mismo plan) no se puede leer aquí y no se rechaza; el módulo
# `iam` ya rechaza `user:` por validación de variables (§8).
package main

deny contains msg if {
	some rc in planned_resources
	is_iam_type(rc.type)
	some member in iam_members(rc.change.after)
	startswith(lower(member), "user:")
	msg := message("iam_user_principal", rc, sprintf(
		"asigna un rol a %s: los roles se otorgan a grupos o cuentas de servicio, nunca a user:",
		[member],
	))
}
