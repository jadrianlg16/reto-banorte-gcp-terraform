# ADR 0010: Un bucket de estado con un prefijo por etapa e IAM condicionado por prefijo

## Estado

Aceptado, 2026-11-20. Enmendado el 2026-11-21: lecturas mínimas por cuenta (menos que lo que
permite la columna "Lee además" de §6.1) y cláusula de listado ya construida. Enmendado el
2026-11-24: con el proyecto único ([ADR 0029](0029-un-solo-proyecto.md) §2) los prefijos son
`1-base`, `2-networks/hub`, `2-networks/<env>` y `3-workloads/<env>`; hay una cuenta que escribe
por raíz y entorno, y la cuenta de solo lectura `tf-read` lee todo el bucket para los `plan`.

Tipo: Aclaración.

## Contexto

La especificación pide que cada cuenta de servicio del pipeline escriba solo su prefijo del
estado y, a la vez, que cada etapa lea las salidas de la anterior. Tomadas al pie de la letra,
"solo su prefijo" impediría el `terraform_remote_state`. Hay nueve cuentas (ocho que escriben,
una por raíz, y `tf-read`) y un solo bucket en el proyecto único (ADR 0008).

## Decisión

Un bucket, un prefijo por raíz (`0-bootstrap`, `1-base`, `2-networks/hub`, `2-networks/<env>`,
`3-workloads/<env>`; tabla de §6.1 del contrato). `backend.tf` fija solo el prefijo; el bucket
entra por `-backend-config`. Las lecturas se concentran en `remote_state.tf` y ninguna raíz lee
un prefijo fuera de su fila de §6.1. `0-bootstrap` da a cada cuenta que escribe:

- `roles/storage.objectAdmin` con una condición de IAM sobre los objetos de su prefijo
  (`resource.name.startsWith("projects/_/buckets/<bucket>/objects/<prefijo>/")`);
- `roles/storage.objectViewer` con condiciones equivalentes para los prefijos de la columna
  "Lee además".

Las lecturas son las que las raíces de cada cuenta usan de verdad (`reads` de `local.stage_roots`
en `stages/0-bootstrap/service_accounts.tf`, publicadas en la salida `state_iam_conditions`):
`tf-base` lee `0-bootstrap`; `tf-net` (hub) no lee nada; `tf-net-<env>` lee `2-networks/hub`; y
`tf-wl-<env>` lee `1-base` y `2-networks/<env>`. Las condiciones empiezan con
`resource.type == "storage.googleapis.com/Bucket"` para que el backend pueda listar.
`tf-read` tiene `roles/storage.objectViewer` sobre todo el bucket, sin condición: los `plan`
corren con ella y `-lock=false` (ADR 0025).

Leer aguas arriba es la interpretación mínima que cumple las dos exigencias.

## Alternativas consideradas

- **Un bucket por etapa.** Aísla por recurso sin condiciones, pero multiplica buckets,
  políticas de IAM y configuración de CMEK, y el backend necesitaría un bucket distinto por
  raíz en `-backend-config`. Queda como plan B si fallan las dos opciones de abajo.
- **Carpetas administradas de Cloud Storage con IAM propio.** Es la alternativa documentada en
  §6.2: una carpeta administrada por prefijo, con `objectAdmin` u `objectViewer` sobre ella. La
  documentación permite usarlas en condiciones de políticas de permiso; que el backend `gcs`
  liste y bloquee correctamente dentro de una carpeta administrada está por verificar.
- **IAM sin condiciones a nivel de bucket.** Rechazada: cualquier etapa podría sobrescribir el
  estado de otra, incluido el de prod.

## Consecuencias

- Positivas: un solo bucket, una sola llave, un solo lugar donde auditar el estado.
- Negativas y riesgo principal: la documentación de IAM de Cloud Storage (consultada el
  2026-11-21) dice que `storage.objects.list` se otorga a nivel de bucket y que la condición
  `resource.name` no puede restringir el listado. El backend `gcs` lista objetos del prefijo
  (por ejemplo para los espacios de trabajo). Por eso la condición incluye el caso del bucket
  (`resource.type == "storage.googleapis.com/Bucket"`): cada cuenta ve los nombres de todos los
  objetos pero no su contenido. Si aun así el backend falla, la salida es pasar a carpetas
  administradas.
- El bloqueo (`<prefijo>/default.tflock`) cae dentro del prefijo propio, así que la escritura
  condicionada lo cubre. `tf-read` no puede escribirlo; por eso los `plan` van con
  `-lock=false`.
- `tf-read` lee el estado de todas las raíces, incluido el secreto de la VPN del hub (ADR 0006):
  cualquier trabajo del repositorio puede tomar esa cuenta (ADR 0023).
- Primer apply: listado de objetos del backend con IAM condicionado por prefijo (punto 1 de
  [`docs/pendientes-apply.md`](../pendientes-apply.md)); si falla, aplicar una de las salidas
  anteriores y actualizar este ADR.
