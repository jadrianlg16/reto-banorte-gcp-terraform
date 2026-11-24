# Etapa `1-base`

Lo que existe **una sola vez** en el proyecto único y no es de la etapa 0 (ADR 0029 §4 y §7).
Reemplaza a las etapas `1-org` y `2-security` del diseño de varios proyectos. La aplica el
pipeline con la cuenta `<prefix>-tf-base` (entorno de GitHub `common`); lee el estado de
`0-bootstrap` y escribe el suyo bajo el prefijo `1-base`.

## Qué crea

| Archivo | Recursos |
|---|---|
| `main.tf` | Configuración de auditoría del proyecto (`ADMIN_READ` para todos los servicios; `DATA_READ` y `DATA_WRITE` para KMS, IAM, Secret Manager, Cloud SQL y Cloud Storage); llaves comunes `logs` y `pubsub`; bucket de logs con CMEK y sink de proyecto (módulo `log-export`, con una exclusión para los registros del propio bucket); alertas de auditoría CIS 2.5 a 2.12 (módulo `audit-alerts`, canal `security`); canal de operaciones opcional (`operations_alert_email`) para las alertas de los entornos; contactos esenciales del proyecto; tema de Pub/Sub y notificación de hallazgos de SCC (opcional) |
| `kms.tf` | Un llavero por entorno y ubicación con llaves (`primary_region`; `dr_region` y la multirregión `us` según `dr_environments` y `artifact_registry_location`), solo con las llaves que alguien usa, y sus agentes de servicio; contenedores de secretos por entorno con réplica en la región primaria y, en `dr_environments`, en la de DR |
| `artifacts.tf` | Un repositorio Docker `<prefix>-<env>-<app>` por entorno y aplicación, cifrado con la llave `artifacts` de su entorno; su IAM; la política única de Binary Authorization |
| `iam.tf` | Roles de solo lectura de los grupos de personas y los roles de proyecto de las cuentas de ejecución (el `tagUser` de los agentes de GKE y de las APIs de Google lo da 0-bootstrap) |
| `runtime_accounts.tf` | Las cuentas de ejecución de cada entorno y aplicación y sus permisos (tabla de abajo) |
| `onprem_dns.tf` | Solo si `0-bootstrap` tiene `onprem_dns_vm = true`: la cuenta `<prefix>-common-net-dns` de la VM DNS de `onprem-sim` (hub), con `logging.logWriter`, y `iam.serviceAccountUser` sobre ella para `<prefix>-tf-net` |
| `remote_state.tf` | Lectura del estado de `0-bootstrap` (número del proyecto, cuentas de las raíces, roles personalizados y `onprem_dns_vm_enabled`) |

Ninguna raíz de entorno declara roles de proyecto ni crea cuentas de servicio: todos están aquí.
La cuenta de esta etapa solo puede asignar los roles de `local.base_grantable_roles` y
`local.runtime_grantable_roles` de `stages/0-bootstrap/service_accounts.tf`; un rol nuevo en
`iam.tf` o `runtime_accounts.tf` exige agregarlo allí y volver a aplicar 0-bootstrap.

## Cuentas de ejecución (`runtime_accounts.tf`)

Por entorno y aplicación (`applications`), `<prefix>-<env>-<app>-<uso>` (ADR 0017). Antes las
creaba `3-workloads`; ahora la cuenta de cargas de un entorno no administra cuentas ni asigna
roles de proyecto (hallazgos 2 y 4 de la revisión de seguridad del ADR 0029).

