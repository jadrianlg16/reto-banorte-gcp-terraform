# ADR 0010: Un bucket de estado con un prefijo por etapa e IAM condicionado por prefijo

## Estado

Aceptado, 2026-11-20.

Tipo: Aclaración.

## Contexto

La especificación pide que cada cuenta de servicio del pipeline escriba solo su prefijo del
estado y, a la vez, que cada etapa lea las salidas de la anterior. Tomadas al pie de la letra,
"solo su prefijo" impediría el `terraform_remote_state`. Hay siete cuentas o raíces
(`0-bootstrap` a `5-workloads`, con hub y spokes en la etapa 3) y un solo bucket en el proyecto
semilla (ADR 0008).

## Decisión

Un bucket, un prefijo por raíz (`1-org`, `2-security`, `3-networks/hub`, `3-networks/<env>`,
`4-projects/<env>`, `5-workloads/<env>`; tabla de §6.1). `backend.tf` fija solo el prefijo; el
bucket entra por `-backend-config`. Las lecturas se concentran en `remote_state.tf` y ninguna
raíz lee un prefijo fuera de su fila de §6.1. La etapa 0 da a cada cuenta
`<prefix>-tf-<etapa>`:

- `roles/storage.objectAdmin` con una condición de IAM sobre los objetos de su prefijo
  (`resource.name.startsWith("projects/_/buckets/<bucket>/objects/<prefijo>/")`);
- `roles/storage.objectViewer` con condiciones equivalentes para los prefijos de la columna
  "Lee además".

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
  (por ejemplo para los espacios de trabajo), así que con la condición tal cual el listado se
  espera que falle. Salidas posibles: agregar a la condición el caso del bucket
  (`resource.type == "storage.googleapis.com/Bucket"`), con lo que cada cuenta vería los nombres
  de todos los objetos pero no su contenido; o pasar a carpetas administradas.
- El bloqueo (`<prefijo>/default.tflock`) cae dentro del prefijo propio, así que la escritura
  condicionada lo cubre.
- Primer apply: listado de objetos del backend con IAM condicionado por prefijo (punto 1 de
  [`docs/pendientes-apply.md`](../pendientes-apply.md)); si falla, aplicar una de las salidas
  anteriores y actualizar este ADR.
