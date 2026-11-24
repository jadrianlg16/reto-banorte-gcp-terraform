# ADR 0023: Endurecimiento de la identidad del pipeline

## Estado

Aceptado, 2026-11-21. Completa los ADR 0007, 0010 y 0015.

Enmendado el 2026-11-24: con el proyecto único ([ADR 0029](0029-un-solo-proyecto.md) §3 y §5)
se conservan los cuatro principios (WIF por IDs numéricos, política de denegación, roles
personalizados sin acceso a valores y lecturas de estado mínimas) y cambian los detalles: nueve
cuentas en lugar de cinco; WIF además por entorno de GitHub, con `tf-read` para los `plan`; la
política de denegación va en el proyecto y reconoce lo protegido por la etiqueta
`<prefix>-proteccion = etapa-0`; todos los roles de proyecto de las cuentas los da
`0-bootstrap`, condicionados por nombre donde el servicio lo admite; `tf-wl-<env>` usa el rol
`<prefix>TfServiceAccountManager` en lugar de `iam.serviceAccountAdmin`. El texto de abajo
describe el diseño vigente; el de varios proyectos vive en la rama `archivo/multiproyecto`.

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

## Decisión

- **WIF por IDs numéricos y por entorno (`stages/0-bootstrap/wif.tf` y
  `service_accounts.tf`).** Variables obligatorias `github_repository_id` y
  `github_repository_owner_id` (solo dígitos; `gh api repos/<dueño>/<repositorio> --jq '.id,
  .owner.id'`). `attribute_condition` exige
  `assertion.repository_id == "<id>" && assertion.repository_owner_id == "<id del dueño>"`; el
  mapeo trae `attribute.repository_id`, `attribute.repository_owner_id`, `attribute.repository`,
  `attribute.ref` y `attribute.environment`. `roles/iam.workloadIdentityUser`:
  - `tf-base` y `tf-net`: `principalSet://iam.googleapis.com/<pool>/attribute.environment/common`;
  - `tf-net-<env>` y `tf-wl-<env>`: `…/attribute.environment/<env>`;
  - `tf-read`: `…/attribute.repository_id/<github_repository_id>`.

  Un trabajo sin entorno de GitHub solo obtiene `tf-read`. `github_repository` queda solo como
  dato legible.