| Cuenta | Roles en el proyecto | Permisos sobre recursos del entorno |
|---|---|---|
| `gke-nodes` | `autoscaling.metricsWriter`, `logging.logWriter`, `monitoring.metricWriter`, `monitoring.viewer`, `stackdriver.resourceMetadata.writer` | `artifactregistry.reader` sobre el repositorio del entorno y la aplicación |
| `workload` | `cloudtrace.agent`, `logging.logWriter`, `monitoring.metricWriter`; `cloudsql.client` e `instanceUser` limitados a `<prefix>-<env>-data-*` | `secretmanager.secretAccessor` sobre cada secreto del entorno; `iam.workloadIdentityUser` para todos los pods del clúster `<prefix>-<env>-<app>-gke` (y `-gke-dr` en `dr_environments`), con `gke_workload_identity_bindings` |
| `mig` | `logging.logWriter`, `monitoring.metricWriter`; Cloud SQL como `workload` | `artifactregistry.reader` sobre el repositorio del entorno y la aplicación |
| `run` | `cloudtrace.agent`, `logging.logWriter`, `monitoring.metricWriter`; Cloud SQL como `workload` | `secretmanager.secretAccessor` sobre cada secreto del entorno |
| `sched` (solo `off_hours_environments`) | el rol `<prefix>OffHoursScheduler`, limitado a la instancia `<prefix>-<env>-data-*` y a los clústeres `<prefix>-<env>-*` | — |

La cuenta de cargas del entorno (`<prefix>-tf-wl-<env>`) recibe `iam.serviceAccountUser` sobre
`gke-nodes`, `mig`, `run` y `sched` de su entorno, nunca en el proyecto. El enlace de Workload
Identity necesita el pool `<proyecto>.svc.id.goog`, que GKE crea con el primer clúster del
proyecto: `gke_workload_identity_bindings` queda en `false` hasta el primer apply de
`3-workloads` con `enable_gke` y después se pone en `true`.

El enlace usa el principalSet de Workload Identity Federation for GKE de todos los pods de un
clúster (`…/kubernetes.cluster/https://container.googleapis.com/v1/projects/<proyecto>/locations/<ubicación>/clusters/<clúster>`)
y no `serviceAccount:<proyecto>.svc.id.goog[<ns>/<cuenta>]`, que vale desde cualquier clúster del
proyecto (hallazgo N1 de la segunda revisión de seguridad). La documentación no tiene un
identificador que combine clúster, namespace y cuenta de Kubernetes: cualquier pod del clúster
con una cuenta de Kubernetes anotada con la cuenta `workload` la obtiene. Cada clúster es de un
solo entorno y una sola aplicación.

## Llaves por entorno

Llaveros `<prefix>-<env>-sec-keyring-<código de ubicación>`; cada llave cifra con un solo uso y
solo existen las que usan `3-workloads` (su lista `required_kms`) y esta etapa (hallazgo H9).
`dr_environments` (por defecto `["prod"]`) son los entornos con `enable_dr`:

| Uso | Agentes con `cryptoKeyEncrypterDecrypter` | Ubicaciones |
|---|---|---|
| `gke` | GKE (secretos de Kubernetes) y Compute (discos de los nodos) | primaria; DR en `dr_environments` |
| `compute`, `run`, `sql`, `secrets` | el agente de ese servicio | primaria; DR en `dr_environments` |
| `redis`, `filestore` | el agente de ese servicio | primaria (3-workloads no los crea en DR) |
| `storage` | Cloud Storage | primaria (bucket sin DR); `us` en `dr_environments` (doble región) |
| `backup` | Backup for GKE | DR en `dr_environments` (el plan de respaldo vive en `dr_region`) |
| `artifacts` | Artifact Registry | solo `artifact_registry_location` |

Un entorno de `3-workloads` con `enable_dr` que no esté en `dr_environments` falla en su plan
(precondición de llaves). En los entornos sin DR los secretos tienen una sola réplica.

Los agentes de servicio son uno por proyecto, así que cada uno puede cifrar con las llaves de los
tres entornos (riesgo aceptado, ADR 0029 §9). La separación está en quién administra: el IAM de
llaves y secretos solo lo cambia esta etapa; las cuentas de cargas no tienen permisos de IAM
sobre ellos. El llavero del estado (`<prefix>-bootstrap-`) queda fuera del `cloudkms.admin` de
esta etapa, y una regla de la política de denegación de 0-bootstrap impide que la cuenta de esta
etapa lea valores de secretos aunque pueda cambiar su IAM.

