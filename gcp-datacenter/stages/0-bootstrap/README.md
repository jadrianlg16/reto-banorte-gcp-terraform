# Etapa `0-bootstrap`

Arranque de la organización (§7.0 del contrato). La corre **una sola vez** una persona
administradora; después todo lo hace el pipeline con las cuentas de servicio que crea esta
etapa.

## Qué crea

| Recurso | Nombre (prefix `bnt`) | Notas |
|---|---|---|
| Carpeta | `bootstrap` | módulo `folders` |
| Proyecto semilla | `bnt-bootstrap-seed[-<sufijo>]` | módulo `project-factory`; APIs de esta etapa y las de nivel organización que las etapas 1 a 5 cobran a este proyecto como proyecto de cuota |
| Registros de auditoría | `allServices` en el proyecto semilla | ADMIN_READ, DATA_READ y DATA_WRITE: toda lectura y escritura del estado queda auditada |
| Llavero y llave KMS | `bnt-bootstrap-sec-keyring-usc1` / `bnt-bootstrap-sec-state` | módulo `kms`; rotación de 90 días, `prevent_destroy` (ADR 0008) |
| Bucket de estado | `bnt-bootstrap-ops-tfstate[-<sufijo>]` | regional en `primary_region`, versionado, acceso uniforme, sin acceso público, CMEK con la llave anterior, `prevent_destroy`; conserva `state_versions_to_keep` versiones viejas |
| Cuentas de servicio | `bnt-tf-1-org` … `bnt-tf-5-workloads` | ADR 0017; en el proyecto semilla |
| Pool y proveedor de WIF | `bnt-bootstrap-sec-wif-pool` / `bnt-bootstrap-sec-github` | §6.3 |
| Rol personalizado | `organizations/<n>/roles/bntTfKmsSecretIamGranter` | ver "Rol personalizado" |
| IAM | módulo `iam` | roles de organización, facturación, semilla, estado y WIF de cada cuenta |

El bucket de estado se construye directamente en la raíz y no con `modules/storage`: ese
módulo solo admite los entornos `dev`, `qa` y `prod` y el dominio `data`, y el bucket de
estado es de `bootstrap` y `ops`.

El permiso del agente de Cloud Storage sobre la llave se da con un
`google_kms_crypto_key_iam_member` en la raíz, no con `encrypter_decrypters` del módulo
`kms`: ese mapa usa el miembro como llave del `for_each`, y el correo del agente lleva el
número del proyecto semilla, que no se conoce en el plan de la primera ejecución.

## Tabla de §6.1 en el código

`local.stages` (en `service_accounts.tf`) codifica una sola vez, por cuenta de etapa, los
prefijos que escribe, los que lee además y sus roles de organización y facturación. De ahí
salen las cuentas, sus roles, las condiciones de IAM del bucket y la salida
`state_iam_conditions`.

| Cuenta | Escribe (objectAdmin) | Lee además (objectViewer) |
|---|---|---|
| `bnt-tf-1-org` | `1-org/` | `0-bootstrap/` |
| `bnt-tf-2-security` | `2-security/` | `0-bootstrap/`, `1-org/` |
| `bnt-tf-3-networks` | `3-networks/hub/`, `3-networks/{dev,qa,prod}/` | `0-bootstrap/`, `1-org/` |
| `bnt-tf-4-projects` | `4-projects/{dev,qa,prod}/` | `1-org/`, `2-security/`, `3-networks/{dev,qa,prod}/` |
| `bnt-tf-5-workloads` | `5-workloads/{dev,qa,prod}/` | `1-org/`, `2-security/`, `3-networks/{dev,qa,prod}/`, `4-projects/{dev,qa,prod}/` |

Cada condición tiene la forma
`resource.type == "storage.googleapis.com/Bucket" || resource.name.startsWith("projects/_/buckets/<bucket>/objects/<prefijo>/") || …`.
La primera cláusula permite `storage.objects.list`, que se evalúa sobre el bucket y no sobre
un objeto (§6.2); consecuencia aceptada: toda cuenta de etapa ve los **nombres** de los
objetos del bucket, no su contenido. La barra final de cada prefijo hace que la coincidencia
sea exacta (`3-networks/hub/` no coincide con un hermano como `3-networks/hub2/`).

