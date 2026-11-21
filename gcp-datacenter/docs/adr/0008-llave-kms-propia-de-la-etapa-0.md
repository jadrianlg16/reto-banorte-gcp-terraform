# ADR 0008: La etapa 0 crea su propia llave KMS para el bucket de estado

## Estado

Aceptado, 2026-11-20.

Tipo: Aclaración.

## Contexto

La especificación pide que el bucket de estado remoto, que crea la etapa 0, esté cifrado con
CMEK, y a la vez ubica KMS en la etapa 2 (seguridad), en el proyecto `security`. La etapa 2
corre dos etapas después de la 0 y su propio estado vive en ese bucket, así que no puede
proveer la llave que lo cifra. Cambiar la llave predeterminada de un bucket después de creado
solo afecta a los objetos nuevos; los estados escritos antes seguirían con cifrado
administrado por Google hasta reescribirse.

## Decisión

La etapa 0 usa el módulo `kms` con `environment = "bootstrap"` para crear, en el proyecto
semilla (`<prefix>-bootstrap-seed`), un llavero en `primary_region` y una llave `state`
(`ENCRYPT_DECRYPT`, rotación `7776000s`, `prevent_destroy`). Antes de crear el bucket da
`roles/cloudkms.cryptoKeyEncrypterDecrypter` sobre la llave al agente de servicio de Cloud
Storage del proyecto semilla. El bucket de estado nace con esa llave como predeterminada,
versionado, acceso uniforme y sin acceso público. La salida `state_kms_key_id` la publica para
las demás etapas. La etapa 0 arranca con estado local y lo migra al bucket con
`terraform init -migrate-state` (paso manual permitido y documentado en su runbook).

## Alternativas consideradas

- **Crear el bucket con cifrado de Google y activar CMEK cuando exista la llave de la etapa 2.**
  Rechazada: deja una ventana sin CMEK y los objetos ya escritos no se recifran solos.
- **Crear la llave del estado en el proyecto `security` desde la etapa 0.** Rechazada: la etapa
  0 tendría que crear o conocer el proyecto `security`, que es de la etapa 1, y la etapa 2
  tendría que importar o tolerar una llave ajena en su proyecto.
- **Llave creada a mano con `gcloud` antes de la etapa 0.** Rechazada: quedaría fuera de
  Terraform, sin rotación ni `prevent_destroy` declarados y sin pasar por las políticas de
  Conftest (regla 6 de §9.1).

## Consecuencias

- Positivas: el estado está cifrado con CMEK desde el primer objeto; la llave del estado y la
  de las cargas quedan en proyectos distintos, con administradores distintos.
- Negativas: hay un llavero fuera del proyecto `security`, que el equipo de seguridad debe
  vigilar aparte. Los llaveros no se pueden borrar y la llave tiene `prevent_destroy`, así que
  la etapa 0 no se puede destruir por completo.
- Perder la llave o deshabilitar sus versiones deja ilegible todo el estado; las versiones
  antiguas siguen siendo necesarias para leer estados escritos antes de cada rotación.
- Quien lee el estado no necesita permisos de KMS: el cifrado y descifrado los hace el agente de
  servicio de Cloud Storage. El control de acceso es el IAM del bucket (ADR 0010).
- El mismo criterio se aplica al bucket de logs de la etapa 1 (ADR 0018).
- Primer apply: la migración del estado local y que el agente de Cloud Storage tenga el permiso
  antes de crear el bucket; no tiene entrada propia en §12 y se propone
  agregarla a [`docs/pendientes-apply.md`](../pendientes-apply.md) junto al runbook de la
  etapa 0.
