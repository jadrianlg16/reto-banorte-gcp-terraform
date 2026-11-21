# ADR 0023: Endurecimiento de la identidad del pipeline

## Estado

Aceptado, 2026-11-21. Completa los ADR 0007, 0010 y 0015.

Tipo: Aclaración.

## Contexto

Las cinco cuentas de etapa (`<prefix>-tf-<etapa>`, ADR 0017) aplican la infraestructura con
Workload Identity Federation (ADR 0007). La revisión independiente encontró caminos por los que
una de ellas, o quien controle el repositorio, obtenía más de lo que su etapa necesita:

- El proveedor de WIF y el `principalSet` confiaban en el **nombre** del repositorio
  (`assertion.repository`). La guía de WIF para pipelines de Google advierte que un nombre de
  repositorio o de dueño se puede volver a registrar si se borra o se renombra; los IDs
  numéricos no se reutilizan.
- `1-org` tiene `roles/iam.securityAdmin` y `roles/resourcemanager.folderAdmin` en la
  organización. Por herencia cubren la carpeta `bootstrap`: podía darse permiso para tomar la
  identidad de las cuentas 2 a 5 o ampliar su acceso al bucket de estado.
- `5-workloads` recibía roles en las carpetas de entorno, que también contienen el host
  `net-spoke` de la etapa 3: `compute.securityAdmin` le permitía cambiar el firewall del host y
  `iam.serviceAccountUser` de carpeta anulaba el `actAs` por cuenta de la etapa 4.
- `2-security` tenía el rol predefinido de administrador de Secret Manager (incluye
  `secretmanager.versions.access`) y un `projectIamAdmin` sin condición en `security`: el
  pipeline podía leer valores de secretos, en contra del ADR 0015.

## Decisión

- **WIF por IDs numéricos (etapa 0).** Variables obligatorias `github_repository_id` y
  `github_repository_owner_id` (solo dígitos; `gh api repos/<dueño>/<repositorio> --jq '.id,
  .owner.id'`). `attribute_condition` exige
  `assertion.repository_id == "<id>" && assertion.repository_owner_id == "<id del dueño>"`; el
  mapeo agrega `attribute.repository_id` y `attribute.repository_owner_id` y conserva
  `attribute.repository`, `attribute.ref` y `attribute.environment`; cada cuenta de etapa da
  `roles/iam.workloadIdentityUser` a
  `principalSet://iam.googleapis.com/<pool>/attribute.repository_id/<github_repository_id>`.
  `github_repository` queda solo como dato legible (descripción del proveedor y registros).
- **Política de denegación en la carpeta `bootstrap` (etapa 0, `deny_policy.tf`).**
  `google_iam_deny_policy.bootstrap_folder` niega al principal de la cuenta de `1-org` cambiar
  el IAM, mover o borrar la carpeta y el proyecto semilla; cambiar el IAM de las cuentas de
  servicio, tomar su identidad (`actAs`, `getAccessToken`, `getOpenIdToken`,
  `implicitDelegation`, `signBlob`, `signJwt`), cambiarlas, borrarlas, deshabilitarlas o crearles
  llaves; cambiar el IAM, la configuración o borrar el bucket de estado; y cambiar el IAM o la
  llave del estado o destruir sus versiones. Una denegación se impone a cualquier permiso
  concedido. Quien corre la etapa 0 necesita además `roles/iam.denyAdmin` en la organización.
- **5-workloads solo en sus proyectos de servicio.** `1-org` ya no le da ningún rol. `4-projects`,
  que crea los proyectos de servicio, le da en cada uno los 13 roles de los recursos que crea la
  etapa 5 (`backupdr.admin`, `certificatemanager.editor`, `cloudsql.admin`,
  `compute.instanceAdmin.v1`, `compute.loadBalancerAdmin`, `compute.securityAdmin`,
  `container.admin`, `file.editor`, `gkebackup.admin`, `monitoring.editor`, `redis.admin`,
  `run.admin`, `storage.admin`), `roles/resourcemanager.projectIamAdmin` con la condición
  `api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly(['roles/cloudsql.client',
  'roles/cloudsql.instanceUser'])`, `roles/iam.serviceAccountAdmin` solo sobre la cuenta
  `workload` (para el enlace de Workload Identity) y `roles/compute.networkViewer` en el host.
  El uso de subredes y de etiquetas seguras sigue siendo por subred y por valor.
