# Regla 9 (ADR 0029 §1; reemplaza `iam.disableServiceAccountKeyCreation`): llave de una cuenta de
# servicio.
#
# El pipeline se autentica por Workload Identity Federation (ADR 0023) y las cargas con la cuenta
# adjunta al recurso o con Workload Identity de GKE: ninguna raíz necesita llaves. Se rechaza todo
# `google_service_account_key` que quede en el estado, con llave generada por Google o subida
# (`public_key_data`), también uno que ya existe (`no-op`). Borrarlo (`delete`) sí se permite.
# La fuente de datos del mismo nombre (`mode = "data"`) solo lee una llave y no se revisa.
package main

deny contains msg if {
	some rc in planned_resources
	rc.type == "google_service_account_key"
	msg := message("service_account_key", rc, sprintf(
		"llave de la cuenta %s: las llaves de cuentas de servicio están prohibidas (usar WIF o la cuenta adjunta al recurso)",
		[value_text(rc, ["service_account_id"])],
	))
}
