# Módulo `compute-mig`

Crea, en el proyecto único (ADR 0029), una plantilla regional de instancias, un grupo de instancias
administrado (MIG) regional con autocuración y actualización progresiva, su autoescalador
regional y una verificación de salud global. Cumple lo que la sección "Componentes del
datacenter" de la especificación exige a las cargas en VM, como valores fijos: Shielded VM
(arranque seguro, vTPM y monitoreo de integridad), imagen endurecida por variable (sin valor
por defecto; en prod se rechazan las imágenes públicas base de Google), autoescalado
(`min_replicas` <= `max_replicas`, y al menos 2 en prod) con autocuración, y sin IP pública
(la interfaz no tiene `access_config` ni `ipv6_access_config` y es `stack_type = "IPV4_ONLY"`). Además fija el cifrado CMEK del disco de arranque con
`kms_key` (uso `compute` de `1-base`, en la misma región), la cuenta de servicio dedicada (se
rechaza la de Compute por defecto), OS Login, bloqueo de llaves SSH del proyecto y puerto
serie apagado, y expone puertos con nombre para el balanceador.

La subred llega como self link de la VPC del spoke, en el mismo proyecto (sin Shared VPC). La
salida `instance_group` es el backend que recibe el módulo `load-balancer`; la verificación de
salud es global y sirve a la autocuración (un balanceador interno regional crea la suya). El
agente de servicio de Compute necesita `roles/cloudkms.cryptoKeyEncrypterDecrypter` sobre la
llave, que da `1-base` (`kms.tf`). Las reglas de firewall del spoke usan etiquetas seguras: se
pasan en `resource_manager_tags` como `tagKeys/<id>` → `tagValues/<id>`.

