# Módulo `memorystore`

Crea una instancia de Memorystore para Redis (`google_redis_instance`) con IP privada por
Private Service Access sobre la VPC del host de Shared VPC. La sección "Componentes del
datacenter" de la especificación pide para la caché IP privada, CMEK y alta disponibilidad en
prod; el módulo lo fija así:

- `connect_mode = "PRIVATE_SERVICE_ACCESS"` fijo, con `authorized_network` y el rango de PSA
  opcional (`reserved_ip_range`).
- CMEK obligatorio (`customer_managed_key`), con la llave de la región de la instancia.
- `tier`: STANDARD_HA por defecto en prod (réplica en otra zona y conmutación automática) y una
  validación rechaza BASIC en prod.
- Cifrado en tránsito fijo (`transit_encryption_mode = "SERVER_AUTHENTICATION"`): el puerto es
  6378 y los clientes validan el servidor con la salida `server_ca_certs`.
- Persistencia RDB por defecto (`rdb_snapshot_period`), ventana de mantenimiento y etiquetas.

## Decisión sobre AUTH

AUTH queda apagado y no es configurable. Con `auth_enabled = true`, GCP genera una cadena AUTH
que el proveedor guarda en el estado de Terraform (`auth_string`); el ADR 0015 prohíbe dejar
secretos generados en el estado, aunque el bucket esté cifrado. La caché se protege por otras
capas: solo IP privada en el rango de PSA del spoke, perímetro de VPC-SC en prod, reglas de
firewall de la VPC y TLS en tránsito. Si un caso de uso exigiera autenticación por cliente, la
alternativa sin secretos en el estado es Memorystore for Redis Cluster con autenticación IAM
(otro recurso, fuera de este módulo). La revisión CKV_GCP_95 se omite en el recurso con este
motivo.

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
| [google_redis_instance.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/redis_instance) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno: dev, qa o prod. | `string` | n/a | yes |
| <a name="input_kms_key"></a> [kms\_key](#input\_kms\_key) | ID de la llave KMS (CMEK) de la instancia; debe estar en la misma región que region. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes. Obligatorias: env, app, owner, cost\_center, managed\_by. | `map(string)` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | VPC de la Shared VPC autorizada, como ID o self link (projects/<host>/global/networks/<red>). La conexión es por Private Service Access. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (§4.2), por ejemplo bnt. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto de servicio donde se crea la instancia. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Región de la instancia. | `string` | n/a | yes |
| <a name="input_alternative_location_id"></a> [alternative\_location\_id](#input\_alternative\_location\_id) | Zona de la réplica en STANDARD\_HA; debe ser distinta de location\_id. Nulo: la elige GCP. | `string` | `null` | no |
| <a name="input_location_id"></a> [location\_id](#input\_location\_id) | Zona principal (por ejemplo us-central1-a). Nulo: la elige GCP. | `string` | `null` | no |
| <a name="input_maintenance_window"></a> [maintenance\_window](#input\_maintenance\_window) | Ventana de mantenimiento semanal: día (MONDAY … SUNDAY) y hora de inicio UTC (0-23). | <pre>object({<br/>    day  = string<br/>    hour = number<br/>  })</pre> | <pre>{<br/>  "day": "SUNDAY",<br/>  "hour": 7<br/>}</pre> | no |
| <a name="input_memory_gb"></a> [memory\_gb](#input\_memory\_gb) | Memoria de la instancia en GB. | `number` | `5` | no |
| <a name="input_name"></a> [name](#input\_name) | Parte <recurso> del nombre (§4.2). El nombre final es <prefix>-<environment>-data-<name>-<código de región> y no pasa de 40 caracteres. | `string` | `"redis"` | no |
| <a name="input_rdb_snapshot_period"></a> [rdb\_snapshot\_period](#input\_rdb\_snapshot\_period) | Periodo de las instantáneas RDB de persistencia: ONE\_HOUR, SIX\_HOURS, TWELVE\_HOURS o TWENTY\_FOUR\_HOURS. Nulo: sin persistencia. | `string` | `"TWELVE_HOURS"` | no |
| <a name="input_redis_configs"></a> [redis\_configs](#input\_redis\_configs) | Parámetros de Redis (por ejemplo maxmemory-policy). Ver la lista admitida por Memorystore. | `map(string)` | `{}` | no |
| <a name="input_redis_version"></a> [redis\_version](#input\_redis\_version) | Versión de Redis, por ejemplo REDIS\_7\_2. | `string` | `"REDIS_7_2"` | no |
| <a name="input_region_short_codes"></a> [region\_short\_codes](#input\_region\_short\_codes) | Mapa región → código corto que se agrega a los nombres (§4.2). | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_reserved_ip_range"></a> [reserved\_ip\_range](#input\_reserved\_ip\_range) | Nombre del rango de Private Service Access de donde se toma la IP (psa\_range\_name de la etapa 3). Nulo: cualquier rango de la conexión. | `string` | `null` | no |
| <a name="input_tier"></a> [tier](#input\_tier) | STANDARD\_HA (réplica en otra zona con conmutación automática) o BASIC. Nulo: STANDARD\_HA en prod y BASIC en dev y qa. En prod solo se acepta STANDARD\_HA. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_host"></a> [host](#output\_host) | IP privada del nodo primario de Redis. |
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | ID completo de la instancia (projects/<p>/locations/<región>/instances/<nombre>). |
| <a name="output_instance_name"></a> [instance\_name](#output\_instance\_name) | Nombre de la instancia de Redis. |
| <a name="output_port"></a> [port](#output\_port) | Puerto de Redis (6378 con TLS en tránsito). |
| <a name="output_server_ca_certs"></a> [server\_ca\_certs](#output\_server\_ca\_certs) | Certificados públicos de la CA del servidor, para que los clientes validen el TLS (no son secretos). |
<!-- END_TF_DOCS -->
