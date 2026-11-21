# Etapa `2-security`

Llaves, secretos y perímetro de VPC Service Controls (§7.2 del contrato), todo en el proyecto
`security` de `common`. Corre con la cuenta `<prefix>-tf-2-security` y lee solo los estados de
`0-bootstrap` y `1-org` (§6.1).

## Qué crea

| Recurso | Nombre (prefix `bnt`) | Módulo / recurso |
|---|---|---|
| Un llavero por entorno y ubicación (`primary_region`, `dr_region`, multirregión `us`) | `bnt-<env>-sec-keyring-{usc1,use4,us}` | `kms` (una instancia por entorno y ubicación) |
| En las regiones, una llave por uso: `gke`, `compute`, `sql`, `storage`, `filestore`, `redis`, `secrets`, `backup`, `run`, `artifacts` | `bnt-<env>-sec-<uso>` | `kms` |
| En `us`, solo `storage`, `backup` y `artifacts` (repositorios de Artifact Registry de la etapa 4, en la multirregión `us`) | `bnt-<env>-sec-<uso>` | `kms` |
| Agente de Secret Manager del proyecto y su permiso `cryptoKeyEncrypterDecrypter` sobre las llaves `secrets` regionales | `service-<n>@gcp-sa-secretmanager.iam.gserviceaccount.com` | `google_project_service_identity`, `encrypter_decrypters` de `kms` |
| Contenedores de secretos por entorno (sin valores, ADR 0015), replicados en las dos regiones con la llave `secrets` de cada región | `bnt-<env>-sec-<nombre>` | `secrets` |
| Política de Access Context Manager (si `access_policy_id = null`) y perímetro de prod con el proyecto `security` dentro, regla de entrada para las cinco cuentas del pipeline (recurso de regla aparte: el perímetro ignora sus reglas de entrada para no quitar las que agrega la etapa 4), dry-run por defecto (ADR 0009) | `bnt_prod_sec_perimeter` | `vpc-sc` |
| Permiso para la etapa 4 sobre la política de acceso | ver abajo | `google_access_context_manager_access_policy_iam_member` |

Rotación de todas las llaves: `key_rotation_period` (por defecto `7776000s`, 90 días; la
validación rechaza más). Las llaves tienen `prevent_destroy` (módulo `kms`).

El agente de Secret Manager se arma con el número del proyecto `security` leído del estado de
1-org: así el miembro se conoce en el plan (es la llave del `for_each` de
`encrypter_decrypters`). `google_project_service_identity` asegura que el agente exista; el
módulo `kms` depende de él y el módulo `secrets` depende de todo `kms` (permisos incluidos),
porque `key_ids` no depende de las asignaciones de IAM.

### Servicios restringidos (ADR 0019)

`vpc_sc_restricted_services` no incluye por defecto `cloudkms.googleapis.com` ni
`secretmanager.googleapis.com`: el proyecto `security` está dentro del perímetro de prod y
también guarda las llaves y secretos de dev y qa, que están fuera; restringir esas APIs los
bloquearía al forzar el perímetro. Se agregan cuando dev y qa tengan su propio proyecto de
llaves. `storage.googleapis.com` es obligatorio (validación).

## Permisos que esta etapa da a la etapa 4

| Cuenta | Ámbito | Rol | Motivo |
|---|---|---|---|
| `4-projects` | política de acceso | `roles/accesscontextmanager.policyEditor` | agregar los proyectos de prod al perímetro (§7.5) |

El rol personalizado de 4-projects sobre el proyecto `security` (`kms_secret_iam_role_id`,
IAM de llaves y secretos, §7.5) **no** lo da esta etapa sino `1-org`, dueña del proyecto: así
la cuenta de 2-security no tiene `projectIamAdmin` en `security` y no puede darse ese rol ni
`secretAccessor` a sí misma. Esta etapa no asigna nada a nivel de proyecto (el IAM de las
llaves para el agente de Secret Manager es de cada llave y lo cubre `cloudkms.admin`).

**Residual conocido (secretos).** El rol de 4-projects incluye
`secretmanager.secrets.setIamPolicy`, que necesita para dar `secretAccessor` a las cuentas de
ejecución; con él, 4-projects podría darse `secretAccessor` a sí misma sobre cualquier secreto
y leer su valor. No se puede limitar con una condición de concesión delegada: Google solo la
admite en proyectos, carpetas y organizaciones, no en un secreto. El cambio queda en los
registros de actividad administrativa (sink de la organización). Mitigación posible fuera de
este diseño: un proyecto de secretos por entorno o asignar `secretAccessor` desde una etapa
sin acceso al pipeline de PR.

