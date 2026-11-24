# Diagrama 4: seguridad, operación y continuidad

Quién puede cambiar qué, cómo nos enteramos de un cambio o una falla, cómo se apagan dev y qa
de noche y cómo se recupera prod en `us-east4`. Es diseño: nada ha corrido contra GCP y los
objetivos de RPO y RTO no se han medido. El pipeline tiene su propio
[diagrama 5](05-pipeline.md).

![Seguridad y operación: quién cambia qué y cómo nos enteramos](img/04-seguridad-y-operacion.png)

El PNG sale de [`fuente/`](fuente/LEEME.md). El diagrama de texto usa `prefix = "bnt"`.

```mermaid
flowchart TB
  gha["GitHub Actions<br/>trabajo con environment<br/>para escribir: solo desde main"]

  subgraph ID["Identidad del pipeline (0-bootstrap, nueve cuentas)"]
    wif["Workload Identity Federation<br/>sin llaves JSON · attribute.deploy"]
    common["common: bnt-tf-base · bnt-tf-net"]
    envs["dev · qa · prod: bnt-tf-net-{env} · bnt-tf-wl-{env}"]
    read["bnt-tf-read: plan, drift, prueba de humo, huérfanos"]
    state[("Bucket de estado multirregión US<br/>un prefijo por raíz · CMEK · versionado")]
    deny{{"IAM Deny + etiqueta bnt-proteccion = etapa-0<br/>ninguna cuenta borra el bucket, cambia WIF ni pide tokens"}}
  end
  gha -- "OIDC" --> wif
  wif --> common
  wif --> envs
  wif --> read
  deny -. "protege" .-> state

  subgraph LOG["Registro, auditoría y cuentas (1-base, una vez por proyecto)"]
    audit["Configuración de auditoría<br/>ADMIN_READ en todo · DATA_READ y DATA_WRITE<br/>de KMS, Secret Manager, IAM, Cloud SQL y Storage"]
    sink["Sink de proyecto → bucket bnt-common-ops-audit-logs<br/>CMEK logs · retención 365 días"]
    alerts["Alertas de auditoría del CIS 2.5 a 2.12<br/>métricas de log → correo security_alert_email"]
    contacts["Contactos esenciales (CIS 1.17)"]
    scc["Security Command Center<br/>activación manual en el proyecto<br/>notificación opcional a Pub/Sub"]
    runsa["Cuentas de ejecución bnt-{env}-app-{uso}<br/>gke-nodes · workload · mig · run · sched"]
  end
  audit --> sink
  audit --> alerts
  envs -. "tf-wl-{env} solo adjunta las de su entorno" .-> runsa

  subgraph OFF["Apagado fuera de horario (solo dev y qa, ADR 0028)"]
    sched["Cloud Scheduler · cuenta bnt-{env}-app-sched (de 1-base)<br/>rol bntOffHoursScheduler (de 0-bootstrap)"]
    sqloff["Cloud SQL detenida 20:00–07:00 y fin de semana"]
    gkeoff["Pools de GKE a 0"]
    migoff["MIG a 0 con programa de escalado"]
  end
  sched --> sqloff
  sched --> gkeoff

  subgraph MON["Monitoreo por entorno (3-workloads)"]
    mon["Cloud Monitoring · alertas por correo<br/>disponibilidad · 5xx · saturación · retraso de réplica<br/>SLO 99.9 %"]
  end

  subgraph REC["Recuperar prod en us-east4 (enable_dr = true)"]
    replica[("Réplica de Cloud SQL en us-east4<br/>PITR en la primaria")]
    dual[("Bucket de doble región<br/>turbo replication")]
    backup[("Bóveda de Backup and DR en us-east4<br/>plan diario de Cloud SQL, 30 días<br/>Backup for GKE en us-east4")]
    vpndr["HA VPN de DR en us-east4"]
    failover["Conmutación (runbook 04)<br/>promover la réplica · dr_active = true<br/>vuelta con dr_teardown en dos applies"]
  end
  mon -- "alerta" --> failover
  replica --> failover
  dual --> failover
  backup --> failover
  vpndr --> failover
  state -- "disponible sin us-central1" --> failover
```

## Cómo se lee

- **Identidad.** Nueve cuentas del pipeline, todas de `0-bootstrap`. Un trabajo de GitHub
  Actions obtiene una cuenta que escribe solo si es de `main`, de un flujo de
  `.github/workflows/` del repositorio y con el entorno de GitHub de esa cuenta
  (`attribute.deploy`); cualquier otro obtiene `tf-read`. Las cuentas de ejecución de las cargas
  las crea `1-base`, y `tf-wl-<env>` solo puede adjuntar las de su entorno. Las personas solo
  leen ([diagrama 1](01-organizacion-gobierno-acceso.md)).
- **Protección del estado.** La política de denegación y la etiqueta (ADR 0029 §5). Si las
  etiquetas no funcionan en el proyecto (HYPOTHESIS sin organización),
  `enable_protection_tags = false` deja solo la regla sin condición, y la protección queda en
  que ninguna cuenta tiene `storage.admin` ni `projectIamAdmin` sin condición
  (`stages/0-bootstrap/README.md`).
- **Auditoría (ADR 0029 §7).** La configuración de auditoría es única por proyecto, así que los
  registros de acceso a datos valen para los tres entornos. Un sink de proyecto los copia al
  bucket de logs con CMEK; una exclusión evita que el sink exporte los accesos al propio bucket.
  Las alertas de auditoría existen una sola vez, en `1-base`.
- **SCC.** Se activa a mano en el proyecto ([runbook 01](../runbooks/01-arranque-etapa-0.md)).
  La notificación a Pub/Sub de `1-base` está apagada por defecto
  (`enable_scc_notification = false`). Que SCC funcione sin organización es HYPOTHESIS.
- **Apagado fuera de horario.** Solo dev y qa (prod lo rechaza). Cloud SQL y los pools de GKE con
  trabajos de Cloud Scheduler; el MIG con un programa de escalado; Cloud Run ya escala a cero.
  La cuenta `sched` la crea `1-base` en los entornos de `off_hours_environments` y le da el rol
  del apagado, que crea `0-bootstrap`. El rol no tiene condición: la cuenta de dev podría detener
  recursos de otro entorno; los trabajos solo apuntan a los del suyo
  (`stages/1-base/runtime_accounts.tf`).
- **Monitoreo.** Uno por entorno, limitado a los recursos del entorno por nombre y etiqueta.
  También avisa al canal de operaciones de `1-base` (`operations_alert_email`), si existe; el
  canal de seguridad queda solo para las alertas de auditoría.
- **Continuidad de prod.** Datos replicados (Cloud SQL y el bucket), respaldos en la región de
  DR, la VPN de DR y el estado multirregional. La conmutación es manual, con el
  [runbook 04](../runbooks/04-conmutacion-a-dr.md). Memorystore y Filestore no tienen DR.

## Lo que cambió del primer texto del ADR 0029 al código

- El rol `<prefix>OffHoursScheduler` lo crea `0-bootstrap`, no `1-base`; `1-base` lo publica
  (`off_hours_role_id`) y se lo da a la cuenta `sched`.
- Las cuentas de ejecución, `sched` incluida, las crea `1-base`, no cada raíz de entorno.
- Las cuentas que escriben se toman por `attribute.deploy`, no por `attribute.environment`. La
  tabla completa está en el [diagrama 1](01-organizacion-gobierno-acceso.md).

El diseño anterior, con sink de organización y Data Access solo en prod, está en la rama
`archivo/multiproyecto`.
