# Módulo `vpc-sc`

Crea un perímetro regular de VPC Service Controls con sus servicios restringidos, una regla de
entrada para las cuentas de servicio del pipeline (`ingress_identities`, como recurso aparte),
reglas de salida opcionales (`egress_policies`) y el alta de los proyectos de `resources` en el
perímetro. Trabaja sobre una política de Access Context Manager que ya existe
(`access_policy_id`, obligatoria): la política es una por organización y no la crea el pipeline.

En el diseño de un solo proyecto (ADR 0029 §1) el perímetro es opcional: `1-base` lo crea solo si
hay organización y llega `access_policy_id`, con `environment = "common"`. Rodea todo el
proyecto, queda en dry-run y no separa entornos. La especificación (sección "Componentes del
datacenter", seguridad) pide un perímetro para los datos: por eso `restricted_services` debe
incluir al menos `storage.googleapis.com` (validación), los recursos deben ser números de
proyecto y las identidades de entrada y salida rechazan `user:`.

## Modo forzado y dry-run

`enforced` elige dónde vive la configuración (ADR 0009, dry-run por defecto):

| `enforced` | Configuración | `use_explicit_dry_run_spec` | Alta de proyectos | Regla de entrada del pipeline |
|---|---|---|---|---|
| `false` | `spec` (solo registra violaciones) | `true` | `google_access_context_manager_service_perimeter_dry_run_resource` | `google_access_context_manager_service_perimeter_dry_run_ingress_policy` |
| `true` | `status` (bloquea) | `false` | `google_access_context_manager_service_perimeter_resource` | `google_access_context_manager_service_perimeter_ingress_policy` |

La salida `enforced` le dice a otra raíz que agregue altas cuál de los recursos usar. Las
salidas `status_ingress_policies` y `spec_ingress_policies` muestran la regla de entrada que
administra este módulo (construidas desde sus recursos; no incluyen reglas de otras raíces).

## Proyectos y reglas de entrada agregados desde otras raíces

Con un solo proyecto, `1-base` mete el proyecto completo y ninguna otra raíz agrega altas. El
mecanismo de recursos separados se conserva porque es el que piden las páginas del proveedor
6.x y deja abierta la puerta a otras altas sin drift:

- El perímetro nunca declara `resources` ni `ingress_policies`: tiene `ignore_changes` sobre
  `status[0].resources`, `spec[0].resources`, `status[0].ingress_policies` y
  `spec[0].ingress_policies`.
- Los proyectos de este módulo (`resources`) entran con los recursos de alta separados.
- La regla de las cuentas del pipeline (`ingress_identities`) también es un recurso aparte, con
  `create_before_destroy = true` (el proveedor la quita y la vuelve a agregar al cambiarla; así
  la nueva entra antes de quitar la vieja).
- Orden en la primera creación: perímetro (sin proyectos ni reglas) → regla de entrada del
  pipeline → alta de proyectos (`depends_on`). Un perímetro sin proyectos no restringe nada, así
  que no hay ventana en que el pipeline quede fuera del proyecto ya protegido.
- Las reglas de salida (`egress_policies`) siguen en línea.
- El título de la regla del pipeline es `<nombre corto>-pipeline-<hash>`, con los 8 primeros
  caracteres del SHA-256 de las identidades ordenadas. La API exige títulos únicos dentro del
  perímetro y todos los campos de la regla fuerzan reemplazo: con un título fijo, el reemplazo
  con `create_before_destroy` agregaría una segunda regla con el mismo título antes de quitar
  la vieja.

Si algún día otra raíz agrega altas o reglas, vale la regla de operación anterior: un plan
guardado que cambia el perímetro solo se aplica si ninguna otra raíz agregó altas o reglas
después de crearlo, porque el proveedor manda `status` o `spec` completos con lo que leyó al
planear.

Nombre (§4.2 del contrato, adaptado): los perímetros no admiten guiones, así que el nombre
corto por defecto es `<prefix>_<environment>_sec_perimeter`.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
