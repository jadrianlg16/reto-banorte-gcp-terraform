# ADR 0003: Una VPC por entorno, unida al hub por VPC Network Peering

## Estado

Aceptado, 2026-11-20.

Tipo: Desviación del diagrama de red de la especificación.

## Contexto

La especificación se contradice. Su diagrama de red dibuja una sola Shared VPC en el proyecto
hub, de la que colgarían todos los entornos. Su jerarquía de proyectos, en cambio, pide un
proyecto de red spoke por entorno (`<prefix>-<env>-net-spoke`). Con una sola VPC compartida,
dev, qa y prod estarían en la misma red y solo el firewall los separaría; un error en una regla
abriría el paso entre entornos.

## Decisión

Se sigue la jerarquía. Cada entorno tiene su VPC en su proyecto `net-spoke`, que es host de
Shared VPC para los proyectos de servicio del entorno (etapa 4). Cada spoke se une al hub
(`<prefix>-common-net-hub`) con VPC Network Peering en los dos sentidos, que crea el módulo
`network-spoke` (`google_compute_network_peering.spoke_to_hub` y `.hub_to_spoke`): el hub
exporta rutas personalizadas y el spoke las importa, así las rutas aprendidas por BGP desde
on-premises llegan a los spokes. No hay peering entre spokes. Cada spoke usa su propio /16
(`10.X.0.0/16`, §5).

## Alternativas consideradas

- **Una sola Shared VPC en el hub (lo que dibuja el diagrama).** Rechazada: contradice la
  jerarquía de proyectos y deja el aislamiento entre entornos solo en el firewall.
- **Network Connectivity Center con spokes de VPC.** Daría conectividad entre spokes
  controlada por el hub, pero el diseño no la quiere, añade un producto que la especificación
  no pide y no cambia el aislamiento. Rechazada por alcance.
- **Shared VPC por entorno sin hub, cada una con su VPN a on-premises.** Rechazada: multiplica
  túneles, sesiones BGP y reenvío de DNS por tres, y la especificación pide un hub central.

## Consecuencias

- Positivas: aislamiento por red. Como el peering no es transitivo, dev no puede alcanzar prod
  a través del hub aunque una regla de firewall se equivoque.
- Negativas, derivadas de que el peering no es transitivo:
  - Lo que vive detrás de otro peering dentro del spoke no se alcanza desde el hub ni desde
    on-premises: Cloud SQL, Memorystore y Filestore (Private Service Access, rango `psa`
    `10.X.176.0/20`) y el plano de control privado de GKE. El hub anuncia a on-premises el /16
    completo del spoke, que incluye el rango `psa`; ese tráfico llegaría al hub y no tendría
    ruta. Si on-premises necesita esos servicios, hace falta un proxy o un bastión en el spoke,
    o exportar las rutas del peering de servicios (por verificar).
  - Internet y Cloud NAT tampoco se comparten por el peering (ADR 0004).
  - El lado del hub de cada peering lo crea la raíz del spoke sobre la red del hub; dos spokes
    no deben aplicarse a la vez (`VERIFICAR-EN-APPLY` en `modules/network-spoke/main.tf`).
- Costo y operación: tres proyectos host en lugar de uno.
- El cliente debe confirmar que acepta la desviación del diagrama; los diagramas corregidos de
  `docs/diagramas/` la reflejan.
- Primer apply: que las rutas aprendidas por BGP en el hub lleguen a los spokes y que
  on-premises alcance los /16 de los spokes (punto 6 de
  [`docs/pendientes-apply.md`](../pendientes-apply.md)).
