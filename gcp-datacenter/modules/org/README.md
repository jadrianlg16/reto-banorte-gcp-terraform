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
<!-- END_TF_DOCS -->
