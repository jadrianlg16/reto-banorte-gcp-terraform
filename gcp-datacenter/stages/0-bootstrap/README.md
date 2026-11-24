# Etapa `0-bootstrap`

Arranque del proyecto único (ADR 0029 §2). La corre **una sola vez** una persona, a mano; después
todo lo hace el pipeline con las nueve cuentas que crea esta etapa. El proyecto ya existe: lo
crea una persona con la consola o `gcloud`, lo liga a una cuenta de facturación de pago y entra
aquí como `project_id`. Ninguna raíz crea ni borra el proyecto.

## Qué crea

| Archivo | Recursos |
|---|---|
| `main.tf` | Todas las APIs del proyecto (una sola vez, `disable_on_destroy = false`) más `additional_apis`; los agentes de servicio que 1-base necesita (`google_project_service_identity`: Artifact Registry, Filestore, Backup for GKE, Pub/Sub, Memorystore, Secret Manager y Cloud SQL); OS Login en el proyecto; la cuenta de Compute por defecto sin `roles/editor` (`DEPRIVILEGE`); `resourcemanager.tagUser` de proyecto para el agente de GKE y `<número>@cloudservices` (etiquetas seguras de nodos y VM; aquí y no en 1-base para que ninguna cuenta del pipeline pueda asignar `tagUser`); llave KMS y bucket del estado; presupuesto del proyecto |
| `service_accounts.tf` | Las nueve cuentas del pipeline, sus roles de proyecto, su acceso condicionado al bucket de estado y quién toma cada una por WIF |
| `custom_roles.tf` | Cuatro roles personalizados del proyecto |
| `wif.tf` | Pool y proveedor de Workload Identity Federation para GitHub Actions |
| `deny_policy.tf` | Etiqueta `<prefix>-proteccion = etapa-0` y política de denegación del proyecto |
| `org.tf` | Solo con organización: las políticas de organización aplicadas al proyecto (módulo `org`, con `org_id`) y el perímetro de VPC-SC en dry-run (módulo `vpc-sc`, con `access_policy_id`) |

Nombres con `prefix = "bnt"`: bucket `bnt-bootstrap-ops-tfstate[-<name_suffix>]`, llavero
`bnt-bootstrap-sec-keyring-us`, pool `bnt-bootstrap-sec-wif-pool`, presupuesto
`bnt-bootstrap-ops-budget` y política `bnt-bootstrap-sec-deny-pipeline`.

### Ubicación del estado

El bucket es multirregional (`state_bucket_location`, `US` por defecto) o de doble región
configurable (`state_bucket_dual_regions`, con replicación turbo), y su llave está en la
multirregión de KMS homónima (`us`), como exige la CMEK de Cloud Storage. Así el estado y su
llave sobreviven a la caída de `primary_region` (runbook de conmutación a DR). Valores fijos:
versionado, acceso uniforme, prevención de acceso público, sin `force_destroy`,
`prevent_destroy` y borrado solo de versiones viejas (`state_versions_to_keep`).

## Cuentas del pipeline (ADR 0029 §3)

| Cuenta | Raíz | Entorno de GitHub (WIF) | Escribe | Lee |
|---|---|---|---|---|
| `<prefix>-tf-base` | `1-base` | `common` | `1-base` | `0-bootstrap` |
| `<prefix>-tf-net` | `2-networks` (hub) | `common` | `2-networks/hub` | — |
| `<prefix>-tf-net-<env>` | `2-networks/envs/<env>` | `<env>` | `2-networks/<env>` | `2-networks/hub` |
| `<prefix>-tf-wl-<env>` | `3-workloads/envs/<env>` | `<env>` | `3-workloads/<env>` | `1-base`, `2-networks/<env>` |
| `<prefix>-tf-read` | plan, drift, prueba de humo, huérfanos | cualquier trabajo del repositorio | — | todo el bucket |

Las raíces de red no leen `1-base`: no usan ninguna de sus salidas. Todo sale de
`local.stage_roots`, que es también la salida `state_iam_conditions`. Cada escritura es
`roles/storage.objectAdmin` y cada lectura `roles/storage.objectViewer` sobre el bucket, con la
condición `resource.type == "storage.googleapis.com/Bucket" || resource.name.startsWith("projects/_/buckets/<bucket>/objects/<prefijo>/")`.
La primera cláusula deja listar el bucket (el backend la necesita); la barra final evita que un
prefijo coincida con un hermano.

