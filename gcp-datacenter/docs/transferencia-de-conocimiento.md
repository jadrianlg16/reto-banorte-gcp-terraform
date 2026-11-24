# Plan de transferencia de conocimiento

Tres sesiones de dos horas para el equipo que va a operar la landing zone. Al terminar, ese equipo
debe poder hacer un cambio por PR de principio a fin, dar de alta una aplicación, responder a un
drift y conducir una conmutación a DR con los runbooks, sin ayuda del equipo que la construyó.

Las sesiones siguen el diseño de un solo proyecto (ADR [0029](adr/0029-un-solo-proyecto.md)):
cuatro etapas (`0-bootstrap`, `1-base`, `2-networks` y `3-workloads`), los tres entornos como
VPC y recursos con nombre `<prefix>-<env>-…` dentro del mismo proyecto, y organización opcional.
El plan anterior, de varios proyectos, está en la rama `archivo/multiproyecto`.

**Estado:** propuesta. Fechas, asistentes y modalidad por confirmar con el cliente. Las sesiones 2
y 3 tienen ejercicios que necesitan el proyecto de prueba desplegado
([`guia-colaborador-gcp.md`](guia-colaborador-gcp.md)); sin él, se hacen como recorrido del
procedimiento sobre el repositorio.

## Participantes y preparación

| Rol | Quién | Preparación antes de la sesión 1 |
|---|---|---|
| Expositores | Equipo 2: arquitectura y redes, IaC, seguridad | Proyecto de prueba con la rebanada vertical de la guía (sección E) o el despliegue mínimo; una rama de práctica |
| Operadores | Equipo de plataforma del cliente | Acceso al repositorio con permiso para abrir PR y lanzar flujos; `gcloud`, `gh` y Terraform 1.16.5 instalados; en el grupo `auditors` del proyecto |
| Seguridad | Responsable de seguridad del cliente | Lo mismo, y en el grupo `security_admins` |

Los grupos salen de la variable `groups` de `1-base` y deben ser grupos: las políticas rechazan
`user:`. Sin organización puede que no haya grupos (guía, sección D.3). En ese caso, los
operadores no ven el proyecto en la consola y la persona dueña muestra en pantalla lo que haga
falta.

## Sesión 1. Arquitectura y decisiones (2 h)

**Objetivo:** que los operadores expliquen la arquitectura con sus palabras y sepan dónde está cada
decisión y por qué.

| Tiempo | Tema | Material |
|---|---|---|
| 0:00 – 0:20 | El reto y los objetivos del cliente; criterios de aceptación | `README.md` ("Criterios de aceptación") |
| 0:20 – 0:55 | Recorrido por los cinco diagramas: gobierno y acceso en el proyecto, red hub-and-spoke e híbrida, aplicación y datos, operación y continuidad, pipeline | [`docs/diagramas/`](diagramas/01-organizacion-gobierno-acceso.md) |
| 0:55 – 1:25 | Las cuatro etapas y su orden; un estado por raíz en un solo bucket; qué lee cada raíz de otra | ADR 0029 §2 e "Interfaces entre etapas"; `README.md` |
| 1:25 – 1:45 | Un proyecto para tres entornos: regla de nombres `<prefix>-<env>-`, qué separa a los entornos y qué riesgos se aceptaron; las demás desviaciones y sus ADR | ADR 0029 §4 y §9; [`docs/adr/README.md`](adr/README.md) |
| 1:45 – 2:00 | Ejercicio y cierre | — |

**Ejercicio:** cada operador clona el repositorio, corre `bash scripts/check.sh` sobre una raíz
(por ejemplo `stages/2-networks/envs/dev`) y responde tres preguntas con el ADR y la sección que
corresponden. Ejemplos: ¿por qué Cloud NAT está en cada spoke y no en el hub? Si dev y prod
viven en el mismo proyecto, ¿qué impide que un flujo de dev aplique en prod y qué riesgo se
aceptó (la cuenta de red de dev tiene roles de red sin condición)? ¿Qué pasa con las llaves de
un entorno cuando se destruye?

**Evidencia de cierre:** salida de `check.sh` de cada operador y respuestas con el número de ADR.

## Sesión 2. Operar el repositorio (2 h)

**Objetivo:** que los operadores hagan un cambio real por el pipeline, de la rama al apply, y
sepan responder a un drift.

