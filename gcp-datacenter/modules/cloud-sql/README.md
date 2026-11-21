# Módulo `cloud-sql`

Crea una instancia de Cloud SQL para PostgreSQL con IP privada únicamente (Private Service
Access de la VPC del spoke, sin IPv4 pública ni redes autorizadas), sus bases de datos, los
usuarios con autenticación IAM y, con `enable_dr = true`, una réplica de lectura en la región
de DR. La sección "Componentes del datacenter" de la especificación pide para la base de datos
IP privada, alta disponibilidad regional en prod, recuperación a un punto en el tiempo, réplica
en la región secundaria, SSL obligatorio, CMEK y autenticación IAM; el módulo lo deja como
valores fijos o validaciones:

- `ipv4_enabled = false` y `private_network` fijos; `allocated_ip_range` opcional para tomar la
  IP del rango de PSA de la etapa 3.
- `availability_type`: REGIONAL por defecto en prod y una validación rechaza ZONAL en prod. La
  réplica usa la misma disponibilidad que la primaria.
- Respaldos diarios y PITR siempre activos (`retained_backups`, `transaction_log_retention_days`).
- `ssl_mode` validado: `TRUSTED_CLIENT_CERTIFICATE_REQUIRED` (por defecto, compatible con los
  conectores de Cloud SQL y la autenticación IAM) o `ENCRYPTED_ONLY`; nunca sin cifrado.
- CMEK obligatorio: `kms_key` en la región primaria y `dr_kms_key` en `dr_region` (obligatoria
  con `enable_dr`). Las llaves llegan de la etapa 2 por entorno, ubicación y uso `sql`.
- Sin contraseñas (ADR 0015): bandera `cloudsql.iam_authentication = on`, usuarios
  `CLOUD_IAM_USER`, `CLOUD_IAM_SERVICE_ACCOUNT` o `CLOUD_IAM_GROUP`, ningún `root_password` y
  ningún usuario integrado con contraseña generada. El usuario predeterminado `postgres` que crea
  GCP queda sin contraseña y no se usa.
- Banderas de auditoría fijas en la primaria y la réplica (pgAudit y los `log_*` que exige el
  análisis estático); `additional_database_flags` no puede reemplazarlas.
- `deletion_protection` (en Terraform y en la API) obligatorio en prod; etiquetas en
  `settings.user_labels`.

Roles de entrada: con `grant_iam_login_roles = true` el módulo otorga `roles/cloudsql.client` y
`roles/cloudsql.instanceUser`, condicionados a esta instancia y su réplica, a los usuarios de
tipo cuenta de servicio y grupo. Los `CLOUD_IAM_USER` no reciben roles directos (ningún rol a
`user:`): los obtienen por su grupo.

pgAudit: la bandera activa la extensión a nivel de instancia; cada base necesita
`CREATE EXTENSION pgaudit;`, que se ejecuta fuera de Terraform (no hay proveedor de PostgreSQL
en el repositorio).

## Cómo apoya el objetivo de RPO de 15 minutos

El módulo no demuestra el RPO; aporta dos mecanismos que lo hacen alcanzable:

1. La réplica entre regiones (`enable_dr = true`) recibe los cambios por replicación asíncrona.
   Si se pierde la región primaria, la réplica se promueve y la pérdida es el retraso de
   replicación en ese momento, que en operación normal suele ser de segundos, pero se mide en el
   apply y se vigila con la métrica de retraso de réplica (módulo `observability`).
2. PITR conserva los registros de transacciones (`transaction_log_retention_days`) para
   restaurar a un instante concreto ante corrupción lógica, que la réplica copiaría.

