# Etapa `4-projects/envs/<env>`

Raíz de la etapa 4 (§7.5 del contrato). Las tres raíces `envs/{dev,qa,prod}` son idénticas salvo
`backend.tf` (prefijo `4-projects/<env>`) y `terraform.tfvars.example`; las diferencias de
entorno llegan por variables (`environment`, `deletion_policy`).

## Qué crea

Por cada aplicación de `applications` (por defecto una, `app`):

- **Proyecto de servicio** `<prefix>-<environment>-<app>[-<project_suffix>]` con
  `project-factory`, en la carpeta del entorno (`folder_ids` de 1-org; se comprueba que la
  carpeta pertenezca a `org_id`), unido como servicio al host de Shared VPC
  (`host_project_id` del spoke), con etiquetas §4.3 y `app = <llave>`.
- **APIs**: las base (abajo) más `applications[app].apis`.
- **Cuentas de servicio de ejecución** `<prefix>-<environment>-<app>-<uso>` (ADR 0017; el
  guion bajo del uso pasa a guion: `gke_nodes` → `gke-nodes`). La variable `applications`
  rechaza llaves que harían pasar de 30 caracteres el ID más largo.
- **Agentes de servicio** que no existen hasta el primer uso, creados con
  `google_project_service_identity` (google-beta): `sqladmin`, `file`, `redis`, `gkebackup`. El
  de Cloud Storage lo crea la fuente de datos `google_storage_project_service_account`. Los de
  `container`, `compute` y `run` aparecen al habilitar la API (VERIFICAR-EN-APPLY).
- **Permisos** (todos aditivos, por el módulo `iam` salvo los de etiquetas seguras, que el
  módulo no cubre y van como `google_tags_tag_value_iam_member` en la raíz).
- **En prod**: alta en el perímetro de VPC-SC de 2-security (`perimeter_name`) de cada proyecto
  de servicio y del proyecto host del spoke (VPC-SC exige host y servicio en el mismo
  perímetro; su número se lee con `data "google_project"`), con
  `google_access_context_manager_service_perimeter_resource` si `vpc_sc_enforced` es `true` y
  con `..._dry_run_resource` si es `false` (ADR 0009). Se decide con
  `var.environment == "prod"`, no por raíz.

### APIs base

`artifactregistry`, `backupdr`, `binaryauthorization`, `certificatemanager`,
`cloudresourcemanager`, `cloudtrace`, `compute`, `container`, `file`, `gkebackup`, `iam`,
`iamcredentials`, `iap`, `logging`, `monitoring`, `oslogin`, `redis`, `run`, `secretmanager`,
`sqladmin`, `storage` (todas `*.googleapis.com`).

### Cuentas de ejecución y sus roles (en el proyecto de servicio)

| Uso | Para | Roles |
|---|---|---|
| `gke_nodes` | Nodos de GKE | `roles/logging.logWriter`, `roles/monitoring.metricWriter`, `roles/monitoring.viewer`, `roles/stackdriver.resourceMetadata.writer`, `roles/autoscaling.metricsWriter`, `roles/artifactregistry.reader` |
| `workload` | Pods (Workload Identity) | `roles/logging.logWriter`, `roles/monitoring.metricWriter`, `roles/cloudtrace.agent`; `roles/secretmanager.secretAccessor` sobre los secretos de la aplicación |
| `mig` | VM del MIG | `roles/logging.logWriter`, `roles/monitoring.metricWriter`, `roles/artifactregistry.reader` |
| `run` | Servicio de Cloud Run | `roles/logging.logWriter`, `roles/monitoring.metricWriter`, `roles/cloudtrace.agent`; `roles/secretmanager.secretAccessor` sobre los secretos de la aplicación |

No se dan aquí: Cloud SQL (usuarios IAM y `cloudsql.client`/`instanceUser`, módulo `cloud-sql`
en la etapa 5) ni `roles/iam.workloadIdentityUser` de la cuenta `workload` hacia la cuenta de
Kubernetes (el pool `<proyecto>.svc.id.goog` existe solo cuando la etapa 5 crea el clúster).

### Agentes de servicio y permisos

| Agente (`<n>` = número del proyecto) | Subredes del host (`roles/compute.networkUser`) | Llaves KMS (`roles/cloudkms.cryptoKeyEncrypterDecrypter`) | Otros |
|---|---|---|---|
| GKE `service-<n>@container-engine-robot` | `app`, `app_dr` | `gke` | `roles/container.hostServiceAgentUser` en el host; `tagUser` en las etiquetas seguras |
| APIs de Google `<n>@cloudservices.gserviceaccount.com` | `app`, `app_dr` (crea las VM del MIG y los nodos) | — | `tagUser` en las etiquetas seguras |
| Compute `service-<n>@compute-system` | — | `compute` y `gke` (discos de arranque de los nodos) | |
| Cloud Run `service-<n>@serverless-robot-prod` | `run`, `run_dr` (salida directa a la VPC) | `run` | |
| Cloud SQL `service-<n>@gcp-sa-cloud-sql` | — | `sql` | |
| Cloud Storage `service-<n>@gs-project-accounts` | — | `storage` (también en la multirregión `us`) | |
| Filestore `service-<n>@cloud-filer` | — | `filestore` | |
| Memorystore `service-<n>@cloud-redis` | — | `redis` | |
| Backup for GKE `service-<n>@gcp-sa-gkebackup` | — | `backup` | |

