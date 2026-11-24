# Backlog para terminar el proyecto

Lo que falta para dar el proyecto por completo, al **24 nov 2026**. El diseño es de un solo
proyecto con tres entornos ([ADR 0029](adr/0029-un-solo-proyecto.md); plan en
[`plan-rediseno-un-proyecto.md`](plan-rediseno-un-proyecto.md)). El de 10 proyectos queda en la
rama `archivo/multiproyecto`. Lo que queda es de cinco tipos:

- decisiones y trámites del equipo;
- la entrega final de la Fase 4 (presentación, video y documentos);
- el despliegue en un proyecto de GCP;
- mejoras de diseño que decidimos no construir;
- documentación que falta corregir (§6).

Prioridades:

- **P0:** bloquea la entrega final (3 dic 2026, fecha que maneja el equipo; confirmarla en Canvas).
- **P1:** necesario para cerrar los criterios de aceptación del README.
- **P2:** mejora; el proyecto se puede entregar sin ella, con el hueco documentado.

Cuando se cierre una tarea, márcala con la fecha y la evidencia (enlace a la ejecución, PR o
captura), igual que en [`pendientes-apply.md`](pendientes-apply.md). Las rutas son relativas a
`gcp-datacenter/`. Los números de punto (`punto N`) son los de ese archivo; del 123 al 151 son los agregados por los arreglos de R2. La
§5 lista lo que esos arreglos ya cerraron en el código.

---

## 1. Decisiones y trámites del dueño del repositorio y del equipo

