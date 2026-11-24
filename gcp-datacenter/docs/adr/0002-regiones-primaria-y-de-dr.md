# ADR 0002: Regiones primaria y de recuperación

## Estado

Aceptado, 2026-11-20. Enmendado el 2026-11-21: lo que la conmutación no puede depender de la
región primaria (estado, VPN de DR, balanceador interno por región) está en el ADR
[0022](0022-estado-y-conmutacion-sin-depender-de-la-region-primaria.md).
Enmendado el 2026-11-24: con el proyecto único ([ADR 0029](0029-un-solo-proyecto.md)) los
llaveros por ubicación los crea `1-base` (antes la etapa 2) y `gcp.resourceLocations` solo existe
si hay organización.

Tipo: Conforme.

## Contexto

La especificación, en su sección de recuperación ante desastres, propone una región primaria
y una secundaria en Estados Unidos y menciona una región en México como opción si hubiera
requisitos de residencia de datos. Varios componentes dependen del par de regiones: la réplica
de Cloud SQL (`cloud-sql`, `dr_region`), el bucket de doble región con turbo replication
(`storage`, `dual_region`), los llaveros de KMS por ubicación (`1-base`), la bóveda de Backup
and DR (`backup-dr`) y las subredes `*_dr` del plan de direccionamiento (§5).

## Decisión

`primary_region = "us-central1"` y `dr_region = "us-east4"`, ambas como variables de todas las
raíces que las usan. Los nombres de recursos regionales agregan el código corto que sale de un
mapa (`usc1`, `use4`, y `nas1` para `northamerica-south1`), nunca escrito a mano. `1-base`
crea además llaveros en la multirregión `us` para los buckets de doble región y los
repositorios de Artifact Registry, porque la llave de un bucket o de un repositorio debe estar
en la misma ubicación que él.

Nada que la conmutación necesite vive solo en la región primaria (ADR 0022): el bucket de
estado y su llave están en la multirregión `us` (etapa 0, `state_bucket_location`); el hub tiene
una segunda HA VPN en el router de `dr_region` (`enable_vpn_dr`, prioridad de anuncio mayor que
la primaria); el balanceador interno es uno por región con acceso global y `dr_active` agrega el
de DR sin tocar el primario; y las imágenes de contenedor están en un repositorio multirregional
(ADR 0024).

## Alternativas consideradas

- **`northamerica-south1` como primaria.** No se adopta sin un requisito explícito de
  residencia. Es la única región de GCP en México (Querétaro; consultado en la lista oficial
  de regiones el 2026-11-21), así que con residencia estricta no hay región de DR dentro del
  país: la recuperación tendría que ser entre zonas de la misma región, o la residencia tendría
  que admitir una región de DR fuera de México. Además, el bucket de doble región con turbo
  replication de este diseño pide dos regiones dentro de la misma multirregión (por verificar
  para `northamerica-south1`).
- **Una sola región con alta disponibilidad entre zonas.** Rechazada: la especificación pide
  una región secundaria para DR, y la alta disponibilidad zonal no cubre la pérdida de la
  región.
- **Par `us-central1` / `us-east1`.** Igualmente válido en lo técnico; se mantiene el par de la
  especificación para no desviarse sin motivo.

## Consecuencias

- Positivas: cambiar de región es cambiar dos variables y, si hace falta, agregar una entrada
  al mapa de códigos cortos; ningún módulo tiene regiones fijas.
- Negativas: con organización, `gcp.resourceLocations` (módulo `org`, aplicado por `1-base`)
  debe admitir ambas regiones y además la multirregión `us` (para llaveros y buckets de doble
  región) por `additional_allowed_locations`; si falta `us`, los llaveros de `1-base`, el bucket
  de DR y los repositorios de imágenes fallan. (`0-bootstrap` corre antes de que exista
  `gcp.resourceLocations`, así que el bucket de estado en `US` no depende de esa política.) Sin
  organización no hay esa política.
- La VPN de DR duplica los túneles del hub (cuatro en lugar de dos) y on-premises real debe
  configurar las dos VPN (ADR 0022).
- Si el cliente exige residencia en México, tiene que confirmar qué estrategia de DR acepta
  (zonal en `northamerica-south1` o región de DR fuera del país); este ADR se reabriría.
- Primer apply: verificar que `gcp.resourceLocations` acepta la doble región y los recursos
  globales (punto 3 de [`docs/pendientes-apply.md`](../pendientes-apply.md)) y que las cuotas
  de ambas regiones alcanzan para prod completo (punto 9).
