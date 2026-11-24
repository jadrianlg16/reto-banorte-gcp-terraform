# ADR 0018: La etapa 1 crea la llave KMS del bucket de logs de auditoría

## Estado

Aceptado, 2026-11-21. Enmendado el mismo día: el tema de Pub/Sub de hallazgos de SCC guarda
mensajes solo en la región de su llave, con `enforce_in_transit`. Enmendado el 2026-11-24: con
el proyecto único ([ADR 0029](0029-un-solo-proyecto.md) §4 y §7) la llave la crea `1-base`, en
el llavero común `<prefix>-common-sec-keyring-<código>` de `primary_region` con las llaves
`logs` y `pubsub`, y el sink es de proyecto (`parent = "projects/<id>"`), no agregado de
organización. Ya no hay proyectos `logging` ni `security`.

Tipo: Aclaración.

## Contexto

`1-base` crea el sink de proyecto hacia un bucket de logs con retención (módulo `log-export`
con `parent = "projects/<id>"`, filtro de auditoría y la exclusión `bucket-de-logs`), en el
proyecto único. `log-export` exige CMEK (`kms_key` obligatoria, en la misma ubicación que el
bucket). Es el mismo problema de orden que resolvió el ADR 0008 para el bucket de estado: crear
el bucket sin CMEK y cambiar la llave después no recifraría los objetos ya escritos. (En el
diseño de varios proyectos, la etapa 1 creaba un sink agregado de la organización hacia el
proyecto `logging` y las llaves de las cargas las creaba la etapa 2.)

## Decisión

`1-base` usa el módulo `kms` (`environment = "common"`) para crear, en el proyecto único y en
`primary_region` (la ubicación del bucket de logs), el llavero común con la llave `logs`
(rotación `key_rotation_period`, 90 días por defecto, y `prevent_destroy`). `log-export` da
`roles/cloudkms.cryptoKeyEncrypterDecrypter` sobre la llave al agente de servicio de Cloud
Storage del proyecto (`grant_kms_to_storage_agent = true`) antes de crear el bucket
`<prefix>-common-ops-audit-logs[-<name_suffix>]`. La identidad que escribe el sink recibe
`roles/storage.objectCreator` sobre el bucket y no necesita permisos de KMS. Las llaves de los
entornos también las crea `1-base`, en llaveros aparte (`<prefix>-<env>-sec-keyring-<código>`).

El mismo llavero tiene la llave `pubsub` (regional, `primary_region`) del tema de hallazgos de
SCC (`<prefix>-common-ops-scc-findings`). Como la llave es regional, el tema limita el
almacenamiento de mensajes a esa región (`allowed_persistence_regions = [primary_region]`) y lo
impone en tránsito (`enforce_in_transit = true`), como pide la guía de CMEK de Pub/Sub.

## Alternativas consideradas

- **Mover el sink y el bucket a la etapa 2.** Rechazada en el diseño de varios proyectos: los
  eventos de las etapas 1 y 2 quedarían sin exportar durante el primer despliegue. Con el
  ADR 0029 las dos etapas se unieron en `1-base`.
- **Llave de logs en el llavero de un entorno (por ejemplo, prod).** Rechazada: ataría el
  registro de auditoría de todo el proyecto al ciclo de vida y a los permisos de un entorno.
  (Antes: llave en el proyecto `security`, rechazada por la misma razón.)
- **Destino del sink en un bucket de Cloud Logging en lugar de Cloud Storage.** Posible, pero la
  especificación pide un bucket con retención bloqueable, que `log-export` modela con la
  política de retención de Cloud Storage. Rechazada.

## Consecuencias

- Positivas: los logs de auditoría están cifrados con CMEK desde el primer evento exportado; la
  llave vive junto a los datos que protege. Con el perímetro opcional, queda dentro de él como
  todo el proyecto.
- Negativas: un llavero común más que el equipo de seguridad debe vigilar, además de los de cada
  entorno y del de la etapa 0. `tf-base` tiene `cloudkms.admin` sobre todos los llaveros salvo el
  del estado, incluido este (contrato §6.3). Si `log_retention_locked = true`, la retención es
  irreversible; si además
  la llave se deshabilita, los logs retenidos quedan ilegibles y no se pueden borrar. Por eso la
  llave tiene `prevent_destroy` y solo el grupo de seguridad debe poder administrarla.
- Con organización, `gcp.resourceLocations` debe admitir la ubicación elegida para el llavero y
  el bucket.
- Si cae `primary_region`, las notificaciones de SCC no se entregan hasta que vuelva (la llave
  del tema es regional); se acepta (ADR 0022). Que SCC publique en un tema con
  `enforce_in_transit` se verifica en el primer apply (punto 34).
- Primer apply: que el agente de Cloud Storage tenga el permiso sobre la llave antes de crear el
  bucket y que el bloqueo se aplique sobre un bucket ya creado (`VERIFICAR-EN-APPLY` en
  `modules/log-export/main.tf`); sin entrada propia en §12, se propone agregarla a
  [`docs/pendientes-apply.md`](../pendientes-apply.md) (quedó como punto 15). Relacionados:
  punto 3 (ubicaciones) y punto 27 (en el diseño de varios proyectos, el número del proyecto
  `logging` se pasaba en `project_number` porque el proyecto se creaba en el mismo plan; en el
  proyecto único `1-base` no lo pasa y el agente se consulta con `project_id`).