| # | Prioridad | Tarea | Por qué | Cómo se cierra |
|---|---|---|---|---|
| D1 | P0 | Decidir si el proyecto estará dentro de una organización de GCP (dominio y Cloud Identity) o será un proyecto suelto con facturación | Sin organización no hay políticas de organización ni perímetro de VPC-SC. Varias filas del mapa CIS quedan como "Solo con organización" ([`cumplimiento-cis.md`](cumplimiento-cis.md)). Con organización, las políticas de organización y el perímetro en dry-run los aplica la persona de `0-bootstrap` (`stages/0-bootstrap/org.tf`); ninguna cuenta del pipeline recibe roles de organización (puntos 125 y 126) | Decisión anotada. Con organización, la persona llena `org_id`, `directory_customer_id` y, si hay política de acceso, `access_policy_id` en `0-bootstrap`, y tiene `roles/orgpolicy.policyAdmin` (y `roles/accesscontextmanager.policyAdmin` con `access_policy_id`) en la organización |
| D2 | P0 | Rol de cada integrante para su tarjeta de presentación, y si lleva foto | Lámina 15 del [plan de la presentación](plan-presentacion-final.md) (§5, punto 3) | Nombre, matrícula y rol de cada integrante entregados a quien arma la presentación |
| D3 | P0 | Resto de las decisiones abiertas del plan de la presentación | Duración de la presentación y del video, si el video va dentro o aparte, quién narra y quién edita, Google Slides o PowerPoint (§5, puntos 1, 2 y 4) | Las cuatro respuestas anotadas en el plan |
| D4 | P0 | Subir a GitHub la rama del rediseño (`feat/un-proyecto`, con lo integrado de R1 a R3) | El colaborador de GCP clona desde ahí; hoy la rama no tiene rama remota (`git branch -a`, 24 nov 2026) | `git push -u origin feat/un-proyecto` |
| D5 | P0 | Agregar al colaborador de GCP al repositorio privado | Sin acceso no puede clonar ni lanzar flujos | GitHub → Settings → Collaborators |
| D6 | P0 | Abrir el PR a `main` e integrarlo | `apply.yml` y `destroy.yml` solo corren desde `main`. Integrar a `main` dispara `apply.yml`; con `GCP_ENABLED` distinto de `"true"` no aplica nada en GCP | PR revisado e integrado |
| D7 | P1 | Decidir el plan de GitHub | En un repositorio privado de cuenta gratuita no hay protección de rama ni revisores en entornos: `apply.yml` no se detiene antes de `common` y `prod` (pendiente 12) | Plan elegido y anotado en el pendiente 12 |
| D8 | P1 | "Deployment branches: `main`" en los cuatro entornos de GitHub (`common`, `dev`, `qa`, `prod`) | Las cuentas de raíz ya solo aceptan tokens de `main`, de un flujo de este repositorio y de su entorno (`attribute.deploy`, `stages/0-bootstrap/wif.tf:36`; punto 123). La regla de GitHub queda como segunda barrera (pendiente 121) | Regla configurada y verificada como dice el pendiente 121 |
| D9 | P1 | Aceptar o reducir el alcance de `tf-read` | Lee todos los estados, incluido el del hub con el secreto de la VPN, y la toma cualquier trabajo del repositorio, también uno sin entorno o fuera de `main` (pendientes 122 y 124) | Decisión anotada en el pendiente 122 |
| D10 | P1 | Usuarios de GitHub del equipo en `CODEOWNERS` | Hoy tiene los marcadores `@PENDIENTE-red`, `@PENDIENTE-seguridad` y `@PENDIENTE-plataforma` (`../.github/CODEOWNERS`) | Marcadores reemplazados por usuarios reales |
| D11 | P1 | Protección de `main` con las comprobaciones obligatorias de `pr.yml` (incluidas `plan-gate` y `go (vet y pruebas sin GCP)`) | Sin ella, un PR que viola una política o rompe las pruebas de Go no queda bloqueado de verdad (criterio "el pipeline bloquea un PR") | Configuración de [`pipeline.md`](pipeline.md) hecha, si el plan de GitHub lo permite |
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
| G2 | P0 | Borrar la red `default` antes de `0-bootstrap` (ADR 0029 §6; paso del runbook 01). Después, etapa 0 a mano (`0-bootstrap`, runbook 01) y estado movido al bucket. Con organización (D1), la misma persona aplica las políticas de organización y el perímetro | Puntos 90 a 96, 125, 126 y 137 |
| G3 | P0 | Configurar GitHub: <br>• variables del repositorio; <br>• `GCP_AUDIT_SERVICE_ACCOUNT` = salida `read_service_account` de `0-bootstrap` (`tf-read`, punto 50); <br>• `GCP_TFVARS_JSON` de la rebanada, con valores reales en las variables que en los ejemplos llevan marcador: `scripts/root-tfvars.py` sale con 2 si queda alguno (lista en [`pipeline.md`](pipeline.md)); `operations_alert_email` de `1-base` es opcional (punto 138); <br>• los cuatro entornos con sus ramas de despliegue (D8) | — |
| G4 | P0 | Primer `apply.yml` de la rebanada: `1-base`, hub, spoke de dev y `3-workloads/envs/dev` con Cloud Run y Cloud SQL. Detenerlo después de dev como dice la [guía](guia-colaborador-gcp.md) (§E.1; ver M22). Lo que falle se corrige en una rama `fix/<tema>` con PR. Con `enable_backup = true`, el plan de respaldo de Cloud SQL puede fallar por los roles de la bóveda (punto 150, M21) | Primer `apply.yml` en verde; puntos 55, 123, 124, 131 a 133, 136, 146 y 147 |
| G5 | P0 | Prueba de humo de dev y `drift.yml` en verde sobre la rebanada | Puntos 50, 117 y, para dev, 11 y 80 |

### R5: despliegue mínimo, ensayo y grabación (28 a 29 nov)

