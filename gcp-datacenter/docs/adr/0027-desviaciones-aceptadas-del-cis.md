# ADR 0027: Desviaciones aceptadas del CIS GCP Foundation Benchmark

## Estado

Aceptado, 2026-11-23. Enmendado el 2026-11-24 para el proyecto único
([ADR 0029](0029-un-solo-proyecto.md)): 2.1 pasa a `ADMIN_READ` para `allServices` más
`DATA_READ` y `DATA_WRITE` para cinco servicios en los tres entornos; 2.3 y 2.4 apuntan al sink
de proyecto de `stages/1-base`; 3.10 y 4.12 con las rutas nuevas. Las filas 3.9, 4.7, 4.11 y 6.9
no cambian.

Enmendado otra vez el 2026-11-24, con el código final de las ramas de arreglo:

- se agrega la fila 1.1.3 (sin carpetas);
- 1.6 con los roles actuales de las nueve cuentas, todos desde `0-bootstrap`, sin `tagAdmin` y
  con los cuatro roles personalizados;
- 3.8 con el perímetro que crea la persona de `0-bootstrap` (`stages/0-bootstrap/org.tf`);
- 1.7 deja de ser hueco: lo cierran las cuentas de ejecución de `1-base`;
- se quita el límite de la política de firewall jerárquica, que el proyecto único no crea.

Tipo: Desviación (del CIS Google Cloud Platform Foundation Benchmark v5.0, no de la
especificación). El cliente tiene que confirmar que acepta cada desviación de la tabla o pedir
que se construya lo que la cierra.

## Contexto

[`cumplimiento-cis.md`](../cumplimiento-cis.md) mapea las 93 recomendaciones de la v5.0 contra
el código. El 23 nov 2026 se cerraron con código, pruebas o runbook los huecos que no dependían
de una decisión: Cloud Asset (2.14), contactos esenciales (1.17), métricas y alertas de
auditoría (2.5 a 2.12, módulo `audit-alerts`), OS Login de proyecto (4.4), registro de DNS de
`onprem-sim` (2.13) y los pasos de Cloud Identity y consola del runbook 01 (1.1.1, 1.1.2, 1.3,
1.4, 2.2, 2.15, 2.16). El 24 nov 2026 se cerró 1.7: ninguna raíz asigna `serviceAccountUser` ni
`serviceAccountTokenCreator` en el proyecto, porque `1-base` crea las cuentas de ejecución y da
`serviceAccountUser` solo sobre cada cuenta que se adjunta (`stages/1-base/runtime_accounts.tf`,
puntos 131 a 135 de [`pendientes-apply.md`](../pendientes-apply.md)).

Lo que queda abierto choca con decisiones ya tomadas (costo, destroy limpio, un solo proyecto,
ADR anteriores) o necesita un rediseño. Este ADR las junta en un solo lugar para que el cliente
las acepte o las rechace de una vez.

La evaluación de Security Command Center llega a la v3.0 del benchmark
([`cumplimiento-cis.md`](../cumplimiento-cis.md) §1): una desviación de esta tabla puede salir
como hallazgo de SCC aunque esté aceptada.

## Decisión

Se aceptan estas desviaciones. Cada fila dice por qué, qué riesgo queda y qué hace falta para
cumplir.