Apagado fuera de horario (ADR 0028, solo dev y qa; se rechaza en prod): con `business_hours`
el autoescalador usa un programa de escalado (`business-hours`) como única señal, con
`min_replicas = 0`: durante el horario exige `min_replicas` VM y fuera de él el grupo baja a 0.
No hay autoescalado por CPU mientras `business_hours` esté puesto. Es declarativo (sin
trabajos ni deriva). Como `cpu_utilization` es Optional+Computed en el proveedor, cambiar entre
la señal de CPU y el programa reemplaza el autoescalador (`replace_triggered_by`) en vez de
actualizarlo. La salida `autoscaling` resume la política.

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
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [google_compute_health_check.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_health_check) | resource |
| [google_compute_region_autoscaler.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_autoscaler) | resource |
| [google_compute_region_instance_group_manager.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_instance_group_manager) | resource |
| [google_compute_region_instance_template.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_instance_template) | resource |
| [terraform_data.autoscaler_signal](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno: dev, qa o prod. | `string` | n/a | yes |
| <a name="input_image"></a> [image](#input\_image) | Imagen endurecida del disco de arranque: projects/<p>/global/images/<imagen> o projects/<p>/global/images/family/<familia>. Sin valor por defecto: la elige quien llama. En prod no se admiten las imágenes públicas sin endurecer de Google. | `string` | n/a | yes |
| <a name="input_kms_key"></a> [kms\_key](#input\_kms\_key) | ID de la llave KMS (uso compute) que cifra los discos de arranque. Debe estar en la misma región que el MIG. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes. Obligatorias: env, app, owner, cost\_center, managed\_by. | `map(string)` | n/a | yes |
| <a name="input_machine_type"></a> [machine\_type](#input\_machine\_type) | Tipo de máquina de las instancias (por ejemplo, e2-standard-2). | `string` | n/a | yes |
| <a name="input_max_replicas"></a> [max\_replicas](#input\_max\_replicas) | Máximo de instancias del autoescalador; no puede ser menor que min\_replicas. | `number` | n/a | yes |
| <a name="input_min_replicas"></a> [min\_replicas](#input\_min\_replicas) | Mínimo de instancias del autoescalador. En prod, al menos 2. Con business\_hours es el número de VM durante el horario encendido (fuera de él, 0). | `number` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (por ejemplo, bnt). | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto (único, ADR 0029) donde se crean la plantilla, el MIG y el autoescalador. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Región del MIG regional (primaria, o la de DR durante una conmutación). | `string` | n/a | yes |
| <a name="input_service_account"></a> [service\_account](#input\_service\_account) | Correo de la cuenta de servicio dedicada de las instancias (uso mig, la crea 1-base). No se admite la cuenta de Compute por defecto. | `string` | n/a | yes |
| <a name="input_subnet"></a> [subnet](#input\_subnet) | Self link (o ruta projects/<proyecto>/regions/<región>/subnetworks/<subred>) de la subred del spoke del entorno. | `string` | n/a | yes |
| <a name="input_business_hours"></a> [business\_hours](#input\_business\_hours) | Apagado fuera de horario (solo dev y qa, ADR 0028): programa de escalado del autoescalador con el cron de encendido (schedule), su duración en segundos (duration\_sec) y su zona horaria IANA (time\_zone). Durante el programa el MIG tiene min\_replicas VM; fuera de él, 0. En este modo no hay señal de CPU: un autoescalador por CPU no puede bajar a 0. null: autoescalado por CPU sin horario. | <pre>object({<br/>    schedule     = string<br/>    duration_sec = number<br/>    time_zone    = string<br/>  })</pre> | `null` | no |
| <a name="input_cooldown_period"></a> [cooldown\_period](#input\_cooldown\_period) | Segundos que el autoescalador espera tras iniciar una instancia antes de leer sus métricas. | `number` | `120` | no |
| <a name="input_cpu_target"></a> [cpu\_target](#input\_cpu\_target) | Uso de CPU objetivo del autoescalador (entre 0.1 y 0.9). | `number` | `0.6` | no |
| <a name="input_disk_size_gb"></a> [disk\_size\_gb](#input\_disk\_size\_gb) | Tamaño del disco de arranque en GB. | `number` | `50` | no |
| <a name="input_disk_type"></a> [disk\_type](#input\_disk\_type) | Tipo del disco de arranque. | `string` | `"pd-balanced"` | no |
| <a name="input_distribution_zones"></a> [distribution\_zones](#input\_distribution\_zones) | Zonas de la región donde se reparten las instancias. Vacío: GCP elige tres zonas. | `list(string)` | `[]` | no |
| <a name="input_health_check"></a> [health\_check](#input\_health\_check) | Verificación de salud para la autocuración: protocolo (HTTP, HTTPS o TCP), puerto, ruta (HTTP/HTTPS), umbrales y retraso inicial. | <pre>object({<br/>    protocol            = optional(string, "HTTP")<br/>    port                = optional(number, 80)<br/>    request_path        = optional(string, "/healthz")<br/>    check_interval_sec  = optional(number, 10)<br/>    timeout_sec         = optional(number, 5)<br/>    healthy_threshold   = optional(number, 2)<br/>    unhealthy_threshold = optional(number, 3)<br/>    initial_delay_sec   = optional(number, 300)<br/>  })</pre> | `{}` | no |
| <a name="input_metadata"></a> [metadata](#input\_metadata) | Metadatos adicionales de las instancias (por ejemplo, startup-script). No pueden cambiar enable-oslogin, block-project-ssh-keys ni serial-port-enable. | `map(string)` | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | Identificador corto de la carga dentro de los nombres (<prefix>-<environment>-app-<name>-<región>). | `string` | `"mig"` | no |
| <a name="input_named_ports"></a> [named\_ports](#input\_named\_ports) | Puertos con nombre del grupo (nombre → puerto) que usa el servicio de backend del balanceador. | `map(number)` | <pre>{<br/>  "http": 80<br/>}</pre> | no |
| <a name="input_network_tags"></a> [network\_tags](#input\_network\_tags) | Etiquetas de red de las instancias (las reglas de firewall del spoke usan etiquetas seguras; ver resource\_manager\_tags). | `list(string)` | `[]` | no |
| <a name="input_region_codes"></a> [region\_codes](#input\_region\_codes) | Mapa región → código corto que se agrega a los nombres (§4.2 del contrato). | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_resource_manager_tags"></a> [resource\_manager\_tags](#input\_resource\_manager\_tags) | Etiquetas seguras de las instancias (tagKeys/<id> → tagValues/<id>), por ejemplo la de lb\_backend de la etapa 3. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_autoscaling"></a> [autoscaling](#output\_autoscaling) | Política configurada del autoescalador: min\_replicas, max\_replicas, señal (cpu o schedule con business\_hours) y programas de escalado (nombre → cron, zona horaria, duración en segundos y VM requeridas). |
| <a name="output_health_check_id"></a> [health\_check\_id](#output\_health\_check\_id) | ID de la verificación de salud global de la autocuración. |
| <a name="output_health_check_self_link"></a> [health\_check\_self\_link](#output\_health\_check\_self\_link) | Self link de la verificación de salud global. |
| <a name="output_instance_group"></a> [instance\_group](#output\_instance\_group) | URL del grupo de instancias del MIG regional; es el backend que recibe el módulo load-balancer. |
| <a name="output_instance_group_manager_id"></a> [instance\_group\_manager\_id](#output\_instance\_group\_manager\_id) | ID del MIG regional. |
| <a name="output_instance_group_manager_name"></a> [instance\_group\_manager\_name](#output\_instance\_group\_manager\_name) | Nombre del MIG regional. |
| <a name="output_instance_template_self_link"></a> [instance\_template\_self\_link](#output\_instance\_template\_self\_link) | Self link de la plantilla de instancias vigente. |
| <a name="output_kms_key"></a> [kms\_key](#output\_kms\_key) | Llave KMS del disco de arranque de la plantilla. |
| <a name="output_named_ports"></a> [named\_ports](#output\_named\_ports) | Puertos con nombre del grupo (nombre → puerto). |
| <a name="output_subnetwork"></a> [subnetwork](#output\_subnetwork) | Subred de la interfaz de la plantilla (la que se configuró en el recurso). |
<!-- END_TF_DOCS -->
