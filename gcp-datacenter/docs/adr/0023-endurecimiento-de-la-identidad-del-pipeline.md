# ADR 0023: Endurecimiento de la identidad del pipeline

## Estado

Aceptado, 2026-11-21. Completa los ADR 0007, 0010 y 0015.

Enmendado el 2026-11-24: con el proyecto único ([ADR 0029](0029-un-solo-proyecto.md) §3 y §5)
se conservan los cuatro principios (WIF por IDs numéricos, política de denegación, roles
personalizados sin acceso a valores y lecturas de estado mínimas) y cambian los detalles: nueve
cuentas en lugar de cinco, `tf-read` para los `plan`, la política de denegación en el proyecto
con la etiqueta `<prefix>-proteccion = etapa-0` y todos los roles de proyecto dados desde
`0-bootstrap`, condicionados por nombre donde el servicio lo admite.

Enmendado otra vez el 2026-11-24, con los arreglos de la revisión de seguridad del código (rama
`r2/identidad`):

- las cuentas que escriben se toman por `attribute.deploy` (solo `main` y un flujo del
  repositorio), no por `attribute.environment`;
- ninguna cuenta del pipeline tiene `tagUser` ni `tagAdmin` de proyecto;
- las cuentas de ejecución las crea `1-base`, y `tf-wl-<env>` ya no administra cuentas ni IAM
  de proyecto;
- la denegación niega además tokens y firmas de cualquier cuenta de servicio y el valor de los
  secretos;
- desaparecen `<prefix>TfKmsSecretIamGranter` y `<prefix>TfRepositoryIamGranter`, y aparece
  `<prefix>TfNetworkTagManager`;
- las políticas de organización las aplica la persona de `0-bootstrap`.

Enmendado una tercera vez el 2026-11-24, con el arreglo de la re-revisión de seguridad (rama
`r2/seg2`, hallazgos N1 a N5):

- `attribute.deploy` exige el `job_workflow_ref` exacto de `_terraform-root.yml` en `main` y
  `event_name` igual a `push` o `workflow_dispatch` (N3);
- la denegación tiene cuatro reglas: la regla sin etiqueta niega además cambiar los servicios
  habilitados (N2), y una regla 4 niega a todos crear llaves de cuentas de servicio (N4);
- `tf-wl-<env>` tiene `container.clusterAdmin` en lugar de `container.admin` y cinco roles de
  Monitoring en lugar de `monitoring.editor`; `cloudsql.admin`, `container.clusterAdmin` y
  `backupdr.admin` van condicionados a los recursos de su entorno (N1 y N2);
- Conftest rechaza todo IAM de proyecto y de cuentas de servicio en las raíces de entorno (N5).

El texto de abajo describe el diseño vigente; el de varios proyectos vive en la rama
`archivo/multiproyecto`.

Tipo: Aclaración.

## Contexto

Las cuentas del pipeline aplican la infraestructura con Workload Identity Federation (ADR 0007).
La revisión independiente del 21 nov 2026 encontró caminos por los que una de ellas, o quien
controle el repositorio, obtenía más de lo que su raíz necesita: el proveedor de WIF confiaba en
el **nombre** del repositorio (que se puede volver a registrar si se borra o se renombra; los IDs
numéricos no se reutilizan), una cuenta con roles de organización alcanzaba por herencia a la
etapa 0, y el pipeline podía leer valores de secretos en contra del ADR 0015.

Con el proyecto único (ADR 0029) el problema cambia de forma: ya no hay carpetas ni proyectos que
separen a las cuentas. Los tres entornos, el estado y las nueve cuentas están en el mismo
proyecto, así que la cuenta de un entorno no debe alcanzar el estado, las cuentas ni los recursos
con nombre de otro entorno, y nada de eso puede depender de la herencia entre carpetas.

La revisión de seguridad del código (24 nov 2026) encontró que la cuenta de cargas de un entorno
todavía podía tomar otras cuentas. Tenía `tagUser` de proyecto, que trae
`iam.serviceAccounts.deleteTagBinding`, un permiso que la denegación no puede negar. Con eso
podía quitar la etiqueta de protección de una cuenta del pipeline. Además tenía `setIamPolicy` y
`serviceAccountUser` sobre todas las cuentas, y WIF se la entregaba a cualquier rama que declarara
el entorno de GitHub.

