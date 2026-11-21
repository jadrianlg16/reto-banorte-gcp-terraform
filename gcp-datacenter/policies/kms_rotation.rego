# Regla 6 (§9.1): llave KMS sin rotación o con rotación mayor a 90 días (7 776 000 s).
#
# Solo aplica a llaves de propósito ENCRYPT_DECRYPT (el valor por defecto del proveedor), que
# son las únicas que admiten rotación automática. `rotation_period` desconocido en el plan se
# rechaza: debe llegar por variable, que siempre se conoce en el plan.
package main

kms_max_rotation_seconds := 7776000

kms_purpose(after) := purpose if {
	purpose := after.purpose
	is_string(purpose)
} else := "ENCRYPT_DECRYPT"

# Segundos de un valor con formato de duración de la API ("7776000s" o "7776000.5s").
kms_rotation_seconds(period) := to_number(trim_suffix(period, "s")) if {
	regex.match(`^[0-9]+(\.[0-9]+)?s$`, period)
}

kms_has_rotation(after) if is_string(after.rotation_period)

kms_rotation_text(rc) := value_text(rc, ["rotation_period"])

deny contains msg if {
	some rc in planned_resources
	rc.type == "google_kms_crypto_key"
	kms_purpose(rc.change.after) == "ENCRYPT_DECRYPT"
	not kms_has_rotation(rc.change.after)
	msg := message("kms_rotation", rc, sprintf(
		"la llave debe declarar rotation_period <= 7776000s (valor en el plan: %s)",
		[kms_rotation_text(rc)],
	))
}

deny contains msg if {
	some rc in planned_resources
	rc.type == "google_kms_crypto_key"
	kms_purpose(rc.change.after) == "ENCRYPT_DECRYPT"
	period := rc.change.after.rotation_period
	is_string(period)
	not kms_rotation_seconds(period)
	msg := message("kms_rotation", rc, sprintf("rotation_period con formato no reconocido: %s", [period]))
}

deny contains msg if {
	some rc in planned_resources
	rc.type == "google_kms_crypto_key"
	kms_purpose(rc.change.after) == "ENCRYPT_DECRYPT"
	period := rc.change.after.rotation_period
	kms_rotation_seconds(period) > kms_max_rotation_seconds
	msg := message("kms_rotation", rc, sprintf(
		"rotation_period %s supera el máximo de 7776000s (90 días)",
		[period],
	))
}
