# Backlog para terminar el proyecto

Lo que falta para dar el proyecto por completo, al **23 nov 2026**. Todo lo que se podía construir
y probar sin Google Cloud está hecho y pasa `check.sh`, `policy-check.sh`, `selftest.sh` y
`docs.sh --check`. Lo que queda es de tres tipos: decisiones y trámites del equipo, el despliegue
en una organización de GCP, y mejoras de diseño que decidimos no construir.

Prioridades:

- **P0:** bloquea la entrega final (3 dic 2026, fecha que maneja el equipo; confirmarla en Canvas).
- **P1:** necesario para cerrar los criterios de aceptación del README.
- **P2:** mejora; el proyecto se puede entregar sin ella, con el hueco documentado.

Cuando se cierre una tarea, márcala con la fecha y la evidencia (enlace a la ejecución, PR o
captura), igual que en [`pendientes-apply.md`](pendientes-apply.md).

---

## 1. Decisiones y trámites del dueño del repositorio

| # | Prioridad | Tarea | Por qué | Cómo se cierra |
|---|---|---|---|---|
| D1 | P0 | Subir la rama `feat/gcp-datacenter-build` a GitHub | El colaborador de GCP clona desde ahí (guía, sección B) | `git push -u origin feat/gcp-datacenter-build` |
| D2 | P0 | Agregar al colaborador de GCP al repositorio privado | Sin acceso no puede clonar ni lanzar flujos | GitHub → Settings → Collaborators |
| D3 | P0 | Abrir el PR a `main` e integrarlo | `apply.yml` y `destroy.yml` solo corren desde `main` (guía, D.1). Integrar a `main` dispara `apply.yml`; con `GCP_ENABLED` distinto de `"true"` no aplica nada en GCP | PR revisado e integrado |
| D4 | P1 | Decidir el plan de GitHub | En un repositorio privado de cuenta gratuita no hay protección de rama ni revisores en entornos: `apply.yml` no se detiene antes de `common` y `prod` (pendiente 12) | Plan elegido y anotado en el pendiente 12 |
| D5 | P1 | Usuarios de GitHub del equipo en `CODEOWNERS` | Hoy tiene marcadores `@PENDIENTE-red`, `@PENDIENTE-seguridad` y `@PENDIENTE-plataforma` (`.github/CODEOWNERS`) | Marcadores reemplazados por usuarios reales |
| D6 | P1 | Protección de `main` con las comprobaciones obligatorias de `pr.yml` (incluida `plan-gate`) | Sin ella, un PR que viola una política no queda bloqueado de verdad (criterio "el pipeline bloquea un PR") | Configuración de [`pipeline.md`](pipeline.md) §4 hecha, si el plan de GitHub lo permite |
| D7 | P2 | Revisores en los entornos de GitHub `dev` y `qa` | La única barrera humana de `destroy.yml` es la confirmación escrita (pendientes, §5) | Revisores configurados, o la decisión de no hacerlo anotada |
| D8 | P2 | Secreto `INFRACOST_API_KEY` | Sin él, `pr.yml` omite el costo por PR | Secreto creado, o la omisión aceptada |

## 2. Entrega final de la Fase 4 (equipo)

Los documentos de la entrega (memoria técnica, resumen ejecutivo y presentación) se generan fuera
de este repositorio. Lo que el equipo tiene que poner o confirmar está resaltado en amarillo en
cada documento.

