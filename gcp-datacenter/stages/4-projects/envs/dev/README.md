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
  guion bajo del uso pasa a guion: `gke_nodes` → `gke-nodes`). Las llaves de `applications`
  tienen de 2 a 8 minúsculas o dígitos (el mismo conjunto que `application` de 5-workloads),
  así el ID más largo no pasa de 30 caracteres con cualquier prefijo y entorno.
- **Agentes de servicio** que no existen hasta el primer uso, creados con
  `google_project_service_identity` (google-beta): `artifactregistry`, `sqladmin`, `file`,
  `redis`, `gkebackup`. El
  de Cloud Storage lo crea la fuente de datos `google_storage_project_service_account`. Los de
  `container`, `compute` y `run` aparecen al habilitar la API (VERIFICAR-EN-APPLY).
- **Repositorio Docker de Artifact Registry** `<prefix>-<environment>-app-<app>-images-<ubicación>`
  en la multirregión `artifact_registry_location` (por defecto `us`: sobrevive a la pérdida de
  una región), con CMEK (`kms_key_ids[environment][<ubicación>]["artifacts"]`) y etiquetas
  inmutables; `roles/artifactregistry.reader` sobre el repositorio a la cuenta `gke_nodes`, a la
  cuenta `mig` y al agente de Cloud Run (que es quien descarga la imagen).
- **Política de Binary Authorization** del proyecto: `global_policy_evaluation_mode = ENABLE`,
  regla por defecto `ALWAYS_DENY` con `ENFORCED_BLOCK_AND_AUDIT_LOG` y lista de permitidos =
  `<repositorio>/**` más `binary_authorization_allowlist_patterns` (validada: sin `*` solo, sin
  registros enteros, `**` solo después de `/`). Con `binary_authorization_attestors` la regla
  pasa a `REQUIRE_ATTESTATION`. La usan GKE (`PROJECT_SINGLETON_POLICY_ENFORCE`) y Cloud Run
  (`use_default`).
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
| `gke_nodes` | Nodos de GKE | `roles/logging.logWriter`, `roles/monitoring.metricWriter`, `roles/monitoring.viewer`, `roles/stackdriver.resourceMetadata.writer`, `roles/autoscaling.metricsWriter`; `roles/artifactregistry.reader` sobre el repositorio |
| `workload` | Pods (Workload Identity) | `roles/logging.logWriter`, `roles/monitoring.metricWriter`, `roles/cloudtrace.agent`; `roles/secretmanager.secretAccessor` sobre los secretos de la aplicación |
| `mig` | VM del MIG | `roles/logging.logWriter`, `roles/monitoring.metricWriter`; `roles/artifactregistry.reader` sobre el repositorio |
| `run` | Servicio de Cloud Run | `roles/logging.logWriter`, `roles/monitoring.metricWriter`, `roles/cloudtrace.agent`; `roles/secretmanager.secretAccessor` sobre los secretos de la aplicación |

No se dan aquí: Cloud SQL (usuarios IAM y `cloudsql.client`/`instanceUser` de las cuentas con
cómputo encendido, módulo `cloud-sql` en la etapa 5) ni `roles/iam.workloadIdentityUser` de la
cuenta `workload` hacia la cuenta de Kubernetes: el pool `<proyecto>.svc.id.goog` existe solo
cuando la etapa 5 crea el clúster, y la etapa 5 hace ese enlace con el
`roles/iam.serviceAccountAdmin` que recibe aquí sobre la cuenta `workload`.

### Agentes de servicio y permisos

