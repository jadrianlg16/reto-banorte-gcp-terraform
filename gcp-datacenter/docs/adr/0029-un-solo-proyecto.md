# ADR 0029: Toda la landing zone en un solo proyecto de GCP

## Estado

Aceptado, 2026-11-24. Reemplaza al diseño de varios proyectos, que queda en la rama
`archivo/multiproyecto` (commit `d22d164`).

Enmendado el 2026-11-24, después de las revisiones de seguridad e integración del código y de sus
arreglos (ramas `r2/integracion`, `r2/politicas`, `r2/pipeline` y `r2/identidad`). Se conservan
las decisiones de fondo: un proyecto, cuatro raíces y la separación por entorno. Cambia cómo se
logra:

- las políticas de organización y el perímetro de VPC-SC los aplica la persona de `0-bootstrap`;
  ninguna cuenta del pipeline tiene roles de organización (§1);
- las cuentas de ejecución las crea `1-base`, y `tf-wl-<env>` ya no administra cuentas de
  servicio ni asigna roles de proyecto (§2, §4);
- las cuentas que escriben solo aceptan tokens de `main` y de un flujo del repositorio
  (`attribute.deploy`, §3);
- ninguna cuenta del pipeline tiene `tagUser` ni `tagAdmin` de proyecto (§3 y §5);
- la denegación niega además tokens y firmas de cualquier cuenta de servicio (§5);
- Binary Authorization admite un atestador por entorno (§4);
- `DEPRIVILEGE`, el rol `OffHoursScheduler` y el `tagUser` de los agentes de Google están en
  `0-bootstrap` (§4);
- la VM DNS de `onprem-sim` es código opcional (§6);
- las llaves KMS son solo las que se usan, y las de DR existen solo en `dr_environments` (§4).

También corrige ocho diferencias entre el primer texto y el código: las lecturas de estado (§2),
el lugar de `DEPRIVILEGE` y `OffHoursScheduler` (§4), la regla de Binary Authorization de los
clústeres de prod (§4), las interfaces de `kms_key_ids` y de `artifact_registry_repositories`,
el `serviceUsageConsumer` de `tf-read` (§3), lo que niega la política de denegación y dónde va la
etiqueta (§5), la inversión del ADR 0019 y la tabla de ADR afectados. Los riesgos aceptados del
§9 quedan con la lista exacta de lo que sigue sin condición.

Enmendado otra vez el 2026-11-24, después de la re-revisión de seguridad (`seg2`, cinco
hallazgos) y de su arreglo (rama `r2/seg2`):

- `tf-wl-<env>` tiene `container.clusterAdmin` en lugar de `container.admin`, y
  `cloudsql.admin`, `container.clusterAdmin` y `backupdr.admin` quedan condicionados a los
  recursos de su entorno. Monitoring va con cinco roles finos en lugar de `monitoring.editor`
  (§3).
- La cuenta `sched` tiene el rol del apagado condicionado a la instancia y a los clústeres de su
  entorno. La cuenta `workload` se enlaza a todos los pods de un clúster, no a un namespace
  (§3 y §9).
- `attribute.deploy` exige además el `job_workflow_ref` exacto de `_terraform-root.yml` en
  `main` y `event_name` igual a `push` o `workflow_dispatch` (§3).
- La regla 2 de la denegación niega además cambiar los servicios habilitados, y una regla 4
  impide a todos crear llaves de cuentas de servicio (§5).
- Conftest rechaza todo IAM de proyecto y de cuentas de servicio en las raíces de entorno (§4).
- El §9 se rehace con los cuatro riesgos residuales de la re-revisión.

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
- La revisión de seguridad del código (24 nov 2026) encontró que, en el primer texto de este ADR,
  la cuenta de cargas de un entorno podía tomar otras cuentas: tenía `tagUser` de proyecto (que
  trae `iam.serviceAccounts.deleteTagBinding`, un permiso que la denegación no puede negar),
  `serviceAccountUser` y `setIamPolicy` sobre todas las cuentas, y WIF se la entregaba a
  cualquier rama que declarara el entorno. La enmienda de este ADR recoge sus arreglos.
- La re-revisión de seguridad (24 nov 2026) encontró que la misma cuenta todavía llegaba a los
  secretos y a Cloud SQL de prod por GKE: `container.admin` trae permisos sobre los objetos de
  Kubernetes de todos los clústeres, y el enlace de Workload Identity por namespace vale desde
  cualquier clúster del proyecto. También encontró permisos de Service Usage en
  `monitoring.editor`, un filtro de WIF más ancho que lo documentado, llaves de cuentas de
  servicio sin ninguna regla que las impida y una regla de Conftest que admitía IAM de proyecto.
  La segunda enmienda recoge sus arreglos.

## Decisión

### 1. Proyecto y organización

- El proyecto lo crea una persona (consola o `gcloud`) y lo liga a una cuenta de facturación de
  pago. Entra a Terraform como `project_id`. Ninguna raíz crea ni borra el proyecto.
- `org_id` es opcional (`null` por defecto) y es una variable de `0-bootstrap`. Con organización,
  `0-bootstrap` (`stages/0-bootstrap/org.tf`) activa dos cosas:
  - las políticas de organización aplicadas al proyecto (`modules/org`, con padre
    `projects/<id>`), con `additional_allowed_locations` y `directory_customer_id`;
  - el perímetro de VPC-SC opcional, si además llega `access_policy_id`. Rodea todo el proyecto,
    deja entrar a las nueve cuentas del pipeline, queda en dry-run y no separa entornos
    (`vpc_sc_restricted_services`).
- Los aplica la persona de la etapa 0, no el pipeline. `roles/orgpolicy.policyAdmin` solo se puede
  dar en la organización y alcanza a toda ella, y quien edita la política de acceso puede cambiar
  cualquier perímetro de la organización. Por eso ninguna cuenta del pipeline recibe roles de
  organización ni de la política de acceso. La persona necesita
  `roles/orgpolicy.policyAdmin` y `roles/accesscontextmanager.policyAdmin` (runbook 01; puntos 125
  y 126 de [`pendientes-apply.md`](../pendientes-apply.md)).
- Sin organización, esos controles no existen. Lo cubren las reglas de Conftest en cada PR
  (`iam_public_principal`, `service_account_key`, `bucket_uniform_access` y
  `resource_locations`, [`policies/README.md`](../../policies/README.md)) y los pasos manuales
  del runbook 01. Que las políticas de organización y VPC-SC no se puedan usar sin organización
  es HYPOTHESIS: las páginas oficiales no lo dicen explícitamente.

