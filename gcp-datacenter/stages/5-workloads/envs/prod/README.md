# Etapa `5-workloads/envs/<env>`

Cargas de trabajo de un entorno (§7.6 del contrato), en el proyecto de servicio de la
aplicación (`service_project_ids[var.application]` de la etapa 4) y sobre la Shared VPC del
spoke del entorno (etapa 3). Las tres raíces `envs/dev`, `envs/qa` y `envs/prod` son idénticas
salvo `backend.tf` (prefijo `5-workloads/<env>`) y `terraform.tfvars.example`; las diferencias
entre entornos llegan solo por variables.

## Qué crea

Nombres con `prefix = "bnt"`, `application = "app"` y región primaria `us-central1` (§4.2).

| Carga | Interruptor | Módulo | Nombre | Notas |
|---|---|---|---|---|
| GKE | `enable_gke` | `gke` | `bnt-<env>-app-gke-usc1` | subred `app`, rangos secundarios `pods`/`services`, plano de control en `subnet_cidrs["gke_master"]`, llave `gke`, nodos con la cuenta `gke_nodes` y la etiqueta segura `lb_backend`; regional en prod |
| MIG | `enable_mig` | `compute-mig` | `bnt-<env>-app-mig-usc1` | subred `app`, llave `compute`, cuenta `mig`, etiquetas seguras `lb_backend` e `iap_ssh` (`resource_manager_tags`), imagen endurecida por variable (`mig_image`, sin valor por defecto) |
| Cloud Run | `enable_cloud_run` | `cloud-run` | `bnt-<env>-app-run-usc1` | salida directa a la VPC por la subred `run`, llave `run`, cuenta `run`, `public_via_load_balancer = true` (ADR 0020) |
| Cloud SQL | siempre | `cloud-sql` | `bnt-<env>-data-sql-usc1` | PostgreSQL, IP privada en el rango de PSA, llave `sql`, usuario IAM = cuenta `workload` (ADR 0015); con `enable_dr`, réplica `bnt-<env>-data-sql-use4` con la llave `sql` de DR |
| Memorystore | `enable_memorystore` | `memorystore` | `bnt-<env>-data-redis-usc1` | PSA, llave `redis`, STANDARD_HA en prod |
| Filestore | `enable_filestore` | `filestore` | `bnt-<env>-data-nfs-usc1` | PSA, llave `filestore`, tier por variable |
| Cloud Storage | siempre | `storage` | `bnt-<env>-data-app-usc1` | llave `storage`; con `enable_dr`, doble región `bnt-<env>-data-app-usc1-use4` en `US` con turbo replication y la llave `storage` de la multirregión `us` |
| Cloud Armor | con el balanceador externo | `cloud-armor` | `bnt-<env>-app-app-armor` | OWASP (SQLi, XSS y demás), límite de tasa |
| Balanceador externo | hay al menos un backend | `load-balancer` (`external`) | `bnt-<env>-app-app-xlb-*` | HTTPS global, certificado administrado para `domain_names`, redirección de HTTP, Cloud Armor (ADR 0005) |
| Balanceador interno | `enable_internal_lb` | `load-balancer` (`internal`) | `bnt-<env>-app-app-ilb-usc1-*` | regional, IP en la subred `app` de la región activa, subred proxy-only del spoke, certificado de Certificate Manager para `internal_domain_names` |
| Observabilidad | siempre | `observability` | — | canales para `notification_emails`, verificación de disponibilidad del primer dominio, alertas, tablero y SLO de 99.9 % filtrado por el mapa de URL del balanceador externo |
| Respaldo | `enable_backup` (true) | `backup-dr` | `bnt-<env>-bkp-vault-use4` | bóveda en `dr_region`, plan diario de Cloud SQL con 30 días de retención y la instancia asociada; con `enable_gke` y `enable_dr`, plan de Backup for GKE del clúster primario en `dr_region` con la llave `backup` de DR |

Todas las llaves vienen de `kms_key_ids[<env>][<ubicación>][<uso>]` (etapa 2) y todas las
cuentas de servicio de `service_accounts[<application>][<uso>]` (etapa 4). Todo recurso
etiquetable lleva `local.labels` (§4.3).

