# Módulo `filestore`

Crea una instancia de Filestore con un recurso compartido NFS, conectada por Private Service
Access a la VPC del spoke de su entorno (proyecto único, sin Shared VPC; ADR 0029). La
sección "Componentes del datacenter" de la especificación pide para el almacenamiento de archivos CMEK y red por PSA; el módulo lo fija así:

- CMEK obligatorio (`kms_key_name`), en la misma región que la instancia.
- `tier` limitado a los niveles que admiten CMEK: `ZONAL`, `REGIONAL` y `ENTERPRISE` (los
  niveles básicos no lo admiten, según la documentación de Filestore consultada el 21 nov 2026).
- `connect_mode = "PRIVATE_SERVICE_ACCESS"` fijo, solo IPv4 privada, rango de PSA opcional
  (`reserved_ip_range`). `network` es la ruta completa de la red del spoke.
- `capacity_gb` validada por tier, con los rangos y pasos de la documentación de niveles de
  servicio.
- Reglas de exportación NFS opcionales (`ROOT_SQUASH` por defecto en cada regla), protección
  contra borrado obligatoria en prod y etiquetas.

`location` es una zona con `ZONAL` y una región con `REGIONAL` o `ENTERPRISE`. El módulo no
obliga a `REGIONAL` en prod porque la especificación no exige alta disponibilidad para
Filestore; `3-workloads` elige el tier.

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
| [google_filestore_instance.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/filestore_instance) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno: dev, qa o prod. | `string` | n/a | yes |
| <a name="input_kms_key"></a> [kms\_key](#input\_kms\_key) | ID de la llave KMS (CMEK) de la instancia; debe estar en la región de location. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes. Obligatorias: env, app, owner, cost\_center, managed\_by. | `map(string)` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Zona (us-central1-a) para ZONAL; región (us-central1) para REGIONAL y ENTERPRISE. | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | VPC del spoke del entorno, como ID o self link: projects/<proyecto>/global/networks/<red>. La conexión es por Private Service Access. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (§4.2), por ejemplo bnt. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto (único, ADR 0029) donde se crea la instancia. | `string` | n/a | yes |
| <a name="input_capacity_gb"></a> [capacity\_gb](#input\_capacity\_gb) | Capacidad del recurso compartido en GiB. ZONAL: 1024-9984 en pasos de 256 o 10240-102400 en pasos de 2560. REGIONAL: 100-10239 en pasos de 1 o 10240-102400 en pasos de 2560. ENTERPRISE: 1024-10240 en pasos de 256. | `number` | `1024` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Protección contra borrado de la instancia. En prod siempre debe ser true. | `bool` | `true` | no |
| <a name="input_name"></a> [name](#input\_name) | Parte <recurso> del nombre (§4.2). El nombre final es <prefix>-<environment>-data-<name>-<código de región>. | `string` | `"nfs"` | no |
| <a name="input_nfs_export_options"></a> [nfs\_export\_options](#input\_nfs\_export\_options) | Reglas de exportación NFS (hasta 10): rangos de IP de clientes, acceso y squash. Lista vacía: todos los clientes de la VPC con lectura y escritura (valor de GCP). | <pre>list(object({<br/>    ip_ranges   = list(string)<br/>    access_mode = optional(string, "READ_WRITE")<br/>    squash_mode = optional(string, "ROOT_SQUASH")<br/>    anon_uid    = optional(number)<br/>    anon_gid    = optional(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_region_short_codes"></a> [region\_short\_codes](#input\_region\_short\_codes) | Mapa región → código corto que se agrega a los nombres (§4.2). | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_reserved_ip_range"></a> [reserved\_ip\_range](#input\_reserved\_ip\_range) | Nombre del rango de Private Service Access de donde se toma la IP (psa\_range\_name de la etapa 3). Nulo: cualquier rango de la conexión. | `string` | `null` | no |
| <a name="input_share_name"></a> [share\_name](#input\_share\_name) | Nombre del recurso compartido NFS (letras, dígitos y guion bajo, hasta 16 caracteres). | `string` | `"data"` | no |
| <a name="input_tier"></a> [tier](#input\_tier) | Nivel de servicio con soporte de CMEK: ZONAL, REGIONAL o ENTERPRISE (los niveles BASIC\_HDD y BASIC\_SSD no admiten CMEK). | `string` | `"ZONAL"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | ID completo de la instancia (projects/<p>/locations/<ubicación>/instances/<nombre>). |
| <a name="output_instance_name"></a> [instance\_name](#output\_instance\_name) | Nombre de la instancia de Filestore. |
| <a name="output_ip_address"></a> [ip\_address](#output\_ip\_address) | IP privada del servidor NFS (dentro del rango de Private Service Access). |
| <a name="output_share_name"></a> [share\_name](#output\_share\_name) | Nombre del recurso compartido NFS (se monta como <ip\_address>:/<share\_name>). |
<!-- END_TF_DOCS -->