- **Etiqueta y política de denegación del proyecto (`stages/0-bootstrap/deny_policy.tf`).**
  Las condiciones de denegación solo admiten funciones de etiquetas
  ([deny](https://docs.cloud.google.com/iam/docs/deny-overview)), así que lo protegido se marca
  con la clave `<prefix>-proteccion` (padre `projects/<id>`) y el valor `etapa-0`, ligado al
  bucket de estado, al llavero del estado y a las nueve cuentas. La política
  `<prefix>-bootstrap-sec-deny-pipeline` niega a las nueve cuentas:
  - con la etiqueta: borrar el bucket o cambiar su configuración, su IAM y sus etiquetas; cambiar
    el IAM del llavero o de la llave, cambiar la llave o destruir versiones; cambiar el IAM de
    las cuentas, tomar su identidad (`actAs`, `getAccessToken`, `getOpenIdToken`,
    `implicitDelegation`, `signBlob`, `signJwt`), cambiarlas, borrarlas o deshabilitarlas;
  - sin condición: crear, cambiar o borrar pools y proveedores de WIF y roles personalizados,
    crear llaves de cuentas de servicio y borrar el proyecto.

  Una denegación se impone a cualquier permiso concedido. Quien aplica `0-bootstrap` necesita
  `roles/iam.denyAdmin` en el proyecto. `enable_protection_tags` y `enable_deny_policy` (ambas
  `true` por defecto) permiten apagarlas si no funcionan sin organización.
- **Roles de proyecto solo desde `0-bootstrap`, con condiciones**
  ([atributos](https://docs.cloud.google.com/iam/docs/conditions-resource-attributes)). Ninguna
  raíz de entorno da roles de proyecto a una cuenta del pipeline (regla de recursos únicos,
  contrato §7.5). Lista completa en el contrato §6.3; lo esencial:
  - `roles/storage.admin` solo con condición: buckets `<prefix>-common-` para `tf-base` y
    `<prefix>-<env>-` para `tf-wl-<env>`; ninguna alcanza el bucket de estado
    (`<prefix>-bootstrap-…`).
  - `tf-base` tiene `cloudkms.admin` con condición que excluye el llavero del estado.
  - `tf-wl-<env>` da IAM de llaves y secretos con `<prefix>TfKmsSecretIamGranter`, condicionado a
    los llaveros y secretos `<prefix>-<env>-` (formato exacto de la condición: HYPOTHESIS).
  - `roles/resourcemanager.projectIamAdmin` solo con la concesión delegada
    `api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([...])`: `tf-base`
    para los roles de lectura de los grupos y `tagUser` de los agentes; `tf-wl-<env>` para los
    roles mínimos de sus cuentas de ejecución y el rol del apagado.
  - Compute, GKE, Cloud Run, Cloud SQL, Memorystore, Filestore, cuentas de servicio y etiquetas,
    **sin condición** (una condición por nombre sobre un tipo que no la admite niega todo).
- **Cuentas de servicio sin `serviceAccountAdmin`.** `tf-wl-<env>` crea sus cuentas de ejecución
  con el rol personalizado `<prefix>TfServiceAccountManager` (crear, cambiar, borrar,
  deshabilitar y dar IAM sobre cuentas, sin `createTagBinding` ni `deleteTagBinding`), más
  `iam.serviceAccountUser` y `resourcemanager.tagUser`. `iam.serviceAccountAdmin` incluye
  `deleteTagBinding`, que no se puede negar: con `tagUser` dejaría quitar la etiqueta de
  protección de una cuenta del pipeline.
- **Secretos sin acceso a valores.** `<prefix>TfSecretContainerAdmin` (de `tf-base`):
  `secretmanager.secrets.{create,delete,get,list,update}` y `secretmanager.locations.{get,list}`,
  sin versiones ni `secrets.setIamPolicy`. Los roles personalizados viven en `0-bootstrap`
  (salida `custom_role_ids`), así que ninguna cuenta necesita `iam.roleAdmin`.
- **Lecturas de estado mínimas.** Cada cuenta escribe su prefijo y lee solo los de la lista
  `reads` de su raíz (contrato §6.1): el hub no lee nada, cada spoke lee `2-networks/hub` y las
  cargas leen `1-base` y `2-networks/<env>`. `tf-read` lee todo el bucket. Los `plan` corren con
  `tf-read` y `-lock=false` (ADR 0025).

## Alternativas consideradas

- **Condicionar WIF por `attribute.ref`.** Ataría cada cuenta a una rama y rompería los `plan`
  de los PR, que corren en ramas. Se eligió el entorno de GitHub, que además lleva revisores y
  reglas de rama configurables (`pipeline.md` §4).
- **Política de denegación en una carpeta `bootstrap`.** Era el diseño de varios proyectos; sin
  organización no hay carpetas (ADR 0029 §5).
- **`iam.serviceAccountAdmin` para `tf-wl-<env>`.** Rechazada: incluye `deleteTagBinding`
  (ver arriba).
- **Que `1-base` cree las cuentas de ejecución y dé `actAs` por cuenta.** Quitaría a
  `tf-wl-<env>` el `setIamPolicy` sobre cuentas a nivel de proyecto. Propuesta abierta del
  constructor; no se construyó porque cambia la regla de que cada entorno crea sus principales
  (ADR 0029 §4).

## Consecuencias

Riesgos residuales (análisis de la documentación de Google, sin probar en GCP):

- **Las etiquetas y la denegación en un proyecto sin organización son HYPOTHESIS**
  (`VERIFICAR-EN-APPLY` en `deny_policy.tf`). Si no funcionan, la protección queda en que ninguna
  cuenta tiene `storage.admin` sin condición, `iam.serviceAccountAdmin` ni `projectIamAdmin` sin
  condición. En ese caso `tf-wl-<env>`, con `setIamPolicy` sobre cuentas a nivel de proyecto
  (`<prefix>TfServiceAccountManager`) e `iam.serviceAccountUser`, podría darse acceso a otra
  cuenta del pipeline, por ejemplo a `tf-base`.
- **Algunos permisos no se pueden negar:** `iam.serviceAccounts.createTagBinding` y
  `deleteTagBinding`, `cloudkms.keyRings.deleteTagBinding` y `iam.denypolicies.*`. Ninguna cuenta
  tiene esos permisos sobre lo protegido ni `iam.denyAdmin`. Las cuentas de spoke tienen
  `resourcemanager.tagAdmin` en el proyecto, que alcanza también la clave de protección (su IAM
  y sus valores); sin permisos de enlace sobre cuentas, buckets ni llaves no deberían poder quitar
  la etiqueta de lo protegido (HYPOTHESIS, riesgo abierto).
- **Los permisos de objeto de Cloud Storage no se niegan:** los prefijos del estado se separan
  solo con condiciones de IAM (ADR 0010).
- **Permisos sin condición entre entornos:** una cuenta de dev puede, técnicamente, cambiar
  recursos de prod de Compute, GKE, Cloud Run, Cloud SQL, Memorystore y Filestore (ADR 0029 §9).
  Lo frenan que solo un trabajo del entorno `dev` obtiene esa cuenta y que todo cambio pasa por
  un PR con plan revisado.
- **WIF depende de la configuración manual de los entornos de GitHub:** sin reglas de rama en
  cada entorno, cualquier rama que declare `environment: prod` obtiene `tf-wl-prod`
  ([`pipeline.md`](../pipeline.md) §4 y §5).
- **Las concesiones delegadas limitan roles, no destinatarios:** `tf-wl-<env>` puede dar los
  roles de su lista a cualquier identidad del proyecto.
- **`<prefix>TfKmsSecretIamGranter` permite darse `secretAccessor`** sobre los secretos de su
  entorno (lo necesita para darlo a las cuentas de ejecución).
- **`orgpolicy.policyAdmin` de `tf-base`** solo se puede dar en la organización y alcanza a toda
  ella (solo con `org_id`).

Primer apply: la política de denegación y la etiqueta, los roles personalizados, las condiciones
por nombre de KMS y Secret Manager, la concesión delegada y el mapeo de `attribute.environment`
en trabajos sin entorno (`VERIFICAR-EN-APPLY` de `stages/0-bootstrap/` y puntos de
[`docs/pendientes-apply.md`](../pendientes-apply.md)).