| CIS 5.0 | Desviación | Por qué | Riesgo que queda | Para cumplir |
|---|---|---|---|---|
| 1.1.3 | Sin carpetas: los tres entornos viven en un solo proyecto. | Pedido del cliente (ADR 0029). Sin organización no hay carpetas. | Los entornos se separan por VPC, nombre `<prefix>-<env>-`, etiqueta `env`, cuenta del pipeline y condiciones de IAM, no por la jerarquía de recursos. Lo que no separan está en el ADR 0029 §9. Sin detector de SCC. | Una organización con carpetas y un proyecto por entorno: el diseño de la rama `archivo/multiproyecto`. Tamaño L. |
| 1.6 | Las cuentas `<prefix>-tf-*` tienen roles cuyo ID contiene "admin", todos dados por `0-bootstrap` (`stages/0-bootstrap/service_accounts.tf`, contrato §6.3): `cloudkms.admin` condicionado, `artifactregistry.admin`, `essentialcontacts.admin`, `pubsub.admin`, `storage.admin` condicionado y `projectIamAdmin` con concesión delegada de `tf-base`; `compute.networkAdmin`, `compute.securityAdmin`, `dns.admin` y `servicenetworking.networksAdmin` de las de red; `backupdr.admin`, `cloudsql.admin`, `container.admin`, `gkebackup.admin`, `redis.admin`, `run.admin`, `compute.instanceAdmin.v1`, `compute.loadBalancerAdmin`, `compute.securityAdmin`, `storage.admin` condicionado y, en dev y qa, `cloudscheduler.admin` de `tf-wl-<env>`; `networkmanagement.admin` de `tf-read`. | El pipeline crea y administra la landing zone; los roles predefinidos más chicos que alcanzan llevan "admin" en el nombre. Donde un rol predefinido traía permisos de etiquetas o de valores, ya hay un rol personalizado (`TfServiceAccountManager`, `TfNetworkTagManager`, `TfSecretContainerAdmin`). | Una identidad del pipeline comprometida tiene permisos amplios, y las de entorno alcanzan sin condición recursos de otros entornos (ADR 0029 §9). Lo acotan WIF por ID de repositorio y solo desde `main` para escribir, la política de denegación del proyecto, las condiciones por nombre, la concesión delegada solo en `tf-base`, y el plan y apply separados con aprobación (ADR 0023 y 0025). `ADMIN_SERVICE_ACCOUNT` las va a marcar. | Roles personalizados mínimos por raíz en `stages/0-bootstrap/custom_roles.tf`. El owner del proyecto es la persona que lo crea, no una cuenta del pipeline. Tamaño L. |
| 2.1 | Registros de acceso a datos (`DATA_READ` y `DATA_WRITE`) solo para `cloudkms`, `iam`, `secretmanager`, `sqladmin` y `storage`; `ADMIN_READ` para `allServices`. Vale para los tres entornos (ADR 0029 §7). | Volumen y costo de Data Access del resto de los servicios (Compute, GKE, Cloud Run, etc.). | Sin registro de lecturas de datos de los demás servicios. HYPOTHESIS: `AUDIT_LOGGING_DISABLED` pide `DATA_READ` y `DATA_WRITE` en `allServices`. | `DATA_READ` y `DATA_WRITE` en `google_project_iam_audit_config.all_services` de `stages/1-base/main.tf` (y la prueba de `stages/1-base/tests/`). Sube el volumen de logs de los tres entornos (`estimacion-de-costos.md`). |
| 2.3 | El sink de proyecto de `1-base` lleva el filtro `logName:"cloudaudit.googleapis.com"` (solo auditoría; valor por defecto de `filter` en `modules/log-export`). | Costo: el destino es un bucket de Cloud Storage con retención larga. | Flow logs, DNS y registros del balanceador quedan solo en el `_Default` del proyecto (retención corta). HYPOTHESIS: el detector `LOG_NOT_EXPORTED` pide un sink sin filtro. | `filter = ""` en `module "audit_logs"` de `stages/1-base/main.tf`, o un segundo sink sin filtro hacia un bucket de Logging. |
| 2.4 | `log_retention_locked = false` por defecto y en el ejemplo. | El bloqueo es irreversible y no se ha probado (pendiente 15). | Alguien con permisos podría acortar la retención. `LOCKED_RETENTION_POLICY_NOT_SET`. | `log_retention_locked = true` en el `terraform.tfvars` real de `stages/1-base`, después de probar el pendiente 15 y de confirmar la retención con cumplimiento. |
| 3.8 | Perímetro de VPC-SC opcional: solo existe con organización y `access_policy_id`, rodea todo el proyecto y siempre está en dry-run (`enforced = false` fijo en `stages/0-bootstrap/org.tf`). Lo crea la persona de la etapa 0; ninguna cuenta del pipeline tiene roles de la política de acceso. En el mapa CIS la fila queda como "Solo con organización" (parcial). | ADR 0029 §1 (no hay proyectos de prod separados; sin organización no hay política de acceso, HYPOTHESIS) y ADR 0009 (dry-run antes de forzar). | En dry-run el perímetro solo registra; sin organización no existe. No puede separar entornos dentro del proyecto. | Con organización: una variable para forzarlo en `stages/0-bootstrap` después de revisar el dry-run (pendientes 4, 5, 17, 18, 53 y 126). Separar entornos con perímetros exige volver a varios proyectos. |
| 3.9 | Las API de Google se alcanzan por Private Google Access y el VIP restringido, no por Private Service Connect. | ADR 0026: el VIP restringido ya aplica VPC-SC y no necesita un endpoint por VPC. | Las API salen por rangos de Google y no por una IP interna de la VPC. Sin detector de SCC. | Endpoint PSC global (`google_compute_global_address` con `purpose = "PRIVATE_SERVICE_CONNECT"` y `google_compute_global_forwarding_rule` con `target = "vpc-sc"`) en los módulos de red, zonas DNS hacia esa IP y un ADR que reemplace al 0026. |
| 3.10 | Flow logs al 100 % solo en prod, el hub y `onprem-sim`; dev y qa muestrean 0.5. | Decidido en este ADR: el valor por defecto de `network-hub`, `network-spoke` y de `flow_log_sampling` en `stages/2-networks/envs/*` pasa a 1.0, y los ejemplos de dev y qa lo bajan a 0.5 por costo. | `VPC_FLOW_LOGS_SETTINGS_NOT_RECOMMENDED` marca las subredes de dev y qa; menos detalle forense fuera de prod. | `flow_log_sampling = 1` en el `terraform.tfvars` de dev y qa (pendiente 62 mide el costo en prod). |
| 4.7 | Discos con CMEK, no con CSEK. | Con CSEK la llave viaja en cada solicitud y Google no la guarda: un MIG que recrea VM solo y los nodos de GKE no la tendrían (HYPOTHESIS). CMEK rota cada 90 días y separa funciones en KMS. | `DISK_CSEK_DISABLED` solo revisa discos con la marca `enforce_customer_supplied_disk_encryption_keys`; el riesgo es de cumplimiento formal. | VM sueltas con CSEK y manejo de llaves fuera de GCP para las cargas críticas; no compatible con el MIG ni con GKE. |
| 4.11 | Sin Confidential Computing (`e2-*` en los ejemplos). | Costo y tipos de máquina: pide N2D (o similares) y `on_host_maintenance = "TERMINATE"`. | Memoria de las VM sin cifrado en uso. `CONFIDENTIAL_COMPUTING_DISABLED` solo escanea N2D. | `confidential_instance_config`, tipo N2D y `TERMINATE` en `modules/compute-mig`; `confidential_nodes` en `modules/gke`. Tamaño M. |
| 4.12 | Parches de SO: GKE con `auto_upgrade` e imagen COS; las VM del MIG sin VM Manager. | El MIG se renueva con la imagen `mig_image`; los parches dependen de publicar imágenes nuevas. | VM del MIG sin parches entre imágenes. Sin detector. | VM Manager: `osconfig.googleapis.com`, `enable-osconfig = "TRUE"` en `modules/compute-mig` y `google_os_config_patch_deployment` en `stages/3-workloads/envs/*`. |
| 6.9 | Cloud SQL sin protección contra borrado en los ejemplos de dev y qa (en prod es obligatoria por validación). | Destroy limpio de dev y qa (pendiente 11). | Un `destroy` o un error borra la base de dev o qa. | `deletion_protection = true` en dev y qa, y que el procedimiento de destroy lo apague antes. |