`VERIFICAR-EN-APPLY` (pendiente 1): que `init`, `plan` y `apply` del backend `gcs` funcionen
con estas condiciones. Alternativa documentada si fallan: carpetas administradas de Cloud
Storage (*managed folders*) por prefijo, cada una con su propio IAM sin condiciones.

## Roles de las cuentas de etapa

Los roles sobre carpetas y proyectos que todavía no existen cuando corre esta etapa (carpetas
de entorno y proyectos de `common`) los asigna la etapa que los crea (`1-org`, ver su README);
el rol sobre el proyecto `security` para `4-projects` lo asigna `2-security`. Esta etapa
asigna solo lo de nivel organización, facturación y proyecto semilla.

Todas las cuentas reciben además, en el proyecto semilla,
`roles/serviceusage.serviceUsageConsumer` (proyecto de cuota de sus llamadas:
`billing_project` con `user_project_override` en sus proveedores), los dos roles
condicionados sobre el bucket de estado y, en sí mismas, `roles/iam.workloadIdentityUser`
para el repositorio autorizado.

| Cuenta | Ámbito | Rol | Motivo |
|---|---|---|---|
| `1-org` | organización | `roles/resourcemanager.folderAdmin` | crear las carpetas `common`, `dev`, `qa`, `prod`, su IAM y la configuración de auditoría de `prod` |
| `1-org` | organización | `roles/resourcemanager.projectCreator` | crear los proyectos de `common` (queda como dueña de lo que crea) |
| `1-org` | organización | `roles/orgpolicy.policyAdmin` | las nueve políticas de organización |
| `1-org` | organización | `roles/logging.configWriter` | sink agregado de la organización |
| `1-org` | organización | `roles/iam.securityAdmin` | IAM por grupos en la organización (incluye `billing.viewer` de `billing_admins`) |
| `1-org` | organización | `roles/securitycenter.notificationConfigEditor` | notificación de hallazgos de Security Command Center |
| `1-org` | organización | `roles/resourcemanager.organizationViewer` | leer la organización |
| `1-org` | facturación | `roles/billing.user` | asociar los proyectos de `common` a la cuenta |
| `1-org` | facturación | `roles/billing.costsManager` | presupuesto con alertas |
| `2-security` | organización | `roles/accesscontextmanager.policyAdmin` | política de acceso, perímetro de VPC-SC y su IAM |
| `2-security` | organización | `roles/resourcemanager.organizationViewer` | leer la organización |
| `3-networks` | organización | `roles/compute.orgFirewallPolicyAdmin` | política de firewall jerárquica |
| `3-networks` | organización | `roles/compute.orgSecurityResourceAdmin` | asociar la política a la organización |
| `3-networks` | organización | `roles/resourcemanager.organizationViewer` | leer la organización |
| `3-networks` | facturación | `roles/billing.user` | asociar los proyectos `net-spoke` |
| `4-projects` | organización | `roles/resourcemanager.organizationViewer` | leer la organización |
| `4-projects` | facturación | `roles/billing.user` | asociar los proyectos de servicio |
| `5-workloads` | — | — | sin roles de organización ni facturación: solo trabaja dentro de proyectos ya creados |

Ninguna cuenta recibe `roles/owner`, `roles/editor` ni `roles/resourcemanager.organizationAdmin`
(la prueba lo comprueba). `1-org` con `iam.securityAdmin` puede cambiar el IAM de la
organización: es inherente a la etapa que administra ese IAM; la mitiga el filtro de WIF.

### Rol personalizado

`bntTfKmsSecretIamGranter` solo lee llaves, llaveros y secretos y cambia su IAM
(`cloudkms.cryptoKeys.{get,list,getIamPolicy,setIamPolicy}`, `cloudkms.keyRings.{get,list}`,
`secretmanager.secrets.{get,list,getIamPolicy,setIamPolicy}`). Es lo que necesita `4-projects`
para dar a los agentes de servicio permiso sobre las llaves y lectura de secretos (§7.5) sin
poder usar, administrar ni destruir llaves. Lo crea esta etapa porque crear roles de
organización exige `roles/iam.organizationRoleAdmin`, que no tiene ninguna cuenta de etapa; la
etapa `2-security` lo asigna sobre el proyecto `security` (salida `kms_secret_iam_role_id`).
`VERIFICAR-EN-APPLY`: que todos sus permisos estén admitidos en roles personalizados.

