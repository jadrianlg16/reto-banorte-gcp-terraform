# Estimación de costos mensuales

Estimación del costo de operar la landing zone en Google Cloud, con el dimensionamiento que fija
este repositorio (valores de `terraform.tfvars.example` y valores por defecto de las raíces y los
módulos) y los precios de lista de las páginas oficiales, leídos el **2026-11-23**.

**Estado:** nada se ha aplicado. Esto es una estimación de diseño, no una factura. Cuando el
pipeline tenga acceso a GCP, Infracost calcula el costo del plan real en cada PR (§6.3).

## Resumen

| Escenario | USD/mes (bajo – alto) | USD/día (bajo – alto) |
|---|---:|---:|
| A. Diseño completo (valores de ejemplo de los tres entornos, DR de prod incluida) | 2,450.43 – 3,553.63 | 80.56 – 116.83 |
| B. Despliegue mínimo de prueba (todas las etapas, cómputo apagado salvo Cloud Run) | 621.86 – 666.33 | 20.44 – 21.91 |
| B, variante solo dev (etapas 0 a 2, hub y dev) | 241.13 – 263.36 | 7.93 – 8.66 |

Una prueba de 3 días del escenario B cuesta **61.32 – 65.73 USD**; la variante solo dev,
**23.79 – 25.98 USD** (§5).

## 1. Supuestos

- **Precios de lista on-demand en USD**, leídos el 2026-11-23 en las páginas oficiales de la §7.
  Sin descuentos por compromiso (CUD) ni contratos.
