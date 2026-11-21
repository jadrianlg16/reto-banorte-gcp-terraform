# ADR 0014: Raíz del hub en `stages/3-networks/` y una raíz por spoke en `envs/<env>/`

## Estado

Aceptado, 2026-11-20.

Tipo: Aclaración.

## Contexto

El árbol de repositorio de la especificación muestra para la etapa de redes solo
`envs/{dev,qa,prod}`. El hub (`<prefix>-common-net-hub`) no pertenece a ningún entorno: tiene
su VPC, los Cloud Router, la HA VPN, el reenvío de DNS, la política de firewall jerárquica de
la organización y, en modo simulado, la VPC `onprem-sim` (ADR 0006). Si viviera dentro de un
spoke, destruir dev se llevaría la conectividad de todos.

## Decisión

La raíz del hub es `stages/3-networks/` (prefijo de estado `3-networks/hub`) y cada spoke es
`stages/3-networks/envs/<env>/` (prefijo `3-networks/<env>`). Las dos usan la cuenta
`<prefix>-tf-3-networks`. El hub lee `0-bootstrap` y `1-org`; cada spoke lee además
`3-networks/hub` para obtener `hub_network_self_link`. El hub no lee a los spokes: los /16 que
anuncia por BGP entran por la variable `spoke_supernets` (mapa entorno → /16), y las raíces
validan que no se traslapen con `onprem_cidrs`. Las tres raíces de spoke son idénticas salvo
`backend.tf` y `terraform.tfvars.example`.

## Alternativas consideradas

- **Hub dentro de `envs/prod`.** Rechazada: ata la conectividad común al ciclo de vida de prod y
  obliga a dev y qa a leer el estado de prod.
- **Hub en una etapa propia (por ejemplo `3-hub` y `4-spokes`).** Rechazada: renumera las etapas
  que nombra la especificación y cambia las filas de §6.1.
- **Hub y spokes en una sola raíz.** Rechazada: un plan de dev tocaría el estado de prod y del
  hub, y el pipeline no podría aplicar los entornos por separado.

## Consecuencias

- Positivas: el hub se aplica una vez, antes de los spokes; cada spoke tiene su estado y su plan.
- Negativas: el lado del hub de cada peering (`hub_to_spoke`) lo crea la raíz del spoke sobre la
  red del hub, así que la cuenta de la etapa 3 necesita permisos de red en el proyecto hub desde
  las raíces de spoke, y el hub tiene recursos cuyo estado vive en otra raíz. GCP no admite dos
  operaciones de peering a la vez sobre una red: los spokes no deben aplicarse en paralelo
  (`VERIFICAR-EN-APPLY` en `modules/network-spoke/main.tf`); `apply.yml` debe serializarlos.
- `spoke_supernets` y los `subnet_cidrs` de cada spoke son dos fuentes del mismo dato; las
  validaciones de §5 comprueban que cada spoke quepa en su /16.
- Primer apply: propagación de rutas entre hub, spokes y on-premises (punto 6 de
  [`docs/pendientes-apply.md`](../pendientes-apply.md)) y el orden de los peering en el apply
  de los tres spokes.
