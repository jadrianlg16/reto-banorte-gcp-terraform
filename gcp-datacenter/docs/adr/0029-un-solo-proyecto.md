# ADR 0029: Toda la landing zone en un solo proyecto de GCP

## Estado

Aceptado, 2026-11-24. Reemplaza al diseño de varios proyectos, que queda en la rama
`archivo/multiproyecto` (commit `d22d164`).

Tipo: Desviación del diseño anterior por pedido del cliente. En la junta del 23 nov 2026,
Banorte pidió que todo vaya dentro de un solo proyecto.

Esta decisión manda sobre §2, §3, §6 y §7 del [contrato](../CONTRATO.md) y sobre los ADR que
suponen varios proyectos o carpetas (lista al final). Las convenciones de nombres, etiquetas,
variables, módulos, pruebas y políticas (§1, §4, §5, §8 y §9 del contrato) siguen vigentes salvo
donde este ADR diga otra cosa.

## Contexto

- Un solo proyecto de GCP, creado por una persona. No se sabe si estará dentro de una
  organización. El diseño debe funcionar sin organización y aprovecharla si existe.
- Se mantienen dev, qa y prod.
- Shared VPC necesita organización y proyectos distintos para el host y el servicio
  ([Shared VPC](https://docs.cloud.google.com/vpc/docs/shared-vpc)). La política de firewall
  jerárquica se asocia a una organización o a carpetas
  ([firewall policies](https://docs.cloud.google.com/firewall/docs/firewall-policies-overview)).
  En un proyecto suelto no hay ninguna de las dos.
- El peering entre VPC del mismo proyecto sí existe
  ([VPC peering](https://docs.cloud.google.com/vpc/docs/vpc-peering)), y cada VPC puede tener
  su propia conexión de Private Service Access
  ([PSA](https://docs.cloud.google.com/vpc/docs/configure-private-services-access)).
- La revisión independiente del plan (Fable 5.2, 24 nov 2026) encontró lo difícil del cambio: no
  es mover recursos, sino la identidad del pipeline y el ciclo de destroy sin borrar proyectos.

## Decisión

### 1. Proyecto y organización

- El proyecto lo crea una persona (consola o `gcloud`) y lo liga a una cuenta de facturación de
  pago. Entra a Terraform como `project_id`. Ninguna raíz crea ni borra el proyecto.
- `org_id` es opcional (`null` por defecto). Con organización se activan dos cosas en `1-base`:
  - las políticas de organización aplicadas al proyecto (`google_org_policy_policy` con padre
    `projects/<id>`);
  - el perímetro de VPC-SC opcional, si además llega `access_policy_id`. Rodea todo el proyecto
    y queda en dry-run; no separa entornos.
- Sin organización, esos controles no existen. Lo cubren las reglas de Conftest en cada PR y los
  pasos manuales del runbook 01. Que las políticas de organización y VPC-SC no se puedan usar sin
  organización es HYPOTHESIS: las páginas oficiales no lo dicen explícitamente.

### 2. Etapas, raíces y estado

Cuatro etapas en lugar de seis. Un bucket de estado con un prefijo por raíz (ADR 0010 sigue
vigente).

| Raíz | Prefijo | Cuenta que aplica | Entorno de GitHub | Lee |
|---|---|---|---|---|
| `stages/0-bootstrap` | `0-bootstrap` | una persona, a mano | — | — |
| `stages/1-base` | `1-base` | `<prefix>-tf-base` | `common` | `0-bootstrap` |
| `stages/2-networks` (hub) | `2-networks/hub` | `<prefix>-tf-net` | `common` | `1-base` |
| `stages/2-networks/envs/<env>` | `2-networks/<env>` | `<prefix>-tf-net-<env>` | `<env>` | `1-base`, `2-networks/hub` |
| `stages/3-workloads/envs/<env>` | `3-workloads/<env>` | `<prefix>-tf-wl-<env>` | `<env>` | `1-base`, `2-networks/<env>` |

Orden de `apply.yml`: `1-base` → hub → spoke dev → cargas dev → prueba de humo de dev → spoke
qa → cargas qa → spoke prod → cargas prod.

| Etapa nueva | Viene de | Qué contiene |
|---|---|---|
| `0-bootstrap` | etapa 0 y parte de la 1 | APIs del proyecto (todas, una sola vez, `disable_on_destroy = false`), llave y bucket del estado, las nueve cuentas del pipeline (§3) con sus roles de proyecto, WIF, roles personalizados de proyecto, etiqueta de protección y política de denegación (§5), presupuesto del proyecto |
| `1-base` | etapas 1 y 2, y lo único por proyecto de la 4 | Ver §4 |
| `2-networks` | etapa 3 | Hub, `onprem-sim`, VPN, DNS y políticas de firewall de red; un spoke por entorno sin Shared VPC |
| `3-workloads` | etapas 4 y 5 | Cuentas de ejecución, permisos sobre recursos del propio entorno y todas las cargas |

### 3. Identidad del pipeline

Nueve cuentas, todas creadas por `0-bootstrap`:

- `tf-base`: aplica `1-base`.
- `tf-net`: aplica el hub.
- `tf-net-dev`, `tf-net-qa` y `tf-net-prod`: aplican el spoke de su entorno.
- `tf-wl-dev`, `tf-wl-qa` y `tf-wl-prod`: aplican las cargas de su entorno.
- `tf-read`: solo lectura. La usan los `plan` de `pr.yml` y `apply.yml`, `drift.yml`, la prueba
  de humo y la búsqueda de huérfanos. Reemplaza a la cuenta de auditoría manual: la variable
  `GCP_AUDIT_SERVICE_ACCOUNT` toma la salida `read_service_account`.

WIF, con el mismo proveedor y la misma `attribute_condition` por ID numérico (ADR 0023):

- `tf-base` y `tf-net` solo aceptan tokens con `attribute.environment/common`.
- Cada `tf-*-<env>` solo acepta tokens con `attribute.environment/<env>`.
- `tf-read` acepta tokens de cualquier trabajo del repositorio.

Un trabajo sin entorno de GitHub solo obtiene la cuenta de lectura.

- Los `plan` corren con `tf-read` y `-lock=false`: la cuenta no puede escribir el candado del
  estado. El apply toma el candado con la cuenta del entorno.
- Roles de `tf-read`: `roles/viewer`, `roles/iam.securityReviewer`,
  `roles/cloudasset.viewer` y `roles/networkmanagement.admin` (para las Connectivity Tests de la
  prueba de humo), más `storage.objectViewer` sobre el bucket de estado. Que `viewer` alcance
  para refrescar todos los recursos es HYPOTHESIS; se marca `VERIFICAR-EN-APPLY`.

Roles de las cuentas que escriben:

- Se dan **en el proyecto** y desde `0-bootstrap`: un rol de proyecto para un principal
  compartido nunca se declara en una raíz de entorno (§4).
- Ninguna cuenta recibe `roles/storage.admin` sin condición. Las de entorno lo reciben
  condicionado a `resource.name.startsWith("projects/_/buckets/<prefix>-<env>-")`
  ([condiciones](https://docs.cloud.google.com/iam/docs/conditions-resource-attributes)).
- KMS y Secret Manager admiten condiciones por nombre. El rol que da IAM sobre llaves y
  secretos (antes `TfKmsSecretIamGranter`) va condicionado al llavero y a los secretos del
  entorno (`<prefix>-<env>-`). El formato exacto del nombre en la condición es HYPOTHESIS.
- Compute, GKE, Cloud Run, Cloud SQL, Memorystore y Filestore se dan **sin condición**. Una
  condición por nombre sobre un tipo que no la admite niega todo, y esto no se puede probar sin
  GCP. Una cuenta de dev puede, técnicamente, cambiar recursos de prod de esos servicios
  (riesgo aceptado, §Consecuencias). Lo frena que solo un trabajo del entorno `dev` obtiene esa
  cuenta y que todo cambio pasa por PR con plan revisado.

### 4. Regla de recursos únicos y principales compartidos

Una raíz de entorno (`2-networks/envs/<env>`, `3-workloads/envs/<env>`) **no puede** declarar:

1. Nada que exista una vez por proyecto:
   - APIs (`google_project_service`) y metadatos del proyecto (OS Login);
   - configuración de auditoría (`google_project_iam_audit_config`);
   - la política de Binary Authorization, contactos esenciales, sinks y buckets de logs, el
     presupuesto y la notificación de SCC;
   - roles personalizados y políticas de organización.
2. Permisos de proyecto (`google_project_iam_member`) para un principal que no creó ella misma:
   cuentas del pipeline, grupos, agentes de servicio y la cuenta de Compute por defecto.
3. Recursos con nombre que no lleve `<prefix>-<env>-` (o `<env>` dentro de los nombres cortos
   que limita GCP, ADR 0017).

Por eso pasan a `1-base`:

- **Auditoría y avisos:** configuración de auditoría del proyecto (§7), sink y bucket de logs con
  su llave, `audit-alerts` una sola vez, contactos esenciales y la notificación de SCC
  (opcional).
- **Llaves y secretos:** llaveros y llaves KMS por entorno (`<prefix>-<env>-…`) y la llave de logs;
  contenedores de secretos por entorno; permisos de los agentes de servicio sobre las llaves.
  El agente de cada servicio es uno por proyecto y queda con las llaves de los tres entornos
  (riesgo aceptado).
- **Imágenes:** repositorios de Artifact Registry por entorno y aplicación (`<prefix>-<env>-<app>`,
  multirregión) y la única política de Binary Authorization. Su regla por defecto admite los
  repositorios del proyecto. Cada clúster de GKE de prod tiene una regla propia que solo admite
  el repositorio de prod. Los nombres de los clústeres se fijan por convención:
  `<prefix>-<env>-<app>-gke[-dr]`. Cloud Run usa la regla por defecto (riesgo aceptado).
- **Apagado fuera de horario:** el rol personalizado `<prefix>OffHoursScheduler` (una vez).
- **Cuenta de Compute por defecto:** `google_project_default_service_accounts` con
  `action = "DEPRIVILEGE"`, para quitarle el rol Editor que el proyecto le da al crearse.
  Ninguna carga la usa.
- **Si hay organización:** políticas de organización en el proyecto y VPC-SC opcional (§1).
- **IAM de personas:** grupos o usuarios de solo lectura (`roles/viewer`, `roles/logging.viewer`
  y los de auditoría).

Las raíces de entorno sí crean sus cuentas de ejecución (`<prefix>-<env>-<app>-<uso>`) y las del
apagado (`<prefix>-<env>-<app>-sched`). También les dan permisos de proyecto, porque esos
principales son del entorno, y crean sus permisos sobre recursos propios del entorno.

### 5. Protección del estado y de la etapa 0

La política de denegación ya no puede ir en una carpeta. Va en el proyecto y usa una
**etiqueta**, porque las condiciones de denegación solo reconocen funciones de etiquetas
([deny](https://docs.cloud.google.com/iam/docs/deny-overview)).

- `0-bootstrap` crea la clave de etiqueta `<prefix>-proteccion`, con valor `etapa-0`, y la liga
  al bucket de estado.
- Niega a las nueve cuentas, sobre lo que tenga esa etiqueta, borrar el bucket o cambiar su IAM
  y su configuración.
- Además les niega cambiar el IAM de las cuentas del pipeline, suplantarlas (`actAs`,
  `getAccessToken`) y cambiar el proveedor de WIF.
- Que el bucket y la llave del estado admitan la etiqueta, y que las etiquetas funcionen en un
  proyecto sin organización, es HYPOTHESIS (`VERIFICAR-EN-APPLY`). Si no funciona, la protección
  queda en: ninguna cuenta con `storage.admin` sin condición, ni `iam.serviceAccountAdmin`, ni
  `resourcemanager.projectIamAdmin`. Esto último ya es así: el IAM de proyecto lo da
  `0-bootstrap`, que aplica una persona.

### 6. Red

- Cinco VPC en el proyecto: hub, `dev`, `qa`, `prod` y `onprem-sim`. Cada spoke se une al hub por
  peering, sin peering entre spokes. Se conservan el direccionamiento de §5 del contrato, Cloud
  NAT y PSA por spoke (ADR 0004) y la VPN y el DNS del hub.
- **Sin Shared VPC:** el spoke y sus cargas están en el mismo proyecto. Las salidas `host_project_id`
  y `service_project_ids` desaparecen; se usa `project_id`.
- **La política jerárquica se reemplaza por una política de firewall de red global por VPC**
  (`google_compute_network_firewall_policy` y su asociación). Hoy se negaba por defecto y se
  delegaba con `goto_next`; esas reglas pasan a la política de cada VPC. Que las etiquetas
  seguras con padre proyecto funcionen sin organización es HYPOTHESIS.
- El proyecto trae la red `default` con reglas abiertas. Se borra a mano, antes de
  `0-bootstrap` (runbook 01). Con organización, la política de organización
  `compute.skipDefaultNetworkCreation` solo sirve para proyectos nuevos.

### 7. Logs, auditoría y SCC

- **Sink:** de proyecto, con exclusiones, hacia el bucket de logs con CMEK de `1-base` (antes era
  agregado de organización).
- **Configuración de auditoría (única por proyecto):**
  - `ADMIN_READ` para `allServices`;
  - `DATA_READ` y `DATA_WRITE` para `cloudkms`, `secretmanager`, `iam`, `sqladmin` y `storage`.
  - Ya no se pueden limitar los registros de acceso a datos a prod: valen para los tres
    entornos. El costo se recalcula en `estimacion-de-costos.md`.
- **SCC:** se activa a mano en el proyecto (Standard o Premium). Según la documentación, la
  activación a nivel proyecto existe y su vista de cumplimiento solo cubre ese proyecto
  ([activación](https://docs.cloud.google.com/security-command-center/docs/activate-scc-overview)).
  Que funcione en un proyecto sin organización es HYPOTHESIS.
- **Mapa CIS:** se rehace. Lo de Cloud Identity y de organización pasa a "No aplica (sin
  organización)" o a "Manual".

### 8. Destroy y ciclo de vida

En un proyecto fijo ya no se borra un proyecto entero.

- **Qué destruye `destroy.yml` para `dev` o `qa`:** siempre `3-workloads/envs/<env>`. El spoke
  `2-networks/envs/<env>` solo con la entrada `incluir_red = true`, porque la conexión de PSA
  puede tardar días en poder borrarse después de borrar Cloud SQL (HYPOTHESIS de la revisión).
- **Qué queda a propósito:** lo del entorno que vive en `1-base`: llaves, repositorios y
  contenedores de secretos. Las llaves KMS no se pueden borrar.
- **Huérfanos:** se buscan con Cloud Asset Inventory en el alcance del proyecto
  ([asset search](https://docs.cloud.google.com/asset-inventory/docs/searching-resources)).
  Cuenta como huérfano todo recurso con `labels.env:<env>` o con nombre que contenga
  `<prefix>-<env>-`, salvo la lista de lo que conserva `1-base`.
  - La etiqueta obligatoria es `env` (`policies/required_labels.rego`).
  - VPC, subredes, routers, políticas de firewall y cuentas de servicio no llevan etiquetas: se
    reconocen por el nombre.
- **`destroy-plan-check.py`** rechaza además cualquier recurso del plan de destroy cuyo nombre no
  lleve `<prefix>-<env>-` (protege lo compartido).
- **Nombres que no se reutilizan de inmediato** (roles personalizados, pools de WIF) solo existen
  en `0-bootstrap` y `1-base`, que no tienen destroy.

### 9. Separación de entornos dentro del proyecto

Lo que separa a dev, qa y prod:

- **Red:** una VPC por entorno, sin peering entre ellas.
- **Nombres y etiquetas:** `<prefix>-<env>-` y `env`.
- **Identidad del pipeline:** una cuenta por entorno, ligada al entorno de GitHub.
- **Permisos condicionados:** en Storage, KMS y Secret Manager.
- **Workload Identity:**
  - Las cuentas de Kubernetes de un namespace se identifican con el pool del proyecto
    (`<proyecto>.svc.id.goog`), igual en los tres entornos
    ([Workload Identity](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity)).
  - Por eso el namespace por defecto pasa a ser `<app>-<env>`, y una validación rechaza un
    namespace que no termine en `-<env>`.
- **Un clúster de GKE por entorno.**

Lo que ya **no** separa, y queda como riesgo aceptado:

- los permisos de Compute, GKE, Cloud Run, Cloud SQL, Memorystore y Filestore de las cuentas de
  entorno;
- los agentes de servicio, que son uno por proyecto;
- la regla por defecto de Binary Authorization para Cloud Run;
- las cuotas, que se comparten.

### 10. Cuotas

Todos los entornos comparten las cuotas del proyecto: redes, peerings por red, CPU e IP por
región, e instancias de Cloud SQL. La documentación no da los valores por defecto
([cuotas de VPC](https://docs.cloud.google.com/vpc/docs/quota)). La guía del colaborador pide
revisarlas el primer día, antes de `0-bootstrap`.

## Interfaces entre etapas

Nombres y tipos fijos: un constructor que necesite otra salida se detiene y lo reporta.

| Etapa | Salida | Tipo | Contenido |
|---|---|---|---|
| `0-bootstrap` | `project_id`, `project_number` | string | el proyecto |
| | `state_bucket`, `state_kms_key_id` | string | estado |
| | `stage_service_accounts` | map(string) | llaves `1-base`, `2-networks`, `2-networks/dev`, `2-networks/qa`, `2-networks/prod`, `3-workloads/dev`, `3-workloads/qa`, `3-workloads/prod` → correo |
| | `read_service_account` | string | correo de `tf-read` |
| | `workload_identity_provider`, `workload_identity_pool` | string | WIF |
| | `custom_role_ids` | map(string) | rol → ID completo |
| | `state_iam_conditions` | map(object) | raíz → `{ writes, reads }` |
| `1-base` | `kms_key_ids` | map(map(string)) | entorno → uso (`app`, `sql`, `storage`, `artifacts`, …) → ID |
| | `secret_ids` | map(map(string)) | entorno → secreto → ID |
| | `artifact_registry_repositories` | map(map(string)) | entorno → app → `{id, url}` serializado como en la etapa 4 actual |
| | `off_hours_role_id` | string | rol del apagado |
| | `security_alert_email`, `notification_channel_ids` | string, map(string) | avisos |
| | `log_bucket` | string | bucket de logs |
| | `vpc_sc_perimeter_name` | string (o null) | perímetro opcional |
| | `org_policies_enabled` | bool | si hay organización |
| `2-networks` (hub) | `hub_network_self_link`, `spoke_supernets` | string, map(string) | como la etapa 3 actual |
| `2-networks/envs/<env>` | `network_self_link`, `subnets`, `psa_range_name`, `reserved_cidrs`, `secure_tags`, `secure_tag_keys` | como la etapa 3 actual | sin `host_project_id` |
| `3-workloads/envs/<env>` | las de la etapa 5 actual que leen las pruebas y la prueba de humo | — | sin cambios de nombre |

## Alternativas descartadas

- **Una sola VPC con una subred por entorno.** Es más simple, pero pierde el hub-and-spoke, el
  aislamiento de red y el ruteo propio hacia on-premises por entorno.
- **Conservar varios proyectos.** El cliente pidió uno solo.
- **Espacios de trabajo de Terraform por entorno.** Ocultan el entorno en el comando; el
  repositorio ya usa una raíz por entorno, y `apply.yml` y las pruebas dependen de eso.

## Consecuencias

- Menos piezas: 4 etapas, sin carpetas, sin Shared VPC y sin crear proyectos. Sin organización,
  cualquier integrante puede desplegar: desaparece el día de dominio y Cloud Identity.
- El aislamiento entre entornos es más débil que con proyectos separados (§9, riesgos aceptados).
  El CIS a nivel organización deja de aplicar.
- Los riesgos aceptados se agregan a `pendientes-apply.md` §5. Lo que este ADR marca como
  HYPOTHESIS entra como pendientes nuevos.

## ADR afectados

| ADR | Qué pasa |
|---|---|
| 0003 | Se mantiene una VPC por entorno con peering al hub, sin Shared VPC |
| 0005 | El balanceador y Cloud Armor quedan en el proyecto único, en la raíz de cargas del entorno |
| 0009 | El perímetro es opcional, rodea todo el proyecto y solo existe con organización |
| 0011 | El orden de despliegue es 0 → 1 → 2 → 3 |
| 0014 | La raíz del hub pasa a `stages/2-networks/` y cada spoke a `envs/<env>/` |
| 0018 | La llave de logs la crea `1-base` |
| 0019 | Ya no hay proyecto `security` aparte; KMS y Secret Manager viven en el proyecto único |
| 0023 | La política de denegación se ata al proyecto con etiquetas (§5); WIF por entorno (§3) |
| 0024 | Un repositorio por entorno y aplicación, y una sola política de Binary Authorization (§4) |
| 0025 | Los `plan` corren con la cuenta de lectura (§3) |
| 0027 | Las desviaciones del CIS se revisan con el mapa nuevo |
| 0028 | El rol del apagado se crea una vez en `1-base`; la cuenta del apagado, en `3-workloads` |
