# Etapa `3-workloads/envs/<env>`

Cargas de trabajo de un entorno en el proyecto único (ADR 0029): lo que antes hacía la etapa 5.
Todo va en `project_id`, sobre la VPC del spoke del entorno (`2-networks/<env>`): sin proyectos
de servicio ni Shared VPC. Las tres raíces `envs/dev`, `envs/qa` y `envs/prod` son idénticas
salvo `backend.tf` (prefijo `3-workloads/<env>`) y `terraform.tfvars.example`; las diferencias
entre entornos llegan solo por variables.

Lo que existe una vez por proyecto no está aquí (ADR 0029 §4): APIs, metadatos del proyecto,
política de Binary Authorization, repositorios de Artifact Registry, llaves KMS, contenedores
de secretos, las cuentas de ejecución de los entornos y sus permisos, los permisos de los agentes
de servicio, la auditoría y sus alertas, y el perímetro de VPC-SC son de `1-base` (el rol
personalizado del apagado, de `0-bootstrap`). Esta raíz no crea cuentas de servicio ni asigna
roles de proyecto o de cuentas de servicio.

## Qué crea

Nombres con `prefix = "bnt"`, `application = "app"` y región primaria `us-central1` (§4.2).
Todos empiezan con `<prefix>-<env>-`.

| Carga | Interruptor | Módulo | Nombre | Notas |
|---|---|---|---|---|
| GKE | `enable_gke` | `gke` | `bnt-<env>-app-gke` (`bnt-<env>-app-gke-dr` en DR) | nombre por convención (ADR 0029 §4: lo usa la regla por clúster de Binary Authorization de `1-base`); subred `app`, rangos secundarios `pods`/`services`, plano de control en `reserved_cidrs["gke_master"]` del spoke, llave `gke`, nodos con la cuenta `gke-nodes` y la etiqueta segura `lb_backend`; regional en prod; el enlace de Workload Identity de `<app>-<env>`/`gke_workload_ksa_name` hacia la cuenta `workload` lo crea `1-base` |
| MIG | `enable_mig` | `compute-mig` | `bnt-<env>-app-mig-usc1` | subred `app`, llave `compute`, cuenta `mig`, etiquetas seguras `lb_backend` e `iap_ssh` (`resource_manager_tags`), imagen endurecida por variable (`mig_image`, sin valor por defecto) |
| Cloud Run | `enable_cloud_run` | `cloud-run` | `bnt-<env>-app-run-usc1` | salida directa a la VPC por la subred `run`, llave `run`, cuenta `run`, `public_via_load_balancer = true` (ADR 0020) |
| Cloud SQL | siempre | `cloud-sql` | `bnt-<env>-data-<sql_instance_name>-usc1` | PostgreSQL, IP privada en el rango de PSA, llave `sql`, usuarios IAM = cuentas de ejecución con cómputo encendido (`workload` con GKE, `run` con Cloud Run, `mig` con el MIG; ADR 0015), sin roles de proyecto (`grant_iam_login_roles = false`: los da `1-base`); con `enable_backup`, horario y retención los define el plan de Backup and DR; con `enable_dr`, réplica `bnt-<env>-data-<sql_instance_name>-use4` con la llave `sql` de DR |
| Memorystore | `enable_memorystore` | `memorystore` | `bnt-<env>-data-redis-usc1` | PSA, llave `redis`, STANDARD_HA en prod |
| Filestore | `enable_filestore` | `filestore` | `bnt-<env>-data-nfs-usc1` | PSA, llave `filestore`, tier por variable |
| Cloud Storage | siempre | `storage` | `bnt-<env>-data-app-usc1` | llave `storage`; con `enable_dr`, doble región `bnt-<env>-data-app-usc1-use4` en `US` con turbo replication y la llave `storage` de la multirregión `us` |
| Cloud Armor | con el balanceador externo | `cloud-armor` | `bnt-<env>-app-app-armor` | OWASP (SQLi, XSS y demás), límite de tasa |
| Balanceador externo | hay al menos un backend | `load-balancer` (`external`) | `bnt-<env>-app-app-xlb-*` | HTTPS global, certificado administrado para `domain_names`, redirección de HTTP, Cloud Armor (ADR 0005) |
| Balanceador interno | `enable_internal_lb` | `load-balancer` (`internal`) | `bnt-<env>-app-app-ilb-<usc1\|use4>-*` | uno por región con cómputo (con `dr_active` se agrega el de `dr_region`), IP en la subred `app` de su región, subred proxy-only del spoke, acceso global; el certificado de Certificate Manager para `internal_domain_names` y sus autorizaciones DNS los crea la raíz (`load_balancing.tf`) por región: la primaria y, con `enable_dr`, también `dr_region` aunque `dr_active` sea false |
| Observabilidad | siempre | `observability` | — | canales para `notification_emails` más los `notification_channel_ids` de `1-base`, verificación de disponibilidad del primer dominio, alertas, tablero y SLO de 99.9 % sobre el mapa de URL del balanceador externo; filtros limitados al entorno (abajo) |
| Respaldo | `enable_backup` (true) | `backup-dr` | `bnt-<env>-bkp-vault-use4` | bóveda en `dr_region`, plan diario de Cloud SQL con 30 días de retención y 7 días de registros (ventana de PITR); con `enable_gke` y `enable_dr`, plan de Backup for GKE del clúster primario en `dr_region` con la llave `backup` de DR |
| Apagado fuera de horario | `off_hours_shutdown.enabled` (dev y qa) | `off-hours-shutdown` | trabajos `bnt-<env>-ops-<trabajo>-usc1` con la cuenta `bnt-<env>-app-sched` de `1-base` | ADR 0028; sección propia abajo |

