# ADR 0018: La etapa 1 crea la llave KMS del bucket de logs de auditoría

## Estado

Aceptado, 2026-11-21. Enmendado el mismo día: el tema de Pub/Sub de hallazgos de SCC guarda
mensajes solo en la región de su llave, con `enforce_in_transit`.

Tipo: Aclaración.

## Contexto

La etapa 1 (`1-org`) crea el sink agregado de la organización hacia un bucket de logs con
retención (módulo `org` para el sink y módulo `log-export` con `parent = null` para el bucket,
en el proyecto `<prefix>-common-logging`). `log-export` exige CMEK (`kms_key` obligatoria, en la
misma ubicación que el bucket). Las llaves de las cargas las crea la etapa 2, que corre después.
Es el mismo problema de orden que resolvió el ADR 0008 para el bucket de estado, y crear el
bucket sin CMEK y cambiar la llave después no recifraría los objetos ya escritos.

## Decisión

La etapa 1 usa el módulo `kms` (`environment = "common"`) para crear, en el proyecto `logging`,
un llavero en la ubicación del bucket de logs y una llave para él (rotación `7776000s`,
`prevent_destroy`). `log-export` da `roles/cloudkms.cryptoKeyEncrypterDecrypter` sobre la llave
al agente de servicio de Cloud Storage del proyecto `logging`
(`grant_kms_to_storage_agent = true`) antes de crear el bucket. La identidad que escribe el sink
recibe `roles/storage.objectCreator` sobre el bucket y no necesita permisos de KMS.

El mismo llavero tiene la llave `pubsub` (regional, `primary_region`) del tema de hallazgos de
SCC (`<prefix>-common-ops-scc-findings`). Como la llave es regional, el tema limita el
almacenamiento de mensajes a esa región (`allowed_persistence_regions = [primary_region]`) y lo
impone en tránsito (`enforce_in_transit = true`), como pide la guía de CMEK de Pub/Sub.

## Alternativas consideradas

- **Mover el sink y el bucket a la etapa 2.** Rechazada: el contrato (§7.1) ubica el sink de
  auditoría en la etapa de organización, y los eventos de las etapas 1 y 2 quedarían sin
  exportar durante el primer despliegue.
- **Llave en el proyecto `security`, creada por la etapa 1.** Rechazada: la etapa 1 crearía
  recursos en un proyecto cuyo dueño es la etapa 2, y una caída del proyecto `security`
  afectaría al registro de auditoría que debería documentarla.
- **Destino del sink en un bucket de Cloud Logging en lugar de Cloud Storage.** Posible, pero la
  especificación pide un bucket con retención bloqueable, que `log-export` modela con la
  política de retención de Cloud Storage. Rechazada.

## Consecuencias

- Positivas: los logs de auditoría están cifrados con CMEK desde el primer evento exportado; la
  llave vive junto a los datos que protege y fuera del perímetro de prod (ADR 0019).
- Negativas: otro llavero fuera de `security` que el equipo de seguridad debe vigilar, además
  del de la etapa 0. Si `log_retention_locked = true`, la retención es irreversible; si además
  la llave se deshabilita, los logs retenidos quedan ilegibles y no se pueden borrar. Por eso la
  llave tiene `prevent_destroy` y solo el grupo de seguridad debe poder administrarla.
- `gcp.resourceLocations` debe admitir la ubicación elegida para el llavero y el bucket.
- Si cae `primary_region`, las notificaciones de SCC no se entregan hasta que vuelva (la llave
  del tema es regional); se acepta (ADR 0022). Que SCC publique en un tema con
  `enforce_in_transit` se verifica en el primer apply (punto 34).
- Primer apply: que el agente de Cloud Storage tenga el permiso sobre la llave antes de crear el
  bucket y que el bloqueo se aplique sobre un bucket ya creado (`VERIFICAR-EN-APPLY` en
  `modules/log-export/main.tf`); sin entrada propia en §12, se propone agregarla a
  [`docs/pendientes-apply.md`](../pendientes-apply.md) (quedó como punto 15). Relacionados:
  punto 3 (ubicaciones) y punto 27 (la etapa 1 pasa a `log-export` el número del proyecto
  `logging` en `project_number`, para que el agente se consulte en el apply).