| # | Prioridad | Tarea |
|---|---|---|
| F1 | P0 | Confirmar la fecha de entrega y lo resaltado: lecciones aprendidas, fechas y asistentes de la transferencia de conocimiento, y cualquier dato que el equipo quiera corregir |
| F2 | P0 | Completar lo que pida Canvas además de los documentos (bitácora del equipo, evidencias, firmas o formatos del curso) |
| F3 | P0 | Ensayar la presentación con tiempos |
| F4 | P0 | Subir los entregables a Canvas |
| F5 | P1 | Si hay despliegue antes de la entrega: actualizar las secciones de resultados con las evidencias del despliegue (tabla de criterios, costos reales y tiempos) |
| F6 | P2 | Agregar al [diagrama 4](diagramas/04-operacion-continuidad-automatizacion.md) y a su lámina lo construido el 23 nov: `destroy.yml`, el apagado fuera de horario (ADR 0028) y las alertas de auditoría del CIS (módulo `audit-alerts`). Hoy no aparecen (`grep -li "destroy\|apagado\|audit-alerts" docs/diagramas/04*` no da resultados, 23 nov 2026) |

## 3. Depende de GCP (colaborador con la cuenta)

Se hace con [`guia-colaborador-gcp.md`](guia-colaborador-gcp.md), que trae el prompt para Claude
Code. Las secciones de la guía van en este orden.

| # | Prioridad | Tarea | Guía | Cierra |
|---|---|---|---|---|
| G1 | P1 | Dominio, Cloud Identity Free, organización, facturación, grupos y roles | A | Requisito de todo lo demás |
| G2 | P1 | Controles manuales del CIS en Cloud Identity, con su evidencia | A.5 y runbook 01, "Controles manuales del CIS" | 7 recomendaciones "Manual" del mapa CIS |
| G3 | P1 | Etapa 0 a mano, mover el estado al bucket, activar SCC | C | Pendientes de la etapa 0 |
| G4 | P1 | Variables de GitHub, cuenta de auditoría y `GCP_TFVARS_JSON` mínimo | D.2 y D.3 | — |
| G5 | P1 | Primer `apply.yml` del despliegue mínimo, con el tiempo medido (objetivo: menos de 90 min) | D.4 | Criterio "despliegue limpio" |
| G6 | P1 | `drift.yml` después del apply, en verde | F | Criterio "segundo `plan` sin cambios" (pendientes 11 y 80) |
| G7 | P1 | PR de prueba que viole una política y quede bloqueado | F | Criterio "el pipeline bloquea un PR" (pendientes 12 y 51) |
| G8 | P1 | VM DNS a mano en `onprem-sim` y cómputo de prod; Connectivity Test desde prod | E y F | Criterio "una VM de prod alcanza on-premises" (pendientes 6, 7, 36 y 37) |
| G9 | P1 | Evaluación de SCC y del CIS | F; [`cumplimiento-cis.md`](cumplimiento-cis.md) §6 | Criterio "sin hallazgos críticos ni altos" (pendientes 2 y 56) |
| G10 | P1 | Definir el acceso de emergencia antes del simulacro de DR | Pendientes, §5, "Sin acceso de emergencia" | Requisito de G11 |
| G11 | P1 | DR encendido y simulacro del runbook 04, midiendo RTO (4 h) y RPO (15 min) | E | Criterio "simulacro de DR dentro del RTO" |
| G12 | P1 | Recursos no administrados de `drift.yml` contra la carpeta real | F | Criterio "cero recursos a mano" (pendiente 49) |
| G13 | P1 | `destroy.yml` de dev, en verde con la búsqueda de huérfanos | H | Criterio "`destroy` de dev sin huérfanos" (pendientes 11 y 85 a 89) |
| G14 | P1 | Apagado fuera de horario: ver una noche y una mañana en dev o qa | D.3 | Pendientes 70 a 81 |
| G15 | P1 | Marcar cada punto de `pendientes-apply.md` comprobado y cada marcador `VERIFICAR-EN-APPLY` resuelto | F | 74 puntos abiertos (79 menos los 5 resueltos en el código: 19, 20, 21, 25 y 26); 96 marcadores distintos (§4) |
| G16 | P2 | Regenerar al menos un plan de ejemplo de Conftest por regla desde un plan real | — | Pendientes, §5, "Planes de ejemplo" |
| G17 | P2 | Terratest y prueba de extremo a extremo contra GCP | F; [`tests/README.md`](../tests/README.md) | Pendiente 42; `terratest.yml` en verde |
| G18 | P1 | Apagar todo al terminar y desvincular la facturación | H | Costo en cero |