| # | Prioridad | Tarea | Cierra |
|---|---|---|---|
| G6 | P0 | Desplegar el resto en modo mínimo y medir el tiempo (objetivo: menos de 90 min). Es el escenario B de la [estimación de costos](estimacion-de-costos.md): qa y prod sin GKE, MIG, Filestore, Memorystore ni balanceador interno, y 20.38 a 21.87 USD/día | Criterio "despliegue limpio" |
| G7 | P1 | `drift.yml` en verde después del despliegue mínimo | Criterio "segundo `plan` sin cambios" (pendientes 11 y 80) |
| G8 | P0 | Ensayo de la grabación y grabación de las escenas 0 a 7 del plan de la presentación (§2), sobre una ejecución ya probada | Video en bruto (F5) |
| G9 | P1 | PR de prueba que viole una política y quede bloqueado (escena 2) | Criterio "el pipeline bloquea un PR" (pendientes 12 y 51) |
| G10 | P1 | `destroy.yml` de dev en verde, con la búsqueda de huérfanos (escena 7). Después, `GCP_DISABLED_ENVS=dev` para que el siguiente push a `main` no lo vuelva a crear | Criterio "`destroy` de dev sin huérfanos" (pendientes 11, 85, 86, 87, 89, 141 y 143; el 140, cuando se destruya un entorno con GKE) |

### Después del ensayo: criterios que piden el diseño completo

| # | Prioridad | Tarea | Cierra |
|---|---|---|---|
| G11 | P1 | VM DNS de `onprem-sim` con `onprem_dns_vm = true` en `0-bootstrap` y en el hub (ya es código, `stages/2-networks/onprem_dns.tf`; 7.51 USD/mes\*, [estimación](estimacion-de-costos.md) §4.7), cómputo de prod y Connectivity Test desde prod. Al terminar, `onprem_dns_vm = false` | Criterio "una VM de prod alcanza on-premises" (pendientes 6, 7, 36, 37 y 128 a 130) |
| G12 | P1 | Activar SCC y evaluar el CIS ([`cumplimiento-cis.md`](cumplimiento-cis.md) §6) | Criterio "sin hallazgos críticos ni altos" (pendientes 2, 23 y 56) |
| G13 | P1 | Escribir el procedimiento de acceso de emergencia de la persona dueña del proyecto antes del simulacro de DR | Pendientes, §5, "El acceso de emergencia es la persona dueña del proyecto"; requisito de G14 |
| G14 | P1 | DR encendido y simulacro del runbook 04, midiendo RTO (4 h) y RPO (15 min). Antes, los roles de la bóveda de Backup and DR (M21) | Criterio "simulacro de DR dentro del RTO" (y punto 150) |
| G15 | P1 | Recursos no administrados de `drift.yml` contra el proyecto real | Criterio "cero recursos a mano" (pendientes 49, 118, 141 y 142) |
| G16 | P1 | Apagado fuera de horario: ver una noche y una mañana en dev o qa | Pendientes 70 a 73, 75 a 81 (el 74 es obsoleto), 127 y 134 |
| G17 | P1 | Marcar cada punto de `pendientes-apply.md` comprobado y cada marcador `VERIFICAR-EN-APPLY` resuelto | Puntos, al 24 nov 2026: 117 abiertos de 141 (15 obsoletos y 9 resueltos en el código), con los comandos del inicio de `pendientes-apply.md`: `grep -cE '^\*\*[0-9]+\. ' docs/pendientes-apply.md` y los mismos filtrados por `Obsoleto por el ADR 0029` y `Resuelto en el código`. Marcadores: 131 líneas en los `.tf` (`grep -rn "VERIFICAR-EN-APPLY" modules stages --include=*.tf \| wc -l`, desde `gcp-datacenter/`) y 113 filas en la §4 de `pendientes-apply.md` (`verificar_marcadores.py`: "malas: 0; marcadores sin fila: 0"); los de `envs/*` cuentan una vez por los tres entornos |
| G18 | P2 | Regenerar al menos un plan de ejemplo de Conftest por regla desde un plan real | Pendientes, §5, "Planes de ejemplo de Conftest"; puntos 146 y 147 |
| G19 | P2 | Terratest y prueba de extremo a extremo contra GCP, de preferencia en un proyecto de pruebas aparte | Pendientes, §5, "Terratest y prueba de extremo a extremo sin ejecutar" (puntos 119, 120, 145, 148 y 149); `terratest.yml` en verde |
| G20 | P0 | Apagar todo al terminar: `destroy.yml` de dev y qa; después, la persona dueña borra el proyecto o desmonta a mano el hub, `1-base` y la etapa 0, y desvincula la facturación | Costo en cero |

