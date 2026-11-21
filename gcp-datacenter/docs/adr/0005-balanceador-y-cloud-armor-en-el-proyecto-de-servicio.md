# ADR 0005: Balanceador HTTPS global y Cloud Armor en el proyecto de servicio de cada entorno

## Estado

Aceptado, 2026-11-20.

Tipo: Desviación del diagrama de red de la especificación.

## Contexto

El diagrama de red de la especificación dibuja el balanceador HTTPS global y Cloud Armor en la
VPC hub, como punto de entrada común. Con el ADR 0003 los backends (MIG, NEG de GKE y NEG sin
servidor de Cloud Run) viven en los proyectos de servicio de cada entorno, sobre la Shared VPC
de su spoke. El balanceador de aplicaciones externo global no es un recurso de una VPC: sus
Google Front Ends están en el borde de Google y hablan directo con los backends. Según la
documentación del producto (consultada el 2026-11-21), los backends pueden estar en cualquier
VPC de la misma organización sin peering, y el frontend puede referirse a servicios de backend
de otro proyecto de la organización (referencia de servicios entre proyectos). Es decir, ubicar
el balanceador en el hub sería posible; el criterio de la decisión no es la factibilidad, sino
la propiedad y el radio de impacto.

## Decisión

El módulo `load-balancer` con `type = "external"` (`EXTERNAL_MANAGED`) y el módulo
`cloud-armor` se instancian en la etapa 5, en el proyecto de servicio del entorno
(`<prefix>-<env>-app`). `security_policy` es obligatoria por validación en el externo. El
balanceador interno (`type = "internal"`, `INTERNAL_MANAGED`) también vive en el proyecto de
servicio y usa la subred proxy-only del spoke (`proxy`, `proxy_dr`). El tráfico desde
on-premises sí entra solo por el hub (HA VPN y peering, ADR 0003 y 0006).

## Alternativas consideradas

- **Balanceador y Cloud Armor en el proyecto hub, con referencia de servicios entre
  proyectos.** Factible según la documentación, pero rechazada: el equipo de red sería dueño
  del frontend de todas las aplicaciones, la raíz `3-networks` tendría que conocer los backends
  de la etapa 5 (dependencia inversa entre etapas), y un cambio en el mapa de URL de prod
  compartiría plan y estado con dev. La política de Cloud Armor se adjunta al servicio de
  backend, que de todos modos vive en el proyecto de servicio.
- **Un balanceador por entorno en el proyecto `net-spoke`.** Rechazada: mezcla recursos de
  aplicación en el proyecto host, que la etapa 4 reserva para red.

## Consecuencias

- Positivas: cada entorno tiene su IP, su certificado, su política de Cloud Armor y su registro
  de solicitudes; el despliegue de una aplicación no toca el hub. La conmutación a DR
  (`dr_active`) cambia backends dentro del mismo estado de la etapa 5.
- Negativas: no hay un único punto de entrada para reglas comunes de Cloud Armor; las reglas
  base (OWASP y límite de tasa) se repiten por entorno desde el módulo, no se heredan.
- El certificado administrado solo se activa cuando los registros DNS A de `domain_names`
  apuntan a `lb_ip_address` (`VERIFICAR-EN-APPLY` en `modules/load-balancer/main.tf`).
- El cliente debe confirmar que acepta la desviación del diagrama, o pedir el balanceador
  central en el hub sabiendo el costo en dependencias entre etapas descrito arriba.
- Primer apply: no hay entrada específica en §12; queda cubierto por la prueba de extremo a
  extremo y el segundo plan sin cambios (punto 11 de
  [`docs/pendientes-apply.md`](../pendientes-apply.md)).
