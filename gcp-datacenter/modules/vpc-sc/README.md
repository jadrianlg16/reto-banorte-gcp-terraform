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
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [google_access_context_manager_service_perimeter.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/access_context_manager_service_perimeter) | resource |
| [google_access_context_manager_service_perimeter_dry_run_ingress_policy.pipeline](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/access_context_manager_service_perimeter_dry_run_ingress_policy) | resource |
| [google_access_context_manager_service_perimeter_dry_run_resource.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/access_context_manager_service_perimeter_dry_run_resource) | resource |
| [google_access_context_manager_service_perimeter_ingress_policy.pipeline](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/access_context_manager_service_perimeter_ingress_policy) | resource |
| [google_access_context_manager_service_perimeter_resource.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/access_context_manager_service_perimeter_resource) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_access_policy_id"></a> [access\_policy\_id](#input\_access\_policy\_id) | ID numérico de la política de Access Context Manager de la organización, que ya existe (el módulo no la crea: es una por organización y la administra una persona). | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno del nombre del perímetro. common (el de 1-base) cuando rodea todo el proyecto único (ADR 0029 §1); dev, qa o prod si algún día se separa uno por entorno. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (por ejemplo, bnt). | `string` | n/a | yes |
| <a name="input_restricted_services"></a> [restricted\_services](#input\_restricted\_services) | Servicios restringidos por el perímetro (por ejemplo storage.googleapis.com). Debe incluir storage.googleapis.com. | `list(string)` | n/a | yes |
| <a name="input_egress_policies"></a> [egress\_policies](#input\_egress\_policies) | Reglas de salida opcionales. Cada una: identities (miembros serviceAccount:/group:/<br/>principal...; vacío con identity\_type), identity\_type (ANY\_IDENTITY, ANY\_USER\_ACCOUNT,<br/>ANY\_SERVICE\_ACCOUNT o null), resources (projects/<número> o "*"), external\_resources y<br/>operations (mapa servicio → lista de métodos; lista vacía = todos los métodos). | <pre>list(object({<br/>    identities         = optional(list(string), [])<br/>    identity_type      = optional(string)<br/>    resources          = optional(list(string), [])<br/>    external_resources = optional(list(string), [])<br/>    operations         = map(list(string))<br/>  }))</pre> | `[]` | no |
| <a name="input_enforced"></a> [enforced](#input\_enforced) | true: configuración forzada (status). false: modo dry-run (spec con use\_explicit\_dry\_run\_spec), que solo registra violaciones. Por defecto dry-run (ADR 0009). | `bool` | `false` | no |
| <a name="input_ingress_identities"></a> [ingress\_identities](#input\_ingress\_identities) | Cuentas de servicio del pipeline (serviceAccount:...) que pueden entrar al perímetro desde cualquier origen, a todos sus servicios y proyectos. | `list(string)` | `[]` | no |
| <a name="input_perimeter_name"></a> [perimeter\_name](#input\_perimeter\_name) | Nombre corto del perímetro (solo letras, dígitos y guion bajo). Si es null: <prefix>\_<environment>\_sec\_perimeter. | `string` | `null` | no |
| <a name="input_resources"></a> [resources](#input\_resources) | Proyectos que este módulo mete al perímetro, como projects/<número>. Otras raíces pueden agregar más con sus propios recursos (ver README). | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_access_policy_id"></a> [access\_policy\_id](#output\_access\_policy\_id) | ID numérico de la política de Access Context Manager (creada o recibida). |
| <a name="output_enforced"></a> [enforced](#output\_enforced) | true si el perímetro está forzado; false si está en dry-run. Otra raíz que agregue altas lo usa para elegir el recurso. |
| <a name="output_perimeter_name"></a> [perimeter\_name](#output\_perimeter\_name) | Nombre completo del perímetro (accessPolicies/<política>/servicePerimeters/<nombre>), el que piden los recursos de alta de proyectos. |
| <a name="output_perimeter_short_name"></a> [perimeter\_short\_name](#output\_perimeter\_short\_name) | Nombre corto del perímetro. |
| <a name="output_spec_ingress_policies"></a> [spec\_ingress\_policies](#output\_spec\_ingress\_policies) | Reglas de entrada dry-run (spec) que administra este módulo (recursos ...\_dry\_run\_ingress\_policy): lista de { title, ingress\_from, ingress\_to }; vacía si está forzado. No incluye las que agreguen otras raíces. Para revisión y pruebas. |
| <a name="output_status_ingress_policies"></a> [status\_ingress\_policies](#output\_status\_ingress\_policies) | Reglas de entrada forzadas (status) que administra este módulo (recursos ...\_ingress\_policy): lista de { title, ingress\_from, ingress\_to }; vacía en dry-run. No incluye las que agreguen otras raíces. Para revisión y pruebas. |
<!-- END_TF_DOCS -->
