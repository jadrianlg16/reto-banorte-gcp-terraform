# ADR 0028: Apagado fuera de horario de dev y qa

## Estado

Aceptado, 2026-11-23. Enmendado el 2026-11-24: con el proyecto único
([ADR 0029](0029-un-solo-proyecto.md)) el rol `<prefix>OffHoursScheduler` lo crea
`0-bootstrap` una sola vez y `1-base` lo publica como `off_hours_role_id`; la cuenta
`<prefix>-<env>-<app>-sched` y su permiso los crea `stages/3-workloads/envs/<env>` cuando
`off_hours_shutdown.enabled`; la API de Cloud Scheduler la habilita `0-bootstrap`, y
`cloudscheduler.admin` para `tf-wl-dev` y `tf-wl-qa` (nunca prod) también lo da `0-bootstrap`.
Ya no existe `enable_off_hours_shutdown`.

Tipo: Aclaración. Construye la mitigación de costo opcional que el contrato (§8) dejaba sin
construir; no cambia la especificación.

## Contexto

dev y qa están encendidos las 24 horas, pero solo se usan en horario de trabajo. Lo que se cobra
por hora y se puede detener es Cloud SQL (vCPU y memoria), las VM del MIG y los nodos de GKE. El
apagado tiene que cumplir cuatro condiciones:

- **Nunca en prod.** Debe ser imposible activarlo ahí, no solo "apagado por defecto".
- **Sin deriva falsa.** `drift.yml` corre `terraform plan -detailed-exitcode` a las 12:17 UTC
  (06:17 en Monterrey, con los recursos apagados) y abre una incidencia con el código 2. Los plan
  de `pr.yml` y `apply.yml` también pueden caer de noche. Un recurso detenido por un trabajo
  programado no puede aparecer como cambio. Los cambios en las salidas raíz también dan código 2.
- **Mínimo privilegio.** La identidad que apaga y enciende solo debe poder hacer esas llamadas.
- **Que un apply o la prueba de humo de noche se entiendan.** Un merge fuera de horario no debe
  fallar con un error críptico.

## Decisión

Variable `off_hours_shutdown` en las raíces de `stages/3-workloads/envs/*`:
`{ enabled, time_zone, start_schedule, stop_schedule }`.

- Por defecto vale `{ enabled = false }`. Se rechaza en prod y con `enable_dr`.
- Los crons tienen la forma `M H * * D` y los dos usan los mismos días.
- La ventana encendida dura al menos 60 minutos y deja lugar para la ventana de respaldo de 6
  horas.
- Los `terraform.tfvars.example` de dev y qa la encienden: de 07:00 a 20:00 de lunes a viernes,
  zona `America/Monterrey`.

Quién crea cada pieza en el proyecto único:

- `0-bootstrap` habilita `cloudscheduler.googleapis.com` (con las demás APIs), crea el rol
  personalizado `<prefix>OffHoursScheduler`, con solo los permisos de las llamadas
  (`cloudsql.instances.get`, `cloudsql.instances.update` y `container.clusters.update`), y da a
  `tf-wl-dev` y `tf-wl-qa` `roles/cloudscheduler.admin` en el proyecto. `tf-wl-<env>` ya tiene
  `iam.serviceAccountUser` en el proyecto (para sus cuentas de ejecución) y puede dar el rol del
  apagado por su concesión delegada.
- `1-base` publica el ID del rol en la salida `off_hours_role_id`.
- `stages/3-workloads/envs/<env>`, con `off_hours_shutdown.enabled`, crea la cuenta
  `<prefix>-<env>-<app>-sched`, que firma los tokens de los trabajos, y le da el rol en el
  proyecto, **sin condición**: el rol junta permisos de Cloud SQL y de GKE, y una condición por
  nombre sobre un tipo que no la admite niega todo (ADR 0029 §3).

El rol vive en `0-bootstrap` porque crear roles personalizados desde una raíz de entorno le
exigiría `iam.roleAdmin`, y con ese rol una cuenta podría darse a sí misma cualquier permiso.

### Mecanismo por recurso

