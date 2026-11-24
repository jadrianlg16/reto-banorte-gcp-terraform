# ADR 0014: Raíz del hub en `stages/2-networks/` y una raíz por spoke en `envs/<env>/`

## Estado

Aceptado, 2026-11-20. Enmendado el 2026-11-24: con el proyecto único
([ADR 0029](0029-un-solo-proyecto.md) §2) la etapa de redes pasa de `stages/3-networks/` a
`stages/2-networks/` (prefijos `2-networks/hub` y `2-networks/<env>`); el hub lo aplica
`<prefix>-tf-net` (entorno de GitHub `common`) y cada spoke `<prefix>-tf-net-<env>` (entorno
`<env>`); el hub no lee ningún estado y cada spoke lee solo `2-networks/hub`; la política
jerárquica se reemplaza por políticas de firewall de red por VPC. El título decía
`stages/3-networks/`; el nombre del archivo no cambia.

Tipo: Aclaración.

## Contexto

El árbol de repositorio de la especificación muestra para la etapa de redes solo
`envs/{dev,qa,prod}`. El hub (`<prefix>-common-net-hub`) no pertenece a ningún entorno: tiene
su VPC, los Cloud Router, la HA VPN, el reenvío de DNS, sus políticas de firewall de red y, en
modo simulado, la VPC `onprem-sim` (ADR 0006). Si viviera dentro de un spoke, destruir dev se
llevaría la conectividad de todos.

## Decisión

La raíz del hub es `stages/2-networks/` (prefijo de estado `2-networks/hub`) y cada spoke es
`stages/2-networks/envs/<env>/` (prefijo `2-networks/<env>`). El hub lo aplica
`<prefix>-tf-net` y cada spoke `<prefix>-tf-net-<env>`, cada una ligada a su entorno de GitHub
(ADR 0023). El hub no lee ningún estado; cada spoke lee `2-networks/hub` para obtener
`hub_network_self_link` y `spoke_supernets`. El hub no lee a los spokes: los /16 que
anuncia por BGP entran por la variable `spoke_supernets` (mapa entorno → /16), y las raíces
validan que no se traslapen con `onprem_cidrs`; cada spoke comprueba que su `spoke_supernet`
coincide con lo que el hub anuncia para su entorno. Las tres raíces de spoke son idénticas salvo
`backend.tf` y `terraform.tfvars.example`.

## Alternativas consideradas

- **Hub dentro de `envs/prod`.** Rechazada: ata la conectividad común al ciclo de vida de prod y
  obliga a dev y qa a leer el estado de prod.
- **Hub en una etapa propia (por ejemplo `2-hub` y `3-spokes`).** Rechazada: renumera las etapas
  y cambia las filas de §6.1.
- **Hub y spokes en una sola raíz.** Rechazada: un plan de dev tocaría el estado de prod y del
  hub, y el pipeline no podría aplicar los entornos por separado.

## Consecuencias

- Positivas: el hub se aplica una vez, antes de los spokes; cada spoke tiene su estado y su plan.
- Negativas: el lado del hub de cada peering (`hub_to_spoke`) lo crea la raíz del spoke sobre la
  red del hub, así que cada `tf-net-<env>` tiene `compute.networkAdmin` en el proyecto (sin
  condición: alcanza también al hub y a los otros spokes, riesgo aceptado del ADR 0029 §9), y el
  hub tiene recursos cuyo estado vive en otra raíz. GCP no admite dos operaciones de peering a la
  vez sobre una red: los spokes no deben aplicarse en paralelo (`VERIFICAR-EN-APPLY` en
  `modules/network-spoke/main.tf`); `apply.yml` los encadena.
- `spoke_supernets` y los `subnet_cidrs` de cada spoke son dos fuentes del mismo dato; las
  validaciones de §5 comprueban que cada spoke quepa en su /16.
- Primer apply: propagación de rutas entre hub, spokes y on-premises (punto 6 de
  [`docs/pendientes-apply.md`](../pendientes-apply.md)) y el orden de los peering en el apply
  de los tres spokes.
