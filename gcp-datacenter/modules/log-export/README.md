# Módulo `log-export`

Crea un bucket de Cloud Storage para logs y, si se indica `parent`, el sink de Logging que
exporta hacia él desde una organización, una carpeta o un proyecto, junto con el permiso
`roles/storage.objectCreator` para la identidad que escribe el sink. La especificación
(sección "Componentes del datacenter", registro y auditoría) pide un bucket de logs con
retención bloqueable: por eso la política de retención siempre existe (`retention_days`, de
30 a 36 500 días) y su bloqueo lo controla `retention_locked`, que es **irreversible** una vez
aplicado. Además quedan como valores fijos: CMEK obligatorio (`kms_key`), acceso uniforme,
prevención de acceso público `enforced`, versionado activo y sin `force_destroy`. Las
versiones no actuales se borran cuando vence la retención.

Notas de uso:

- Con `parent` de organización o carpeta y `include_children = true` (por defecto) el sink es
  agregado. Con `parent` de proyecto se usa una identidad de escritura propia del sink.
- Con `parent = null` solo se crea el bucket: sirve cuando el sink lo crea otro módulo (por
  ejemplo `org`), que recibe la salida `destination`.
- El módulo da al agente de Cloud Storage del proyecto permiso para cifrar con `kms_key`
  (`grant_kms_to_storage_agent`). La llave debe estar en la misma ubicación que el bucket.
- El filtro por defecto exporta los registros de auditoría.

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
| [google_kms_crypto_key_iam_member.storage_agent](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_crypto_key_iam_member) | resource |
| [google_logging_folder_sink.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_folder_sink) | resource |
| [google_logging_organization_sink.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_organization_sink) | resource |
| [google_logging_project_sink.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_project_sink) | resource |
| [google_storage_bucket.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket_iam_member.writer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_storage_project_service_account.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/storage_project_service_account) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno según la convención de nombres: bootstrap, common, dev, qa o prod. | `string` | n/a | yes |
| <a name="input_kms_key"></a> [kms\_key](#input\_kms\_key) | ID completo de la llave KMS (CMEK) que cifra el bucket: projects/<p>/locations/<l>/keyRings/<r>/cryptoKeys/<k>. Obligatoria; debe estar en la misma ubicación que el bucket. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes. Obligatorias: env, app, owner, cost\_center, managed\_by. | `map(string)` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Ubicación del bucket: una región (us-central1), una doble región o una multirregión (US). Debe estar permitida por gcp.resourceLocations. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa en los nombres (por ejemplo, bnt). | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Proyecto donde se crea el bucket de logs (por ejemplo, el proyecto logging de common). | `string` | n/a | yes |
| <a name="input_retention_days"></a> [retention\_days](#input\_retention\_days) | Días que cada objeto queda protegido contra borrado y reemplazo (política de retención del bucket). | `number` | n/a | yes |
| <a name="input_access_logs_bucket"></a> [access\_logs\_bucket](#input\_access\_logs\_bucket) | Bucket que recibe los registros de acceso de este bucket. null: sin registros de acceso (los registros de auditoría de Cloud Storage siguen activos). | `string` | `null` | no |
| <a name="input_filter"></a> [filter](#input\_filter) | Filtro de Logging del sink. Por defecto, los registros de auditoría (actividad de administración, acceso a datos, eventos del sistema y política denegada). "" exporta todo. | `string` | `"logName:\"cloudaudit.googleapis.com\""` | no |
| <a name="input_grant_kms_to_storage_agent"></a> [grant\_kms\_to\_storage\_agent](#input\_grant\_kms\_to\_storage\_agent) | Si es true, el módulo da roles/cloudkms.cryptoKeyEncrypterDecrypter sobre kms\_key al agente de servicio de Cloud Storage del proyecto. false si ese permiso lo asigna otra etapa. | `bool` | `true` | no |
| <a name="input_include_children"></a> [include\_children](#input\_include\_children) | Solo para parent de organización o carpeta: si es true, el sink es agregado e incluye los logs de todas las carpetas y proyectos hijos. | `bool` | `true` | no |
| <a name="input_name"></a> [name](#input\_name) | Parte de recurso del nombre. Bucket: <prefix>-<environment>-ops-<name>[-<name\_suffix>]; sink: <prefix>-<environment>-ops-<name>-sink. | `string` | `"audit-logs"` | no |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Sufijo opcional para que el nombre del bucket sea único a nivel mundial (normalmente el project\_suffix de la raíz). Vacío: sin sufijo. | `string` | `""` | no |
| <a name="input_parent"></a> [parent](#input\_parent) | Recurso cuyos logs se exportan: "organizations/<n>", "folders/<n>" o "projects/<id>". null: solo se crea el bucket (otro módulo, por ejemplo org, crea el sink). | `string` | `null` | no |
| <a name="input_project_number"></a> [project\_number](#input\_project\_number) | Número de project\_id (opcional). Pasarlo cuando el proyecto se crea en el mismo plan: el agente de Cloud Storage se consulta con el número, que no se conoce hasta el apply, y así la consulta no corre en el plan contra un proyecto que todavía no existe. null: se consulta con project\_id (proyecto que ya existe). | `string` | `null` | no |
| <a name="input_retention_locked"></a> [retention\_locked](#input\_retention\_locked) | Si es true, bloquea la política de retención. IRREVERSIBLE: una vez aplicado, la retención no se puede acortar ni quitar, y el bucket no se puede borrar hasta que venza el último objeto. | `bool` | `false` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | Clase de almacenamiento por defecto del bucket. | `string` | `"STANDARD"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | Nombre del bucket de logs. |
| <a name="output_bucket_url"></a> [bucket\_url](#output\_bucket\_url) | URL gs:// del bucket de logs. |
| <a name="output_destination"></a> [destination](#output\_destination) | Destino de Logging del bucket (storage.googleapis.com/<bucket>), para un sink creado fuera del módulo. |
| <a name="output_sink_name"></a> [sink\_name](#output\_sink\_name) | Nombre del sink creado, o null si parent es null. |
| <a name="output_writer_identity"></a> [writer\_identity](#output\_writer\_identity) | Identidad que escribe el sink ("serviceAccount:..."), o null si parent es null. |
<!-- END_TF_DOCS -->
