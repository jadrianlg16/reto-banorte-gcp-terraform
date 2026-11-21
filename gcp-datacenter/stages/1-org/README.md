# Etapa `1-org`

Estructura y gobierno de la organización (§7.1 del contrato). Corre con la cuenta
`<prefix>-tf-1-org` y lee solo el estado de `0-bootstrap` (§6.1).

## Qué crea

| Recurso | Nombre (prefix `bnt`) | Módulo / recurso |
|---|---|---|
| Carpetas | `common`, `dev`, `qa`, `prod` | `folders` |
| Proyectos de common | `bnt-common-net-hub`, `bnt-common-logging`, `bnt-common-security`, `bnt-common-backup` (más `-<project_suffix>`) | `project-factory` |
| Llavero y llaves del proyecto logging | `bnt-common-sec-keyring-usc1`: `bnt-common-sec-logs` (CMEK del bucket de logs, ADR 0018) y `bnt-common-sec-pubsub` (CMEK del tema de SCC) | `kms` |
| Bucket de logs de auditoría | `bnt-common-ops-audit-logs[-<sufijo>]`, retención `log_retention_days`, bloqueo por `log_retention_locked` (**irreversible**) | `log-export` con `parent = null` |
| Nueve políticas de organización y el sink agregado | `bnt-common-ops-audit-sink`, de toda la organización hacia el bucket de logs | `org` |
| Registros de Data Access | carpeta `prod`, `allServices`: ADMIN_READ, DATA_READ, DATA_WRITE | `google_folder_iam_audit_config` |
| Security Command Center | notificación `bnt-common-ops-scc-findings` (v2, `global`) hacia el tema de Pub/Sub `bnt-common-ops-scc-findings` (CMEK regional; mensajes solo en `primary_region`, con imposición en tránsito) | `google_scc_v2_organization_notification_config`, `google_pubsub_topic` |
| Presupuesto | `bnt-common-ops-budget` sobre toda la organización, alertas a `budget_alert_thresholds` del gasto real y al 100 % del pronosticado | `google_billing_budget` |
| IAM por grupos y permisos de las cuentas de etapa | ver abajo | `iam` |

Un solo sink: `log-export` recibe `parent = null` (solo crea el bucket, su CMEK y el permiso
del agente de Cloud Storage) y el módulo `org` crea el sink con
`log_sink_destination = module.audit_logs.destination` y da a su identidad
`roles/storage.objectCreator` sobre el bucket.

`gcp.resourceLocations` admite `primary_region` y `dr_region` (grupos `in:<región>-locations`)
más `additional_allowed_locations` (por defecto `us`, la multirregión de los llaveros de la
etapa 2 y de los buckets de doble región).

Los IDs de carpeta conservan el prefijo literal `folders/` (salida `ids` del módulo
`folders`), así quien los consume sabe el tipo de padre en el plan.

### Security Command Center

El proveedor 6.x no tiene un recurso para **activar** Security Command Center en la
organización (nivel Standard o Premium): solo recursos de configuración (notificaciones,
silenciamiento, exportaciones, módulos personalizados). La activación queda como paso manual
del runbook de la etapa 0 (`VERIFICAR-EN-APPLY`, pendiente 2). Esta etapa configura la
notificación continua de hallazgos activos de severidad alta o crítica
(`scc_notification_filter`) a un tema de Pub/Sub en el proyecto `logging`, cifrado con su
propia llave; el agente de Pub/Sub del proyecto se crea con `google_project_service_identity`
y recibe `cryptoKeyEncrypterDecrypter` sobre esa llave antes de crear el tema.

La llave del tema es regional (`primary_region`). La guía de CMEK de Pub/Sub admite una llave
regional solo si el almacenamiento de mensajes se limita a la región de la llave con
imposición en tránsito: por eso `message_storage_policy` permite solo `primary_region` con
`enforce_in_transit = true`. Riesgo aceptado: si cae `primary_region`, los avisos de SCC no se
entregan hasta que vuelva (es un canal de avisos, no un dato de negocio; los hallazgos siguen
en SCC).