Las llaves salen de `kms_key_ids[environment][ubicación][uso]` en las regiones primaria y de DR
(réplica, plan de Backup for GKE y conmutación con `dr_active`) y, solo para `storage`, también
en `us`. No se otorgan `secrets` (los secretos viven en `security`; su agente es de la etapa 2)
ni `backup` en `us` (ningún consumidor en la etapa 5). Las subredes se otorgan solo si existen
en el estado del spoke (en dev y qa no hay `*_dr`); las proxy-only no se otorgan.

### Pipeline de la etapa 5 (`workloads_service_account`)

La cuenta `<prefix>-tf-5-workloads` crea las cargas en el proyecto de servicio, así que recibe:
`roles/iam.serviceAccountUser` sobre cada cuenta de ejecución (no sobre el proyecto),
`roles/compute.networkUser` sobre las subredes otorgadas (plantillas, nodos, reglas de reenvío
del balanceador interno y Cloud Run con salida a la VPC) y `roles/resourcemanager.tagUser` sobre
los valores de etiqueta `lb_backend` e `iap_ssh`. Llega por variable porque esta etapa no lee
el estado de 0-bootstrap (§6.1).

Etiquetas seguras: quien adjunta una etiqueta necesita `tagUser` sobre el valor. Las pone el
pipeline (en la plantilla del MIG y en los pools de GKE), pero las VM las crea el agente de APIs
de Google (MIG y grupos de nodos) y el agente de GKE las aplica a los nodos; por eso los tres
la reciben. El agente de Compute (`compute-system`) no crea instancias y no la recibe
(VERIFICAR-EN-APPLY).

## Estado remoto que lee

| Prefijo | Salidas |
|---|---|
| `1-org` | `folder_ids` (map(string)) |
| `2-security` | `kms_key_ids` (map(map(map(string)))), `secret_ids` (map(map(string))), `perimeter_name` (string), `vpc_sc_enforced` (bool) |
| `3-networks/<env>` | `host_project_id` (string), `subnets` (map(object)), `secure_tags` (map(string)) |

Cada lectura tiene postcondiciones: carpeta con forma `folders/<n>`, todas las llaves de uso en
la región primaria, los secretos pedidos en `secret_ids[environment]`, subredes `app` y `run`, y
etiquetas `lb_backend` e `iap_ssh` como `tagValues/<id>`.

## Cómo se corre

```sh
cd stages/4-projects/envs/<env>
cp terraform.tfvars.example terraform.tfvars   # y ajustar
terraform init -backend-config="bucket=<state_bucket>"
terraform plan -out=tfplan
terraform apply tfplan
```

Orden: después de `3-networks/<env>` y antes de `5-workloads/<env>`. En prod, al pasar el
perímetro de dry-run a forzado: aplicar 2-security y luego esta etapa.

Prueba sin GCP: `terraform test` (o `bash scripts/check.sh stages/4-projects/envs/<env>`).

## Roles de la cuenta de servicio de la etapa (`<prefix>-tf-4-projects`)

Los otorga la etapa 0 (HYPOTHESIS: la lista debe coincidir con su README):

- En la carpeta del entorno: `roles/resourcemanager.projectCreator`,
  `roles/resourcemanager.projectIamAdmin`, `roles/serviceusage.serviceUsageAdmin`,
  `roles/iam.serviceAccountAdmin`, `roles/resourcemanager.folderViewer`.
- En la cuenta de facturación: `roles/billing.user`.
- Shared VPC: `roles/compute.xpnAdmin` en la carpeta del entorno (unir el proyecto de servicio
  y dar `networkUser` por subred en el host) y `roles/resourcemanager.projectIamAdmin` en el
  host (para `container.hostServiceAgentUser`).
- En el proyecto `security`: `roles/cloudkms.admin` (o un rol propio con
  `cloudkms.cryptoKeys.getIamPolicy`/`setIamPolicy`) y `roles/secretmanager.admin` (o
  `secretmanager.secrets.setIamPolicy`).
- En los valores de etiqueta del spoke: `roles/resourcemanager.tagAdmin` (setIamPolicy).
- Solo prod: `roles/accesscontextmanager.policyEditor` sobre la política de acceso y
  `roles/browser` en el host (leer su número).
- Lectura del estado: `objectAdmin` en `4-projects/<env>` y `objectViewer` en `1-org`,
  `2-security` y `3-networks/<env>` (§6.2).

## VERIFICAR-EN-APPLY

- `generateServiceIdentity` para `sqladmin`, `file`, `redis` y `gkebackup`; agentes de
  `container`, `compute` y `run` presentes tras habilitar la API.
- `tagUser` sobre el valor basta a los agentes de GKE y de APIs para crear nodos y VM con
  etiquetas.
