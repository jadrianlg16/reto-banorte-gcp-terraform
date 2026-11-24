# Plan de rediseño: todo en un solo proyecto de GCP

**Estado:** versión 2, del 24 nov 2026. Ya incluye la revisión independiente con Fable 5.2 del
mismo día. El diseño detallado está en el
[ADR 0029](adr/0029-un-solo-proyecto.md), que es lo que siguen los constructores.

**Avance al 24 nov 2026:** R0 a R3 hechos el mismo día, todo sin GCP. R1 se construyó en cuatro
ramas; R2 integró, pasó por una revisión de seguridad y una de integración, y corrigió sus
hallazgos en las ramas `r2/integracion`, `r2/politicas`, `r2/pipeline` y `r2/identidad`; R3
concilió la documentación con ese código. Lo que sigue es R4, que espera al proyecto de GCP. Lo
que solo un apply confirma está en [`pendientes-apply.md`](pendientes-apply.md).

**Origen:** en la junta del 23 nov 2026, Banorte confirmó que todo el despliegue va dentro de
**un solo proyecto de GCP**.

**Decisiones del equipo (24 nov 2026):**

- No se sabe si habrá organización. El diseño funciona sin ella y la aprovecha si existe.
- Se mantienen dev, qa y prod.
- El diseño de varios proyectos se conserva en la rama `archivo/multiproyecto` (commit `d22d164`,
  ya en GitHub). El rediseño se trabaja en la rama `feat/un-proyecto`.

## 1. Qué cambia y por qué

