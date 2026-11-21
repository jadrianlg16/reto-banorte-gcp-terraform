# ADR 0022: Estado y conmutación a DR sin depender de la región primaria

## Estado

Aceptado, 2026-11-21. Completa los ADR 0002, 0005, 0006 y 0008.

Tipo: Aclaración.

## Contexto

El runbook de conmutación ([04](../runbooks/04-conmutacion-a-dr.md)) corre `terraform` durante
una caída de `us-central1` (`primary_region`). La revisión independiente encontró cuatro puntos
del diseño anterior que dependían de esa región y hacían que la conmutación no se pudiera
ejecutar tal como estaba escrita:

1. El bucket de estado y su llave KMS eran regionales (`primary_region`): sin la región, `init`,
   el bloqueo y `terraform_remote_state` fallan y no hay Terraform para conmutar.
2. La HA VPN existía solo en el router del hub de la región primaria: al perderla, la región de
   DR quedaba sin camino a on-premises.
3. El balanceador interno tenía una sola instancia con la llave fija `internal`; `dr_active`
   cambiaba su región y sus nombres, así que Terraform lo destruía en la región caída antes de
   crearlo en DR. Sin acceso global, on-premises (túneles en la región primaria) tampoco
   llegaba a un balanceador en otra región.
4. `dr_active = true` con NEG de GKE solo en la región primaria fallaba por validación: los NEG
   de DR no pueden existir antes de crear el clúster de DR, que es el mismo paso.

## Decisión

- **Estado (etapa 0).** El bucket se crea en `state_bucket_location` (por defecto `US`,
  multirregión; `EU` o `ASIA` por validación) o, con `state_bucket_dual_regions`, como doble
  región configurable dentro de esa multirregión con `rpo = "ASYNC_TURBO"`; una precondición
  exige que la lista incluya `primary_region`. Su llave va en la ubicación de KMS homónima
  (`lower(state_bucket_location)`, `us` por defecto), porque la CMEK de Cloud Storage exige que
  la llave esté en la ubicación del bucket (para una doble región configurable dentro de `US`,
  la multirregión `us`; documentación de CMEK de Cloud Storage, citada en el código). El
  llavero pasa a ser `<prefix>-bootstrap-sec-keyring-us`. La ubicación de un bucket no se cambia
  después de crearlo: se elige antes del primer apply.
- **VPN de DR (etapa 3, hub).** Con `enable_vpn_dr = true` (por defecto) se crea una segunda HA
  VPN, `module.vpn_hub_dr`, en el Cloud Router del hub en `dr_region`, con sus /30 propios
  (`vpn_dr_bgp_ranges`, por defecto `169.254.0.8/30` y `169.254.0.12/30`), los mismos anuncios
  que la primaria y `advertised_route_priority = vpn_dr_route_priority` (200 por defecto; la
  validación exige más de 100, el valor de la primaria), para que on-premises prefiera la
  primaria mientras exista. En modo simulado, `onprem-sim` recibe un router en `dr_region` (sin
  subred, `extra_router_regions` del módulo `network-hub`) y su propia punta
  (`module.vpn_onprem_sim_dr`). Con on-premises real, la VPN de DR crea su gateway externo
  `<prefix>-common-net-vpn-onprem-dr-peer` con las mismas `onprem_vpn_gateway_ips`.
- **Balanceador interno por región (etapa 5).** `module.internal_lb` usa
  `for_each = local.compute_regions` (llaves `primary` y `dr`): `dr_active = true` agrega
  `module.internal_lb["dr"]` y no toca `["primary"]`; volver a `dr_active = false` destruye solo
  el de DR. Un bloque `moved` lleva la llave vieja `["internal"]` a `["primary"]`. El módulo
  `load-balancer` pone `allow_global_access = true` en las dos reglas de reenvío internas
  (443 y 80): on-premises llega a cualquiera de los dos balanceadores por la VPN de cualquier
  región, y el registro DNS interno decide a cuál va el tráfico. Salidas:
  `internal_lb_ip_address` (la región activa), `internal_lb_ip_addresses` (todas) e
  `internal_lb_dns_authorization_records_by_region`.
- **GKE durante la conmutación (etapa 5).** `dr_active = true` planea con los `tfvars` normales:
  mientras `gke_lb_negs.dr` esté vacío, el backend `gke` sale del balanceador externo y el
  backend por defecto pasa al primero habilitado (`run`, `mig`, `gke`). Si GKE es el único
  backend, el balanceador conserva los NEG primarios para no destruirse con su IP. Cuando la
  carga está desplegada en el clúster de DR, se llenan `gke_lb_negs.dr` y GKE vuelve al
  balanceador.
- **Imágenes.** El repositorio de Artifact Registry de cada aplicación es multirregional
  (ADR 0024), así que la imagen sigue disponible sin la región primaria.

## Alternativas consideradas

- **Bucket de estado de doble región por defecto.** Admitido con `state_bucket_dual_regions`,
  pero no por defecto: la multirregión no necesita elegir el par de regiones y su llave queda en
  la misma ubicación `us`.
- **Un solo túnel de respaldo en la región de DR.** Rechazado: la especificación pide HA VPN con
  dos túneles (SLA 99.99 %) y el módulo ya la arma igual que la primaria.
- **Recrear el balanceador interno en DR (diseño anterior).** Rechazado: depende de borrar
  recursos en la región caída.
- **Exigir en el runbook `gke_lb_negs.primary = []` al conmutar.** Rechazado: depende de que la
  persona lo recuerde durante el incidente y cambia el backend por defecto sin aviso.

## Consecuencias

- Positivas: el runbook 04 se puede ejecutar con la región primaria caída en lo que depende de
  Terraform (estado, red híbrida y balanceadores); dev y qa con `enable_vpn_dr = true` también
  pagan la VPN de DR del hub, que es común.
- Negativas: el hub pasa de dos a cuatro túneles (en modo simulado, otros cuatro del lado de
  `onprem-sim`: ocho en total); on-premises real debe configurar las dos VPN. El regreso de un flujo hacia la
  región de DR puede ser asimétrico (entra por la VPN primaria y vuelve por la de DR); un
  firewall con estado en on-premises debe admitirlo. El tema de hallazgos de SCC sigue con una
  llave regional (ADR 0018): sin la región primaria no se entregan notificaciones.
- Durante la conmutación, mientras GKE no tenga NEG de DR, el tráfico del externo va a Cloud Run
  o al MIG si están habilitados; si GKE es el único backend, el externo sigue apuntando a la
  región caída hasta el paso de los NEG de DR.
- Primer apply: doble región válida si se usa (punto 31), las dos VPN con su preferencia y el
  paso a la de DR (punto 37), el balanceador interno de DR alcanzable desde on-premises (punto
  44) y la asimetría del regreso (punto 38) en
  [`docs/pendientes-apply.md`](../pendientes-apply.md).
