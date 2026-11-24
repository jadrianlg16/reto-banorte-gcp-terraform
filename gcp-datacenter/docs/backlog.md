# Backlog para terminar el proyecto

Lo que falta para dar el proyecto por completo, al **24 nov 2026**. El diseño es de un solo
proyecto con tres entornos ([ADR 0029](adr/0029-un-solo-proyecto.md); plan en
[`plan-rediseno-un-proyecto.md`](plan-rediseno-un-proyecto.md)). El de 10 proyectos queda en la
rama `archivo/multiproyecto`. Lo que queda es de cuatro tipos:

- decisiones y trámites del equipo;
- la entrega final de la Fase 4 (presentación, video y documentos);
- el despliegue en un proyecto de GCP;
- mejoras de diseño que decidimos no construir.

Prioridades:

- **P0:** bloquea la entrega final (3 dic 2026, fecha que maneja el equipo; confirmarla en Canvas).
- **P1:** necesario para cerrar los criterios de aceptación del README.
- **P2:** mejora; el proyecto se puede entregar sin ella, con el hueco documentado.

Cuando se cierre una tarea, márcala con la fecha y la evidencia (enlace a la ejecución, PR o
captura), igual que en [`pendientes-apply.md`](pendientes-apply.md).

---

## 1. Decisiones y trámites del dueño del repositorio y del equipo

| # | Prioridad | Tarea | Por qué | Cómo se cierra |
|---|---|---|---|---|
| D1 | P0 | Decidir si el proyecto estará dentro de una organización de GCP (dominio y Cloud Identity) o será un proyecto suelto con facturación | Sin organización no hay políticas de organización ni perímetro de VPC-SC. Diez filas del mapa CIS quedan como "Solo con organización" ([`cumplimiento-cis.md`](cumplimiento-cis.md)). Con organización, `0-bootstrap` da a `tf-base` `orgpolicy.policyAdmin` en toda la organización (pendientes, §5) | Decisión anotada. Con organización, la persona llena `org_id` y `access_policy_id` en `0-bootstrap` y `1-base`, más `directory_customer_id` en `1-base` |
| D2 | P0 | Rol de cada integrante para su tarjeta de presentación, y si lleva foto | Lámina 15 del [plan de la presentación](plan-presentacion-final.md) (§5, punto 3) | Nombre, matrícula y rol de cada integrante entregados a quien arma la presentación |
| D3 | P0 | Resto de las decisiones abiertas del plan de la presentación | Duración de la presentación y del video, si el video va dentro o aparte, quién narra y quién edita, Google Slides o PowerPoint (§5, puntos 1, 2 y 4) | Las cuatro respuestas anotadas en el plan |
| D4 | P0 | Subir a GitHub la rama del rediseño (`feat/un-proyecto`, con lo integrado de R1 a R3) | El colaborador de GCP clona desde ahí; hoy la rama no tiene rama remota (`git branch -a`, 24 nov 2026) | `git push -u origin feat/un-proyecto` |
| D5 | P0 | Agregar al colaborador de GCP al repositorio privado | Sin acceso no puede clonar ni lanzar flujos | GitHub → Settings → Collaborators |
| D6 | P0 | Abrir el PR a `main` e integrarlo | `apply.yml` y `destroy.yml` solo corren desde `main`. Integrar a `main` dispara `apply.yml`; con `GCP_ENABLED` distinto de `"true"` no aplica nada en GCP | PR revisado e integrado |
| D7 | P1 | Decidir el plan de GitHub | En un repositorio privado de cuenta gratuita no hay protección de rama ni revisores en entornos: `apply.yml` no se detiene antes de `common` y `prod` (pendiente 12) | Plan elegido y anotado en el pendiente 12 |
| D8 | P1 | "Deployment branches: `main`" en los cuatro entornos de GitHub (`common`, `dev`, `qa`, `prod`) | Las cuentas de raíz solo aceptan tokens de su entorno (`attribute.environment`); sin esa regla, un flujo de otra rama puede usar el entorno (pendiente 121) | Regla configurada y verificada como dice el pendiente 121 |
| D9 | P1 | Aceptar o reducir el alcance de `tf-read` | Lee todos los estados, incluido el del hub con el secreto de la VPN, y la toma cualquier trabajo del repositorio (pendiente 122) | Decisión anotada en el pendiente 122 |
| D10 | P1 | Usuarios de GitHub del equipo en `CODEOWNERS` | Hoy tiene los marcadores `@PENDIENTE-red`, `@PENDIENTE-seguridad` y `@PENDIENTE-plataforma` (`.github/CODEOWNERS`) | Marcadores reemplazados por usuarios reales |
| D11 | P1 | Protección de `main` con las comprobaciones obligatorias de `pr.yml` (incluida `plan-gate`) | Sin ella, un PR que viola una política no queda bloqueado de verdad (criterio "el pipeline bloquea un PR") | Configuración de [`pipeline.md`](pipeline.md) hecha, si el plan de GitHub lo permite |
| D12 | P2 | Revisores en los entornos de GitHub `dev` y `qa` | La única barrera humana de `destroy.yml` es la confirmación escrita (pendientes, §5) | Revisores configurados, o la decisión de no hacerlo anotada |
| D13 | P2 | Secreto `INFRACOST_API_KEY` | Sin él, `pr.yml` omite el costo por PR | Secreto creado, o la omisión aceptada |

