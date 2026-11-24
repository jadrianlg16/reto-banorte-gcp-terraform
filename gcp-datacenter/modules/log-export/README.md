# Módulo `log-export`

Crea un bucket de Cloud Storage para logs y, si se indica `parent = "projects/<id>"`, el sink
de Logging del proyecto que exporta hacia él, junto con el permiso
`roles/storage.objectCreator` para la identidad que escribe el sink. En el diseño de un solo
proyecto (ADR 0029 §7) el sink es de proyecto: ya no hay sinks agregados de organización ni de
carpeta. La especificación (sección "Componentes del datacenter", registro y auditoría) pide un
bucket de logs con retención bloqueable: por eso la política de retención siempre existe
(`retention_days`, de 30 a 36 500 días) y su bloqueo lo controla `retention_locked`, que es
**irreversible** una vez aplicado. Además quedan como valores fijos: CMEK obligatorio
(`kms_key`), acceso uniforme, prevención de acceso público `enforced`, versionado activo y sin
`force_destroy`. Las versiones no actuales se borran cuando vence la retención.

Notas de uso:

- El sink usa una identidad de escritura propia (`unique_writer_identity = true`).
- `exclusions` descarta entradas antes de exportarlas. `1-base` excluye los registros de acceso
  a datos del propio bucket de logs: con `DATA_WRITE` de Cloud Storage activo, cada escritura
  del sink generaría otra entrada que volvería al bucket.
- Con `parent = null` solo se crea el bucket: sirve cuando el sink lo crea otra raíz, que
  recibe la salida `destination`.
- El módulo da al agente de Cloud Storage del proyecto permiso para cifrar con `kms_key`
  (`grant_kms_to_storage_agent`). La llave debe estar en la misma ubicación que el bucket.
- El filtro por defecto exporta los registros de auditoría.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
