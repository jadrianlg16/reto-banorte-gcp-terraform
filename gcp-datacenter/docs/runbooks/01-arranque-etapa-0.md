# Runbook 01: arranque del proyecto y de `0-bootstrap`

## Objetivo

Dejar listo, una sola vez, el proyecto único de la landing zone (ADR
[0029](../adr/0029-un-solo-proyecto.md)): crear el proyecto con facturación de pago, revisar sus
cuotas, borrar la red `default`, habilitar las APIs mínimas, aplicar `stages/0-bootstrap` con
estado local, migrar ese estado al bucket que crea la etapa y sacar las salidas que necesita
GitHub. Incluye los controles del CIS que viven fuera de Terraform.

Nada de esto se ha ejecutado todavía. Es el procedimiento diseñado, pendiente de verificar en el
primer despliegue ([pendientes](../pendientes-apply.md), puntos 1, 2, 9, 13, 22, 23, 27, 31,
32, 33, 56, 125, 126, 127, 128, 137 y 147).

## Cuándo usarlo

- Al empezar, antes de encender el pipeline. La
  [guía del colaborador](../guia-colaborador-gcp.md) dice cuándo y sigue con GitHub y el primer
  despliegue.
- Para volver a aplicar `0-bootstrap` después (por ejemplo, si cambia el repositorio y con él
  `github_repository_id`): ver "Cambios posteriores".

## Prerrequisitos

- **Herramientas:** Terraform 1.16.5 (la del pipeline; mínimo 1.11, porque `terraform init` lee
  `tests/0-bootstrap.tftest.hcl` con `override_during`, ADR 0021), Google Cloud CLI (`gcloud`),
  GitHub CLI (`gh`) con sesión en el repositorio, `jq` y Git. Usa siempre la misma versión de
  Terraform para esta etapa: Terraform no abre un estado escrito por una versión más nueva.