La re-revisión de seguridad (24 nov 2026) encontró que, con esos arreglos, la cuenta de cargas de
dev todavía llegaba a los secretos y a Cloud SQL de prod por GKE (`container.admin` trae permisos
sobre los objetos de Kubernetes de todos los clústeres); que `monitoring.editor` trae permisos de
Service Usage; que el filtro de WIF aceptaba cualquier flujo de `.github/workflows/`; que nada
impedía crear llaves de cuentas de servicio sin organización; y que una regla de Conftest
admitía IAM de proyecto en las raíces de entorno.

## Decisión

- **WIF por IDs numéricos y, para escribir, solo desde `main` (`stages/0-bootstrap/wif.tf` y
  `service_accounts.tf`).**
  - Variables obligatorias `github_repository_id` y `github_repository_owner_id` (solo dígitos;
    `gh api repos/<dueño>/<repositorio> --jq '.id, .owner.id'`). `attribute_condition` exige
    `assertion.repository_id == "<id>" && assertion.repository_owner_id == "<id del dueño>"`.
  - `attribute.deploy` vale el entorno de GitHub del trabajo solo si el token trae la
    afirmación `environment`, `ref == 'refs/heads/main'`,
    `job_workflow_ref == '<github_repository>/.github/workflows/_terraform-root.yml@refs/heads/main'`
    y `event_name` igual a `push` o `workflow_dispatch`; si no, vale `none`. Los trabajos que
    escriben son el `apply` de `_terraform-root.yml`, que `apply.yml` (`push` y
    `workflow_dispatch`) y `destroy.yml` (`workflow_dispatch`) llaman como flujo reutilizable, y
    GitHub solo documenta `job_workflow_ref` para flujos reutilizables
    ([OIDC](https://docs.github.com/en/actions/reference/security/oidc)). El evento cierra el paso
    a un flujo nuevo con `pull_request_target`, `workflow_run` o `issue_comment`, cuyo `ref`
    también es la rama por defecto
    ([eventos](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)).
    Que GitHub ponga `@refs/heads/main` y no un SHA cuando el flujo se llama con ruta local no está
    documentado: si no, el apply falla al autenticar (punto 156). Google sugiere restringir por
    rama o flujo
    ([WIF con pipelines](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines)).
  - `attribute.repository_id`, `attribute.repository_owner_id`, `attribute.repository`,
    `attribute.ref` y `attribute.environment` se conservan solo para leer los registros de
    auditoría. Las afirmaciones que pueden faltar se leen después de comprobar que están: una
    expresión de mapeo que falla deja sin token a cualquier trabajo.
  - `roles/iam.workloadIdentityUser`:
    - `tf-base` y `tf-net`: `principalSet://iam.googleapis.com/<pool>/attribute.deploy/common`;
    - `tf-net-<env>` y `tf-wl-<env>`: `…/attribute.deploy/<env>`;
    - `tf-read`: `…/attribute.repository_id/<github_repository_id>`.

  Un trabajo sin entorno de GitHub, de otra rama, de otro evento o de otro flujo solo obtiene
  `tf-read`. La regla "Deployment branches: main" de cada entorno de GitHub queda como segunda
  barrera. Si el repositorio o `_terraform-root.yml` se renombran, `attribute.deploy` queda en
  `none` hasta volver a aplicar `0-bootstrap` con el nombre nuevo (falla cerrado). Puntos 123,
  124 y 156 de [`pendientes-apply.md`](../pendientes-apply.md).
- **Etiqueta y política de denegación del proyecto (`stages/0-bootstrap/deny_policy.tf`).**
  Las condiciones de denegación solo admiten funciones de etiquetas
  ([deny](https://docs.cloud.google.com/iam/docs/deny-overview)), así que lo protegido se marca
  con la clave `<prefix>-proteccion` (padre `projects/<id>`) y el valor `etapa-0`, ligado al
  bucket de estado, al llavero del estado y a las nueve cuentas. La política
  `<prefix>-bootstrap-sec-deny-pipeline` tiene cuatro reglas, las tres primeras contra las nueve
  cuentas:
  1. con la etiqueta: borrar el bucket o cambiar su configuración, su IAM y sus etiquetas;
     cambiar el IAM del llavero o de la llave, cambiar la llave o destruir versiones; cambiar el
     IAM de las cuentas, tomar su identidad (`actAs`, `getAccessToken`, `getOpenIdToken`,
     `implicitDelegation`, `signBlob`, `signJwt`), cambiarlas, borrarlas o deshabilitarlas;
  2. sin condición: pedir tokens o firmas de **cualquier** cuenta de servicio (`getAccessToken`,
     `getOpenIdToken`, `implicitDelegation`, `signBlob`, `signJwt`); crear, cambiar o borrar
     pools y proveedores de WIF y roles personalizados; crear llaves de cuentas de servicio;
     borrar el proyecto; y cambiar qué servicios están habilitados
     (`serviceusage.googleapis.com/services.enable`, `services.disable` y
     `consumerpolicy.update`; solo `0-bootstrap` habilita APIs). `actAs` no se niega: adjuntar
     una cuenta de ejecución a un nodo, una VM, un servicio de Cloud Run o un trabajo de Cloud
     Scheduler lo necesita (puntos 127 y 154). Tampoco `serviceusage.services.use`, que las
     nueve cuentas usan como proyecto de cuota;
  3. valores de secretos: `secretmanager.versions.access` para todas salvo `tf-net`, que lee la
     llave de la VPN real;
  4. llaves de cuentas de servicio para **todos**: `iam.googleapis.com/serviceAccountKeys.create`
     negado a `principalSet://goog/public:all`, sin excepción. Sin organización no existe
     `iam.disableServiceAccountKeyCreation`, y `tf-base`, que administra el IAM de las cuentas de
     ejecución, podría dar `serviceAccountKeyAdmin` a otro principal. Nadie crea llaves en el
     proyecto, tampoco la persona de la etapa 0; si alguna vez hiciera falta una, esa persona
     quita la regla con `roles/iam.denyAdmin` y lo registra (ADR 0029 §5; punto 155).

  Una denegación se impone a cualquier permiso concedido. Quien aplica `0-bootstrap` necesita
  `roles/iam.denyAdmin` en el proyecto. `enable_protection_tags` y `enable_deny_policy` (ambas
  `true` por defecto) permiten apagarlas si no funcionan sin organización.
- **Roles de proyecto solo desde `0-bootstrap`, con condiciones**
  ([atributos](https://docs.cloud.google.com/iam/docs/conditions-resource-attributes)). Ninguna
  raíz de entorno da roles de proyecto (regla de recursos únicos, contrato §7.5). Lista completa
  en el contrato §6.3; lo esencial:
  - `roles/storage.admin` solo con condición: buckets `<prefix>-common-` para `tf-base` y
    `<prefix>-<env>-` para `tf-wl-<env>`; ninguna alcanza el bucket de estado
    (`<prefix>-bootstrap-…`).
  - `tf-base` tiene `cloudkms.admin` con una condición que excluye el llavero del estado. Las
    cuentas de entorno no tienen permisos de IAM sobre llaves, secretos ni repositorios: los da
    `1-base` a las cuentas de ejecución.
  - `roles/resourcemanager.projectIamAdmin` solo lo tiene `tf-base`, con dos concesiones
    delegadas
    (`api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([...])`, hasta 10
    roles por lista): los roles de lectura de los grupos, y los roles de las cuentas de ejecución
    más el del apagado. Ninguna lista tiene `tagUser`.
  - `cloudsql.admin`, `container.clusterAdmin` y `backupdr.admin` de `tf-wl-<env>` van
    condicionados a las instancias, clústeres y bóvedas de su entorno, con la forma
    `resource.type != <tipo> || resource.name.startsWith(<prefijo>)` (ADR 0029 §3; punto 152).
    `container.clusterAdmin` reemplaza a `container.admin`, que trae permisos sobre los objetos
    de Kubernetes de todos los clústeres; cinco roles de Monitoring reemplazan a
    `monitoring.editor`, que trae `serviceusage.services.enable` (punto 153).
  - Compute, Cloud Run, Memorystore, Filestore, Backup for GKE, Certificate Manager, Monitoring y
    la red, **sin condición**: no admiten `resource.name`, o su rol abarca tipos que no lo
    admiten, y una condición por nombre sobre un tipo que no la admite niega todo. La lista
    exacta y sus riesgos están en el ADR 0029 §9.
- **Ni `serviceAccountAdmin` ni `tagUser` de proyecto.** Los dos traen `*TagBinding` sobre
  cuentas, y `iam.serviceAccounts.deleteTagBinding` no se puede negar
  ([permisos que se pueden negar](https://cloud.google.com/iam/docs/deny-permissions-support)).
  Los cuatro roles personalizados (`stages/0-bootstrap/custom_roles.tf`, salida
  `custom_role_ids`) cubren lo que hace falta:
  - `<prefix>TfServiceAccountManager` (`tf-base`): crear, cambiar, borrar, deshabilitar y dar IAM
    sobre cuentas, sin `createTagBinding` ni `deleteTagBinding`. Con él `1-base` crea las cuentas
    de ejecución y da a `tf-wl-<env>` `iam.serviceAccountUser` solo sobre sus cuentas
    `gke_nodes`, `mig`, `run` y `sched`.
  - `<prefix>TfNetworkTagManager` (`tf-net-<env>`): claves y valores de etiquetas y su IAM, sin
    `tagValueBindings` ni `*TagBinding`. El spoke da a `tf-wl-<env>` `tagUser` solo sobre sus
    valores `lb_backend` e `iap_ssh`.
  - `<prefix>TfSecretContainerAdmin` (`tf-base`): `secretmanager.secrets.{create,delete,get,
    getIamPolicy,list,setIamPolicy,update}` y `secretmanager.locations.{get,list}`, sin
    versiones.
  - `<prefix>OffHoursScheduler`: el rol del apagado (ADR 0028).

  El `tagUser` de los agentes de GKE y de `<número>@cloudservices` lo da `0-bootstrap` (punto
  137). Los roles personalizados viven en `0-bootstrap`, así que ninguna cuenta necesita
  `iam.roleAdmin`.
- **Lecturas de estado mínimas.** Cada cuenta escribe su prefijo y lee solo los de la lista
  `reads` de su raíz (contrato §6.1): `1-base` lee `0-bootstrap`, el hub no lee nada, cada spoke
  lee `2-networks/hub` y las cargas leen `1-base` y `2-networks/<env>`. `tf-read` lee todo el
  bucket. Los `plan` corren con `tf-read` y `-lock=false` (ADR 0025).
- **Ningún rol de organización en el pipeline.** Las políticas de organización y el perímetro de
  VPC-SC los aplica la persona de `0-bootstrap` (`stages/0-bootstrap/org.tf`, ADR 0029 §1).

## Alternativas consideradas

- **WIF solo por `attribute.environment`** (primer texto de este ADR con el proyecto único).
  Descartada por la revisión de seguridad: cualquier rama que declarara el entorno obtenía la
  cuenta, y la regla de ramas de los entornos de GitHub depende del plan de GitHub del
  repositorio.
- **Condicionar todas las cuentas por `attribute.ref`.** Rompería los `plan` de los PR, que
  corren en ramas. Por eso la condición de rama solo está en las cuentas que escriben; los `plan`
  usan `tf-read`.
- **Política de denegación en una carpeta `bootstrap`.** Era el diseño de varios proyectos; sin
  organización no hay carpetas (ADR 0029 §5).
- **`iam.serviceAccountAdmin` o `tagUser` de proyecto para alguna cuenta.** Rechazada: traen
  `*TagBinding` sobre cuentas (ver arriba).
- **Que cada raíz de entorno cree sus cuentas de ejecución** (diseño anterior). Rechazada: la
  cuenta de cargas necesitaba `setIamPolicy` sobre cuentas y `projectIamAdmin` delegado a nivel de
  proyecto, y con eso alcanzaba las cuentas de otros entornos. Ahora las crea `1-base` y da
  `actAs` por cuenta.

## Consecuencias

Riesgos residuales (análisis de la documentación de Google, sin probar en GCP):

- **Las etiquetas y la denegación en un proyecto sin organización son HYPOTHESIS**
  (`VERIFICAR-EN-APPLY` en `deny_policy.tf`, puntos 90 a 93). Si no funcionan, la protección queda
  en que ninguna cuenta tiene `storage.admin` sin condición, `iam.serviceAccountAdmin`,
  `projectIamAdmin` sin condición ni `tagUser`. En ese caso `tf-base`, con `setIamPolicy` sobre
  cuentas a nivel de proyecto (`<prefix>TfServiceAccountManager`), podría darse acceso a otra
  cuenta del pipeline.
- **Algunos permisos no se pueden negar:** `iam.serviceAccounts.createTagBinding` y
  `deleteTagBinding`, `cloudkms.keyRings.deleteTagBinding`, `resourcemanager.tagValueBindings.*` e
  `iam.denypolicies.*`. Ninguna cuenta tiene esos permisos sobre lo protegido ni `iam.denyAdmin`.
  Las cuentas de spoke, con `<prefix>TfNetworkTagManager`, alcanzan también la clave de
  protección: podrían darse `tagUser` sobre su valor. Sin `deleteTagBinding` sobre cuentas,
  buckets ni llaveros no deberían poder quitar la etiqueta de lo protegido (prueba
  `ningun_rol_del_pipeline_liga_etiquetas` de `stages/0-bootstrap/tests/`; en GCP, HYPOTHESIS).
- **Los permisos de objeto de Cloud Storage no se niegan:** los prefijos del estado se separan
  solo con condiciones de IAM (ADR 0010).
- **Permisos sin condición entre entornos:** los cuatro riesgos residuales y la tabla del ADR
  0029 §9 (Compute sin condición, un MIG con la plantilla de prod, un clúster con nombre de prod
  creado por otro entorno y los servicios sin condición o con condición parcial). Lo frenan que
  solo el trabajo `apply` de `_terraform-root.yml` en `main`, con su evento y con el entorno de
  GitHub obtiene esa cuenta, y que todo cambio pasa por un PR con plan revisado.
- **La regla 4 no tiene excepción:** ningún agente de servicio debería necesitar crear llaves
  administradas por el usuario, pero `public:all` también los incluye (HYPOTHESIS, punto 155).
- **Quien puede integrar a `main` o lanzar un flujo de `main`** obtiene, a través del pipeline,
  las cuentas que escriben. Lo frenan la revisión de los PR y los revisores de los entornos de
  GitHub ([`pipeline.md`](../pipeline.md) §4).
- **Las concesiones delegadas limitan roles, no destinatarios:** `tf-base` puede dar los roles de
  sus dos listas a cualquier identidad del proyecto.
- **`<prefix>TfSecretContainerAdmin` permite darse `secretAccessor`** sobre cualquier secreto (lo
  necesita para darlo a las cuentas de ejecución). La tercera regla de la denegación le niega
  leer el valor. `tf-net` queda fuera de esa regla para leer la llave de la VPN real.
- **`tf-read` lee todos los estados** y la toma cualquier trabajo del repositorio, también los de
  un PR (punto 122).

Primer apply: la política de denegación y la etiqueta, los roles personalizados, las condiciones
por nombre de KMS, Storage, Cloud SQL, GKE y Backup and DR, las dos concesiones delegadas, el
mapeo de `attribute.deploy` (valor real de `job_workflow_ref` y `event_name`) y que adjuntar
cuentas con la regla de tokens sin condición funcione (`VERIFICAR-EN-APPLY` de
`stages/0-bootstrap/` y puntos 90 a 93, 123, 124, 127 y 152 a 156 de
[`pendientes-apply.md`](../pendientes-apply.md)).