## 2. Entrega final de la Fase 4 (equipo)

Banorte pidió en la junta del 23 nov 2026 un video de la ejecución y una presentación con más
storytelling, íconos oficiales y tarjetas del equipo. El plan está en
[`plan-presentacion-final.md`](plan-presentacion-final.md). Los documentos de la entrega (memoria
técnica, resumen ejecutivo y presentación) se generan fuera de este repositorio. Se generaron antes
del rediseño del 24 nov, así que describen el diseño de 10 proyectos.

| # | Prioridad | Tarea |
|---|---|---|
| F1 | P0 | Confirmar en Canvas la fecha de entrega y lo que se pide además de los documentos: bitácora del equipo, evidencias, firmas o formatos del curso |
| F2 | P0 | Regenerar la memoria técnica y el resumen ejecutivo con el diseño de un solo proyecto. Se toman del ADR 0029, el README, los diagramas nuevos, el mapa CIS y la [estimación de costos](estimacion-de-costos.md). Confirmar lo resaltado en amarillo: lecciones aprendidas, fechas y asistentes de la transferencia de conocimiento, y cualquier dato que el equipo quiera corregir |
| F3 | P0 | Rehacer los cuatro [diagramas](diagramas/) con los íconos oficiales y el estilo de la referencia de Google (plan, §1 y §3): recuadro de Google Cloud, proyecto, regiones, zonas, VPC y subredes, con lo opcional en línea punteada. El diagrama 4 debe incluir `destroy.yml`, el apagado fuera de horario (ADR 0028) y las alertas de auditoría del CIS (módulo `audit-alerts`) |
| F4 | P0 | Presentación nueva de 17 láminas, según la historia del plan (§1). Lleva las tarjetas de producto con íconos, "por qué estos componentes" con su ADR, la lámina del equipo (D2) y el código al final |
| F5 | P0 | Video de 4 a 6 min ya editado, según el guion del plan (§2). Se graba en el ensayo de R5 (G8), se edita con voz y subtítulos, y una segunda persona lo revisa cuadro por cuadro antes de entregarlo (lista "No mostrar" del plan) |
| F6 | P1 | Lámina de resultados con lo **medido** separado de lo **diseñado y sin medir**: tiempo de despliegue, pruebas y costo del despliegue de prueba frente a 99.9 %, RTO y RPO de DR y CIS completo. Si llega a tiempo, lleva el costo real del ensayo |
| F7 | P0 | Ensayar la presentación con tiempos (2 dic) |
| F8 | P0 | Subir los entregables a Canvas (3 dic) |

## 3. Depende de GCP (colaborador con la cuenta)

Se hace con [`guia-colaborador-gcp.md`](guia-colaborador-gcp.md), que trae el prompt para Claude
Code, y en el orden del [plan de rediseño](plan-rediseno-un-proyecto.md):

1. primero la rebanada vertical real (R4);
2. después el despliegue mínimo y el ensayo de la grabación (R5);
3. al final, los criterios que piden el diseño completo.

Las etapas 1 a 3 solo las aplica el pipeline. La etapa 0 es la única manual
([runbook 01](runbooks/01-arranque-etapa-0.md)).

### R4: rebanada vertical real (cuando haya proyecto; ideal 27 a 28 nov)

| # | Prioridad | Tarea | Cierra |
|---|---|---|---|
| G1 | P0 | La persona crea el proyecto y le vincula facturación. Si D1 dice "con organización": antes, dominio, Cloud Identity y organización | Requisito de todo lo demás |
| G2 | P0 | Borrar la red `default` antes de `0-bootstrap` (ADR 0029 §6; el runbook 01 todavía no tiene ese paso). Después, etapa 0 a mano (`0-bootstrap`, runbook 01) y estado movido al bucket | Puntos 90 a 96 |
| G3 | P0 | Configurar GitHub: <br>• variables del repositorio; <br>• `GCP_AUDIT_SERVICE_ACCOUNT` = salida `read_service_account` de `0-bootstrap` (`tf-read`, punto 50); <br>• `GCP_TFVARS_JSON` de la rebanada; <br>• los cuatro entornos con sus ramas de despliegue (D8) | — |
| G4 | P0 | Primer `apply.yml` de la rebanada: `1-base`, hub, spoke de dev y `3-workloads/envs/dev` con Cloud Run y Cloud SQL. Lo que falle se corrige en una rama `fix/<tema>` con PR | Primer `apply.yml` en verde; puntos 55 y 114 |
| G5 | P0 | Prueba de humo de dev y `drift.yml` en verde sobre la rebanada | Puntos 50, 117 y, para dev, 11 y 80 |

