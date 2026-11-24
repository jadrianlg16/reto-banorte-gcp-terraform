# Etapa `0-bootstrap`

Arranque del proyecto único (ADR 0029 §2). La corre **una sola vez** una persona, a mano; después
todo lo hace el pipeline con las nueve cuentas que crea esta etapa. El proyecto ya existe: lo
crea una persona con la consola o `gcloud`, lo liga a una cuenta de facturación de pago y entra
aquí como `project_id`. Ninguna raíz crea ni borra el proyecto.

## Qué crea

| Archivo | Recursos |
|---|---|
| `main.tf` | Todas las APIs del proyecto (una sola vez, `disable_on_destroy = false`) más `additional_apis`; los agentes de servicio que 1-base necesita (`google_project_service_identity`: Artifact Registry, Filestore, Backup for GKE, Pub/Sub, Memorystore, Secret Manager y Cloud SQL); OS Login en el proyecto; la cuenta de Compute por defecto sin `roles/editor` (`DEPRIVILEGE`); llave KMS y bucket del estado; presupuesto del proyecto |
| `service_accounts.tf` | Las nueve cuentas del pipeline, sus roles de proyecto, su acceso condicionado al bucket de estado y quién toma cada una por WIF |
| `custom_roles.tf` | Cinco roles personalizados del proyecto |
| `wif.tf` | Pool y proveedor de Workload Identity Federation para GitHub Actions |
| `deny_policy.tf` | Etiqueta `<prefix>-proteccion = etapa-0` y política de denegación del proyecto |

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
| `tf-base` | `cloudkms.admin` (salvo el llavero del estado), `TfSecretContainerAdmin`, `artifactregistry.admin`, `binaryauthorization.policyEditor`, `logging.configWriter`, `monitoring.alertPolicyEditor`, `monitoring.notificationChannelEditor`, `essentialcontacts.admin`, `pubsub.admin`, `securitycenter.notificationConfigEditor`, `storage.admin` (buckets `<prefix>-common-`), `projectIamAdmin` (solo los roles de lectura de personas y `tagUser`); con `org_id`, `orgpolicy.policyAdmin` en la organización; con `access_policy_id`, `accesscontextmanager.policyEditor` sobre esa política |
| `tf-net` | `compute.networkAdmin`, `compute.securityAdmin`, `dns.admin` |
| `tf-net-<env>` | los de `tf-net`, más `resourcemanager.tagAdmin` y `servicenetworking.networksAdmin` |
| `tf-wl-<env>` | `backupdr.admin`, `certificatemanager.editor`, `cloudsql.admin`, `compute.instanceAdmin.v1`, `compute.loadBalancerAdmin`, `compute.securityAdmin`, `compute.networkUser`, `container.admin`, `file.editor`, `gkebackup.admin`, `monitoring.editor`, `redis.admin`, `run.admin`, `storage.admin` (buckets `<prefix>-<env>-`), `TfServiceAccountManager`, `iam.serviceAccountUser`, `resourcemanager.tagUser`, `TfKmsSecretIamGranter` (llaveros y secretos `<prefix>-<env>-`), `projectIamAdmin` (solo los roles de las cuentas de ejecución, Cloud SQL por IAM y el apagado); `cloudscheduler.admin` solo en dev y qa (ADR 0028) |
| `tf-read` | `viewer`, `iam.securityReviewer`, `cloudasset.viewer`, `networkmanagement.admin` y `storage.objectViewer` sobre el bucket de estado |

Que cada lista alcance para aplicar su raíz es HYPOTHESIS hasta el primer apply. Ninguna cuenta
tiene `storage.admin` ni `projectIamAdmin` sin condición, ni `iam.serviceAccountAdmin`,
`iam.roleAdmin` o `serviceusage.serviceUsageAdmin` (las APIs y los agentes los crea esta
etapa). Compute, GKE, Cloud Run, Cloud SQL, Memorystore y Filestore van sin condición: una cuenta
de dev puede tocar recursos de prod de esos servicios (riesgo aceptado, ADR 0029 §3 y §9).