| Pieza actual | En un proyecto | Fuente |
|---|---|---|
| Carpetas | No existen | — |
| Shared VPC | **No se puede.** Necesita organización, y el host y el servicio deben ser proyectos distintos | [Shared VPC](https://docs.cloud.google.com/vpc/docs/shared-vpc) |
| Política de firewall jerárquica | **No se puede sin organización ni carpetas.** Se reemplaza por una política de firewall de red por VPC | [Firewall policies](https://docs.cloud.google.com/firewall/docs/firewall-policies-overview) |
| Sink agregado de la organización | Sink de proyecto con exclusiones | [Sinks](https://docs.cloud.google.com/logging/docs/export/configure_export_v2) |
| Políticas de organización y VPC-SC | Solo con organización, y el perímetro rodea todo el proyecto. Sin organización: HYPOTHESIS que no se pueden usar (las páginas no lo dicen) | [Org policy](https://docs.cloud.google.com/resource-manager/docs/organization-policy/overview), [VPC-SC](https://docs.cloud.google.com/vpc-service-controls/docs/overview) |
| SCC de la organización | Activación en el proyecto (Standard o Premium); el cumplimiento solo cubre ese proyecto. Que funcione sin organización es HYPOTHESIS | [Activar SCC](https://docs.cloud.google.com/security-command-center/docs/activate-scc-overview) |
| Registros de acceso a datos solo en prod | La configuración de auditoría es única por proyecto: vale para los tres entornos | ADR 0029 §7 |
| Presupuesto | Un presupuesto del proyecto, que crea una persona en `0-bootstrap`. Las etiquetas solo filtran presupuestos de cuenta de facturación | [Budgets](https://docs.cloud.google.com/billing/docs/how-to/budgets) |
| Aislamiento de IAM por proyecto | Una cuenta del pipeline por entorno ligada al entorno de GitHub, y condiciones por nombre en Storage, KMS y Secret Manager. El resto queda como riesgo aceptado | ADR 0029 §3 y §9 |
| Destroy borrando el proyecto | Destroy recurso por recurso; huérfanos por la etiqueta `env` y por el prefijo `<prefix>-<env>-` | ADR 0029 §8 |

Lo que **sí funciona en un proyecto**, según la documentación oficial: peering entre VPC del mismo
proyecto, una conexión de PSA por VPC, roles personalizados de proyecto, políticas de denegación
atadas al proyecto, contactos esenciales en el proyecto y Cloud Asset con alcance de proyecto. Los
enlaces están en el ADR 0029.

## 2. Arquitectura

- **Un hub y tres spokes** como VPC del mismo proyecto, unidas por peering. Además `onprem-sim`
  con HA VPN, como hoy.
- **Cuatro etapas:** `0-bootstrap` (a mano), `1-base`, `2-networks` (hub y spokes) y
  `3-workloads` (por entorno). La tabla de raíces, prefijos, cuentas e interfaces está en el
  ADR 0029 §2.

Lo que cambió por la revisión independiente:

| Hallazgo | Gravedad | Cómo se resuelve |
|---|---|---|
| El estado, el pipeline y las cargas quedan en el mismo proyecto; `storage.admin` de la etapa 5 alcanzaría el bucket de estado | Alto | Ninguna cuenta con `storage.admin` sin condición. Política de denegación con una etiqueta sobre el bucket de estado (HYPOTHESIS que funcione sin organización). ADR 0029 §3 y §5 |
| "Una cuenta por etapa" no separa entornos | Alto | Nueve cuentas: una por raíz y entorno, ligadas por WIF al entorno de GitHub, más `tf-read` de solo lectura para los `plan`. ADR 0029 §3 |
| La regla de recursos únicos no bastaba | Alto | Regla ampliada. Fuera de las raíces de entorno quedan los permisos de proyecto para principales compartidos, el rol del apagado, los repositorios y la política de Binary Authorization, y la cuenta de Compute por defecto. Además, namespace de GKE `<app>-<env>` (Workload Identity comparte el pool del proyecto). ADR 0029 §4 y §9 |
| Sin borrar proyectos no hay "empezar de cero" | Alto | El destroy de un entorno quita sus cargas, y el spoke solo con `incluir_red`. Lo persistente del entorno vive en `1-base`. Huérfanos por la etiqueta `env` y el prefijo. ADR 0029 §8 |
| El calendario no era creíble | Alto | Calendario nuevo (§3): rebanada vertical primero y grabación de una ejecución ensayada, no de la primera |
| La etiqueta es `env`, no `environment` | Medio | Corregido en todo el plan |
| La red `default` y la cuenta de Compute por defecto en un proyecto creado a mano | Medio | Borrar `default` en el runbook 01. `DEPRIVILEGE` de la cuenta por defecto en `0-bootstrap` (al construirlo se movió de `1-base`: quitar un rol básico necesita `setIamPolicy` sin condición en el proyecto, que ninguna cuenta del pipeline tiene) |
| Registros de acceso a datos: todo o nada | Medio | Decidido en el ADR 0029 §7; el costo se recalcula |
| Fuentes mal marcadas (SCC sin organización, presupuestos) | Medio | Corregidas en la tabla de §1 |
| Cuotas compartidas | Medio | Revisarlas el primer día con la cuenta, antes de `0-bootstrap` |
| `tests/` faltaba en el impacto | Medio | Agregado (tabla siguiente) |

### Impacto en el código

El inventario se sacó con `grep` el 24 nov 2026, antes de R1; los conteos de líneas los confirmó
la revisión. El resultado de R1 y R2 cambió dos filas: quedan 24 módulos (se retiraron `folders`
y `project-factory`; `ls modules | wc -l` → 24) y 12 reglas de Conftest (las 7 de antes más
`bucket_uniform_access`, `env_root_scope`, `iam_public_principal`, `resource_locations` y
`service_account_key`), contadas el 24 nov 2026 con `ls policies/*.rego`.

| Parte | Qué pasa |
|---|---|
| 19 módulos (`kms`, `secrets`, `audit-alerts`, `network-hub`, `network-spoke`, `hybrid-connectivity`, `dns`, `load-balancer`, `cloud-armor`, `gke`, `compute-mig`, `cloud-run`, `cloud-sql`, `memorystore`, `filestore`, `storage`, `backup-dr`, `observability`, `off-hours-shutdown`) | Se reusan. La revisión confirmó que los de red ya nombran con `<prefix>-<env>` |
| `org`, `iam`, `log-export`, `firewall`, `project-factory`, `vpc-sc` | Cambian de organización o carpeta a proyecto. El firewall pasa de política jerárquica a política de red |
| `folders` | Se retira |
| Etapas | Se reescriben las raíces. Las tres raíces de entorno de `4-projects` y `5-workloads` son copias (1,213 y 1,773 líneas cada una), así que el trabajo real es cerca de un tercio de las 8,958 líneas |
| Pipeline | `apply.yml` (39 referencias a la estructura vieja), `destroy.yml` (26), `drift.yml` (12), `_terraform-root.yml`, `pr.yml`, `affected-roots.sh` y `CODEOWNERS` |
| Scripts | `selftest.sh` (44 referencias), `destroy-orphans.py`, `destroy-plan-check.py` y `unmanaged-resources.py` |
| `tests/` | 7,805 líneas en Go; 15 archivos con referencias a proyectos o carpetas |
| Reglas de Conftest | Las 7 se quedan |
| Documentación | El contrato (§2, §3, §6 y §7), el README, los cuatro diagramas, el runbook 01, `pipeline.md`, el mapa CIS, los costos, la guía del colaborador y `pendientes-apply.md`. ADR afectados: tabla final del ADR 0029 |

## 3. Plan de trabajo

La entrega final es el 3 dic 2026 (confirmar en Canvas). Nada de GCP se puede probar hasta que
alguien del equipo tenga el proyecto.

| Paso | Cuándo | Qué | Listo cuando |
|---|---|---|---|
| R0 | 24 nov | ADR 0029 y nota en el contrato | Hecho |
| R1 | 24 a 25 nov | Construcción en paralelo, un constructor Opus por bloque y cada uno en su rama: (a) `0-bootstrap` y `1-base` con sus módulos; (b) `2-networks` con `firewall` y `network-spoke`; (c) `3-workloads`; (d) pipeline, scripts y `tests/` | Cada bloque con `check.sh` y sus pruebas en verde. Hecho el 24 nov |
| R2 | 25 a 26 nov | Integrar, suite completa con 1.16.5 y 1.9.8, revisión independiente y correcciones | Suite en verde y hallazgos corregidos. Hecho el 24 nov |
| R3 | 26 a 27 nov | Documentación, diagramas con íconos oficiales, guía nueva del colaborador, mapa CIS y costos | `docs.sh --check` en verde y enlaces sin romper. Hecho el 24 nov |
| R4 | Cuando haya proyecto (ideal 27 a 28 nov) | **Rebanada vertical real:** `0-bootstrap`, `1-base`, hub, spoke dev y Cloud Run con Cloud SQL. Se corrige lo que falle | Primer `apply.yml` en verde |
| R5 | 28 a 29 nov | Desplegar el resto en modo mínimo y **ensayar la grabación**; grabar una ejecución ya probada | Video en bruto ([plan de la presentación](plan-presentacion-final.md)) |
| R6 | 30 nov a 1 dic | Presentación y documentos de la Fase 4 con datos reales | Archivos listos |
| R7 | 2 dic | Ensayo con tiempos | Presentación ensayada |

**Si no alcanza el tiempo, se recorta en este orden** (propuesta de la revisión):

1. DR y la segunda región, VPC-SC y políticas de organización: se quedan solo en código.
2. qa desplegado.
3. GKE, MIG, Filestore, Memorystore y Backup and DR. El video queda con Cloud Run, Cloud SQL, la
   VPN y el pipeline.
4. La búsqueda de recursos no administrados de `drift.yml` y la pata 1.9.8.
5. La escena del destroy en el video.

No se recortan la rebanada vertical real ni el ensayo de grabación.

**Costo del despliegue de prueba.** La estimación actual del despliegue mínimo es de 20 a 22 USD
por día con los tres entornos ([`estimacion-de-costos.md`](estimacion-de-costos.md)). En R3 se
recalcula con los registros de acceso a datos en los tres entornos.

## 4. Riesgos

| Riesgo | Mitigación |
|---|---|
| Nadie tiene el proyecto a tiempo | Sin organización, cualquier integrante lo crea en minutos con su cuenta y facturación de pago |
| El primer apply de la historia del repositorio encuentra muchas fallas (131 marcadores `VERIFICAR-EN-APPLY` en 53 archivos `.tf` de `modules/` y `stages/`, sin pruebas ni ejemplos, según `git grep -c` del 24 nov 2026; hay más en scripts, pruebas de Go y flujos) | Rebanada vertical primero (R4) y recortes (§3) |
| Una cuenta de dev puede tocar Compute, GKE, Cloud Run o Cloud SQL de prod | Riesgo aceptado (ADR 0029 §9): la cuenta solo la obtiene el entorno `dev` de GitHub y los cambios pasan por PR |
| El destroy de un entorno borra algo compartido | Regla de recursos únicos y `destroy-plan-check.py` que rechaza nombres sin `<prefix>-<env>-` |
| Cuotas del proyecto | Revisarlas el primer día; pedir aumentos de inmediato |
| Prueba gratuita sin aumentos de cuota | Cuenta de facturación de pago |
