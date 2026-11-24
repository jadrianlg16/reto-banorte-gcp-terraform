# Regla 11 (ADR 0029 §1; reemplaza `gcp.resourceLocations`): recurso fuera de las ubicaciones
# permitidas.
#
# Permitidas, las mismas que `modules/org` da a la política de organización desde `1-base`:
# - `us-central1` (primaria) y `us-east4` (DR) con sus zonas: los grupos `in:<región>-locations`
#   de `primary_region` y `dr_region` (ADR 0002);
# - `us`, el valor de `additional_allowed_locations` por defecto: bucket de estado, llaveros y
#   repositorios multirregionales. Un bucket de doble región configurable también lleva
#   `location = "US"`, y sus dos regiones se revisan aparte;
# - `global` (la notificación de SCC de `1-base`, Certificate Manager, llaveros globales): no tiene
#   región.
# Para cambiar de región (por ejemplo, `northamerica-south1`, ADR 0002) se cambia esta lista junto
# con `primary_region` y `dr_region`.
#
# Dónde se lee, en cualquier recurso `google_*` y sin distinguir mayúsculas (Cloud Storage escribe
# `US-CENTRAL1`): `location`, `region` y `zone`; las regiones de un bucket de doble región
# (`custom_placement_config[*].data_locations[*]`); y las réplicas de un secreto
# (`replication[*].user_managed[*].replicas[*].location`). Las zonas anidadas (Cloud SQL,
# Memorystore, nodos de GKE) quedan dentro de la región del recurso, que sí se revisa.
#
# Un recurso que omite la región usa la del bloque `provider`: el plan la deja desconocida en el
# recurso (comprobado con google 6.50.0 en una subred sin `region`). Por eso también se revisan
# `region` y `zone` de cada bloque `provider "google"` o `"google-beta"` de la raíz
# (`configuration.provider_config`), con valor constante o tomado de una variable de la raíz
# (`region = var.primary_region`, como en las raíces de red y de cargas).
#
# Valores desconocidos o vacíos: no se rechazan. Un recurso que toma la ubicación de otro del mismo
# plan hereda la revisión del otro.
package main

resource_location_regions := {"us-central1", "us-east4"}

resource_location_others := {"us", "global"}

resource_location_allowed(value) if lower(value) in resource_location_regions

resource_location_allowed(value) if lower(value) in resource_location_others

# Zona de una región permitida: `<región>-<letra>`.
resource_location_allowed(value) if {
	some region in resource_location_regions
	startswith(lower(value), sprintf("%s-", [region]))
	regex.match(`^[a-z]$`, substring(lower(value), count(region) + 1, -1))
}

# Pares [ruta, valor] con las ubicaciones conocidas de un recurso.
resource_location_values(after) := (top | placement) | replicas if {
	top := {[attr, v] |
		some attr in ["location", "region", "zone"]
		v := object.get(after, attr, null)
		is_string(v)
		v != ""
	}
	placement := {[sprintf("custom_placement_config[%d].data_locations", [i]), v] |
		some i, config in list_at(after, "custom_placement_config")
		some v in list_at(config, "data_locations")
		is_string(v)
	}
	replicas := {[sprintf("replication[%d].user_managed[%d].replicas[%d].location", [i, j, k]), v] |
		some i, replication in list_at(after, "replication")
		some j, managed in list_at(replication, "user_managed")
		some k, replica in list_at(managed, "replicas")
		v := object.get(replica, "location", null)
		is_string(v)
	}
}

# Lista de un objeto, o vacía si falta o no es lista (`null` en el plan).
list_at(obj, key) := value if {
	is_object(obj)
	value := object.get(obj, key, [])
	is_array(value)
} else := []

# Valor de una expresión de `provider_config`: constante, o una sola referencia a una variable de
# la raíz (`var.<nombre>`) con su valor en `variables`.
provider_expression_value(expr) := value if {
	value := object.get(expr, "constant_value", null)
	value != null
} else := value if {
	refs := object.get(expr, "references", [])
	count(refs) == 1
	startswith(refs[0], "var.")
	value := input.variables[substring(refs[0], 4, -1)].value
}

# [bloque, atributo, valor] de la región y la zona por defecto de los proveedores de Google de la
# raíz. Los bloques dentro de módulos (`module_address`) no se resuelven.
resource_location_provider_values contains [key, attr, value] if {
	some key, config in object.get(object.get(input, "configuration", {}), "provider_config", {})
	config.name in {"google", "google-beta"}
	not config.module_address
	some attr in ["region", "zone"]
	value := provider_expression_value(config.expressions[attr])
	is_string(value)
	value != ""
}

deny contains msg if {
	some rc in planned_resources
	startswith(rc.type, "google_")
	some pair in resource_location_values(rc.change.after)
	not resource_location_allowed(pair[1])
	msg := message("resource_locations", rc, sprintf(
		"%s = %s está fuera de las ubicaciones permitidas (us-central1, us-east4 y sus zonas, us, global)",
		[pair[0], pair[1]],
	))
}

deny contains msg if {
	some entry in resource_location_provider_values
	not resource_location_allowed(entry[2])
	msg := sprintf(
		"[resource_locations] provider[%q]: %s = %s está fuera de las ubicaciones permitidas (us-central1, us-east4 y sus zonas, us, global); los recursos que no declaran la suya la usan",
		[entry[0], entry[1], entry[2]],
	)
}
