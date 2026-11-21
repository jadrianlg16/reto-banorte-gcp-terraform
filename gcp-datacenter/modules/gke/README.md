# Módulo `gke`

Crea un clúster de GKE estándar y sus pools de nodos (`gke_node_pools`) en el proyecto de
servicio, sobre la VPC compartida del proyecto host (red y subred llegan como self links) y en
modo VPC nativo con los rangos secundarios con nombre de la subred. Cumple lo que la sección
"Componentes del datacenter" de la especificación exige al cómputo en contenedores, como
valores fijos y no como opciones: nodos privados, Workload Identity, Binary Authorization
(evaluación con la política del proyecto) y clúster regional en prod (validación de
`location`). Además fija Shielded nodes con arranque seguro y monitoreo de integridad, CMEK
para los secretos de Kubernetes (`database_encryption`) y para los discos de arranque de los
nodos, Dataplane V2, canal de versiones (sin `RAPID` en prod), pool por defecto eliminado,
pools con autoescalado, autorreparación y autoactualización, la cuenta de servicio dedicada de
los nodos (se rechaza la de Compute por defecto), metadatos de GKE (`GKE_METADATA`) y
protección contra borrado siempre activa en prod.

Decisión sobre el endpoint del plano de control: privado por defecto
(`enable_private_endpoint = true`), con acceso global dentro de la VPC y redes autorizadas por
variable. Terraform no lo necesita (la etapa 5 solo usa la API de Google), y `kubectl` llega
desde la VPC del spoke o desde los rangos de `master_authorized_networks`. Como el peering del
plano de control no es transitivo, desde el hub u on-premises hace falta un bastión en el
spoke o el endpoint basado en DNS de GKE (no construido). En prod el endpoint privado es
obligatorio (validación); en dev y qa se puede abrir el público, y entonces el módulo exige al
menos un rango autorizado y rechaza `/0`.

