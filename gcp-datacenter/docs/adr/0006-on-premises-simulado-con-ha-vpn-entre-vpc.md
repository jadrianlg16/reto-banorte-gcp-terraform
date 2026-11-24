# ADR 0006: On-premises simulado con una VPC `onprem-sim` y HA VPN entre VPC

## Estado

Aceptado, 2026-11-20. Enmendado el 2026-11-21: VPN de DR en los dos lados, política de red de
`onprem-sim` para probar el reenvío DNS y secreto real por versión numérica con rotación por
túnel. Enmendado el 2026-11-24: con el proyecto único ([ADR 0029](0029-un-solo-proyecto.md)
§6) la raíz del hub es `stages/2-networks/` y crea `onprem-sim` en el proyecto único; sin
política jerárquica, la política de red de `onprem-sim` es la única que admite el reenvío DNS
(ya no hay delegación con `goto_next`); el estado del hub, con el secreto, lo leen `tf-net`, las
cuentas de los spokes y `tf-read`.

Tipo: Supuesto.

## Contexto

La especificación pide conectividad híbrida con HA VPN de dos túneles y BGP (SLA de 99.99 %),
Interconnect opcional y reenvío de DNS hacia on-premises. El equipo no tiene un sitio
on-premises ni un equipo de VPN real con el cual probar. Sin una punta remota, los túneles, las
sesiones BGP, los anuncios personalizados y la zona de reenvío de DNS no se pueden ejercitar.

## Decisión

Con `simulate_onprem = true`, la raíz del hub (`stages/2-networks/`) crea en el proyecto
único una VPC `onprem-sim` (módulo `network-hub` con `network_suffix`, subred
`192.168.0.0/24` dentro de `onprem_cidrs = 192.168.0.0/16`) con su Cloud Router (ASN
`onprem_asn = 65001`, que en este modo debe ser privado: la validación de `onprem_asn` lo exige).
El módulo `hybrid-connectivity` se instancia una vez por punta y por VPN con
`peer.type = "gcp"`: cada instancia recibe el `gateway_self_link` de la otra, la punta simulada
invierte las IP de cada /30 (`router_ip`, `peer_ip`) y `connection_name` evita choques de
nombres en el mismo proyecto. Con `enable_vpn_dr = true` (por defecto) hay una segunda VPN en la
región de DR (ADR 0022): `module.vpn_hub_dr` en el router del hub en `dr_region` y
`module.vpn_onprem_sim_dr` en un router de `onprem-sim` en esa región, sin subred
(`extra_router_regions` del módulo `network-hub`). Con `simulate_onprem = false`, el mismo
módulo recibe `peer.type = "external"` con `onprem_vpn_gateway_ips` (las mismas IP para las dos
VPN; la de DR crea su propio gateway externo `…-vpn-onprem-dr-peer`), `onprem-sim` no se crea y
`onprem_asn` puede ser un ASN público de 2 o 4 bytes.

Para poder probar el reenvío de DNS en modo simulado, `onprem-sim` tiene su propia política de
firewall de red (`<prefix>-common-net-fw-onprem-sim`, `module.firewall_onprem_sim`) que permite
`35.199.192.0/19` (TCP y UDP 53) y SSH por IAP; lo demás lo deniega la regla por defecto del
módulo. Sin política jerárquica (ADR 0029 §6), esa política es la única que decide. Falta solo
la VM DNS, que se crea a mano.

Secreto compartido de IKE: entra por `shared_secret` (variable `sensitive`, sin valor por
defecto, mínimo 32 caracteres; ninguna salida lo expone). En modo simulado la raíz lo genera con
`random_password` y lo pasa a las dos puntas. Con on-premises real lo lee de Secret Manager con
`data "google_secret_manager_secret_version"`, en una versión numérica fija
(`onprem_vpn_secret_version`; `latest` no se admite) y, para rotar de a un túnel, con versiones
por túnel en `onprem_vpn_secret_version_overrides` (llaves `primary-if0`, `primary-if1`,
`dr-if0`, `dr-if1`); el valor lo carga el equipo de red fuera de Terraform. En los dos casos el
valor queda en el estado de la raíz `2-networks/hub`, cifrado con la llave CMEK del bucket de
estado (ADR 0008) y legible por `tf-net`, por las cuentas de los spokes (`tf-net-<env>`, que leen
el prefijo del hub para el peering) y por `tf-read` (ADR 0010). Con on-premises real, `tf-net`
todavía no tiene permiso para leer el secreto en Secret Manager (abierto, contrato §12).

## Alternativas consideradas

- **Un appliance de VPN en una VM (por ejemplo strongSwan) como on-premises.** Más realista
  como gateway externo, pero exige una VM con IP pública, que prohíbe
  `compute.vmExternalIpAccess`, y una imagen a mantener. Rechazada.
- **Construir solo el modo real y no probar la VPN.** Rechazada: los criterios de la
  especificación sobre conectividad híbrida quedarían sin demostrar.
- **Pasar el secreto por variable o `tfvars`.** Rechazada: prohibido por §1, regla 5.

## Consecuencias

- Positivas: el mismo código cubre la prueba y la producción; solo cambia `peer.type`.
- Negativas: la simulación es GCP a GCP. No prueba la configuración de un equipo de otro
  fabricante, la MTU ni la latencia reales. La VPC simulada no tiene servidor DNS: para probar
  el reenvío condicional (`onprem_dns_servers`) hace falta crear a mano una VM de DNS en
  `onprem-sim` con esa IP; el firewall ya lo admite.
- El secreto queda en el estado en ambos modos; esto es una excepción al principio del
  ADR 0015, aceptada porque `google_compute_vpn_tunnel` exige el valor y Terraform 1.9 no tiene
  atributos de solo escritura (ADR 0001). En el proveedor 6.50, `shared_secret` fuerza el
  reemplazo del túnel y no existe la variante de solo escritura: rotar el secreto recrea el
  túnel. Por eso la versión es numérica (una rotación entra por PR) y se rota de a un túnel con
  `onprem_vpn_secret_version_overrides`, mientras los otros tres mantienen la conectividad
  (procedimiento en el README de `stages/2-networks`).
- Primer apply: propagación de rutas BGP del hub a los spokes y de los /16 de los spokes hacia
  on-premises, y anuncio de `35.199.192.0/19` con respuesta de DNS (puntos 6, 7 y 36); las dos
  VPN con su preferencia (punto 37) y el regreso asimétrico (punto 38) de
  [`docs/pendientes-apply.md`](../pendientes-apply.md).
