# Etapa `1-base`

Lo que existe **una sola vez** en el proyecto único y no es de la etapa 0 (ADR 0029 §4 y §7).
Reemplaza a las etapas `1-org` y `2-security` del diseño de varios proyectos. La aplica el
pipeline con la cuenta `<prefix>-tf-base` (entorno de GitHub `common`); lee el estado de
`0-bootstrap` y escribe el suyo bajo el prefijo `1-base`.

## Qué crea

| Archivo | Recursos |
|---|---|
| `main.tf` | Configuración de auditoría del proyecto (`ADMIN_READ` para todos los servicios; `DATA_READ` y `DATA_WRITE` para KMS, IAM, Secret Manager, Cloud SQL y Cloud Storage); llaves comunes `logs` y `pubsub`; bucket de logs con CMEK y sink de proyecto (módulo `log-export`, con una exclusión para los registros del propio bucket); alertas de auditoría CIS 2.5 a 2.12 (módulo `audit-alerts`); contactos esenciales del proyecto; tema de Pub/Sub y notificación de hallazgos de SCC (opcional) |
| `kms.tf` | Un llavero por entorno y ubicación (`primary_region`, `dr_region` y la multirregión `us`) con las llaves de cada uso y sus agentes de servicio; contenedores de secretos por entorno con réplica en las dos regiones |
| `artifacts.tf` | Un repositorio Docker `<prefix>-<env>-<app>` por entorno y aplicación, cifrado con la llave `artifacts` de su entorno; su IAM; la política única de Binary Authorization |
| `iam.tf` | Roles de solo lectura de los grupos de personas y `resourcemanager.tagUser` para los agentes de GKE y de las APIs de Google |
| `org.tf` | Solo con organización: las políticas de organización aplicadas al proyecto (módulo `org`) y el perímetro de VPC-SC en dry-run (módulo `vpc-sc`) |
| `remote_state.tf` | Lectura del estado de `0-bootstrap` |

Ninguna raíz de entorno declara roles de proyecto para principales compartidos (agentes,
grupos): todos están aquí. La cuenta de esta etapa solo puede asignar los roles de
`local.base_grantable_roles` de `stages/0-bootstrap/service_accounts.tf`; un rol nuevo en
`iam.tf` exige agregarlo allí y volver a aplicar 0-bootstrap.

## Llaves por entorno

Llaveros `<prefix>-<env>-sec-keyring-<código de ubicación>`; cada llave cifra con un solo uso:

| Uso | Agentes con `cryptoKeyEncrypterDecrypter` | Ubicaciones |
|---|---|---|
| `gke` | GKE (secretos de Kubernetes) y Compute (discos de los nodos) | regiones |
| `compute`, `sql`, `filestore`, `redis`, `run`, `secrets` | el agente de ese servicio | regiones |
| `storage` | Cloud Storage | regiones y `us` |
| `backup` | Backup for GKE | regiones y `us` |
| `artifacts` | Artifact Registry | regiones y `us` |

Los agentes de servicio son uno por proyecto, así que cada uno puede cifrar con las llaves de los
tres entornos (riesgo aceptado, ADR 0029 §9). La separación está en quién administra: la cuenta
de cargas de un entorno solo puede dar IAM sobre los llaveros y secretos `<prefix>-<env>-`
(condición de 0-bootstrap). El llavero del estado (`<prefix>-bootstrap-`) queda fuera del
`cloudkms.admin` de esta etapa.

## Imágenes y Binary Authorization

- Repositorios en `artifact_registry_location` (`us` por defecto), con etiquetas inmutables.
- `artifactregistry.writer` solo para quien diga `artifact_registry_publishers`, por repositorio.
- El agente de Cloud Run lee todos los repositorios (uno por proyecto); los nodos de GKE y las
  VM reciben la lectura de su repositorio desde `3-workloads`.
- La cuenta de cargas de cada entorno recibe aquí `TfRepositoryIamGranter` (rol de 0-bootstrap)
  sobre los repositorios de su entorno, para dar esa lectura.
- La política de Binary Authorization admite los repositorios del proyecto y
  `binary_authorization_allowlist_patterns`, y niega lo demás (`ALWAYS_DENY`) o exige
  atestaciones si hay `binary_authorization_attestors`.