Las llaves vienen de `kms_key_ids[<env>]` de `1-base`; las cuentas de ejecución, de
`runtime_service_accounts[<env>][<application>]`, y el repositorio de imágenes, de
`artifact_registry_repositories[<env>][<application>]`. Todo recurso etiquetable lleva
`local.labels` (§4.3).

### Cuentas de ejecución (`service_accounts.tf`)

Las crea `1-base` (`stages/1-base/runtime_accounts.tf`) con sus permisos: roles mínimos de
telemetría en el proyecto, lectura de los secretos del entorno (`workload` y `run`), lectura del
repositorio del entorno (`gke-nodes` y `mig`), `cloudsql.client` e `instanceUser` limitados a
las instancias `<prefix>-<env>-data-` (`workload`, `run` y `mig`), el rol del apagado (`sched`)
y el enlace de Workload Identity (`workload`). Esta raíz las lee y las adjunta a sus recursos:
`<prefix>-tf-wl-<env>` solo tiene `iam.serviceAccountUser` sobre `gke-nodes`, `mig`, `run` y
`sched` de su entorno. Una postcondición exige que `1-base` publique las cuatro cuentas (y
`scheduler` con el apagado).

`application` tiene como máximo 8 caracteres: con el prefijo más largo (6) y prod,
`<prefix>-prod-<application>-gke-nodes` llega a los 30 de un ID de cuenta (ADR 0017). Cloud
Run descarga imágenes con su agente de servicio, que es del proyecto: ese permiso es de
`1-base`.

### Alcance por entorno en el proyecto único

- **Workload Identity**: el pool `<proyecto>.svc.id.goog` es del proyecto y lo comparten los
  clústeres de los tres entornos, así que lo que separa a los entornos es el namespace,
  `<application>-<environment>`, que fija `1-base` (ADR 0029 §9). Una cuenta de Kubernetes con
  el mismo namespace y nombre en el clúster de otro entorno obtendría la misma identidad: se
  evita no creando namespaces de otro entorno en un clúster (riesgo aceptado, ADR 0029). El pool
  lo crea GKE con el primer clúster: `1-base` crea el enlace solo con
  `gke_workload_identity_bindings = true`, que se enciende después del primer apply de esta raíz
  con `enable_gke`. Mientras tanto el `check "workload_identity_enlazada"` avisa en cada plan.
- **Observabilidad**: las alertas, el SLO y el tablero filtran por los nombres
  `<prefix>-<env>-` (clústeres, instancias de Cloud SQL, mapas de URL) y por la etiqueta `env`
  de las VM, para no mezclar los entornos del proyecto (módulo `observability`).
- **Cloud SQL**: el nombre de una instancia borrada no se puede reutilizar de inmediato
  (HYPOTHESIS: hasta una semana). Para volver a crear dev o qa poco después de un `destroy`,
  cambiar `sql_instance_name` (por ejemplo a `sql2`).

### Backends del balanceador externo

Se arman con lo que esté habilitado: `run` (NEG sin servidor de Cloud Run), `mig` (grupo de
instancias del MIG con su verificación de salud) y `gke`. El backend por defecto es
`lb_default_backend` si está habilitado o, si no, el primero habilitado en el orden `run`,
`mig`, `gke`; `lb_backend_paths` asigna rutas a cada backend. Si no hay ningún backend, no se
crean el balanceador ni Cloud Armor y `lb_ip_address` es null.

**GKE**: los NEG zonales los crea GKE al desplegar un `Service` con la anotación
`cloud.google.com/neg` (fuera de Terraform), así que no existen en el primer plan. Entran por
`gke_lb_negs` (self links, vacío por defecto) después del primer despliegue de la carga, y se
aplica otra vez; el balanceador les crea una verificación de salud
(`gke_lb_negs.health_check_path`) y usa el modo `RATE` con `max_rate_per_endpoint`. Con
`gke_lb_negs.primary` vacío el clúster existe pero no recibe tráfico del balanceador externo.

### Plano de control de GKE y puertos de backend

El /28 del plano de control sale de la salida `reserved_cidrs` del spoke (`gke_master` y, con
`dr_active`, `gke_master_dr`): es el mismo valor que usa su regla de firewall. Una
postcondición sobre el estado de red lo exige con `enable_gke`. Otra comprueba que
`mig_http_port` (con `enable_mig`) esté en `lb_backend_ports` del spoke (puerto o rango); si el
spoke no publica esa salida, no se comprueba. Una tercera exige que la VPC del spoke esté en
`project_id`.

## DR

- `enable_dr = true` (prod): réplica de Cloud SQL en `dr_region`, bucket de doble región con
  turbo replication y plan de Backup for GKE. Exige el spoke con `enable_dr = true`. Cambiar
  `enable_dr` reemplaza el bucket (cambian ubicación y nombre): se decide al crear el entorno.
- `dr_active = true` (conmutación; exige `enable_dr`, validado): GKE, MIG y Cloud Run se crean
  también en `dr_region` (llave `dr` de cada `for_each`, subredes `app_dr`/`run_dr`,
  `reserved_cidrs["gke_master_dr"]`, llaves de DR) y los backends del balanceador externo pasan
  a esa región (`dr_active`/`dr_groups` del módulo `load-balancer`). El cómputo primario se
  conserva para no destruirlo durante el incidente.
- GKE en la conmutación: los NEG del clúster de DR no existen hasta desplegar la carga en él,
  así que `dr_active = true` planea con los tfvars normales (`gke_lb_negs.dr` vacío): el backend
  `gke` sale del externo (y el backend por defecto pasa al primero habilitado) hasta que se
  llenen los NEG de DR y se aplique otra vez. Si GKE es el único backend, se queda con los NEG
  primarios para no destruir el balanceador ni su IP.
