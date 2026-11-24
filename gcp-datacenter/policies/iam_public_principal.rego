# Regla 8 (ADR 0029 §1; parte pública de `iam.allowedPolicyMemberDomains`): asignación de IAM a
# `allUsers` o `allAuthenticatedUsers`.
#
# Sin organización no hay política que limite los principales. Esta regla rechaza los dos
# principales públicos en cualquier `*_iam_member`, `*_iam_binding` o `*_iam_policy` del proveedor
# (proyecto, secreto, KMS, Cloud Run, cuenta de servicio...), en sus tres formas: `member`,
# `members` y `policy_data`. Las asignaciones sobre Cloud Storage ya las rechaza la regla 1
# (`bucket_public_access`, junto con las ACL) y aquí se omiten para no repetir el mensaje.
#
# No hay excepción legítima en el código: Cloud Run público va detrás del balanceador con la
# verificación del invocador desactivada y sin `allUsers` (ADR 0020), y los módulos `iam`, `kms`,
# `secrets` y `cloud-run` ya rechazan los dos principales por validación.
#
# Lo que no cubre: la restricción por dominio de `iam.allowedPolicyMemberDomains` (sin Cloud
# Identity no hay dominio que admitir) ni los accesos de BigQuery fuera de IAM.
#
# Valores desconocidos: un principal que se calcula en el apply no se puede leer aquí y no se
# rechaza.
package main

deny contains msg if {
	some rc in planned_resources
	is_iam_type(rc.type)
	not is_storage_iam_type(rc.type)
	some member in iam_members(rc.change.after)
	lower(member) in public_principals
	msg := message("iam_public_principal", rc, sprintf(
		"asigna un rol a %s: ningún recurso se abre a principales públicos (allUsers, allAuthenticatedUsers)",
		[member],
	))
}
