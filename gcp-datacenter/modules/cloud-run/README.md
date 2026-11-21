# Módulo `cloud-run`

Crea, en el proyecto de servicio, un servicio de Cloud Run v2 con salida directa a la VPC
compartida del proyecto host (red y subred llegan como self links y se convierten en rutas de
recurso), los permisos de invocador explícitos y el NEG sin servidor que el balanceador usa
como backend. Cumple lo que la sección "Componentes del datacenter" de la especificación exige
a los servicios sin estado, como valores fijos: solo tráfico interno y del balanceador
(`INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER`) y cuenta de servicio propia (se rechaza la de
Compute por defecto). Además fija CMEK (`encryption_key`, llave en la misma región), la
verificación de IAM del invocador activa y nunca invocadores públicos (`invokers` rechaza
`allUsers`, `allAuthenticatedUsers` y `user:`), secretos solo por referencia a Secret Manager,
Binary Authorization con la política del proyecto, imagen con etiqueta fija o digest en prod
y protección contra borrado siempre activa en prod.

El NEG vive en este módulo y sale como `neg_id`: el módulo `load-balancer` recibe backends
genéricos y no necesita saber que el backend es Cloud Run. Por defecto la verificación de IAM
sigue activa y quien llegue por el balanceador necesita `roles/run.invoker`: con IAP en el
servicio de backend se da al agente de servicio de IAP por `invokers`; sin IAP, los clientes
deben mandar un token de identidad. Cuando el servicio es backend del balanceador HTTPS externo
y sirve tráfico público, `public_via_load_balancer = true` desactiva la verificación de IAM del
invocador (`invoker_iam_disabled = true`) sin tocar la entrada, que sigue fija en interno y
balanceador, y sin conceder `allUsers` (lo impide `iam.allowedPolicyMemberDomains`); el control
de acceso queda en el balanceador y Cloud Armor (ADR 0020). Para la salida directa a la VPC, el agente de servicio de Cloud Run del
proyecto de servicio necesita el usuario de subred en el host, y para CMEK,
`roles/cloudkms.cryptoKeyEncrypterDecrypter` sobre la llave (los da la etapa 4).

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
| [google_cloud_run_v2_service.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service) | resource |
| [google_cloud_run_v2_service_iam_member.invoker](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service_iam_member) | resource |
| [google_compute_region_network_endpoint_group.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_network_endpoint_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno: dev, qa o prod. | `string` | n/a | yes |
| <a name="input_image"></a> [image](#input\_image) | Imagen del contenedor (por ejemplo, <región>-docker.pkg.dev/<proyecto>/<repo>/<imagen>@sha256:<digest>). En prod no se admite la etiqueta latest. | `string` | n/a | yes |
| <a name="input_kms_key"></a> [kms\_key](#input\_kms\_key) | ID de la llave KMS (CMEK) que cifra la imagen y los datos del servicio. Debe estar en la misma región que el servicio. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes. Obligatorias: env, app, owner, cost\_center, managed\_by. | `map(string)` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | Self link (o ruta projects/<host>/global/networks/<red>) de la VPC compartida del proyecto host, para la salida directa a la VPC. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (por ejemplo, bnt). | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto de servicio donde se crean el servicio y su NEG sin servidor. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Región del servicio (primaria, o la de DR durante una conmutación). | `string` | n/a | yes |
| <a name="input_service_account"></a> [service\_account](#input\_service\_account) | Correo de la cuenta de servicio propia del servicio (uso run de la etapa 4). No se admite la cuenta de Compute por defecto. | `string` | n/a | yes |
| <a name="input_subnet"></a> [subnet](#input\_subnet) | Self link (o ruta projects/<host>/regions/<región>/subnetworks/<subred>) de la subred compartida de Cloud Run (llave run de §5). | `string` | n/a | yes |
| <a name="input_concurrency"></a> [concurrency](#input\_concurrency) | Solicitudes simultáneas máximas por instancia. | `number` | `80` | no |
| <a name="input_container_port"></a> [container\_port](#input\_container\_port) | Puerto en el que escucha el contenedor. | `number` | `8080` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Límite de CPU del contenedor (por ejemplo, 1 o 2). | `string` | `"1"` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Protección contra borrado fuera de prod. En prod siempre es true, sin importar este valor. | `bool` | `false` | no |
| <a name="input_enable_binary_authorization"></a> [enable\_binary\_authorization](#input\_enable\_binary\_authorization) | Aplica la política de Binary Authorization del proyecto a las revisiones del servicio. | `bool` | `true` | no |
| <a name="input_env_vars"></a> [env\_vars](#input\_env\_vars) | Variables de entorno sin secretos (nombre → valor). Los secretos van en secret\_env. | `map(string)` | `{}` | no |
| <a name="input_health_check_path"></a> [health\_check\_path](#input\_health\_check\_path) | Ruta HTTP de las sondas de arranque y de vida del contenedor. null: solo la sonda TCP de arranque por defecto de Cloud Run. | `string` | `null` | no |
| <a name="input_invokers"></a> [invokers](#input\_invokers) | Principales que reciben roles/run.invoker (serviceAccount:, group: o domain:). Nunca allUsers, allAuthenticatedUsers ni user:. | `list(string)` | `[]` | no |
| <a name="input_max_instances"></a> [max\_instances](#input\_max\_instances) | Máximo de instancias del servicio; no puede ser menor que min\_instances. | `number` | `10` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Límite de memoria del contenedor (por ejemplo, 512Mi o 1Gi). | `string` | `"512Mi"` | no |
| <a name="input_min_instances"></a> [min\_instances](#input\_min\_instances) | Mínimo de instancias del servicio. | `number` | `0` | no |
| <a name="input_name"></a> [name](#input\_name) | Identificador corto del servicio dentro de los nombres (<prefix>-<environment>-app-<name>-<región>). | `string` | `"run"` | no |
| <a name="input_network_tags"></a> [network\_tags](#input\_network\_tags) | Etiquetas de red de la salida directa a la VPC (para reglas de firewall). | `list(string)` | `[]` | no |
| <a name="input_public_via_load_balancer"></a> [public\_via\_load\_balancer](#input\_public\_via\_load\_balancer) | Si es true, el servicio es backend del balanceador HTTPS externo y recibe tráfico público: se desactiva la verificación de IAM del invocador (invoker\_iam\_disabled = true). La entrada sigue fija en interno y balanceador y nunca se concede allUsers (ADR 0020); el control de acceso queda en el balanceador y Cloud Armor. | `bool` | `false` | no |
| <a name="input_region_codes"></a> [region\_codes](#input\_region\_codes) | Mapa región → código corto que se agrega a los nombres (§4.2 del contrato). | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_request_timeout"></a> [request\_timeout](#input\_request\_timeout) | Tiempo máximo de una solicitud, en segundos con sufijo s (por ejemplo, 300s). | `string` | `"300s"` | no |
| <a name="input_secret_env"></a> [secret\_env](#input\_secret\_env) | Variables de entorno leídas de Secret Manager (nombre → { secret, version }). secret es el ID del secreto de la etapa 2; el valor nunca pasa por Terraform. | <pre>map(object({<br/>    secret  = string<br/>    version = optional(string, "latest")<br/>  }))</pre> | `{}` | no |
| <a name="input_vpc_egress"></a> [vpc\_egress](#input\_vpc\_egress) | Tráfico de salida que pasa por la VPC: ALL\_TRAFFIC (todo, controlado por firewall y Cloud NAT) o PRIVATE\_RANGES\_ONLY. | `string` | `"ALL_TRAFFIC"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_kms_key"></a> [kms\_key](#output\_kms\_key) | Llave KMS (CMEK) configurada en la plantilla del servicio. |
| <a name="output_location"></a> [location](#output\_location) | Región del servicio. |
| <a name="output_neg_id"></a> [neg\_id](#output\_neg\_id) | ID del NEG sin servidor; es el backend que recibe el módulo load-balancer. |
| <a name="output_neg_self_link"></a> [neg\_self\_link](#output\_neg\_self\_link) | Self link del NEG sin servidor. |
| <a name="output_service_id"></a> [service\_id](#output\_service\_id) | ID del servicio (projects/<p>/locations/<región>/services/<nombre>). |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Nombre del servicio de Cloud Run. |
| <a name="output_service_uri"></a> [service\_uri](#output\_service\_uri) | URI del servicio (solo alcanzable desde la red interna o el balanceador). |
| <a name="output_subnetwork"></a> [subnetwork](#output\_subnetwork) | Subred de la salida directa a la VPC configurada en el servicio (ruta projects/<host>/regions/<r>/subnetworks/<s>). |
<!-- END_TF_DOCS -->