`projectIamAdmin` es una concesión delegada:
`api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([...])`. Una llamada que
no cambia bindings (la configuración de auditoría de `1-base`) tiene la lista vacía y pasa (HYPOTHESIS).

### Roles personalizados (`custom_roles.tf`)

| Llave de `custom_role_ids` | Rol | Quién lo usa |
|---|---|---|
| `secret_container_admin` | `<prefix>TfSecretContainerAdmin` | `tf-base`: contenedores de secretos sin leer valores ni cambiar su IAM |
| `kms_secret_iam_granter` | `<prefix>TfKmsSecretIamGranter` | `tf-wl-<env>`, condicionado a su entorno: IAM de llaves y secretos |
| `service_account_manager` | `<prefix>TfServiceAccountManager` | `tf-wl-<env>`: lo de `iam.serviceAccountAdmin` sin `createTagBinding` ni `deleteTagBinding` |
| `repository_iam_granter` | `<prefix>TfRepositoryIamGranter` | `tf-wl-<env>`: IAM de los repositorios de su entorno (lo asigna `1-base` por repositorio) |
| `off_hours_scheduler` | `<prefix>OffHoursScheduler` | cuentas del apagado fuera de horario (ADR 0028); `1-base` lo publica como `off_hours_role_id` |

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
  personalizados, crear llaves de cuentas de servicio y borrar el proyecto.
- Se niega a las nueve cuentas. Nada niega los objetos del estado, el proyecto de cuota ni
  `projects.setIamPolicy` (la concesión delegada lo necesita).

Límites: `iam.serviceAccounts.createTagBinding`/`deleteTagBinding` y
`cloudkms.keyRings.deleteTagBinding` no se pueden negar. Por eso las cuentas de cargas usan
`TfServiceAccountManager` en lugar de `iam.serviceAccountAdmin`, y `tf-base` no tiene `tagUser`.
Si las etiquetas no funcionan en el proyecto (HYPOTHESIS sin organización),
`enable_protection_tags = false` deja solo la regla 2 y la protección queda en los roles
condicionados. `enable_deny_policy = false` quita la política (quien aplica necesita
`roles/iam.denyAdmin`).

## Workload Identity Federation

El proveedor acepta solo tokens con
`assertion.repository_id == "<github_repository_id>" && assertion.repository_owner_id == "<github_repository_owner_id>"`
(`attribute_condition`) y mapea `google.subject`, `attribute.repository_id`,
`attribute.repository_owner_id`, `attribute.repository`, `attribute.ref` y
`attribute.environment`. La confianza se basa en los IDs numéricos porque los nombres se pueden
volver a registrar; los IDs no se reutilizan (`gh api repos/<dueño>/<repositorio> --jq '.id, .owner.id'`).

Dentro del repositorio:

- `tf-base` y `tf-net`: `principalSet://…/attribute.environment/common`;
- `tf-net-<env>` y `tf-wl-<env>`: `principalSet://…/attribute.environment/<env>`;
- `tf-read`: `principalSet://…/attribute.repository_id/<github_repository_id>`.

Un trabajo sin entorno de GitHub solo obtiene `tf-read`. Los pools de WIF se borran de forma
suave durante 30 días: si se destruyen, el mismo ID no se puede reusar hasta que venzan.

## Cómo se ejecuta

Requisitos de quien la corre (con `gcloud auth application-default login`): `roles/owner` en el
proyecto, `roles/iam.denyAdmin` (la política de denegación; `owner` no lo incluye) y
`roles/billing.costsManager` en la cuenta de facturación (presupuesto). Con `org_id`, además
permiso para dar `roles/orgpolicy.policyAdmin` en la organización; con `access_policy_id`,
`roles/accesscontextmanager.policyAdmin`. El proyecto es el proyecto de cuota (`providers.tf`):
antes del primer plan deben estar habilitadas `cloudresourcemanager`, `serviceusage` y `storage`.

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
estado, el `principalSet` de cada cuenta, los cinco roles personalizados, la etiqueta y sus
enlaces y las dos reglas de la denegación; las variantes sin etiquetas, sin denegación y con
organización y política de acceso; y que se rechazan entradas inválidas.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
