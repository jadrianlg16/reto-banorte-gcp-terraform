# ADR 0006: On-premises simulado con una VPC `onprem-sim` y HA VPN entre VPC

## Estado

Aceptado, 2026-11-20.

Tipo: Supuesto.

## Contexto

La especificación pide conectividad híbrida con HA VPN de dos túneles y BGP (SLA de 99.99 %),
Interconnect opcional y reenvío de DNS hacia on-premises. El equipo no tiene un sitio
on-premises ni un equipo de VPN real con el cual probar. Sin una punta remota, los túneles, las
sesiones BGP, los anuncios personalizados y la zona de reenvío de DNS no se pueden ejercitar.

## Decisión

Con `simulate_onprem = true`, la raíz del hub (`stages/3-networks/`) crea en el proyecto
`net-hub` una VPC `onprem-sim` (módulo `network-hub` con `network_suffix`, subred
`192.168.0.0/24` dentro de `onprem_cidrs = 192.168.0.0/16`) con su Cloud Router (ASN
`onprem_asn = 65001`). El módulo `hybrid-connectivity` se instancia dos veces, una por VPC, con
`peer.type = "gcp"`: cada instancia recibe el `gateway_self_link` de la otra, la punta simulada
invierte las IP de cada /30 (`router_ip`, `peer_ip`) y `connection_name` evita choques de
nombres en el mismo proyecto. Con `simulate_onprem = false`, el mismo módulo recibe
`peer.type = "external"` con `onprem_vpn_gateway_ips` y no se crea `onprem-sim`.

Secreto compartido de IKE: entra por `shared_secret` (variable `sensitive`, sin valor por
defecto, mínimo 32 caracteres; ninguna salida lo expone). En modo simulado la raíz lo genera con
`random_password` y lo pasa a las dos puntas. Con on-premises real lo lee de Secret Manager con
`data "google_secret_manager_secret_version"`; el valor lo carga el equipo de red fuera de
Terraform. En los dos casos el valor queda en el estado de la raíz `3-networks/hub`, cifrado
con la llave CMEK del bucket de estado (ADR 0008) y legible solo por la cuenta de esa etapa
(ADR 0010).

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
  el reenvío condicional (`onprem_dns_servers`) hace falta una VM de DNS en `onprem-sim`, que
  el contrato no incluye.
- El secreto queda en el estado en ambos modos; esto es una excepción al principio del
  ADR 0015, aceptada porque `google_compute_vpn_tunnel` exige el valor y Terraform 1.9 no tiene
  atributos de solo escritura (ADR 0001). Rotar el secreto implica recrear los túneles.
- Primer apply: propagación de rutas BGP del hub a los spokes y de los /16 de los spokes hacia
  on-premises, y anuncio de `35.199.192.0/19` con respuesta de DNS (puntos 6 y 7 de
  [`docs/pendientes-apply.md`](../pendientes-apply.md)).