Además, sobre las métricas de 2.5 a 2.12 (módulo `audit-alerts`):

- **Novena métrica.** Las ocho métricas llevan, palabra por palabra, el filtro que la página de
  hallazgos de SHA dice que revisa cada detector. El filtro de 2.8 solo ve reglas de firewall de
  VPC (`compute.firewalls.*`) y el repositorio usa políticas de firewall de red. En lugar de
  ampliar ese filtro (y arriesgar que el detector deje de reconocerlo), los cambios de políticas
  de firewall van en una métrica aparte, `firewall_policy`, con su alerta. Con el proyecto único
  todas las políticas de firewall son de red y están en el proyecto
  (`stages/2-networks/firewall.tf` y `envs/<env>/firewall.tf`), así que esa métrica las ve todas
  (HYPOTHESIS hasta el pendiente 58).
- **3.12** (IAP solo desde IP de Google) sigue parcial por diseño: la aplicación es pública
  detrás de Cloud Armor (ADR 0005 y 0020); no es una desviación nueva.

## Alternativas consideradas

- **Cerrar todo en código ya.** Rechazada: 1.6, 3.9, 4.11 y 4.12 son rediseños (roles
  personalizados, PSC, tipos de máquina, VM Manager), 1.1.3 contradice el pedido del cliente,
  2.1 y 2.3 suben el costo de logs sin que el cliente lo haya pedido y 2.4 es irreversible sin
  una prueba antes.
- **Silenciar los hallazgos en SCC.** Rechazada como solución: una regla de silencio documenta el
  hallazgo pero no cumple el CIS. Se puede agregar acotada (por ejemplo a `<prefix>-tf-*` para
  1.6) si el cliente acepta la desviación y no quiere el ruido.
- **Flow logs al 100 % también en dev y qa.** Rechazada por costo; queda a una línea de
  `terraform.tfvars`.

## Consecuencias

- Positivas: el mapa CIS distingue lo que falta construir de lo que se decidió no cumplir, y cada
  desviación dice qué cuesta cerrarla.
- Negativas: SCC va a reportar hallazgos de estas filas (1.6, 2.1, 2.4, 3.10 en dev y qa, entre
  otros); la revisión del pendiente 56 tiene que separarlos de los inesperados.
- Primer apply: evaluación del CIS (pendiente 56), alertas de auditoría (58) y costo de flow
  logs al 100 % en prod (62) en [`pendientes-apply.md`](../pendientes-apply.md).
