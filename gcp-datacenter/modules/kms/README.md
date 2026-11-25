# Módulo `kms`

Crea un llavero de Cloud KMS en una ubicación (región o la multirregión `us`) y, dentro, una
llave simétrica por uso (`keys`). Opcionalmente da `roles/cloudkms.cryptoKeyEncrypterDecrypter`
sobre cada llave a los miembros indicados (cuentas de servicio, grupos o identidades
federadas; nunca `user:`).

La especificación (sección "Componentes del datacenter", seguridad) pide llaves con rotación
de 90 días y protegidas contra borrado. Por eso:

- El propósito es fijo (`ENCRYPT_DECRYPT`), el único que admite rotación automática.
- `rotation_period` vale `7776000s` por defecto y se aplica a todas las llaves del llavero; la
  validación rechaza valores mayores a 90 días (o menores a un día). No hay rotación por
  llave a propósito: así el valor se puede revisar de forma estática (checkov CKV_GCP_43).
- Las llaves tienen `lifecycle { prevent_destroy = true }`: cualquier plan que las destruya o
  las reemplace falla. Para retirar una llave a propósito hay que quitar el bloque en un PR.
- Las llaves llevan las cinco etiquetas obligatorias más `key_use`. Los llaveros no admiten
  etiquetas en GCP y tampoco se pueden borrar.

Nombres (§4.2 del contrato): llavero `<prefix>-<environment>-sec-keyring-<código corto>`
(`bnt-prod-sec-keyring-usc1`, `bnt-dev-sec-keyring-us`) y llave
`<prefix>-<environment>-sec-<uso>`. Los códigos cortos salen de `location_short_codes`.

Lo consumen `0-bootstrap` (llave del bucket de estado, `environment = "bootstrap"`) y `1-base`
(un llavero por entorno y ubicación, solo con las llaves que se usan). Los permisos de las
llaves para los agentes de servicio del proyecto los da `1-base` (`kms.tf`) con
`encrypter_decrypters`.

Pruebas: `tests/kms.tftest.hcl` usa `mock_provider` y `command = plan`. Con `prevent_destroy`
una prueba con `command = apply` fallaría al limpiar el estado al final, por eso no se usa.

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
| [google_kms_crypto_key.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_crypto_key) | resource |
| [google_kms_crypto_key_iam_member.encrypter_decrypter](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_crypto_key_iam_member) | resource |
| [google_kms_key_ring.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_key_ring) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno que usa las llaves: bootstrap (llave del estado), common, dev, qa o prod. | `string` | n/a | yes |
| <a name="input_keys"></a> [keys](#input\_keys) | Llaves a crear, por uso (gke, compute, sql, storage, filestore, redis, secrets, backup,<br/>state...). Todas son simétricas (ENCRYPT\_DECRYPT) y rotan con var.rotation\_period.<br/>Opciones: protection\_level (SOFTWARE o HSM), destroy\_scheduled\_duration y<br/>encrypter\_decrypters (miembros que reciben roles/cloudkms.cryptoKeyEncrypterDecrypter<br/>sobre la llave; sin user:). | <pre>map(object({<br/>    protection_level           = optional(string, "SOFTWARE")<br/>    destroy_scheduled_duration = optional(string, "2592000s")<br/>    encrypter_decrypters       = optional(list(string), [])<br/>  }))</pre> | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes. Obligatorias: env, app, owner, cost\_center, managed\_by. | `map(string)` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Ubicación del llavero: una región (us-central1, us-east4) o la multirregión us. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (por ejemplo, bnt). | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto donde se crean el llavero y las llaves. | `string` | n/a | yes |
| <a name="input_location_short_codes"></a> [location\_short\_codes](#input\_location\_short\_codes) | Mapa ubicación → código corto que se agrega al nombre del llavero. | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us": "us",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_rotation_period"></a> [rotation\_period](#input\_rotation\_period) | Periodo de rotación por defecto de las llaves, en segundos con sufijo s. Máximo 90 días. | `string` | `"7776000s"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_key_ids"></a> [key\_ids](#output\_key\_ids) | Mapa uso → ID de la llave (projects/.../keyRings/.../cryptoKeys/<nombre>), el formato que piden los argumentos de CMEK. |
| <a name="output_key_names"></a> [key\_names](#output\_key\_names) | Mapa uso → nombre corto de la llave. |
| <a name="output_keyring_id"></a> [keyring\_id](#output\_keyring\_id) | ID del llavero (projects/<proyecto>/locations/<ubicación>/keyRings/<nombre>). |
| <a name="output_keyring_name"></a> [keyring\_name](#output\_keyring\_name) | Nombre corto del llavero. |
| <a name="output_location"></a> [location](#output\_location) | Ubicación del llavero y sus llaves. |
<!-- END_TF_DOCS -->