### Roles de proyecto

Todos se dan en el proyecto y desde aquí: un rol de proyecto para un principal compartido nunca
se declara en una raíz de entorno (ADR 0029 §4). Todas las cuentas tienen además
`roles/serviceusage.serviceUsageConsumer` (proyecto de cuota).

| Cuenta | Roles |
|---|---|
| `tf-base` | `cloudkms.admin` (salvo el llavero del estado), `TfSecretContainerAdmin`, `artifactregistry.admin`, `binaryauthorization.policyEditor`, `logging.configWriter`, `monitoring.alertPolicyEditor`, `monitoring.notificationChannelEditor`, `essentialcontacts.admin`, `pubsub.admin`, `securitycenter.notificationConfigEditor`, `storage.admin` (buckets `<prefix>-common-`), `TfServiceAccountManager` (cuentas de ejecución de los entornos), `projectIamAdmin` en dos concesiones delegadas (roles de lectura de personas; roles de las cuentas de ejecución, Cloud SQL por IAM y el apagado). Ningún rol de organización ni de la política de acceso (`org.tf` los usa la persona de esta etapa) |
| `tf-net` | `compute.networkAdmin`, `compute.securityAdmin`, `dns.admin`; con `onprem_dns_vm = true`, además `compute.instanceAdmin.v1` sin condición para la VM DNS de `onprem-sim` (riesgo aceptado mientras esté activo: el hub podría cambiar las VM de los entornos). `1-base` le da `iam.serviceAccountUser` solo sobre la cuenta de esa VM |
| `tf-net-<env>` | los de `tf-net`, más `TfNetworkTagManager` (claves y valores de etiquetas y su IAM, sin ligarlas) y `servicenetworking.networksAdmin` |
| `tf-wl-<env>` | `backupdr.admin` (bóvedas `<prefix>-<env>-`), `certificatemanager.editor`, `cloudsql.admin` (instancias `<prefix>-<env>-data-`), `compute.instanceAdmin.v1`, `compute.loadBalancerAdmin`, `compute.securityAdmin`, `compute.networkUser`, `container.clusterAdmin` (clústeres `<prefix>-<env>-` de `primary_region` y `dr_region`), `file.editor`, `gkebackup.admin`, `monitoring.alertPolicyEditor`, `monitoring.dashboardEditor`, `monitoring.notificationChannelEditor`, `monitoring.servicesEditor`, `monitoring.uptimeCheckConfigEditor`, `redis.admin`, `run.admin`, `storage.admin` (buckets `<prefix>-<env>-`); `cloudscheduler.admin` solo en dev y qa (ADR 0028). Sin roles de IAM ni de etiquetas en el proyecto: `1-base` le da `iam.serviceAccountUser` sobre cada cuenta de ejecución de su entorno que adjunta, y su spoke, `tagUser` sobre los valores `lb_backend` e `iap_ssh` |
| `tf-read` | `viewer`, `iam.securityReviewer`, `cloudasset.viewer`, `networkmanagement.admin` y `storage.objectViewer` sobre el bucket de estado |

Que cada lista alcance para aplicar su raíz es HYPOTHESIS hasta el primer apply. Ninguna cuenta
tiene `storage.admin` ni `projectIamAdmin` sin condición, ni `iam.serviceAccountAdmin`,
`iam.roleAdmin` o `serviceusage.serviceUsageAdmin` (las APIs y los agentes los crea esta
etapa). `cloudsql.admin`, `container.clusterAdmin` y `backupdr.admin` llevan una condición por
nombre de recurso con la forma `resource.type != <tipo> || resource.name.startsWith(<prefijo del
entorno>)`, porque Cloud SQL (`Instance`, `BackupRun`), GKE (`Cluster`) y Backup and DR
(`BackupVaults`) figuran en "Resource attributes for IAM Conditions"; los demás tipos de esos
roles (y crear un clúster, que GKE comprueba en el proyecto) quedan sin límite. Compute, Cloud
Run, Memorystore, Filestore, Backup for GKE y Monitoring no figuran en esa página y van sin
condición: una cuenta de dev puede tocar recursos de prod de esos servicios (riesgo aceptado,
ADR 0029 §3 y §9). `container.clusterAdmin` (y no `container.admin`) no trae permisos sobre
objetos de Kubernetes (pods, secretos, tokens de cuentas de Kubernetes); Monitoring va con roles
finos en lugar de `monitoring.editor`, que trae permisos `serviceusage.*`.