De los nueve criterios de aceptación del README, solo "cada módulo tiene README, ejemplo y prueba"
está demostrado completo sin GCP. Los otros ocho se cierran con G6, G7, G9, G10, G11, G12, G14 y
G15.

## 4. Mejoras de diseño no construidas

Cada una está documentada como hueco conocido, con lo que haría falta. Ninguna bloquea la entrega.

| # | Tema | Hueco | Qué haría falta | Dónde está escrito |
|---|---|---|---|---|
| M1 | Identidad del pipeline | **Hecho en parte (R2, 24 nov 2026):** las cuentas de escritura solo aceptan tokens de `main`, de un flujo de `.github/workflows/` de este repositorio y de su entorno de GitHub (`attribute.deploy`, `stages/0-bootstrap/wif.tf:36`; puntos 123 y 124). Queda que `tf-read` la toma cualquier trabajo del repositorio y lee todos los estados | `tf-read` limitado a los prefijos que necesita cada plan | Pendientes, §5, "WIF"; puntos 121, 122 y 124; `pipeline.md` |
| M2 | Separación de entornos (CIS 1.7) | **Hecho (R2, 24 nov 2026):** `1-base` crea las cuentas de ejecución de cada entorno y `tf-wl-<env>` recibe `serviceAccountUser` solo sobre las de su entorno (`stages/1-base/runtime_accounts.tf:264-270`); `tf-wl-<env>` ya no tiene `serviceAccountUser` de proyecto ni `TfServiceAccountManager`. Lo que sigue sin condición está en M23 | — | `cumplimiento-cis.md`, 1.7; puntos 131 a 135 |
| M3 | Binary Authorization | **Hecho en parte (R2, 24 nov 2026):** `binary_authorization_env_attestors` de `1-base` hace que cada clúster exija el atestador de su entorno y saca los repositorios de la lista de permitidos (`stages/1-base/variables.tf:191-208`; punto 139). Por defecto sigue la lista global: una imagen del repositorio de dev pasa en prod (desviación del ADR 0029 §4) | Crear los atestadores (la etapa no los crea), un paso del pipeline que firme las imágenes promovidas y llenar la variable | Pendientes, §5; puntos 42 y 139 |
| M4 | CIS 1.6 | Cuentas `<prefix>-tf-*` con roles de administrador | Roles personalizados más estrechos por etapa (ya hay cuatro en `0-bootstrap`) | ADR 0027 |
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
| M20 | Conftest | La regla `resource_locations` tiene la lista de ubicaciones fija: `us-central1` y `us-east4` con sus zonas, `us` y `global` (`policies/resource_locations.rego:31`, `:33`). Cambiar `primary_region` o `dr_region` (por ejemplo, a `northamerica-south1`, ADR 0002) sin cambiar la lista rechaza el plan, y `additional_allowed_locations` de `0-bootstrap` no la cambia. Su comentario todavía dice que la política de organización la da `1-base` (`:4`); hoy la aplica `0-bootstrap` | Sacar la lista de los `terraform.tfvars` (por ejemplo, un archivo de datos que Conftest lea con `--data`) o una prueba que la compare con `primary_region` y `dr_region` de los ejemplos; corregir el comentario | `policies/resource_locations.rego:12-13`; puntos 146 y 147 |
| M21 | Backup and DR | Ninguna raíz da a la cuenta de servicio de la bóveda los roles que Backup and DR pide sobre los recursos protegidos: la cuenta se conoce solo después de crear la bóveda en `3-workloads`, y `tf-wl-<env>` no asigna roles de proyecto (`modules/backup-dr/main.tf:47-51`). El respaldo de Cloud SQL puede fallar en el primer apply con `enable_backup = true` | Propuesta, no construida: un interruptor en `1-base` que, después del primer apply del entorno, lea la cuenta de la bóveda y le dé los roles (como `gke_workload_identity_bindings`), o que la persona los dé a mano y quede anotado. Qué roles: por verificar en la documentación de Backup and DR | Punto 150 |
| M22 | Pipeline | `apply.yml` no tiene una entrada para detenerse después de dev, y `GCP_DISABLED_ENVS` no admite prod (`../.github/workflows/apply.yml:10-14`). En la rebanada vertical (G4) qa se apaga con `GCP_DISABLED_ENVS=qa` y prod se detiene porque su plan falla en `root-tfvars.py` sin sus valores en `GCP_TFVARS_JSON`: la ejecución termina en rojo a propósito, y `drift.yml` falla cada día en las raíces de prod ([guía](guia-colaborador-gcp.md), §E.1) | Una entrada de `workflow_dispatch` que diga hasta qué entorno llegar, o aceptar prod en `GCP_DISABLED_ENVS` con una confirmación aparte | [Guía](guia-colaborador-gcp.md), §E.1; punto 143 |
| M23 | Separación de entornos | Roles sin condición en todo el proyecto: <br>• `tf-wl-<env>`: Backup and DR, Certificate Manager, Cloud SQL, Compute (instancias, balanceadores, seguridad y `networkUser`), GKE, Filestore, Backup for GKE, Monitoring, Memorystore y Cloud Run, más Cloud Scheduler en los entornos con apagado (`stages/0-bootstrap/service_accounts.tf:197-303`); <br>• `tf-net-<env>`: `compute.networkAdmin`, `compute.securityAdmin`, `dns.admin`, `TfNetworkTagManager` y `servicenetworking.networksAdmin` (`:231-252`); <br>• el hub, con `onprem_dns_vm = true`, también `compute.instanceAdmin.v1` (`:236-246`). <br>La cuenta de dev puede cambiar o borrar cargas, red, firewall, DNS e IAM de etiquetas de prod. Lo frena la revisión del plan (ADR 0025), no un control técnico | Condiciones por etiquetas de recurso o una política de denegación por entorno, donde el servicio las admita (HYPOTHESIS: no se comprobó qué servicios de esta lista las admiten); o volver a un proyecto por entorno (rama `archivo/multiproyecto`) | ADR 0029 §3 y §9; pendientes, §5, "Lo que ya no separa a los entornos" |
| M24 | VPN con on-premises real | Con `simulate_onprem = false`, el plan del hub falla en el pipeline: corre con `tf-read`, que tiene negado el secreto de la VPN (`stages/2-networks/vpn.tf:92-98`). El modo real no se puede aplicar desde el pipeline; con `simulate_onprem = true` (por defecto) no se lee ningún secreto | Una de tres salidas propuestas, no construidas: <br>• plan del hub con `tf-net` en el entorno `common`; <br>• un atributo de solo escritura para el secreto (Terraform >= 1.11; el repositorio admite 1.9; HYPOTHESIS: no se comprobó que el proveedor lo tenga para el túnel); <br>• que el valor no entre al plan: leerlo solo en el apply con `tf-net`, con la misma huella entre el plan revisado y el aplicado. <br>Las tres cambian el pipeline o la versión mínima | Punto 151; pendientes, §5 |

