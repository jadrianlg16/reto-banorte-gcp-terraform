# Estimación de costos mensuales

Estimación del costo de operar la landing zone en Google Cloud con el diseño de un solo proyecto
([ADR 0029](adr/0029-un-solo-proyecto.md)): etapas `0-bootstrap`, `1-base`, `2-networks` y
`3-workloads`. El dimensionamiento sale de este repositorio (valores de `terraform.tfvars.example`
y valores por defecto de las raíces y los módulos). Los precios son los de lista de las páginas
oficiales, leídos el **2026-11-23**. El recálculo para un solo proyecto es del **2026-11-24**.
La estimación del diseño anterior de 10 proyectos se conserva en la rama `archivo/multiproyecto`.

**Estado:** nada se ha aplicado. Esto es una estimación de diseño, no una factura. Cuando el
pipeline tenga acceso a GCP, Infracost calcula el costo del plan real en cada PR (§6.3).

## Resumen

| Escenario | USD/mes (bajo – alto) | USD/día (bajo – alto) |
|---|---:|---:|
| A. Diseño completo (valores de ejemplo de los tres entornos, DR de prod incluida) | 2,450.60 – 3,571.58 | 80.57 – 117.42 |
| B. Despliegue mínimo de prueba (todas las etapas, cómputo apagado salvo Cloud Run) | 622.03 – 667.28 | 20.45 – 21.94 |
| B, variante solo dev (`0-bootstrap`, `1-base`, hub y dev) | 241.20 – 263.81 | 7.93 – 8.67 |

Una prueba de 3 días del escenario B cuesta **61.35 – 65.82 USD**. La variante solo dev cuesta
**23.79 – 26.01 USD** (§5). El presupuesto de ejemplo es de 300
(`stages/0-bootstrap/terraform.tfvars.example:28`). Con ese monto alcanza para unos 13.7 a 14.7
días del escenario B o 34.6 a 37.8 días de la variante solo dev. Del escenario A alcanza para
unos 2.6 a 3.7 días (300 / 117.42 y 300 / 80.57).

### Cambios frente a la estimación de 10 proyectos

| Renglón | Antes (bajo / alto) | Ahora (bajo / alto) | Causa y cálculo |
|---|---:|---:|---|
| Cloud Logging sobre el nivel gratuito | prod: 0.00 / 25.00 | común: 0.00 / 37.50 | **Causa:** los 50 GiB gratuitos son por proyecto, y ahora hay uno solo. Antes, dev, qa y los proyectos comunes tenían cada uno su propio nivel gratuito. **Cálculo:** alto = (125 − 50) GiB × 0.50 = 37.50, en vez de (100 − 50) × 0.50 = 25.00 en el proyecto de prod. Bajo = 35 GiB, dentro del nivel gratuito. Volúmenes en la §1. |
| Bucket de logs de auditoría | 0.02 / 0.40 | 0.04 / 0.60 | **Causa:** hay registros de acceso a datos en los tres entornos (antes solo en prod y en la semilla). **Cálculo:** 2 GiB y 30 GiB × 0.000027397 × 730. |
| Flow logs del hub y onprem-sim | 0.05 / 0.25 | 0.10 / 0.50 | **Causa:** muestreo al 100 % (ADR 0027). La estimación anterior lo dejaba anotado sin recalcular. **Cálculo:** 0.4 GiB y 2 GiB × 0.25. |
| Flow logs de prod (escenario A) | 0.10 / 5.00 | 0.20 / 10.00 | **Causa:** igual, muestreo al 100 %. **Cálculo:** 0.8 GiB y 40 GiB × 0.25. |
| Flow logs de prod (escenario B) | 0.10 / 0.50 | 0.20 / 1.00 | **Causa:** igual. **Cálculo:** 0.8 GiB y 4 GiB × 0.25. |
| Política de firewall por VM (qa y prod) | jerárquica: 1.00 / 3.00 y 5.00 / 15.00 | de red: mismos valores\* | **Causa:** la política jerárquica se asocia a una organización o carpeta, y el diseño de un proyecto no la usa. Cada VPC lleva una política de firewall de red (`modules/firewall/main.tf:50`, `:56`). **Precio:** por verificar (§3). |
| **Escenario A** | 2,450.43 / 3,553.63 | 2,450.60 / 3,571.58 | **Bajo:** +0.17 = +0.02 + 0.05 + 0.10. **Alto:** +17.95 = +37.50 − 25.00 + 0.20 + 0.25 + 5.00. |
| **Escenario B** | 621.86 / 666.33 | 622.03 / 667.28 | **Bajo:** +0.17. **Alto:** +0.95 = +0.20 + 0.25 + 0.50. En B no hay cargo de Logging: alto = 35 GiB. |
| **Solo dev** | 241.13 / 263.36 | 241.20 / 263.81 | **Bajo:** +0.07 = +0.02 + 0.05. **Alto:** +0.45 = +0.20 + 0.25. |

Lo demás no cambia con el diseño de un solo proyecto. Las 72 llaves se mantienen: las 69 de los
entornos ahora las crea `1-base`. Las 19 zonas de DNS, los 8 túneles, los balanceadores, el
cómputo y los datos son los mismos. Los proyectos, las carpetas y la VPC compartida no tenían
costo propio.

## 1. Supuestos

- **Precios de lista on-demand en USD.** Se leyeron el 2026-11-23 en las páginas oficiales de la
  §7. No se aplican descuentos por compromiso (CUD) ni contratos.