## IAM por grupos (solo lectura)

Las personas solo reciben roles de lectura y siempre a través de grupos (`groups`); el módulo
`iam` rechaza `user:`. Los cambios los hace el pipeline.

| Grupo | Ámbito | Roles |
|---|---|---|
| `org_admins` | organización | `browser`, `iam.securityReviewer`, `orgpolicy.policyViewer`, `resourcemanager.organizationViewer` |
| `billing_admins` | organización | `billing.viewer`, `resourcemanager.organizationViewer` |
| `security_admins` | organización | `accesscontextmanager.policyReader`, `cloudkms.viewer`, `iam.securityReviewer`, `logging.viewer`, `orgpolicy.policyViewer`, `securitycenter.adminViewer` |
| `network_admins` | organización | `browser`, `compute.networkViewer`, `dns.reader` |
| `auditors` | organización | `browser`, `iam.securityReviewer`, `logging.privateLogViewer` (incluye Data Access), `orgpolicy.policyViewer`, `securitycenter.findingsViewer` |
| `auditors` | bucket de logs | `storage.objectViewer` |
| `platform_devops` | carpetas `common`, `dev`, `qa`, `prod` | `browser`, `logging.viewer`, `monitoring.viewer` |
| `developers` | carpetas `dev` y `qa` (nunca `common` ni `prod`) | `browser`, `logging.viewer`, `monitoring.viewer` |

## Permisos que esta etapa da a las cuentas de etapa

La etapa 0 dio los roles de organización y facturación; los de carpetas y proyectos que crea
esta etapa se asignan aquí (las cuentas se leen de `stage_service_accounts` de 0-bootstrap).

| Cuenta | Ámbito | Rol | Motivo |
|---|---|---|---|
| `2-security` | proyecto `security` | `roles/cloudkms.admin` | llaveros y llaves, y su IAM |
| `2-security` | proyecto `security` | `organizations/<n>/roles/<prefix>TfSecretContainerAdmin` (rol personalizado de la etapa 0, salida `secret_container_admin_role_id`) | contenedores de secretos, sin `secretmanager.versions.access` ni `secrets.setIamPolicy`: el pipeline no lee valores de secretos (ADR 0015) |
| `2-security` | proyecto `security` | `roles/serviceusage.serviceUsageAdmin` | crear el agente de Secret Manager (`google_project_service_identity`) |
| `3-networks` | proyecto `net-hub` | `roles/compute.networkAdmin` | VPC hub, routers, HA VPN, peering |
| `3-networks` | proyecto `net-hub` | `roles/compute.securityAdmin` | reglas y políticas de firewall de red |
| `3-networks` | proyecto `net-hub` | `roles/dns.admin` | zonas de reenvío, política de servidor y peering de DNS desde los spokes |
| `3-networks` | proyecto `net-hub` | `roles/serviceusage.serviceUsageAdmin` | habilitar APIs de red que falten |
| `3-networks` | carpetas `dev`, `qa`, `prod` | `roles/resourcemanager.projectCreator` | crear `net-spoke` (queda como dueña) |
| `3-networks` | carpetas `dev`, `qa`, `prod` | `roles/compute.xpnAdmin` | habilitar `net-spoke` como host de Shared VPC |
| `4-projects` | proyecto `security` | `organizations/<n>/roles/<prefix>TfKmsSecretIamGranter` (rol personalizado de la etapa 0, salida `kms_secret_iam_role_id`) | dar a los agentes de servicio permiso sobre las llaves y `secretAccessor` a las cuentas de ejecución (§7.5), sin usar, administrar ni destruir llaves ni leer valores |
| `4-projects` | carpetas `dev`, `qa`, `prod` | `roles/resourcemanager.projectCreator` | proyectos de servicio |
| `4-projects` | carpetas `dev`, `qa`, `prod` | `roles/compute.xpnAdmin` | alta como servicio de Shared VPC y permisos de uso de subred |
| `4-projects` | carpetas `dev`, `qa`, `prod` | `roles/resourcemanager.tagAdmin` | dar `tagUser` sobre los valores de las etiquetas seguras del spoke (sus llaves viven en `net-spoke`, que crea 3-networks) |
| `4-projects` | carpetas `dev`, `qa`, `prod` | `roles/resourcemanager.projectIamAdmin` **con condición**: solo puede asignar `roles/compute.networkUser`, `roles/compute.networkViewer` y `roles/container.hostServiceAgentUser` | dar esos roles sobre el host del spoke (proyecto `net-spoke` de 3-networks) a las identidades de los proyectos de servicio: uso de la Shared VPC, lectura de la red (Cloud Run con salida directa a la VPC) y agente de GKE |