| Recurso | Mecanismo | Por qué no hay deriva | Fuente oficial |
|---|---|---|---|
| Cloud SQL | Dos trabajos HTTP de Cloud Scheduler (`sql-<llave>-stop` y `-start`) llaman a `instances.patch` con `settings.activationPolicy` en `NEVER` o `ALWAYS`. Usan el token OAuth de la cuenta `-sched`. Módulo nuevo `off-hours-shutdown`. | El módulo `cloud-sql` ignora `settings[0].activation_policy`. Ver "Qué deja de detectarse" más abajo. | [instances.patch](https://docs.cloud.google.com/sql/docs/postgres/admin-api/rest/v1/instances/patch); [permisos de IAM](https://docs.cloud.google.com/sql/docs/postgres/iam-permissions) (`patch` pide `cloudsql.instances.update`); [iniciar y detener](https://docs.cloud.google.com/sql/docs/postgres/start-stop-restart-instance) (una réplica de lectura no se puede detener; detenida se siguen cobrando almacenamiento e IP); [DatabaseInstance](https://docs.cloud.google.com/sql/docs/postgres/admin-api/rest/v1/instances) (`RUNNABLE` también significa "stopped by owner") |
| MIG | Programa de escalado nativo del autoescalador (`business_hours` del módulo `compute-mig`). Exige `mig_min_replicas` VM durante el horario. Fuera del horario, con `min_replicas = 0` y sin señal de CPU, el grupo baja a 0. | Es declarativo: el programa está en el código y no cambia nada que Terraform administre. Cambiar de señal (CPU o programa) reemplaza el autoescalador (`replace_triggered_by`), porque en el proveedor `cpu_utilization` es Optional+Computed y quitar el bloque no lo borra. | [Programas de escalado](https://docs.cloud.google.com/compute/docs/autoscaler/scaling-schedules) (un programa puede ser la única señal; mínimo 5 minutos; zona horaria; al terminar, el grupo vuelve al mínimo); [escalar a cero](https://docs.cloud.google.com/compute/docs/autoscaler/understanding-autoscaler-decisions#scale-in-to-zero) (`minNumReplicas` 0, sin programas activos y sin señales de CPU, de balanceador ni por instancia) |
| Pools de GKE | Cuatro trabajos por pool. Apagado: `setAutoscaling` con `enabled=false` y, 10 minutos después, `setSize` con `nodeCount=0`. Encendido: `setSize` al mínimo (al menos 1) y, 10 minutos después, `setAutoscaling` con los límites de la configuración. Se desactiva el autoescalado antes del cambio de tamaño para que no lo deshaga. | Con `scheduled_scaling`, el módulo `gke` crea los pools en un recurso aparte (`scheduled`, nombre `...-app-nps-<llave>`) que ignora `autoscaling` e `initial_node_count`. Prod sigue con el recurso `this`, sin `ignore_changes` nuevos. | [Autoescalador de clúster](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/cluster-autoscaler); [cambiar el tamaño de un clúster](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/resizing-a-cluster) (el tamaño es por zona; no mezclar con el autoescalador) |
| Cloud Run | Nada: ya escala a cero (`min_instances = 0` por defecto en el módulo; la raíz no lo cambia). | — | [Instancias mínimas](https://docs.cloud.google.com/run/docs/configuring/min-instances) |
| Memorystore y Filestore | No se apagan. Se cobra la capacidad aprovisionada mientras la instancia exista; la única forma de no pagar es no crearla (`enable_memorystore` o `enable_filestore` en `false`). HYPOTHESIS: que no exista una operación para detenerlas (no se encontró en la documentación). | — | [Precios de Memorystore](https://cloud.google.com/memorystore/docs/redis/pricing); [precios de Filestore](https://cloud.google.com/filestore/pricing) |
| Backup and DR | La ventana diaria de 6 horas se mueve al horario encendido: empieza en la primera hora en punto después del encendido, en la misma zona horaria. Sin apagado se mantienen los valores de siempre (01:00, `America/Mexico_City`). | Es declarativo. | [Respaldos con la instancia detenida](https://cloud.google.com/sql/docs/mysql/backup-recovery/view-audit-logs-for-automated-backups) (página de MySQL; para PostgreSQL y Backup and DR es HYPOTHESIS) |

Cloud Scheduler:

- [Autenticación de destinos HTTP](https://docs.cloud.google.com/scheduler/docs/http-target-auth): el token OAuth solo sirve para `*.googleapis.com`; quien crea el trabajo necesita actAs sobre la cuenta; el agente de servicio se configura solo.
- [Referencia de `jobs`](https://docs.cloud.google.com/scheduler/docs/reference/rest/v1/projects.locations.jobs).
- [Precios](https://cloud.google.com/scheduler/pricing): se cobra por trabajo al mes, con 3 trabajos gratis por cuenta de facturación.

### Sin deriva en `drift.yml` ni en los plan de `pr.yml`

- Lo que cambian los trabajos (`activation_policy` y `autoscaling` de los pools) está en
  `ignore_changes`. El tamaño del MIG y de los pools nunca lo fija Terraform: no hay `target_size`
  y `initial_node_count` se ignora.
- La salida raíz `off_hours_shutdown` solo lleva valores de la configuración (ventana e IDs de los
  trabajos). No da código 2 entre el día y la noche. `activation_policy` no es salida raíz.
- El bloque `check "cloud_sql_encendida"` avisa en cada plan si la instancia está detenida. Es
  una advertencia y no cambia el código de salida.
- Los trabajos se declaran con `paused = false`. Un trabajo pausado a mano sí aparece como deriva,
  porque el apagado dejaría de correr sin que nadie lo notara.

### Qué deja de detectarse con `ignore_changes` en módulos que prod comparte

- **`cloud-sql`:** el `ignore_changes` de `settings[0].activation_policy` aplica en todos los
  entornos, porque Terraform no permite un `ignore_changes` condicional. Por eso el plan ya no
  marcaría como deriva una instancia de prod detenida a mano.
  - **Compensación:** una `postcondition` exige `activation_policy = "ALWAYS"` siempre que
    `allow_scheduled_stop = false`, y ese valor es obligatorio en prod y con `enable_dr`. En ese
    caso el plan falla con un mensaje que dice cómo encenderla. Un plan que falla hace que
    `drift.yml` termine en error (código 1, trabajo en rojo) en vez de abrir una incidencia, y
    también bloquea `pr.yml` y `apply.yml`.
  - **Diferencia con antes:** antes, el plan proponía encenderla; ahora falla y alguien tiene
    que encenderla a mano.
  - **Mientras tanto:** `observability` no tiene una alerta propia de Cloud SQL detenida. Si la
    aplicación depende de la base, las alertas de 5xx y de SLO del balanceador lo harían notar
    en prod (HYPOTHESIS).
- **`gke`:** el `ignore_changes` de `autoscaling` solo está en el recurso `scheduled`, que prod
  no puede usar (validación). En dev y qa con apagado, un cambio manual de los límites no se ve
  en el plan. Lo corrige el siguiente encendido, porque el trabajo `start-autoscaling` vuelve a
  poner los límites de la configuración.

### Apply y prueba de humo fuera de horario

- **Apply:** un apply de noche no enciende nada. El plan no tiene cambios por el apagado y
  muestra el aviso de `cloud_sql_encendida`. Un apply que cree bases o usuarios IAM en la
  instancia detenida debería fallar hasta el encendido (HYPOTHESIS). Para aplicar antes, se lanza
  el trabajo `sql-primary-start` con `gcloud scheduler jobs run` (el ID está en la salida
  `off_hours_shutdown.job_ids`).
- **Prueba de humo:** la de dev (`TestDevSmoke`, trabajo "dev / prueba de humo" de `apply.yml`)
  detecta la instancia detenida (`settings.activationPolicy = NEVER`; `state` sigue en
  `RUNNABLE`). Falla con un mensaje que lo dice y explica cómo seguir. No la enciende: la cuenta
  de auditoría es de solo lectura y, si la encendiera, la instancia quedaría prendida hasta el
  siguiente apagado. Para seguir hay tres opciones:
  - volver a correr el trabajo después del encendido ("Re-run failed jobs");
  - lanzar antes el trabajo de encendido;
  - lanzar `apply.yml` a mano con `omitir_prueba_de_humo` ([`pipeline.md`](../pipeline.md) §1.2).

## Alternativas consideradas

- **Cloud Scheduler más una función (el tutorial de Google, [start-and-stop-sql](https://docs.cloud.google.com/scheduler/docs/start-and-stop-sql-server-instances-on-a-schedule)).**
  Rechazada: agrega código propio, su construcción y otra identidad. Cada acción aquí es una sola
  llamada a la API, y el destino HTTP de Cloud Scheduler la hace directo.
- **El MIG con trabajos de Cloud Scheduler** (autoescalador en `OFF` y `resize` a 0). Rechazada:
  el programa de escalado es nativo y declarativo, no necesita otra identidad ni permisos sobre
  el MIG y no causa deriva.
- **`ignore_changes` condicional.** Terraform no lo permite. En GKE se resolvió con dos recursos.
  En Cloud SQL, duplicar la instancia obligaría a mover el estado de una base de datos con datos
  al activar el apagado, así que se eligió `ignore_changes` más la `postcondition`.
- **Que la raíz de cargas cree el rol.** Rechazada por la escalada de privilegios descrita en
  Decisión. La cuenta sí la crea la raíz de cargas: es un principal del entorno (ADR 0029 §4).
- **Roles predefinidos para la cuenta `-sched`.** Rechazada: los roles predefinidos que incluyen
  esos permisos traen muchos más.
- **Apagar con `terraform apply` o `destroy` nocturnos.** Rechazada: un apply cada noche necesita
  aprobación y huella de plan (ADR 0025), destruir Cloud SQL borra los datos, y el código dejaría
  de describir el estado real.

## Consecuencias

- **Positivas:**
  - Con los valores de ejemplo (5 días × 13 h encendidas), dev y qa quedan apagados 103 de las
    168 horas de la semana (61 %). Los precios de [`estimacion-de-costos.md`](../estimacion-de-costos.md)
    §6.2 dan unos 124 USD/mes menos en el escenario A.
  - Prod no puede activarlo: validaciones en la raíz y en los módulos, con pruebas que fallan si
    se intenta.
- **Negativas:**
  - Durante el horario, el MIG de qa tiene `mig_min_replicas` VM fijas, sin autoescalado por CPU.
  - Cambiar `scheduled_scaling` reemplaza los pools de GKE: crea los nuevos y borra los viejos.
  - De noche, la prueba de humo de dev falla con un mensaje claro y un apply que toque bases o
    usuarios espera al encendido.
  - Memorystore, Filestore, la cuota del clúster de GKE, los balanceadores, Cloud Armor, NAT, la
    VPN y el almacenamiento de Cloud SQL se siguen cobrando.
  - No hay alerta si un trabajo de Cloud Scheduler falla (limitación en
    [`pendientes-apply.md`](../pendientes-apply.md) §5).
  - La cuenta `-sched` de dev tiene el rol en todo el proyecto: técnicamente podría detener la
    instancia o cambiar los pools de qa o de prod; sus trabajos solo apuntan a los de su entorno
    (riesgo aceptado, ADR 0029 §9). `cloudscheduler.admin` de `tf-wl-dev` y `tf-wl-qa` también
    alcanza los trabajos del otro entorno.
- **Fórmula de ahorro:**
  - Horas apagadas por semana: `H = 168 − días × (hora de apagado − hora de encendido)`.
  - Ahorro mensual: `730 × H / 168 × (vCPU y memoria de Cloud SQL por hora + VM y disco del MIG
    por hora × mig_min_replicas + nodo y disco de GKE por hora × zonas × min_node_count)`, menos
    los trabajos de Cloud Scheduler (2 por instancia y 4 por pool, con 3 gratis por cuenta de
    facturación).
- **Primer apply:** puntos 70 a 81 de [`pendientes-apply.md`](../pendientes-apply.md) (§3.8).