Si el retraso medido supera 15 minutos, el objetivo no se cumple: es una verificación del
primer apply (marcada `VERIFICAR-EN-APPLY` en `main.tf`).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [google_project_iam_member.login](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_sql_database.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_database) | resource |
| [google_sql_database_instance.replica](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_database_instance) | resource |
| [google_sql_database_instance.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_database_instance) | resource |
| [google_sql_user.iam](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_user) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno: dev, qa o prod. | `string` | n/a | yes |
| <a name="input_kms_key"></a> [kms\_key](#input\_kms\_key) | ID de la llave KMS (CMEK) de la instancia primaria; debe estar en la misma región que region. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes. Obligatorias: env, app, owner, cost\_center, managed\_by. | `map(string)` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | VPC de la Shared VPC donde vive la IP privada, como ID o self link (projects/<host>/global/networks/<red>). | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (§4.2), por ejemplo bnt. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto de servicio donde se crea la instancia. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Región primaria de la instancia. | `string` | n/a | yes |
| <a name="input_additional_database_flags"></a> [additional\_database\_flags](#input\_additional\_database\_flags) | Banderas de PostgreSQL adicionales. No pueden reemplazar las banderas obligatorias de autenticación IAM y auditoría que fija el módulo. | `map(string)` | `{}` | no |
| <a name="input_allocated_ip_range"></a> [allocated\_ip\_range](#input\_allocated\_ip\_range) | Nombre del rango de Private Service Access de donde se toma la IP (psa\_range\_name de la etapa 3). Nulo: cualquier rango de la conexión. | `string` | `null` | no |
| <a name="input_availability_type"></a> [availability\_type](#input\_availability\_type) | REGIONAL (alta disponibilidad) o ZONAL. Nulo: REGIONAL en prod y ZONAL en dev y qa. En prod solo se acepta REGIONAL. | `string` | `null` | no |
| <a name="input_backup_location"></a> [backup\_location](#input\_backup\_location) | Ubicación de los respaldos (región o multirregión). Nulo: la multirregión más cercana a la instancia. | `string` | `null` | no |
| <a name="input_backup_start_time"></a> [backup\_start\_time](#input\_backup\_start\_time) | Hora de inicio del respaldo diario, HH:MM en UTC. | `string` | `"06:00"` | no |
| <a name="input_database_version"></a> [database\_version](#input\_database\_version) | Versión de PostgreSQL (por ejemplo POSTGRES\_16). El módulo solo admite PostgreSQL: sus banderas de auditoría son de PostgreSQL. | `string` | `"POSTGRES_16"` | no |
| <a name="input_databases"></a> [databases](#input\_databases) | Bases de datos que se crean en la instancia. | `list(string)` | `[]` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Protección contra borrado (en Terraform y en la API). En prod siempre debe ser true. | `bool` | `true` | no |
| <a name="input_disk_autoresize_limit_gb"></a> [disk\_autoresize\_limit\_gb](#input\_disk\_autoresize\_limit\_gb) | Límite del crecimiento automático del disco en GB; 0 es sin límite. | `number` | `0` | no |
| <a name="input_disk_size_gb"></a> [disk\_size\_gb](#input\_disk\_size\_gb) | Tamaño inicial del disco en GB; crece solo (disk\_autoresize). | `number` | `20` | no |
| <a name="input_dr_kms_key"></a> [dr\_kms\_key](#input\_dr\_kms\_key) | ID de la llave KMS de la réplica en DR; obligatoria con enable\_dr = true y en la misma ubicación que dr\_region. | `string` | `null` | no |
| <a name="input_dr_region"></a> [dr\_region](#input\_dr\_region) | Región de DR para la réplica de lectura. Obligatoria con enable\_dr = true. | `string` | `null` | no |
| <a name="input_edition"></a> [edition](#input\_edition) | Edición de Cloud SQL: ENTERPRISE (tipos db-custom-*) o ENTERPRISE\_PLUS (tipos db-perf-optimized-*). | `string` | `"ENTERPRISE"` | no |
| <a name="input_enable_dr"></a> [enable\_dr](#input\_enable\_dr) | Crea una réplica de lectura entre regiones en dr\_region, cifrada con dr\_kms\_key. | `bool` | `false` | no |
| <a name="input_grant_iam_login_roles"></a> [grant\_iam\_login\_roles](#input\_grant\_iam\_login\_roles) | Otorga roles/cloudsql.client y roles/cloudsql.instanceUser (condicionados a esta instancia) a los usuarios IAM de tipo cuenta de servicio y grupo. Los CLOUD\_IAM\_USER nunca reciben roles directos: los obtienen por su grupo (§7.1). | `bool` | `true` | no |
| <a name="input_iam_users"></a> [iam\_users](#input\_iam\_users) | Usuarios de base de datos con autenticación IAM. type: CLOUD\_IAM\_USER, CLOUD\_IAM\_SERVICE\_ACCOUNT o CLOUD\_IAM\_GROUP. Sin contraseñas (ADR 0015). | <pre>list(object({<br/>    email = string<br/>    type  = string<br/>  }))</pre> | `[]` | no |
| <a name="input_maintenance_window"></a> [maintenance\_window](#input\_maintenance\_window) | Ventana de mantenimiento: día (1 = lunes … 7 = domingo), hora UTC (0-23) y canal (stable o canary). | <pre>object({<br/>    day          = number<br/>    hour         = number<br/>    update_track = optional(string, "stable")<br/>  })</pre> | <pre>{<br/>  "day": 7,<br/>  "hour": 7<br/>}</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | Parte <recurso> del nombre (§4.2). El nombre final es <prefix>-<environment>-data-<name>-<código de región>. | `string` | `"sql"` | no |
| <a name="input_pgaudit_log"></a> [pgaudit\_log](#input\_pgaudit\_log) | Clases de sentencias que registra pgAudit (bandera pgaudit.log), separadas por coma. La extensión se activa con CREATE EXTENSION pgaudit en cada base. | `string` | `"ddl,role,write"` | no |
| <a name="input_region_short_codes"></a> [region\_short\_codes](#input\_region\_short\_codes) | Mapa región → código corto que se agrega a los nombres (§4.2). | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_retained_backups"></a> [retained\_backups](#input\_retained\_backups) | Número de respaldos diarios que se conservan. | `number` | `30` | no |
| <a name="input_sql_tier"></a> [sql\_tier](#input\_sql\_tier) | Tipo de máquina de Cloud SQL (por ejemplo db-custom-2-7680). Debe ser compatible con edition. | `string` | `"db-custom-2-7680"` | no |
| <a name="input_ssl_mode"></a> [ssl\_mode](#input\_ssl\_mode) | Modo de SSL de las conexiones. TRUSTED\_CLIENT\_CERTIFICATE\_REQUIRED funciona con los conectores de Cloud SQL y la autenticación IAM; ENCRYPTED\_ONLY exige TLS sin certificado de cliente. | `string` | `"TRUSTED_CLIENT_CERTIFICATE_REQUIRED"` | no |
| <a name="input_transaction_log_retention_days"></a> [transaction\_log\_retention\_days](#input\_transaction\_log\_retention\_days) | Días de registros de transacciones para la recuperación a un punto en el tiempo (hasta 7 en ENTERPRISE, hasta 35 en ENTERPRISE\_PLUS). | `number` | `7` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_connection_name"></a> [connection\_name](#output\_connection\_name) | Nombre de conexión de la primaria (<proyecto>:<región>:<instancia>) para los conectores de Cloud SQL. |
| <a name="output_database_names"></a> [database\_names](#output\_database\_names) | Bases de datos creadas. |
| <a name="output_iam_user_names"></a> [iam\_user\_names](#output\_iam\_user\_names) | Mapa correo → nombre del usuario de base de datos (las cuentas de servicio van sin .gserviceaccount.com). |
| <a name="output_instance_name"></a> [instance\_name](#output\_instance\_name) | Nombre de la instancia primaria. |
| <a name="output_private_ip"></a> [private\_ip](#output\_private\_ip) | IP privada de la primaria dentro del rango de Private Service Access. |
| <a name="output_replica_connection_name"></a> [replica\_connection\_name](#output\_replica\_connection\_name) | Nombre de conexión de la réplica en DR; null si enable\_dr = false. |
| <a name="output_replica_name"></a> [replica\_name](#output\_replica\_name) | Nombre de la réplica de lectura en DR; null si enable\_dr = false. |
| <a name="output_replica_private_ip"></a> [replica\_private\_ip](#output\_replica\_private\_ip) | IP privada de la réplica en DR; null si enable\_dr = false. |
<!-- END_TF_DOCS -->
