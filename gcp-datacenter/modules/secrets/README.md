# Módulo `secrets`

Crea contenedores de Secret Manager (sin versiones) y da
`roles/secretmanager.secretAccessor` sobre ellos a los miembros de `accessors`.

La especificación (sección "Componentes del datacenter", seguridad) pide secretos sin texto
plano en Terraform y cifrados con llaves propias. Por eso (ADR 0015):

- El módulo no tiene ninguna variable por la que pueda entrar el valor de un secreto, ni crea
  `google_secret_manager_secret_version`. Las versiones se cargan fuera de Terraform, así el
  valor nunca queda en el estado ni en el plan.
- La replicación es siempre administrada por el usuario: una réplica por región de
  `kms_keys`, cada una con CMEK y la llave de su misma región (validado). Sin `kms_keys` no
  hay secreto; la replicación automática no se ofrece.
- `accessors` rechaza `user:`, `allUsers` y `allAuthenticatedUsers` por validación.
- `deletion_protection` está activa por defecto: borrar el contenedor borra todas sus
  versiones.
- Los secretos llevan las cinco etiquetas obligatorias más `secret`.

Nombres (§4.2 del contrato): `<prefix>-<environment>-sec-<nombre>`.

Requisito previo: el agente de servicio de Secret Manager del proyecto necesita
`roles/cloudkms.cryptoKeyEncrypterDecrypter` sobre cada llave de `kms_keys`. Lo da la etapa
que llama al módulo (la 2, con el módulo `kms`), antes de crear los secretos.

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
| [google_secret_manager_secret.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret) | resource |
| [google_secret_manager_secret_iam_member.accessor](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_iam_member) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno dueño de los secretos: common, dev, qa o prod. | `string` | n/a | yes |
| <a name="input_kms_keys"></a> [kms\_keys](#input\_kms\_keys) | Mapa región → ID de la llave KMS (projects/<p>/locations/<región>/keyRings/<k>/cryptoKeys/<n>)<br/>con la que se cifra la réplica de esa región. Cada región del mapa es una réplica<br/>(replicación administrada por el usuario); la llave debe estar en la misma región. | `map(string)` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes. Obligatorias: env, app, owner, cost\_center, managed\_by. | `map(string)` | n/a | yes |
| <a name="input_names"></a> [names](#input\_names) | Nombres cortos de los secretos; el ID final es <prefix>-<environment>-sec-<nombre>. | `set(string)` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (por ejemplo, bnt). | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto donde se crean los contenedores de secretos. | `string` | n/a | yes |
| <a name="input_accessors"></a> [accessors](#input\_accessors) | Miembros que reciben roles/secretmanager.secretAccessor sobre todos los secretos del módulo. Sin user:. | `list(string)` | `[]` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Impide que Terraform borre los contenedores (y con ellos todas sus versiones). | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_secret_ids"></a> [secret\_ids](#output\_secret\_ids) | Mapa nombre corto → ID del secreto (projects/<proyecto>/secrets/<id>). |
| <a name="output_secret_names"></a> [secret\_names](#output\_secret\_names) | Mapa nombre corto → secret\_id (<prefix>-<environment>-sec-<nombre>). |
<!-- END_TF_DOCS -->