## Imágenes y Binary Authorization

- Repositorios en `artifact_registry_location` (`us` por defecto), con etiquetas inmutables.
- `artifactregistry.writer` solo para quien diga `artifact_registry_publishers`, por repositorio.
- El agente de Cloud Run lee todos los repositorios (uno por proyecto); los nodos de GKE y las
  VM del MIG reciben la lectura de su repositorio en `runtime_accounts.tf`.
- La política de Binary Authorization tiene dos modos, según
  `binary_authorization_env_attestors` (entorno → atestador, uno por entorno de `environments`):

| | Sin atestadores por entorno (por defecto) | Con atestadores por entorno |
|---|---|---|
| Lista de permitidos | repositorios de los tres entornos y `binary_authorization_allowlist_patterns` | solo `binary_authorization_allowlist_patterns` |
| Reglas de clúster | `<prefix>-prod-<app>-gke[-dr]`, con la evaluación de la regla por defecto | `<prefix>-<env>-<app>-gke[-dr]` de cada entorno, con el atestador de su entorno (más `binary_authorization_attestors`) |
| Regla por defecto (Cloud Run y clústeres fuera de la convención) | `ALWAYS_DENY`, o los `binary_authorization_attestors` | `binary_authorization_attestors` o, si está vacío, el atestador del primer entorno de la promoción (dev, qa, prod) |

**Riesgo sin atestadores por entorno (ADR 0024; desviación del ADR 0029 §4).** La lista de
permitidos es global y una imagen que coincide con ella se admite sin mirar las reglas: una
imagen del repositorio de dev se puede desplegar en un clúster de prod. Las reglas de los
clústeres de prod existen por convención de nombres pero no lo impiden.

**Con atestadores por entorno.** Binary Authorization exige las atestaciones de **todos** los
atestadores de una regla, así que "cualquiera de los atestadores" no se puede expresar en la
regla por defecto; por eso exige el del primer entorno, que toda imagen promovida trae. Cloud Run
solo admite la regla por defecto: Cloud Run de qa y prod no exige el atestador de su entorno
(riesgo aceptado). Los atestadores no los crea esta etapa; si están en otro proyecto, el agente de
Binary Authorization de este necesita `roles/binaryauthorization.attestorsVerifier` allí.

## Organización

Esta etapa ya no aplica políticas de organización ni el perímetro de VPC-SC: con `org_id` y
`access_policy_id` los aplica `0-bootstrap` (`org.tf`), con la persona de la etapa 0. La cuenta
de esta etapa no tiene `roles/orgpolicy.policyAdmin` ni roles sobre la política de acceso.

## Interfaz con las raíces siguientes

| Salida | Forma | La usa |
|---|---|---|
| `kms_key_ids` | entorno → `<uso>` (primaria), `<uso>_dr`, `<uso>_us` → ID | `3-workloads` |
| `artifact_registry_repositories` | entorno → aplicación → `<ubicación>-docker.pkg.dev/<proyecto>/<repositorio>` | `3-workloads` |
| `runtime_service_accounts` | entorno → aplicación → uso (`gke_nodes`, `workload`, `mig`, `run`, `scheduler`) → correo | `3-workloads` |
| `gke_workload_identity_members` | entorno → aplicación → clúster (`primary`, `dr`) → principalSet `…/kubernetes.cluster/…/clusters/<prefix>-<env>-<app>-gke[-dr]`, o null | `3-workloads` |
| `notification_channel_ids` | `{ security = <canal>, operations = <canal> }` (`operations` solo con `operations_alert_email`) | `3-workloads` (solo `operations`) |
| `secret_ids` | entorno → nombre → ID | informativa |
| `off_hours_role_id` | ID completo del rol personalizado del apagado (lo crea 0-bootstrap) | informativa |
| `security_alert_email`, `log_bucket` | valores sueltos | informativas |
| `onprem_dns_service_account` | correo de `<prefix>-common-net-dns` o null | informativa (el hub arma el correo con el nombre) |