`projectIamAdmin` de `tf-base` es una concesión delegada:
`api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([...])`, en dos
asignaciones porque cada lista admite como máximo 10 roles ("Set limits on granting roles" de la
documentación de IAM): `base_grantable_roles` (personas y agentes) y `runtime_grantable_roles`
(cuentas de ejecución). Una llamada que no cambia bindings (la configuración de auditoría de
`1-base`) tiene la lista vacía y pasa (HYPOTHESIS).

### Roles personalizados (`custom_roles.tf`)

| Llave de `custom_role_ids` | Rol | Quién lo usa |
|---|---|---|
| `secret_container_admin` | `<prefix>TfSecretContainerAdmin` | `tf-base`: contenedores de secretos y su IAM (lectura de los secretos por las cuentas de ejecución), sin leer ni agregar versiones |
| `service_account_manager` | `<prefix>TfServiceAccountManager` | `tf-base`: cuentas de ejecución y su IAM, lo de `iam.serviceAccountAdmin` sin `createTagBinding` ni `deleteTagBinding` |
| `network_tag_manager` | `<prefix>TfNetworkTagManager` | `tf-net-<env>`: claves y valores de etiquetas y su IAM, como `resourcemanager.tagAdmin` sin `tagHolds`; ni este ni aquel ligan etiquetas (`tagValueBindings`, `*TagBinding`) |
| `off_hours_scheduler` | `<prefix>OffHoursScheduler` | cuentas del apagado fuera de horario (ADR 0028); `1-base` se lo da y lo publica como `off_hours_role_id` |

Van aquí y no en la raíz que los usa para que ninguna cuenta del pipeline necesite
`roles/iam.roleAdmin`.

## Protección del estado y de la etapa 0 (ADR 0029 §5)

La política de denegación ya no puede ir en una carpeta: va en el proyecto y distingue lo
protegido con una etiqueta, porque las condiciones de denegación solo reconocen etiquetas.

- La clave `<prefix>-proteccion` (padre: el proyecto) con valor `etapa-0` se liga al bucket de
  estado, al llavero del estado y a las nueve cuentas del pipeline.
- Regla 1, sobre lo que tenga la etiqueta: borrar o cambiar el bucket, su IAM y sus etiquetas;
  el IAM del llavero y de la llave, cambiar la llave y destruir versiones; el IAM de las cuentas
  del pipeline, suplantarlas (`actAs`, `getAccessToken`, `signJwt`…), cambiarlas o borrarlas.
- Regla 2, sin condición: crear, cambiar o borrar pools y proveedores de WIF y roles
  personalizados, crear llaves de cuentas de servicio, pedir tokens o firmas de cualquier cuenta
  de servicio (`getAccessToken`, `getOpenIdToken`, `implicitDelegation`, `signBlob`, `signJwt`;
  `actAs` no, porque adjuntar las cuentas de ejecución lo necesita), habilitar o deshabilitar
  servicios (`serviceusage.googleapis.com/services.enable`, `services.disable`,
  `consumerpolicy.update`; solo esta etapa habilita APIs) y borrar el proyecto. No niega
  `services.use`, que las nueve cuentas usan como proyecto de cuota.
- Regla 3, sin condición: leer valores de secretos (`versions.access`). Se niega a todas las
  cuentas del pipeline salvo `tf-net`, que lee la clave compartida de la VPN del hub.
- Regla 4, sin condición y para `principalSet://goog/public:all`: crear llaves de cuentas de
  servicio (`iam.googleapis.com/serviceAccountKeys.create`). Sin organización no existe la
  política `iam.disableServiceAccountKeyCreation`, y el pipeline usa WIF. No tiene excepción
  porque ninguna variable identifica a quien administra esta etapa; esa persona puede quitar la
  regla con `roles/iam.denyAdmin`.
- Las reglas 1 y 2 se niegan a las nueve cuentas. Nada niega los objetos del estado, el proyecto
  de cuota ni `projects.setIamPolicy` (la concesión delegada lo necesita).