### Backends del balanceador externo

Se arman con lo que esté habilitado: `run` (NEG sin servidor de Cloud Run), `mig` (grupo de
instancias del MIG con su verificación de salud) y `gke`. El backend por defecto es
`lb_default_backend` o, si es null, el primero habilitado en el orden `run`, `mig`, `gke`;
`lb_backend_paths` asigna rutas a cada backend. Si no hay ningún backend, no se crean el
balanceador ni Cloud Armor y `lb_ip_address` es null.

**GKE**: los NEG zonales los crea GKE al desplegar un `Service` con la anotación
`cloud.google.com/neg` (fuera de Terraform), así que no existen en el primer plan. Decisión:
entran por `gke_lb_negs` (self links, vacío por defecto) después del primer despliegue de la
carga, y se aplica otra vez; el balanceador les crea una verificación de salud
(`gke_lb_negs.health_check_path`) y usa el modo `RATE` con `max_rate_per_endpoint`. Con
`gke_lb_negs.primary` vacío el clúster existe pero no recibe tráfico del balanceador externo.

### Plano de control de GKE

El spoke reserva `gke_master`/`gke_master_dr` sin publicarlos (§7.4 solo publica subredes). La
raíz los recibe en `subnet_cidrs` con las mismas llaves de §5, así que se puede pasar el mismo
mapa de la etapa 3; las demás llaves se ignoran.

## DR

- `enable_dr = true` (prod): réplica de Cloud SQL en `dr_region`, bucket de doble región con
  turbo replication y plan de Backup for GKE. Exige el spoke con `enable_dr = true`. Cambiar
  `enable_dr` reemplaza el bucket (cambian ubicación y nombre): se decide al crear el entorno.
- `dr_active = true` (conmutación; exige `enable_dr`, validado): GKE, MIG y Cloud Run se crean
  también en `dr_region` (llave `dr` de cada `for_each`, subredes `app_dr`/`run_dr`,
  `subnet_cidrs["gke_master_dr"]`, llaves de DR) y los backends de los balanceadores pasan a
  esa región (`dr_active`/`dr_groups` del módulo `load-balancer`; para GKE, `gke_lb_negs.dr`).
  El cómputo primario se conserva para no destruirlo durante el incidente. El balanceador
  interno se recrea en la región de DR (su nombre lleva la región).
- **Promoción de la réplica de Cloud SQL**: es un paso del runbook de conmutación a DR, no de
  Terraform (`gcloud sql instances promote-replica`). Después hay que reconciliar el estado
  (la réplica promovida deja de ser réplica) antes del siguiente `apply`.

## Lecturas de otras etapas (`remote_state.tf`)

| Prefijo | Salidas que usa (§7) |
|---|---|
| `2-security` | `kms_key_ids` (map(map(map(string)))) |
| `3-networks/<env>` | `network_self_link`, `subnets` (map(object)), `psa_range_name`, `secure_tags`, `secure_tag_keys` |
| `4-projects/<env>` | `service_project_ids`, `service_accounts` (map(map(string))) |

La fila de §6.1 admite también `1-org`, pero esta etapa no usa ninguna de sus salidas y no lo
lee. `terraform_data.upstream_checks` comprueba en el plan que esas salidas traigan las llaves
que pide la configuración.

## Cómo correrla

```sh
cd stages/5-workloads/envs/<env>
cp terraform.tfvars.example terraform.tfvars   # reemplazar marcadores
terraform init -backend-config="bucket=<bucket de estado>"
terraform plan -out=tfplan
terraform apply tfplan
```

Orden: después de `4-projects/envs/<env>`. Con GKE detrás del balanceador externo: primer
apply sin `gke_lb_negs`, despliegue de la carga en el clúster, segundo apply con los NEG.
Prueba sin GCP: `terraform test` (proveedores simulados; `tests/workloads.tftest.hcl` cubre
prod normal, prod en conmutación, dev con solo Cloud Run y SQL, qa y entradas rechazadas).

Pasos fuera de Terraform: registros DNS A de `domain_names` hacia `lb_ip_address` (el
certificado se activa entonces); registros de `internal_lb_dns_authorization_records` en la
zona pública del dominio interno; `CREATE EXTENSION pgaudit;` en cada base.

