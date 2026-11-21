# Regla 2 (§9.1): instancia o plantilla sin Shielded VM.
#
# Se exige el bloque `shielded_instance_config` con arranque seguro, vTPM y supervisión de
# integridad encendidos. El proveedor solo enciende por defecto vTPM e integridad; el arranque
# seguro viene apagado, así que omitir el bloque se rechaza. Un indicador desconocido hasta el
# apply también se rechaza: debe ser una constante en el código.
package main

shielded_vm_types := {
	"google_compute_instance",
	"google_compute_instance_template",
	"google_compute_region_instance_template",
}

shielded_vm_flags := ["enable_secure_boot", "enable_vtpm", "enable_integrity_monitoring"]

shielded_flag_on(after, flag) if after.shielded_instance_config[0][flag] == true

deny contains msg if {
	some rc in planned_resources
	rc.type in shielded_vm_types
	missing := [flag | some flag in shielded_vm_flags; not shielded_flag_on(rc.change.after, flag)]
	count(missing) > 0
	msg := message("shielded_vm", rc, sprintf(
		"Shielded VM incompleta: shielded_instance_config debe tener en true %s",
		[concat(", ", missing)],
	))
}