- **Concesiones delegadas de 4-projects en las carpetas de entorno (etapa 1).**
  `projectIamAdmin` condicionado a `roles/compute.networkUser`, `roles/compute.networkViewer` y
  `roles/container.hostServiceAgentUser`, para dar esos roles en el host del spoke.
- **Secretos sin acceso a valores.** La etapa 0 crea un segundo rol personalizado de
  organización, `<prefix>TfSecretContainerAdmin` (salida `secret_container_admin_role_id`):
  `secretmanager.secrets.{create,delete,get,list,update}` y `secretmanager.locations.{get,list}`,
  sin permisos de versiones ni `secrets.setIamPolicy`. `1-org` lo da a `2-security` en
  `security`. `2-security` ya no tiene `projectIamAdmin` en ningún ámbito: el rol personalizado
  de `4-projects` sobre `security` (`kms_secret_iam_role_id`) lo asigna `1-org`, dueña del
  proyecto.
- **Lecturas de estado mínimas (etapa 0).** `3-networks` solo lee `1-org` y `5-workloads` ya no
  lee `1-org`: se otorga lo que cada raíz lee, no todo lo que permitía la tabla de §6.1.

## Alternativas consideradas

- **Condicionar WIF por `attribute.ref` o `attribute.environment`.** Cierra el riesgo de que
  cualquier rama tome la identidad de las cuentas, pero exige cuentas de solo lectura separadas
  para los `plan` de los PR. No se construye en esta ronda.
- **Quitar `iam.securityAdmin` de organización a `1-org`.** Rechazada: es la etapa que
  administra el IAM por grupos de la organización.
- **`projectIamAdmin` condicional para 2-security en `security`.** Se probó y se descartó: la
  condición limita los roles, no a quién se asignan, así que `2-security` podía darse a sí misma
  el rol de `4-projects` y con él `secretAccessor`.

## Consecuencias

Riesgos residuales (análisis de la documentación de Google, sin probar en GCP):

- **WIF sigue filtrando solo por repositorio:** cualquier rama o flujo del repositorio (incluido
  un PR desde una rama del mismo repositorio) puede tomar la identidad de las cuentas de etapa
  ([`pipeline.md`](../pipeline.md) §5).
- **La política de denegación no se protege a sí misma:** los permisos `iam.denypolicies.*` no
  se pueden negar; `1-org` podría darse `roles/iam.denyAdmin` en la organización y borrarla. Queda
  en los registros de actividad administrativa.
- **Los permisos de objeto de Cloud Storage no se niegan:** `1-org` los necesita para su propio
  prefijo y una condición de denegación solo admite etiquetas. Si `1-org` se diera un rol de
  Storage en la organización, podría leer otros prefijos del estado.
- **4-projects puede darse `secretAccessor`:** su rol personalizado incluye
  `secretmanager.secrets.setIamPolicy` (lo necesita para dar `secretAccessor` a las cuentas de
  ejecución), y una concesión delegada no se admite en un secreto.
- **Las concesiones delegadas limitan roles, no destinatarios:** `4-projects` puede dar
  `networkUser`, `networkViewer` o `hostServiceAgentUser` en el host a cualquier identidad, y
  `5-workloads` puede dar `cloudsql.client` e `instanceUser` a cualquier identidad en su
  proyecto de servicio.
- **`serviceAccountAdmin` sobre la cuenta `workload`** también deja a `5-workloads` deshabilitarla
  o borrarla. Un rol personalizado más estrecho es posible; no se construyó.

Primer apply: la política de denegación (punto 32), los roles personalizados (punto 33), el rol
personalizado asignado en un proyecto (punto 35), la concesión delegada en carpetas y en
proyectos (punto 28) y el enlace de Workload Identity (punto 46) de
[`docs/pendientes-apply.md`](../pendientes-apply.md).