**Desviación del ADR 0029 §4.** La lista de permitidos es global y una imagen que coincide con
ella se admite sin importar las reglas (descripción del campo en el proveedor 6.x). Una regla por
clúster no puede, entonces, limitar los clústeres de prod (`<prefix>-prod-<app>-gke` y
`-gke-dr`, por convención de nombres) al repositorio de prod. Esas reglas existen y aplican la
misma evaluación que la regla por defecto. Separar las imágenes de prod exige atestaciones
(propuesta para una fase siguiente).

## Organización (opcional)

Sin `org_id`, `org.tf` no crea nada y los controles de organización los cubren las reglas de
Conftest y los pasos manuales del runbook 01. Con `org_id`:

- el módulo `org` aplica al proyecto siete políticas: ubicación de recursos (`primary_region`,
  `dr_region` y `additional_allowed_locations`), sin IP externa en VM, sin llaves de cuentas de
  servicio, VM blindadas, acceso uniforme y prevención de acceso público en buckets y Cloud SQL
  sin IP pública; más `iam.allowedPolicyMemberDomains` con `directory_customer_id`;
- 0-bootstrap da a la cuenta de esta etapa `roles/orgpolicy.policyAdmin` **en la organización**
  (el rol no se puede dar en un proyecto).

Con `access_policy_id` (requiere `org_id`), el módulo `vpc-sc` crea un perímetro en dry-run
alrededor de todo el proyecto, con las nueve cuentas del pipeline en la regla de entrada. No
separa entornos (ADR 0029 §1).

## Interfaz con las raíces siguientes

| Salida | Forma | La usa |
|---|---|---|
| `kms_key_ids` | entorno → `<uso>` (primaria), `<uso>_dr`, `<uso>_us` → ID | `3-workloads` |
| `secret_ids` | entorno → nombre → ID | `3-workloads` |
| `artifact_registry_repositories` | entorno → aplicación → `<ubicación>-docker.pkg.dev/<proyecto>/<repositorio>` | `3-workloads` |
| `off_hours_role_id` | ID completo del rol personalizado del apagado (lo crea 0-bootstrap) | `3-workloads` (dev y qa) |
| `notification_channel_ids` | `{ security = <canal> }` | `3-workloads` |
| `security_alert_email`, `log_bucket`, `vpc_sc_perimeter_name`, `org_policies_enabled` | valores sueltos | informativas |

## Cómo se ejecuta

La aplica `apply.yml` con la cuenta `<prefix>-tf-base` después de 0-bootstrap. Para un plan
local con la cuenta de lectura:

```bash
cd stages/1-base
cp terraform.tfvars.example terraform.tfvars    # project_id y state_bucket de 0-bootstrap
terraform init -backend-config="bucket=<state_bucket>"
terraform plan
```

`project_id` debe ser el mismo que el de 0-bootstrap (precondición). Security Command Center se
activa a mano en el proyecto antes de poner `enable_scc_notification = true`.

## Pruebas