La llave KMS (`kms_key`, uso `gke` de la etapa 2) debe estar en la misma región que el
clúster, y la subred también. El agente de servicio de GKE del proyecto de servicio necesita
`roles/cloudkms.cryptoKeyEncrypterDecrypter` sobre la llave y el usuario de subred en el host
(los da la etapa 4). La política de Binary Authorization del proyecto no la crea este módulo.
Las reglas de firewall del spoke usan etiquetas seguras: `node_resource_manager_tags`
(`tagKeys/<id>` → `tagValues/<id>`, vacío por defecto) las pone en los nodos de todos los
pools, por ejemplo `lb_backend` para que el balanceador llegue a los NEG de GKE.

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
| [google_container_cluster.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/container_cluster) | resource |
| [google_container_node_pool.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/container_node_pool) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_authenticator_security_group"></a> [authenticator\_security\_group](#input\_authenticator\_security\_group) | Grupo raíz de Google Groups for RBAC (debe llamarse gke-security-groups@<dominio>). | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno: dev, qa o prod. | `string` | n/a | yes |
| <a name="input_gke_node_pools"></a> [gke\_node\_pools](#input\_gke\_node\_pools) | Pools de nodos (llave → configuración). min\_node\_count y max\_node\_count son por zona. La llave forma parte del nombre del pool. | <pre>map(object({<br/>    machine_type    = string<br/>    min_node_count  = number<br/>    max_node_count  = number<br/>    disk_size_gb    = optional(number, 100)<br/>    disk_type       = optional(string, "pd-balanced")<br/>    spot            = optional(bool, false)<br/>    node_locations  = optional(list(string))<br/>    max_surge       = optional(number, 1)<br/>    max_unavailable = optional(number, 0)<br/>    k8s_labels      = optional(map(string), {})<br/>    taints = optional(list(object({<br/>      key    = string<br/>      value  = string<br/>      effect = string<br/>    })), [])<br/>  }))</pre> | n/a | yes |
| <a name="input_kms_key"></a> [kms\_key](#input\_kms\_key) | ID de la llave KMS (uso gke) para cifrar los secretos de Kubernetes en la capa de aplicación y los discos de arranque de los nodos. Debe estar en la misma región que el clúster. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes. Obligatorias: env, app, owner, cost\_center, managed\_by. | `map(string)` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Ubicación del clúster: una región (clúster regional) o una zona (clúster zonal, solo fuera de prod). | `string` | n/a | yes |
| <a name="input_master_cidr"></a> [master\_cidr](#input\_master\_cidr) | Rango /28 privado del plano de control (llave gke\_master de §5). | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | Self link (o ruta projects/<host>/global/networks/<red>) de la VPC compartida del proyecto host. | `string` | n/a | yes |
| <a name="input_node_service_account"></a> [node\_service\_account](#input\_node\_service\_account) | Correo de la cuenta de servicio dedicada de los nodos (uso gke\_nodes de la etapa 4). No se admite la cuenta de Compute por defecto. | `string` | n/a | yes |
| <a name="input_pods_range"></a> [pods\_range](#input\_pods\_range) | Nombre del rango secundario de la subred para los pods (VPC nativa). | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (por ejemplo, bnt). | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto de servicio donde se crea el clúster. | `string` | n/a | yes |
| <a name="input_services_range"></a> [services\_range](#input\_services\_range) | Nombre del rango secundario de la subred para los servicios (VPC nativa). | `string` | n/a | yes |
| <a name="input_subnet"></a> [subnet](#input\_subnet) | Self link (o ruta projects/<host>/regions/<región>/subnetworks/<subred>) de la subred compartida donde viven los nodos. | `string` | n/a | yes |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Protección contra borrado fuera de prod. En prod siempre es true, sin importar este valor (salvo teardown). | `bool` | `false` | no |
| <a name="input_enable_backup_agent"></a> [enable\_backup\_agent](#input\_enable\_backup\_agent) | Habilita el complemento de Backup for GKE (lo necesita el plan de respaldo del módulo backup-dr). | `bool` | `true` | no |
| <a name="input_enable_private_endpoint"></a> [enable\_private\_endpoint](#input\_enable\_private\_endpoint) | Si es true, el plano de control solo tiene IP privada (sin endpoint público). Si es false (solo dev y qa), el endpoint público queda limitado a master\_authorized\_networks, que no puede estar vacío. | `bool` | `true` | no |
| <a name="input_maintenance_start_time"></a> [maintenance\_start\_time](#input\_maintenance\_start\_time) | Hora de inicio (UTC, HH:MM) de la ventana diaria de mantenimiento. | `string` | `"08:00"` | no |
| <a name="input_master_authorized_networks"></a> [master\_authorized\_networks](#input\_master\_authorized\_networks) | Rangos autorizados para llegar al plano de control (por ejemplo, la subred de administración o el rango on-premises). | <pre>list(object({<br/>    cidr_block   = string<br/>    display_name = string<br/>  }))</pre> | `[]` | no |
| <a name="input_name"></a> [name](#input\_name) | Identificador corto de la carga dentro del nombre del clúster (<prefix>-<environment>-app-<name>-<región>). | `string` | `"gke"` | no |
| <a name="input_node_resource_manager_tags"></a> [node\_resource\_manager\_tags](#input\_node\_resource\_manager\_tags) | Etiquetas seguras de los nodos de todos los pools (tagKeys/<id> → tagValues/<id>), por ejemplo la de lb\_backend de la etapa 3. Vacío: sin etiquetas seguras. | `map(string)` | `{}` | no |
| <a name="input_region_codes"></a> [region\_codes](#input\_region\_codes) | Mapa región → código corto que se agrega a los nombres (§4.2 del contrato). | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_release_channel"></a> [release\_channel](#input\_release\_channel) | Canal de versiones de GKE: RAPID, REGULAR o STABLE. En prod no se admite RAPID. | `string` | `"REGULAR"` | no |
| <a name="input_teardown"></a> [teardown](#input\_teardown) | Retiro deliberado del clúster: deletion\_protection = false también en prod, para que un apply posterior lo pueda destruir. Solo para una instancia que se va a quitar (el clúster de DR en la vuelta a la región primaria, runbook 04); nunca en el clúster que atiende el tráfico normal. | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | ID del clúster (projects/<p>/locations/<l>/clusters/<nombre>); lo usa backup-dr como gke\_cluster\_id. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Nombre del clúster. |
| <a name="output_deletion_protection"></a> [deletion\_protection](#output\_deletion\_protection) | Protección contra borrado efectiva del clúster (true en prod salvo teardown). |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | IP del plano de control (privada si enable\_private\_endpoint = true). |
| <a name="output_kms_key"></a> [kms\_key](#output\_kms\_key) | Llave KMS del cifrado de secretos de Kubernetes en la capa de aplicación. |
| <a name="output_location"></a> [location](#output\_location) | Ubicación del clúster (región si es regional). |
| <a name="output_master_cidr"></a> [master\_cidr](#output\_master\_cidr) | Rango /28 del plano de control configurado en el clúster (private\_cluster\_config.master\_ipv4\_cidr\_block). |
| <a name="output_node_pool_names"></a> [node\_pool\_names](#output\_node\_pool\_names) | Mapa llave de gke\_node\_pools → nombre del pool de nodos. |
| <a name="output_subnetwork"></a> [subnetwork](#output\_subnetwork) | Subred del clúster (la configurada en el recurso). |
| <a name="output_workload_pool"></a> [workload\_pool](#output\_workload\_pool) | Pool de Workload Identity (<proyecto>.svc.id.goog) para enlazar cuentas de Kubernetes con cuentas de servicio. |
<!-- END_TF_DOCS -->