`5-workloads` no recibe ningún rol en esta etapa. Las carpetas de entorno también contienen el
host `net-spoke` de 3-networks, así que un rol de carpeta le daría poder sobre la red (por
ejemplo, reglas de firewall con `compute.securityAdmin`) y `iam.serviceAccountUser` sobre
cualquier cuenta del entorno. Sus roles van sobre cada proyecto de servicio y los da
`4-projects`, que crea esos proyectos y recibe la cuenta de 5-workloads como variable.

La asignación de `projectIamAdmin` de 4-projects usa una concesión delegada:
`api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([...])`, así la cuenta
solo puede agregar o quitar esos roles en los proyectos de la carpeta (`VERIFICAR-EN-APPLY`).
La condición limita los roles, no a quién se asignan: es un límite de Google.

Proyecto `security`: ninguna cuenta de etapa tiene `projectIamAdmin` ahí. El único rol de
proyecto que hacía falta asignar en él (el de 4-projects) lo asigna esta etapa, que es dueña
del proyecto; así `2-security` no puede darse a sí misma ese rol ni `secretAccessor`.

Residual conocido sobre secretos: `4-projects` tiene `secretmanager.secrets.setIamPolicy` (lo
necesita para dar `secretAccessor` a las cuentas de ejecución) y podría darse `secretAccessor`
a sí misma. No se puede limitar con una concesión delegada: Google solo la admite en
proyectos, carpetas y organizaciones, no en un secreto. El cambio queda en los registros de
actividad administrativa del proyecto `security` y del sink de la organización.

## Roles que necesita la cuenta de la etapa

`<prefix>-tf-1-org` (los da la etapa 0): en la organización `resourcemanager.folderAdmin`,
`resourcemanager.projectCreator`, `orgpolicy.policyAdmin`, `logging.configWriter`,
`iam.securityAdmin`, `securitycenter.notificationConfigEditor` y
`resourcemanager.organizationViewer`; en la cuenta de facturación `billing.user` y
`billing.costsManager`; en el proyecto semilla `serviceusage.serviceUsageConsumer`; en el
bucket de estado, escritura de `1-org/` y lectura de `0-bootstrap/`. Es dueña de los proyectos
que crea (logging, KMS, Pub/Sub e IAM de proyecto).

## Cómo se ejecuta

```bash
cd stages/1-org
cp terraform.tfvars.example terraform.tfvars    # valores reales; state_bucket = salida de la etapa 0
terraform init -backend-config="bucket=<state_bucket>"
terraform plan
terraform apply
```

En el pipeline, con WIF y la cuenta `<prefix>-tf-1-org`. Los proveedores usan el proyecto
semilla como proyecto de cuota (`billing_project`, leído del estado de la etapa 0).

`log_retention_locked = true` es irreversible: aplicarlo solo después de confirmar la
retención con el área de cumplimiento.

## Pendientes del primer apply (VERIFICAR-EN-APPLY)

- Activación de Security Command Center (pendiente 2) y permiso de su cuenta para publicar
  en el tema.
- `gcp.resourceLocations` frente a la multirregión `us` y los recursos globales (pendiente 3,
  en el módulo `org`).
- `iam.allowedPolicyMemberDomains` frente a los `principalSet://` de WIF y a los agentes de
  servicio de Google.
- Proyecto de cuota aceptado por todas las APIs de la etapa.
- Retención bloqueada y CMEK del bucket de logs (en el módulo `log-export`).