Límites: `iam.serviceAccounts.createTagBinding`/`deleteTagBinding` y
`cloudkms.keyRings.deleteTagBinding` no se pueden negar. Por eso `tf-base` usa
`TfServiceAccountManager` en lugar de `iam.serviceAccountAdmin` y no tiene `tagUser`.
Si las etiquetas no funcionan en el proyecto (HYPOTHESIS sin organización),
`enable_protection_tags = false` quita la regla 1 (quedan las reglas 2, 3 y 4) y la protección
de lo etiquetado queda en los roles condicionados. `enable_deny_policy = false` quita la política (quien aplica necesita
`roles/iam.denyAdmin`).

## Workload Identity Federation

El proveedor acepta solo tokens con
`assertion.repository_id == "<github_repository_id>" && assertion.repository_owner_id == "<github_repository_owner_id>"`
(`attribute_condition`) y mapea `google.subject`, `attribute.repository_id`,
`attribute.repository_owner_id`, `attribute.repository`, `attribute.ref`,
`attribute.environment` y `attribute.deploy`. La confianza se basa en los IDs numéricos porque los
nombres se pueden volver a registrar; los IDs no se reutilizan
(`gh api repos/<dueño>/<repositorio> --jq '.id, .owner.id'`).

`attribute.deploy` vale el entorno de GitHub del trabajo (`common`, `dev`, `qa` o `prod`) solo si
el token trae la afirmación `environment`, `ref == refs/heads/main`,
`job_workflow_ref == <github_repository>/.github/workflows/_terraform-root.yml@refs/heads/main`
(el único flujo que aplica) y `event_name` igual a `push` o `workflow_dispatch` (los eventos de
`apply.yml` y `destroy.yml`); si no, vale `none`. Un `pull_request`, un `workflow_run`, otro
flujo del repositorio o `_terraform-root.yml` desde otra rama no obtienen cuentas de escritura.
Las afirmaciones que pueden faltar se leen solo después de comprobar que están, para que el
mapeo no falle en los trabajos sin entorno. Que GitHub ponga en `job_workflow_ref` la rama
(`@refs/heads/main`) y no un SHA cuando el flujo reutilizable se llama con ruta local
(`uses: ./.github/workflows/...`) no está documentado (VERIFICAR-EN-APPLY): si fuera otro valor,
el apply fallaría al tomar la cuenta, sin abrir permisos. Dentro del repositorio:

- `tf-base` y `tf-net`: `principalSet://…/attribute.deploy/common`;
- `tf-net-<env>` y `tf-wl-<env>`: `principalSet://…/attribute.deploy/<env>`;
- `tf-read`: `principalSet://…/attribute.repository_id/<github_repository_id>`.

Un trabajo sin entorno de GitHub, de otra rama, de otro evento o de cualquier flujo que no sea
`_terraform-root.yml` en `main` solo obtiene `tf-read`. Todos los trabajos que escriben son el trabajo `apply` de
`_terraform-root.yml`, que `apply.yml` y `destroy.yml` llaman desde `main`.
`github_repository` tiene que coincidir exactamente con la afirmación `repository` (mayúsculas
incluidas); si el repositorio se renombra, las cuentas que escriben dejan de aceptar tokens hasta
volver a aplicar esta etapa. Los pools de WIF se borran de forma suave durante 30 días: si se
destruyen, el mismo ID no se puede reusar hasta que venzan.

## Cómo se ejecuta

Requisitos de quien la corre (con `gcloud auth application-default login`): `roles/owner` en el
proyecto, `roles/iam.denyAdmin` (la política de denegación; `owner` no lo incluye) y
`roles/billing.costsManager` en la cuenta de facturación (presupuesto). Con `org_id`, además
`roles/orgpolicy.policyAdmin` en la organización (esta etapa crea las políticas de organización
del proyecto); con `access_policy_id`, `roles/accesscontextmanager.policyAdmin` en la
organización (o `policyEditor` sobre la política) para crear el perímetro. Las políticas de
organización se aplican al final del primer apply, después de las cuentas y sus roles. El
proyecto es el proyecto de cuota (`providers.tf`):
si el primer plan falla por una API apagada, se habilitan `cloudresourcemanager`, `serviceusage`
y `storage` con `gcloud services enable` y se repite (HYPOTHESIS: que basten esas tres).

Primera ejecución (el bucket todavía no existe):

```bash
cd stages/0-bootstrap
cp terraform.tfvars.example terraform.tfvars          # y ajustar valores reales
cp backend_override.tf.example backend_override.tf    # backend local temporal
terraform init
terraform apply
```

