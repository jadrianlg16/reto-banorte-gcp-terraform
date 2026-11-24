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
atestadores y sin prod; y que se rechazan entradas inválidas (proyecto distinto del de
0-bootstrap, contactos que no cubren las categorías obligatorias, grupo desconocido, publicador
`user:`, política de acceso sin organización y secretos fuera de dev, qa y prod).

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