## 5. Cerrado en el código por los arreglos de R2 (24 nov 2026)

Lo construyó R2 y solo falta comprobarlo en GCP (los puntos de `pendientes-apply.md` que se
citan). Nada de esto se ha aplicado.

| Tema | Qué quedó en el código | Dónde | Se comprueba en |
|---|---|---|---|
| Cuentas de ejecución y CIS 1.7 | `1-base` crea las cuentas `<prefix>-<env>-<app>-<uso>`; `tf-wl-<env>` solo tiene `serviceAccountUser` sobre las de su entorno (M2) | `stages/1-base/runtime_accounts.tf` | Puntos 131 a 135 |
| WIF de escritura solo desde `main` | `attribute.deploy`: el entorno solo con `refs/heads/main` y un flujo de este repositorio; si no, `none` y solo `tf-read` (M1) | `stages/0-bootstrap/wif.tf:36`, `:99` | Puntos 123 y 124 |
| Políticas de organización y VPC-SC | Pasan a `0-bootstrap` y las aplica la persona; ninguna cuenta del pipeline tiene roles de organización (D1) | `stages/0-bootstrap/org.tf` | Puntos 125 y 126 |
| Denegación ampliada | La regla sin etiqueta también niega tokens y firmas a las cuentas del pipeline | `stages/0-bootstrap/deny_policy.tf:96` | Punto 127 |
| Binary Authorization con atestadores | Opción `binary_authorization_env_attestors` (M3) | `stages/1-base/artifacts.tf:163` | Punto 139 |
| Llaves de KMS sin uso | `1-base` crea solo las llaves que alguien usa; las de DR y `storage` de la multirregión, solo en `dr_environments` (por defecto prod) | `stages/1-base/kms.tf:24-37` | Costo en la [estimación](estimacion-de-costos.md) |
| Canal de operaciones | `operations_alert_email` en `1-base`; `3-workloads` usa solo ese canal para las alertas del entorno | `stages/1-base/variables.tf:261` | Punto 138 |
| VM DNS de onprem-sim | Opcional con `onprem_dns_vm = true` (G11) | `stages/2-networks/onprem_dns.tf` | Puntos 128 a 130 |
| Entornos apagados | `GCP_DISABLED_ENVS` (solo dev y qa) en `apply.yml` y `drift.yml`; el comentario de `destroy.yml` pide usarla después de destruir | `../.github/workflows/apply.yml:10-21` | Punto 143 |
| `apply.yml` sin cambios de documentación | No se dispara con `gcp-datacenter/docs/**` ni con los `.md` de `gcp-datacenter/` | `../.github/workflows/apply.yml:64-68` | Punto 144 |
| Pruebas de Go en los PR | Trabajo `go (vet y pruebas sin GCP)` en `pr.yml` (falta hacerlo obligatorio, D11) | `../.github/workflows/pr.yml:189` | — |
| Huérfanos de GKE | La búsqueda de huérfanos de `destroy.yml` reconoce los restos que GKE nombra con el clúster | `scripts/destroy-orphans.py` | Puntos 140 a 142 |
| Marcadores en `GCP_TFVARS_JSON` | `root-tfvars.py` sale con 2 si un valor resuelto conserva un marcador de los ejemplos (G3) | `scripts/root-tfvars.py` | Primer `apply.yml` (G4) |

## 6. Documentación que falta corregir

| # | Prioridad | Tarea | Cómo se comprueba |
|---|---|---|---|
| T1 | P2 | Los `terraform.tfvars.example` usan marcadores distintos de `project_id` (`example-project-id`, `example-landing-zone` y `example-lz-000000`): usar uno solo | `grep -rhE '^project_id' stages --include=terraform.tfvars.example \| sort -u`, desde `gcp-datacenter/` |
| T2 | P1 | Corregir el comentario de `policies/resource_locations.rego:4` (M20) | Lectura del archivo |
| T3 | P0 | Conteos de la entrega (módulos, reglas de Conftest, pruebas, puntos y marcadores) en el README, `pendientes-apply.md` y la presentación, cada uno con el comando que lo produjo y la fecha (F2, F4) | Por ejemplo, al 24 nov 2026: módulos, 24 con `ls -d modules/*/ \| wc -l`; reglas de Conftest, 12 con `ls policies/*.rego \| grep -v _test \| grep -v helpers \| grep -vc lib.rego` |