## Roles que necesita la cuenta de la etapa

`<prefix>-tf-2-security`: en la organización `accesscontextmanager.policyAdmin` y
`resourcemanager.organizationViewer` (etapa 0); en el proyecto `security`
`cloudkms.admin`, el rol personalizado `secret_container_admin_role_id` de la etapa 0
(contenedores de secretos sin `secretmanager.versions.access`: la cuenta no lee valores),
y `serviceusage.serviceUsageAdmin`, sin `projectIamAdmin` (etapa 1); en el proyecto semilla
`serviceusage.serviceUsageConsumer`; en el bucket de estado, escritura de `2-security/` y
lectura de `0-bootstrap/` y `1-org/`.

## Estado que lee

| Etapa | Salida | Tipo | Uso |
|---|---|---|---|
| `0-bootstrap` | `seed_project_id` | string | proyecto de cuota de los proveedores |
| `0-bootstrap` | `stage_service_accounts` | map(string) | regla de entrada del perímetro y permiso de 4-projects sobre la política de acceso |
| `1-org` | `common_project_ids["security"]` | string | proyecto de llaves y secretos |
| `1-org` | `common_project_numbers["security"]` | string | recurso del perímetro y agente de Secret Manager |

## Cómo se ejecuta

```bash
cd stages/2-security
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config="bucket=<state_bucket>"
terraform plan
terraform apply
```

Para forzar el perímetro, `vpc_sc_enforced = true` después de revisar las violaciones que
registró el modo dry-run. Si la organización ya tiene política de Access Context Manager, se
pasa su número en `access_policy_id` (solo puede haber una por organización).

## Pendientes del primer apply (VERIFICAR-EN-APPLY)

- Uso de las llaves CMEK del proyecto `security` desde los proyectos de prod con el perímetro
  forzado (pendiente 4).
- Regla de entrada del perímetro para las cuentas del pipeline (pendiente 5, módulo `vpc-sc`).
- Perímetro en dry-run sin bloque `status` y paso a forzado en un solo plan (módulo `vpc-sc`).
- Permiso del agente de Secret Manager sobre las llaves antes de crear los secretos.
- Proyecto de cuota aceptado por las APIs de la etapa.

## Pruebas