- **Descuentos automáticos.** No se aplica ningún descuento por uso continuo (SUD). Las VM de
  este diseño son E2, y E2 no está entre las series elegibles para SUD
  ([sustained-use-discounts](https://docs.cloud.google.com/compute/docs/sustained-use-discounts)).
  La página de precios de Cloud SQL no ofrece SUD.
- **Niveles gratuitos que sí se aplican.** Son los que la página de cada producto describe como
  automáticos, y cada renglón dice cuál usa:
  - crédito de Binary Authorization para GKE;
  - nivel gratuito de Cloud Run;
  - 6 versiones de Secret Manager;
  - 20 Connectivity Tests por mes;
  - 50 GiB de Logging por proyecto;
  - 1 millón de ejecuciones de uptime check por proyecto;
  - 100 certificados de Certificate Manager por proyecto.

  Con un solo proyecto, los tres niveles "por proyecto" cuentan **una sola vez** para los tres
  entornos.
- **El crédito gratuito de GKE (74.40 USD/mes) no aplica.** Solo cubre clústeres zonales o
  Autopilot, y el de este diseño es regional.
- **Niveles gratuitos que no se aplican (estimación conservadora):** los 5 GB-mes Always Free de
  Cloud Storage, los 0.5 GiB gratuitos de Artifact Registry y cualquier crédito de prueba.
- **730 horas por mes.** Día = mes × 24 / 730, redondeado a centavos. Una semana o una prueba de
  N días = ese día redondeado × 7 o × N.
- **Todo encendido las 730 horas.** Las tablas de §4 y §5 no restan el apagado fuera de horario
  que los `terraform.tfvars.example` de dev y qa encienden (`off_hours_shutdown`, ADR 0028;
  `stages/3-workloads/envs/dev/terraform.tfvars.example:52`). Su ahorro se calcula aparte en la
  §6.2.
- **Regiones:** `us-central1` (primaria) y `us-east4` (DR); multirregión `us`/`US`
  (`stages/1-base/terraform.tfvars.example:6-7`, `stages/1-base/kms.tf:9-10`).
- **Excluidos:** salida a Internet, impuestos y tráfico entre zonas o regiones. Eso incluye la
  replicación de Cloud SQL a `us-east4`, el peering entre zonas y el tráfico IPsec entre los
  gateways de VPN. En una prueba con poco tráfico ese costo es pequeño, pero no está en las
  tablas.
- **Región de las tablas de precios.** Las tablas estáticas de las páginas oficiales muestran
  Iowa (`us-central1`). El selector de región carga los demás valores dinámicamente y no se pudo
  leer `us-east4`. Todo precio de `us-east4` que no venga de una tabla sin región es
  **SUPUESTO** (§3).
- **Alertas de Monitoring:** sin costo. La página de precios dice que el cobro de políticas de
  alerta empieza "no antes del 1 de septiembre de 2027".
- **Bajo / alto.** Lo provisionado (instancias, discos, túneles, reglas) es igual en los dos. Lo
  que depende del uso tiene dos valores:
  - *bajo* = mínimos del autoescalado y tráfico de prueba;
  - *alto* = máximos del autoescalado y tráfico moderado.

  Las cantidades de cada renglón están en la columna de cálculo.
- **Volumen de logs del proyecto (SUPUESTO).** Desde el ADR 0029, todo cae en un solo proyecto:
  - logs de cargas de GKE;
  - registros del balanceador con Cloud Armor en `VERBOSE`;
  - `ADMIN_READ` de todos los servicios y `DATA_READ`/`DATA_WRITE` de KMS, IAM, Secret Manager,
    Cloud SQL y Cloud Storage en los tres entornos (`stages/1-base/main.tf:44-50`, `:59-88`).

  Volúmenes supuestos:
  - escenario A, *bajo*: 35 GiB/mes (prod 20, dev 5, qa 5, común 5);
  - escenario A, *alto*: 125 GiB/mes (prod 100, dev 10, qa 10, común 5);
  - escenario B, *alto*: 35 GiB/mes (dev 10, qa 10, prod 10 sin GKE, común 5).

  Cada GiB por encima de 50 cuesta 0.50.
- **VPC Flow Logs.** Son *vended logs*, sin nivel gratuito. El muestreo es:
  - 0.5 en dev y qa (`stages/2-networks/envs/dev/terraform.tfvars.example:38`);
  - 1.0 en prod (`stages/2-networks/envs/prod/terraform.tfvars.example:38`);
  - 1.0 en el hub y en `onprem-sim`, por defecto del módulo
    (`modules/network-hub/variables.tf:106-109`; ADR 0027, CIS 3.10).

  Volúmenes en GiB/mes, con *bajo* / *alto*:
  - dev: 0.4 / 2;
  - qa: 0.4 / 5;
  - prod: 0.8 / 40 en el escenario A y 0.8 / 4 en el B;
  - hub y `onprem-sim` juntos: 0.4 / 2.

  HIPÓTESIS: el volumen crece en proporción al muestreo. Por eso prod y el hub tienen el doble
  del volumen que tenían con muestreo 0.5.
- **Métricas de log y alertas de auditoría (CIS 2.5 a 2.12).** Son nueve, una sola vez en el
  proyecto (`stages/1-base/main.tf:140`, `modules/audit-alerts/main.tf:24`, `:164-165`). Las
  alertas no cobran (punto anterior). Las métricas de log cuentan solo cuando hay entradas que
  coinciden: cambios de IAM, firewall, rutas, redes, buckets o Cloud SQL. Por eso se toman en 0
  (HIPÓTESIS: no se buscó el precio de métricas definidas por el usuario).
- **Monitoring y Secret Manager no tienen cargo con este tamaño:**
  - **Uptime checks.** Hay 1 por entorno con balanceador externo, cada 60 s: 43,800 ejecuciones
    al mes por región de verificación
    (`stages/3-workloads/envs/prod/operations.tf:16`, `modules/observability/variables.tf:97`).
    Sin `selected_regions` corre desde todas (`modules/observability/variables.tf:99`; 6
    ubicaciones, HIPÓTESIS). Eso da 262,800 por entorno y 788,400 en los tres. El total queda
    bajo el millón gratuito, que ahora es uno solo para el proyecto.
  - **Managed Service for Prometheus.** Cobra 0.06 USD por millón de muestras. El repo no crea
    recursos `PodMonitoring` y GKE solo envía métricas de sistema (`modules/gke/main.tf:127-131`),
    así que se toma 0.
  - **Secret Manager.** Hay 3 secretos × 2 ubicaciones = 6 versiones activas, justo las 6
    gratuitas por cuenta de facturación (`stages/1-base/terraform.tfvars.example:19-23`,
    `stages/1-base/kms.tf:76-94`). Cada versión o rotación adicional cuesta 0.06 USD/mes por
    ubicación.
- **Redondeo.** Cada renglón se redondea a centavos (mitad hacia arriba), y los totales suman los
  renglones ya redondeados. Un script aparte recalculó todas las cifras (§8).

## 2. Dimensionamiento tomado del repositorio

Las rutas son relativas a `gcp-datacenter/`. Las raíces `stages/3-workloads/envs/{dev,qa,prod}` y
`stages/2-networks/envs/{dev,qa,prod}` solo difieren en `backend.tf` y `terraform.tfvars.example`
(se comprobó con `diff -rq` el 2026-11-24). Por eso las citas de código de prod valen para los
tres entornos.

### 2.1 Interruptores por entorno (`stages/3-workloads/envs/<env>/terraform.tfvars.example`)

| Variable | dev | qa | prod |
|---|---|---|---|
| `enable_dr` / `dr_active` | false / false (l. 17-18) | false / false (l. 17-18) | true / false (l. 18-19) |
| `enable_gke` | false (l. 21) | false (l. 20) | true (l. 24) |
| `enable_mig` | false (l. 22) | true (l. 21) | true (l. 25) |
| `enable_cloud_run` | true (l. 23) | true (l. 22) | true (l. 26) |
| `enable_filestore` | false (l. 24) | false (l. 23) | true (l. 27) |
| `enable_memorystore` | false (l. 25) | true (l. 24) | true (l. 28) |
| `enable_internal_lb` | false (l. 26) | false (l. 25) | true (l. 29) |
| `enable_backup` | true (l. 27) | true (l. 26) | true (l. 30) |
| Spoke: `enable_dr` (`stages/2-networks/envs/<env>/terraform.tfvars.example`) | false (l. 14) | false (l. 14) | true (l. 14) |

En el hub (`stages/2-networks/terraform.tfvars.example`):

- `enable_vpn_dr = true` (l. 27);
- `simulate_onprem = true` (l. 38);
- `enable_interconnect = false` (l. 44).

### 2.2 Tamaños

| Pieza | Tamaño | Fuente |
|---|---|---|
| GKE | Clúster regional (location = región) | `stages/3-workloads/envs/prod/compute.tf:13`, `modules/gke/main.tf:31` |
| GKE: nodos | Pool `general`, e2-standard-4, mín. 1 y máx. 3 **por zona** | `stages/3-workloads/envs/prod/terraform.tfvars.example:44-50`, `stages/3-workloads/envs/prod/variables.tf:272` |
| GKE: zonas | 3 (sin `node_locations`, el clúster regional usa tres zonas) | `modules/gke/main.tf:206`; [regional-clusters](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/regional-clusters) |
| GKE: disco de nodo | 100 GB pd-balanced | `stages/3-workloads/envs/prod/variables.tf:277-278` |
| GKE: Binary Authorization | Aplicada en el clúster; una sola política en el proyecto (`1-base`) | `modules/gke/main.tf:88-90`, `stages/1-base/artifacts.tf:132` |
| MIG | e2-standard-2; qa 1 a 3 VM, prod 2 a 6 VM; regional | `stages/3-workloads/envs/qa/terraform.tfvars.example:30-32`, `stages/3-workloads/envs/prod/terraform.tfvars.example:59-61`, `modules/compute-mig/main.tf:138` |
| MIG: disco | 50 GB pd-balanced | `modules/compute-mig/variables.tf:201`, `:212` |
| Cloud Run | 1 vCPU, 512 MiB, mín. 0 instancias, máx. 10 | `modules/cloud-run/variables.tf:162`, `:173`, `:184`; `stages/3-workloads/envs/prod/variables.tf:511-514` |
| Cloud SQL | Edición ENTERPRISE, PostgreSQL 16, siempre se crea | `modules/cloud-sql/variables.tf:126`, `stages/3-workloads/envs/prod/data.tf:5` |
| Cloud SQL: tipo | dev `db-custom-1-3840` (1 vCPU, 3.75 GiB); qa y prod `db-custom-2-7680` (2 vCPU, 7.5 GiB) | `stages/3-workloads/envs/dev/terraform.tfvars.example:38`, `…/qa/…:42`, `…/prod/…:71` |
| Cloud SQL: HA | ZONAL fuera de prod, REGIONAL (HA) en prod | `modules/cloud-sql/main.tf:6` |
| Cloud SQL: disco | 20 GB PD_SSD con crecimiento automático | `modules/cloud-sql/main.tf:78-80`, `modules/cloud-sql/variables.tf:267` |
| Cloud SQL: réplica de DR | Con `enable_dr`, en `dr_region`, mismo tipo, disco y disponibilidad (REGIONAL en prod) | `modules/cloud-sql/main.tf:232`, `:246-250` |
| Memorystore | 5 GB; BASIC fuera de prod, STANDARD_HA en prod | `…/qa/terraform.tfvars.example:49`, `…/prod/terraform.tfvars.example:76`, `modules/memorystore/main.tf:5` |
| Filestore | REGIONAL, 1024 GiB (prod) | `stages/3-workloads/envs/prod/terraform.tfvars.example:77-78` |
| Cloud Storage: bucket de la app | STANDARD. Sin DR: regional. Con `enable_dr`: doble región `us-central1`+`us-east4` con turbo replication | `stages/3-workloads/envs/prod/data.tf:105`, `:115-119`, `modules/storage/variables.tf:113` |
| Cloud Storage: estado | Multirregión US | `stages/0-bootstrap/terraform.tfvars.example:24`, `stages/0-bootstrap/main.tf:178-182` |
| Cloud Storage: logs de auditoría | `us-central1`, STANDARD, CMEK, retención de 365 días | `stages/1-base/main.tf:113-136`, `stages/1-base/terraform.tfvars.example:48`, `modules/log-export/variables.tf:83` |
| HA VPN | 4 instancias de 2 túneles = **8 túneles**: hub primaria, onprem-sim primaria, hub de DR y onprem-sim de DR | `stages/2-networks/vpn.tf:96`, `:129`, `:183`, `:209`; 2 sesiones BGP por VPN (`stages/2-networks/vpn.tf:42-49`), un túnel por sesión (`modules/hybrid-connectivity/main.tf:63-64`) |
| Cloud Router | Hub: uno por región; onprem-sim: primaria y DR | `modules/network-hub/main.tf:48-49`, `stages/2-networks/vpn.tf:171` |
| Cloud NAT | Uno por spoke y región activa, `AUTO_ONLY`: dev 1, qa 1, prod 2 (con DR) = 4 | `modules/network-spoke/main.tf:6-9`, `:209`, `:216` |
| Balanceador externo | Uno por entorno: existe si hay algún backend, y Cloud Run está encendido en los tres. 2 reglas de reenvío globales (443 y 80) | `stages/3-workloads/envs/prod/load_balancing.tf:86`, `:178-180`; `modules/load-balancer/main.tf:255`, `:290` |
| Balanceador interno | Uno por región con cómputo (solo la primaria sin `dr_active`), 2 reglas `INTERNAL_MANAGED` (443 y 80) | `stages/3-workloads/envs/prod/load_balancing.tf:204-206`; `modules/load-balancer/main.tf:447`, `:492` |
| Cloud Armor | 1 política por balanceador externo, 12 reglas: 9 OWASP, cve-canary, límite de tasa y regla por defecto | `stages/3-workloads/envs/prod/load_balancing.tf:166-168`; `modules/cloud-armor/variables.tf:56-65`; `modules/cloud-armor/main.tf:44`, `:58`, `:85` |
| Cloud KMS | 72 llaves SOFTWARE con rotación de 90 días (detalle debajo de la tabla) | `stages/1-base/kms.tf:13-14`, `:42-54`; `stages/1-base/main.tf:93-109`; `stages/0-bootstrap/main.tf:147-163`; `modules/kms/variables.tf:66`; `stages/1-base/variables.tf:176-179` |
| Secret Manager | 1 secreto por entorno con réplica en 2 regiones = 6 versiones activas cuando se carguen los valores | `stages/1-base/terraform.tfvars.example:19-23`, `stages/1-base/kms.tf:76-94` |
| Artifact Registry | 1 repositorio Docker por entorno y aplicación (3 con `applications = ["app"]`) en la multirregión `us` | `stages/1-base/artifacts.tf:7-13`, `:47-51`; `stages/1-base/variables.tf:120` |
| Backup and DR | Bóveda en `dr_region` y plan diario de Cloud SQL (30 días) en cada entorno | `stages/3-workloads/envs/prod/operations.tf:40`, `:50`; `modules/backup-dr/main.tf:23-25` |
| Backup for GKE | Solo con `enable_backup`, `enable_gke` y `enable_dr` (prod); plan en `dr_region`, todos los namespaces | `stages/3-workloads/envs/prod/operations.tf:34`, `modules/backup-dr/main.tf:88-92`, `:107-109` |
| Cloud DNS | 19 zonas: 1 de reenvío en el hub + 6 por spoke; registro de consultas encendido | `stages/2-networks/dns.tf:22-31`, `stages/2-networks/envs/prod/dns.tf:58-92` |
| Logging | Sink de proyecto con el filtro `logName:"cloudaudit.googleapis.com"` hacia el bucket de logs. Acceso a datos de 5 servicios en todo el proyecto. GKE con logs de sistema y de cargas. Flow logs: 0.5 en dev y qa, 1.0 en prod, hub y `onprem-sim`. NAT: solo errores | `stages/1-base/main.tf:44-50`, `:59-88`; `modules/log-export/main.tf:98`, `modules/log-export/variables.tf:148`; `modules/gke/main.tf:123-125`; `stages/2-networks/envs/prod/terraform.tfvars.example:38`; `modules/network-spoke/main.tf:230-232` |
| Monitoring | Managed Prometheus en GKE; 1 uptime check cada 60 s por entorno; políticas de alerta por entorno | `modules/gke/main.tf:127-131`, `modules/observability/variables.tf:97`, `modules/observability/main.tf:129`, `:175`, `:225`, `:266`, `:335` |
| SCC | Solo la notificación de hallazgos; la activación (Standard) es manual | `stages/1-base/main.tf:163-200` |
| Política de firewall de red | Una por VPC, asociada a la VPC; se supone cobro por VM, como la jerárquica (§3) | `modules/firewall/main.tf:50`, `:56` |
| Presupuesto | `budget_amount = 300` (moneda de la cuenta de facturación), en `0-bootstrap` | `stages/0-bootstrap/terraform.tfvars.example:28`, `stages/0-bootstrap/main.tf:253` |

Las 72 llaves de Cloud KMS se reparten así:

- 69 de los entornos, en `1-base`: 3 entornos × (2 regiones × 10 usos + multirregión × 3 usos);
- 2 comunes de `1-base` (`logs` y `pubsub`);
- 1 del estado, en `0-bootstrap`.

## 3. Precios unitarios

`*` = **SUPUESTO**: valor no leído en la página oficial. El motivo está en la columna Nota.

| Concepto | Precio usado | Fuente | Nota |
|---|---|---|---|
| e2-standard-2 / e2-standard-4 | 0.06701142 / 0.13402284 USD/h | [compute general-purpose](https://cloud.google.com/products/compute/pricing/general-purpose) | us-central1 |
| pd-balanced | 0.000136986 USD/GiB-h (0.10/GiB-mes) | [disks-image-pricing](https://cloud.google.com/compute/disks-image-pricing) | us-central1 |
| Cuota de clúster GKE | 0.10 USD/clúster-h | [kubernetes-engine/pricing](https://cloud.google.com/kubernetes-engine/pricing) | Crédito de 74.40 USD solo para zonales y Autopilot |
| Backup for GKE | 0.012328767 USD/namespace-h; 0.000061644 USD/GiB-h | [kubernetes-engine/pricing](https://cloud.google.com/kubernetes-engine/pricing) | Tabla de us-central1; el plan está en us-east4 \* |
| Binary Authorization para GKE | 0.01613 USD/clúster-h; crédito de 12 USD/mes por cuenta | [binary-authorization/pricing](https://cloud.google.com/binary-authorization/pricing) | Gratis para Cloud Run |
| Cloud SQL ENTERPRISE | vCPU 0.0413, RAM 0.007 USD/GiB-h; HA: 0.0826 y 0.014 | [sql/pricing](https://cloud.google.com/sql/pricing) | us-central1 |
| Cloud SQL SSD | 0.000232877 USD/GiB-h (0.17/GiB-mes); HA 0.000465753 (0.34) | [sql/pricing](https://cloud.google.com/sql/pricing) | us-central1 |
| Cloud SQL en us-east4 (réplica HA) | vCPU 0.0930, RAM 0.0158 USD/GiB-h; SSD HA 0.374 USD/GiB-mes | — | \* El selector de región no se pudo leer |
| Memorystore for Redis M2 (5-10 GB) | BASIC 0.027; STANDARD_HA 0.054 USD/GB-h | — | \* La página oficial respondió 404 el 2026-11-23 |
| Filestore REGIONAL | 0.000616438 USD/GiB-h (0.45/GiB-mes) | [filestore/pricing](https://cloud.google.com/filestore/pricing) | us-central1, sin Custom Performance |
| Cloud Storage STANDARD | Regional 0.000027397 USD/GiB-h (0.02/GiB-mes); doble región 0.000030137 por región; multirregión 0.000035616; turbo replication 0.04 USD/GiB escrito | [storage/pricing](https://cloud.google.com/storage/pricing) | SKU de doble región de us-east4 igual al de us-central1 \* |
| HA VPN | 0.05 USD/túnel-h; IP usada por un túnel sin cargo | [vpn/pricing](https://cloud.google.com/vpn/pricing) | us-central1; mismo valor para us-east4 \* |
| Cloud NAT | 0.0014 USD/h por VM (hasta 32); 0.005 USD/h por IP; 0.045 USD/GiB procesado | [nat/pricing](https://cloud.google.com/nat/pricing) | El procesamiento es igual en todas las regiones |
| Cloud Router | Sin cargo | [vpc/network-pricing](https://cloud.google.com/vpc/network-pricing) | |
| Balanceador externo | 0.025 USD/h por las primeras 5 reglas de reenvío; 0.008 USD/GiB procesado | [vpc/network-pricing](https://cloud.google.com/vpc/network-pricing) | IP estática asignada a una regla de reenvío: sin cargo |
| Balanceador interno de aplicaciones | 0.025 USD/proxy-h; mínimo 3 proxies por regla de reenvío; 0.008 USD/GiB | [vpc/network-pricing](https://cloud.google.com/vpc/network-pricing) | us-central1 |
| VPC Flow Logs (vended) | 0.25 USD/GiB (0 a 10 TiB) | [vpc/network-pricing](https://cloud.google.com/vpc/network-pricing) | Sin nivel gratuito |
| Cloud Armor Standard | Política 0.006849315 USD/h (5/mes); regla 0.001369863 USD/h (1/mes); 0.75 USD por millón de solicitudes | [armor/pricing](https://cloud.google.com/armor/pricing) | |
| Cloud DNS | 0.000273973 USD/zona-h (0.20/mes, primeras 25); 0.40 USD por millón de consultas | [dns/pricing](https://cloud.google.com/dns/pricing) | Sin nivel gratuito |
| Cloud KMS | 0.000082192 USD/versión-h (0.06/mes, SOFTWARE); 0.03 USD por 10 mil operaciones | [kms/pricing](https://cloud.google.com/kms/pricing) | Versión programada para destrucción sigue activa |
| Secret Manager | 6 versiones activas gratis por cuenta; luego 0.000082192 USD/h; se cobra por ubicación | [secret-manager/pricing](https://cloud.google.com/secret-manager/pricing) | |
| Artifact Registry | 0.000136986 USD/GiB-h (0.10/GiB-mes) sobre 0.5 GiB | [artifact-registry/pricing](https://cloud.google.com/artifact-registry/pricing) | Igual regional y multirregional |
| Backup and DR (Cloud SQL) | Almacenamiento 0.000061644 USD/GiB-h; gestión 0.000068493 USD/GiB-h; transferencia entre regiones de Norteamérica 0.02 USD/GiB | [backup-disaster-recovery/pricing](https://cloud.google.com/backup-disaster-recovery/pricing) | Tabla de us-central1; la bóveda está en us-east4 \* |
| Cloud Run (facturación por solicitud) | 0.000024 USD/vCPU-s; 0.0000025 USD/GiB-s; 0.40 USD por millón de solicitudes; gratis 180,000 vCPU-s, 360,000 GiB-s y 2 M de solicitudes por mes | [run/pricing](https://cloud.google.com/run/pricing) | us-central1 |
| Cloud Logging | 0.50 USD/GiB sobre 50 GiB/proyecto/mes | [observability/pricing](https://cloud.google.com/products/observability/pricing) | Un solo proyecto: un solo nivel gratuito. Retención > 30 días: 0.01 USD/GiB-mes (no aplica: el sink escribe en Cloud Storage) |
| Uptime checks / alertas | 0.30 USD por mil ejecuciones sobre 1 M/proyecto; alertas sin cargo hasta septiembre de 2027 | [observability/pricing](https://cloud.google.com/products/observability/pricing) | |
| Política de firewall de red | 0.001369863 USD/VM-h, tarifa de la política jerárquica (≤ 500 atributos) | [firewall/pricing](https://cloud.google.com/firewall/pricing) | \* **Por verificar.** La página se arma con JavaScript y no se pudo leer la tarifa de las políticas de red. Se usa la de la jerárquica |
| Certificate Manager | Primeros 100 certificados por proyecto gratis | [certificate-manager/pricing](https://cloud.google.com/certificate-manager/pricing) | |
| Connectivity Tests | 20 gratis por mes; 0.15 USD por prueba adicional | [network-intelligence-center/pricing](https://cloud.google.com/products/network-intelligence-center/pricing) | |
| SCC Standard | Sin cargo | [security-command-center/pricing](https://cloud.google.com/security-command-center/pricing) | |

## 4. Escenario A: diseño completo

Usa los valores de ejemplo de los tres entornos, `enable_vpn_dr = true` y DR de datos en prod.
Con `dr_active = false` no hay cómputo en `us-east4`.

| Bloque | USD/mes bajo | USD/mes alto |
|---|---:|---:|
| Común (`1-base` y hub) | 151.10 | 197.06 |
| `0-bootstrap` | 0.06 | 0.09 |
| dev | 90.04 | 104.16 |
| qa | 297.49 | 417.59 |
| prod (región primaria) | 1,527.09 | 2,454.36 |
| Extras de DR de prod | 384.82 | 398.32 |
| **Total** | **2,450.60** | **3,571.58** |
| **Por día** | **80.57** | **117.42** |

Por día: 2,450.60 × 24 / 730 = 80.57 y 3,571.58 × 24 / 730 = 117.42. El total supera el
presupuesto de ejemplo de 300 (`stages/0-bootstrap/terraform.tfvars.example:28`).

`*` en un renglón = usa un precio SUPUESTO de la §3. Los precios de las columnas de cálculo están
en USD por hora (× 730) o por unidad.

### 4.1 Común (`1-base` y hub)

| Componente | Cálculo bajo | Bajo | Cálculo alto | Alto |
|---|---|---:|---|---:|
| HA VPN primaria: 2 túneles del hub + 2 de onprem-sim (us-central1) | 4 túneles × 0.05 × 730 | 146.00 | igual | 146.00 |
| Cloud Router (hub y onprem-sim) | sin cargo | 0.00 | igual | 0.00 |
| Cloud DNS: zona de reenvío del hub | 1 zona × 0.000273973 × 730 | 0.20 | igual | 0.20 |
| Cloud DNS: consultas del hub | 0.5 M × 0.40 | 0.20 | 5 M × 0.40 | 2.00 |
| Cloud KMS: 71 versiones activas (69 de los entornos + 2 comunes, todas de `1-base`) | 71 versiones × 0.000082192 × 730 | 4.26 | igual | 4.26 |
| Cloud KMS: operaciones | 10 bloques de 10 mil ops × 0.03 | 0.30 | 200 bloques de 10 mil ops × 0.03 | 6.00 |
| Bucket de logs de auditoría (us-central1), con acceso a datos de los tres entornos | 2 GiB × 0.000027397 × 730 | 0.04 | 30 GiB × 0.000027397 × 730 | 0.60 |
| Flow logs del hub y onprem-sim (vended, muestreo 1.0) | 0.4 GiB × 0.25 | 0.10 | 2 GiB × 0.25 | 0.50 |
| Cloud Logging del proyecto (sobre 50 GiB gratis) | 35 GiB < 50 GiB | 0.00 | (125 − 50) GiB × 0.50 | 37.50 |
| SCC Standard, Pub/Sub de hallazgos, presupuesto, IAM (incluye la política de denegación), etiquetas, WIF; con organización, políticas de organización y VPC-SC | sin cargo / despreciable | 0.00 | igual | 0.00 |
| **Total** | | **151.10** | | **197.06** |

### 4.2 `0-bootstrap`

| Componente | Cálculo bajo | Bajo | Cálculo alto | Alto |
|---|---|---:|---|---:|
| Cloud KMS: llave del estado (multirregión us) | 1 versión × 0.000082192 × 730 | 0.06 | igual | 0.06 |
| Bucket de estado (multirregión US) | 0.1 GiB × 0.000035616 × 730 | 0.00 | 1 GiB × 0.000035616 × 730 | 0.03 |
| **Total** | | **0.06** | | **0.09** |

### 4.3 dev

| Componente | Cálculo bajo | Bajo | Cálculo alto | Alto |
|---|---|---:|---|---:|
| Cloud SQL `db-custom-1-3840`, ZONAL | 1 vCPU × 0.0413 × 730 + 3.75 GiB × 0.007 × 730 + 20 GiB × 0.000232877 × 730 | 52.71 | igual | 52.71 |
| Balanceador externo: reglas 443 y 80 (tarifa fija hasta 5 reglas) | 1 × 0.025 × 730 | 18.25 | igual | 18.25 |
| Balanceador externo: datos procesados | 5 GiB × 0.008 | 0.04 | 50 GiB × 0.008 | 0.40 |
| Cloud Armor: política y 12 reglas | 1 política × 0.006849315 × 730 + 12 reglas × 0.001369863 × 730 | 17.00 | igual | 17.00 |
| Cloud Armor: solicitudes | 0.2 M × 0.75 | 0.15 | 1 M × 0.75 | 0.75 |
| Cloud Run (mín. 0 instancias) | nivel gratuito | 0.00 | igual | 0.00 |
| Cloud NAT: gateway sin VM + IP | 0 VM, 0 IP | 0.00 | 1 IP × 0.005 × 730 | 3.65 |
| Cloud NAT: datos procesados | 2 GiB × 0.045 | 0.09 | 20 GiB × 0.045 | 0.90 |
| Cloud DNS: 6 zonas del spoke | 6 zonas × 0.000273973 × 730 | 1.20 | igual | 1.20 |
| Cloud DNS: consultas | 0.5 M × 0.40 | 0.20 | 5 M × 0.40 | 2.00 |
| VPC Flow Logs (vended, muestreo 0.5) | 0.4 GiB × 0.25 | 0.10 | 2 GiB × 0.25 | 0.50 |
| Bucket de la aplicación (regional) | 1 GiB × 0.000027397 × 730 | 0.02 | 50 GiB × 0.000027397 × 730 | 1.00 |
| Artifact Registry | 0.5 GiB × 0.000136986 × 730 | 0.05 | 5 GiB × 0.000136986 × 730 | 0.50 |
| Backup and DR de Cloud SQL (bóveda en us-east4)\* | 2 GiB × 0.000061644 × 730 + 2 GiB × 0.000068493 × 730 + 2 GiB × 0.02 | 0.23 | 20 GiB × 0.000061644 × 730 + 20 GiB × 0.000068493 × 730 + 20 GiB × 0.02 | 2.30 |
| Connectivity Tests (prueba de humo) | ≤ 20 gratis | 0.00 | 20 pruebas sobre las 20 gratis × 0.15 | 3.00 |
| **Total** | | **90.04** | | **104.16** |

### 4.4 qa

| Componente | Cálculo bajo | Bajo | Cálculo alto | Alto |
|---|---|---:|---|---:|
| Cloud SQL `db-custom-2-7680`, ZONAL | 2 vCPU × 0.0413 × 730 + 7.5 GiB × 0.007 × 730 + 20 GiB × 0.000232877 × 730 | 102.02 | igual | 102.02 |
| MIG e2-standard-2 + disco de 50 GiB pd-balanced | 1 VM × 0.06701142 × 730 + 50 GiB × 0.000136986 × 730 | 53.92 | 3 VM × 0.06701142 × 730 + 150 GiB × 0.000136986 × 730 | 161.75 |
| Memorystore BASIC 5 GB\* | 5 GB × 0.027 × 730 | 98.55 | igual | 98.55 |
| Balanceador externo: reglas 443 y 80 (tarifa fija hasta 5 reglas) | 1 × 0.025 × 730 | 18.25 | igual | 18.25 |
| Balanceador externo: datos procesados | 5 GiB × 0.008 | 0.04 | 50 GiB × 0.008 | 0.40 |
| Cloud Armor: política y 12 reglas | 1 política × 0.006849315 × 730 + 12 reglas × 0.001369863 × 730 | 17.00 | igual | 17.00 |
| Cloud Armor: solicitudes | 0.2 M × 0.75 | 0.15 | 1 M × 0.75 | 0.75 |
| Cloud Run (mín. 0 instancias) | nivel gratuito | 0.00 | igual | 0.00 |
| Cloud NAT: VM que usan el gateway + 1 IP | 1 VM × 0.0014 × 730 + 1 IP × 0.005 × 730 | 4.67 | 3 VM × 0.0014 × 730 + 1 IP × 0.005 × 730 | 6.72 |
| Cloud NAT: datos procesados | 2 GiB × 0.045 | 0.09 | 20 GiB × 0.045 | 0.90 |
| Cloud DNS: 6 zonas del spoke | 6 zonas × 0.000273973 × 730 | 1.20 | igual | 1.20 |
| Cloud DNS: consultas | 0.5 M × 0.40 | 0.20 | 5 M × 0.40 | 2.00 |
| VPC Flow Logs (vended, muestreo 0.5) | 0.4 GiB × 0.25 | 0.10 | 5 GiB × 0.25 | 1.25 |
| Política de firewall de red (por VM)\* | 1 VM × 0.001369863 × 730 | 1.00 | 3 VM × 0.001369863 × 730 | 3.00 |
| Bucket de la aplicación (regional) | 1 GiB × 0.000027397 × 730 | 0.02 | 50 GiB × 0.000027397 × 730 | 1.00 |
| Artifact Registry | 0.5 GiB × 0.000136986 × 730 | 0.05 | 5 GiB × 0.000136986 × 730 | 0.50 |
| Backup and DR de Cloud SQL (bóveda en us-east4)\* | 2 GiB × 0.000061644 × 730 + 2 GiB × 0.000068493 × 730 + 2 GiB × 0.02 | 0.23 | 20 GiB × 0.000061644 × 730 + 20 GiB × 0.000068493 × 730 + 20 GiB × 0.02 | 2.30 |
| **Total** | | **297.49** | | **417.59** |

### 4.5 prod (región primaria)

| Componente | Cálculo bajo | Bajo | Cálculo alto | Alto |
|---|---|---:|---|---:|
| Cloud SQL `db-custom-2-7680`, REGIONAL (HA) | 2 vCPU × 0.0826 × 730 + 7.5 GiB × 0.014 × 730 + 20 GiB × 0.000465753 × 730 | 204.05 | igual | 204.05 |
| GKE: cuota del clúster regional | 1 clúster × 0.10 × 730 | 73.00 | igual | 73.00 |
| GKE: nodos e2-standard-4 (1 a 3 por zona, 3 zonas) | 3 nodos × 0.13402284 × 730 | 293.51 | 9 nodos × 0.13402284 × 730 | 880.53 |
| GKE: discos de nodo 100 GiB pd-balanced | 300 GiB × 0.000136986 × 730 | 30.00 | 900 GiB × 0.000136986 × 730 | 90.00 |
| Binary Authorization para GKE | 0.01613 × 730 = 11.77 − crédito de 12 | 0.00 | igual | 0.00 |
| MIG e2-standard-2 + disco de 50 GiB pd-balanced | 2 VM × 0.06701142 × 730 + 100 GiB × 0.000136986 × 730 | 107.84 | 6 VM × 0.06701142 × 730 + 300 GiB × 0.000136986 × 730 | 323.51 |
| Memorystore STANDARD_HA 5 GB\* | 5 GB × 0.054 × 730 | 197.10 | igual | 197.10 |
| Filestore REGIONAL 1024 GiB | 1024 GiB × 0.000616438 × 730 | 460.80 | igual | 460.80 |
| Balanceador externo: reglas 443 y 80 (tarifa fija hasta 5 reglas) | 1 × 0.025 × 730 | 18.25 | igual | 18.25 |
| Balanceador externo: datos procesados | 5 GiB × 0.008 | 0.04 | 50 GiB × 0.008 | 0.40 |
| Cloud Armor: política y 12 reglas | 1 política × 0.006849315 × 730 + 12 reglas × 0.001369863 × 730 | 17.00 | igual | 17.00 |
| Cloud Armor: solicitudes | 0.2 M × 0.75 | 0.15 | 5 M × 0.75 | 3.75 |
| Balanceador interno: 2 reglas × 3 proxies | 6 proxies × 0.025 × 730 | 109.50 | igual | 109.50 |
| Balanceador interno: datos procesados | 5 GiB × 0.008 | 0.04 | 20 GiB × 0.008 | 0.16 |
| Cloud Run (mín. 0 instancias) | nivel gratuito | 0.00 | igual | 0.00 |
| Cloud Run: uso sobre el nivel gratuito | dentro del nivel gratuito | 0.00 | 820,000 vCPU-s × 0.000024 + 140,000 GiB-s × 0.0000025 + 3 M solicitudes × 0.40 | 21.23 |
| Cloud NAT: VM que usan el gateway (MIG + nodos) + 1 IP | 5 VM × 0.0014 × 730 + 1 IP × 0.005 × 730 | 8.76 | 15 VM × 0.0014 × 730 + 1 IP × 0.005 × 730 | 18.98 |
| Cloud NAT: datos procesados | 2 GiB × 0.045 | 0.09 | 20 GiB × 0.045 | 0.90 |
| Cloud DNS: 6 zonas del spoke | 6 zonas × 0.000273973 × 730 | 1.20 | igual | 1.20 |
| Cloud DNS: consultas | 0.5 M × 0.40 | 0.20 | 5 M × 0.40 | 2.00 |
| VPC Flow Logs (vended, muestreo 1.0) | 0.8 GiB × 0.25 | 0.20 | 40 GiB × 0.25 | 10.00 |
| Política de firewall de red (por VM)\* | 5 VM × 0.001369863 × 730 | 5.00 | 15 VM × 0.001369863 × 730 | 15.00 |
| Bucket de la aplicación (doble región, turbo replication)\* | 1 GiB × 0.000030137 × 730 × 2 regiones + 1 GiB escrito × 0.04 | 0.08 | 50 GiB × 0.000030137 × 730 × 2 regiones + 50 GiB escritos × 0.04 | 4.20 |
| Artifact Registry | 0.5 GiB × 0.000136986 × 730 | 0.05 | 5 GiB × 0.000136986 × 730 | 0.50 |
| Backup and DR de Cloud SQL (bóveda en us-east4)\* | 2 GiB × 0.000061644 × 730 + 2 GiB × 0.000068493 × 730 + 2 GiB × 0.02 | 0.23 | 20 GiB × 0.000061644 × 730 + 20 GiB × 0.000068493 × 730 + 20 GiB × 0.02 | 2.30 |
| **Total** | | **1,527.09** | | **2,454.36** |

Los logs de prod ya no tienen renglón propio: cuentan en el renglón de Cloud Logging del proyecto
(§4.1).

### 4.6 Extras de DR de prod

Esta tabla cubre lo que existe solo por `enable_vpn_dr = true` (hub) y `enable_dr = true` (spoke
y cargas de prod), sin conmutar. Con `dr_active = true` se suman además GKE, MIG, Cloud Run y el
balanceador interno en `us-east4`. Eso no se estima: es el estado durante un incidente.

| Componente | Cálculo bajo | Bajo | Cálculo alto | Alto |
|---|---|---:|---|---:|
| HA VPN de DR: 2 túneles del hub + 2 de onprem-sim (us-east4)\* | 4 túneles × 0.05 × 730 | 146.00 | igual | 146.00 |
| Réplica de Cloud SQL en us-east4, REGIONAL (HA)\* | 2 vCPU × 0.0930 × 730 + 7.5 GiB × 0.0158 × 730 + 20 GiB-mes × 0.374 | 229.77 | igual | 229.77 |
| Cloud NAT de DR (us-east4), sin VM\* | 0 VM, 0 IP | 0.00 | 1 IP × 0.005 × 730 | 3.65 |
| Backup for GKE: gestión (plan en us-east4)\* | 1 namespace × 0.012328767 × 730 | 9.00 | 2 namespaces × 0.012328767 × 730 | 18.00 |
| Backup for GKE: almacenamiento\* | 1 GiB × 0.000061644 × 730 | 0.05 | 20 GiB × 0.000061644 × 730 | 0.90 |
| Certificado interno de DR (Certificate Manager) | primeros 100 por proyecto gratis | 0.00 | igual | 0.00 |
| **Total** | | **384.82** | | **398.32** |

## 5. Escenario B: despliegue mínimo de prueba

Se aplican todas las etapas, con estos cambios sobre los valores de ejemplo:

- **`stages/3-workloads/envs/<env>` (los tres):**
  - `enable_dr = false`, `enable_gke = false`, `enable_mig = false`;
  - `enable_filestore = false`, `enable_memorystore = false`, `enable_internal_lb = false`;
  - `enable_cloud_run = true`; `enable_backup` sigue en `true`.

  Cloud SQL se crea siempre (`stages/3-workloads/envs/prod/data.tf:5`). En prod sigue siendo
  REGIONAL porque el módulo lo impone (`modules/cloud-sql/main.tf:6`,
  `modules/cloud-sql/variables.tf:154-157`).
- **`stages/2-networks/envs/prod`:** `enable_dr = false`, así que hay un solo Cloud NAT en prod.
- **Hub:** `enable_vpn_dr = false`. Quedan los 4 túneles de la VPN primaria: no hay interruptor
  para quitarlos mientras `simulate_onprem = true`.

| Bloque | USD/mes bajo | USD/mes alto | Tabla |
|---|---:|---:|---|
| Común (`1-base` y hub sin VPN de DR) | 151.10 | 159.56 | §4.1 con Logging alto de 35 GiB: 197.06 − 37.50 + 0.00 |
| `0-bootstrap` | 0.06 | 0.09 | Igual a la §4.2 |
| dev | 90.04 | 104.16 | Igual a la §4.3 |
| qa | 139.35 | 150.47 | §5.1 |
| prod | 241.48 | 253.00 | §5.2 |
| **Total** | **622.03** | **667.28** | |

| Duración | Escenario B completo | Variante solo dev |
|---|---:|---:|
| Mes | 622.03 – 667.28 | 241.20 – 263.81 |
| Día | **20.45 – 21.94** | **7.93 – 8.67** |
| Semana | 143.15 – 153.58 | 55.51 – 60.69 |
| Prueba de 2 días | 40.90 – 43.88 | 15.86 – 17.34 |
| Prueba de 3 días | 61.35 – 65.82 | 23.79 – 26.01 |
| Días que cubren 300 USD de crédito | 14.7 – 13.7 | 37.8 – 34.6 |

Cómo salen las cifras de la variante solo dev:

- Mes = común + `0-bootstrap` + dev: 151.10 + 0.06 + 90.04 = 241.20 y
  159.56 + 0.09 + 104.16 = 263.81.
- Día = mes × 24 / 730: 7.93 y 8.67. En el escenario B completo, 622.03 × 24 / 730 = 20.45 y
  667.28 × 24 / 730 = 21.94.
- Días con 300 USD = 300 / día.

La variante solo dev aplica `0-bootstrap`, `1-base`, el hub (`stages/2-networks`) y solo
`envs/dev` de `2-networks` y `3-workloads`. Con sus valores por defecto, `1-base` sigue creando
las 69 llaves de los tres entornos (4.26 USD/mes en la §4.1); la §6.2 tiene la palanca para
reducirlas. Es también la variante más fácil de apagar:

- dev usa `deletion_protection = false`
  (`stages/3-workloads/envs/dev/terraform.tfvars.example:28`);
- `destroy.yml` destruye `3-workloads/envs/dev` y, con `incluir_red`, también el spoke
  (`../.github/workflows/destroy.yml:8-9`).

Los cargos por hora se prorratean: un recurso que existe N horas cuesta N/730 de su renglón
mensual (Cloud DNS y Cloud KMS lo dicen así en sus páginas). En una prueba de pocos días casi
todo el costo es fijo:

- Cloud SQL;
- los 4 túneles de VPN: 146.00 × 24 / 730 = 4.80 USD/día;
- el balanceador con Cloud Armor: 35.25 × 24 / 730 = 1.16 USD/día por entorno.

### 5.1 qa (escenario B)

| Componente | Cálculo bajo | Bajo | Cálculo alto | Alto |
|---|---|---:|---|---:|
| Cloud SQL `db-custom-2-7680`, ZONAL | 2 vCPU × 0.0413 × 730 + 7.5 GiB × 0.007 × 730 + 20 GiB × 0.000232877 × 730 | 102.02 | igual | 102.02 |
| Balanceador externo: reglas 443 y 80 (tarifa fija hasta 5 reglas) | 1 × 0.025 × 730 | 18.25 | igual | 18.25 |
| Balanceador externo: datos procesados | 5 GiB × 0.008 | 0.04 | 50 GiB × 0.008 | 0.40 |
| Cloud Armor: política y 12 reglas | 1 política × 0.006849315 × 730 + 12 reglas × 0.001369863 × 730 | 17.00 | igual | 17.00 |
| Cloud Armor: solicitudes | 0.2 M × 0.75 | 0.15 | 1 M × 0.75 | 0.75 |
| Cloud Run (mín. 0 instancias) | nivel gratuito | 0.00 | igual | 0.00 |
| Cloud NAT: gateway sin VM + IP | 0 VM, 0 IP | 0.00 | 1 IP × 0.005 × 730 | 3.65 |
| Cloud NAT: datos procesados | 2 GiB × 0.045 | 0.09 | 20 GiB × 0.045 | 0.90 |
| Cloud DNS: 6 zonas del spoke | 6 zonas × 0.000273973 × 730 | 1.20 | igual | 1.20 |
| Cloud DNS: consultas | 0.5 M × 0.40 | 0.20 | 5 M × 0.40 | 2.00 |
| VPC Flow Logs (vended, muestreo 0.5) | 0.4 GiB × 0.25 | 0.10 | 2 GiB × 0.25 | 0.50 |
| Bucket de la aplicación (regional) | 1 GiB × 0.000027397 × 730 | 0.02 | 50 GiB × 0.000027397 × 730 | 1.00 |
| Artifact Registry | 0.5 GiB × 0.000136986 × 730 | 0.05 | 5 GiB × 0.000136986 × 730 | 0.50 |
| Backup and DR de Cloud SQL (bóveda en us-east4)\* | 2 GiB × 0.000061644 × 730 + 2 GiB × 0.000068493 × 730 + 2 GiB × 0.02 | 0.23 | 20 GiB × 0.000061644 × 730 + 20 GiB × 0.000068493 × 730 + 20 GiB × 0.02 | 2.30 |
| **Total** | | **139.35** | | **150.47** |

### 5.2 prod (escenario B)

| Componente | Cálculo bajo | Bajo | Cálculo alto | Alto |
|---|---|---:|---|---:|
| Cloud SQL `db-custom-2-7680`, REGIONAL (HA) | 2 vCPU × 0.0826 × 730 + 7.5 GiB × 0.014 × 730 + 20 GiB × 0.000465753 × 730 | 204.05 | igual | 204.05 |
| Balanceador externo: reglas 443 y 80 (tarifa fija hasta 5 reglas) | 1 × 0.025 × 730 | 18.25 | igual | 18.25 |
| Balanceador externo: datos procesados | 5 GiB × 0.008 | 0.04 | 50 GiB × 0.008 | 0.40 |
| Cloud Armor: política y 12 reglas | 1 política × 0.006849315 × 730 + 12 reglas × 0.001369863 × 730 | 17.00 | igual | 17.00 |
| Cloud Armor: solicitudes | 0.2 M × 0.75 | 0.15 | 1 M × 0.75 | 0.75 |
| Cloud Run (mín. 0 instancias) | nivel gratuito | 0.00 | igual | 0.00 |
| Cloud NAT: gateway sin VM + IP | 0 VM, 0 IP | 0.00 | 1 IP × 0.005 × 730 | 3.65 |
| Cloud NAT: datos procesados | 2 GiB × 0.045 | 0.09 | 20 GiB × 0.045 | 0.90 |
| Cloud DNS: 6 zonas del spoke | 6 zonas × 0.000273973 × 730 | 1.20 | igual | 1.20 |
| Cloud DNS: consultas | 0.5 M × 0.40 | 0.20 | 5 M × 0.40 | 2.00 |
| VPC Flow Logs (vended, muestreo 1.0) | 0.8 GiB × 0.25 | 0.20 | 4 GiB × 0.25 | 1.00 |
| Bucket de la aplicación (regional, sin DR) | 1 GiB × 0.000027397 × 730 | 0.02 | 50 GiB × 0.000027397 × 730 | 1.00 |
| Artifact Registry | 0.5 GiB × 0.000136986 × 730 | 0.05 | 5 GiB × 0.000136986 × 730 | 0.50 |
| Backup and DR de Cloud SQL (bóveda en us-east4)\* | 2 GiB × 0.000061644 × 730 + 2 GiB × 0.000068493 × 730 + 2 GiB × 0.02 | 0.23 | 20 GiB × 0.000061644 × 730 + 20 GiB × 0.000068493 × 730 + 20 GiB × 0.02 | 2.30 |
| **Total** | | **241.48** | | **253.00** |

## 6. Mayores costos y cómo reducirlos

### 6.1 Mayores costos (escenario A, columna baja)

Porcentaje = USD/mes × 100 / 2,450.60.

| Categoría | USD/mes | % del total |
|---|---:|---:|
| Cloud SQL (dev, qa, prod HA y réplica HA en us-east4\*): 52.71 + 102.02 + 204.05 + 229.77 | 588.55 | 24.0 % |
| Filestore REGIONAL 1024 GiB | 460.80 | 18.8 % |
| GKE (cuota, 3 nodos, discos, Backup for GKE): 73.00 + 293.51 + 30.00 + 9.00 + 0.05 | 405.56 | 16.5 % |
| Memorystore (qa BASIC y prod STANDARD_HA)\*: 98.55 + 197.10 | 295.65 | 12.1 % |
| HA VPN (8 túneles; 4 de ellos de onprem-sim): 146.00 × 2 | 292.00 | 11.9 % |
| MIG (qa 1 VM, prod 2 VM): 53.92 + 107.84 | 161.76 | 6.6 % |
| Balanceador interno de prod: 109.50 + 0.04 | 109.54 | 4.5 % |
| Balanceador externo + Cloud Armor (3 entornos): 3 × (18.25 + 0.04 + 17.00 + 0.15) | 106.32 | 4.3 % |

En el escenario B, el costo se concentra en tres renglones, cada uno con su porcentaje sobre
622.03:

- Cloud SQL: 358.78 USD/mes (52.71 + 102.02 + 204.05), 58 %;
- la VPN primaria: 146.00, 23 %;
- el balanceador externo con Cloud Armor en los tres entornos: 106.32, 17 %.

### 6.2 Palancas

Ahorros mensuales calculados con los precios de la §3. Las palancas que piden cambiar código, y no
solo variables, están marcadas como tales: son propuestas, no cambios hechos.

- **Filestore.**
  - `filestore_capacity_gb = 100` con tier REGIONAL (el módulo admite de 100 a 10239,
    `modules/filestore/variables.tf:97-98`): 100 × 0.000616438 × 730 = 45.00 en vez de 460.80
    (−415.80).
  - ZONAL de 1024 GiB a 0.000342466 USD/GiB-h: 256.00 (−204.80).
  - Para pruebas, `enable_filestore = false`.
- **GKE.**
  - `node_locations` con una sola zona en `gke_node_pools` deja 1 nodo en vez de 3: −195.67 en
    nodos y −20.00 en discos.
  - La cuota de 73.00 sigue mientras el clúster sea regional. Un clúster zonal entraría en el
    crédito de 74.40 (cambio de código en `stages/3-workloads/envs/prod/compute.tf:13`).
- **Cloud SQL.**
  - El HA fuera de prod ya está apagado (ZONAL en dev y qa). En prod es obligatorio por diseño.
  - Bajar el tipo: qa con `db-custom-1-3840` cuesta 52.71 (−49.31); prod HA con
    `db-custom-1-3840`, 105.42 (−98.63).
  - La réplica de DR hereda REGIONAL (`modules/cloud-sql/main.tf:248`). Como ZONAL costaría cerca
    de la mitad (114.88\*, cambio de código).
- **Llaves de `1-base` en la variante solo dev.** Con `environments = ["dev"]` en `1-base`
  (`stages/1-base/variables.tf:89-102`) se crean 23 llaves de dev (2 regiones × 10 usos +
  multirregión × 3 usos) más las 2 comunes. Son 25 versiones × 0.000082192 × 730 = 1.50 en vez de
  4.26 (−2.76). Para pasar después a qa y prod hay que agregarlos a la lista y volver a aplicar
  `1-base`.
- **Apagado fuera de horario de dev y qa** (`off_hours_shutdown`, ya en los ejemplos de dev y qa;
  ADR 0028).
  - Horas apagadas por semana: H = 168 − días × (apagado − encendido). Con 5 días de 07:00 a
    20:00, H = 168 − 65 = 103 (61.3 %), o sea 730 × 103 / 168 = 447.56 h al mes.
  - Se deja de cobrar la vCPU y la memoria de Cloud SQL; el almacenamiento y la IP siguen.
    También se dejan de cobrar las VM del MIG y sus discos (el grupo baja a 0):
    - Cloud SQL dev: (1 × 0.0413 + 3.75 × 0.007) × 447.56 = −30.23;
    - Cloud SQL qa: (2 × 0.0413 + 7.5 × 0.007) × 447.56 = −60.47;
    - MIG de qa (1 VM y 50 GiB): (0.06701142 + 50 × 0.000136986) × 447.56 = −33.06. Además salen
      de noche los cargos por VM de Cloud NAT y de la política de firewall de red\* (menos de
      1.25).
  - Total frente a la columna baja del escenario A: −123.76 USD/mes. En el escenario B (sin
    MIG), −90.70.
  - Se suman los trabajos de Cloud Scheduler: 2 por instancia de Cloud SQL (4 en dev y qa) y 4
    por pool de GKE (`modules/off-hours-shutdown/main.tf:32-94`). Hay 3 gratis por cuenta de
    facturación, y el resto se cobra al precio por trabajo al mes de
    [scheduler/pricing](https://cloud.google.com/scheduler/pricing). Ese monto no se pudo leer el
    2026-11-23 y no está en esta suma.
  - Con el apagado, el MIG de qa tiene `mig_min_replicas` VM fijas en el horario, sin
    autoescalado por CPU. La columna alta de qa ya no aplica a ese renglón.
  - Con GKE en dev o qa, cada pool ahorra al menos (precio por hora del nodo + su disco) × zonas
    × `min_node_count` × 447.56. La cuota del clúster sigue.
- **VPN del on-premises simulado.**
  - Cada VPN son 2 túneles del hub más 2 de onprem-sim: 146.00 USD/mes (4.80 USD/día) por región.
  - `enable_vpn_dr = false` quita 146.00.
  - Con on-premises real (`simulate_onprem = false`) desaparecen los 4 túneles de onprem-sim
    (−146.00 si sigue la de DR).
  - La VPN primaria no tiene interruptor: es costo fijo del hub mientras exista.
- **Memorystore.** `enable_memorystore = false` en qa ahorra 98.55\*; en prod, 197.10\*.
- **Balanceador interno.**
  - Cada regla `INTERNAL_MANAGED` suma 3 proxies. La de redirección del puerto 80 duplica el
    cargo: 109.50 en vez de 54.75 (cambio de código en `modules/load-balancer/main.tf:492`).
  - Para pruebas, `enable_internal_lb = false`.
- **Balanceador externo y Cloud Armor:** 35.25 USD/mes fijos por entorno (18.25 + 17.00). Probar
  solo dev evita los de qa y prod.
- **Cloud NAT.** Pesa poco: 13.70 USD/mes en el escenario A (0.09 + 4.76 + 8.85). Cobra 0.0014
  USD/h por VM y 3.65 USD/mes por IP, así que crece con las VM de GKE y el MIG, no con los
  gateways vacíos ([ADR 0004](adr/0004-cloud-nat-en-cada-spoke.md)).
- **Logs del proyecto.** Con un solo proyecto, todos los entornos comparten los 50 GiB gratuitos
  de Logging. Cada GiB por encima cuesta 0.50, así que 100 GiB de logs de GKE en prod empujan
  también los de dev y qa sobre el nivel gratuito. Para pruebas, el volumen baja si se apagan los
  logs de cargas de GKE o el registro `VERBOSE` de Cloud Armor (cambio de código).
- **Apagar después de la prueba.**
  - `destroy.yml` destruye `3-workloads` de dev o qa y, con `incluir_red`, el spoke del entorno
    (`../.github/workflows/destroy.yml:8-17`).
  - Quedan cobrando el hub (con la VPN), `1-base` (llaves, repositorios, secretos, bucket de
    logs) y `0-bootstrap`. Para una prueba, la persona dueña borra el proyecto completo (ver la
    [guía del colaborador](guia-colaborador-gcp.md), apagado al terminar). Lo que sigue
    cobrando después del destroy:
    - Las versiones de KMS programadas para destrucción siguen activas 30 días
      (`modules/kms/variables.tf:67`): hasta 72 × 0.06 = 4.32 USD. Las llaves y los llaveros no
      se borran en Cloud KMS; solo se destruyen sus versiones.
    - El bucket de logs de auditoría guarda los objetos 365 días por su retención
      (`stages/1-base/terraform.tfvars.example:48`): centavos.
    - El bucket de estado tiene `prevent_destroy` (`stages/0-bootstrap/main.tf:231`).
  - Prod no se desmonta solo con `destroy`: tiene `deletion_protection` obligatoria
    (`stages/3-workloads/envs/prod/variables.tf:202-210`), y `destroy.yml` solo acepta dev y qa.
- **Presupuesto.**
  - `budget_amount = 300` (`stages/0-bootstrap/terraform.tfvars.example:28`) coincide con un
    crédito de 300 USD, y los avisos de umbral salen de `stages/0-bootstrap/main.tf:253-287`.
  - El presupuesto avisa; no corta el gasto.
  - Con 300 USD, el escenario B dura unos 14 días (§5), y el A no llega a 4 días.

### 6.3 Infracost en el pipeline

`pr.yml` calcula el costo del plan real de cada raíz afectada con Infracost y lo publica en el
comentario del PR (`../.github/workflows/pr.yml:9`, `:276-286`). Para activarlo:

- la variable de repositorio `GCP_ENABLED = true` (`../.github/workflows/pr.yml:18`);
- el secreto opcional `INFRACOST_API_KEY` (`../.github/workflows/pr.yml:35`,
  [`pipeline.md`](pipeline.md)).

Ese número sale de los recursos del plan y reemplaza los renglones provisionados de este
documento. Los renglones por uso (tráfico, logs, solicitudes) siguen dependiendo de supuestos como
los de la §1. Infracost no ve el nivel gratuito de Logging compartido por los entornos.

## 7. Fuentes

Leídas el 2026-11-23. Cuando la página tiene selector de región, el valor es el de la tabla por
defecto, Iowa (`us-central1`).

- https://cloud.google.com/products/compute/pricing/general-purpose
- https://cloud.google.com/compute/disks-image-pricing
- https://docs.cloud.google.com/compute/docs/sustained-use-discounts
- https://cloud.google.com/kubernetes-engine/pricing
- https://docs.cloud.google.com/kubernetes-engine/docs/concepts/regional-clusters
- https://cloud.google.com/binary-authorization/pricing
- https://cloud.google.com/sql/pricing
- https://cloud.google.com/filestore/pricing
- https://cloud.google.com/storage/pricing
- https://cloud.google.com/vpn/pricing
- https://cloud.google.com/nat/pricing
- https://cloud.google.com/vpc/network-pricing
- https://cloud.google.com/armor/pricing
- https://cloud.google.com/dns/pricing
- https://cloud.google.com/kms/pricing
- https://cloud.google.com/secret-manager/pricing
- https://cloud.google.com/artifact-registry/pricing
- https://cloud.google.com/backup-disaster-recovery/pricing
- https://cloud.google.com/run/pricing
- https://cloud.google.com/products/observability/pricing
- https://cloud.google.com/firewall/pricing. Sirvió para la tarifa de la política jerárquica; la
  de las políticas de red queda por verificar (§3).
- https://cloud.google.com/certificate-manager/pricing
- https://cloud.google.com/products/network-intelligence-center/pricing
- https://cloud.google.com/security-command-center/pricing
- Memorystore for Redis: https://cloud.google.com/memorystore/docs/redis/pricing redirigió a
  una página 404 el 2026-11-23; sus precios son SUPUESTO.

## 8. Qué no se verificó

- **Precios SUPUESTO** (marcados con `*`):
  - todo Memorystore;
  - la réplica de Cloud SQL en `us-east4`;
  - en `us-east4` se usó el precio de `us-central1` para los túneles de VPN, la IP de NAT, la
    bóveda de Backup and DR, el plan de Backup for GKE y el SKU de doble región.
- **Por verificar:** la tarifa de la política de firewall de red. Se usó la de la jerárquica: 1.00
  y 3.00 en qa, 5.00 y 15.00 en prod. Si las políticas de red no cobran por VM, el escenario A baja
  6.00 en *bajo* y 18.00 en *alto*.
- **HIPÓTESIS:**
  - Que un gateway de Cloud NAT `AUTO_ONLY` sin VM no reserve IP (*bajo* = 0, *alto* = 1 IP).
  - Que la regla por defecto de Cloud Armor cuente como regla facturable. Si no, −1.00 USD/mes
    por entorno.
  - Que Backup for GKE cuente 1 o 2 namespaces no del sistema.
  - Que las VM de Cloud Run con salida directa a la VPC no cuenten como VM del gateway de NAT.
  - Que Adaptive Protection de Cloud Armor no tenga cargo en el nivel Standard (la página de
    precios no la menciona).
  - Que el uptime check corra desde 6 ubicaciones. Aun con 7, los tres entornos quedarían bajo el
    millón gratuito del proyecto.
  - Que el volumen de flow logs crezca en proporción al muestreo.
  - Que las etiquetas, la política de denegación de IAM y las políticas de organización no tengan
    cargo. No se buscó su precio.
- **Volúmenes de uso:** todos los GiB, millones de solicitudes y operaciones de las tablas son
  supuestos de esta estimación, no mediciones. Eso incluye los volúmenes de Logging del proyecto
  de la §1.
- **Recálculo:** el 2026-11-24 un script de Python fuera del repositorio recalculó cada renglón
  con `Decimal` (redondeo a centavos, mitad hacia arriba). También recalculó los totales de la §4
  y la §5, los días, las semanas, las pruebas de 2 y 3 días, los días con 300 USD y los
  porcentajes de la §6.1. Sus cifras coinciden con las de este documento.