| Agente (`<n>` = número del proyecto) | Subredes del host (`roles/compute.networkUser`) | Llaves KMS (`roles/cloudkms.cryptoKeyEncrypterDecrypter`) | Otros |
|---|---|---|---|
| GKE `service-<n>@container-engine-robot` | `app`, `app_dr` | `gke` | `roles/container.hostServiceAgentUser` en el host; `tagUser` en las etiquetas seguras |
| APIs de Google `<n>@cloudservices.gserviceaccount.com` | `app`, `app_dr` (crea las VM del MIG y los nodos) | — | `tagUser` en las etiquetas seguras |
| Compute `service-<n>@compute-system` | — | `compute` y `gke` (discos de arranque de los nodos) | |
| Cloud Run `service-<n>@serverless-robot-prod` | `run`, `run_dr` (salida directa a la VPC) | `run` | `roles/compute.networkViewer` en el host (salida directa a la VPC en Shared VPC); `artifactregistry.reader` sobre el repositorio |
| Artifact Registry `service-<n>@gcp-sa-artifactregistry` | — | `artifacts` (solo en `artifact_registry_location`) | |
| Cloud SQL `service-<n>@gcp-sa-cloud-sql` | — | `sql` | |
| Cloud Storage `service-<n>@gs-project-accounts` | — | `storage` (también en la multirregión `us`) | |
| Filestore `service-<n>@cloud-filer` | — | `filestore` | |
| Memorystore `service-<n>@cloud-redis` | — | `redis` | |
| Backup for GKE `service-<n>@gcp-sa-gkebackup` | — | `backup` | |

Las llaves salen de `kms_key_ids[environment][ubicación][uso]` en las regiones primaria y de DR
(réplica, plan de Backup for GKE y conmutación con `dr_active`) y, solo para `storage`, también
en `us`; `artifacts` solo en la ubicación del repositorio. No se otorgan `secrets` (los secretos viven en `security`; su agente es de la etapa 2)
ni `backup` en `us` (ningún consumidor en la etapa 5). Las subredes se otorgan solo si existen
en el estado del spoke (en dev y qa no hay `*_dr`); las proxy-only no se otorgan.

### Pipeline de la etapa 5 (`workloads_service_account`)

La cuenta `<prefix>-tf-5-workloads` crea las cargas en el proyecto de servicio. No tiene roles en
la carpeta del entorno (que también contiene el host de la Shared VPC); recibe aquí:

- En cada proyecto de servicio, un rol por tipo de recurso que crea: `backupdr.admin`,
  `certificatemanager.editor`, `cloudsql.admin`, `compute.instanceAdmin.v1`,
  `compute.loadBalancerAdmin`, `compute.securityAdmin` (Cloud Armor), `container.admin`,
  `file.editor`, `gkebackup.admin`, `monitoring.editor`, `redis.admin`, `run.admin`,
  `storage.admin`; y `roles/resourcemanager.projectIamAdmin` con la condición
  `modifiedGrantsByRole` limitada a `roles/cloudsql.client` y `roles/cloudsql.instanceUser`
  (acceso a Cloud SQL por IAM de las cuentas de ejecución).
- `roles/iam.serviceAccountAdmin` solo sobre la cuenta `workload` (enlace de Workload Identity).
- `roles/compute.networkViewer` en el host (Memorystore pide `compute.networks.list` en el host;
  Cloud SQL y Filestore leen la red para la IP privada por PSA). Sin `networkUser` de proyecto.

Además:
`roles/iam.serviceAccountUser` sobre cada cuenta de ejecución (no sobre el proyecto),
`roles/compute.networkUser` sobre las subredes otorgadas (plantillas, nodos, reglas de reenvío
del balanceador interno y Cloud Run con salida a la VPC) y `roles/resourcemanager.tagUser` sobre
los valores de etiqueta `lb_backend` e `iap_ssh`. Llega por variable porque esta etapa no lee
el estado de 0-bootstrap (§6.1): **debe ser igual a `stage_service_accounts["5-workloads"]`** de
las salidas de 0-bootstrap (`terraform output -json stage_service_accounts` en esa raíz). Con
otro correo, la etapa 5 falla por permisos al crear las cargas.

Etiquetas seguras: quien adjunta una etiqueta necesita `tagUser` sobre el valor. Las pone el
pipeline (en la plantilla del MIG y en los pools de GKE), pero las VM las crea el agente de APIs
de Google (MIG y grupos de nodos) y el agente de GKE las aplica a los nodos; por eso los tres
la reciben. El agente de Compute (`compute-system`) no crea instancias y no la recibe
(VERIFICAR-EN-APPLY).

## Estado remoto que lee

| Prefijo | Salidas |
|---|---|
| `1-org` | `folder_ids` (map(string)) |
| `2-security` | `kms_key_ids` (map(map(map(string))); también `[<artifact_registry_location>]["artifacts"]`), `secret_ids` (map(map(string))), `perimeter_name` (string), `vpc_sc_enforced` (bool) |
| `3-networks/<env>` | `host_project_id` (string), `subnets` (map(object)), `secure_tags` (map(string)) |