`vpc_sc_perimeter_name` y `org_policies_enabled` pasaron a ser salidas de `0-bootstrap`.

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
Authorization, los roles de grupos y agentes, las cuentas de ejecución y sus permisos (roles,
condición de Cloud SQL y la del rol del apagado, secretos, repositorio, `serviceAccountUser` de
las cuentas de cargas y el enlace de Workload Identity por clúster con y sin
`gke_workload_identity_bindings`), los llaveros y los
nombres exactos de `kms_key_ids` (solo las llaves usadas; DR según `dr_environments`, también
con qa), que no haya roles de organización, el canal de operaciones, la cuenta de la VM DNS de
`onprem-sim` (sin ella por defecto; con `onprem_dns_vm_enabled`, solo `logWriter` y
`serviceAccountUser` para `tf-net`), las variantes con SCC y atestadores, con
atestadores por entorno (solos y con comunes: lista sin repositorios, atestador de cada entorno
en sus clústeres y regla por defecto), sin prod y con patrones de imagen válidos; y que se
rechazan entradas inválidas (proyecto distinto del de 0-bootstrap, contactos que no cubren las
categorías obligatorias, grupo desconocido, publicador `user:`, secretos fuera de dev, qa y prod,
una aplicación de más de 8 caracteres, el apagado en prod, atestadores por entorno que no cubren
todos los entornos, un entorno de DR fuera de `environments` y un patrón de imagen que admite un
registro entero).

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
| <a name="module_secrets"></a> [secrets](#module\_secrets) | ../../modules/secrets | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [google_artifact_registry_repository.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository) | resource |
| [google_artifact_registry_repository_iam_member.run_agent_reader](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_artifact_registry_repository_iam_member.runtime_reader](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_artifact_registry_repository_iam_member.writer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_binary_authorization_policy.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/binary_authorization_policy) | resource |
| [google_essential_contacts_contact.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/essential_contacts_contact) | resource |
| [google_monitoring_notification_channel.operations](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_notification_channel) | resource |
| [google_project_iam_audit_config.all_services](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_audit_config) | resource |
| [google_project_iam_audit_config.data_access](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_audit_config) | resource |
| [google_pubsub_topic.scc_findings](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic) | resource |
| [google_scc_v2_project_notification_config.findings](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/scc_v2_project_notification_config) | resource |
| [google_secret_manager_secret_iam_member.runtime](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_iam_member) | resource |
| [google_service_account.onprem_dns](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account.runtime](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account_iam_member.onprem_dns_hub_user](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_service_account_iam_member.workload_identity](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_service_account_iam_member.workloads_user](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
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
| <a name="input_applications"></a> [applications](#input\_applications) | Aplicaciones de cada entorno: repositorio de imágenes (<prefix>-<env>-<app>), cuentas de ejecución (<prefix>-<env>-<app>-<uso>) y regla de Binary Authorization en sus clústeres de prod (<prefix>-prod-<app>-gke[-dr]). Misma validación que application de 3-workloads: de 2 a 8 caracteres. | `set(string)` | <pre>[<br/>  "app"<br/>]</pre> | no |
| <a name="input_artifact_registry_location"></a> [artifact\_registry\_location](#input\_artifact\_registry\_location) | Ubicación de los repositorios de Artifact Registry: la multirregión us (por defecto; sobrevive a la pérdida de una región) o primary\_region o dr\_region. Se cifran con la llave artifacts de esa ubicación. | `string` | `"us"` | no |
| <a name="input_artifact_registry_publishers"></a> [artifact\_registry\_publishers](#input\_artifact\_registry\_publishers) | Mapa entorno → aplicación → miembros que publican imágenes (roles/artifactregistry.writer solo sobre ese repositorio), por ejemplo la cuenta del CI de la aplicación. Sin user:. | `map(map(list(string)))` | `{}` | no |
| <a name="input_binary_authorization_allowlist_patterns"></a> [binary\_authorization\_allowlist\_patterns](#input\_binary\_authorization\_allowlist\_patterns) | Patrones de imágenes que Binary Authorization admite además de los repositorios del proyecto (por ejemplo, imágenes base de un registro aprobado), con la forma <registro>/<ruta>[/*\|/**\|*]: comodines solo al final, * al final del nombre o después de una /, ** solo después de una /. Globales: valen para todos los clústeres y Cloud Run. | `list(string)` | `[]` | no |
| <a name="input_binary_authorization_attestors"></a> [binary\_authorization\_attestors](#input\_binary\_authorization\_attestors) | Atestadores (projects/<p>/attestors/<a>) que exigen la regla por defecto y todas las reglas de clúster (todos a la vez: Binary Authorization pide la atestación de cada uno). Vacío (por defecto): sin atestaciones comunes; sin binary\_authorization\_env\_attestors se niega todo lo que no esté en la lista de permitidos. | `list(string)` | `[]` | no |
| <a name="input_binary_authorization_env_attestors"></a> [binary\_authorization\_env\_attestors](#input\_binary\_authorization\_env\_attestors) | Mapa entorno → atestador (projects/<p>/attestors/<a>), uno por entorno de environments. Con él, los repositorios del proyecto salen de la lista de permitidos (queda solo binary\_authorization\_allowlist\_patterns), cada clúster <prefix>-<env>-<app>-gke[-dr] exige el atestador de su entorno y la regla por defecto (Cloud Run y clústeres fuera de la convención) exige binary\_authorization\_attestors o, si está vacío, el atestador del primer entorno de la promoción (dev, qa, prod). Vacío (por defecto): la lista de permitidos global con los repositorios de los tres entornos (una imagen de dev se puede desplegar en prod; riesgo del ADR 0024). Los atestadores no los crea esta etapa. | `map(string)` | `{}` | no |
| <a name="input_dr_environments"></a> [dr\_environments](#input\_dr\_environments) | Entornos con recuperación ante desastres (enable\_dr en su raíz de 3-workloads): solo ellos tienen llaves en dr\_region (<uso>\_dr), la llave storage de la multirregión us y la segunda réplica de sus secretos. Por defecto prod. Un entorno de 3-workloads con enable\_dr que no esté aquí falla en su plan por falta de llaves. | `list(string)` | <pre>[<br/>  "prod"<br/>]</pre> | no |
| <a name="input_enable_scc_notification"></a> [enable\_scc\_notification](#input\_enable\_scc\_notification) | Si es true, crea el tema de Pub/Sub con CMEK y la notificación de hallazgos de Security Command Center del proyecto. SCC se activa a mano en el proyecto antes (ADR 0029 §7); por eso es false por defecto. | `bool` | `false` | no |
| <a name="input_environments"></a> [environments](#input\_environments) | Entornos con llaveros, llaves, contenedores de secretos y repositorios de imágenes. | `list(string)` | <pre>[<br/>  "dev",<br/>  "qa",<br/>  "prod"<br/>]</pre> | no |
| <a name="input_essential_contacts_language"></a> [essential\_contacts\_language](#input\_essential\_contacts\_language) | Idioma de las notificaciones de Essential Contacts (etiqueta BCP-47, por ejemplo es o en). | `string` | `"es"` | no |
| <a name="input_gke_workload_identity_bindings"></a> [gke\_workload\_identity\_bindings](#input\_gke\_workload\_identity\_bindings) | true: crea el enlace de Workload Identity (roles/iam.workloadIdentityUser) en la cuenta workload de cada entorno y aplicación para todos los pods del clúster <prefix>-<env>-<app>-gke (y del de DR, <prefix>-<env>-<app>-gke-dr, en dr\_environments): principalSet kubernetes.cluster/… de Workload Identity Federation for GKE. Exige que ya exista el pool <proyecto>.svc.id.goog, que GKE crea con el primer clúster con Workload Identity del proyecto: false (por defecto) hasta el primer apply de 3-workloads con enable\_gke, y después true. | `bool` | `false` | no |
| <a name="input_groups"></a> [groups](#input\_groups) | Grupos de personas con roles de solo lectura en el proyecto (ADR 0029 §4). Llaves opcionales: readers (viewer, logging.viewer, monitoring.viewer), security\_admins (viewer, iam.securityReviewer, logging.viewer, cloudkms.viewer) y auditors (viewer, iam.securityReviewer, logging.privateLogViewer y lectura del bucket de logs). Valor: correo del grupo, sin group:. Solo grupos: las políticas de Conftest rechazan user:. | `map(string)` | `{}` | no |
| <a name="input_key_rotation_period"></a> [key\_rotation\_period](#input\_key\_rotation\_period) | Periodo de rotación de todas las llaves, en segundos con sufijo s. Por defecto 7776000s (90 días); máximo 90 días. | `string` | `"7776000s"` | no |
| <a name="input_location_short_codes"></a> [location\_short\_codes](#input\_location\_short\_codes) | Mapa ubicación → código corto de los nombres de llaveros (§4.2). Debe incluir primary\_region, dr\_region y us. | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us": "us",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Días de retención de cada objeto del bucket de logs de auditoría. | `number` | `365` | no |
| <a name="input_log_retention_locked"></a> [log\_retention\_locked](#input\_log\_retention\_locked) | Si es true, bloquea la retención del bucket de logs. IRREVERSIBLE una vez aplicado: la retención ya no se puede acortar ni quitar y el bucket no se puede borrar hasta que venza el último objeto. | `bool` | `false` | no |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Sufijo opcional del nombre del bucket de logs para que sea único a nivel mundial. Vacío: sin sufijo. | `string` | `""` | no |
| <a name="input_off_hours_environments"></a> [off\_hours\_environments](#input\_off\_hours\_environments) | Entornos con cuenta de los trabajos del apagado fuera de horario (<prefix>-<env>-<app>-sched, ADR 0028) y su rol. 3-workloads la usa con off\_hours\_shutdown.enabled. Nunca prod. | `list(string)` | <pre>[<br/>  "dev",<br/>  "qa"<br/>]</pre> | no |
| <a name="input_operations_alert_email"></a> [operations\_alert\_email](#input\_operations\_alert\_email) | Correo (de preferencia una lista de grupo) del canal de operaciones: recibe las alertas de los entornos que crea 3-workloads (disponibilidad, SLO, recursos), además de los notification\_emails de cada entorno. null (por defecto): sin canal de operaciones. Las alertas de auditoría van siempre a security\_alert\_email, nunca a este canal. | `string` | `null` | no |
| <a name="input_scc_notification_filter"></a> [scc\_notification\_filter](#input\_scc\_notification\_filter) | Filtro de los hallazgos de Security Command Center que se publican en el tema de Pub/Sub. Por defecto, los activos y sin silenciar de severidad alta o crítica. | `string` | `"state = \"ACTIVE\" AND mute != \"MUTED\" AND (severity = \"HIGH\" OR severity = \"CRITICAL\")"` | no |
| <a name="input_secret_names"></a> [secret\_names](#input\_secret\_names) | Mapa entorno → nombres cortos de los contenedores de secretos (sin valores, ADR 0015). El ID queda <prefix>-<entorno>-sec-<nombre>. Un entorno sin entrada no tiene secretos. | `map(list(string))` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_artifact_registry_repositories"></a> [artifact\_registry\_repositories](#output\_artifact\_registry\_repositories) | Mapa entorno → aplicación → URL del repositorio Docker (<ubicación>-docker.pkg.dev/<proyecto>/<repositorio>), como la salida de la etapa 4 anterior. Binary Authorization admite estos repositorios y binary\_authorization\_allowlist\_patterns. |
| <a name="output_gke_workload_identity_members"></a> [gke\_workload\_identity\_members](#output\_gke\_workload\_identity\_members) | Mapa entorno → aplicación → clúster (primary y, en dr\_environments, dr) → principalSet de Workload Identity Federation for GKE de todos los pods de ese clúster (…/kubernetes.cluster/https://container.googleapis.com/v1/projects/<proyecto>/locations/<ubicación>/clusters/<prefix>-<env>-<app>-gke[-dr]) que actúa como la cuenta workload, o null mientras gke\_workload\_identity\_bindings sea false (el enlace no existe). |
| <a name="output_kms_key_ids"></a> [kms\_key\_ids](#output\_kms\_key\_ids) | Mapa entorno → llave → ID de la llave KMS. Llave: <uso> en primary\_region, <uso>\_dr en dr\_region y <uso>\_us en la multirregión us (formato de la etapa 2 anterior; el uso es la primera palabra y la ubicación sale del ID). Solo las llaves que alguien usa: en la primaria gke, compute, run, sql, storage, redis, filestore y secrets; en dr\_region (solo entornos de dr\_environments) gke, compute, run, sql, backup y secrets; en us storage (solo dr\_environments); y artifacts solo en artifact\_registry\_location. |
| <a name="output_log_bucket"></a> [log\_bucket](#output\_log\_bucket) | Nombre del bucket de logs de auditoría (destino del sink de proyecto). |
| <a name="output_notification_channel_ids"></a> [notification\_channel\_ids](#output\_notification\_channel\_ids) | Mapa uso → ID del canal de notificación de Monitoring. security: canal de correo de security\_alert\_email (alertas de auditoría, solo de 1-base). operations: canal de operations\_alert\_email, que 3-workloads agrega a las alertas de su entorno; solo existe con operations\_alert\_email. |
| <a name="output_off_hours_role_id"></a> [off\_hours\_role\_id](#output\_off\_hours\_role\_id) | ID completo (projects/<id>/roles/<prefix>OffHoursScheduler) del rol personalizado del apagado fuera de horario (ADR 0028). Lo crea 0-bootstrap; 1-base lo publica. |
| <a name="output_onprem_dns_service_account"></a> [onprem\_dns\_service\_account](#output\_onprem\_dns\_service\_account) | Correo de la cuenta de la VM DNS de onprem-sim (<prefix>-common-net-dns), o null si 0-bootstrap no tiene onprem\_dns\_vm = true. El hub la adjunta a la VM; ninguna raíz lee esta salida. |
| <a name="output_runtime_service_accounts"></a> [runtime\_service\_accounts](#output\_runtime\_service\_accounts) | Mapa entorno → aplicación → uso → correo de las cuentas de ejecución (<prefix>-<env>-<app>-<uso>): gke\_nodes, workload, mig, run y, en off\_hours\_environments, scheduler (<prefix>-<env>-<app>-sched). 3-workloads las usa; no las crea. |
| <a name="output_secret_ids"></a> [secret\_ids](#output\_secret\_ids) | Mapa entorno → nombre corto → ID del secreto (projects/<proyecto>/secrets/<id>). Un entorno sin secretos tiene un mapa vacío. |
| <a name="output_security_alert_email"></a> [security\_alert\_email](#output\_security\_alert\_email) | Correo que recibe las alertas de auditoría del proyecto (CIS 2.5 a 2.12). |
<!-- END_TF_DOCS -->