### R5: despliegue mínimo, ensayo y grabación (28 a 29 nov)

| # | Prioridad | Tarea | Cierra |
|---|---|---|---|
| G6 | P0 | Desplegar el resto en modo mínimo y medir el tiempo (objetivo: menos de 90 min). Es el escenario B de la [estimación de costos](estimacion-de-costos.md): qa y prod sin GKE, MIG, Filestore, Memorystore ni balanceador interno, y 20.45 a 21.94 USD/día | Criterio "despliegue limpio" |
| G7 | P1 | `drift.yml` en verde después del despliegue mínimo | Criterio "segundo `plan` sin cambios" (pendientes 11 y 80) |
| G8 | P0 | Ensayo de la grabación y grabación de las escenas 0 a 7 del plan de la presentación (§2), sobre una ejecución ya probada | Video en bruto (F5) |
| G9 | P1 | PR de prueba que viole una política y quede bloqueado (escena 2) | Criterio "el pipeline bloquea un PR" (pendientes 12 y 51) |
| G10 | P1 | `destroy.yml` de dev en verde, con la búsqueda de huérfanos (escena 7) | Criterio "`destroy` de dev sin huérfanos" (pendientes 11, 85, 86, 87 y 89) |

### Después del ensayo: criterios que piden el diseño completo

| # | Prioridad | Tarea | Cierra |
|---|---|---|---|
| G11 | P1 | VM DNS a mano en `onprem-sim` y cómputo de prod; Connectivity Test desde prod | Criterio "una VM de prod alcanza on-premises" (pendientes 6, 7, 36 y 37) |
| G12 | P1 | Activar SCC y evaluar el CIS ([`cumplimiento-cis.md`](cumplimiento-cis.md) §6) | Criterio "sin hallazgos críticos ni altos" (pendientes 2, 23 y 56) |
| G13 | P1 | Escribir el procedimiento de acceso de emergencia de la persona dueña del proyecto antes del simulacro de DR | Pendientes, §5, "El acceso de emergencia es la persona dueña del proyecto"; requisito de G14 |
| G14 | P1 | DR encendido y simulacro del runbook 04, midiendo RTO (4 h) y RPO (15 min) | Criterio "simulacro de DR dentro del RTO" |
| G15 | P1 | Recursos no administrados de `drift.yml` contra el proyecto real | Criterio "cero recursos a mano" (pendientes 49 y 118) |
| G16 | P1 | Apagado fuera de horario: ver una noche y una mañana en dev o qa | Pendientes 70 a 73 y 75 a 81 (el 74 es obsoleto) |
| G17 | P1 | Marcar cada punto de `pendientes-apply.md` comprobado y cada marcador `VERIFICAR-EN-APPLY` resuelto | Hoy hay 94 puntos abiertos de 112: 15 obsoletos y 3 resueltos en el código. La §4 tiene 103 filas con `ruta:línea`, que cubren los 123 marcadores de los `.tf`; los de `envs/*` cuentan una vez por los tres entornos |
| G18 | P2 | Regenerar al menos un plan de ejemplo de Conftest por regla desde un plan real | Pendientes, §5, "Planes de ejemplo de Conftest" |
| G19 | P2 | Terratest y prueba de extremo a extremo contra GCP, de preferencia en un proyecto de pruebas aparte | Pendientes, §5, "Terratest y prueba de extremo a extremo sin ejecutar" (puntos 119 y 120); `terratest.yml` en verde |
| G20 | P0 | Apagar todo al terminar: `destroy.yml` de dev y qa; después, la persona dueña borra el proyecto o desmonta a mano el hub, `1-base` y la etapa 0, y desvincula la facturación | Costo en cero |

De los nueve criterios de aceptación del README, solo "cada módulo tiene README, ejemplo y prueba"
está demostrado completo sin GCP. Los otros ocho se cierran con G6, G7, G9, G10, G11, G12, G14 y
G15.

## 4. Mejoras de diseño no construidas

Cada una está documentada como hueco conocido, con lo que haría falta. Ninguna bloquea la entrega.