- Balanceador interno: uno por región con cómputo. `dr_active = true` agrega el de `dr_region`
  con los grupos de esa región y no toca el primario; las reglas de reenvío tienen acceso
  global, así que on-premises llega a cualquiera de los dos. El registro DNS interno se cambia a
  `internal_lb_ip_address` (la IP del de la región activa; todas en `internal_lb_ip_addresses`).
- Certificado interno de DR: con `enable_dr` la autorización DNS y el certificado de
  `dr_region` existen desde el primer apply (sin el balanceador de DR), así que el certificado
  se emite antes de un incidente con los registros de
  `internal_lb_dns_authorization_records_by_region`. El registro DNS interno no lo administra
  ninguna etapa: la salida `internal_lb_dns_records` da los registros A que deben existir para
  la región activa, y moverlos es el único paso manual de DNS de la conmutación (runbook 04).
- Vuelta a la región primaria: en prod el clúster de GKE y el servicio de Cloud Run tienen la
  protección contra borrado fija y el proveedor se niega a destruirlos. `dr_teardown = true`
  (solo con `dr_active = true`, validado) la quita solo de la instancia `dr`: primero un apply
  con `dr_active = true` y `dr_teardown = true` (cambio en el lugar; en Cloud Run es un PATCH
  del servicio vivo, así que en ese apply no se cambia nada más), después uno con
  `dr_active = false` y `dr_teardown = false` juntos, que destruye el cómputo y el balanceador
  interno de DR (el proveedor 6.50.0 lee la protección del estado al borrar). La validación
  impide que `dr_teardown` quede encendido. El MIG y el balanceador interno no tienen protección
  contra borrado; la réplica de Cloud SQL, el certificado interno de DR y los planes de
  respaldo dependen de `enable_dr`/`enable_backup`, no de `dr_active`, y la vuelta no los toca.
- **Promoción de la réplica de Cloud SQL**: es un paso del runbook de conmutación a DR, no de
  Terraform (`gcloud sql instances promote-replica`). Después hay que reconciliar el estado
  (la réplica promovida deja de ser réplica) antes del siguiente `apply`.

## Apagado fuera de horario (`off_hours_shutdown`, ADR 0028)

Solo dev y qa: se rechaza en prod y con `enable_dr`. Por defecto está apagado; los
`terraform.tfvars.example` de dev y qa lo encienden de 07:00 a 20:00 de lunes a viernes
(`America/Monterrey`). Con `enabled = true` los trabajos usan la cuenta
`<prefix>-<env>-<app>-sched`, que `1-base` crea con el rol personalizado del apagado si
`off_hours_environments` de `1-base` incluye el entorno (una postcondición exige que exista). El
rol va sin condición, así que esa cuenta también podría detener la instancia o cambiar los pools
de otro entorno del proyecto; sus trabajos solo apuntan a los de su entorno (riesgo aceptado,
ADR 0029 §3). Qué hace (`off_hours.tf`):

| Recurso | Qué pasa fuera del horario | Cómo |
|---|---|---|
| Cloud SQL | Detenida (`activation_policy = NEVER`); se siguen cobrando almacenamiento e IP | Trabajos `sql-primary-stop` y `sql-primary-start` del módulo `off-hours-shutdown` |
| GKE (`enable_gke`) | Cada pool en 0 nodos; el clúster sigue (y cobra su cuota) | Cuatro trabajos por pool (`setAutoscaling` y `setSize`, con 10 minutos entre pasos); pools con `scheduled_scaling` |
| MIG (`enable_mig`) | 0 VM; durante el horario, `mig_min_replicas` VM fijas (sin autoescalado por CPU) | Programa de escalado del autoescalador (`business_hours`) |
| Cloud Run | Ya escala a 0 (`min_instances = 0`) | Nada |
| Memorystore, Filestore | Siguen encendidos y cobrando | No se pueden detener (HYPOTHESIS, ADR 0028); apagarlos es `enable_* = false` |
| Backup and DR | La ventana diaria de 6 horas empieza en la primera hora en punto desde el encendido | `operations.tf`; la variable valida que quepa en el horario |

Sin deriva: el módulo `cloud-sql` ignora `activation_policy` y los pools `scheduled` ignoran
`autoscaling`; la salida `off_hours_shutdown` solo lleva valores de la configuración. El
`check "cloud_sql_encendida"` avisa en cada plan con la instancia detenida (no cambia el código
de salida). Un apply fuera de horario no enciende nada; si necesita la base (crear bases o
usuarios), lanzar antes el trabajo de encendido:

```sh
terraform output -json off_hours_shutdown | jq -r '.job_ids["sql-primary-start"]'
gcloud scheduler jobs run <id>
```

## Lecturas de otras etapas (`remote_state.tf`)

| Prefijo | Salidas que usa (ADR 0029, "Interfaces entre etapas") |
|---|---|
| `1-base` | `kms_key_ids` (entorno → uso → ID; también se acepta entorno → ubicación → uso), `artifact_registry_repositories` (entorno → aplicación → URL `<ubicación>-docker.pkg.dev/<proyecto>/<repositorio>`), `runtime_service_accounts` (entorno → aplicación → uso → correo), `gke_workload_identity_members` (entorno → aplicación → miembro o null), `notification_channel_ids` |
| `2-networks/<env>` | `network_self_link`, `subnets`, `psa_range_name`, `secure_tags`, `secure_tag_keys`, `reserved_cidrs`, `lb_backend_ports` (opcional) |

De `kms_key_ids` la raíz toma la ubicación del ID de cada llave y el uso de la primera palabra
de su llave (`sql_dr` → `us-east4`/`sql`, `storage_us` → `us`/`storage`). Postcondiciones sobre
los dos estados y `terraform_data.upstream_checks` comprueban en el plan que esas salidas traigan
lo que pide la configuración: llaves de cada región con recursos, las cuentas de ejecución (y la
del apagado con `off_hours_shutdown`), el repositorio de la aplicación en `project_id`, subredes,
rangos y etiquetas seguras. `secret_ids` y `security_alert_email` no se leen: la lectura de los
secretos y las alertas de auditoría son de `1-base`.