## Roles de la cuenta `<prefix>-tf-5-workloads`

Sobre la carpeta del entorno (los asigna `1-org`, `stages/1-org/iam.tf`): `roles/backupdr.admin`,
`roles/certificatemanager.editor` (certificado del balanceador interno, `enable_internal_lb`),
`roles/cloudsql.admin`, `roles/compute.instanceAdmin.v1`, `roles/compute.loadBalancerAdmin`,
`roles/compute.networkUser`, `roles/compute.securityAdmin` (Cloud Armor),
`roles/container.admin`, `roles/file.editor`, `roles/gkebackup.admin`,
`roles/iam.serviceAccountUser` (usar las cuentas `gke_nodes`, `mig` y `run`),
`roles/monitoring.editor`, `roles/redis.admin`, `roles/run.admin`, `roles/storage.admin`, y
`roles/resourcemanager.projectIamAdmin` con una condición que solo le deja asignar
`roles/cloudsql.client` y `roles/cloudsql.instanceUser` (entrada por IAM de la cuenta `workload`
a Cloud SQL, que el módulo `cloud-sql` otorga). La etapa 4 le da además `actAs` sobre cada cuenta
de ejecución, `roles/compute.networkUser` en las subredes `app` y `run` y
`roles/resourcemanager.tagUser` sobre los valores de `lb_backend` e `iap_ssh` (§7.4). La etapa 0
le da `roles/serviceusage.serviceUsageConsumer` en el proyecto semilla y la lectura del estado:
`roles/storage.objectViewer` condicionado a los prefijos de §6.1.

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
| <a name="module_storage"></a> [storage](#module\_storage) | ../../../../modules/storage | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [terraform_data.upstream_checks](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_remote_state.network](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |
| [terraform_remote_state.projects](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |
| [terraform_remote_state.security](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_domain_names"></a> [domain\_names](#input\_domain\_names) | Dominios públicos del certificado administrado del balanceador externo; el primero recibe la verificación de disponibilidad. | `list(string)` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno de esta raíz: dev, qa o prod. Debe coincidir con el prefijo de backend.tf. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes (§4.3). Obligatorias aquí: app (igual a application), owner y cost\_center; env y managed\_by las fija la raíz. | `map(string)` | n/a | yes |
| <a name="input_notification_emails"></a> [notification\_emails](#input\_notification\_emails) | Correos (de preferencia listas de grupo) que reciben las alertas del entorno. | `list(string)` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (§4.2), por ejemplo bnt. | `string` | n/a | yes |
| <a name="input_state_bucket"></a> [state\_bucket](#input\_state\_bucket) | Bucket de estado de la etapa 0; de él se leen los prefijos 2-security, 3-networks/<env> y 4-projects/<env> (§6.1). | `string` | n/a | yes |
| <a name="input_application"></a> [application](#input\_application) | Aplicación cuyas cargas crea esta raíz: llave de service\_project\_ids y service\_accounts de la etapa 4 (por defecto app). Forma parte de los nombres del balanceador, la política de Cloud Armor y el bucket. | `string` | `"app"` | no |
| <a name="input_bucket_name_suffix"></a> [bucket\_name\_suffix](#input\_bucket\_name\_suffix) | Sufijo del nombre del bucket para hacerlo único a nivel mundial (como project\_suffix). Vacío por defecto. | `string` | `""` | no |
| <a name="input_cloud_run_container_port"></a> [cloud\_run\_container\_port](#input\_cloud\_run\_container\_port) | Puerto en el que escucha el contenedor de Cloud Run. | `number` | `8080` | no |
| <a name="input_cloud_run_image"></a> [cloud\_run\_image](#input\_cloud\_run\_image) | Imagen del contenedor de Cloud Run (registro/ruta:etiqueta o @sha256:digest; en prod sin latest). Obligatoria con enable\_cloud\_run. | `string` | `null` | no |
| <a name="input_cloud_run_max_instances"></a> [cloud\_run\_max\_instances](#input\_cloud\_run\_max\_instances) | Máximo de instancias del servicio de Cloud Run. | `number` | `10` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Protección contra borrado de Cloud SQL, Filestore, GKE y Cloud Run fuera de prod. En prod debe ser true (los módulos además la fijan). | `bool` | `true` | no |
| <a name="input_dr_active"></a> [dr\_active](#input\_dr\_active) | Conmutación a DR: crea el cómputo (GKE, MIG, Cloud Run) también en dr\_region y apunta los backends de los balanceadores a esa región. Exige enable\_dr. La promoción de la réplica de Cloud SQL es un paso del runbook, no de Terraform. | `bool` | `false` | no |
| <a name="input_dr_region"></a> [dr\_region](#input\_dr\_region) | Región de DR (ADR 0002). Siempre se declara: la bóveda de respaldos vive ahí aunque enable\_dr = false. | `string` | `"us-east4"` | no |
| <a name="input_enable_backup"></a> [enable\_backup](#input\_enable\_backup) | Crea la bóveda de Backup and DR en dr\_region y los planes diarios (retención de 30 días). | `bool` | `true` | no |
| <a name="input_enable_cloud_run"></a> [enable\_cloud\_run](#input\_enable\_cloud\_run) | Crea el servicio de Cloud Run (ADR 0012) en la región primaria (y en la de DR con dr\_active). | `bool` | `false` | no |
| <a name="input_enable_dr"></a> [enable\_dr](#input\_enable\_dr) | DR de datos (prod): réplica de Cloud SQL en dr\_region, bucket de doble región con turbo replication y plan de Backup for GKE. Exige que el spoke de la etapa 3 tenga enable\_dr = true. | `bool` | `false` | no |
| <a name="input_enable_filestore"></a> [enable\_filestore](#input\_enable\_filestore) | Crea la instancia de Filestore en la región primaria. | `bool` | `false` | no |
| <a name="input_enable_gke"></a> [enable\_gke](#input\_enable\_gke) | Crea el clúster de GKE (ADR 0012) en la región primaria (y en la de DR con dr\_active). | `bool` | `false` | no |
| <a name="input_enable_internal_lb"></a> [enable\_internal\_lb](#input\_enable\_internal\_lb) | Crea el balanceador de aplicaciones interno regional (subred proxy-only del spoke) delante del MIG y de Cloud Run para clientes internos y on-premises. | `bool` | `false` | no |
| <a name="input_enable_memorystore"></a> [enable\_memorystore](#input\_enable\_memorystore) | Crea la instancia de Memorystore para Redis en la región primaria. | `bool` | `false` | no |
| <a name="input_enable_mig"></a> [enable\_mig](#input\_enable\_mig) | Crea el MIG regional de VM (ADR 0012) en la región primaria (y en la de DR con dr\_active). | `bool` | `false` | no |
| <a name="input_filestore_capacity_gb"></a> [filestore\_capacity\_gb](#input\_filestore\_capacity\_gb) | Capacidad del recurso compartido de Filestore en GiB (rangos por tier: los valida el módulo). | `number` | `1024` | no |
| <a name="input_filestore_tier"></a> [filestore\_tier](#input\_filestore\_tier) | Nivel de Filestore con CMEK: ZONAL (en la zona primary\_region-<filestore\_zone\_suffix>), REGIONAL o ENTERPRISE. | `string` | `"REGIONAL"` | no |
| <a name="input_filestore_zone_suffix"></a> [filestore\_zone\_suffix](#input\_filestore\_zone\_suffix) | Letra de la zona de primary\_region para Filestore ZONAL (por ejemplo, a). | `string` | `"a"` | no |
| <a name="input_gke_authenticator_security_group"></a> [gke\_authenticator\_security\_group](#input\_gke\_authenticator\_security\_group) | Grupo raíz de Google Groups for RBAC del clúster (gke-security-groups@<dominio>). Obligatorio con enable\_gke. | `string` | `null` | no |
| <a name="input_gke_lb_negs"></a> [gke\_lb\_negs](#input\_gke\_lb\_negs) | Backends de GKE para el balanceador externo. GKE crea los NEG zonales al desplegar un Service<br/>con la anotación cloud.google.com/neg (fuera de Terraform), así que sus self links se llenan<br/>después del primer despliegue de la carga y se aplica de nuevo. Vacío por defecto: sin backend<br/>de GKE en el balanceador.<br/>- primary: self links de los NEG zonales del clúster de la región primaria.<br/>- dr: los del clúster de DR (obligatorios con dr\_active si hay primary).<br/>- max\_rate\_per\_endpoint: solicitudes por segundo por endpoint (modo RATE).<br/>- health\_check\_path: ruta de la verificación de salud que crea el balanceador. | <pre>object({<br/>    primary               = optional(list(string), [])<br/>    dr                    = optional(list(string), [])<br/>    max_rate_per_endpoint = optional(number, 100)<br/>    health_check_path     = optional(string, "/healthz")<br/>  })</pre> | `{}` | no |
| <a name="input_gke_master_authorized_networks"></a> [gke\_master\_authorized\_networks](#input\_gke\_master\_authorized\_networks) | Rangos autorizados para llegar al plano de control privado de GKE (por ejemplo, el rango on-premises o una subred de administración). | <pre>list(object({<br/>    cidr_block   = string<br/>    display_name = string<br/>  }))</pre> | `[]` | no |
| <a name="input_gke_node_pools"></a> [gke\_node\_pools](#input\_gke\_node\_pools) | Pools de nodos de GKE (llave → configuración); mismo formato que el módulo gke. min\_node\_count y max\_node\_count son por zona. Obligatorio con enable\_gke. | <pre>map(object({<br/>    machine_type    = string<br/>    min_node_count  = number<br/>    max_node_count  = number<br/>    disk_size_gb    = optional(number, 100)<br/>    disk_type       = optional(string, "pd-balanced")<br/>    spot            = optional(bool, false)<br/>    node_locations  = optional(list(string))<br/>    max_surge       = optional(number, 1)<br/>    max_unavailable = optional(number, 0)<br/>    k8s_labels      = optional(map(string), {})<br/>    taints = optional(list(object({<br/>      key    = string<br/>      value  = string<br/>      effect = string<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_gke_release_channel"></a> [gke\_release\_channel](#input\_gke\_release\_channel) | Canal de versiones de GKE: RAPID, REGULAR o STABLE (sin RAPID en prod, lo valida el módulo). | `string` | `"REGULAR"` | no |
| <a name="input_internal_domain_names"></a> [internal\_domain\_names](#input\_internal\_domain\_names) | Dominios del certificado del balanceador interno (Certificate Manager con autorización DNS). Obligatorio con enable\_internal\_lb. | `list(string)` | `[]` | no |
| <a name="input_lb_backend_paths"></a> [lb\_backend\_paths](#input\_lb\_backend\_paths) | Rutas del mapa de URL por backend (llaves gke, mig o run → lista de rutas, por ejemplo { run = ["/api/*"] }). Las solicitudes sin ruta van a lb\_default\_backend. | `map(list(string))` | `{}` | no |
| <a name="input_lb_default_backend"></a> [lb\_default\_backend](#input\_lb\_default\_backend) | Backend por defecto del mapa de URL externo: gke, mig o run. null: el primero habilitado en el orden run, mig, gke. | `string` | `null` | no |
| <a name="input_memorystore_memory_gb"></a> [memorystore\_memory\_gb](#input\_memorystore\_memory\_gb) | Memoria de la instancia de Redis en GB (el tier lo decide el módulo: STANDARD\_HA en prod, BASIC fuera). | `number` | `5` | no |
| <a name="input_mig_health_check_path"></a> [mig\_health\_check\_path](#input\_mig\_health\_check\_path) | Ruta HTTP de la verificación de salud del MIG (autocuración y balanceadores). | `string` | `"/healthz"` | no |
| <a name="input_mig_http_port"></a> [mig\_http\_port](#input\_mig\_http\_port) | Puerto HTTP en el que sirven las VM (puerto con nombre http del grupo y de las verificaciones de salud). | `number` | `80` | no |
| <a name="input_mig_image"></a> [mig\_image](#input\_mig\_image) | Imagen endurecida de las VM del MIG (projects/<p>/global/images/<imagen> o .../images/family/<familia>). Sin valor por defecto público: obligatoria con enable\_mig. | `string` | `null` | no |
| <a name="input_mig_machine_type"></a> [mig\_machine\_type](#input\_mig\_machine\_type) | Tipo de máquina de las VM del MIG. | `string` | `"e2-standard-2"` | no |
| <a name="input_mig_max_replicas"></a> [mig\_max\_replicas](#input\_mig\_max\_replicas) | Máximo de VM del autoescalador. | `number` | `4` | no |
| <a name="input_mig_min_replicas"></a> [mig\_min\_replicas](#input\_mig\_min\_replicas) | Mínimo de VM del autoescalador (al menos 2 en prod, lo valida el módulo). | `number` | `2` | no |
| <a name="input_multi_region"></a> [multi\_region](#input\_multi\_region) | Multirregión del bucket de doble región con enable\_dr (anillo de llaves de la etapa 2 de esa ubicación). Debe contener primary\_region y dr\_region. | `string` | `"us"` | no |
| <a name="input_primary_region"></a> [primary\_region](#input\_primary\_region) | Región primaria (ADR 0002). | `string` | `"us-central1"` | no |
| <a name="input_region_codes"></a> [region\_codes](#input\_region\_codes) | Mapa región → código corto para los nombres (§4.2). | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_sql_database_version"></a> [sql\_database\_version](#input\_sql\_database\_version) | Versión de PostgreSQL de Cloud SQL (POSTGRES\_<n>). | `string` | `"POSTGRES_16"` | no |
| <a name="input_sql_databases"></a> [sql\_databases](#input\_sql\_databases) | Bases de datos que se crean en la instancia de Cloud SQL. | `list(string)` | <pre>[<br/>  "app"<br/>]</pre> | no |
| <a name="input_sql_tier"></a> [sql\_tier](#input\_sql\_tier) | Tipo de máquina de Cloud SQL (db-custom-* en edición ENTERPRISE). | `string` | `"db-custom-2-7680"` | no |
| <a name="input_subnet_cidrs"></a> [subnet\_cidrs](#input\_subnet\_cidrs) | Rangos reservados del plan de §5 que el spoke no publica como subred: gke\_master (obligatorio con enable\_gke) y gke\_master\_dr (obligatorio con enable\_gke y dr\_active), /28 para el plano de control de GKE. Puede ser el mismo mapa subnet\_cidrs de la etapa 3; las demás llaves se ignoran. | `map(string)` | `{}` | no |
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
| <a name="output_internal_lb_dns_authorization_records"></a> [internal\_lb\_dns\_authorization\_records](#output\_internal\_lb\_dns\_authorization\_records) | Registros DNS (name, type, data) que hay que crear para emitir el certificado del balanceador interno. |
| <a name="output_internal_lb_ip_address"></a> [internal\_lb\_ip\_address](#output\_internal\_lb\_ip\_address) | IP interna del balanceador interno regional (null sin enable\_internal\_lb). |
| <a name="output_lb_ip_address"></a> [lb\_ip\_address](#output\_lb\_ip\_address) | IP pública global del balanceador HTTPS externo (para los registros DNS A de domain\_names). null si no hay ningún backend habilitado. |
| <a name="output_mig_instance_groups"></a> [mig\_instance\_groups](#output\_mig\_instance\_groups) | Mapa región → URL del grupo de instancias del MIG (vacío con enable\_mig = false). |
| <a name="output_redis_host"></a> [redis\_host](#output\_redis\_host) | IP privada de Memorystore (null con enable\_memorystore = false). |
| <a name="output_sql_instance_connection_name"></a> [sql\_instance\_connection\_name](#output\_sql\_instance\_connection\_name) | Nombre de conexión de la instancia primaria de Cloud SQL (<proyecto>:<región>:<instancia>). |
| <a name="output_sql_replica_connection_name"></a> [sql\_replica\_connection\_name](#output\_sql\_replica\_connection\_name) | Nombre de conexión de la réplica de Cloud SQL en dr\_region (null sin enable\_dr). Se promueve en el runbook de conmutación. |
<!-- END_TF_DOCS -->