De los nueve criterios de aceptación del README, solo "cada módulo tiene README, ejemplo y
prueba" está demostrado completo sin GCP. Los otros ocho se cierran con G5 a G13.

## 4. Mejoras de diseño no construidas

Cada una está documentada como hueco conocido, con lo que haría falta. Ninguna bloquea la entrega.

| # | Tema | Hueco | Qué haría falta | Dónde está escrito |
|---|---|---|---|---|
| M1 | Identidad del pipeline | WIF confía en el repositorio, no en la rama ni el entorno | Condición por `attribute.ref` o `attribute.environment` y cuentas de solo lectura para los `plan` de los PR | Pendientes, §5; `pipeline.md` §5 |
| M2 | CIS 1.6 | Cuentas `<prefix>-tf-*` con roles de administrador | Roles personalizados más estrechos por etapa | ADR 0027 |
| M3 | CIS 2.1 | Registros de acceso a datos solo en prod y en el semilla | Encenderlos en `common` (al menos `security`), dev y qa, con su costo | ADR 0027 |
| M4 | CIS 2.3 | El sink agregado solo exporta auditoría | Exportar también flow logs, DNS y balanceador, con su costo | ADR 0027 |
| M5 | CIS 2.4 | Retención del bucket de logs sin bloquear | `log_retention_locked = true` después de probarlo (es irreversible) | ADR 0027; pendiente 15 |
| M6 | CIS 3.9 | API de Google por el VIP restringido, no por Private Service Connect | Endpoint de PSC por VPC, si el cliente lo exige | ADR 0026 y 0027 |
| M7 | CIS 4.11 | Sin Confidential Computing | Tipos N2D y `confidential_instance_config` en el MIG y GKE | ADR 0027 |
| M8 | CIS 4.12 | VM del MIG sin parches entre imágenes | VM Manager o publicar imágenes con más frecuencia | ADR 0027 |
| M9 | Apagado | Sin alerta si falla un trabajo de Cloud Scheduler; sin flujo para encender a mano | Alerta de Cloud Monitoring sobre sus registros; flujo con la cuenta de la etapa 5 | Pendientes, §5; ADR 0028 |
| M10 | Destroy | Solo dev y qa; prod, hub y etapas 0 a 2 se desmontan a mano | Flujo o runbook de desmontaje completo | Pendientes, §5; guía, H |
| M11 | Destroy | Bucket de la aplicación sin `force_destroy` | `force_destroy` fuera de prod, o un paso para vaciarlo | Pendiente 89 |
| M12 | Red | Servicios de PSA y plano de control de GKE no alcanzables desde on-premises | Proxy o bastión en el spoke, o exportar las rutas del peering de servicios | Pendientes, §5 |
| M13 | Datos | Memorystore sin AUTH; Memorystore y Filestore sin DR; sin restauración de Backup for GKE | Redis Cluster con IAM; instancias en `dr_region`; plan de restauración | Pendientes, §5; ADR 0015 |
| M14 | Operación | Nadie puede cargar valores de secretos ni entrar por IAP | `secretVersionAdder` y `iap.tunnelResourceAccessor` a grupos definidos | Pendientes, §5 |
| M15 | Escala | Una sola aplicación por raíz de `5-workloads` | Raíz o espacio de trabajo por aplicación que recorran `apply.yml` y `drift.yml` | Pendientes, §5; runbook 02 |
| M16 | Servicios | Cloud IDS y Private Service Connect no se construyen | Módulo nuevo y ADR, si se piden | Pendientes, §5 |
| M17 | Cierre | Acta de aceptación con el cliente | Recorrer la tabla de criterios con evidencia y firmar | — |