## Cómo correrla

```sh
cd stages/3-workloads/envs/<env>
cp terraform.tfvars.example terraform.tfvars   # reemplazar marcadores
terraform init -backend-config="bucket=<bucket de estado>"
terraform plan -out=tfplan
terraform apply tfplan
```

Orden: después de `1-base` y de `2-networks/envs/<env>`. En el pipeline la aplica la cuenta
`<prefix>-tf-wl-<env>` y la planea `<prefix>-tf-read`. Con GKE detrás del balanceador externo:
primer apply sin `gke_lb_negs`, despliegue de la carga en el clúster, segundo apply con los NEG.
Prueba sin GCP: `terraform test` (proveedores simulados y estados de `1-base` y del spoke
simulados; `tests/workloads.tftest.hcl` cubre prod normal, la conmutación con y sin NEG de DR,
los dos pasos de la vuelta con `dr_teardown`, el certificado interno de DR antes del incidente,
dev, qa, la primera ejecución sin cómputo, las cuentas de `1-base`, GKE antes del enlace de
Workload Identity, la forma anterior de `kms_key_ids`, el apagado fuera de horario y entradas
rechazadas, entre ellas una red o un repositorio de otro proyecto, un estado de `1-base` sin
las cuentas de ejecución y el apagado en prod o sin la cuenta de `1-base`).

Pasos fuera de Terraform: registros DNS A de `domain_names` hacia `lb_ip_address` (el
certificado se activa entonces); registros de `internal_lb_dns_authorization_records_by_region`
(las dos regiones con `enable_dr`) en la zona pública del dominio interno; registros A de
`internal_lb_dns_records` en el DNS interno; `CREATE EXTENSION pgaudit;` en cada base; los
valores de los secretos (los carga una persona); la cuenta de Kubernetes
`<application>-<env>`/`gke_workload_ksa_name` (de `1-base`) con la anotación
`iam.gke.io/gcp-service-account` = correo de `service_accounts["workload"]`. Las imágenes de Cloud Run y de GKE deben estar en el
repositorio del entorno (`artifact_registry_repositories` de `1-base`): Binary Authorization
niega las demás. Se referencian con una etiqueta de versión o un digest (`@sha256:...`), nunca
`latest`: el repositorio tiene etiquetas inmutables.

## Permisos de la cuenta `<prefix>-tf-wl-<env>`

Los da `0-bootstrap` en el proyecto (ADR 0029 §3) y `1-base` sobre cada cuenta de ejecución;
esta raíz no se los da a sí misma. Lo que necesita para aplicar esta raíz:

- Cuentas de servicio: solo `actAs` (`roles/iam.serviceAccountUser`) sobre `gke-nodes`, `mig`,
  `run` y `sched` de su entorno, que `1-base` le da sobre cada cuenta
  (`google_service_account_iam_member.workloads_user`). No crea cuentas ni administra su IAM, y
  no tiene `projectIamAdmin`.
- Cargas: `roles/backupdr.admin`, `roles/certificatemanager.editor`, `roles/cloudsql.admin`,
  `roles/compute.instanceAdmin.v1`, `roles/compute.loadBalancerAdmin`,
  `roles/compute.securityAdmin` (Cloud Armor), `roles/compute.networkUser` (subredes del
  spoke), `roles/container.admin`, `roles/file.editor`, `roles/gkebackup.admin`,
  `roles/monitoring.editor`, `roles/redis.admin`, `roles/run.admin`,
  `roles/cloudscheduler.admin` (dev y qa) y `roles/storage.admin` condicionado a
  `projects/_/buckets/<prefix>-<env>-`.
- Etiquetas seguras: `roles/resourcemanager.tagUser` solo sobre los valores `lb_backend` e
  `iap_ssh` del spoke de su entorno (§7.4), que le da `2-networks/envs/<env>` para crear
  plantillas y pools con esas etiquetas; ningún rol de etiquetas en el proyecto (el `tagUser` de
  proyecto trae `iam.serviceAccounts.deleteTagBinding`, que la denegación no puede negar). Esta
  raíz no declara ningún tagUser: los valores no son suyos. El agente de GKE y
  `<número>@cloudservices.gserviceaccount.com`, que crean los nodos y las VM, tienen `tagUser`
  de proyecto desde `0-bootstrap`.
- Estado: lectura de los prefijos `1-base` y `2-networks/<env>` y escritura de
  `3-workloads/<env>` en el bucket de estado.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_backup"></a> [backup](#module\_backup) | ../../../../modules/backup-dr | n/a |