## Workload Identity Federation y limitación conocida

El proveedor acepta solo tokens con `assertion.repository == var.github_repository`
(`attribute_condition`) y mapea `google.subject`, `attribute.repository`, `attribute.ref` y
`attribute.environment`. Cada cuenta de etapa da `roles/iam.workloadIdentityUser` al
`principalSet://…/attribute.repository/<repositorio>`.

**Limitación conocida:** la condición y el permiso filtran solo por repositorio. Cualquier
rama o flujo de ese repositorio (incluido un PR desde una rama del mismo repositorio) puede
tomar la identidad de las cuentas de etapa, que pueden aplicar cambios. Limitar los `apply` a
`main` o al entorno protegido de GitHub (por ejemplo, con `attribute.ref` o
`attribute.environment` en el `principalSet`) exige separar cuentas de solo lectura para los
`plan` de los PR. No está construido; queda como mejora.

Los pools de WIF se borran de forma suave durante 30 días: si se destruyen, el mismo ID no
se puede reusar hasta que venzan.

## Cómo se ejecuta

Requisitos de quien la corre (con `gcloud auth application-default login`): en la
organización, `roles/resourcemanager.organizationAdmin` (IAM de organización),
`roles/resourcemanager.folderCreator`, `roles/resourcemanager.projectCreator` e
`roles/iam.organizationRoleAdmin` (rol personalizado); en la cuenta de facturación,
`roles/billing.admin` (asociar el proyecto y dar `billing.user` y `billing.costsManager`).

Primera ejecución (el bucket todavía no existe; §6.1 permite este paso manual):

```bash
cd stages/0-bootstrap
cp terraform.tfvars.example terraform.tfvars          # y ajustar valores reales
cp backend_override.tf.example backend_override.tf    # backend local temporal
terraform init
terraform apply
```

`backend_override.tf` usa el mecanismo de archivos *override* de Terraform: reemplaza el
backend `gcs` de `backend.tf` por uno local sin tocar `backend.tf`, que queda versionado y
es el que valida `scripts/check.sh` (con `-backend=false`). El override y el estado local
están en el `.gitignore` de esta raíz.

Migración al bucket:

```bash
rm backend_override.tf
terraform init -migrate-state -backend-config="bucket=$(terraform output -raw state_bucket)"
rm terraform.tfstate terraform.tfstate.backup          # tras comprobar que el estado migró
```

Después, cualquier cambio a esta etapa lo vuelve a aplicar una persona administradora con
`terraform init -backend-config="bucket=<state_bucket>"` (no hay cuenta de pipeline para la
etapa 0). Las salidas `workload_identity_provider` y `stage_service_accounts` se cargan como
variables del repositorio de GitHub (`GCP_WORKLOAD_IDENTITY_PROVIDER`,
`GCP_STAGE_SERVICE_ACCOUNTS`) y `state_bucket` como `GCP_STATE_BUCKET`.

## Pendientes del primer apply (VERIFICAR-EN-APPLY)

- Listado de objetos del backend con las condiciones de IAM (§6.2).
- Permiso del agente de Cloud Storage sobre la llave antes de crear el bucket (propagación).
- Mapeo de `attribute.environment` en trabajos sin entorno de GitHub.
- Permisos del rol personalizado admitidos en roles personalizados.

## Pruebas