## Pruebas

`tests/1-org.tftest.hcl`: `mock_provider`, `override_data` del estado de 0-bootstrap con la
forma de §7.0 y `command = plan` con los valores de `terraform.tfvars.example`. Comprueba las
salidas y nombres de §7.1, las nueve políticas, el sink único, las llaves de logging, Data
Access en prod, SCC, el presupuesto, que los grupos solo tienen lectura, que `developers` solo
está en dev y qa y los permisos de las cuentas de etapa (5-workloads sin ningún rol,
projectIamAdmin de 4-projects con su condición exacta, 2-security sin `secretmanager.admin` ni
`projectIamAdmin`, el rol personalizado de 4-projects sobre `security`), el almacenamiento del tema de SCC limitado a la región primaria; y
que `groups` incompleto, una región
de DR igual a la primaria y un `prefix` inválido se rechazan.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |
| <a name="provider_google-beta"></a> [google-beta](#provider\_google-beta) | ~> 6.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_audit_logs"></a> [audit\_logs](#module\_audit\_logs) | ../../modules/log-export | n/a |
| <a name="module_common_project"></a> [common\_project](#module\_common\_project) | ../../modules/project-factory | n/a |
| <a name="module_folders"></a> [folders](#module\_folders) | ../../modules/folders | n/a |
| <a name="module_iam"></a> [iam](#module\_iam) | ../../modules/iam | n/a |
| <a name="module_logging_kms"></a> [logging\_kms](#module\_logging\_kms) | ../../modules/kms | n/a |
| <a name="module_org"></a> [org](#module\_org) | ../../modules/org | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [google-beta_google_project_service_identity.pubsub](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_project_service_identity) | resource |
| [google_billing_budget.org](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/billing_budget) | resource |
| [google_folder_iam_audit_config.prod](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/folder_iam_audit_config) | resource |
| [google_kms_crypto_key_iam_member.pubsub_agent](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_crypto_key_iam_member) | resource |
| [google_pubsub_topic.scc_findings](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic) | resource |
| [google_scc_v2_organization_notification_config.findings](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/scc_v2_organization_notification_config) | resource |
| [terraform_remote_state.bootstrap](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | Cuenta de facturación de los proyectos de common y del presupuesto (formato XXXXXX-XXXXXX-XXXXXX). | `string` | n/a | yes |
| <a name="input_budget_amount"></a> [budget\_amount](#input\_budget\_amount) | Monto mensual del presupuesto de la organización, en la moneda de la cuenta de facturación (unidades enteras). | `number` | n/a | yes |
| <a name="input_directory_customer_id"></a> [directory\_customer\_id](#input\_directory\_customer\_id) | ID de cliente de Cloud Identity / Google Workspace (Cxxxxxxxx): único dominio admitido en las políticas de IAM (iam.allowedPolicyMemberDomains). | `string` | n/a | yes |
| <a name="input_dr_region"></a> [dr\_region](#input\_dr\_region) | Región de DR (ADR 0002). Junto con la primaria forma la lista de regiones permitidas por gcp.resourceLocations. | `string` | n/a | yes |
| <a name="input_groups"></a> [groups](#input\_groups) | Mapa rol → correo del grupo de Cloud Identity. Llaves exactas: org\_admins, billing\_admins, security\_admins, network\_admins, platform\_devops, developers, auditors. Las personas solo reciben roles de lectura (§7.1). | `map(string)` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes (§4.3). Deben traer app, owner y cost\_center; la raíz agrega env = common y managed\_by = terraform. | `map(string)` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | ID numérico de la organización de GCP (sin el prefijo organizations/). | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa en todos los nombres (§4.2), por ejemplo bnt. El mismo que en la etapa 0. | `string` | n/a | yes |
| <a name="input_primary_region"></a> [primary\_region](#input\_primary\_region) | Región primaria (ADR 0002). Aquí viven el bucket de logs, su llave y el tema de hallazgos de SCC. | `string` | n/a | yes |
| <a name="input_state_bucket"></a> [state\_bucket](#input\_state\_bucket) | Bucket de estado (salida state\_bucket de la etapa 0); se usa para leer el estado de 0-bootstrap. | `string` | n/a | yes |
| <a name="input_additional_allowed_locations"></a> [additional\_allowed\_locations](#input\_additional\_allowed\_locations) | Ubicaciones extra permitidas por gcp.resourceLocations, además de las dos regiones. Por defecto us: la multirregión de los llaveros de la etapa 2 y de los buckets de doble región. | `list(string)` | <pre>[<br/>  "us"<br/>]</pre> | no |
| <a name="input_budget_alert_thresholds"></a> [budget\_alert\_thresholds](#input\_budget\_alert\_thresholds) | Umbrales de alerta del presupuesto sobre el gasto real, como fracción del monto (0.5 = 50 %). Además se alerta al 100 % del gasto pronosticado. | `list(number)` | <pre>[<br/>  0.5,<br/>  0.75,<br/>  0.9,<br/>  1<br/>]</pre> | no |
| <a name="input_location_short_codes"></a> [location\_short\_codes](#input\_location\_short\_codes) | Mapa ubicación → código corto que se agrega a los nombres de recursos con región (§4.2). Debe incluir primary\_region. | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us": "us",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Días de retención de cada objeto del bucket de logs de auditoría. | `number` | `365` | no |
| <a name="input_log_retention_locked"></a> [log\_retention\_locked](#input\_log\_retention\_locked) | Si es true, bloquea la retención del bucket de logs. IRREVERSIBLE una vez aplicado: la retención ya no se puede acortar ni quitar y el bucket no se puede borrar hasta que venza el último objeto. | `bool` | `false` | no |
| <a name="input_project_suffix"></a> [project\_suffix](#input\_project\_suffix) | Sufijo opcional de los IDs de proyecto y del bucket de logs, para que sean únicos a nivel mundial. Vacío: sin sufijo. | `string` | `""` | no |
| <a name="input_scc_notification_filter"></a> [scc\_notification\_filter](#input\_scc\_notification\_filter) | Filtro de los hallazgos de Security Command Center que se publican en el tema de Pub/Sub. Por defecto, los activos y sin silenciar de severidad alta o crítica. | `string` | `"state = \"ACTIVE\" AND mute != \"MUTED\" AND (severity = \"HIGH\" OR severity = \"CRITICAL\")"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_budget_name"></a> [budget\_name](#output\_budget\_name) | Nombre completo del presupuesto de la organización. |
| <a name="output_common_project_ids"></a> [common\_project\_ids](#output\_common\_project\_ids) | Mapa net\_hub, logging, security, backup → ID del proyecto de common. |
| <a name="output_common_project_numbers"></a> [common\_project\_numbers](#output\_common\_project\_numbers) | Mapa net\_hub, logging, security, backup → número del proyecto de common. |
| <a name="output_folder_ids"></a> [folder\_ids](#output\_folder\_ids) | Mapa carpeta (common, dev, qa, prod) → ID completo "folders/<número>". |
| <a name="output_log_bucket"></a> [log\_bucket](#output\_log\_bucket) | Nombre del bucket de logs de auditoría (destino del sink agregado). |
| <a name="output_log_sink_writer_identity"></a> [log\_sink\_writer\_identity](#output\_log\_sink\_writer\_identity) | Identidad que escribe el sink agregado de la organización. |
| <a name="output_logging_kms_key_ids"></a> [logging\_kms\_key\_ids](#output\_logging\_kms\_key\_ids) | Mapa uso (logs, pubsub) → ID de las llaves KMS del proyecto logging (ADR 0018). |
| <a name="output_org_policy_names"></a> [org\_policy\_names](#output\_org\_policy\_names) | Mapa restricción → nombre completo de las nueve políticas de organización. |
| <a name="output_scc_findings_topic"></a> [scc\_findings\_topic](#output\_scc\_findings\_topic) | ID del tema de Pub/Sub que recibe los hallazgos de Security Command Center. |
<!-- END_TF_DOCS -->
