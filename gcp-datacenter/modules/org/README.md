# Módulo `org`

Aplica las políticas de organización de la línea base con la API v2
(`google_org_policy_policy`) sobre el proyecto único (`projects/<project_id>`, ADR 0029 §1).
Solo se usa cuando el proyecto está dentro de una organización: `1-base` lo llama con `count`
según `org_id`. Sin organización, lo cubren las reglas de Conftest y los pasos manuales del
runbook 01. La especificación (sección "Componentes del datacenter", organización y gobierno)
pide nueve políticas; en un proyecto que ya existe se aplican estas, sin interruptores para
apagarlas:

| Restricción | Regla |
|---|---|
| `compute.vmExternalIpAccess` | `deny_all`: ninguna VM con IP externa |
| `iam.disableServiceAccountKeyCreation` | forzada |
| `gcp.resourceLocations` | `in:<región>-locations` por cada `allowed_regions`, más `additional_allowed_locations` |
| `compute.requireShieldedVm` | forzada |
| `storage.publicAccessPrevention` | forzada |
| `storage.uniformBucketLevelAccess` | forzada |
| `iam.allowedPolicyMemberDomains` | solo `directory_customer_id`; no se crea si es `null` |
| `sql.restrictPublicIp` | forzada |

Notas de uso:

- `compute.skipDefaultNetworkCreation` ya no se aplica: solo actúa al crear un proyecto y el
  proyecto ya existe. La red `default` se borra a mano antes de `0-bootstrap` (ADR 0029 §6).
- Crear políticas con padre de proyecto pide `roles/orgpolicy.policyAdmin`, que solo se puede
  dar en la organización. `0-bootstrap` se lo da a la cuenta de `1-base` cuando llega `org_id`.
- Las excepciones puntuales se declaran en la etapa con su propio `google_org_policy_policy`;
  no se modelan aquí para que la línea base no se pueda debilitar por variable.
- `gcp.resourceLocations` no limita los recursos globales. Para llaveros de KMS o buckets en la
  multirregión `us` hay que agregar `us` en `additional_allowed_locations`.
- El sink de auditoría ya no está aquí: es un sink de proyecto del módulo `log-export`.

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
| [google_org_policy_policy.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/org_policy_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allowed_regions"></a> [allowed\_regions](#input\_allowed\_regions) | Regiones permitidas por gcp.resourceLocations (por ejemplo, ["us-central1", "us-east4"]). Cada una se traduce al grupo de valores in:<región>-locations, que incluye sus zonas. | `list(string)` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto único donde se aplican las políticas (padre projects/<id>, ADR 0029 §1). | `string` | n/a | yes |
| <a name="input_additional_allowed_locations"></a> [additional\_allowed\_locations](#input\_additional\_allowed\_locations) | Valores extra para gcp.resourceLocations, tal cual: ubicaciones (por ejemplo, us para la multirregión de KMS o buckets) o grupos in:<grupo>-locations. Por defecto, ninguno. | `list(string)` | `[]` | no |
| <a name="input_directory_customer_id"></a> [directory\_customer\_id](#input\_directory\_customer\_id) | ID de cliente de Cloud Identity / Google Workspace (Cxxxxxxxx) cuyo dominio es el único admitido en las políticas de IAM (iam.allowedPolicyMemberDomains). null (por defecto): esa política no se crea. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_policy_names"></a> [policy\_names](#output\_policy\_names) | Mapa restricción → nombre completo de la política (projects/<id>/policies/<restricción>): siete políticas, u ocho con directory\_customer\_id. |
| <a name="output_policy_parent"></a> [policy\_parent](#output\_policy\_parent) | Recurso donde se aplicaron las políticas (projects/<id>). |
<!-- END_TF_DOCS -->
