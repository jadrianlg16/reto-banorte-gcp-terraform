# Módulo `org`

Aplica las políticas de organización de la línea base con la API v2
(`google_org_policy_policy`) y crea el sink agregado de auditoría de la organización
(`include_children = true`) hacia `log_sink_destination`. La especificación (sección
"Componentes del datacenter", organización y gobierno, y su diagrama de jerarquía) pide nueve
políticas; el módulo las crea siempre y no tiene interruptores para apagarlas:

| Restricción | Regla |
|---|---|
| `compute.vmExternalIpAccess` | `deny_all`: ninguna VM con IP externa |
| `iam.disableServiceAccountKeyCreation` | forzada |
| `gcp.resourceLocations` | `in:<región>-locations` por cada `allowed_regions`, más `additional_allowed_locations` |
| `compute.requireShieldedVm` | forzada |
| `storage.publicAccessPrevention` | forzada |
| `storage.uniformBucketLevelAccess` | forzada |
| `compute.skipDefaultNetworkCreation` | forzada |
| `iam.allowedPolicyMemberDomains` | solo `directory_customer_id` |
| `sql.restrictPublicIp` | forzada |

Notas de uso:

- `policy_parent` (por defecto la organización) permite aplicar el mismo juego en una carpeta.
  Las excepciones puntuales (un proyecto o carpeta que necesite otra regla) se declaran en la
  etapa con su propio `google_org_policy_policy` sobre ese recurso, que prevalece sobre la
  heredada; no se modelan aquí para que el juego base no se pueda debilitar por variable.
- `gcp.resourceLocations` no limita los recursos globales. Para llaveros de KMS o buckets en la
  multirregión `us` hay que agregar `us` en `additional_allowed_locations`.
- Si el destino del sink es un bucket de Cloud Storage, el módulo da a la identidad del sink
  `roles/storage.objectCreator` sobre ese bucket (`grant_sink_writer`). El bucket se crea con
  `log-export` y `parent = null`, y se pasa su salida `destination`.

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
| [google_logging_organization_sink.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_organization_sink) | resource |
| [google_org_policy_policy.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/org_policy_policy) | resource |
| [google_storage_bucket_iam_member.sink_writer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allowed_regions"></a> [allowed\_regions](#input\_allowed\_regions) | Regiones permitidas por gcp.resourceLocations (por ejemplo, ["us-central1", "us-east4"]). Cada una se traduce al grupo de valores in:<región>-locations, que incluye sus zonas. | `list(string)` | n/a | yes |
| <a name="input_directory_customer_id"></a> [directory\_customer\_id](#input\_directory\_customer\_id) | ID de cliente de Cloud Identity / Google Workspace (Cxxxxxxxx) cuyo dominio es el único admitido en las políticas de IAM (iam.allowedPolicyMemberDomains). | `string` | n/a | yes |
| <a name="input_log_sink_destination"></a> [log\_sink\_destination](#input\_log\_sink\_destination) | Destino del sink agregado de la organización, por ejemplo storage.googleapis.com/<bucket> (salida destination del módulo log-export). | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | ID numérico de la organización. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa en los nombres (por ejemplo, bnt). | `string` | n/a | yes |
| <a name="input_additional_allowed_locations"></a> [additional\_allowed\_locations](#input\_additional\_allowed\_locations) | Valores extra para gcp.resourceLocations, tal cual: ubicaciones (por ejemplo, us para la multirregión de KMS o buckets) o grupos in:<grupo>-locations. Por defecto, ninguno. | `list(string)` | `[]` | no |
| <a name="input_grant_sink_writer"></a> [grant\_sink\_writer](#input\_grant\_sink\_writer) | Si es true y el destino es un bucket de Cloud Storage, el módulo da roles/storage.objectCreator sobre ese bucket a la identidad del sink. Para otros destinos el permiso lo asigna la etapa. | `bool` | `true` | no |
| <a name="input_log_sink_filter"></a> [log\_sink\_filter](#input\_log\_sink\_filter) | Filtro del sink agregado. Por defecto, todos los registros de auditoría de la organización. | `string` | `"logName:\"cloudaudit.googleapis.com\""` | no |
| <a name="input_policy_parent"></a> [policy\_parent](#input\_policy\_parent) | Dónde se aplican las nueve políticas: "organizations/<n>" o "folders/<n>". null (por defecto): la organización de org\_id. Las excepciones para un proyecto o carpeta concretos se declaran en la etapa con su propio google\_org\_policy\_policy. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_policy_names"></a> [policy\_names](#output\_policy\_names) | Mapa restricción → nombre completo de la política (<padre>/policies/<restricción>), con las nueve políticas. |
| <a name="output_policy_parent"></a> [policy\_parent](#output\_policy\_parent) | Recurso donde se aplicaron las políticas (organizations/<n> o folders/<n>). |
| <a name="output_sink_name"></a> [sink\_name](#output\_sink\_name) | Nombre del sink agregado de la organización. |
| <a name="output_sink_writer_identity"></a> [sink\_writer\_identity](#output\_sink\_writer\_identity) | Identidad que escribe el sink agregado ("serviceAccount:..."); necesita permiso de escritura en el destino. |
<!-- END_TF_DOCS -->
