# Módulo `storage`

Crea un bucket de Cloud Storage, regional o de doble región. La sección "Componentes del
datacenter" de la especificación pide para el almacenamiento de objetos CMEK, versionado,
reglas de ciclo de vida, acceso uniforme y ningún acceso público; el módulo lo fija así:

- CMEK obligatorio (`kms_key`); una validación exige que la llave esté en la misma ubicación
  que el bucket. Para doble región, la llave vive en la multirregión (`us`), donde la etapa 2
  crea un llavero para este caso.
- Versionado, `uniform_bucket_level_access = true` y `public_access_prevention = "enforced"`
  fijos.
- `lifecycle_rules` exige al menos una regla. Por defecto borra versiones no actuales a los
  30 días y aborta cargas multiparte incompletas a los 7 días.
- `dual_region` (opcional): dos regiones en `custom_placement_config` dentro de la multirregión
  `location`, con turbo replication (`rpo = "ASYNC_TURBO"`) por defecto. Es el bucket de DR de
  prod de la etapa 5.
- `retention_policy` opcional (bloquearla con `is_locked` es irreversible), borrado suave
  configurable, `force_destroy` false por defecto y prohibido en prod, y etiquetas.

El nombre sigue `<prefix>-<env>-data-<name>-<código de ubicación><name_suffix>`: el código es
el de la región, los de ambas regiones en doble región (`usc1-use4`) o la multirregión. Los
nombres de bucket son únicos a nivel mundial: `name_suffix` cumple el papel de `project_suffix`.

Cloud Storage se alcanza por Private Google Access desde las subredes, no por Private Service
Access. El registro de uso heredado del bucket no se activa (CKV_GCP_62 omitido): el acceso a
objetos queda en los registros de auditoría de acceso a datos.

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
| [google_storage_bucket.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno: dev, qa o prod. | `string` | n/a | yes |
| <a name="input_kms_key"></a> [kms\_key](#input\_kms\_key) | ID de la llave KMS (CMEK) del bucket. Su ubicación debe coincidir con location (para doble región, la multirregión, por ejemplo us). | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes. Obligatorias: env, app, owner, cost\_center, managed\_by. | `map(string)` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Ubicación del bucket: una región (us-central1) o, con dual\_region, la multirregión que contiene ambas regiones (us). | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (§4.2), por ejemplo bnt. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto donde se crea el bucket. | `string` | n/a | yes |
| <a name="input_dual_region"></a> [dual\_region](#input\_dual\_region) | Doble región configurable: dos regiones dentro de location y turbo replication (RPO de 15 min, ASYNC\_TURBO) por defecto. Nulo: bucket de una sola ubicación. | <pre>object({<br/>    regions           = list(string)<br/>    turbo_replication = optional(bool, true)<br/>  })</pre> | `null` | no |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Permite borrar el bucket con objetos dentro. false por defecto; en prod siempre false. | `bool` | `false` | no |
| <a name="input_lifecycle_rules"></a> [lifecycle\_rules](#input\_lifecycle\_rules) | Reglas de ciclo de vida (al menos una). Por defecto: borrar versiones no actuales a los 30 días y abortar cargas multiparte incompletas a los 7 días. | <pre>list(object({<br/>    action = object({<br/>      type          = string<br/>      storage_class = optional(string)<br/>    })<br/>    condition = object({<br/>      age                        = optional(number)<br/>      created_before             = optional(string)<br/>      with_state                 = optional(string)<br/>      matches_storage_class      = optional(list(string))<br/>      matches_prefix             = optional(list(string))<br/>      matches_suffix             = optional(list(string))<br/>      num_newer_versions         = optional(number)<br/>      days_since_noncurrent_time = optional(number)<br/>      noncurrent_time_before     = optional(string)<br/>      days_since_custom_time     = optional(number)<br/>    })<br/>  }))</pre> | <pre>[<br/>  {<br/>    "action": {<br/>      "type": "Delete"<br/>    },<br/>    "condition": {<br/>      "days_since_noncurrent_time": 30,<br/>      "with_state": "ARCHIVED"<br/>    }<br/>  },<br/>  {<br/>    "action": {<br/>      "type": "AbortIncompleteMultipartUpload"<br/>    },<br/>    "condition": {<br/>      "age": 7<br/>    }<br/>  }<br/>]</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | Parte <recurso> del nombre (§4.2). El nombre final es <prefix>-<environment>-data-<name>-<código de ubicación><name\_suffix>. | `string` | `"bucket"` | no |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Sufijo que se agrega al final del nombre para hacerlo único a nivel mundial (como project\_suffix). Vacío por defecto. | `string` | `""` | no |
| <a name="input_region_short_codes"></a> [region\_short\_codes](#input\_region\_short\_codes) | Mapa región → código corto que se agrega a los nombres (§4.2). | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_retention_policy"></a> [retention\_policy](#input\_retention\_policy) | Política de retención opcional: retention\_period en segundos e is\_locked. Bloquearla es irreversible. | <pre>object({<br/>    retention_period = number<br/>    is_locked        = optional(bool, false)<br/>  })</pre> | `null` | no |
| <a name="input_soft_delete_retention_seconds"></a> [soft\_delete\_retention\_seconds](#input\_soft\_delete\_retention\_seconds) | Retención de objetos borrados (borrado suave) en segundos: 0 la apaga; si no, entre 7 y 90 días. | `number` | `604800` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | Clase de almacenamiento por defecto. | `string` | `"STANDARD"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | Nombre del bucket. |
| <a name="output_bucket_self_link"></a> [bucket\_self\_link](#output\_bucket\_self\_link) | Self link del bucket. |
| <a name="output_bucket_url"></a> [bucket\_url](#output\_bucket\_url) | URL gs:// del bucket. |
| <a name="output_data_locations"></a> [data\_locations](#output\_data\_locations) | Regiones de la doble región; lista vacía si el bucket no es de doble región. |
| <a name="output_location"></a> [location](#output\_location) | Ubicación del bucket en mayúsculas (región o multirregión). |
<!-- END_TF_DOCS -->