| Tiempo | Tema | Material |
|---|---|---|
| 0:00 – 0:20 | Identidad del pipeline: WIF, una cuenta por raíz y por entorno que solo se entrega a un trabajo de `main` (`attribute.deploy`), la cuenta de lectura `tf-read`, la política de denegación y su etiqueta; las cuentas de ejecución que crea `1-base`; por qué las personas solo leen | ADR 0029 §3 y §5, ADR 0023, [`pipeline.md`](pipeline.md) §5, [`diagramas/05-pipeline.md`](diagramas/05-pipeline.md) |
| 0:20 – 0:45 | Flujo de un cambio: PR, comprobaciones, plan con huella, aprobación del entorno, apply; qué bloquea un PR; por qué un merge a `main` lanza `apply.yml` (y uno de solo documentación no); cómo se apaga dev o qa con `GCP_DISABLED_ENVS` | `diagramas/05-pipeline.md`, ADR 0025, [`pipeline.md`](pipeline.md) §1.2, `.github/workflows/` |
| 0:45 – 1:20 | Ejercicio guiado: alta de una aplicación en dev | [Runbook 02](runbooks/02-alta-proyecto-aplicacion.md), sección A |
| 1:20 – 1:45 | Drift: cómo se detecta (un plan por raíz y un trabajo de recursos no administrados para todo el proyecto), cómo se lee la incidencia, importar o revertir | [Runbook 05](runbooks/05-respuesta-a-drift.md), `drift.yml` |
| 1:45 – 2:00 | `0-bootstrap`, variables de GitHub (`GCP_TFVARS_JSON` y las salidas de la etapa 0) y cuándo se vuelve a correr la etapa 0 | [Runbook 01](runbooks/01-arranque-etapa-0.md), guía sección D |

**Ejercicios:**

1. Alta de una aplicación nueva hasta `1-base` (runbook 02, pasos A.1 y A.2): registrar el
   cambio en una incidencia, agregar la aplicación a `applications` y un secreto de dev a
   `secret_names` en la llave `stages/1-base` de `GCP_TFVARS_JSON` (lo hace quien administra las
   variables del repositorio), lanzar `apply.yml` y leer en el resumen del trabajo `plan` de
   `1-base`, antes de aprobar `common`, que solo se agregan, en cada entorno, su repositorio, sus
   cuentas de ejecución con sus permisos y, en dev, el contenedor del secreto con su lectura
   para las cuentas `workload` y `run` de todas las aplicaciones de dev.
   Las cargas de una segunda aplicación en el mismo entorno no están soportadas (runbook 02,
   paso A.4): el ejercicio se queda en `1-base`.
2. Abrir un PR que viole una política en una raíz desplegada (por ejemplo, IP pública en la
   instancia de Cloud SQL de dev, o un miembro `user:` en un IAM) y ver que Conftest lo bloquea.
3. La persona dueña del proyecto cambia a mano una etiqueta de un recurso de dev (las personas
   de los grupos solo leen); los operadores corren `drift.yml`, leen la incidencia y lo resuelven
   con el runbook 05.

**Evidencia de cierre:** enlaces a la incidencia y a la ejecución del alta, al PR bloqueado y a
la incidencia de drift cerrada.

## Sesión 3. Seguridad, continuidad y costos (2 h)

**Objetivo:** que seguridad sepa leer SCC contra el mapa CIS y que los operadores conduzcan una
conmutación a DR y su vuelta con el runbook.

| Tiempo | Tema | Material |
|---|---|---|
| 0:00 – 0:25 | Controles de seguridad en el proyecto: CMEK con llaves por entorno (solo las que se usan) y su rotación, política de denegación, reglas de Conftest; con organización, políticas de organización y VPC-SC en dry-run, que aplica la persona de `0-bootstrap`; los controles manuales del CIS | `docs/cumplimiento-cis.md`, [runbook 03](runbooks/03-rotacion-de-llaves.md), runbook 01 ("Controles manuales del CIS") |
| 0:25 – 0:45 | SCC y el CIS: qué evalúa SCC, qué no, desviaciones aceptadas. SCC activado en el proyecto, no en una organización (HYPOTHESIS que funcione sin ella) | `docs/cumplimiento-cis.md` §5 y §6 |
| 0:45 – 1:30 | Simulacro de DR: promover la réplica, `dr_active`, verificación y vuelta con `dr_teardown` | [Runbook 04](runbooks/04-conmutacion-a-dr.md) |
| 1:30 – 1:50 | Costos: dónde se va el dinero y las palancas (modo mínimo, apagado fuera de horario de dev y qa, destroy de dev y qa y `GCP_DISABLED_ENVS` para que no se recreen); Infracost en cada PR | `docs/estimacion-de-costos.md`, ADR 0028, guía sección I |
| 1:50 – 2:00 | Pendientes del primer despliegue y backlog; cierre | `docs/pendientes-apply.md`, `docs/backlog.md` |

**Ejercicio:** conmutación a DR en el proyecto de prueba siguiendo el runbook 04, con un operador
al teclado y otro midiendo los tiempos de cada paso. Necesita prod con DR encendido (guía,
sección F), que es lo más caro del despliegue: se hace en un bloque corto. Sin eso, recorrido de
mesa del runbook con los comandos y las salidas esperadas.

**Evidencia de cierre:** tiempos medidos de la conmutación (RTO) y del dato más reciente
recuperado (RPO), o el recorrido de mesa firmado.

## Al terminar

- Lista de asistencia de las tres sesiones y las evidencias de cierre de cada una.
- Preguntas abiertas registradas como incidencias del repositorio.
- Firma de recibido por el responsable del cliente (forma parte del acta de aceptación).
- Apagar lo que se encendió para los ejercicios (guía, sección I).