`tests/0-bootstrap.tftest.hcl`: `mock_provider` y `command = plan` con los valores de
`terraform.tfvars.example`. Comprueba nombres, las cinco llaves de `stage_service_accounts`,
las exigencias del bucket, la condición de WIF, las condiciones de estado derivadas de §6.1 y
que no hay roles básicos; y que `prefix` y `github_repository` inválidos se rechazan.

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

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_bootstrap_folder"></a> [bootstrap\_folder](#module\_bootstrap\_folder) | ../../modules/folders | n/a |
| <a name="module_seed_project"></a> [seed\_project](#module\_seed\_project) | ../../modules/project-factory | n/a |
| <a name="module_stage_iam"></a> [stage\_iam](#module\_stage\_iam) | ../../modules/iam | n/a |
| <a name="module_state_kms"></a> [state\_kms](#module\_state\_kms) | ../../modules/kms | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [google_iam_workload_identity_pool.github](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool) | resource |
| [google_iam_workload_identity_pool_provider.github](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool_provider) | resource |
| [google_kms_crypto_key_iam_member.state_storage_agent](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_crypto_key_iam_member) | resource |
| [google_organization_iam_custom_role.kms_secret_iam_granter](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/organization_iam_custom_role) | resource |
| [google_project_iam_audit_config.seed](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_audit_config) | resource |
| [google_service_account.stage](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_storage_bucket.state](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_project_service_account.seed](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/storage_project_service_account) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | Cuenta de facturación del proyecto semilla y de los proyectos que crean las etapas (formato XXXXXX-XXXXXX-XXXXXX). | `string` | n/a | yes |
| <a name="input_github_repository"></a> [github\_repository](#input\_github\_repository) | Repositorio de GitHub (<dueño>/<repositorio>) único autorizado a usar las cuentas de servicio de las etapas por Workload Identity Federation (§6.3). | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes (§4.3). Deben traer app, owner y cost\_center; la raíz agrega env = bootstrap y managed\_by = terraform. | `map(string)` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | ID numérico de la organización de GCP (sin el prefijo organizations/). | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa en todos los nombres (§4.2), por ejemplo bnt. | `string` | n/a | yes |
| <a name="input_primary_region"></a> [primary\_region](#input\_primary\_region) | Región primaria (ADR 0002). Aquí viven el llavero de KMS y el bucket de estado. | `string` | n/a | yes |
| <a name="input_location_short_codes"></a> [location\_short\_codes](#input\_location\_short\_codes) | Mapa ubicación → código corto que se agrega a los nombres de recursos con región (§4.2). Debe incluir primary\_region. | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us": "us",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_project_suffix"></a> [project\_suffix](#input\_project\_suffix) | Sufijo opcional que se agrega al ID del proyecto semilla y al nombre del bucket de estado para que sean únicos a nivel mundial. Vacío: sin sufijo. | `string` | `""` | no |
| <a name="input_state_versions_to_keep"></a> [state\_versions\_to\_keep](#input\_state\_versions\_to\_keep) | Versiones no actuales de cada archivo de estado que se conservan en el bucket; las más viejas se borran. Permiten recuperar un estado dañado. | `number` | `20` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bootstrap_folder_id"></a> [bootstrap\_folder\_id](#output\_bootstrap\_folder\_id) | ID de la carpeta bootstrap ("folders/<número>"). |
| <a name="output_kms_secret_iam_role_id"></a> [kms\_secret\_iam\_role\_id](#output\_kms\_secret\_iam\_role\_id) | Rol personalizado de organización (organizations/<n>/roles/<id>) que la etapa 2 asigna a la cuenta de 4-projects sobre el proyecto security. |
| <a name="output_seed_project_id"></a> [seed\_project\_id](#output\_seed\_project\_id) | ID del proyecto semilla. |
| <a name="output_seed_project_number"></a> [seed\_project\_number](#output\_seed\_project\_number) | Número del proyecto semilla. |
| <a name="output_stage_service_accounts"></a> [stage\_service\_accounts](#output\_stage\_service\_accounts) | Mapa etapa (1-org, 2-security, 3-networks, 4-projects, 5-workloads) → correo de su cuenta de servicio. |
| <a name="output_state_bucket"></a> [state\_bucket](#output\_state\_bucket) | Nombre del bucket de estado; las etapas lo reciben como state\_bucket y en -backend-config. |
| <a name="output_state_iam_conditions"></a> [state\_iam\_conditions](#output\_state\_iam\_conditions) | Mapa etapa → { writes, reads } con los prefijos de estado que cada cuenta escribe y lee (tabla de §6.1), para revisión. |
| <a name="output_state_kms_key_id"></a> [state\_kms\_key\_id](#output\_state\_kms\_key\_id) | ID completo de la llave KMS que cifra el bucket de estado. |
| <a name="output_workload_identity_pool"></a> [workload\_identity\_pool](#output\_workload\_identity\_pool) | Nombre completo del pool de WIF. |
| <a name="output_workload_identity_provider"></a> [workload\_identity\_provider](#output\_workload\_identity\_provider) | Nombre completo del proveedor de WIF (projects/<número>/locations/global/workloadIdentityPools/<pool>/providers/<proveedor>), para google-github-actions/auth. |
<!-- END_TF_DOCS -->