`tests/1-base.tftest.hcl`: `mock_provider` y `override_data` del estado de 0-bootstrap con la
forma de su tabla de interfaces. Comprueba la configuración de auditoría, el sink de proyecto y
su exclusión, los llaveros y sus agentes, los repositorios, su IAM y la política de Binary
Authorization, los roles de grupos y agentes, los nombres de llave de `kms_key_ids`, las
variantes con organización y perímetro, con SCC y
atestadores, sin prod y con patrones de imagen válidos; y que se rechazan entradas inválidas
(proyecto distinto del de 0-bootstrap, contactos que no cubren las categorías obligatorias, grupo
desconocido, publicador `user:`, política de acceso sin organización, secretos fuera de dev, qa y
prod y un patrón de imagen que admite un registro entero).

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
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_audit_alerts"></a> [audit\_alerts](#module\_audit\_alerts) | ../../modules/audit-alerts | n/a |
| <a name="module_audit_logs"></a> [audit\_logs](#module\_audit\_logs) | ../../modules/log-export | n/a |
| <a name="module_common_kms"></a> [common\_kms](#module\_common\_kms) | ../../modules/kms | n/a |
| <a name="module_iam"></a> [iam](#module\_iam) | ../../modules/iam | n/a |
| <a name="module_kms"></a> [kms](#module\_kms) | ../../modules/kms | n/a |
| <a name="module_org_policies"></a> [org\_policies](#module\_org\_policies) | ../../modules/org | n/a |
| <a name="module_secrets"></a> [secrets](#module\_secrets) | ../../modules/secrets | n/a |
| <a name="module_vpc_sc"></a> [vpc\_sc](#module\_vpc\_sc) | ../../modules/vpc-sc | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [google_artifact_registry_repository.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository) | resource |
| [google_artifact_registry_repository_iam_member.run_agent_reader](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_artifact_registry_repository_iam_member.workloads_iam_granter](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_artifact_registry_repository_iam_member.writer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_binary_authorization_policy.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/binary_authorization_policy) | resource |
| [google_essential_contacts_contact.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/essential_contacts_contact) | resource |
| [google_project_iam_audit_config.all_services](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_audit_config) | resource |
| [google_project_iam_audit_config.data_access](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_audit_config) | resource |
| [google_pubsub_topic.scc_findings](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic) | resource |
| [google_scc_v2_project_notification_config.findings](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/scc_v2_project_notification_config) | resource |
| [terraform_remote_state.bootstrap](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_dr_region"></a> [dr\_region](#input\_dr\_region) | Región de DR (ADR 0002): segundo llavero de cada entorno y segunda réplica de los secretos. | `string` | n/a | yes |
| <a name="input_essential_contacts"></a> [essential\_contacts](#input\_essential\_contacts) | Contactos esenciales del proyecto (CIS 1.17): correo → categorías de notificación. Entre todos deben cubrir LEGAL, SECURITY, SUSPENSION y TECHNICAL (detector ESSENTIAL\_CONTACTS\_NOT\_CONFIGURED). Categorías admitidas: ALL, BILLING, LEGAL, PRODUCT\_UPDATES, SECURITY, SUSPENSION, TECHNICAL y TECHNICAL\_INCIDENTS. | `map(list(string))` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes (§4.3). Deben traer app, owner y cost\_center; la raíz agrega env (common o el entorno de cada recurso) y managed\_by = terraform. | `map(string)` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa en todos los nombres (§4.2), por ejemplo bnt. El mismo que en 0-bootstrap. | `string` | n/a | yes |
| <a name="input_primary_region"></a> [primary\_region](#input\_primary\_region) | Región primaria (ADR 0002): llaveros de entorno, llavero común, bucket de logs y tema de SCC. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto único (ADR 0029 §1). Llega por tfvars como en las demás raíces; una precondición exige que sea el mismo que publica 0-bootstrap. | `string` | n/a | yes |
| <a name="input_security_alert_email"></a> [security\_alert\_email](#input\_security\_alert\_email) | Correo que recibe las alertas de auditoría (CIS 2.5 a 2.12, módulo audit-alerts). Puede ser un grupo o una persona: es un canal de notificación, no un permiso de IAM. | `string` | n/a | yes |
| <a name="input_state_bucket"></a> [state\_bucket](#input\_state\_bucket) | Bucket de estado (salida state\_bucket de 0-bootstrap); se usa para leer el estado de 0-bootstrap. | `string` | n/a | yes |
| <a name="input_access_policy_id"></a> [access\_policy\_id](#input\_access\_policy\_id) | ID numérico de la política de Access Context Manager de la organización. Con él se crea el perímetro de VPC-SC en dry-run alrededor de todo el proyecto (ADR 0029 §1). null (por defecto): sin perímetro. Exige org\_id. | `string` | `null` | no |
| <a name="input_additional_allowed_locations"></a> [additional\_allowed\_locations](#input\_additional\_allowed\_locations) | Solo con org\_id: ubicaciones extra permitidas por gcp.resourceLocations además de primary\_region y dr\_region. Por defecto us: la multirregión del estado, de los llaveros y de los repositorios. | `list(string)` | <pre>[<br/>  "us"<br/>]</pre> | no |
| <a name="input_applications"></a> [applications](#input\_applications) | Aplicaciones con repositorio de imágenes en cada entorno (<prefix>-<env>-<app>) y regla de Binary Authorization en sus clústeres de prod (<prefix>-prod-<app>-gke[-dr]). Como en 3-workloads: hasta 8 caracteres. | `set(string)` | <pre>[<br/>  "app"<br/>]</pre> | no |
| <a name="input_artifact_registry_location"></a> [artifact\_registry\_location](#input\_artifact\_registry\_location) | Ubicación de los repositorios de Artifact Registry: la multirregión us (por defecto; sobrevive a la pérdida de una región) o primary\_region o dr\_region. Se cifran con la llave artifacts de esa ubicación. | `string` | `"us"` | no |
| <a name="input_artifact_registry_publishers"></a> [artifact\_registry\_publishers](#input\_artifact\_registry\_publishers) | Mapa entorno → aplicación → miembros que publican imágenes (roles/artifactregistry.writer solo sobre ese repositorio), por ejemplo la cuenta del CI de la aplicación. Sin user:. | `map(map(list(string)))` | `{}` | no |
| <a name="input_binary_authorization_allowlist_patterns"></a> [binary\_authorization\_allowlist\_patterns](#input\_binary\_authorization\_allowlist\_patterns) | Patrones de imágenes que Binary Authorization admite además de los repositorios del proyecto (por ejemplo, imágenes base de un registro aprobado), con la forma <registro>/<ruta>[/*\|/**\|*]: comodines solo al final, * al final del nombre o después de una /, ** solo después de una /. Globales: valen para todos los clústeres y Cloud Run. | `list(string)` | `[]` | no |
| <a name="input_binary_authorization_attestors"></a> [binary\_authorization\_attestors](#input\_binary\_authorization\_attestors) | Atestadores (projects/<p>/attestors/<a>) que exigen la regla por defecto y las reglas de los clústeres de prod. Vacío (por defecto): sin atestaciones, se niega todo lo que no esté en la lista de permitidos. | `list(string)` | `[]` | no |
| <a name="input_directory_customer_id"></a> [directory\_customer\_id](#input\_directory\_customer\_id) | Solo con org\_id: ID de cliente de Cloud Identity (Cxxxxxxxx), único dominio admitido en las políticas de IAM (iam.allowedPolicyMemberDomains). null: esa política no se crea. | `string` | `null` | no |
| <a name="input_enable_scc_notification"></a> [enable\_scc\_notification](#input\_enable\_scc\_notification) | Si es true, crea el tema de Pub/Sub con CMEK y la notificación de hallazgos de Security Command Center del proyecto. SCC se activa a mano en el proyecto antes (ADR 0029 §7); por eso es false por defecto. | `bool` | `false` | no |
| <a name="input_environments"></a> [environments](#input\_environments) | Entornos con llaveros, llaves, contenedores de secretos y repositorios de imágenes. | `list(string)` | <pre>[<br/>  "dev",<br/>  "qa",<br/>  "prod"<br/>]</pre> | no |
| <a name="input_essential_contacts_language"></a> [essential\_contacts\_language](#input\_essential\_contacts\_language) | Idioma de las notificaciones de Essential Contacts (etiqueta BCP-47, por ejemplo es o en). | `string` | `"es"` | no |
| <a name="input_groups"></a> [groups](#input\_groups) | Grupos de personas con roles de solo lectura en el proyecto (ADR 0029 §4). Llaves opcionales: readers (viewer, logging.viewer, monitoring.viewer), security\_admins (viewer, iam.securityReviewer, logging.viewer, cloudkms.viewer) y auditors (viewer, iam.securityReviewer, logging.privateLogViewer y lectura del bucket de logs). Valor: correo del grupo, sin group:. Solo grupos: las políticas de Conftest rechazan user:. | `map(string)` | `{}` | no |
| <a name="input_key_rotation_period"></a> [key\_rotation\_period](#input\_key\_rotation\_period) | Periodo de rotación de todas las llaves, en segundos con sufijo s. Por defecto 7776000s (90 días); máximo 90 días. | `string` | `"7776000s"` | no |
| <a name="input_location_short_codes"></a> [location\_short\_codes](#input\_location\_short\_codes) | Mapa ubicación → código corto de los nombres de llaveros (§4.2). Debe incluir primary\_region, dr\_region y us. | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us": "us",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Días de retención de cada objeto del bucket de logs de auditoría. | `number` | `365` | no |
| <a name="input_log_retention_locked"></a> [log\_retention\_locked](#input\_log\_retention\_locked) | Si es true, bloquea la retención del bucket de logs. IRREVERSIBLE una vez aplicado: la retención ya no se puede acortar ni quitar y el bucket no se puede borrar hasta que venza el último objeto. | `bool` | `false` | no |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Sufijo opcional del nombre del bucket de logs para que sea único a nivel mundial. Vacío: sin sufijo. | `string` | `""` | no |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | ID numérico de la organización, si el proyecto está dentro de una (ADR 0029 §1). Con él se aplican las políticas de organización al proyecto. null (por defecto): sin políticas de organización. | `string` | `null` | no |
| <a name="input_scc_notification_filter"></a> [scc\_notification\_filter](#input\_scc\_notification\_filter) | Filtro de los hallazgos de Security Command Center que se publican en el tema de Pub/Sub. Por defecto, los activos y sin silenciar de severidad alta o crítica. | `string` | `"state = \"ACTIVE\" AND mute != \"MUTED\" AND (severity = \"HIGH\" OR severity = \"CRITICAL\")"` | no |
| <a name="input_secret_names"></a> [secret\_names](#input\_secret\_names) | Mapa entorno → nombres cortos de los contenedores de secretos (sin valores, ADR 0015). El ID queda <prefix>-<entorno>-sec-<nombre>. Un entorno sin entrada no tiene secretos. | `map(list(string))` | `{}` | no |
| <a name="input_vpc_sc_restricted_services"></a> [vpc\_sc\_restricted\_services](#input\_vpc\_sc\_restricted\_services) | Servicios restringidos por el perímetro opcional; debe incluir storage.googleapis.com. Con un solo proyecto, el perímetro ya incluye llaves y secretos: KMS y Secret Manager se restringen también. | `list(string)` | <pre>[<br/>  "artifactregistry.googleapis.com",<br/>  "backupdr.googleapis.com",<br/>  "bigquery.googleapis.com",<br/>  "cloudkms.googleapis.com",<br/>  "compute.googleapis.com",<br/>  "container.googleapis.com",<br/>  "file.googleapis.com",<br/>  "gkebackup.googleapis.com",<br/>  "pubsub.googleapis.com",<br/>  "redis.googleapis.com",<br/>  "run.googleapis.com",<br/>  "secretmanager.googleapis.com",<br/>  "sqladmin.googleapis.com",<br/>  "storage.googleapis.com"<br/>]</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_artifact_registry_repositories"></a> [artifact\_registry\_repositories](#output\_artifact\_registry\_repositories) | Mapa entorno → aplicación → URL del repositorio Docker (<ubicación>-docker.pkg.dev/<proyecto>/<repositorio>), como la salida de la etapa 4 anterior. Binary Authorization admite estos repositorios y binary\_authorization\_allowlist\_patterns. |
| <a name="output_kms_key_ids"></a> [kms\_key\_ids](#output\_kms\_key\_ids) | Mapa entorno → llave → ID de la llave KMS. Llave: <uso> en primary\_region, <uso>\_dr en dr\_region y <uso>\_us en la multirregión us (formato de la etapa 2 anterior; el uso es la primera palabra y la ubicación sale del ID). Usos: gke, compute, sql, storage, filestore, redis, secrets, backup, run y artifacts (en us solo storage, backup y artifacts). |
| <a name="output_log_bucket"></a> [log\_bucket](#output\_log\_bucket) | Nombre del bucket de logs de auditoría (destino del sink de proyecto). |
| <a name="output_notification_channel_ids"></a> [notification\_channel\_ids](#output\_notification\_channel\_ids) | Mapa uso → ID del canal de notificación de Monitoring. security: canal de correo de security\_alert\_email (alertas de auditoría). |
| <a name="output_off_hours_role_id"></a> [off\_hours\_role\_id](#output\_off\_hours\_role\_id) | ID completo (projects/<id>/roles/<prefix>OffHoursScheduler) del rol personalizado del apagado fuera de horario (ADR 0028). Lo crea 0-bootstrap; 1-base lo publica. |
| <a name="output_org_policies_enabled"></a> [org\_policies\_enabled](#output\_org\_policies\_enabled) | true si el proyecto está en una organización (org\_id) y se aplicaron las políticas de organización. |
| <a name="output_secret_ids"></a> [secret\_ids](#output\_secret\_ids) | Mapa entorno → nombre corto → ID del secreto (projects/<proyecto>/secrets/<id>). Un entorno sin secretos tiene un mapa vacío. |
| <a name="output_security_alert_email"></a> [security\_alert\_email](#output\_security\_alert\_email) | Correo que recibe las alertas de auditoría del proyecto (CIS 2.5 a 2.12). |
| <a name="output_vpc_sc_perimeter_name"></a> [vpc\_sc\_perimeter\_name](#output\_vpc\_sc\_perimeter\_name) | Nombre completo del perímetro de VPC-SC (accessPolicies/<política>/servicePerimeters/<nombre>), o null sin access\_policy\_id. |
<!-- END_TF_DOCS -->
