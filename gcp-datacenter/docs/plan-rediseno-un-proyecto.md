# Plan de rediseño: todo en un solo proyecto de GCP

**Estado:** propuesta. Es un plan, no se ha construido nada. Se escribió el 24 nov 2026.

**Origen:** en la junta del 23 nov 2026, Banorte confirmó que todo el despliegue va dentro de
**un solo proyecto de GCP**.

**Decisiones del equipo (24 nov 2026):**

- No se sabe si el proyecto estará dentro de una organización. El diseño tiene que funcionar sin
  organización y aprovecharla si existe.
- Se mantienen los tres entornos: dev, qa y prod.
- El diseño de varios proyectos se conserva en la rama `archivo/multiproyecto` (commit
  `d22d164`, ya en GitHub). El rediseño se trabaja en la rama `feat/un-proyecto`.

## 1. Qué cambia y por qué

El diseño actual reparte la landing zone en unos diez proyectos, con carpetas, Shared VPC y
controles de organización. En un solo proyecto, estas piezas no se pueden usar o pierden sentido:

| Pieza actual | En un proyecto | Fuente |
|---|---|---|
| Carpetas `bootstrap`, `common`, `dev`, `qa` y `prod` | No existen; los entornos se separan dentro del proyecto | — |
| Shared VPC (host por entorno y proyectos de servicio) | **No se puede.** Necesita organización, y el host y el servicio deben ser proyectos distintos | [Shared VPC](https://docs.cloud.google.com/vpc/docs/shared-vpc) |
| Política de firewall jerárquica | **No se puede sin organización ni carpetas.** Se reemplaza por una política de firewall de red (global o regional) por VPC; que funcione en un proyecto suelto es HYPOTHESIS | [Firewall policies](https://docs.cloud.google.com/firewall/docs/firewall-policies-overview) |
| Sink agregado de la organización | Se reemplaza por un sink de proyecto con exclusiones | [Sinks agregados](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks), [sinks de proyecto](https://docs.cloud.google.com/logging/docs/export/configure_export_v2) |
| Nueve políticas de organización | Solo si hay organización, aplicadas al proyecto. Que sin organización no se puedan usar es HYPOTHESIS | [Organization policy](https://docs.cloud.google.com/resource-manager/docs/organization-policy/overview) |
| Perímetro de VPC Service Controls | Solo con organización, y rodearía todo el proyecto, sin separar entornos. Que haga falta la organización es HYPOTHESIS (la página no lo dice explícitamente) | [VPC-SC](https://docs.cloud.google.com/vpc-service-controls/docs/overview) |
| SCC a nivel organización y mapa CIS de toda la organización | Se activa en el proyecto (Standard o Premium); el cumplimiento solo se ve para ese proyecto | [Activar SCC](https://docs.cloud.google.com/security-command-center/docs/activate-scc-overview), [compliance](https://docs.cloud.google.com/security-command-center/docs/compliance-management) |
| Presupuesto por proyecto o carpeta | Un presupuesto para el proyecto. Un presupuesto de proyecto no se puede filtrar por etiquetas | [Budgets](https://docs.cloud.google.com/billing/docs/how-to/budgets) |
| Aislamiento de IAM por proyecto | IAM condicional por prefijo de nombre (Compute lo admite en instancias, discos, firewall y balanceadores) y por etiquetas. Es más débil que un proyecto aparte; queda como riesgo en un ADR | [Condiciones de IAM](https://docs.cloud.google.com/iam/docs/conditions-resource-attributes) |

Lo que **sí funciona en un proyecto**, según la documentación oficial:

- Peering entre VPC del mismo proyecto ([VPC peering](https://docs.cloud.google.com/vpc/docs/vpc-peering)).
- Varias VPC, cada una con su propia conexión de Private Service Access para Cloud SQL
  ([PSA](https://docs.cloud.google.com/vpc/docs/configure-private-services-access)).
- Roles personalizados a nivel proyecto ([custom roles](https://docs.cloud.google.com/iam/docs/creating-custom-roles)).
- Políticas de denegación de IAM en el proyecto ([deny](https://docs.cloud.google.com/iam/docs/deny-overview)).
  Que no exijan organización es una inferencia, no está escrito.
- Contactos esenciales en el proyecto ([essential contacts](https://docs.cloud.google.com/resource-manager/docs/managing-notification-contacts)).
- Cloud Asset Inventory con alcance de proyecto ([asset search](https://docs.cloud.google.com/asset-inventory/docs/searching-resources)).

**Cuotas.** Todos los entornos comparten las cuotas del proyecto: número de redes, peerings por
red, CPU e IP. La documentación no da números por defecto
([cuotas de VPC](https://docs.cloud.google.com/vpc/docs/quota)): hay que revisarlos en la consola
antes del despliegue. El diseño propuesto usa cinco VPC.

## 2. Arquitectura propuesta

**Recomendación: un hub y tres spokes como VPC independientes dentro del mismo proyecto.** Así se
conserva la historia de hub-and-spoke y el aislamiento de red entre entornos.

```
Proyecto <prefix>-landing-zone  (creado por una persona; con o sin organización)
├── VPC hub          HA VPN a onprem-sim (y a DR), DNS, política de firewall de red
├── VPC dev  ─┐
├── VPC qa   ─┼─ peering con el hub (sin peering entre spokes); NAT y PSA por spoke
├── VPC prod ─┘
├── VPC onprem-sim   on-premises simulado (ADR 0006)
└── Recursos de cada entorno con nombre <prefix>-<env>-..., etiqueta environment=<env>
    y cuentas de servicio propias
```

**Alternativa descartada: una sola VPC con una subred por entorno.** Es más simple, pero pierde el
hub-and-spoke, el aislamiento de red y el ruteo hacia on-premises por entorno.

### Etapas: de 6 a 4

| Nueva etapa | Junta | Contenido |
|---|---|---|
| `0-bootstrap` (manual, una vez) | 0 | APIs, bucket de estado con CMEK, cuentas del pipeline, WIF y roles personalizados de proyecto. La política de denegación sale de la carpeta y se ata al proyecto |
| `1-base` | 1 y 2 | Sink de logs y su bucket, `audit-alerts` una sola vez, contactos esenciales, presupuesto y notificación de SCC. También KMS y Secret Manager por entorno, IAM de personas con condiciones, la política de Binary Authorization (una por proyecto) y, solo si hay organización, las políticas de organización en el proyecto y VPC-SC opcional |
| `2-networks` y `2-networks/envs/{dev,qa,prod}` | 3 | Hub, VPN, DNS y `onprem-sim`; spokes sin Shared VPC |
| `3-workloads/envs/{dev,qa,prod}` | 4 y 5 | Cuentas de ejecución, Artifact Registry y las cargas de cada entorno |

**Regla nueva:** las raíces de entorno no administran nada que sea único por proyecto (APIs,
metadatos de OS Login, política de Binary Authorization, configuración de auditoría,
contactos). Hoy cada raíz `4-projects/envs/*` declara su propia política de Binary
Authorization y `project-factory` habilita APIs y metadatos por proyecto. En un solo proyecto,
eso choca, y un destroy de dev podría apagar las APIs de prod. Todo eso pasa a `1-base`.

### Impacto en el código

El inventario se sacó de `grep` sobre `stages/` y `modules/` el 24 nov 2026.

| Parte | Qué pasa |
|---|---|
| 19 módulos (`kms`, `secrets`, `audit-alerts`, `network-hub`, `network-spoke`, `hybrid-connectivity`, `dns`, `load-balancer`, `cloud-armor`, `gke`, `compute-mig`, `cloud-run`, `cloud-sql`, `memorystore`, `filestore`, `storage`, `backup-dr`, `observability`, `off-hours-shutdown`) | Se reusan. Sus variables no dependen de organización, carpetas ni host de Shared VPC. Falta revisar que ningún nombre choque entre entornos en el mismo proyecto (HYPOTHESIS: la mayoría ya usa `<prefix>-<env>`) |
| `org`, `iam`, `log-export`, `firewall`, `project-factory`, `vpc-sc` | Cambian. Pasan de organización o carpeta a proyecto, y de política jerárquica a política de red. `project-factory` se reduce a la configuración del proyecto único; `vpc-sc` queda opcional |
| `folders` | Se retira (queda en `archivo/multiproyecto`) |
| Etapas | Se reescriben las raíces. El mayor volumen está en `4-projects` (3,639 líneas `.tf`) y `5-workloads` (5,319), que se juntan en `3-workloads` |
| Reglas de Conftest | Las 7 reglas no dependen de la organización; se quedan |
| Pipeline | `apply.yml` con 4 etapas. `destroy.yml` destruye las raíces del entorno y busca huérfanos por la etiqueta `environment=<env>` dentro del proyecto, no por carpeta. `drift.yml` busca recursos no administrados en el proyecto. Cambian `destroy-orphans.py`, `unmanaged-resources.py` y `selftest.sh` |
| Documentación | ADR 0029 "Un solo proyecto" reemplaza total o parcialmente a los ADR que suponen varios proyectos o carpetas: 0003 (VPC host de Shared VPC), 0005 (proyecto de servicio), 0009 (perímetro en dos etapas), 0011 (orden 0 a 5), 0014 (raíces de red), 0018 y 0023 (etapa 1 y política de denegación sobre la carpeta `bootstrap`), 0024 (Artifact Registry y Binary Authorization por proyecto) y 0027 (desviaciones del CIS). También se actualizan el contrato, el README, los cuatro diagramas, el runbook 01, `pipeline.md`, el mapa CIS (lo de organización pasa a "No aplica sin organización" o "Manual"), los costos, la guía del colaborador (mucho más corta: ya no hay que crear una organización) y `pendientes-apply.md` |

**Ventaja para el calendario:** sin organización, cualquier integrante con una cuenta de Google y
facturación puede crear el proyecto y desplegar. Desaparece el día de dominio y Cloud Identity
que pedía la guía.

## 3. Plan de trabajo

Las fechas son una propuesta. La entrega final del equipo es el 3 dic 2026 (confirmar en Canvas),
y antes hay que desplegar y grabar.

| Paso | Cuándo | Qué | Quién | Listo cuando |
|---|---|---|---|---|
| R0 | 24 nov | ADR 0029 y sección nueva del contrato: etapas, interfaces entre etapas, nombres y la regla de recursos únicos | Claude (gestor) | Revisado por el equipo |
| R1 | 25 a 27 nov | Construcción en paralelo, un constructor Opus por bloque, cada uno en su rama: (a) `0-bootstrap` y `1-base`; (b) `2-networks`; (c) `3-workloads` (juntar 4 y 5); (d) pipeline, scripts y pruebas | Constructores | `check.sh`, `policy-check.sh`, `selftest.sh` y `docs.sh --check` en verde en cada rama |
| R2 | 27 nov | Integrar, suite completa con Terraform 1.16.5 y 1.9.8, revisión independiente, documentación y diagramas | Claude y revisor | Suite en verde y hallazgos corregidos |
| R3 | 28 a 29 nov | Despliegue real en el proyecto único (dev y luego qa y prod mínimos) y grabación del video ([plan de la presentación](plan-presentacion-final.md)) | Quien tenga la cuenta, con Claude Code | `apply.yml` en verde, evidencias y video en bruto |
| R4 | 30 nov a 1 dic | Ajustes por lo que falle en GCP; presentación y documentos de la Fase 4 | Equipo y Claude | Documentos y presentación con datos reales |
| R5 | 2 dic | Ensayo con tiempos | Equipo | Presentación ensayada |

**Costo del despliegue de prueba.** La estimación actual del despliegue mínimo es de 20 a 22 USD
por día con los tres entornos, u 8 a 9 USD solo con dev
([`estimacion-de-costos.md`](estimacion-de-costos.md)). En un solo proyecto los recursos son casi
los mismos, así que debería quedar parecido (HYPOTHESIS: se recalcula en R2).

## 4. Riesgos

| Riesgo | Mitigación |
|---|---|
| No alcanza el tiempo para reescribir y desplegar antes del 3 dic | Si R2 se atrasa, desplegar solo dev y prod para el video y dejar qa en código |
| Una cuenta del pipeline con roles de proyecto puede tocar todos los entornos | Una cuenta por etapa, condiciones de IAM por prefijo donde se admitan y revisión del plan en cada PR; riesgo escrito en el ADR 0029 |
| El destroy de dev borra algo compartido | Regla de recursos únicos en `1-base`, `disable_on_destroy = false` en las APIs y `destroy-plan-check.py` ampliado para rechazar recursos sin `environment=dev` |
| Cuotas del proyecto | Revisarlas en la consola antes de R3; pedir aumentos el primer día |
| Prueba gratuita sin aumentos de cuota | Usar una cuenta de facturación de pago (la guía ya lo recomienda) |

## 5. Pendiente de decidir

1. Quién crea el proyecto y pone la facturación, y en qué fechas puede desplegar y grabar.
2. Si hay una organización disponible. Cambia solo `1-base` (políticas de organización y
   VPC-SC opcional).
3. Si se hace una ronda de revisión independiente antes del despliegue. Cuesta tokens, pero las
   cinco rondas anteriores encontraron errores que las pruebas no veían.
4. Nombre del proyecto y prefijo (hoy `bnt`).