| <a name="module_cloud_armor"></a> [cloud\_armor](#module\_cloud\_armor) | ../../../../modules/cloud-armor | n/a |
| <a name="module_cloud_run"></a> [cloud\_run](#module\_cloud\_run) | ../../../../modules/cloud-run | n/a |
| <a name="module_cloud_sql"></a> [cloud\_sql](#module\_cloud\_sql) | ../../../../modules/cloud-sql | n/a |
| <a name="module_external_lb"></a> [external\_lb](#module\_external\_lb) | ../../../../modules/load-balancer | n/a |
| <a name="module_filestore"></a> [filestore](#module\_filestore) | ../../../../modules/filestore | n/a |
| <a name="module_gke"></a> [gke](#module\_gke) | ../../../../modules/gke | n/a |
| <a name="module_internal_lb"></a> [internal\_lb](#module\_internal\_lb) | ../../../../modules/load-balancer | n/a |
| <a name="module_memorystore"></a> [memorystore](#module\_memorystore) | ../../../../modules/memorystore | n/a |
| <a name="module_mig"></a> [mig](#module\_mig) | ../../../../modules/compute-mig | n/a |
| <a name="module_observability"></a> [observability](#module\_observability) | ../../../../modules/observability | n/a |
| <a name="module_off_hours_shutdown"></a> [off\_hours\_shutdown](#module\_off\_hours\_shutdown) | ../../../../modules/off-hours-shutdown | n/a |
| <a name="module_storage"></a> [storage](#module\_storage) | ../../../../modules/storage | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [google_certificate_manager_certificate.internal](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/certificate_manager_certificate) | resource |
| [google_certificate_manager_dns_authorization.internal](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/certificate_manager_dns_authorization) | resource |
| [terraform_data.upstream_checks](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_remote_state.base](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |
| [terraform_remote_state.network](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_domain_names"></a> [domain\_names](#input\_domain\_names) | Dominios públicos del certificado administrado del balanceador externo; el primero recibe la verificación de disponibilidad. | `list(string)` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno de esta raíz: dev, qa o prod. Debe coincidir con el prefijo de backend.tf. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes (§4.3). Obligatorias aquí: app (igual a application), owner y cost\_center; env y managed\_by las fija la raíz. | `map(string)` | n/a | yes |
| <a name="input_notification_emails"></a> [notification\_emails](#input\_notification\_emails) | Correos (de preferencia listas de grupo) que reciben las alertas del entorno. | `list(string)` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (§4.2), por ejemplo bnt. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto único de GCP (ADR 0029 §1). Lo crea una persona; ninguna raíz lo crea ni lo borra. Todo lo de esta raíz vive en él. | `string` | n/a | yes |
| <a name="input_state_bucket"></a> [state\_bucket](#input\_state\_bucket) | Bucket de estado de 0-bootstrap; de él se leen los prefijos 1-base y 2-networks/<environment> (ADR 0029 §2). | `string` | n/a | yes |
| <a name="input_application"></a> [application](#input\_application) | Aplicación cuyas cargas crea esta raíz (por defecto app): llave de artifact\_registry\_repositories[environment] de 1-base y parte de los nombres de las cuentas de ejecución (<prefix>-<environment>-<application>-<uso>), del clúster de GKE, del balanceador, de la política de Cloud Armor y del bucket. | `string` | `"app"` | no |
| <a name="input_bucket_name_suffix"></a> [bucket\_name\_suffix](#input\_bucket\_name\_suffix) | Sufijo del nombre del bucket para hacerlo único a nivel mundial (como project\_suffix). Vacío por defecto. | `string` | `""` | no |
| <a name="input_cloud_run_container_port"></a> [cloud\_run\_container\_port](#input\_cloud\_run\_container\_port) | Puerto en el que escucha el contenedor de Cloud Run. | `number` | `8080` | no |
| <a name="input_cloud_run_image"></a> [cloud\_run\_image](#input\_cloud\_run\_image) | Imagen del contenedor de Cloud Run (registro/ruta:etiqueta o @sha256:digest; en prod sin latest), del repositorio del entorno (artifact\_registry\_repositories de 1-base). Obligatoria con enable\_cloud\_run. | `string` | `null` | no |
| <a name="input_cloud_run_max_instances"></a> [cloud\_run\_max\_instances](#input\_cloud\_run\_max\_instances) | Máximo de instancias del servicio de Cloud Run. | `number` | `10` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Protección contra borrado de Cloud SQL, Filestore, GKE y Cloud Run fuera de prod. En prod debe ser true (los módulos además la fijan). | `bool` | `true` | no |
| <a name="input_dr_active"></a> [dr\_active](#input\_dr\_active) | Conmutación a DR: crea el cómputo (GKE, MIG, Cloud Run) también en dr\_region y apunta los backends de los balanceadores a esa región. Exige enable\_dr. La promoción de la réplica de Cloud SQL es un paso del runbook, no de Terraform. | `bool` | `false` | no |
| <a name="input_dr_region"></a> [dr\_region](#input\_dr\_region) | Región de DR (ADR 0002). Siempre se declara: la bóveda de respaldos vive ahí aunque enable\_dr = false. | `string` | `"us-east4"` | no |
| <a name="input_dr_teardown"></a> [dr\_teardown](#input\_dr\_teardown) | Vuelta a la región primaria (runbook 04): quita la protección contra borrado solo del clúster<br/>de GKE y del servicio de Cloud Run de la región de DR (llave "dr"), también en prod; los de<br/>la región primaria siguen protegidos. Primer apply: dr\_active = true y dr\_teardown = true<br/>(cambio en el lugar). Segundo apply: dr\_active = false y dr\_teardown = false juntos; el<br/>proveedor lee la protección del estado al borrar, así que destruye el cómputo de DR. Solo se<br/>admite con dr\_active = true: no puede quedar encendido y desproteger el cómputo de DR de la<br/>siguiente conmutación. | `bool` | `false` | no |
| <a name="input_enable_backup"></a> [enable\_backup](#input\_enable\_backup) | Crea la bóveda de Backup and DR en dr\_region y los planes diarios (retención de 30 días). | `bool` | `true` | no |
| <a name="input_enable_cloud_run"></a> [enable\_cloud\_run](#input\_enable\_cloud\_run) | Crea el servicio de Cloud Run (ADR 0012) en la región primaria (y en la de DR con dr\_active). | `bool` | `false` | no |
| <a name="input_enable_dr"></a> [enable\_dr](#input\_enable\_dr) | DR de datos (prod): réplica de Cloud SQL en dr\_region, bucket de doble región con turbo replication y plan de Backup for GKE. Exige que el spoke de 2-networks tenga enable\_dr = true. | `bool` | `false` | no |
| <a name="input_enable_filestore"></a> [enable\_filestore](#input\_enable\_filestore) | Crea la instancia de Filestore en la región primaria. | `bool` | `false` | no |
| <a name="input_enable_gke"></a> [enable\_gke](#input\_enable\_gke) | Crea el clúster de GKE (ADR 0012) en la región primaria (y en la de DR con dr\_active). | `bool` | `false` | no |
| <a name="input_enable_internal_lb"></a> [enable\_internal\_lb](#input\_enable\_internal\_lb) | Crea el balanceador de aplicaciones interno regional (subred proxy-only del spoke) delante del MIG y de Cloud Run para clientes internos y on-premises. | `bool` | `false` | no |
| <a name="input_enable_memorystore"></a> [enable\_memorystore](#input\_enable\_memorystore) | Crea la instancia de Memorystore para Redis en la región primaria. | `bool` | `false` | no |
| <a name="input_enable_mig"></a> [enable\_mig](#input\_enable\_mig) | Crea el MIG regional de VM (ADR 0012) en la región primaria (y en la de DR con dr\_active). | `bool` | `false` | no |
| <a name="input_filestore_capacity_gb"></a> [filestore\_capacity\_gb](#input\_filestore\_capacity\_gb) | Capacidad del recurso compartido de Filestore en GiB (rangos por tier: los valida el módulo). | `number` | `1024` | no |
| <a name="input_filestore_tier"></a> [filestore\_tier](#input\_filestore\_tier) | Nivel de Filestore con CMEK: ZONAL (en la zona primary\_region-<filestore\_zone\_suffix>), REGIONAL o ENTERPRISE. | `string` | `"REGIONAL"` | no |
| <a name="input_filestore_zone_suffix"></a> [filestore\_zone\_suffix](#input\_filestore\_zone\_suffix) | Letra de la zona de primary\_region para Filestore ZONAL (por ejemplo, a). | `string` | `"a"` | no |
| <a name="input_gke_authenticator_security_group"></a> [gke\_authenticator\_security\_group](#input\_gke\_authenticator\_security\_group) | Grupo raíz de Google Groups for RBAC del clúster (gke-security-groups@<dominio>). Obligatorio con enable\_gke. | `string` | `null` | no |
| <a name="input_gke_lb_negs"></a> [gke\_lb\_negs](#input\_gke\_lb\_negs) | Backends de GKE para el balanceador externo. GKE crea los NEG zonales al desplegar un Service<br/>con la anotación cloud.google.com/neg (fuera de Terraform), así que sus self links se llenan<br/>después del primer despliegue de la carga y se aplica de nuevo. Vacío por defecto: sin backend<br/>de GKE en el balanceador.<br/>- primary: self links de los NEG zonales del clúster de la región primaria.<br/>- dr: los del clúster de DR. Se llenan después de conmutar (el clúster de DR nace con<br/>  dr\_active): mientras estén vacíos, con dr\_active el backend de GKE queda fuera del<br/>  balanceador (si es el único backend, sigue con los NEG primarios para no destruir el<br/>  balanceador).<br/>- max\_rate\_per\_endpoint: solicitudes por segundo por endpoint (modo RATE).<br/>- health\_check\_path: ruta de la verificación de salud que crea el balanceador. | <pre>object({<br/>    primary               = optional(list(string), [])<br/>    dr                    = optional(list(string), [])<br/>    max_rate_per_endpoint = optional(number, 100)<br/>    health_check_path     = optional(string, "/healthz")<br/>  })</pre> | `{}` | no |
| <a name="input_gke_master_authorized_networks"></a> [gke\_master\_authorized\_networks](#input\_gke\_master\_authorized\_networks) | Rangos autorizados para llegar al plano de control privado de GKE (por ejemplo, el rango on-premises o una subred de administración). | <pre>list(object({<br/>    cidr_block   = string<br/>    display_name = string<br/>  }))</pre> | `[]` | no |
| <a name="input_gke_node_pools"></a> [gke\_node\_pools](#input\_gke\_node\_pools) | Pools de nodos de GKE (llave → configuración); mismo formato que el módulo gke. min\_node\_count y max\_node\_count son por zona. Obligatorio con enable\_gke. | <pre>map(object({<br/>    machine_type    = string<br/>    min_node_count  = number<br/>    max_node_count  = number<br/>    disk_size_gb    = optional(number, 100)<br/>    disk_type       = optional(string, "pd-balanced")<br/>    spot            = optional(bool, false)<br/>    node_locations  = optional(list(string))<br/>    max_surge       = optional(number, 1)<br/>    max_unavailable = optional(number, 0)<br/>    k8s_labels      = optional(map(string), {})<br/>    taints = optional(list(object({<br/>      key    = string<br/>      value  = string<br/>      effect = string<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_gke_release_channel"></a> [gke\_release\_channel](#input\_gke\_release\_channel) | Canal de versiones de GKE: RAPID, REGULAR o STABLE (sin RAPID en prod, lo valida el módulo). | `string` | `"REGULAR"` | no |
| <a name="input_internal_domain_names"></a> [internal\_domain\_names](#input\_internal\_domain\_names) | Dominios del certificado del balanceador interno (Certificate Manager con autorización DNS). Obligatorio con enable\_internal\_lb. | `list(string)` | `[]` | no |
| <a name="input_lb_backend_paths"></a> [lb\_backend\_paths](#input\_lb\_backend\_paths) | Rutas del mapa de URL por backend (llaves gke, mig o run → lista de rutas, por ejemplo { run = ["/api/*"] }). Las solicitudes sin ruta van a lb\_default\_backend. | `map(list(string))` | `{}` | no |
| <a name="input_lb_default_backend"></a> [lb\_default\_backend](#input\_lb\_default\_backend) | Backend por defecto del mapa de URL externo: gke, mig o run. null: el primero habilitado en el orden run, mig, gke. | `string` | `null` | no |
| <a name="input_memorystore_memory_gb"></a> [memorystore\_memory\_gb](#input\_memorystore\_memory\_gb) | Memoria de la instancia de Redis en GB (el tier lo decide el módulo: STANDARD\_HA en prod, BASIC fuera). | `number` | `5` | no |
| <a name="input_mig_health_check_path"></a> [mig\_health\_check\_path](#input\_mig\_health\_check\_path) | Ruta HTTP de la verificación de salud del MIG (autocuración y balanceadores). | `string` | `"/healthz"` | no |
| <a name="input_mig_http_port"></a> [mig\_http\_port](#input\_mig\_http\_port) | Puerto HTTP en el que sirven las VM (puerto con nombre http del grupo y de las verificaciones de salud). Debe estar en lb\_backend\_ports del spoke de 2-networks (lo comprueba el plan si el spoke publica esa salida). | `number` | `80` | no |
| <a name="input_mig_image"></a> [mig\_image](#input\_mig\_image) | Imagen endurecida de las VM del MIG (projects/<p>/global/images/<imagen> o .../images/family/<familia>). Sin valor por defecto público: obligatoria con enable\_mig. | `string` | `null` | no |
| <a name="input_mig_machine_type"></a> [mig\_machine\_type](#input\_mig\_machine\_type) | Tipo de máquina de las VM del MIG. | `string` | `"e2-standard-2"` | no |
| <a name="input_mig_max_replicas"></a> [mig\_max\_replicas](#input\_mig\_max\_replicas) | Máximo de VM del autoescalador. | `number` | `4` | no |
| <a name="input_mig_min_replicas"></a> [mig\_min\_replicas](#input\_mig\_min\_replicas) | Mínimo de VM del autoescalador (al menos 2 en prod, lo valida el módulo). | `number` | `2` | no |
| <a name="input_multi_region"></a> [multi\_region](#input\_multi\_region) | Multirregión del bucket de doble región con enable\_dr (llave storage de 1-base en esa ubicación). Debe contener primary\_region y dr\_region. | `string` | `"us"` | no |
| <a name="input_off_hours_shutdown"></a> [off\_hours\_shutdown](#input\_off\_hours\_shutdown) | Apagado fuera de horario de dev y qa (ADR 0028). Con enabled = true:<br/>- Cloud SQL se detiene a la hora de stop\_schedule y se enciende a la de start\_schedule<br/>  (trabajos de Cloud Scheduler, módulo off-hours-shutdown);<br/>- el MIG (enable\_mig) baja a 0 VM fuera del horario con un programa de escalado nativo y<br/>  tiene mig\_min\_replicas VM durante el horario, sin autoescalado por CPU;<br/>- los pools de GKE (enable\_gke) se llevan a 0 nodos y vuelven a su mínimo con el<br/>  autoescalado reactivado;<br/>- la ventana de Backup and DR pasa al horario encendido.<br/>Cloud Run ya escala a 0 (min\_instances = 0); Memorystore y Filestore no se pueden detener.<br/>Los crons van en time\_zone con la forma "M H * * D" (minuto, hora, días de la semana 0-6) y<br/>los mismos días en los dos. La cuenta de los trabajos (<prefix>-<environment>-<app>-sched) la<br/>crea 1-base con el rol del apagado si off\_hours\_environments de 1-base incluye el entorno.<br/>Se rechaza en prod y con enable\_dr. | <pre>object({<br/>    enabled        = bool<br/>    time_zone      = optional(string, "America/Mexico_City")<br/>    start_schedule = optional(string, "0 7 * * 1-5")<br/>    stop_schedule  = optional(string, "0 20 * * 1-5")<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_primary_region"></a> [primary\_region](#input\_primary\_region) | Región primaria (ADR 0002). | `string` | `"us-central1"` | no |
| <a name="input_region_codes"></a> [region\_codes](#input\_region\_codes) | Mapa región → código corto para los nombres (§4.2). | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_sql_database_version"></a> [sql\_database\_version](#input\_sql\_database\_version) | Versión de PostgreSQL de Cloud SQL (POSTGRES\_<n>). | `string` | `"POSTGRES_16"` | no |
| <a name="input_sql_databases"></a> [sql\_databases](#input\_sql\_databases) | Bases de datos que se crean en la instancia de Cloud SQL. | `list(string)` | <pre>[<br/>  "app"<br/>]</pre> | no |
| <a name="input_sql_instance_name"></a> [sql\_instance\_name](#input\_sql\_instance\_name) | Parte <recurso> del nombre de la instancia de Cloud SQL: <prefix>-<environment>-data-<sql\_instance\_name>-<región>. Por defecto sql. En el proyecto único el destroy de un entorno ya no borra el proyecto, y el nombre de una instancia borrada no se puede reutilizar de inmediato (HYPOTHESIS: hasta una semana, según la documentación de Cloud SQL): para volver a crear el entorno antes, se cambia (por ejemplo sql2). | `string` | `"sql"` | no |
| <a name="input_sql_tier"></a> [sql\_tier](#input\_sql\_tier) | Tipo de máquina de Cloud SQL (db-custom-* en edición ENTERPRISE). | `string` | `"db-custom-2-7680"` | no |
| <a name="input_uptime_check_path"></a> [uptime\_check\_path](#input\_uptime\_check\_path) | Ruta HTTPS que revisa la verificación de disponibilidad sobre el primer dominio de domain\_names. | `string` | `"/"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_active_region"></a> [active\_region](#output\_active\_region) | Región que atiende el tráfico de los balanceadores (dr\_region con dr\_active). |
| <a name="output_backup_plan_ids"></a> [backup\_plan\_ids](#output\_backup\_plan\_ids) | Mapa llave → ID de cada plan de respaldo (sql y, con DR y GKE, gke). |
| <a name="output_backup_vault_id"></a> [backup\_vault\_id](#output\_backup\_vault\_id) | ID de la bóveda de Backup and DR en dr\_region (null con enable\_backup = false). |
| <a name="output_bucket_names"></a> [bucket\_names](#output\_bucket\_names) | Mapa uso → nombre del bucket (llave data: el de la aplicación, de doble región con enable\_dr). |
| <a name="output_cloud_run_service_names"></a> [cloud\_run\_service\_names](#output\_cloud\_run\_service\_names) | Mapa región → nombre del servicio de Cloud Run (vacío con enable\_cloud\_run = false). |
| <a name="output_filestore_ip_address"></a> [filestore\_ip\_address](#output\_filestore\_ip\_address) | IP privada del servidor NFS de Filestore (null con enable\_filestore = false). |
| <a name="output_gke_cluster_names"></a> [gke\_cluster\_names](#output\_gke\_cluster\_names) | Mapa región → nombre del clúster de GKE (vacío con enable\_gke = false; con dr\_active incluye dr\_region). |
| <a name="output_gke_workload_identity_member"></a> [gke\_workload\_identity\_member](#output\_gke\_workload\_identity\_member) | Miembro serviceAccount:<proyecto>.svc.id.goog[<application>-<environment>/<cuenta>] que actúa como la cuenta workload (ADR 0029 §9). Lo enlaza 1-base (gke\_workload\_identity\_bindings); null sin enable\_gke o mientras 1-base no lo enlace. |
| <a name="output_internal_lb_certificate_ids"></a> [internal\_lb\_certificate\_ids](#output\_internal\_lb\_certificate\_ids) | Mapa región → ID del certificado de Certificate Manager del balanceador interno (la de DR existe con enable\_dr, antes de dr\_active). Vacío sin enable\_internal\_lb. |
| <a name="output_internal_lb_dns_authorization_records"></a> [internal\_lb\_dns\_authorization\_records](#output\_internal\_lb\_dns\_authorization\_records) | Dominio → registro DNS (name, type, data) que hay que crear para emitir el certificado del balanceador interno de la región activa. |
| <a name="output_internal_lb_dns_authorization_records_by_region"></a> [internal\_lb\_dns\_authorization\_records\_by\_region](#output\_internal\_lb\_dns\_authorization\_records\_by\_region) | Mapa región → dominio → registro DNS de autorización del certificado interno de esa región. Con enable\_dr incluye dr\_region aunque dr\_active sea false: esos registros se crean antes de un incidente. |
| <a name="output_internal_lb_dns_records"></a> [internal\_lb\_dns\_records](#output\_internal\_lb\_dns\_records) | Registros A que deben existir en el DNS interno (fuera de este repositorio) para internal\_domain\_names: nombre → type y rrdatas con la IP del balanceador interno de la región activa. Cambia con dr\_active; moverlos es el paso manual de DNS del runbook 04. Vacío sin enable\_internal\_lb. |
| <a name="output_internal_lb_ip_address"></a> [internal\_lb\_ip\_address](#output\_internal\_lb\_ip\_address) | IP interna del balanceador interno de la región activa (active\_region): la que debe tener el registro DNS interno. null sin enable\_internal\_lb. |
| <a name="output_internal_lb_ip_addresses"></a> [internal\_lb\_ip\_addresses](#output\_internal\_lb\_ip\_addresses) | Mapa región → IP interna del balanceador interno de esa región (la de DR solo con dr\_active). Vacío sin enable\_internal\_lb. |
| <a name="output_lb_ip_address"></a> [lb\_ip\_address](#output\_lb\_ip\_address) | IP pública global del balanceador HTTPS externo (para los registros DNS A de domain\_names). null si no hay ningún backend habilitado. |
| <a name="output_mig_instance_groups"></a> [mig\_instance\_groups](#output\_mig\_instance\_groups) | Mapa región → URL del grupo de instancias del MIG (vacío con enable\_mig = false). |
| <a name="output_off_hours_shutdown"></a> [off\_hours\_shutdown](#output\_off\_hours\_shutdown) | Apagado fuera de horario (ADR 0028): horario encendido (zona horaria, crons, minutos del día y duración) e IDs de los trabajos de Cloud Scheduler (sql-primary-start enciende Cloud SQL a mano con gcloud scheduler jobs run). null si está apagado. |
| <a name="output_redis_host"></a> [redis\_host](#output\_redis\_host) | IP privada de Memorystore (null con enable\_memorystore = false). |
| <a name="output_scheduler_service_account"></a> [scheduler\_service\_account](#output\_scheduler\_service\_account) | Correo de la cuenta de los trabajos del apagado fuera de horario (<prefix>-<environment>-<application>-sched, ADR 0028), que crea 1-base. null sin off\_hours\_shutdown (siempre en prod). |
| <a name="output_service_accounts"></a> [service\_accounts](#output\_service\_accounts) | Uso → correo de las cuentas de ejecución de la aplicación (<prefix>-<environment>-<application>-<uso>): gke\_nodes, workload, mig y run. Las crea 1-base (runtime\_service\_accounts). La cuenta de Kubernetes de Workload Identity lleva la anotación iam.gke.io/gcp-service-account con el correo de workload. |
| <a name="output_sql_instance_connection_name"></a> [sql\_instance\_connection\_name](#output\_sql\_instance\_connection\_name) | Nombre de conexión de la instancia primaria de Cloud SQL (<proyecto>:<región>:<instancia>). |
| <a name="output_sql_replica_connection_name"></a> [sql\_replica\_connection\_name](#output\_sql\_replica\_connection\_name) | Nombre de conexión de la réplica de Cloud SQL en dr\_region (null sin enable\_dr). Se promueve en el runbook de conmutación. |
<!-- END_TF_DOCS -->