- **Cuenta de facturación de pago.** Según Google, con la prueba gratuita no se pueden pedir
  aumentos de cuota ([funciones de la prueba gratuita](https://docs.cloud.google.com/free/docs/free-cloud-features)).
- **Roles de la persona que aplica** (`stages/0-bootstrap/README.md`, "Cómo se ejecuta"):

  | Rol | Dónde | Para qué |
  |---|---|---|
  | `roles/owner` | el proyecto | todo lo de la etapa |
  | `roles/iam.denyAdmin` | el proyecto | la política de denegación, si `enable_deny_policy = true`; `owner` no lo incluye |
  | `roles/billing.costsManager` | la cuenta de facturación | el presupuesto del proyecto |
  | `roles/orgpolicy.policyAdmin` | la organización | solo con `org_id`: esta etapa crea las políticas de organización del proyecto (pendiente 125) |
  | `roles/accesscontextmanager.policyAdmin` (o `policyEditor` sobre la política) | la organización | solo con `access_policy_id`: esta etapa crea el perímetro de VPC-SC (pendiente 126) |

  Ninguna cuenta del pipeline recibe roles de organización ni de la política de acceso: lo de
  organización solo lo aplica esta persona.

- **Valores que hay que tener a mano:** el ID del proyecto, la cuenta de facturación
  (`XXXXXX-XXXXXX-XXXXXX`), `<prefix>` (2 a 6 minúsculas o dígitos, empieza con letra; ejemplo
  `bnt`), `<dueño>/<repositorio>` y, solo si el proyecto va dentro de una organización, `org_id`,
  `directory_customer_id` y `access_policy_id`.

## Pasos

Las rutas son relativas a `gcp-datacenter/`. `<ID>` es el ID del proyecto y `<correo>`, la cuenta
de la persona que aplica.

1. **Crear el proyecto a mano con facturación de pago.** Ninguna raíz crea ni borra el proyecto
   (ADR 0029 §1).

   ```bash
   gcloud auth login
   gcloud projects create <ID> --name="<nombre>"          # proyecto sin organización
   gcloud billing accounts list
   gcloud billing projects link <ID> --billing-account=<XXXXXX-XXXXXX-XXXXXX>
   gcloud config set project <ID>
   ```

   Con organización, el proyecto se crea dentro de ella (`--organization=<org_id>`) y hay que
   anotar tres valores: `org_id` (`gcloud organizations list`), el ID de cliente de Cloud
   Identity (`directory_customer_id`, `C…`; HYPOTHESIS: la columna `DIRECTORY_CUSTOMER_ID` de la
   misma lista) y,
   si existe, el número de la política de Access Context Manager (`gcloud access-context-manager
   policies list --organization=<org_id>`; solo puede haber una por organización). Con ellos,
   `0-bootstrap` (paso 5) crea las políticas de organización en el proyecto y el perímetro de
   VPC-SC en dry-run. Los aplicas tú, no el pipeline.

   Confirma los roles de la persona (la tabla de prerrequisitos):

   ```bash
   gcloud projects get-iam-policy <ID> --flatten="bindings[].members" \
     --filter="bindings.members:user:<correo>" --format="value(bindings.role)"
   ```

   Si falta `roles/iam.denyAdmin`, quien es `owner` puede darlo en el proyecto:

   ```bash
   gcloud projects add-iam-policy-binding <ID> --member="user:<correo>" --role="roles/iam.denyAdmin"
   ```

   Que ese rol se pueda dar en un proyecto sin organización es HYPOTHESIS. Si no se puede, se
   aplica con `enable_deny_policy = false` (paso 5) y se anota en el punto 32 de los pendientes.

2. **Revisar las cuotas el primer día.** Los tres entornos comparten las cuotas del proyecto y la
   documentación no da sus valores por defecto (ADR 0029 §10). Las de Compute Engine se leen con
   su API habilitada (HYPOTHESIS: que antes no aparezcan):

   ```bash
   gcloud services enable compute.googleapis.com --project=<ID>
   gcloud compute project-info describe --project=<ID> \
     --flatten=quotas --format="table(quotas.metric,quotas.limit,quotas.usage)"
   gcloud compute regions describe us-central1 --project=<ID> \
     --flatten=quotas --format="table(quotas.metric,quotas.limit,quotas.usage)"
   gcloud compute regions describe us-east4 --project=<ID> \
     --flatten=quotas --format="table(quotas.metric,quotas.limit,quotas.usage)"
   ```

   Qué buscar:

   | Cuota | Qué usa el diseño |
   |---|---|
   | `NETWORKS` | cinco VPC: hub, `dev`, `qa`, `prod` y `onprem-sim` (ADR 0029 §6) |
   | Peerings por red | el hub tiene uno por spoke; cada spoke, el del hub y el de Private Service Access |
   | `CPUS` e `IN_USE_ADDRESSES` por región | según el cómputo que se encienda (GKE, MIG, VPN, NAT) |
   | Instancias de Cloud SQL | una por entorno y, en prod con `enable_dr`, su réplica |

   Los límites que no salen en esa lista (por ejemplo, peerings por red) están en la consola, en
   IAM y administración → Cuotas y límites del sistema (HYPOTHESIS de la ruta). Pide los
   aumentos ahí antes de seguir; tardan. Anota lo que encuentres en el punto 9 de los pendientes.

3. **Borrar la red `default`.** El proyecto la trae con reglas de firewall abiertas y el diseño no
   la usa (ADR 0029 §6). Aparece con la API de Compute Engine del paso 2 (HYPOTHESIS). Primero sus
   reglas, después la red:

   ```bash
   gcloud compute networks list --project=<ID>
   gcloud compute firewall-rules list --project=<ID> --filter="network:default" --format="value(name)"
   gcloud compute firewall-rules delete <regla-1> <regla-2> ... --project=<ID>
   gcloud compute networks delete default --project=<ID>
   ```

   Con organización, la política `compute.skipDefaultNetworkCreation` solo sirve para proyectos
   nuevos (ADR 0029 §6): si la red no existe, este paso no hace nada.

4. **Habilitar las APIs mínimas.** `0-bootstrap` habilita todas las APIs del proyecto, pero su
   primer plan necesita estas tres (`stages/0-bootstrap/providers.tf`, `VERIFICAR-EN-APPLY`):

   ```bash
   gcloud services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com \
     storage.googleapis.com --project=<ID>
   gcloud auth application-default login
   ```

   El proyecto es el proyecto de cuota de todas las llamadas (`billing_project` en los
   proveedores). Si una API rechaza la llamada por falta de proyecto de cuota (HYPOTHESIS,
   punto 22): `gcloud auth application-default set-quota-project <ID>` y repetir.

5. **Aplicar `0-bootstrap` con su `terraform.tfvars`.**

   ```bash
   gh api repos/<dueño>/<repositorio> --jq '.id, .owner.id'   # IDs numéricos para WIF
   cd stages/0-bootstrap
   cp terraform.tfvars.example terraform.tfvars
   cp backend_override.tf.example backend_override.tf          # backend local temporal
   git status --short                                          # no debe mostrar ninguno de los dos
   ```

   Variables de `terraform.tfvars`:

   | Variable | Valor |
   |---|---|
   | `project_id`, `billing_account` | los del paso 1 |
   | `org_id`, `directory_customer_id`, `access_policy_id` | solo con organización; si no, comentadas (`null`). `directory_customer_id` y `access_policy_id` exigen `org_id`. Van aquí, no en `GCP_TFVARS_JSON` |
   | `additional_allowed_locations` | solo con `org_id`: ubicaciones extra de `gcp.resourceLocations` además de las dos regiones; por defecto `["us"]` (estado, llaveros y repositorios) |
   | `vpc_sc_restricted_services` | solo con `access_policy_id`: servicios del perímetro; el valor por defecto ya trae los que usa el diseño y debe incluir `storage.googleapis.com` |
   | `onprem_dns_vm` | `false` (por defecto). `true` solo para la VM DNS de prueba de `onprem-sim`, junto con `simulate_onprem = true` y `onprem_dns_vm = true` en `2-networks`: le da a `tf-net` `compute.instanceAdmin.v1` (pendiente 128) |
   | `prefix`, `name_suffix` | `name_suffix` hace único el nombre del bucket (los nombres de bucket son globales) |
   | `primary_region`, `dr_region` | `us-central1` y `us-east4` |
   | `github_repository`, `github_repository_id`, `github_repository_owner_id` | el nombre es informativo; WIF confía en los dos números (entre comillas) |
   | `state_bucket_location`, `state_bucket_dual_regions` | `US` por defecto. **No se cambia después del primer apply** (ADR 0022) |
   | `budget_amount` | monto mensual del presupuesto |
   | `enable_protection_tags` | `true`. `false` solo si un apply demuestra que las etiquetas no funcionan en el proyecto: quita la regla con etiqueta y deja las otras tres de la denegación (sin condición, valores de secretos y llaves para todos) |
   | `enable_deny_policy` | `true`. Exige `roles/iam.denyAdmin`. `false` quita la política de denegación entera, también la regla que niega a todos crear llaves de cuentas de servicio |
   | `labels` | `app`, `owner` y `cost_center` en minúsculas |

   Un error en los IDs de WIF no se nota en el plan: aparece cuando el primer flujo de GitHub no
   consigue token.

   ```bash
   terraform init
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

   Revisa en el plan, con `prefix = "bnt"` como ejemplo:

   - las APIs del proyecto con `disable_on_destroy = false`, los agentes de servicio, el
     metadato de OS Login y `google_project_default_service_accounts` con `DEPRIVILEGE`;
   - el llavero `bnt-bootstrap-sec-keyring-us` con la llave `bnt-bootstrap-sec-state`, y el
     bucket `bnt-bootstrap-ops-tfstate[-<name_suffix>]` en `US`;
   - nueve cuentas (`bnt-tf-base`, `bnt-tf-net`, `bnt-tf-net-{dev,qa,prod}`,
     `bnt-tf-wl-{dev,qa,prod}`, `bnt-tf-read`) y ningún `roles/owner`, `roles/editor` ni
     `iam.serviceAccountAdmin`; `bnt-tf-wl-*` sin `iam.serviceAccountUser` de proyecto ni
     `tagUser`, y `bnt-tf-net` con `compute.instanceAdmin.v1` solo si `onprem_dns_vm = true`;
   - cuatro roles personalizados (`TfSecretContainerAdmin`, `TfServiceAccountManager`,
     `TfNetworkTagManager` y `OffHoursScheduler`, con el prefijo), el pool
     `bnt-bootstrap-sec-wif-pool` y el proveedor con `attribute_condition` sobre
     `assertion.repository_id` y `assertion.repository_owner_id` y el atributo
     `attribute.deploy` (las cuentas que escriben solo desde el trabajo `apply` de
     `_terraform-root.yml` en `main`, con `push` o `workflow_dispatch`; `pipeline.md` §5,
     pendientes 123, 124 y 156);
   - `roles/resourcemanager.tagUser` en el proyecto para el agente de GKE y para
     `<número>@cloudservices.gserviceaccount.com` (pendiente 137);
   - la etiqueta `bnt-proteccion = etapa-0` con sus enlaces y la política
     `bnt-bootstrap-sec-deny-pipeline` (según las dos banderas; la regla sin etiqueta también
     niega a las nueve cuentas pedir tokens o firmar como otra cuenta y cambiar los servicios
     habilitados, pendientes 127 y 154, y la regla 4 niega a todos, también a ti, crear llaves
     de cuentas de servicio, pendiente 155), y el presupuesto `bnt-bootstrap-ops-budget`;
   - solo con organización: `google_org_policy_policy` con padre `projects/<ID>` (al final, después
     de las cuentas, sus roles y el bucket) y, con `access_policy_id`, el perímetro
     `bnt_common_sec_perimeter` en dry-run alrededor del proyecto.

   Si la creación del bucket falla por permisos sobre la llave, repite `terraform plan` y
   `terraform apply`: el permiso del agente de Cloud Storage puede tardar en propagarse
   (punto 27).

6. **Migrar el estado al bucket.** Toma el nombre del bucket **antes** de borrar el override:
   después, `terraform output` falla con `Backend initialization required` (punto 21).

   ```bash
   STATE_BUCKET="$(terraform output -raw state_bucket)"
   echo "${STATE_BUCKET}"
   rm backend_override.tf
   terraform init -migrate-state -backend-config="bucket=${STATE_BUCKET}"
   # Terraform pregunta si copia el estado existente al backend nuevo: responder "yes".
   terraform state list | head
   gcloud storage ls "gs://${STATE_BUCKET}/0-bootstrap/"
   terraform plan -detailed-exitcode       # 0: sin cambios
   rm terraform.tfstate terraform.tfstate.backup tfplan
   ```

   El estado local no tiene secretos, pero describe toda la etapa: no se copia a otro lado.

7. **Sacar las salidas para GitHub.** Cada una va a una variable de **repositorio** (nunca de
   entorno). Cómo cargarlas está en la [guía del colaborador](../guia-colaborador-gcp.md),
   sección D.

   ```bash
   terraform output -raw project_id
   terraform output -raw state_bucket
   terraform output -raw workload_identity_provider
   terraform output -raw read_service_account
   terraform output -json stage_service_accounts
   ```

   | Salida | Variable de GitHub |
   |---|---|
   | `workload_identity_provider` | `GCP_WORKLOAD_IDENTITY_PROVIDER` |
   | `read_service_account` | `GCP_AUDIT_SERVICE_ACCOUNT` |
   | `stage_service_accounts` | `GCP_STAGE_SERVICE_ACCOUNTS` |
   | `state_bucket` | `GCP_STATE_BUCKET` y `common.state_bucket` de `GCP_TFVARS_JSON` |
   | `project_id` | `common.project_id` de `GCP_TFVARS_JSON` (obligatorio) |

   Antes eran pasos a mano: la cuenta de lectura ya la crea `0-bootstrap` (`tf-read`), con sus
   roles y su acceso por WIF.

8. **Activar Security Command Center en el proyecto** (paso manual; puntos 2 y 23). En la
   consola, con el proyecto seleccionado: Seguridad → Security Command Center → activar
   (Standard o Premium, según decida el equipo). La activación a nivel proyecto existe según la
   [documentación de activación](https://docs.cloud.google.com/security-command-center/docs/activate-scc-overview);
   que funcione en un proyecto sin organización es HYPOTHESIS (ADR 0029 §7). Hazlo antes de
   poner `enable_scc_notification = true` en `1-base`; con el valor por defecto (`false`),
   `1-base` no lo necesita.

## Controles manuales del CIS

Controles del CIS GCP Foundation Benchmark v5.0 que Terraform no puede fijar
([`cumplimiento-cis.md`](../cumplimiento-cis.md), estado **Manual**). Se separan en dos grupos.
Las letras se conservan porque el mapa CIS las cita.

**Evidencia:** captura de cada configuración y salida de cada comando, con fecha y quién lo hizo,
en el expediente de cumplimiento del equipo, **fuera del repositorio** (las capturas muestran
correos e IDs); la revisión del punto 56 la pide. Nada de esto se ha hecho todavía. Las rutas de
menú son las de las páginas de Google citadas, leídas el 23 nov 2026, y pueden cambiar.

### Grupo 1: valen en un proyecto suelto

**D. Access Transparency (CIS 2.15).**

- Fuente: [Enabling Access Transparency](https://docs.cloud.google.com/assured-workloads/access-transparency/docs/enable)
  (Google). La página describe una organización. Que se pueda comprobar o activar en un proyecto
  sin organización es HYPOTHESIS.
- Pasos: con el proyecto seleccionado, IAM y administración → Configuración: confirmar que
  Access Transparency está activo; o Seguridad → Access Approval, pestaña Home (rol
  `roles/accessapproval.viewer` o `roles/axt.admin`).
- Evidencia: captura de cualquiera de las dos pantallas. Detector:
  `ACCESS_TRANSPARENCY_DISABLED` (Premium).

**E. Access Approval (CIS 2.16).**

- Fuentes: [Overview of Access Approval](https://docs.cloud.google.com/assured-workloads/access-approval/docs/overview)
  y [aprobación con la llave de firma de Google](https://docs.cloud.google.com/assured-workloads/access-approval/docs/review-approve-access-requests-google-keys)
  (Google). La guía de Google lo da para un proyecto. Requisito: D.
- Pasos: con el proyecto seleccionado, abrir Access Approval
  (`console.cloud.google.com/security/access-approval`) → **Enroll**, modo **Access Approval**,
  servicios: todos los admitidos (valor por defecto); luego **Manage settings** → "Set up approval
  notifications" → el correo de seguridad del equipo. Llave de firma: la de Google. Rol:
  `roles/accessapproval.configEditor` en el proyecto.
- Antes de inscribirse, revisar en la página de precios si tiene costo o pide un plan de soporte
  (HYPOTHESIS: la página de requisitos no lo dice). No va en Terraform, para no dar a `tf-base`
  otro rol de administración (CIS 1.6, ADR 0027).
- Evidencia: captura de la configuración y la salida de
  `gcloud access-approval settings get --project=<ID>` (HYPOTHESIS de la sintaxis).

### Grupo 2: solo con organización (Cloud Identity)

Sin organización no hay consola de administración de Cloud Identity: estos controles **no
aplican** y el mapa CIS los marca así. Lo más cercano, como recomendación del equipo y no como
cumplimiento del control, es que cada persona con acceso al proyecto active la verificación en
dos pasos en su cuenta de Google.

**A. Superadministrador (CIS 1.1.1 y 1.1.2).**

- Fuente: [buenas prácticas de cuentas de superadministrador](https://docs.cloud.google.com/resource-manager/docs/super-admin-best-practices)
  (Google): cuenta aparte, fuera del trabajo diario y del grupo de administradores de la
  organización, con llave de seguridad. El CIS pide además una dirección de rol (por ejemplo
  `gcp-superadmin@<dominio>`).
- Pasos: en la consola de administración, dos cuentas de superadministrador con dirección de rol
  (principal y respaldo), con sus llaves de seguridad guardadas en un lugar físico seguro; quitar
  el rol a las cuentas personales. Quien aplica `0-bootstrap` usa su cuenta normal.
- Evidencia: captura de la lista de administradores con el rol Super Admin (HYPOTHESIS de la ruta:
  Menu → Account → Admin roles → Super Admin → Admins) y la salida de

  ```bash
  gcloud organizations get-iam-policy <org_id> --flatten="bindings[].members" \
    --filter="bindings.members:user:<correo-superadministrador>" --format="value(bindings.role)"
  ```

  que debe salir vacía.

**B. 2SV obligatoria y llaves de seguridad para administradores (CIS 1.3 y 1.4).**

- Fuente: [Deploy 2-Step Verification](https://knowledge.workspace.google.com/admin/security/deploy-2-step-verification)
  (Google). Hace falta ser superadministrador.
- Pasos: Menu → Security → Authentication → 2-step verification. En la unidad organizativa raíz:
  "Allow users to turn on 2-Step Verification" y Enforcement en **On**. En la unidad
  organizativa (o grupo de configuración, HYPOTHESIS) de las cuentas administradoras: Methods en
  **Only security key**, después de comprobar que todas tienen una.
- Evidencia: captura de las dos configuraciones y del informe de inscripción en 2SV. Detector:
  `MFA_NOT_ENFORCED`.

**C. Datos de Cloud Identity compartidos con Google Cloud (CIS 2.2).**

- Fuente: [Share data with Google Cloud services](https://knowledge.workspace.google.com/admin/getting-started/share-data-with-google-cloud-services)
  (Google). Hace falta ser superadministrador.
- Pasos: Menu → Account → Account settings → Legal and compliance → Sharing options →
  **Enabled** → Save.
- Evidencia: captura de la opción y, unas horas después, eventos de la consola de administración
  en los registros de la organización (HYPOTHESIS del filtro):

  ```bash
  gcloud logging read 'protoPayload.serviceName="admin.googleapis.com"' \
    --organization=<org_id> --limit=5 --freshness=1d
  ```

## Verificación

- `terraform plan -detailed-exitcode` en `stages/0-bootstrap` sale con 0 desde el bucket.
- El bucket tiene CMEK, versionado, acceso uniforme y prevención de acceso público:

  ```bash
  gcloud storage buckets describe "gs://${STATE_BUCKET}" \
    --format="yaml(default_kms_key,versioning_enabled,uniform_bucket_level_access,public_access_prevention)"
  ```

- La llave rota cada 90 días (`us` es la ubicación por defecto; con otro
  `state_bucket_location`, su código en minúsculas):

  ```bash
  gcloud kms keys describe <prefix>-bootstrap-sec-state --keyring=<prefix>-bootstrap-sec-keyring-us \
    --location=us --project=<ID> --format="value(rotationPeriod,nextRotationTime)"
  ```

- La política de denegación está en el proyecto (sintaxis por verificar en el primer uso,
  punto 32):

  ```bash
  gcloud iam policies list \
    --attachment-point="cloudresourcemanager.googleapis.com/projects/<ID>" --kind=denypolicies
  ```

  Debe listar `<prefix>-bootstrap-sec-deny-pipeline`.

- La red `default` ya no aparece en `gcloud compute networks list --project=<ID>`.
- El primer trabajo `1-base` de `apply.yml` autentica por WIF e inicializa el backend: es la
  primera prueba real del punto 1 (IAM condicionado por prefijo).

## Reversión

**No se borra el proyecto.** Lo creó una persona y ninguna raíz lo administra. Se retira recurso
por recurso, como dice el ADR 0029 §8:

- **Antes de migrar (paso 6):** corregir y repetir `terraform apply`; el estado sigue local.
- **Volver el estado a local:** `cp backend_override.tf.example backend_override.tf` y
  `terraform init -migrate-state`.
- **Apagar el pipeline:** `gh variable set GCP_ENABLED --body "false"`: los trabajos de GCP se
  omiten. Para dejar fuera solo dev o qa, `GCP_DISABLED_ENVS` (`pipeline.md` §1.2).
- **Entornos dev y qa:** `destroy.yml` (cargas y, con `incluir_red = true`, el spoke). Queda a
  propósito lo que vive en `1-base`: llaves, repositorios y contenedores de secretos. prod, el
  hub y `1-base` no tienen flujo de destroy (guía del colaborador, sección I).
- **`0-bootstrap` no se destruye completa.** Borraría las cuentas y el WIF de todo el pipeline.
  Además, la llave y el bucket del estado tienen `prevent_destroy`, los llaveros no se pueden
  borrar en GCP, un pool de WIF borrado reserva su ID 30 días y los nombres de roles
  personalizados no se reutilizan de inmediato. Para retirar una pieza: PR que la quite del
  código (y su `prevent_destroy`, si lo tiene, revisado por seguridad) y apply de la persona
  dueña. Las APIs se quedan habilitadas (`disable_on_destroy = false`).

## Cambios posteriores

No hay cuenta de pipeline para `0-bootstrap`. Cualquier cambio lo aplica la persona dueña con el
backend ya migrado:

```bash
cd stages/0-bootstrap
terraform init -backend-config="bucket=<state_bucket>"
terraform plan -out=tfplan
terraform apply tfplan
```

Si cambia `stage_service_accounts`, `read_service_account` o `workload_identity_provider`,
actualiza la variable de GitHub que le corresponde (paso 7).

Casos que piden volver a aplicar esta etapa:

- **VM DNS de `onprem-sim`:** `onprem_dns_vm = true` aquí primero (rol de VM del hub); después
  `onprem_dns_vm = true` en la llave `stages/2-networks` de `GCP_TFVARS_JSON` y `apply.yml`, que
  aplica `1-base` (cuenta `<prefix>-common-net-dns`) antes que el hub (la VM). Para quitarla, al
  revés: primero `false` en el hub y `apply.yml` (borra la VM con el rol todavía puesto), después
  `false` aquí; el siguiente `apply.yml` quita la cuenta en `1-base`.
- **Organización nueva o política de acceso nueva:** `org_id`, `directory_customer_id` o
  `access_policy_id` aquí, con los roles de organización de los prerrequisitos.
- **Repositorio renombrado:** `github_repository` aquí. Hasta volver a aplicar, ninguna cuenta que
  escribe obtiene token (`attribute.deploy` queda en `none`; `pipeline.md` §5).

El arranque anterior, con organización, carpetas y proyecto semilla, está en la rama
`archivo/multiproyecto`.