### 2. Etapas, raíces y estado

Cuatro etapas en lugar de seis. Un bucket de estado con un prefijo por raíz (ADR 0010 sigue
vigente).

| Raíz | Prefijo | Cuenta que aplica | Entorno de GitHub | Lee |
|---|---|---|---|---|
| `stages/0-bootstrap` | `0-bootstrap` | una persona, a mano | — | — |
| `stages/1-base` | `1-base` | `<prefix>-tf-base` | `common` | `0-bootstrap` |
| `stages/2-networks` (hub) | `2-networks/hub` | `<prefix>-tf-net` | `common` | — |
| `stages/2-networks/envs/<env>` | `2-networks/<env>` | `<prefix>-tf-net-<env>` | `<env>` | `2-networks/hub` |
| `stages/3-workloads/envs/<env>` | `3-workloads/<env>` | `<prefix>-tf-wl-<env>` | `<env>` | `1-base`, `2-networks/<env>` |

Las raíces de red no usan ninguna salida de `1-base`: el hub no lee ningún estado y cada spoke lee
solo el del hub (`local.stage_roots` de `stages/0-bootstrap/service_accounts.tf`). `tf-read` lee
todo el bucket (§3).

Orden de `apply.yml`: `1-base` → hub → spoke dev → cargas dev → prueba de humo de dev → spoke
qa → cargas qa → spoke prod → cargas prod. dev y qa se pueden dejar fuera con la variable de
repositorio `GCP_DISABLED_ENVS`; prod no ([`pipeline.md`](../pipeline.md) §1.2).

| Etapa nueva | Viene de | Qué contiene |
|---|---|---|
| `0-bootstrap` | etapa 0 y parte de la 1 | APIs del proyecto (todas, una sola vez, `disable_on_destroy = false`), agentes de servicio, OS Login, `DEPRIVILEGE` de la cuenta de Compute por defecto, `tagUser` de los agentes de GKE y de `<número>@cloudservices`, llave y bucket del estado, las nueve cuentas del pipeline (§3) con sus roles de proyecto, WIF, los cuatro roles personalizados de proyecto, etiqueta de protección y política de denegación (§5), presupuesto del proyecto y, con organización, sus políticas y el perímetro (§1) |
| `1-base` | etapas 1 y 2, y lo único por proyecto de la 4 | Ver §4; incluye las cuentas de ejecución de los entornos |
| `2-networks` | etapa 3 | Hub, `onprem-sim` (con la VM DNS opcional), VPN, DNS y políticas de firewall de red; un spoke por entorno sin Shared VPC, con sus etiquetas seguras |
| `3-workloads` | etapas 4 y 5 | Todas las cargas del entorno, con las cuentas de ejecución que crea `1-base` |

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

- Las cuentas que escriben aceptan el `principalSet` de `attribute.deploy`: `common` para
  `tf-base` y `tf-net`, y `<env>` para cada `tf-*-<env>`.