`tests/2-security.tftest.hcl`: `mock_provider`, `override_data` de los estados de 0-bootstrap
y 1-org con la forma de §7.0 y §7.1, y `command = plan`. Comprueba la forma de
`kms_key_ids[entorno][ubicación][uso]` (diez usos en las regiones, tres en `us`, con la llave `artifacts`), nombres, el
permiso del agente de Secret Manager, los secretos por entorno, el perímetro en dry-run, los
servicios restringidos del ADR 0019, el permiso de 4-projects sobre la política de acceso (el override de 0-bootstrap no trae
`kms_secret_iam_role_id`: la raíz ya no lo lee) y el perímetro forzado con una
política existente; la regla de entrada de las cinco cuentas, en `spec` (dry-run) y en `status` (forzado); y que una rotación de más de 90 días y secretos de un entorno no pedido se
rechazan.

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
| <a name="module_kms"></a> [kms](#module\_kms) | ../../modules/kms | n/a |
| <a name="module_secrets"></a> [secrets](#module\_secrets) | ../../modules/secrets | n/a |
| <a name="module_vpc_sc"></a> [vpc\_sc](#module\_vpc\_sc) | ../../modules/vpc-sc | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [google-beta_google_project_service_identity.secretmanager](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_project_service_identity) | resource |
| [google_access_context_manager_access_policy_iam_member.projects_stage](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/access_context_manager_access_policy_iam_member) | resource |
| [terraform_remote_state.bootstrap](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |
| [terraform_remote_state.org](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_dr_region"></a> [dr\_region](#input\_dr\_region) | Región de DR (ADR 0002): un llavero por entorno y segunda réplica de los secretos. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes (§4.3). Deben traer app, owner y cost\_center; la raíz agrega env (el entorno de cada llave o secreto) y managed\_by = terraform. | `map(string)` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | ID numérico de la organización de GCP (sin el prefijo organizations/); padre de la política de acceso si la etapa la crea. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa en todos los nombres (§4.2), por ejemplo bnt. El mismo que en las etapas 0 y 1. | `string` | n/a | yes |
| <a name="input_primary_region"></a> [primary\_region](#input\_primary\_region) | Región primaria (ADR 0002): un llavero por entorno y réplica primaria de los secretos. | `string` | n/a | yes |
| <a name="input_state_bucket"></a> [state\_bucket](#input\_state\_bucket) | Bucket de estado (salida state\_bucket de la etapa 0); se usa para leer los estados de 0-bootstrap y 1-org. | `string` | n/a | yes |
| <a name="input_access_policy_id"></a> [access\_policy\_id](#input\_access\_policy\_id) | ID numérico de la política de Access Context Manager si la organización ya tiene una (solo puede haber una). null: la etapa la crea. | `string` | `null` | no |
| <a name="input_environments"></a> [environments](#input\_environments) | Entornos para los que se crean llaveros, llaves y contenedores de secretos. | `list(string)` | <pre>[<br/>  "dev",<br/>  "qa",<br/>  "prod"<br/>]</pre> | no |
| <a name="input_key_rotation_period"></a> [key\_rotation\_period](#input\_key\_rotation\_period) | Periodo de rotación de todas las llaves, en segundos con sufijo s. Por defecto 7776000s (90 días); máximo 90 días. | `string` | `"7776000s"` | no |
| <a name="input_location_short_codes"></a> [location\_short\_codes](#input\_location\_short\_codes) | Mapa ubicación → código corto de los nombres de llaveros (§4.2). Debe incluir primary\_region, dr\_region y us. | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us": "us",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_secret_names"></a> [secret\_names](#input\_secret\_names) | Mapa entorno → nombres cortos de los contenedores de secretos (sin valores, ADR 0015). El ID queda <prefix>-<entorno>-sec-<nombre>. Un entorno sin entrada no tiene secretos. | `map(list(string))` | `{}` | no |
| <a name="input_vpc_sc_enforced"></a> [vpc\_sc\_enforced](#input\_vpc\_sc\_enforced) | true: perímetro de prod forzado. false (por defecto): modo dry-run, solo registra violaciones (ADR 0009). | `bool` | `false` | no |
| <a name="input_vpc_sc_restricted_services"></a> [vpc\_sc\_restricted\_services](#input\_vpc\_sc\_restricted\_services) | Servicios restringidos por el perímetro de prod; debe incluir storage.googleapis.com.<br/>Por defecto NO incluye cloudkms.googleapis.com ni secretmanager.googleapis.com (ADR 0019):<br/>el proyecto security está dentro del perímetro de prod y también guarda las llaves y<br/>secretos de dev y qa; restringir esas APIs bloquearía a dev y qa (fuera del perímetro) al<br/>forzarlo. Se agregan cuando dev y qa tengan su propio proyecto de llaves. | `list(string)` | <pre>[<br/>  "artifactregistry.googleapis.com",<br/>  "backupdr.googleapis.com",<br/>  "bigquery.googleapis.com",<br/>  "compute.googleapis.com",<br/>  "container.googleapis.com",<br/>  "file.googleapis.com",<br/>  "gkebackup.googleapis.com",<br/>  "pubsub.googleapis.com",<br/>  "redis.googleapis.com",<br/>  "run.googleapis.com",<br/>  "sqladmin.googleapis.com",<br/>  "storage.googleapis.com"<br/>]</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_access_policy_id"></a> [access\_policy\_id](#output\_access\_policy\_id) | ID numérico de la política de Access Context Manager (creada o recibida). |
| <a name="output_keyring_ids"></a> [keyring\_ids](#output\_keyring\_ids) | Mapa [entorno][ubicación] → ID del llavero. |
| <a name="output_kms_key_ids"></a> [kms\_key\_ids](#output\_kms\_key\_ids) | Mapa [entorno][ubicación][uso] → ID de la llave KMS. Ubicaciones: primary\_region, dr\_region y us (en us solo storage y backup). |
| <a name="output_perimeter_name"></a> [perimeter\_name](#output\_perimeter\_name) | Nombre completo del perímetro de prod (accessPolicies/<política>/servicePerimeters/<nombre>). |
| <a name="output_secret_ids"></a> [secret\_ids](#output\_secret\_ids) | Mapa [entorno][nombre] → ID del secreto (projects/<proyecto>/secrets/<id>). Un entorno sin secretos tiene un mapa vacío. |
| <a name="output_vpc_sc_enforced"></a> [vpc\_sc\_enforced](#output\_vpc\_sc\_enforced) | true si el perímetro está forzado; false en dry-run. La etapa 4 elige con él el recurso de alta de proyectos. |
<!-- END_TF_DOCS -->