| # | Tema | Hueco | Qué haría falta | Dónde está escrito |
|---|---|---|---|---|
| M1 | Identidad del pipeline | **Mitigado en parte por el ADR 0029 §3:** las cuentas de raíz solo aceptan tokens de su entorno de GitHub (`attribute.environment`), y los `plan` de los PR usan `tf-read`. Queda que la barrera real es la configuración de los entornos (D7, D8), y que `tf-read` la toma cualquier trabajo del repositorio | Condición por `attribute.ref` además del entorno, y `tf-read` limitado a los prefijos que necesita cada plan | Pendientes, §5, "WIF"; puntos 121 y 122; `pipeline.md` |
| M2 | Separación de entornos (CIS 1.7) | `tf-wl-<env>` tiene `iam.serviceAccountUser` y `TfServiceAccountManager` en todo el proyecto: la cuenta de dev puede adjuntar una cuenta de prod a una VM y, si la etiqueta de protección falla, cambiar el IAM de `tf-base` | **`1-base` crea las cuentas de ejecución** de cada entorno, y `tf-wl-<env>` recibe `serviceAccountUser` solo sobre las de su entorno | Pendientes, §5, "Lo que ya no separa a los entornos"; `cumplimiento-cis.md`, 1.7 |
| M3 | Binary Authorization | Una sola política con lista de permitidos global: una imagen del repositorio de dev pasa en prod (desviación del ADR 0029 §4) | **Atestaciones:** un attestor que firme en el pipeline las imágenes promovidas a prod, y reglas por clúster de prod que lo exijan | Pendientes, §5; punto 42 |
| M4 | CIS 1.6 | Cuentas `<prefix>-tf-*` con roles de administrador | Roles personalizados más estrechos por etapa (ya hay cinco en `0-bootstrap`) | ADR 0027 |
| M5 | CIS 2.3 | El sink de proyecto solo exporta auditoría | Exportar también flow logs, DNS y balanceador, con su costo | ADR 0027 |
| M6 | CIS 2.4 | Retención del bucket de logs sin bloquear | `log_retention_locked = true` después de probarlo (es irreversible) | ADR 0027; pendiente 15 |
| M7 | CIS 3.9 | API de Google por el VIP restringido, no por Private Service Connect | Endpoint de PSC por VPC, si el cliente lo exige | ADR 0026 y 0027 |
| M8 | CIS 4.11 | Sin Confidential Computing | Tipos N2D y `confidential_instance_config` en el MIG y GKE | ADR 0027 |
| M9 | CIS 4.12 | VM del MIG sin parches entre imágenes | VM Manager o publicar imágenes con más frecuencia | ADR 0027 |
| M10 | Apagado | Sin alerta si falla un trabajo de Cloud Scheduler; sin flujo para encender a mano | Alerta de Cloud Monitoring sobre sus registros; flujo con la cuenta `tf-wl-<env>` | Pendientes, §5; ADR 0028 |
| M11 | Destroy | Solo las cargas de dev y qa y, con `incluir_red`, su spoke. prod, hub, `1-base` y la etapa 0 se desmontan a mano | Runbook de desmontaje completo; en un proyecto de prueba, borrar el proyecto | Pendientes, §5, "`destroy.yml` solo destruye las cargas de dev y qa" |
| M12 | Destroy | Bucket de la aplicación sin `force_destroy` | `force_destroy` fuera de prod, o un paso para vaciarlo | Pendiente 89 |
| M13 | Red | Servicios de PSA y plano de control de GKE no alcanzables desde on-premises | Proxy o bastión en el spoke, o exportar las rutas del peering de servicios | Pendientes, §5 |
| M14 | Datos | Memorystore sin AUTH; Memorystore y Filestore sin DR; sin restauración de Backup for GKE | Redis Cluster con IAM; instancias en `dr_region`; plan de restauración | Pendientes, §5; ADR 0015 |
| M15 | Operación | Nadie puede cargar valores de secretos ni entrar por IAP | `secretVersionAdder` y `iap.tunnelResourceAccessor` a grupos definidos, en `1-base` | Pendientes, §5 |
| M16 | Escala | Una sola aplicación con cargas por raíz de `3-workloads/envs/<env>` (`1-base` ya crea repositorios y secretos para varias) | Raíz o espacio de trabajo por aplicación que recorran `apply.yml` y `drift.yml` | Pendientes, §5; runbook 02 |
| M17 | Escala | Los tres entornos, el hub y las pruebas comparten las cuotas del proyecto | Aumentos de cuota antes de prod completo y un proyecto de pruebas aparte | Pendientes, §5, "Cuotas compartidas"; ADR 0029 §10 |
| M18 | Servicios | Cloud IDS y Private Service Connect no se construyen | Módulo nuevo y ADR, si se piden | Pendientes, §5 |
| M19 | Cierre | Acta de aceptación con el cliente | Recorrer la tabla de criterios con evidencia y firmar | — |
