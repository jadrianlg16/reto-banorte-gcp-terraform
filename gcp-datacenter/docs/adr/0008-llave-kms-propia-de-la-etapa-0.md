# ADR 0008: La etapa 0 crea su propia llave KMS para el bucket de estado

## Estado

Aceptado, 2026-11-20. Enmendado el 2026-11-21: el llavero y el bucket ya no están en
`primary_region`, sino en la multirregión `us` / `US` o en una doble región (ADR
[0022](0022-estado-y-conmutacion-sin-depender-de-la-region-primaria.md)).
Enmendado el 2026-11-24: con el proyecto único ([ADR 0029](0029-un-solo-proyecto.md)) ya no hay
proyecto semilla ni proyecto `security`: el llavero del estado, el bucket y las llaves de los
entornos (que crea `1-base`) están en el mismo proyecto. La separación entre la llave del estado
y las demás la dan las condiciones de IAM (`tf-base` tiene `cloudkms.admin` salvo sobre el
llavero del estado) y la etiqueta de protección con la política de denegación (ADR 0023).

Tipo: Aclaración.

## Contexto

La especificación pide que el bucket de estado remoto, que crea la etapa 0, esté cifrado con
CMEK, y a la vez ubica KMS en una etapa posterior (en este diseño, `1-base`). Esa etapa corre
después de la 0 y su propio estado vive en ese bucket, así que no puede proveer la llave que lo
cifra. Cambiar la llave predeterminada de un bucket después de creado solo afecta a los objetos
nuevos; los estados escritos antes seguirían con cifrado administrado por Google hasta
reescribirse.

## Decisión

`0-bootstrap` usa el módulo `kms` con `environment = "bootstrap"` para crear, en el proyecto
único, un llavero en `lower(state_bucket_location)` (por defecto la multirregión `us`:
`<prefix>-bootstrap-sec-keyring-us`) y una llave `state` (`ENCRYPT_DECRYPT`, rotación
`7776000s`, `prevent_destroy`). Antes de crear el bucket da
`roles/cloudkms.cryptoKeyEncrypterDecrypter` sobre la llave al agente de servicio de Cloud
Storage del proyecto. El bucket de estado nace en `state_bucket_location` (`US` por
defecto) o en la doble región de `state_bucket_dual_regions`, con esa llave como
predeterminada, versionado, acceso uniforme y sin acceso público. La llave va en la ubicación
de KMS que corresponde a la del bucket porque la CMEK de Cloud Storage lo exige (ADR 0022); una
llave en `primary_region` no sirve para un bucket multirregional. La salida `state_kms_key_id` la publica para
las demás etapas. La etapa 0 arranca con estado local y lo migra al bucket con
`terraform init -migrate-state` (paso manual permitido y documentado en su runbook).

## Alternativas consideradas

- **Crear el bucket con cifrado de Google y activar CMEK cuando exista la llave de `1-base`.**
  Rechazada: deja una ventana sin CMEK y los objetos ya escritos no se recifran solos.
- **Crear la llave del estado en el llavero de un entorno o en el común de `1-base`.** Rechazada:
  `1-base` corre después y la cuenta que la administra (`tf-base`) alcanzaría la llave del
  estado. (Antes: llave en el proyecto `security`, rechazada por la misma dependencia de orden.)
- **Llave creada a mano con `gcloud` antes de la etapa 0.** Rechazada: quedaría fuera de
  Terraform, sin rotación ni `prevent_destroy` declarados y sin pasar por las políticas de
  Conftest (regla 6 de §9.1).

## Consecuencias

- Positivas: el estado está cifrado con CMEK desde el primer objeto; la llave del estado y la
  de las cargas quedan en llaveros distintos, con administradores distintos: la del estado solo
  la administra quien aplica `0-bootstrap`.
- Negativas: la separación ya no la da un proyecto, sino una condición de IAM y la etiqueta de
  protección (HYPOTHESIS sin organización, ADR 0023). Los llaveros no se pueden borrar y la llave
  tiene `prevent_destroy`, así que la etapa 0 no se puede destruir por completo.
- La ubicación del bucket y del llavero no se cambia después de crearlos: se elige antes del
  primer apply (runbook 01). Sin la región primaria, el estado y su llave siguen disponibles.
- Perder la llave o deshabilitar sus versiones deja ilegible todo el estado; las versiones
  antiguas siguen siendo necesarias para leer estados escritos antes de cada rotación.
- Quien lee el estado no necesita permisos de KMS: el cifrado y descifrado los hace el agente de
  servicio de Cloud Storage. El control de acceso es el IAM del bucket (ADR 0010).
- El mismo criterio se aplica al bucket de logs de `1-base` (ADR 0018).
- Primer apply: la migración del estado local y que el agente de Cloud Storage tenga el permiso
  antes de crear el bucket; no tiene entrada propia en §12 y se propone
  agregarla a [`docs/pendientes-apply.md`](../pendientes-apply.md) junto al runbook de la
  etapa 0 (quedó como punto 13). En el diseño de varios proyectos el agente se consultaba con el
  número del proyecto semilla, que se creaba en el mismo plan (punto 27); el proyecto único ya
  existe antes de `0-bootstrap`. Si se usa una doble región, que
la combinación de regiones y `ASYNC_TURBO` sea válida con la llave en `us` (punto 31).
