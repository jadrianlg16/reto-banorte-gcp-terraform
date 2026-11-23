# Plan de transferencia de conocimiento

Tres sesiones de dos horas para el equipo que va a operar la landing zone. Al terminar, ese equipo
debe poder hacer un cambio por PR de principio a fin, dar de alta una aplicación, responder a un
drift y conducir una conmutación a DR con los runbooks, sin ayuda del equipo que la construyó.

**Estado:** propuesta. Fechas, asistentes y modalidad por confirmar con el cliente. Las sesiones 2
y 3 tienen ejercicios que necesitan la organización de prueba desplegada
([`guia-colaborador-gcp.md`](guia-colaborador-gcp.md)); sin ella, se hacen como recorrido del
procedimiento sobre el repositorio.

## Participantes y preparación

| Rol | Quién | Preparación antes de la sesión 1 |
|---|---|---|
| Expositores | Equipo 2: arquitectura y redes, IaC, seguridad | Organización de prueba desplegada con el despliegue mínimo; una rama de práctica |
| Operadores | Equipo de plataforma del cliente | Acceso de lectura al repositorio; `gcloud`, `gh` y Terraform 1.16.5 instalados; miembro del grupo `auditors` en la organización de prueba |
| Seguridad | Responsable de seguridad del cliente | Lo mismo, y miembro de `security_admins` |

## Sesión 1. Arquitectura y decisiones (2 h)

**Objetivo:** que los operadores expliquen la arquitectura con sus palabras y sepan dónde está cada
decisión y por qué.

| Tiempo | Tema | Material |
|---|---|---|
| 0:00 – 0:20 | El reto y los objetivos del cliente; criterios de aceptación | `README.md` ("Criterios de aceptación") |
| 0:20 – 0:55 | Recorrido por los diagramas: jerarquía y gobierno, red hub-and-spoke e híbrida, cómputo y datos, CI/CD | `docs/diagramas/`, láminas de la Fase 4 |
| 0:55 – 1:25 | Las seis etapas y su orden; estado por prefijo; interfaces entre etapas | `README.md` ("Despliegue"), `docs/CONTRATO.md` |
| 1:25 – 1:45 | Desviaciones respecto al documento del cliente y sus ADR | `docs/adr/` (índice en `docs/adr/README.md`) |
| 1:45 – 2:00 | Ejercicio y cierre | — |

**Ejercicio:** cada operador clona el repositorio, corre `bash scripts/check.sh` en una raíz y
responde tres preguntas con el ADR que corresponde (por ejemplo: ¿por qué Cloud NAT está en cada
spoke y no en el hub?).

**Evidencia de cierre:** salida de `check.sh` de cada operador y respuestas con el número de ADR.

## Sesión 2. Operar el repositorio (2 h)

**Objetivo:** que los operadores hagan un cambio real por el pipeline, de la rama al apply, y
sepan responder a un drift.

| Tiempo | Tema | Material |
|---|---|---|
| 0:00 – 0:20 | Identidad del pipeline: WIF, una cuenta por etapa, por qué las personas solo leen | `docs/pipeline.md` §1 y §5, ADR 0023 |
| 0:20 – 0:45 | Flujo de un cambio: PR, revisiones, plan con huella, aprobación, apply; qué bloquea un PR | `docs/pipeline.md` §1, ADR 0025 |
| 0:45 – 1:20 | Ejercicio guiado: alta de un proyecto de aplicación en dev | Runbook 02 |
| 1:20 – 1:45 | Drift: cómo se detecta, cómo se lee la incidencia, importar o revertir | Runbook 05, `drift.yml` |
| 1:45 – 2:00 | Variables de GitHub, etapa 0 y cuándo se vuelve a correr | Runbook 01, `docs/pipeline.md` §2 a §4 |

**Ejercicios:**

1. Abrir un PR que agregue una aplicación en dev (runbook 02), leer el plan comentado y, tras la
   aprobación, ver el apply en `apply.yml`.
2. Abrir un PR que viole una política (por ejemplo, una IP pública en una VM) y ver que Conftest
   lo bloquea.
3. Un administrador de la organización de prueba cambia a mano una etiqueta de un recurso de dev
   (las personas de los grupos solo leen); los operadores corren `drift.yml` y lo resuelven con
   el runbook 05.

**Evidencia de cierre:** enlaces a los dos PR y a la incidencia de drift cerrada.

## Sesión 3. Seguridad, continuidad y costos (2 h)

**Objetivo:** que seguridad sepa leer SCC contra el mapa CIS y que los operadores conduzcan una
conmutación a DR y su vuelta con el runbook.

| Tiempo | Tema | Material |
|---|---|---|
| 0:00 – 0:25 | Controles de seguridad: políticas de organización, CMEK y rotación, VPC-SC en dry-run y cómo forzarlo | `docs/cumplimiento-cis.md`, runbook 03, ADR 0009 |
| 0:25 – 0:45 | SCC y el CIS: qué evalúa SCC, qué no, desviaciones aceptadas | `docs/cumplimiento-cis.md` §5 y §6 |
| 0:45 – 1:30 | Simulacro de DR: promover la réplica, `dr_active`, verificación y vuelta con `dr_teardown` | Runbook 04 |
| 1:30 – 1:50 | Costos: dónde se va el dinero y las palancas; Infracost en cada PR | `docs/estimacion-de-costos.md` |
| 1:50 – 2:00 | Pendientes del primer despliegue y backlog; cierre | `docs/pendientes-apply.md`, `docs/backlog.md` |

**Ejercicio:** conmutación a DR en la organización de prueba siguiendo el runbook 04, con un
operador al teclado y otro midiendo los tiempos de cada paso. Sin la organización, recorrido de
mesa del runbook con los comandos y las salidas esperadas.

**Evidencia de cierre:** tiempos medidos de la conmutación (RTO) y del dato más reciente
recuperado (RPO), o el recorrido de mesa firmado.

## Al terminar

- Lista de asistencia de las tres sesiones y las evidencias de cierre de cada una.
- Preguntas abiertas registradas como incidencias del repositorio.
- Firma de recibido por el responsable del cliente (forma parte del acta de aceptación).