- CMEK del proyecto `security` con el perímetro forzado (§12, punto 4).
- El agente de GKE puede necesitar `roles/compute.securityAdmin` en el host para crear sus
  reglas de firewall; no se otorga (mínimo privilegio): sin él GKE emite eventos con las reglas
  que hay que crear en la etapa 3.

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
| <a name="module_iam"></a> [iam](#module\_iam) | ../../../../modules/iam | n/a |
| <a name="module_project"></a> [project](#module\_project) | ../../../../modules/project-factory | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [google-beta_google_project_service_identity.this](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_project_service_identity) | resource |
| [google_access_context_manager_service_perimeter_dry_run_resource.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/access_context_manager_service_perimeter_dry_run_resource) | resource |
| [google_access_context_manager_service_perimeter_resource.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/access_context_manager_service_perimeter_resource) | resource |
| [google_service_account.runtime](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_tags_tag_value_iam_member.tag_user](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/tags_tag_value_iam_member) | resource |
| [google_folder.env](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/folder) | data source |
| [google_project.host](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/project) | data source |
| [google_storage_project_service_account.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/storage_project_service_account) | data source |
| [terraform_remote_state.network](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |
| [terraform_remote_state.org](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |
| [terraform_remote_state.security](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | Cuenta de facturación de los proyectos de servicio (formato XXXXXX-XXXXXX-XXXXXX). | `string` | n/a | yes |
| <a name="input_dr_region"></a> [dr\_region](#input\_dr\_region) | Región de DR (ADR 0002), distinta de la primaria. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno de esta raíz: dev, qa o prod. Debe coincidir con el prefijo del backend. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes de §4.3. Deben traer owner y cost\_center; env y managed\_by los pone la raíz y app es la llave de cada aplicación. | `map(string)` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | ID numérico de la organización. Se comprueba que la carpeta del entorno (estado de 1-org) pertenezca a ella. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa en los nombres (por ejemplo, bnt). | `string` | n/a | yes |
| <a name="input_primary_region"></a> [primary\_region](#input\_primary\_region) | Región primaria (ADR 0002). Debe ser una ubicación de kms\_key\_ids en el estado de 2-security. | `string` | n/a | yes |
| <a name="input_state_bucket"></a> [state\_bucket](#input\_state\_bucket) | Bucket del estado remoto (salida state\_bucket de 0-bootstrap). Se usa para leer 1-org, 2-security y 3-networks/<environment>. | `string` | n/a | yes |
| <a name="input_workloads_service_account"></a> [workloads\_service\_account](#input\_workloads\_service\_account) | Correo de la cuenta de servicio del pipeline de la etapa 5 (<prefix>-tf-5-workloads, salida stage\_service\_accounts de 0-bootstrap). Recibe el uso de subredes, el uso de etiquetas seguras y actAs sobre las cuentas de ejecución para crear las cargas. Llega por variable porque esta etapa no lee el estado de 0-bootstrap (§6.1). | `string` | n/a | yes |
| <a name="input_applications"></a> [applications](#input\_applications) | Aplicaciones del entorno: un proyecto de servicio por llave (<prefix>-<environment>-<llave>).<br/>- apis: APIs adicionales a las base que la raíz siempre habilita (ver README).<br/>- secrets: nombres cortos de secretos de 2-security (secret\_ids[environment]) que leen las<br/>  cuentas workload y run de la aplicación.<br/>La llave forma también las cuentas de servicio <prefix>-<environment>-<llave>-<uso>, que no<br/>pueden pasar de 30 caracteres (ADR 0017). | <pre>map(object({<br/>    apis    = optional(set(string), [])<br/>    secrets = optional(set(string), [])<br/>  }))</pre> | <pre>{<br/>  "app": {}<br/>}</pre> | no |
| <a name="input_deletion_policy"></a> [deletion\_policy](#input\_deletion\_policy) | deletion\_policy de los proyectos de servicio: PREVENT (falla al destruir), ABANDON o DELETE. En prod solo PREVENT (lo exige project-factory); en dev se puede usar DELETE para el destroy de prueba. | `string` | `"PREVENT"` | no |
| <a name="input_project_suffix"></a> [project\_suffix](#input\_project\_suffix) | Sufijo opcional para que los IDs de proyecto sean únicos a nivel mundial; se agrega al final con un guion. Vacío: sin sufijo. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_service_accounts"></a> [service\_accounts](#output\_service\_accounts) | [aplicación][uso] → correo de la cuenta de servicio de ejecución; usos gke\_nodes, workload, mig y run. |
| <a name="output_service_agents"></a> [service\_agents](#output\_service\_agents) | [aplicación][agente] → miembro de IAM (serviceAccount:<correo>) de los agentes de servicio que recibieron permisos: apis, compute, filestore, gke, gkebackup, redis, run, sql y storage. |
| <a name="output_service_project_ids"></a> [service\_project\_ids](#output\_service\_project\_ids) | Aplicación → ID del proyecto de servicio. |
| <a name="output_service_project_numbers"></a> [service\_project\_numbers](#output\_service\_project\_numbers) | Aplicación → número del proyecto de servicio. |
<!-- END_TF_DOCS -->