- `attribute.deploy` vale el entorno de GitHub del trabajo solo si el token trae las cuatro
  cosas: la afirmación `environment`, `ref == refs/heads/main`,
  `job_workflow_ref == <github_repository>/.github/workflows/_terraform-root.yml@refs/heads/main`
  y `event_name` igual a `push` o `workflow_dispatch`, los eventos de `apply.yml` y
  `destroy.yml`. Si no, vale `none`, que ninguna cuenta acepta (`stages/0-bootstrap/wif.tf`). Los
  únicos trabajos que escriben son el `apply` de `_terraform-root.yml`, que `apply.yml` y
  `destroy.yml` llaman como flujo reutilizable. Otro flujo del repositorio, `_terraform-root.yml`
  de otra rama y un flujo con `pull_request_target`, `workflow_run` o `issue_comment` (cuyo `ref`
  también es la rama por defecto,
  [eventos](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows))
  reciben `none`. Que GitHub ponga `@refs/heads/main` y no un SHA
  en `job_workflow_ref` cuando el flujo se llama con ruta local no está documentado: si no, el
  apply falla al autenticar, sin abrir permisos (punto 156). Google sugiere restringir por rama o
  flujo
  ([WIF con pipelines](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines));
  las afirmaciones son las de GitHub
  ([OIDC](https://docs.github.com/en/actions/reference/security/oidc)). Puntos 123, 124 y 156.
- `tf-read` acepta tokens de cualquier trabajo del repositorio (`attribute.repository_id`).
- La regla "Deployment branches: main" de cada entorno de GitHub queda como segunda barrera
  (punto 121).

Un trabajo sin entorno de GitHub, de otra rama, de otro evento o de otro flujo solo obtiene la
cuenta de lectura.

- Los `plan` corren con `tf-read` y `-lock=false`: la cuenta no puede escribir el candado del
  estado. El apply toma el candado con la cuenta de la raíz.
- Roles de `tf-read`: `roles/viewer`, `roles/iam.securityReviewer`,
  `roles/cloudasset.viewer`, `roles/networkmanagement.admin` (para las Connectivity Tests de la
  prueba de humo) y `roles/serviceusage.serviceUsageConsumer` (proyecto de cuota, como todas las
  cuentas), más `storage.objectViewer` sobre todo el bucket de estado (punto 122). Que `viewer`
  alcance para refrescar todos los recursos es HYPOTHESIS; se marca `VERIFICAR-EN-APPLY`.

Roles de las cuentas que escriben (lista completa en el [contrato](../CONTRATO.md) §6.3):

- Se dan **en el proyecto** y desde `0-bootstrap`: un rol de proyecto para un principal
  compartido nunca se declara en una raíz de entorno (§4).
- Ninguna cuenta recibe `roles/storage.admin` sin condición. `tf-base` lo recibe condicionado a
  `resource.name.startsWith("projects/_/buckets/<prefix>-common-")` y cada `tf-wl-<env>` a
  `…/<prefix>-<env>-`
  ([condiciones](https://docs.cloud.google.com/iam/docs/conditions-resource-attributes)).
- `tf-base` tiene `cloudkms.admin` con una condición que excluye el llavero del estado, y el rol
  `<prefix>TfSecretContainerAdmin` para los contenedores de secretos y su IAM, sin versiones.
  Las cuentas de entorno no tienen permisos de IAM sobre llaves ni secretos: la lectura de los
  secretos la da `1-base` a cada cuenta de ejecución.
- Ninguna cuenta del pipeline tiene `serviceAccountAdmin`, `tagUser` ni `tagAdmin` de proyecto.
  `tagUser` trae `iam.serviceAccounts.deleteTagBinding`, que la denegación no puede negar
  ([referencia de roles](https://cloud.google.com/iam/docs/roles-permissions/resourcemanager) y
  [permisos que se pueden negar](https://cloud.google.com/iam/docs/deny-permissions-support)):
  con él, una cuenta podría quitar la etiqueta de protección de otra (§5).
  - `tf-base` crea las cuentas de ejecución con `<prefix>TfServiceAccountManager` (cuentas e IAM
    de cuentas, sin `*TagBinding`).
  - `tf-net-<env>` administra las etiquetas seguras de su spoke con `<prefix>TfNetworkTagManager`
    (claves, valores y su IAM, sin ligarlas a recursos).
  - `tf-wl-<env>` recibe `tagUser` solo sobre los valores `lb_backend` e `iap_ssh` de su spoke
    (lo da el spoke) y `serviceAccountUser` solo sobre sus cuentas `gke_nodes`, `mig`, `run` y
    `sched` (lo da `1-base`).
- `roles/resourcemanager.projectIamAdmin` solo lo tiene `tf-base`, en dos asignaciones con
  concesión delegada (`modifiedGrantsByRole`, hasta 10 roles por lista): los roles de lectura de
  los grupos y los roles de las cuentas de ejecución.
- `tf-wl-<env>` recibe condicionados los roles de los servicios que figuran en los
  [atributos de recurso](https://docs.cloud.google.com/iam/docs/conditions-resource-attributes)
  de IAM: Cloud SQL (`Instance` y `BackupRun`), GKE (`Cluster`) y Backup and DR (`BackupVaults`).
  La condición tiene la forma `resource.type != <tipo> || resource.name.startsWith(<prefijo del
  entorno>)`: limita los permisos que se evalúan sobre un recurso de ese tipo y deja pasar los que
  se evalúan sobre otro tipo o sobre el proyecto. GKE comprueba `clusters.create` sobre el
  proyecto
  ([permisos de la API de GKE](https://cloud.google.com/kubernetes-engine/docs/reference/api-permissions)),
  así que la condición no limita el nombre de un clúster nuevo (riesgo 3 del §9). Roles finales
  (`workloads_roles` de `stages/0-bootstrap/service_accounts.tf`):

  | Rol de `tf-wl-<env>` | Condición |
  |---|---|
  | `backupdr.admin` | bóvedas `projects/<id>/locations/<primary_region o dr_region>/backupVaults/<prefix>-<env>-` |
  | `cloudsql.admin` | instancias y sus respaldos `projects/<id>/instances/<prefix>-<env>-data-` |
  | `container.clusterAdmin` (no `container.admin`) | clústeres `projects/<id>/locations/<primary_region o dr_region>/clusters/<prefix>-<env>-` |
  | `storage.admin` | buckets `projects/_/buckets/<prefix>-<env>-` |
  | `certificatemanager.editor`, `compute.instanceAdmin.v1`, `compute.loadBalancerAdmin`, `compute.securityAdmin`, `compute.networkUser`, `file.editor`, `gkebackup.admin`, `monitoring.alertPolicyEditor`, `monitoring.dashboardEditor`, `monitoring.notificationChannelEditor`, `monitoring.servicesEditor`, `monitoring.uptimeCheckConfigEditor`, `redis.admin`, `run.admin` | ninguna |
  | `cloudscheduler.admin` | ninguna; solo `tf-wl-dev` y `tf-wl-qa` (ADR 0028) |

  `container.clusterAdmin` administra clústeres y pools sin permisos sobre los objetos de
  Kubernetes (pods, secretos, tokens de cuentas de Kubernetes), que `container.admin` sí trae en
  todos los clústeres del proyecto. Monitoring va con cinco roles finos porque
  `monitoring.editor` trae `serviceusage.services.enable` y `serviceusage.consumerpolicy.update`.
  Que estas condiciones dejen aplicar la raíz y nieguen lo de otro entorno es HYPOTHESIS (puntos
  152 y 153).
- Compute, Cloud Run, Memorystore, Filestore, Backup for GKE, Certificate Manager y Monitoring van
  **sin condición** a `tf-wl-<env>`, y los de red a `tf-net-<env>`: no admiten `resource.name`, o
  su rol abarca tipos que no lo admiten, y una condición por nombre sobre un tipo que no la
  admite niega todo. Una cuenta de dev puede,
  técnicamente, cambiar recursos de prod de esos servicios (riesgo aceptado, §9). Lo frenan que
  solo un trabajo de `main` en el entorno `dev` obtiene esa cuenta y que todo cambio pasa por PR
  con plan revisado (ADR 0025).
- Las cuentas de ejecución que crea `1-base` (§4) también tienen condiciones:
  - `sched` (solo en `off_hours_environments`): el rol `<prefix>OffHoursScheduler` limitado a la
    instancia `<prefix>-<env>-data-` y a los clústeres `<prefix>-<env>-` de su entorno, con la
    misma forma por tipo (punto 157);
  - `workload`: `iam.workloadIdentityUser` para el `principalSet` de todos los pods del clúster
    `<prefix>-<env>-<app>-gke` y, en `dr_environments`, del `-gke-dr`
    (`…/kubernetes.cluster/https://container.googleapis.com/v1/projects/<id>/locations/<ubicación>/clusters/<clúster>`,
    [Workload Identity](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity)).
    La documentación no tiene un identificador que combine clúster, namespace y cuenta de
    Kubernetes: cualquier pod de ese clúster con una cuenta de Kubernetes anotada obtiene
    `workload` (punto 158);
  - `workload`, `run` y `mig`: `cloudsql.client` e `instanceUser` limitados a las instancias
    `<prefix>-<env>-data-` (punto 133).

### 4. Regla de recursos únicos y principales compartidos

Una raíz de entorno (`2-networks/envs/<env>`, `3-workloads/envs/<env>`) **no puede** declarar:

1. Nada que exista una vez por proyecto:
   - APIs (`google_project_service`) y metadatos del proyecto (OS Login);
   - configuración de auditoría (`google_project_iam_audit_config`);
   - la política de Binary Authorization, contactos esenciales, sinks y buckets de logs, el
     presupuesto y la notificación de SCC;
   - roles personalizados y políticas de organización;
   - llaveros y llaves KMS, secretos y repositorios de Artifact Registry.
2. Permisos de proyecto (`google_project_iam_member`) para cualquier principal: cuentas del
   pipeline, grupos, agentes de servicio, la cuenta de Compute por defecto y también las cuentas
   de ejecución, que ahora crea `1-base`. Tampoco el IAM de cuentas de servicio
   (`google_service_account_iam_*`).
3. Recursos con nombre que no lleve `<prefix>-<env>-` (o `<env>` dentro de los nombres cortos
   que limita GCP, ADR 0017).

La regla de Conftest `env_root_scope` la revisa en el plan de cada PR cuando la variable
`environment` vale `dev`, `qa` o `prod` (`policies/env_root_scope.rego`; punto 146). Desde la
re-revisión rechaza todo `google_project_iam_member` y `_member_remove`, sea cual sea el
principal, y todo `google_service_account_iam_*`; el IAM de un recurso del entorno (secretos,
repositorios, valores de etiqueta, servicios de Cloud Run, buckets) sí pasa.

Por eso pasan a `1-base`:

- **Auditoría y avisos:** configuración de auditoría del proyecto (§7), sink y bucket de logs con
  su llave, `audit-alerts` una sola vez, contactos esenciales, la notificación de SCC (opcional) y
  el canal de operaciones opcional (`operations_alert_email`), que es el único que usan las
  alertas de los entornos (punto 138).
- **Llaves y secretos:** llaveros y llaves KMS por entorno (`<prefix>-<env>-…`) y la llave de logs;
  contenedores de secretos por entorno; permisos de los agentes de servicio sobre las llaves.
  Solo se crean las llaves que alguien usa. En la región de DR y en la multirregión `us` solo hay
  llaves para los entornos de `dr_environments` (por defecto prod). El agente de cada servicio es
  uno por proyecto y queda con las llaves de los tres entornos (riesgo aceptado).
- **Imágenes:** repositorios de Artifact Registry por entorno y aplicación (`<prefix>-<env>-<app>`,
  multirregión) y la única política de Binary Authorization. Tiene dos modos
  (`binary_authorization_env_attestors`, ADR 0024):
  - Con un atestador por entorno, los repositorios salen de la lista de permitidos y cada clúster
    `<prefix>-<env>-<app>-gke[-dr]` exige el atestador de su entorno. Cloud Run usa la regla por
    defecto, que exige `binary_authorization_attestors` o el atestador del primer entorno de la
    promoción. Los atestadores no los crea el repositorio (punto 139).
  - Sin atestadores (por defecto), la lista de permitidos es global y tiene los repositorios de
    los tres entornos. Una imagen que coincide con ella se admite sin mirar las reglas
    ([política](https://docs.cloud.google.com/binary-authorization/docs/reference/rest/v1/projects.policy)):
    un clúster de prod admite una imagen de dev. Las reglas por clúster de prod existen, pero no
    limitan prod al repositorio de prod (riesgo aceptado, §9).
- **Cuentas de ejecución:** `<prefix>-<env>-<app>-<uso>` (`gke-nodes`, `workload`, `mig`, `run` y,
  en `off_hours_environments`, `sched`), con sus roles de proyecto, la lectura de los secretos de
  su entorno y de su repositorio de imágenes, Cloud SQL por IAM condicionado a las instancias
  `<prefix>-<env>-data-`, el rol del apagado condicionado a la instancia y los clústeres del
  entorno, el enlace de Workload Identity por clúster y `serviceAccountUser` para `tf-wl-<env>`
  solo sobre las que adjunta (`stages/1-base/runtime_accounts.tf`; puntos 131 a 135, 157 y 158).
  También la cuenta `<prefix>-common-net-dns` de la VM DNS de `onprem-sim` (§6).
- **IAM de personas:** grupos de solo lectura (`roles/viewer`, `roles/logging.viewer` y los de
  auditoría).

Y quedan en `0-bootstrap`, porque piden permisos que ninguna cuenta del pipeline tiene:

- **Rol del apagado fuera de horario:** `<prefix>OffHoursScheduler`. Crear un rol personalizado
  pide `iam.roleAdmin`, y con ese rol una cuenta podría ampliarse a sí misma. `1-base` lo publica
  como `off_hours_role_id` y se lo da a cada cuenta `sched`, condicionado a su entorno (§3).
- **Cuenta de Compute por defecto:** `google_project_default_service_accounts` con
  `action = "DEPRIVILEGE"`, para quitarle el rol Editor que el proyecto le da al crearse. Quitar
  un rol básico pide `setIamPolicy` sin condición. Ninguna carga la usa.
- **`tagUser` de los agentes de GKE y de `<número>@cloudservices`:** ligan las etiquetas seguras a
  nodos y VM. Si `1-base` pudiera asignar `tagUser`, su cuenta podría dárselo a sí misma (punto
  137).
- **Si hay organización:** políticas de organización y VPC-SC opcional (§1).

Las raíces de entorno ya no crean cuentas de servicio ni asignan roles de proyecto. Usan las
cuentas de ejecución que publica `1-base` (`runtime_service_accounts`) y crean permisos solo
sobre recursos propios del entorno.

### 5. Protección del estado y de la etapa 0

La política de denegación ya no puede ir en una carpeta. Va en el proyecto y usa una
**etiqueta**, porque las condiciones de denegación solo reconocen funciones de etiquetas
([deny](https://docs.cloud.google.com/iam/docs/deny-overview)).

- `0-bootstrap` crea la clave de etiqueta `<prefix>-proteccion`, con valor `etapa-0`, y la liga
  al bucket de estado, al llavero del estado y a las nueve cuentas del pipeline.
- La política `<prefix>-bootstrap-sec-deny-pipeline` tiene cuatro reglas. Las tres primeras son
  contra las nueve cuentas; la cuarta, contra todos:
  1. **Con la etiqueta:** borrar el bucket o cambiar su configuración, su IAM y sus etiquetas;
     cambiar el IAM del llavero o de la llave, cambiar la llave o destruir versiones; y, sobre las
     cuentas del pipeline, cambiar su IAM, tomar su identidad (`actAs`, tokens y firmas),
     cambiarlas, borrarlas o deshabilitarlas.
  2. **Sin condición:** pedir tokens o firmas de **cualquier** cuenta de servicio
     (`getAccessToken`, `getOpenIdToken`, `implicitDelegation`, `signBlob`, `signJwt`); cambiar
     pools y proveedores de WIF o roles personalizados; crear llaves de cuentas de servicio
     (`serviceAccountKeys.create`); borrar el proyecto (`projects.delete`); y cambiar qué
     servicios están habilitados (`serviceusage.googleapis.com/services.enable`,
     `services.disable` y `consumerpolicy.update`). Solo `0-bootstrap` habilita APIs, y la aplica
     una persona que no está en la regla. No niega `serviceusage.services.use`, que las nueve
     cuentas usan como proyecto de cuota. `actAs` no se niega: adjuntar una cuenta de ejecución a
     un recurso lo necesita (puntos 127 y 154).
  3. **Valores de secretos:** `secretmanager.versions.access` para todas salvo `tf-net`, que lee
     la llave de la VPN real.
  4. **Llaves de cuentas de servicio, para todos:** `iam.googleapis.com/serviceAccountKeys.create`
     negado a `principalSet://goog/public:all`, la forma de la documentación para centralizar un
     permiso ([deny](https://docs.cloud.google.com/iam/docs/deny-overview)). Sin organización no
     existe la política `iam.disableServiceAccountKeyCreation`, y `tf-base`, que administra el
     IAM de las cuentas de ejecución, podría dar `serviceAccountKeyAdmin` sobre una a otro
     principal. El pipeline usa WIF y ningún flujo usa llaves JSON (ADR 0007).
- La regla 4 no tiene excepción: ninguna variable de `0-bootstrap` identifica a la persona o al
  grupo que la administra. Consecuencia: **nadie** crea llaves de cuentas de servicio en el
  proyecto, tampoco la persona de la etapa 0 ni los dueños. Si alguna vez hiciera falta una, esa
  persona quita o cambia la regla con `roles/iam.denyAdmin` (los permisos `iam.denypolicies.*` no
  se pueden negar), crea la llave y lo registra. Que ningún agente de servicio de las APIs del
  proyecto necesite crear llaves administradas por el usuario es HYPOTHESIS (punto 155). Mejora
  propuesta, no construida: una variable `stage0_admin_principal` (grupo o usuario) que vaya en
  `exception_principals` de la regla 4 (backlog).
- Algunos permisos no se pueden negar: `iam.serviceAccounts.createTagBinding` y
  `deleteTagBinding`, `cloudkms.keyRings.deleteTagBinding`, `resourcemanager.tagValueBindings.*`
  e `iam.denypolicies.*`. Por eso ninguna cuenta del pipeline tiene `tagUser`, `tagAdmin`,
  `serviceAccountAdmin` ni `iam.denyAdmin` (§3).
- Que el bucket y el llavero del estado admitan la etiqueta, que la llave la herede de su
  llavero y que las etiquetas funcionen en un proyecto sin organización es HYPOTHESIS
  (`VERIFICAR-EN-APPLY`, puntos 90 a 93). Si no funciona (`enable_protection_tags = false`), la
  protección queda en que ninguna cuenta tiene `storage.admin` sin condición,
  `iam.serviceAccountAdmin`, `projectIamAdmin` sin condición ni `tagUser`, y en las reglas 2, 3
  y 4 de la denegación, que no usan la etiqueta.

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
- **VM DNS de `onprem-sim`:** con `onprem_dns_vm = true` (en `0-bootstrap` y en el hub, y solo
  con `simulate_onprem`), el hub crea una e2-micro sin IP pública que responde por el dominio de
  on-premises (`stages/2-networks/onprem_dns.tf`, ADR 0006). Su cuenta la crea `1-base`. Para
  crearla, el hub recibe `compute.instanceAdmin.v1` sin condición mientras la opción esté
  encendida (riesgo del §9; puntos 128 a 130).
- **VPN con on-premises real:** con `simulate_onprem = false`, el plan del hub falla en el
  pipeline. Lo corre `tf-read`, que tiene negado el valor del secreto de la VPN (§5). Es una
  limitación conocida, con tres salidas propuestas y no construidas
  (`stages/2-networks/vpn.tf`; punto 151).
- El proyecto trae la red `default` con reglas abiertas. Se borra a mano, antes de
  `0-bootstrap` (runbook 01, paso 3). Con organización, la política de organización
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
- **Mapa CIS:** se rehace. Lo de Cloud Identity y de organización pasa a "Solo con organización"
  o a "Manual" ([`cumplimiento-cis.md`](../cumplimiento-cis.md)).

### 8. Destroy y ciclo de vida

En un proyecto fijo ya no se borra un proyecto entero.

- **Qué destruye `destroy.yml` para `dev` o `qa`:** siempre `3-workloads/envs/<env>`. El spoke
  `2-networks/envs/<env>` solo con la entrada `incluir_red = true`, porque la conexión de PSA
  puede tardar días en poder borrarse después de borrar Cloud SQL (HYPOTHESIS de la revisión).
  Para que el siguiente push a `main` no lo vuelva a crear, el entorno se apaga con
  `GCP_DISABLED_ENVS`.
- **Qué queda a propósito:** lo del entorno que vive en `1-base`: llaves, repositorios,
  contenedores de secretos y cuentas de ejecución con sus permisos. Las llaves KMS no se pueden
  borrar.
- **Huérfanos:** se buscan con Cloud Asset Inventory en el alcance del proyecto
  ([asset search](https://docs.cloud.google.com/asset-inventory/docs/searching-resources)).
  Es del entorno todo recurso con `labels.env:<env>` o con un nombre, correo u otra etiqueta que
  contenga `<prefix>-<env>-`. De eso, es huérfano lo que no conserva `1-base` (llaves, repositorios
  y contenedores de secretos) ni sigue en un estado del bucket (por ejemplo, las cuentas de
  ejecución de `1-base` o el spoke sin `incluir_red`).
  - La etiqueta obligatoria es `env` (`policies/required_labels.rego`).
  - VPC, subredes, routers, políticas de firewall y cuentas de servicio no llevan etiquetas: se
    reconocen por el nombre.
  - Los restos que GKE nombra con el clúster (firewall, NEG, discos) se asocian al entorno por la
    red o la subred del spoke, la etiqueta del clúster o el namespace `<app>-<env>`; los que no
    se pueden asociar salen como aviso y no hacen fallar el trabajo (`scripts/destroy-orphans.py`;
    punto 140). El namespace `<app>-<env>` queda como convención para esto: Workload Identity ya
    no depende de él (§3).
- **`destroy-plan-check.py`** rechaza además cualquier recurso del plan de destroy cuyo nombre no
  lleve `<prefix>-<env>-` (protege lo compartido).
- **Nombres que no se reutilizan de inmediato** (roles personalizados, pools de WIF) solo existen
  en `0-bootstrap` y `1-base`, que no tienen destroy.

### 9. Separación de entornos dentro del proyecto

Lo que separa a dev, qa y prod:

- **Red:** una VPC por entorno, sin peering entre ellas.
- **Nombres y etiquetas:** `<prefix>-<env>-` y `env`, revisados por Conftest (`env_root_scope` y
  `required_labels`).
- **Identidad del pipeline:** una cuenta por raíz y entorno, que solo se obtiene desde `main`,
  en `_terraform-root.yml`, con `push` o `workflow_dispatch` y con el entorno de GitHub (§3).
- **Permisos por recurso o condicionados** (§3):
  - Storage por prefijo de bucket;
  - `cloudsql.admin` de `tf-wl-<env>` por instancias, `container.clusterAdmin` por clústeres y
    `backupdr.admin` por bóvedas del entorno;
  - la lectura de cada secreto y de cada repositorio de imágenes, solo para las cuentas de
    ejecución de su entorno;
  - Cloud SQL por IAM, condicionado a las instancias del entorno;
  - el rol del apagado de cada cuenta `sched`, condicionado a la instancia y los clústeres de su
    entorno;
  - `serviceAccountUser` de `tf-wl-<env>` solo sobre sus cuentas de ejecución;
  - `tagUser` de `tf-wl-<env>` solo sobre los valores de etiqueta de su spoke.
- **Workload Identity por clúster:** el pool `<proyecto>.svc.id.goog` es uno para el proyecto, y
  un principal por namespace y cuenta de Kubernetes vale desde cualquier clúster del proyecto
  ("Identity sameness" de
  [Workload Identity](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity)).
  Por eso `1-base` enlaza la cuenta `workload` de cada entorno al `principalSet` de todos los pods
  del clúster `<prefix>-<env>-<app>-gke[-dr]` (§3): la frontera es el clúster, que es de un solo
  entorno y una sola aplicación.
- **Un clúster de GKE por entorno**, sin permisos del pipeline sobre los objetos de Kubernetes
  (`container.clusterAdmin`, y 3-workloads no usa el proveedor `kubernetes`).

Lo que ya **no** separa, y queda como riesgo aceptado. Siguen los cuatro riesgos residuales de la
re-revisión de seguridad (24 nov 2026), con lo que cada uno permite (confidencialidad, C;
integridad, I; disponibilidad, A), qué lo detecta y qué lo cerraría:

| Riesgo | Qué permite | Qué lo detecta | Qué lo cerraría |
|---|---|---|---|
| 1. `compute.instanceAdmin.v1` de `tf-wl-<env>` sin condición | Cambiar los metadatos (`startup-script`, `enable-oslogin=FALSE`) de las VM y de los nodos de GKE de prod, lo que da `root` con la cuenta de esa VM: sus permisos sobre secretos, Cloud SQL o imágenes (C e I). Detener o borrar VM de prod (A) | Solo los registros de auditoría de `compute.instances.setMetadata` hechos por `tf-wl-dev` o `tf-wl-qa` sobre nombres `-prod-`. `drift.yml` no lo ve: las VM de un MIG y los nodos de GKE no están en ningún estado. La alerta no está construida (backlog) | Condicionar Compute por los tipos que admite la página de atributos (HYPOTHESIS para los nodos de GKE), o proyectos separados (rama `archivo/multiproyecto`) |
| 2. Un MIG con la plantilla de prod que ya existe (HYPOTHESIS de la re-revisión) | Crear VM con la cuenta `mig` de prod sin `actAs`, porque las crea el agente de servicio de Compute; con `setMetadata` (riesgo 1) se obtiene su token (C e I) | Los registros de auditoría de `instanceGroupManagers.insert` con una plantilla `-prod-` hechos por otra cuenta; el MIG nuevo sale como recurso no administrado en `drift.yml` | Lo mismo que el riesgo 1 |
| 3. Clúster con el nombre de prod creado por otro entorno | La condición de `clusters.update` ya impide un pool propio en el clúster de prod (punto 152). Pero GKE comprueba `clusters.create` en el proyecto: `tf-wl-dev` podría crear un clúster con el nombre de prod que aún no exista (`<prefix>-prod-<app>-gke-dr` antes de una conmutación, o el primario si prod no usa GKE), y `1-base` ya enlazó ese `principalSet`. Con `root` en sus nodos (riesgo 1), un token de cuenta de Kubernetes de ese clúster da la cuenta `workload` de prod: secretos y Cloud SQL de prod (C e I) | Los registros de auditoría de `CreateCluster` con nombre `-prod-` hechos por una cuenta que no es `tf-wl-prod`; el clúster sale como recurso no administrado en `drift.yml`. La alerta no está construida (backlog) | Un principal por UID de la cuenta de Kubernetes, enlazar solo los clústeres que ya existen, o proyectos separados |
| 4. Otros servicios sin condición o con condición parcial | Memorystore (`redis.admin`): cambiar o borrar la instancia de prod (I y A; AUTH está apagado, ADR 0015). Filestore (`file.editor`): respaldos y borrado (A). Backup for GKE (`gkebackup.admin`): restaurar un respaldo de prod en otro clúster (C; HYPOTHESIS). Backup and DR: la condición solo limita las bóvedas; planes, asociaciones y restauraciones fuera de la bóveda quedan sin límite (I y A; las restauraciones, HYPOTHESIS). Los cinco roles de Monitoring pueden borrar las alertas y los canales de `1-base` y de otro entorno: deja sin detección (A). `networkUser` con `instanceAdmin.v1`: VM en las subredes de prod, que llegan por red a Memorystore, Filestore y Cloud SQL (C). Las condiciones de Cloud SQL no limitan usuarios ni bases (`cloudsql.users.*`, `cloudsql.databases.*`). Cualquier pod del clúster obtiene `workload` (I) | `drift.yml` para lo que está en un estado (instancias, alertas, canales, planes); recursos nuevos fuera del código en su trabajo de recursos no administrados; las alertas de `audit-alerts` mientras existan | Proyectos separados; para las alertas de `1-base`, una regla de denegación por etiqueta sobre ellas (HYPOTHESIS, backlog) |

Además siguen sin condición, con efecto entre entornos (`workloads_roles`, `net_env_roles` y
`hub_roles` de `stages/0-bootstrap/service_accounts.tf`):

| Cuenta | Rol sin condición | Qué puede hacer en otro entorno | Qué lo detecta | Qué lo cerraría |
|---|---|---|---|---|
| `tf-wl-<env>` | `compute.loadBalancerAdmin`, `compute.securityAdmin` | Cambiar o borrar balanceadores, certificados SSL y políticas de Cloud Armor de otro entorno | `drift.yml`: el plan diario de la raíz de ese entorno | Condiciones o denegación por etiqueta de recurso, si Compute las admite (HYPOTHESIS); o un proyecto por entorno |
| `tf-wl-<env>` | `run.admin` | Cambiar o borrar servicios de Cloud Run de otro entorno y su IAM de invocador | `drift.yml` | Condiciones por nombre, si Cloud Run las admite (HYPOTHESIS); o un proyecto por entorno |
| `tf-wl-<env>` | `certificatemanager.editor` | Cambiar certificados y autorizaciones DNS de otro entorno | `drift.yml` | Un proyecto por entorno |
| `tf-wl-dev`, `tf-wl-qa` | `cloudscheduler.admin` | Cambiar o borrar los trabajos del apagado del otro entorno (dev y qa). Un trabajo que apunte a otro entorno debe fallar: la cuenta `sched` tiene el rol del apagado solo sobre el suyo (punto 157) | `drift.yml` (los trabajos se declaran con `paused = false`, ADR 0028) | Un proyecto por entorno |
| `tf-net-<env>` | `compute.networkAdmin` | Cambiar o borrar VPC, subredes, rutas, peerings, routers y NAT de otro spoke, del hub y de `onprem-sim` | `drift.yml` y las alertas de rutas y de redes de `audit-alerts` | Un proyecto por entorno (Shared VPC pide organización) |
| `tf-net-<env>` | `compute.securityAdmin` | Cambiar las políticas de firewall de red de otra VPC | `drift.yml` y la alerta `firewall_policy` de `audit-alerts` | Un proyecto por entorno |
| `tf-net-<env>` | `dns.admin` | Cambiar las zonas DNS de otro entorno y del hub | `drift.yml` | Un proyecto por entorno |
| `tf-net-<env>` | `servicenetworking.networksAdmin` | Cambiar o borrar la conexión de PSA de otro spoke | `drift.yml` | Un proyecto por entorno |
| `tf-net-<env>` | `<prefix>TfNetworkTagManager` | Cambiar las claves y valores de etiquetas seguras de otro spoke y su IAM, también el de la clave de protección. No puede quitar la etiqueta de lo protegido: no tiene `deleteTagBinding` (§5) | `drift.yml` para las claves y los valores; un miembro de IAM agregado sobre un valor no lo ve el plan (asignaciones aditivas): solo los registros de auditoría | Dar el IAM de los valores desde `0-bootstrap`, o condicionar el rol si Resource Manager lo admite (HYPOTHESIS) |
| `tf-net` (hub) | `compute.instanceAdmin.v1`, solo con `onprem_dns_vm = true` | Cambiar o borrar las VM de los entornos (el riesgo 1, desde el hub) | Los mismos registros de auditoría que el riesgo 1 | Apagar `onprem_dns_vm` después de la prueba de DNS (backlog G11) |

`serviceusage.serviceUsageConsumer`, sin condición en las nueve cuentas, solo sirve para usar el
proyecto como proyecto de cuota: no da acceso a recursos de otro entorno. Ninguna cuenta del
pipeline puede habilitar ni deshabilitar servicios (regla 2 de la denegación, §5).

También:

- **`tf-base`:** `TfServiceAccountManager` va sin condición, sobre todas las cuentas del proyecto
  salvo las nueve del pipeline, que protege la denegación. Podría cambiar el IAM de una cuenta de
  ejecución de cualquier entorno, o darle `serviceAccountTokenCreator` a otro principal. No puede
  hacer que alguien cree una llave de esa cuenta: la regla 4 de la denegación vale para todos.
  Lo detecta el `drift.yml` diario de `1-base`, salvo los miembros agregados por fuera del
  código. Las concesiones delegadas limitan roles, no destinatarios ni condiciones.
- **Agentes de servicio:** uno por proyecto. El de cada servicio tiene permiso sobre las llaves de
  los tres entornos, y el de Cloud Run lee los repositorios de los tres.
- **Binary Authorization sin atestadores por entorno:** la lista de permitidos global (§4), y la
  regla por defecto para Cloud Run en los dos modos.
- **`tf-read`:** lee los estados de todas las raíces y la toma cualquier trabajo del repositorio
  (punto 122).
- **Cuotas:** se comparten (§10).

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
| | `custom_role_ids` | map(string) | `secret_container_admin`, `service_account_manager`, `network_tag_manager` y `off_hours_scheduler` → ID completo |
| | `org_policies_enabled` | bool | si hay organización y se aplicaron sus políticas |
| | `vpc_sc_perimeter_name` | string (o null) | perímetro opcional |
| | `onprem_dns_vm_enabled` | bool | si el hub puede crear la VM DNS |
| | `state_iam_conditions` | map(object) | raíz → `{ writes, reads }` |
| `1-base` | `kms_key_ids` | map(map(string)) | entorno → llave → ID. Llave `<uso>` en la región primaria, `<uso>_dr` en la de DR y `<uso>_us` en la multirregión (por ejemplo `sql`, `sql_dr`, `storage_us`, `artifacts_us`) |
| | `secret_ids` | map(map(string)) | entorno → secreto → ID |
| | `artifact_registry_repositories` | map(map(string)) | entorno → aplicación → URL `<ubicación>-docker.pkg.dev/<proyecto>/<repositorio>` |
| | `runtime_service_accounts` | map(map(map(string))) | entorno → aplicación → uso (`gke_nodes`, `workload`, `mig`, `run` y `scheduler`) → correo |
| | `gke_workload_identity_members` | map(map(map(string))) | entorno → aplicación → clúster (`primary` y, en `dr_environments`, `dr`) → `principalSet` de todos los pods del clúster, o null mientras `gke_workload_identity_bindings` sea false |
| | `onprem_dns_service_account` | string (o null) | cuenta de la VM DNS |
| | `off_hours_role_id` | string | rol del apagado |
| | `security_alert_email`, `notification_channel_ids` | string, map(string) | avisos: `security` y, con `operations_alert_email`, `operations` |
| | `log_bucket` | string | bucket de logs |
| `2-networks` (hub) | `hub_network_self_link`, `spoke_supernets` | string, map(string) | como la etapa 3 anterior |
| | `onprem_dns_vm` | object (o null) | `{ name, zone, ip, record }` de la VM DNS |
| `2-networks/envs/<env>` | `network_self_link`, `subnets`, `psa_range_name`, `reserved_cidrs`, `secure_tags`, `secure_tag_keys` | como la etapa 3 anterior | sin `host_project_id` |
| `3-workloads/envs/<env>` | las de la etapa 5 anterior que leen las pruebas y la prueba de humo | — | sin cambios de nombre |

`3-workloads` lee de `1-base` `kms_key_ids`, `artifact_registry_repositories`,
`runtime_service_accounts`, `gke_workload_identity_members` y solo
`notification_channel_ids["operations"]`. Ya no lee `secret_ids` ni `off_hours_role_id`.

## Alternativas descartadas

- **Una sola VPC con una subred por entorno.** Es más simple, pero pierde el hub-and-spoke, el
  aislamiento de red y el ruteo propio hacia on-premises por entorno.
- **Conservar varios proyectos.** El cliente pidió uno solo.
- **Espacios de trabajo de Terraform por entorno.** Ocultan el entorno en el comando; el
  repositorio ya usa una raíz por entorno, y `apply.yml` y las pruebas dependen de eso.
- **Cuentas de ejecución creadas por cada raíz de entorno** (primer texto de este ADR).
  Descartada por la revisión de seguridad: la cuenta de cargas necesitaba administrar cuentas de
  servicio e IAM de proyecto, y con eso alcanzaba las cuentas de otros entornos.
- **WIF por `attribute.environment` solamente** (primer texto). Descartada: cualquier rama que
  declarara el entorno obtenía la cuenta, y la regla de ramas de los entornos de GitHub depende
  del plan de GitHub del repositorio.

## Consecuencias

- Menos piezas: 4 etapas, sin carpetas, sin Shared VPC y sin crear proyectos. Sin organización,
  cualquier integrante puede desplegar: desaparece el día de dominio y Cloud Identity.
- El aislamiento entre entornos es más débil que con proyectos separados (§9, riesgos aceptados).
  El CIS a nivel organización deja de aplicar.
- `0-bootstrap` crece: además de la base del pipeline, tiene lo que pide permisos que ninguna
  cuenta del pipeline debe tener (organización, roles personalizados, `DEPRIVILEGE` y `tagUser`
  de los agentes). Un cambio ahí lo aplica una persona a mano.
- Los riesgos aceptados se agregan a `pendientes-apply.md` §5. Lo que este ADR marca como
  HYPOTHESIS entra como pendientes nuevos.

## ADR afectados

| ADR | Qué pasa |
|---|---|
| 0002 | Los llaveros por ubicación los crea `1-base`; `gcp.resourceLocations` solo existe con organización (o como regla de Conftest) |
| 0003 | Se mantiene una VPC por entorno con peering al hub, sin Shared VPC |
| 0005 | El balanceador y Cloud Armor quedan en el proyecto único, en la raíz de cargas del entorno |
| 0006 | El hub crea `onprem-sim` en el proyecto único; la VM DNS es código opcional; con on-premises real, el plan del hub falla en el pipeline |
| 0007 | Seis flujos en total; WIF de escritura solo desde `main`, en `_terraform-root.yml` y con `push` o `workflow_dispatch` (`attribute.deploy`); plan con `tf-read`; `GCP_DISABLED_ENVS` |
| 0008 | La llave del estado sigue en `0-bootstrap`, protegida además por la etiqueta |
| 0009 | Reemplazado: el perímetro es opcional, solo con organización, lo crea `0-bootstrap` alrededor de todo el proyecto y queda en dry-run |
| 0010 | Escritura en el prefijo propio y lectura mínima: el hub no lee nada, los spokes leen el hub; `tf-read` lee todo |
| 0011 | El orden de despliegue es 0 → 1 → 2 → 3 |
| 0012 | Las cargas usan las cuentas de ejecución de `1-base`; Workload Identity por clúster: `1-base` enlaza la cuenta `workload` al `principalSet` de todos los pods de `<prefix>-<env>-<app>-gke[-dr]`; `3-workloads` tiene `container.clusterAdmin` condicionado a sus clústeres |
| 0014 | La raíz del hub pasa a `stages/2-networks/` y cada spoke a `envs/<env>/` |
| 0015 | Los contenedores de secretos y su lectura por las cuentas de ejecución los da `1-base`; ninguna cuenta de entorno tiene IAM de secretos |
| 0017 | Cuentas del pipeline por raíz y entorno; las de ejecución y la de la VM DNS las crea `1-base` |
| 0018 | La llave de logs la crea `1-base` |
| 0019 | Reemplazado e invertido: sin proyecto `security`, KMS y Secret Manager sí están en `vpc_sc_restricted_services` por defecto |
| 0020 | Cloud Run nunca con `allUsers`, con o sin organización (Conftest `iam_public_principal`) |
| 0021 | Las pruebas de las raíces nuevas siguen con `override_during = plan` |
| 0022 | El estado multirregional y la VPN de DR siguen; las llaves de DR existen solo en `dr_environments` |
| 0023 | Política de denegación en el proyecto con cuatro reglas (§5), la cuarta contra la creación de llaves de cuentas de servicio por cualquier principal; WIF por `attribute.deploy` con `job_workflow_ref` y `event_name`; sin `tagUser` ni `tagAdmin` de proyecto |
| 0024 | Un repositorio por entorno y aplicación, una sola política de Binary Authorization y atestadores por entorno opcionales |
| 0025 | Los `plan` corren con la cuenta de lectura (§3) |
| 0026 | Las zonas del VIP restringido siguen en los tres spokes |
| 0027 | Las desviaciones del CIS se revisan con el mapa nuevo; 1.7 se cierra con las cuentas de ejecución en `1-base` |
| 0028 | El rol del apagado lo crea `0-bootstrap`; la cuenta del apagado y su permiso, condicionado a la instancia y los clústeres de su entorno, `1-base` |
