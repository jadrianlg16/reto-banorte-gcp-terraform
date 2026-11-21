# ADR 0004: Cloud NAT en cada spoke y región, no en el hub

## Estado

Aceptado, 2026-11-20.

Tipo: Desviación del diagrama de red de la especificación.

## Contexto

El diagrama de red de la especificación ubica Cloud NAT en el hub, como salida a internet
común. Con el ADR 0003 cada entorno es una VPC distinta unida al hub por peering. La
documentación de Cloud NAT (interacciones con otros productos, consultada el 2026-11-21)
dice que un gateway se configura para rangos de subred de una sola región y una sola VPC, y
que no da NAT a VM de otras VPC aunque estén unidas por VPC Network Peering y en la misma
región. Además, la documentación de VPC Network Peering indica que las rutas estáticas con
siguiente salto al gateway de internet predeterminado no se exportan ni se importan, así que
la ruta `0.0.0.0/0` del hub tampoco llegaría a los spokes.

## Decisión

El módulo `network-spoke` crea, en cada región activa del spoke (la primaria siempre, la de DR
con `enable_dr = true`), un `google_compute_router` y un `google_compute_router_nat` con IP
asignadas por Google (`AUTO_ONLY`; el módulo no crea direcciones externas). La VPC del spoke
se crea sin la ruta por defecto y el módulo agrega dos rutas: `0.0.0.0/0` al gateway de
internet (`google_compute_route.internet_egress`), que solo usa el NAT porque ninguna VM tiene
IP pública, y `199.36.153.4/30` para el VIP restringido. El hub (`network-hub`) no tiene NAT ni
ruta a internet; solo la ruta del VIP restringido.

## Alternativas consideradas

- **NAT en el hub (lo que dibuja el diagrama).** Rechazada: no funciona con peering, por lo
  citado arriba.
- **Appliance de NAT o proxy en el hub con ruta por defecto hacia un balanceador interno como
  siguiente salto.** Técnicamente posible (rutas con siguiente salto a un balanceador interno
  sí se pueden exportar por peering, por verificar en el caso de `0.0.0.0/0`), pero añade VM a
  operar, a parchear y a escalar, y un punto único de falla que la especificación no pide.
- **Private NAT con Network Connectivity Center.** Resuelve NAT entre VPC, no la salida a
  internet, y exigiría cambiar el ADR 0003.

## Consecuencias

- Positivas: cada entorno tiene su propia salida, sus propias IP de NAT y sus registros; un
  problema de NAT en dev no afecta a prod.
- Negativas: cuatro gateways con el plan actual (uno en dev, uno en qa y dos en prod
  con `enable_dr = true`), con costo por gateway
  y por tráfico procesado. Las IP de salida no son fijas (`AUTO_ONLY`): si un tercero necesita
  una lista de IP permitidas, habrá que reservar direcciones estáticas (cambio en el módulo).
- La salida a internet de los spokes no pasa por el hub, así que la inspección centralizada de
  salida no existe en este diseño; la controla el firewall de cada spoke y, opcionalmente, la
  denegación de salida del módulo `firewall` (`enable_egress_default_deny`).
- El cliente debe confirmar que acepta la desviación del diagrama.
- Primer apply: que una VM sin IP pública de cada spoke salga a internet por su NAT y que el hub
  no tenga salida; se cubre en la prueba de conectividad de extremo a extremo (§9.2) y en el
  segundo plan sin cambios (punto 11 de [`docs/pendientes-apply.md`](../pendientes-apply.md)).