Cada lectura tiene postcondiciones: carpeta con forma `folders/<n>`, todas las llaves de uso en
la región primaria, la llave `artifacts` en `artifact_registry_location`, los secretos pedidos en `secret_ids[environment]`, subredes `app` y `run`, y
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

| Alcance | Rol | Lo asigna | Para qué |
|---|---|---|---|
| Organización | `roles/resourcemanager.organizationViewer` | 0-bootstrap | leer la organización (`lookup_organization` de la carpeta) |
| Cuenta de facturación | `roles/billing.user` | 0-bootstrap | asociar los proyectos de servicio |
| Proyecto semilla | `roles/serviceusage.serviceUsageConsumer` | 0-bootstrap | proyecto de cuota |
| Bucket de estado | `objectAdmin` en `4-projects/<env>`, `objectViewer` en `1-org`, `2-security` y `3-networks/<env>` (§6.2) | 0-bootstrap | estado |
| Carpetas `dev`, `qa`, `prod` | `roles/resourcemanager.projectCreator` | 1-org | crear los proyectos de servicio (queda como dueña: APIs, cuentas de ejecución, agentes y su IAM dentro de ellos) |
| Carpetas `dev`, `qa`, `prod` | `roles/compute.xpnAdmin` | 1-org | unir el proyecto de servicio al host y dar `networkUser` por subred; leer la carpeta y el host |
| Carpetas `dev`, `qa`, `prod` | `roles/resourcemanager.tagAdmin` | 1-org | dar `tagUser` sobre los valores de `lb_backend` e `iap_ssh` del spoke |
| Carpetas `dev`, `qa`, `prod` | `roles/resourcemanager.projectIamAdmin` con condición (solo `roles/compute.networkUser`, `roles/compute.networkViewer` y `roles/container.hostServiceAgentUser`) | 1-org | dar en el host `hostServiceAgentUser` al agente de GKE y `networkViewer` al agente de Cloud Run y a la etapa 5 |
| Proyecto `security` | rol personalizado `kms_secret_iam_role_id` (0-bootstrap) | 2-security | IAM de las llaves KMS y de los secretos, sin usarlos ni administrarlos |
| Política de acceso (solo prod) | `roles/accesscontextmanager.policyEditor` | 2-security | alta de los proyectos en el perímetro |

`VERIFICAR-EN-APPLY` (HYPOTHESIS sin GCP): que `compute.xpnAdmin` incluya
`resourcemanager.folders.get` y `resourcemanager.projects.get` (fuentes de datos
`google_folder` y `google_project` del host) y que `tagAdmin` en la carpeta se herede a las
llaves de etiqueta cuyo padre es el proyecto `net-spoke`.

## VERIFICAR-EN-APPLY

- `generateServiceIdentity` para `artifactregistry`, `sqladmin`, `file`, `redis` y `gkebackup`; agentes de
  `container`, `compute` y `run` presentes tras habilitar la API.
- `tagUser` sobre el valor basta a los agentes de GKE y de APIs para crear nodos y VM con
  etiquetas.
- CMEK del proyecto `security` con el perímetro forzado (§12, punto 4).
- `networkViewer` en el host más `networkUser` por subred bastan a la etapa 5 para Cloud SQL,
  Memorystore y Filestore con IP privada (PSA); si piden `compute.networks.use`, la alternativa
  documentada es `networkUser` en el host (todas las subredes) y se decide en revisión.
- Repositorio con CMEK en la multirregión y política de Binary Authorization: una imagen del
  repositorio se despliega en Cloud Run y GKE; una de otro registro se rechaza.