- **Descuentos automáticos:** no se aplica ningún descuento por uso continuo (SUD). Las VM de
  este diseño son E2, y E2 no está entre las series elegibles para SUD
  ([sustained-use-discounts](https://docs.cloud.google.com/compute/docs/sustained-use-discounts)).
  La página de precios de Cloud SQL no ofrece SUD. Sí se aplican los niveles gratuitos que la
  página de cada producto describe como automáticos y que nombra cada renglón: crédito de
  Binary Authorization para GKE, nivel gratuito de Cloud Run, 6 versiones de Secret Manager,
  50 GiB de Logging por proyecto, 1 millón de ejecuciones de uptime check por proyecto, 100
  certificados de Certificate Manager por proyecto y 20 Connectivity Tests por mes. El crédito
  gratuito de GKE (74.40 USD/mes) **no** aplica: solo cubre clústeres zonales o Autopilot, y el
  de este diseño es regional.
- **No se aplican (estimación conservadora):** los 5 GB-mes Always Free de Cloud Storage, los
  0.5 GiB gratuitos de Artifact Registry y cualquier crédito de prueba.
- **730 horas por mes.** Día = mes × 24 / 730, redondeado a centavos; semana y pruebas de N días
  = ese día redondeado × 7 o × N.
- **Todo encendido las 730 horas.** Las tablas de §4 y §5 no restan el apagado fuera de horario
  que los `terraform.tfvars.example` de dev y qa encienden (`off_hours_shutdown`, ADR 0028); su
  ahorro se calcula aparte en la §6.2.
- **Regiones:** `us-central1` (primaria) y `us-east4` (DR); multirregión `us`/`US`
  (`stages/1-org/terraform.tfvars.example:7-8`, `stages/2-security/main.tf:7-8`).
- **Excluidos:** salida a Internet, impuestos y tráfico entre zonas o regiones (replicación de
  Cloud SQL a `us-east4`, peering entre zonas, tráfico IPsec entre los gateways de VPN). En una
  prueba con poco tráfico ese tráfico es pequeño, pero no está en las tablas.
- **Región de las tablas de precios:** las tablas estáticas de las páginas oficiales muestran
  Iowa (`us-central1`); el selector de región carga los demás valores dinámicamente y no se pudo
  leer `us-east4`. Todo precio de `us-east4` que no venga de una tabla sin región es
  **SUPUESTO** (§3).
- **Alertas de Monitoring:** sin costo. La página de precios dice que el cobro de políticas de
  alerta empieza "no antes del 1 de septiembre de 2027".
- **Bajo / alto:** lo provisionado (instancias, discos, túneles, reglas) es igual en los dos.
  Lo que depende del uso tiene dos valores: *bajo* = mínimos del autoescalado y tráfico de
  prueba; *alto* = máximos del autoescalado y tráfico moderado. Las cantidades de cada renglón
  están en la columna de cálculo.
- **Volumen de logs (supuesto):** cada proyecto queda por debajo de los 50 GiB/mes gratuitos,
  salvo, en *alto*, el proyecto de la aplicación de prod con 100 GiB/mes (logs de cargas de GKE,
  Data Access de la carpeta prod y registros del balanceador con Cloud Armor en `VERBOSE`). Los
  VPC Flow Logs son *vended logs*, sin nivel gratuito: 0.4 GiB/mes por spoke en *bajo* y 2, 5 y
  20 GiB/mes (dev, qa, prod) en *alto*.
- **Monitoring y Secret Manager sin cargo con este tamaño:**
  - Uptime checks: 1 por entorno cada 60 s son 43,800 ejecuciones al mes por región de
    verificación. Sin `selected_regions` corre desde todas (`modules/observability/variables.tf:83`;
    6 ubicaciones, HIPÓTESIS): 262,800 por entorno y 788,400 en los tres, bajo el millón gratuito.
  - Managed Service for Prometheus cobra 0.06 USD por millón de muestras, pero el repo no crea
    recursos `PodMonitoring` y GKE solo envía métricas de sistema (`modules/gke/main.tf:127-131`):
    se toma 0.
  - Secret Manager: 3 secretos × 2 ubicaciones = 6 versiones activas, justo las 6 gratuitas por
    cuenta de facturación. Cada versión o rotación adicional cuesta 0.06 USD/mes por ubicación.
- **Redondeo:** cada renglón se redondea a centavos (mitad hacia arriba); los totales suman los
  renglones ya redondeados. Un script aparte recalculó todas las cifras (§8).

## 2. Dimensionamiento tomado del repositorio

Las rutas son relativas a `gcp-datacenter/`. Las raíces `stages/5-workloads/envs/{dev,qa,prod}` y
`stages/3-networks/envs/{dev,qa,prod}` son idénticas salvo `backend.tf` y `terraform.tfvars.example`
(se comprobó con `diff`), así que las citas de código de prod valen para los tres entornos.

### 2.1 Interruptores por entorno (`stages/5-workloads/envs/<env>/terraform.tfvars.example`)

| Variable | dev | qa | prod |
|---|---|---|---|
| `enable_dr` / `dr_active` | false / false (l. 14-15) | false / false (l. 14-15) | true / false (l. 15-16) |
| `enable_gke` | false (l. 18) | false (l. 17) | true (l. 21) |
| `enable_mig` | false (l. 19) | true (l. 18) | true (l. 22) |
| `enable_cloud_run` | true (l. 20) | true (l. 19) | true (l. 23) |
| `enable_filestore` | false (l. 21) | false (l. 20) | true (l. 24) |
| `enable_memorystore` | false (l. 22) | true (l. 21) | true (l. 25) |
| `enable_internal_lb` | false (l. 23) | false (l. 22) | true (l. 26) |
| `enable_backup` | true (l. 24) | true (l. 23) | true (l. 27) |
| Spoke: `enable_dr` (`stages/3-networks/envs/<env>/terraform.tfvars.example`) | false (l. 14) | false (l. 14) | true (l. 14) |

Hub (`stages/3-networks/terraform.tfvars.example`): `enable_vpn_dr = true` (l. 28),
`simulate_onprem = true` (l. 39), `enable_interconnect = false` (l. 45).

### 2.2 Tamaños

| Pieza | Tamaño | Fuente |
|---|---|---|
| GKE | Clúster regional (location = región) | `stages/5-workloads/envs/prod/compute.tf:13`, `modules/gke/main.tf:31` |
| GKE: nodos | Pool `general`, e2-standard-4, mín. 1 y máx. 3 **por zona** | `stages/5-workloads/envs/prod/terraform.tfvars.example:40-46`, `stages/5-workloads/envs/prod/variables.tf:243` |
| GKE: zonas | 3 (sin `node_locations`, el clúster regional usa tres zonas) | `modules/gke/main.tf:206`; [regional-clusters](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/regional-clusters) |
| GKE: disco de nodo | 100 GB pd-balanced | `stages/5-workloads/envs/prod/variables.tf:248-249` |
| GKE: Binary Authorization | Aplicada en el clúster | `modules/gke/main.tf:88-90` |
| MIG | e2-standard-2; qa 1 a 3 VM, prod 2 a 6 VM; regional | `stages/5-workloads/envs/qa/terraform.tfvars.example:27-29`, `stages/5-workloads/envs/prod/terraform.tfvars.example:55-57`, `modules/compute-mig/main.tf:138` |
| MIG: disco | 50 GB pd-balanced | `modules/compute-mig/variables.tf:201`, `:212` |
| Cloud Run | 1 vCPU, 512 MiB, mín. 0 instancias, máx. 10 | `modules/cloud-run/variables.tf:162`, `:173`, `:184`; `stages/5-workloads/envs/prod/variables.tf:482` |
| Cloud SQL | Edición ENTERPRISE, PostgreSQL 16, siempre se crea | `modules/cloud-sql/variables.tf:126`, `stages/5-workloads/envs/prod/data.tf:5` |
| Cloud SQL: tipo | dev `db-custom-1-3840` (1 vCPU, 3.75 GiB); qa y prod `db-custom-2-7680` (2 vCPU, 7.5 GiB) | `stages/5-workloads/envs/dev/terraform.tfvars.example:33`, `…/qa/…:35`, `…/prod/…:63` |
| Cloud SQL: HA | ZONAL fuera de prod, REGIONAL (HA) en prod | `modules/cloud-sql/main.tf:6` |
| Cloud SQL: disco | 20 GB PD_SSD con crecimiento automático | `modules/cloud-sql/main.tf:78-80`, `modules/cloud-sql/variables.tf:267` |
| Cloud SQL: réplica de DR | Con `enable_dr`, en `dr_region`, mismo tipo, disco y disponibilidad (REGIONAL en prod) | `modules/cloud-sql/main.tf:232`, `:246-250` |
| Memorystore | 5 GB; BASIC fuera de prod, STANDARD_HA en prod | `…/qa/terraform.tfvars.example:39`, `…/prod/terraform.tfvars.example:67`, `modules/memorystore/main.tf:5` |
| Filestore | REGIONAL, 1024 GiB (prod) | `stages/5-workloads/envs/prod/terraform.tfvars.example:68-69` |
| Cloud Storage: bucket de la app | Regional sin DR; doble región `us-central1`+`us-east4` con turbo replication con `enable_dr`; STANDARD | `stages/5-workloads/envs/prod/data.tf:114-118`, `modules/storage/variables.tf:113` |
| Cloud Storage: estado | Multirregión US | `stages/0-bootstrap/terraform.tfvars.example:17`, `stages/0-bootstrap/main.tf:130-135` |
| Cloud Storage: logs de auditoría | `us-central1`, STANDARD, retención de 365 días | `stages/1-org/main.tf:86-103`, `stages/1-org/terraform.tfvars.example:23`, `modules/log-export/variables.tf:83` |
| HA VPN | 4 instancias de 2 túneles = **8 túneles**: hub primaria, onprem-sim primaria, hub de DR y onprem-sim de DR | `stages/3-networks/vpn.tf:96-122`, `:129-153`, `:185-207`, `:211-233`; 2 sesiones BGP por VPN (`stages/3-networks/vpn.tf:42-49`), un túnel por sesión (`modules/hybrid-connectivity/main.tf:63-64`) |
| Cloud Router | Hub: uno por región; onprem-sim: primaria y DR | `modules/network-hub/main.tf:48-49`, `stages/3-networks/vpn.tf:171` |
| Cloud NAT | Uno por spoke y región activa, `AUTO_ONLY`: dev 1, qa 1, prod 2 (con DR) = 4 | `modules/network-spoke/main.tf:6-9`, `:195-229`, `:211` |
| Balanceador externo | Uno por entorno (existe si hay algún backend; Cloud Run está encendido en los tres), 2 reglas de reenvío globales (443 y 80) | `stages/5-workloads/envs/prod/load_balancing.tf:86`, `:178-180`; `modules/load-balancer/main.tf:255`, `:290` |
| Balanceador interno | Uno por región con cómputo (solo la primaria sin `dr_active`), 2 reglas `INTERNAL_MANAGED` (443 y 80) | `stages/5-workloads/envs/prod/load_balancing.tf:204-206`; `modules/load-balancer/main.tf:447`, `:492` |
| Cloud Armor | 1 política por balanceador externo, 12 reglas: 9 OWASP, cve-canary, límite de tasa y regla por defecto | `stages/5-workloads/envs/prod/load_balancing.tf:166-168`; `modules/cloud-armor/variables.tf:56-65`; `modules/cloud-armor/main.tf:44`, `:58`, `:85` |
| Cloud KMS | 72 llaves SOFTWARE con rotación de 90 días: 69 de la etapa 2 (3 entornos × [2 regiones × 10 usos + multirregión × 3 usos]), 2 de la etapa 1 y 1 de la etapa 0 | `stages/2-security/main.tf:8-14`, `:21-33`; `stages/1-org/main.tf:77-80`; `stages/0-bootstrap/main.tf:102-104`; `modules/kms/variables.tf:66`; `stages/2-security/terraform.tfvars.example:18` |
| Secret Manager | 1 secreto por entorno con réplica en 2 regiones = 6 versiones activas cuando se carguen los valores; el secreto de la VPN simulada no usa Secret Manager | `stages/2-security/terraform.tfvars.example:12-16`, `stages/2-security/main.tf:83-86`, `stages/3-networks/vpn.tf:76-81` |
| Artifact Registry | 1 repositorio Docker multirregional `us` por entorno | `stages/4-projects/envs/prod/artifacts.tf:43-60`, `stages/4-projects/envs/prod/terraform.tfvars.example:23` |
| Backup and DR | Bóveda en `dr_region` y plan diario de Cloud SQL (30 días) en cada entorno | `stages/5-workloads/envs/prod/operations.tf:36-67`, `modules/backup-dr/main.tf:23-25` |
| Backup for GKE | Solo con `enable_backup`, `enable_gke` y `enable_dr` (prod); plan en `dr_region`, todos los namespaces | `stages/5-workloads/envs/prod/operations.tf:30`, `modules/backup-dr/main.tf:88-92`, `:107-109` |
| Cloud DNS | 19 zonas: 1 de reenvío en el hub + 6 por spoke; registro de consultas encendido | `stages/3-networks/dns.tf:23-37`, `stages/3-networks/envs/prod/dns.tf:58-96` |
| Logging | Sink agregado de auditoría hacia el bucket de logs; Data Access en la carpeta prod y en el proyecto semilla; GKE con logs de sistema y de cargas; flow logs con muestreo 0.5; NAT solo errores | `modules/org/variables.tf:89`, `stages/1-org/main.tf:123-136`, `stages/0-bootstrap/main.tf:74-87`, `modules/gke/main.tf:123-125`, `stages/3-networks/envs/prod/terraform.tfvars.example:37`, `modules/network-spoke/main.tf:225-228` |
| Monitoring | Managed Prometheus en GKE; 1 uptime check cada 60 s; 9 condiciones de alerta por entorno | `modules/gke/main.tf:127-131`, `modules/observability/variables.tf:81`, `modules/observability/main.tf:119`, `:163`, `:214`, `:254`, `:323`, `:338` |
| SCC | Solo la notificación de hallazgos; la activación (Standard) es manual | `stages/1-org/main.tf:138-194` |
| Política jerárquica de firewall | Asociada a la organización (se cobra por VM) | `stages/3-networks/firewall.tf:82` |
| Presupuesto | `budget_amount = 1000` (moneda de la cuenta de facturación) | `stages/1-org/terraform.tfvars.example:25` |

## 3. Precios unitarios

`*` = **SUPUESTO**: valor no leído en la página oficial (motivo en la columna Nota).

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
| Cloud Logging | 0.50 USD/GiB sobre 50 GiB/proyecto/mes | [observability/pricing](https://cloud.google.com/products/observability/pricing) | Retención > 30 días: 0.01 USD/GiB-mes (no aplica aquí) |
| Uptime checks / alertas | 0.30 USD por mil ejecuciones sobre 1 M/proyecto; alertas sin cargo hasta septiembre de 2027 | [observability/pricing](https://cloud.google.com/products/observability/pricing) | |
| Política jerárquica de firewall | 0.001369863 USD/VM-h (≤ 500 atributos); sin cargo si no aplica a VM | [firewall/pricing](https://cloud.google.com/firewall/pricing) | |
| Certificate Manager | Primeros 100 certificados por proyecto gratis | [certificate-manager/pricing](https://cloud.google.com/certificate-manager/pricing) | |
| Connectivity Tests | 20 gratis por mes; 0.15 USD por prueba adicional | [network-intelligence-center/pricing](https://cloud.google.com/products/network-intelligence-center/pricing) | |
| SCC Standard | Sin cargo | [security-command-center/pricing](https://cloud.google.com/security-command-center/pricing) | |

## 4. Escenario A: diseño completo

Valores de ejemplo de los tres entornos, `enable_vpn_dr = true` y DR de datos en prod
(`dr_active = false`: sin cómputo en `us-east4`).

| Entorno | USD/mes bajo | USD/mes alto |
|---|---:|---:|
| Común (hub y proyectos de `common`) | 151.03 | 159.11 |
| Semilla (bootstrap) | 0.06 | 0.09 |
| dev | 90.04 | 104.16 |
| qa | 297.49 | 417.59 |
| prod (región primaria) | 1,526.99 | 2,474.36 |
| Extras de DR de prod | 384.82 | 398.32 |
| **Total** | **2,450.43** | **3,553.63** |
| **Por día** | **80.56** | **116.83** |

El total supera el presupuesto de ejemplo de 1000 (`stages/1-org/terraform.tfvars.example:25`).

`*` en un renglón = usa un precio SUPUESTO de la §3. Los precios de las columnas de cálculo están
en USD por hora (× 730) o por unidad.

### 4.1 Común (hub y proyectos de `common`)

| Componente | Cálculo bajo | Bajo | Cálculo alto | Alto |
|---|---|---:|---|---:|
| HA VPN primaria: 2 túneles del hub + 2 de onprem-sim (us-central1) | 4 túneles × 0.05 × 730 | 146.00 | igual | 146.00 |
| Cloud Router (hub y onprem-sim) | sin cargo | 0.00 | igual | 0.00 |
| Cloud DNS: zona de reenvío del hub | 1 zona × 0.000273973 × 730 | 0.20 | igual | 0.20 |
| Cloud DNS: consultas del hub | 0.5 M × 0.40 | 0.20 | 5 M × 0.40 | 2.00 |
| Cloud KMS: 71 versiones activas (69 de la etapa 2 + 2 de la etapa 1) | 71 versiones × 0.000082192 × 730 | 4.26 | igual | 4.26 |
| Cloud KMS: operaciones | 10 bloques de 10 mil ops × 0.03 | 0.30 | 200 bloques de 10 mil ops × 0.03 | 6.00 |
| Bucket de logs de auditoría (us-central1) | 1 GiB × 0.000027397 × 730 | 0.02 | 20 GiB × 0.000027397 × 730 | 0.40 |
| Flow logs del hub y onprem-sim (vended) | 0.2 GiB × 0.25 | 0.05 | 1 GiB × 0.25 | 0.25 |
| SCC Standard, Pub/Sub de hallazgos, presupuesto, VPC-SC, IAM, WIF | sin cargo / despreciable | 0.00 | igual | 0.00 |
| **Total** | | **151.03** | | **159.11** |

### 4.2 Semilla (bootstrap)

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
| VPC Flow Logs (vended) | 0.4 GiB × 0.25 | 0.10 | 2 GiB × 0.25 | 0.50 |
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
| VPC Flow Logs (vended) | 0.4 GiB × 0.25 | 0.10 | 5 GiB × 0.25 | 1.25 |
| Política jerárquica de firewall (por VM) | 1 VM × 0.001369863 × 730 | 1.00 | 3 VM × 0.001369863 × 730 | 3.00 |
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
| VPC Flow Logs (vended) | 0.4 GiB × 0.25 | 0.10 | 20 GiB × 0.25 | 5.00 |
| Política jerárquica de firewall (por VM) | 5 VM × 0.001369863 × 730 | 5.00 | 15 VM × 0.001369863 × 730 | 15.00 |
| Cloud Logging (proyecto de la app, sobre 50 GiB gratis) | < 50 GiB | 0.00 | (100 − 50) GiB × 0.50 | 25.00 |
| Bucket de la aplicación (doble región, turbo replication)\* | 1 GiB × 0.000030137 × 730 × 2 regiones + 1 GiB escrito × 0.04 | 0.08 | 50 GiB × 0.000030137 × 730 × 2 regiones + 50 GiB escritos × 0.04 | 4.20 |
| Artifact Registry | 0.5 GiB × 0.000136986 × 730 | 0.05 | 5 GiB × 0.000136986 × 730 | 0.50 |
| Backup and DR de Cloud SQL (bóveda en us-east4)\* | 2 GiB × 0.000061644 × 730 + 2 GiB × 0.000068493 × 730 + 2 GiB × 0.02 | 0.23 | 20 GiB × 0.000061644 × 730 + 20 GiB × 0.000068493 × 730 + 20 GiB × 0.02 | 2.30 |
| **Total** | | **1,526.99** | | **2,474.36** |

### 4.6 Extras de DR de prod

Lo que existe solo por `enable_vpn_dr = true` (hub) y `enable_dr = true` (spoke y cargas de
prod), sin conmutar. Con `dr_active = true` se suman además GKE, MIG, Cloud Run y el balanceador
interno en `us-east4` (no estimado: es el estado durante un incidente).

| Componente | Cálculo bajo | Bajo | Cálculo alto | Alto |
|---|---|---:|---|---:|
| HA VPN de DR: 2 túneles del hub + 2 de onprem-sim (us-east4)\* | 4 túneles × 0.05 × 730 | 146.00 | igual | 146.00 |
| Réplica de Cloud SQL en us-east4, REGIONAL (HA)\* | 2 vCPU × 0.0930 × 730 + 7.5 GiB × 0.0158 × 730 + 20 GiB-mes × 0.374 | 229.77 | igual | 229.77 |
| Cloud NAT de DR (us-east4), sin VM\* | 0 VM, 0 IP | 0.00 | 1 IP × 0.005 × 730 | 3.65 |
| Backup for GKE: gestión (plan en us-east4)\* | 1 namespace × 0.012328767 × 730 | 9.00 | 2 namespaces × 0.012328767 × 730 | 18.00 |
| Backup for GKE: almacenamiento\* | 1 GiB × 0.000061644 × 730 | 0.05 | 20 GiB × 0.000061644 × 730 | 0.90 |
| Certificado interno de DR (Certificate Manager) | primeros 100 gratis | 0.00 | igual | 0.00 |
| **Total** | | **384.82** | | **398.32** |

## 5. Escenario B: despliegue mínimo de prueba

Todas las etapas aplicadas con estos cambios sobre los valores de ejemplo:

- `stages/5-workloads/envs/<env>` (los tres): `enable_dr = false`, `enable_gke = false`,
  `enable_mig = false`, `enable_filestore = false`, `enable_memorystore = false`,
  `enable_internal_lb = false`, `enable_cloud_run = true`; `enable_backup` sigue en `true`.
  Cloud SQL se crea siempre (`stages/5-workloads/envs/prod/data.tf:5`) y en prod sigue siendo
  REGIONAL: el módulo lo impone (`modules/cloud-sql/main.tf:6`, `modules/cloud-sql/variables.tf:154-157`).
- `stages/3-networks/envs/prod`: `enable_dr = false` (un solo Cloud NAT en prod).
- Hub: `enable_vpn_dr = false` (quedan los 4 túneles de la VPN primaria; no hay interruptor para
  quitarlos mientras `simulate_onprem = true`).

| Entorno | USD/mes bajo | USD/mes alto | Tabla |
|---|---:|---:|---|
| Común (hub sin VPN de DR) | 151.03 | 159.11 | Igual a la §4.1 |
| Semilla (bootstrap) | 0.06 | 0.09 | Igual a la §4.2 |
| dev | 90.04 | 104.16 | Igual a la §4.3 |
| qa | 139.35 | 150.47 | §5.1 |
| prod | 241.38 | 252.50 | §5.2 |
| **Total** | **621.86** | **666.33** | |

| Duración | Escenario B completo | Variante solo dev |
|---|---:|---:|
| Mes | 621.86 – 666.33 | 241.13 – 263.36 |
| Día | **20.44 – 21.91** | **7.93 – 8.66** |
| Semana | 143.08 – 153.37 | 55.51 – 60.62 |
| Prueba de 2 días | 40.88 – 43.82 | 15.86 – 17.32 |
| Prueba de 3 días | 61.32 – 65.73 | 23.79 – 25.98 |
| Días que cubren 300 USD de crédito | 14.7 – 13.7 | 37.8 – 34.6 |

La variante solo dev aplica las etapas 0 a 2, el hub (`stages/3-networks`) y solo
`envs/dev` de las etapas 3 a 5: común + semilla + dev. La etapa 2 sigue creando las 69 llaves de
los tres entornos (4.26 USD/mes en la §4.1). Es también la variante más fácil de apagar: dev usa
`deletion_policy = "DELETE"` (`stages/4-projects/envs/dev/terraform.tfvars.example:18`) y
`deletion_protection = false` (`stages/5-workloads/envs/dev/terraform.tfvars.example:25`).

Los cargos por hora se prorratean: un recurso que existe N horas cuesta N/730 de su renglón
mensual (Cloud DNS y Cloud KMS lo dicen así en sus páginas). En una prueba de pocos días casi
todo el costo es fijo: Cloud SQL, los 4 túneles de VPN (4.80 USD/día) y balanceador con Cloud
Armor (1.16 USD/día por entorno).

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
| VPC Flow Logs (vended) | 0.4 GiB × 0.25 | 0.10 | 2 GiB × 0.25 | 0.50 |
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
| VPC Flow Logs (vended) | 0.4 GiB × 0.25 | 0.10 | 2 GiB × 0.25 | 0.50 |
| Bucket de la aplicación (regional, sin DR) | 1 GiB × 0.000027397 × 730 | 0.02 | 50 GiB × 0.000027397 × 730 | 1.00 |
| Artifact Registry | 0.5 GiB × 0.000136986 × 730 | 0.05 | 5 GiB × 0.000136986 × 730 | 0.50 |
| Backup and DR de Cloud SQL (bóveda en us-east4)\* | 2 GiB × 0.000061644 × 730 + 2 GiB × 0.000068493 × 730 + 2 GiB × 0.02 | 0.23 | 20 GiB × 0.000061644 × 730 + 20 GiB × 0.000068493 × 730 + 20 GiB × 0.02 | 2.30 |
| **Total** | | **241.38** | | **252.50** |

## 6. Mayores costos y cómo reducirlos

### 6.1 Mayores costos (escenario A, columna baja)

| Categoría | USD/mes | % del total |
|---|---:|---:|
| Cloud SQL (dev, qa, prod HA y réplica HA en us-east4\*) | 588.55 | 24.0 % |
| Filestore REGIONAL 1024 GiB | 460.80 | 18.8 % |
| GKE (cuota, 3 nodos, discos, Backup for GKE) | 405.56 | 16.6 % |
| Memorystore (qa BASIC y prod STANDARD_HA)\* | 295.65 | 12.1 % |
| HA VPN (8 túneles; 4 de ellos de onprem-sim) | 292.00 | 11.9 % |
| MIG (qa 1 VM, prod 2 VM) | 161.76 | 6.6 % |
| Balanceador interno de prod | 109.54 | 4.5 % |
| Balanceador externo + Cloud Armor (3 entornos) | 106.32 | 4.3 % |

En el escenario B el costo es Cloud SQL (358.78 USD/mes, 58 %), la VPN primaria (146.00, 23 %)
y balanceador externo con Cloud Armor en los tres entornos (106.32, 17 %).

### 6.2 Palancas

Ahorros mensuales calculados con los precios de la §3. Las que piden cambiar código, y no solo
variables, se marcan así: son propuestas, no cambios hechos.

- **Filestore.** `filestore_capacity_gb = 100` con tier REGIONAL (el módulo admite 100 a 10239,
  `modules/filestore/variables.tf:97-99`): 100 × 0.000616438 × 730 = 45.00 en vez de 460.80
  (−415.80). ZONAL de 1024 GiB a 0.000342466 USD/GiB-h: 256.00 (−204.80). Para pruebas,
  `enable_filestore = false`.
- **GKE.** `node_locations` con una sola zona en `gke_node_pools` deja 1 nodo en vez de 3:
  −195.67 en nodos y −20.00 en discos. La cuota de 73.00 sigue mientras el clúster sea regional;
  un clúster zonal entraría en el crédito de 74.40 (cambio de código en
  `stages/5-workloads/envs/prod/compute.tf:13`).
- **Cloud SQL.** El HA fuera de prod ya está apagado (ZONAL en dev y qa). En prod es obligatorio
  por diseño. Bajar el tipo: qa con `db-custom-1-3840` cuesta 52.71 (−49.31); prod HA con
  `db-custom-1-3840`, 105.42 (−98.63). La réplica de DR hereda REGIONAL
  (`modules/cloud-sql/main.tf:248`); como ZONAL costaría cerca de la mitad (114.88\*, cambio de
  código).
- **Apagado fuera de horario de dev y qa** (`off_hours_shutdown`, ya en los ejemplos de dev y
  qa; ADR 0028). Horas apagadas por semana: H = 168 − días × (apagado − encendido); con 5 días
  de 07:00 a 20:00, H = 168 − 65 = 103 (61.3 %), o sea 730 × 103 / 168 = 447.56 h al mes. Se deja
  de cobrar la vCPU y la memoria de Cloud SQL (el almacenamiento y la IP siguen) y las VM y sus
  discos del MIG (el grupo baja a 0):
  - Cloud SQL dev: (1 × 0.0413 + 3.75 × 0.007) × 447.56 = −30.23;
  - Cloud SQL qa: (2 × 0.0413 + 7.5 × 0.007) × 447.56 = −60.47;
  - MIG de qa (1 VM y 50 GiB): (0.06701142 + 50 × 0.000136986) × 447.56 = −33.06; además salen
    de noche los cargos por VM de Cloud NAT y de la política jerárquica (menos de 1.25).
  - Total frente a la columna baja del escenario A: −123.76 USD/mes. En el escenario B (sin MIG),
    −90.70.
  - Se suman los trabajos de Cloud Scheduler: 2 por instancia de Cloud SQL (4 en dev y qa) y 4
    por pool de GKE, con 3 gratis por cuenta de facturación, al precio por trabajo al mes de
    [scheduler/pricing](https://cloud.google.com/scheduler/pricing) (no se pudo leer el monto el
    2026-11-23; no está en esta suma).
  - Con el apagado, el MIG de qa tiene `mig_min_replicas` VM fijas en el horario (sin
    autoescalado por CPU): la columna alta de qa ya no aplica a ese renglón. Con GKE en dev o qa,
    cada pool ahorra al menos (precio por hora del nodo + su disco) × zonas × `min_node_count` ×
    447.56 (la cuota del clúster sigue).
- **VPN del on-premises simulado.** Cada VPN son 2 túneles del hub más 2 de onprem-sim:
  146.00 USD/mes (4.80 USD/día) por región. `enable_vpn_dr = false` quita 146.00. Con
  on-premises real (`simulate_onprem = false`) desaparecen los 4 túneles de onprem-sim (−146.00
  si sigue la de DR). La VPN primaria no tiene interruptor: es costo fijo del hub mientras exista.
- **Memorystore.** `enable_memorystore = false` en qa ahorra 98.55\*; en prod, 197.10\*.
- **Balanceador interno.** Cada regla `INTERNAL_MANAGED` suma 3 proxies: la de redirección del
  puerto 80 duplica el cargo (109.50 en vez de 54.75; cambio de código en
  `modules/load-balancer/main.tf:492`). Para pruebas, `enable_internal_lb = false`.
- **Balanceador externo y Cloud Armor:** 35.25 USD/mes fijos por entorno (18.25 + 17.00). Probar
  solo dev evita los de qa y prod.
- **Cloud NAT.** Pesa poco (13.70 USD/mes en el escenario A): 0.0014 USD/h por VM y 3.65 USD/mes
  por IP. Crece con las VM de GKE y el MIG, no con los gateways vacíos
  ([ADR 0004](adr/0004-cloud-nat-en-cada-spoke.md)).
- **Apagar después de la prueba.** `terraform destroy` de la etapa 5 a la 0 detiene casi todos
  los cargos por hora. Lo que sigue cobrando:
  - Las versiones de KMS programadas para destrucción siguen activas 30 días
    (`modules/kms/variables.tf:67`): hasta 72 × 0.06 = 4.32 USD. Las llaves y los llaveros no se
    borran en Cloud KMS; solo se destruyen sus versiones.
  - El bucket de logs de auditoría guarda los objetos 365 días por su retención: centavos.
  - El bucket de estado tiene `prevent_destroy` (`stages/0-bootstrap/main.tf:181-183`).

  Prod no se desmonta solo con `destroy`: tiene `deletion_protection` obligatoria
  (`stages/5-workloads/envs/prod/variables.tf:173-183`) y `deletion_policy = "PREVENT"`
  (`stages/4-projects/envs/prod/terraform.tfvars.example:18`).
- **Presupuesto.** Ajustar `budget_amount` (`stages/1-org/terraform.tfvars.example:25`) al
  crédito disponible para recibir los avisos de umbral (`stages/1-org/main.tf:198-231`). El
  presupuesto avisa; no corta el gasto.

### 6.3 Infracost en el pipeline

`pr.yml` calcula el costo del plan real de cada raíz afectada con Infracost y lo publica en el
comentario del PR (`../.github/workflows/pr.yml:8`, `:261-271`). Se activa con la variable de
repositorio `GCP_ENABLED = true` y el secreto opcional `INFRACOST_API_KEY`
(`../.github/workflows/pr.yml:26`, [`pipeline.md`](pipeline.md)). Ese número sale de los recursos
del plan y reemplaza los renglones provisionados de este documento. Los renglones por uso
(tráfico, logs, solicitudes) siguen dependiendo de supuestos como los de la §1.

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
- https://cloud.google.com/firewall/pricing
- https://cloud.google.com/certificate-manager/pricing
- https://cloud.google.com/products/network-intelligence-center/pricing
- https://cloud.google.com/security-command-center/pricing
- Memorystore for Redis: https://cloud.google.com/memorystore/docs/redis/pricing redirigió a
  una página 404 el 2026-11-23; sus precios son SUPUESTO.

## 8. Qué no se verificó

- **Precios SUPUESTO** (marcados con `*`): todo Memorystore; la réplica de Cloud SQL en
  `us-east4`; los túneles de VPN, la IP de NAT, la bóveda de Backup and DR, el plan de Backup for
  GKE y el SKU de doble región en `us-east4` (se usó el precio de `us-central1`).
- **HIPÓTESIS:**
  - Que un gateway de Cloud NAT `AUTO_ONLY` sin VM no reserve IP (*bajo* = 0, *alto* = 1 IP).
  - Que la regla por defecto de Cloud Armor cuente como regla facturable (si no, −1.00 USD/mes
    por entorno).
  - Que Backup for GKE cuente 1 o 2 namespaces no del sistema.
  - Que las VM de Cloud Run con salida directa a la VPC no cuenten como VM del gateway de NAT.
  - Que Adaptive Protection de Cloud Armor no tenga cargo en el nivel Standard (la página de
    precios no la menciona).
  - Que el uptime check corra desde 6 ubicaciones (aun con 7 quedaría bajo el millón gratuito).
- **Volúmenes de uso:** todos los GiB, millones de solicitudes y operaciones de las tablas son
  supuestos de esta estimación, no mediciones.
- **Recálculo:** un script de Python fuera del repositorio recalculó cada renglón con `Decimal`
  (redondeo a centavos, mitad hacia arriba) y los totales de la §4 y la §5. Además se comprobó
  que las cifras de este documento coinciden con las de ese script.