`backend_override.tf` reemplaza el backend `gcs` de `backend.tf` por uno local sin tocar
`backend.tf`. El override y el estado local están en el `.gitignore` de esta raíz.

Migración al bucket:

```bash
STATE_BUCKET="$(terraform output -raw state_bucket)"
rm backend_override.tf
terraform init -migrate-state -backend-config="bucket=${STATE_BUCKET}"
rm terraform.tfstate terraform.tfstate.backup          # tras comprobar que el estado migró
```

Después, cualquier cambio a esta etapa lo vuelve a aplicar una persona con
`terraform init -backend-config="bucket=<state_bucket>"`. Las salidas `workload_identity_provider`,
`stage_service_accounts`, `read_service_account` y `state_bucket` se cargan como variables del
repositorio de GitHub.

## Pruebas

`tests/0-bootstrap.tftest.hcl`: `mock_provider` con `override_during = plan` (Terraform
>= 1.11) y `command = plan` con los valores de `terraform.tfvars.example`. Comprueba las APIs (y
que no se apagan), los agentes de servicio, OS Login, `DEPRIVILEGE`, el presupuesto por proyecto,
el bucket y su llave, las ocho llaves de `stage_service_accounts` y los nombres de las cuentas,
que no haya roles básicos ni `serviceAccountAdmin` y que `storage.admin`, `projectIamAdmin` y
`cloudkms.admin` siempre lleven condición, las condiciones exactas por entorno, la tabla de
estado, el `principalSet` de cada cuenta y la expresión exacta de `attribute.deploy` (sin
prefijos de `job_workflow_ref` ni eventos de PR), los roles de `tf-wl-<env>`
(`roles_de_cargas_por_entorno`: `container.clusterAdmin` y Monitoring fino en lugar de
`container.admin` y `monitoring.editor`, y las condiciones exactas de Cloud SQL, GKE y Backup and
DR de cada entorno), los cuatro roles personalizados, la etiqueta y sus enlaces y las cuatro
reglas de la denegación (los permisos de Service Usage de la regla 2, sin `services.use`, y las
llaves para `public:all`); que ninguna cuenta del pipeline tenga un rol de
proyecto que ligue o quite etiquetas (`ningun_rol_del_pipeline_liga_etiquetas`: `tagUser`,
`tagAdmin`, roles con `*TagBinding` o `tagValueBindings`, y `cloudkms.admin` y `storage.admin`
solo con una condición que deja fuera el llavero y el bucket del estado); las variantes sin
etiquetas, sin denegación, con organización y política de acceso (las ocho políticas de
organización y el perímetro en dry-run aquí, sin ningún rol de organización para el pipeline) y
con `onprem_dns_vm` (solo `tf-net` suma `compute.instanceAdmin.v1`; sin la opción, solo las
cuentas de cargas lo tienen); y que se rechazan entradas inválidas.

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

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_org_policies"></a> [org\_policies](#module\_org\_policies) | ../../modules/org | n/a |
| <a name="module_stage_iam"></a> [stage\_iam](#module\_stage\_iam) | ../../modules/iam | n/a |
| <a name="module_state_kms"></a> [state\_kms](#module\_state\_kms) | ../../modules/kms | n/a |
| <a name="module_vpc_sc"></a> [vpc\_sc](#module\_vpc\_sc) | ../../modules/vpc-sc | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [google-beta_google_project_service_identity.this](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_project_service_identity) | resource |
| [google_billing_budget.project](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/billing_budget) | resource |
| [google_compute_project_metadata_item.os_login](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_project_metadata_item) | resource |
| [google_iam_deny_policy.pipeline](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_deny_policy) | resource |
| [google_iam_workload_identity_pool.github](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool) | resource |
| [google_iam_workload_identity_pool_provider.github](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool_provider) | resource |
| [google_kms_crypto_key_iam_member.state_storage_agent](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_crypto_key_iam_member) | resource |
| [google_project_default_service_accounts.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_default_service_accounts) | resource |
| [google_project_iam_custom_role.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_custom_role) | resource |
| [google_project_iam_member.tag_user_agents](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_service.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_service_account.read](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account.stage](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_storage_bucket.state](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_tags_location_tag_binding.state_bucket](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/tags_location_tag_binding) | resource |
| [google_tags_location_tag_binding.state_keyring](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/tags_location_tag_binding) | resource |
| [google_tags_tag_binding.pipeline_accounts](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/tags_tag_binding) | resource |
| [google_tags_tag_key.protection](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/tags_tag_key) | resource |
| [google_tags_tag_value.stage0](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/tags_tag_value) | resource |
| [google_project.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/project) | data source |
| [google_storage_project_service_account.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/storage_project_service_account) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | Cuenta de facturación ligada al proyecto (formato XXXXXX-XXXXXX-XXXXXX). Solo se usa para el presupuesto del proyecto; la persona que aplica necesita roles/billing.costsManager en ella. | `string` | n/a | yes |
| <a name="input_budget_amount"></a> [budget\_amount](#input\_budget\_amount) | Monto mensual del presupuesto del proyecto, en la moneda de la cuenta de facturación (unidades enteras). | `number` | n/a | yes |
| <a name="input_dr_region"></a> [dr\_region](#input\_dr\_region) | Región de DR (ADR 0002). Ver primary\_region. | `string` | n/a | yes |
| <a name="input_github_repository"></a> [github\_repository](#input\_github\_repository) | Repositorio de GitHub (<dueño>/<repositorio>) autorizado por Workload Identity Federation, escrito exactamente como la afirmación repository del token (mismas mayúsculas y minúsculas). Qué repositorio entra lo deciden github\_repository\_id y github\_repository\_owner\_id; este nombre decide qué flujo reutilizable puede tomar una cuenta que escribe (job\_workflow\_ref tiene que ser <dueño>/<repositorio>/.github/workflows/\_terraform-root.yml@refs/heads/main). Si el repositorio se renombra, las cuentas que escriben dejan de aceptar tokens hasta volver a aplicar 0-bootstrap con el nombre nuevo. | `string` | n/a | yes |
| <a name="input_github_repository_id"></a> [github\_repository\_id](#input\_github\_repository\_id) | ID numérico del repositorio autorizado (afirmación repository\_id del token OIDC de GitHub; gh api repos/<dueño>/<repositorio> --jq .id). Es la base de la confianza de WIF: no se reutiliza si el repositorio se borra o se renombra. | `string` | n/a | yes |
| <a name="input_github_repository_owner_id"></a> [github\_repository\_owner\_id](#input\_github\_repository\_owner\_id) | ID numérico del dueño (organización o usuario) del repositorio autorizado (afirmación repository\_owner\_id; gh api repos/<dueño>/<repositorio> --jq .owner.id). | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes (§4.3). Deben traer app, owner y cost\_center; la raíz agrega env = bootstrap y managed\_by = terraform. | `map(string)` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa en todos los nombres (§4.2), por ejemplo bnt. | `string` | n/a | yes |
| <a name="input_primary_region"></a> [primary\_region](#input\_primary\_region) | Región primaria (ADR 0002). Con dr\_region, las dos regiones de un bucket de estado de doble región (state\_bucket\_dual\_regions). | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto único (ADR 0029 §1). Lo crea una persona con la consola o gcloud y lo liga a una cuenta de facturación de pago; ninguna raíz lo crea ni lo borra. | `string` | n/a | yes |
| <a name="input_access_policy_id"></a> [access\_policy\_id](#input\_access\_policy\_id) | ID numérico de la política de Access Context Manager de la organización, si existe. Con él, esta etapa crea el perímetro de VPC-SC en dry-run alrededor de todo el proyecto (org.tf); quien la aplica necesita roles/accesscontextmanager.policyAdmin en la organización (o policyEditor sobre la política). null (por defecto): sin perímetro. Exige org\_id. | `string` | `null` | no |
| <a name="input_additional_allowed_locations"></a> [additional\_allowed\_locations](#input\_additional\_allowed\_locations) | Solo con org\_id: ubicaciones extra permitidas por gcp.resourceLocations además de primary\_region y dr\_region. Por defecto us: la multirregión del estado, de los llaveros y de los repositorios. | `list(string)` | <pre>[<br/>  "us"<br/>]</pre> | no |
| <a name="input_additional_apis"></a> [additional\_apis](#input\_additional\_apis) | APIs extra que se habilitan en el proyecto además de las fijas (por ejemplo bigquery.googleapis.com). Se habilitan una sola vez y no se apagan al destruir. | `set(string)` | `[]` | no |
| <a name="input_budget_alert_thresholds"></a> [budget\_alert\_thresholds](#input\_budget\_alert\_thresholds) | Umbrales de alerta del presupuesto sobre el gasto real, como fracción del monto (0.5 = 50 %). Además se alerta al 100 % del gasto pronosticado. | `list(number)` | <pre>[<br/>  0.5,<br/>  0.75,<br/>  0.9,<br/>  1<br/>]</pre> | no |
| <a name="input_directory_customer_id"></a> [directory\_customer\_id](#input\_directory\_customer\_id) | Solo con org\_id: ID de cliente de Cloud Identity (Cxxxxxxxx), único dominio admitido en las políticas de IAM (iam.allowedPolicyMemberDomains). null: esa política no se crea. | `string` | `null` | no |
| <a name="input_enable_deny_policy"></a> [enable\_deny\_policy](#input\_enable\_deny\_policy) | Si es true (por defecto), crea la política de denegación del proyecto contra las nueve cuentas del pipeline (ADR 0029 §5). Sin etiquetas solo lleva la regla sin condición (WIF, roles personalizados, llaves de cuentas y borrar el proyecto). Quien aplica necesita roles/iam.denyAdmin. | `bool` | `true` | no |
| <a name="input_enable_protection_tags"></a> [enable\_protection\_tags](#input\_enable\_protection\_tags) | Si es true (por defecto), crea la etiqueta <prefix>-proteccion = etapa-0 y la liga al bucket y al llavero del estado y a las nueve cuentas del pipeline (ADR 0029 §5). false solo si un apply demuestra que las etiquetas no funcionan en el proyecto; la protección queda entonces en los roles condicionados. | `bool` | `true` | no |
| <a name="input_location_short_codes"></a> [location\_short\_codes](#input\_location\_short\_codes) | Mapa ubicación → código corto que se agrega a los nombres de recursos con ubicación (§4.2). Debe incluir la ubicación de KMS del estado (lower(state\_bucket\_location): us, eu o asia). | `map(string)` | <pre>{<br/>  "asia": "asia",<br/>  "eu": "eu",<br/>  "northamerica-south1": "nas1",<br/>  "us": "us",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Sufijo opcional del nombre del bucket de estado para que sea único a nivel mundial (los nombres de bucket son globales). Vacío: sin sufijo. | `string` | `""` | no |
| <a name="input_onprem_dns_vm"></a> [onprem\_dns\_vm](#input\_onprem\_dns\_vm) | Si es true, la cuenta del hub (<prefix>-tf-net) recibe roles/compute.instanceAdmin.v1 y 1-base crea la cuenta de la VM DNS de onprem-sim (<prefix>-common-net-dns) con serviceAccountUser para el hub. Va en true solo junto con simulate\_onprem = true y onprem\_dns\_vm = true en 2-networks. Por defecto false: el hub no administra VM. | `bool` | `false` | no |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | ID numérico de la organización, si el proyecto está dentro de una (ADR 0029 §1). Con él, esta etapa aplica las políticas de organización al proyecto (org.tf); quien la aplica necesita roles/orgpolicy.policyAdmin en la organización. null (por defecto): proyecto sin organización ni políticas de organización. Ninguna cuenta del pipeline recibe roles de organización. | `string` | `null` | no |
| <a name="input_state_bucket_dual_regions"></a> [state\_bucket\_dual\_regions](#input\_state\_bucket\_dual\_regions) | Opcional: las dos regiones de un bucket de estado de doble región configurable (por ejemplo ["us-central1", "us-east4"]), dentro de state\_bucket\_location; lleva replicación turbo. Vacío (por defecto): bucket multirregional. | `list(string)` | `[]` | no |
| <a name="input_state_bucket_location"></a> [state\_bucket\_location](#input\_state\_bucket\_location) | Multirregión del bucket de estado y de su llave KMS: US, EU o ASIA. Con state\_bucket\_dual\_regions vacío el bucket es multirregional; si no, es de doble región configurable dentro de esta multirregión. La llave va en la ubicación de KMS homónima (us, eu, asia), como exige la CMEK de Cloud Storage. Así el estado y la llave sobreviven a la caída de primary\_region. La ubicación de un bucket no se cambia después de crearlo. | `string` | `"US"` | no |
| <a name="input_state_versions_to_keep"></a> [state\_versions\_to\_keep](#input\_state\_versions\_to\_keep) | Versiones no actuales de cada archivo de estado que se conservan en el bucket; las más viejas se borran. Permiten recuperar un estado dañado. | `number` | `20` | no |
| <a name="input_vpc_sc_restricted_services"></a> [vpc\_sc\_restricted\_services](#input\_vpc\_sc\_restricted\_services) | Servicios restringidos por el perímetro opcional; debe incluir storage.googleapis.com. Con un solo proyecto, el perímetro ya incluye llaves y secretos: KMS y Secret Manager se restringen también. | `list(string)` | <pre>[<br/>  "artifactregistry.googleapis.com",<br/>  "backupdr.googleapis.com",<br/>  "bigquery.googleapis.com",<br/>  "cloudkms.googleapis.com",<br/>  "compute.googleapis.com",<br/>  "container.googleapis.com",<br/>  "file.googleapis.com",<br/>  "gkebackup.googleapis.com",<br/>  "pubsub.googleapis.com",<br/>  "redis.googleapis.com",<br/>  "run.googleapis.com",<br/>  "secretmanager.googleapis.com",<br/>  "sqladmin.googleapis.com",<br/>  "storage.googleapis.com"<br/>]</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_custom_role_ids"></a> [custom\_role\_ids](#output\_custom\_role\_ids) | Mapa rol → ID completo (projects/<id>/roles/<rol>) de los roles personalizados: secret\_container\_admin, service\_account\_manager, network\_tag\_manager y off\_hours\_scheduler. |
| <a name="output_onprem_dns_vm_enabled"></a> [onprem\_dns\_vm\_enabled](#output\_onprem\_dns\_vm\_enabled) | true con onprem\_dns\_vm: el hub tiene compute.instanceAdmin.v1 y 1-base crea la cuenta de la VM DNS de onprem-sim. |
| <a name="output_org_policies_enabled"></a> [org\_policies\_enabled](#output\_org\_policies\_enabled) | true si el proyecto está en una organización (org\_id) y esta etapa le aplicó las políticas de organización (org.tf). |
| <a name="output_project_id"></a> [project\_id](#output\_project\_id) | ID del proyecto único. |
| <a name="output_project_number"></a> [project\_number](#output\_project\_number) | Número del proyecto único. |
| <a name="output_read_service_account"></a> [read\_service\_account](#output\_read\_service\_account) | Correo de la cuenta de solo lectura <prefix>-tf-read (plan, drift, prueba de humo y huérfanos; variable GCP\_AUDIT\_SERVICE\_ACCOUNT). |
| <a name="output_stage_service_accounts"></a> [stage\_service\_accounts](#output\_stage\_service\_accounts) | Mapa raíz (1-base, 2-networks, 2-networks/<env>, 3-workloads/<env>) → correo de la cuenta del pipeline que la aplica. |
| <a name="output_state_bucket"></a> [state\_bucket](#output\_state\_bucket) | Nombre del bucket de estado; las raíces lo reciben como state\_bucket y en -backend-config. |
| <a name="output_state_iam_conditions"></a> [state\_iam\_conditions](#output\_state\_iam\_conditions) | Mapa raíz → { writes, reads }: prefijos del bucket de estado que escribe y que lee la cuenta de cada raíz (ADR 0029 §3). tf-read lee todo el bucket. |
| <a name="output_state_kms_key_id"></a> [state\_kms\_key\_id](#output\_state\_kms\_key\_id) | ID completo de la llave KMS que cifra el bucket de estado. |
| <a name="output_vpc_sc_perimeter_name"></a> [vpc\_sc\_perimeter\_name](#output\_vpc\_sc\_perimeter\_name) | Nombre completo del perímetro de VPC-SC (accessPolicies/<política>/servicePerimeters/<nombre>) que crea esta etapa, o null sin access\_policy\_id. |
| <a name="output_workload_identity_pool"></a> [workload\_identity\_pool](#output\_workload\_identity\_pool) | Nombre completo del pool de WIF. |
| <a name="output_workload_identity_provider"></a> [workload\_identity\_provider](#output\_workload\_identity\_provider) | Nombre completo del proveedor de WIF (projects/<número>/locations/global/workloadIdentityPools/<pool>/providers/<proveedor>), para google-github-actions/auth. |
<!-- END_TF_DOCS -->