- La etapa crea el repositorio, su IAM y la política de Binary Authorization en el proyecto de
  servicio como creadora del proyecto; si no basta, necesita `roles/artifactregistry.admin` y
  `roles/binaryauthorization.policyEditor` en él.
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
| [google_artifact_registry_repository.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository) | resource |
| [google_artifact_registry_repository_iam_member.reader](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_binary_authorization_policy.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/binary_authorization_policy) | resource |
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
| <a name="input_workloads_service_account"></a> [workloads\_service\_account](#input\_workloads\_service\_account) | Correo de la cuenta de servicio del pipeline de la etapa 5 (<prefix>-tf-5-workloads). Debe ser igual a stage\_service\_accounts["5-workloads"] de las salidas de 0-bootstrap. Recibe en cada proyecto de servicio los roles de las cargas que crea, el uso de subredes, networkViewer en el host, el uso de etiquetas seguras, actAs sobre las cuentas de ejecución y serviceAccountAdmin sobre la cuenta workload (Workload Identity). Llega por variable porque esta etapa no lee el estado de 0-bootstrap (§6.1). | `string` | n/a | yes |
| <a name="input_applications"></a> [applications](#input\_applications) | Aplicaciones del entorno: un proyecto de servicio por llave (<prefix>-<environment>-<llave>).<br/>- apis: APIs adicionales a las base que la raíz siempre habilita (ver README).<br/>- secrets: nombres cortos de secretos de 2-security (secret\_ids[environment]) que leen las<br/>  cuentas workload y run de la aplicación.<br/>La llave forma también las cuentas de servicio <prefix>-<environment>-<llave>-<uso>, que no<br/>pueden pasar de 30 caracteres (ADR 0017). | <pre>map(object({<br/>    apis    = optional(set(string), [])<br/>    secrets = optional(set(string), [])<br/>  }))</pre> | <pre>{<br/>  "app": {}<br/>}</pre> | no |
| <a name="input_artifact_registry_location"></a> [artifact\_registry\_location](#input\_artifact\_registry\_location) | Multirregión del repositorio Docker de cada aplicación (us, eu o asia). Debe existir kms\_key\_ids[environment][<ubicación>]["artifacts"] en el estado de 2-security. | `string` | `"us"` | no |
| <a name="input_binary_authorization_allowlist_patterns"></a> [binary\_authorization\_allowlist\_patterns](#input\_binary\_authorization\_allowlist\_patterns) | Patrones de imagen adicionales al repositorio de la aplicación que admite la política de Binary Authorization (registro/ruta, con * o ** solo al final y después de una /). Vacío por defecto: ningún registro público. | `list(string)` | `[]` | no |
| <a name="input_binary_authorization_attestors"></a> [binary\_authorization\_attestors](#input\_binary\_authorization\_attestors) | Atestadores (projects/<p>/attestors/<nombre>) que la política exige a las imágenes fuera de la lista de permitidos. Vacío: la regla por defecto niega todo (ALWAYS\_DENY); con atestadores pasa a REQUIRE\_ATTESTATION. | `list(string)` | `[]` | no |
| <a name="input_deletion_policy"></a> [deletion\_policy](#input\_deletion\_policy) | deletion\_policy de los proyectos de servicio: PREVENT (falla al destruir), ABANDON o DELETE. En prod solo PREVENT (lo exige project-factory); en dev se puede usar DELETE para el destroy de prueba. | `string` | `"PREVENT"` | no |
| <a name="input_project_suffix"></a> [project\_suffix](#input\_project\_suffix) | Sufijo opcional para que los IDs de proyecto sean únicos a nivel mundial; se agrega al final con un guion. Vacío: sin sufijo. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_artifact_registry_repositories"></a> [artifact\_registry\_repositories](#output\_artifact\_registry\_repositories) | Aplicación → URL del repositorio Docker (<ubicación>-docker.pkg.dev/<proyecto>/<repositorio>); es la única fuente de imágenes que admite Binary Authorization además de binary\_authorization\_allowlist\_patterns. |
| <a name="output_service_accounts"></a> [service\_accounts](#output\_service\_accounts) | [aplicación][uso] → correo de la cuenta de servicio de ejecución; usos gke\_nodes, workload, mig y run. |
| <a name="output_service_agents"></a> [service\_agents](#output\_service\_agents) | [aplicación][agente] → miembro de IAM (serviceAccount:<correo>) de los agentes de servicio que recibieron permisos: apis, artifactregistry, compute, filestore, gke, gkebackup, redis, run, sql y storage. |
| <a name="output_service_project_ids"></a> [service\_project\_ids](#output\_service\_project\_ids) | Aplicación → ID del proyecto de servicio. |
| <a name="output_service_project_numbers"></a> [service\_project\_numbers](#output\_service\_project\_numbers) | Aplicación → número del proyecto de servicio. |
<!-- END_TF_DOCS -->
