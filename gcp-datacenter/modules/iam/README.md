# Módulo `iam`

Asigna roles de forma aditiva: cada elemento de `bindings` se convierte en un recurso
`google_*_iam_member`, que agrega un miembro a un rol sin tocar a los demás miembros del
recurso. Nunca usa `*_iam_binding` ni `*_iam_policy`, que son autoritativos y podrían borrar
permisos puestos por otras etapas. La especificación (sección "Componentes del datacenter",
identidad y acceso) pide asignar roles a grupos y cuentas de servicio, nunca a personas: por
eso el módulo rechaza por validación cualquier miembro `user:` (también con mayúsculas) y solo
admite `group:`, `serviceAccount:`, `principal://` y `principalSet://` (identidades de
Workload Identity Federation). También rechaza `allUsers`, `allAuthenticatedUsers`, `domain:`
y los roles básicos `roles/owner` y `roles/editor`.

## Scopes admitidos

| `scope` | Recurso de Terraform | Formato de `resource` |
|---|---|---|
| `organization` | `google_organization_iam_member` | `organizations/<n>` o `<n>` |
| `project` | `google_project_iam_member` | ID del proyecto |
| `service_account` | `google_service_account_iam_member` | `projects/<p>/serviceAccounts/<correo>` |
| `storage_bucket` | `google_storage_bucket_iam_member` | nombre del bucket |
| `kms_key_ring` | `google_kms_key_ring_iam_member` | `projects/<p>/locations/<l>/keyRings/<r>` |
| `kms_crypto_key` | `google_kms_crypto_key_iam_member` | `projects/<p>/locations/<l>/keyRings/<r>/cryptoKeys/<k>` |
| `secret` | `google_secret_manager_secret_iam_member` | `projects/<p>/secrets/<s>` |
| `subnetwork` | `google_compute_subnetwork_iam_member` | `projects/<p>/regions/<r>/subnetworks/<s>` |

Se eligieron por lo que consumen las etapas del diseño de un solo proyecto (ADR 0029): roles
de proyecto de las cuentas del pipeline, condicionados por prefijo donde el servicio lo admite
(`0-bootstrap`), el rol de organización opcional para políticas de organización, Workload
Identity sobre esas cuentas, permisos condicionados por prefijo sobre el bucket de estado, IAM
de personas por grupos (`1-base`), llaves KMS y secretos para agentes de servicio y cuentas de
ejecución, y subredes. Ya no hay carpetas ni cuentas de facturación administradas por el
pipeline: los scopes `folder` y `billing_account` se quitaron. Todos admiten `condition`
(condiciones de IAM).

## Llaves del `for_each`

La llave de cada asignación es `key` si se da, o `scope|resource|role|member`. Debe conocerse
en el plan: cuando el miembro o el recurso se calculan en el mismo plan (por ejemplo, el correo
de una cuenta de servicio recién creada), hay que dar `key` explícita y estable, como
`"<etapa>-<rol>"`. Las validaciones de formato y de `user:` no pueden revisar un valor
desconocido en el plan; en ese caso el miembro sale de una cuenta de servicio creada por
Terraform (`serviceAccount:`), y la política de Conftest revisa el plan real.

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
| [google_billing_account_iam_member.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/billing_account_iam_member) | resource |
| [google_compute_subnetwork_iam_member.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_subnetwork_iam_member) | resource |
| [google_folder_iam_member.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/folder_iam_member) | resource |
| [google_kms_crypto_key_iam_member.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_crypto_key_iam_member) | resource |
| [google_kms_key_ring_iam_member.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_key_ring_iam_member) | resource |
| [google_organization_iam_member.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_member) | resource |
| [google_project_iam_member.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_secret_manager_secret_iam_member.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_iam_member) | resource |
| [google_service_account_iam_member.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_storage_bucket_iam_member.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_bindings"></a> [bindings](#input\_bindings) | Asignaciones aditivas de un rol a un miembro sobre un recurso. Campos:<br/>- scope: organization, folder, project, billing\_account, service\_account, storage\_bucket,<br/>  kms\_key\_ring, kms\_crypto\_key, secret o subnetwork.<br/>- resource: identificador del recurso según scope (ver README).<br/>- role: rol predefinido (roles/...) o personalizado (organizations/N/roles/... o projects/P/roles/...).<br/>- member: group:, serviceAccount:, principal:// o principalSet://. Nunca user:.<br/>- key (opcional): llave estable del for\_each. Obligatoria cuando resource, role o member no<br/>  se conocen en el plan (por ejemplo, el correo de una cuenta de servicio creada en el mismo<br/>  plan); si es null se usa "scope\|resource\|role\|member".<br/>- condition (opcional): condición de IAM { title, expression, description }. | <pre>list(object({<br/>    scope    = string<br/>    resource = string<br/>    role     = string<br/>    member   = string<br/>    key      = optional(string)<br/>    condition = optional(object({<br/>      title       = string<br/>      expression  = string<br/>      description = optional(string)<br/>    }))<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bindings"></a> [bindings](#output\_bindings) | Mapa llave del for\_each → { scope, resource, role, member } de cada asignación creada. |
| <a name="output_conditions"></a> [conditions](#output\_conditions) | Mapa llave del for\_each → condición de IAM ({ title, expression, description }) de cada asignación creada, o null si no tiene. |
| <a name="output_members"></a> [members](#output\_members) | Lista ordenada y sin repetir de los miembros que recibieron algún rol. |
<!-- END_TF_DOCS -->
