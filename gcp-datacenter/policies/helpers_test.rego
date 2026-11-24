# Constructores de planes para las pruebas de Rego (`conftest verify`).
# Arman la forma de `terraform show -json` con solo los campos que leen las políticas.
package main

mk_plan(changes) := {
	"format_version": "1.2",
	"terraform_version": "1.9.8",
	"resource_changes": changes,
}

# Plan con variables de la raíz, en la forma de `terraform show -json`: {nombre: {"value": v}}.
mk_plan_vars(changes, vars) := object.union(mk_plan(changes), {"variables": {name: {"value": value} | some name, value in vars}})

mk_change(address, type, actions, after, unknown) := {
	"address": address,
	"mode": "managed",
	"type": type,
	"name": "this",
	"provider_name": "registry.terraform.io/hashicorp/google",
	"change": {
		"actions": actions,
		"before": null,
		"after": after,
		"after_unknown": unknown,
	},
}

mk_create(address, type, after) := mk_change(address, type, ["create"], after, {})

# Etiquetas completas de §4.3.
mk_labels := {
	"env": "dev",
	"app": "app",
	"owner": "plataforma",
	"cost_center": "ti-001",
	"managed_by": "terraform",
}

# Reemplaza campos de primer nivel. `object.union` mezcla objetos anidados de forma recursiva
# (no sirve para quitar etiquetas), por eso primero se quitan las llaves.
with_fields(obj, fields) := object.union(object.remove(obj, object.keys(fields)), fields)

# Denegaciones de una regla concreta para un plan.
rule_denials(plan, rule) := {msg |
	some msg in deny with input as plan
	startswith(msg, sprintf("[%s]", [rule]))
}

# Todas las denegaciones de un plan.
all_denials(plan) := {msg | some msg in deny with input as plan}
