# Módulo `load-balancer`

Crea un balanceador de aplicaciones de uno de dos tipos (`type`). Con `"external"`: balanceador
HTTPS global externo (`EXTERNAL_MANAGED`) en el proyecto de servicio (ADR 0005), con IP global,
certificado administrado por Google para `domain_names`, política SSL con TLS 1.2 como mínimo,
mapa de URL con reglas de ruta, redirección de HTTP a HTTPS en la misma IP y servicios de backend
con registro de solicitudes. Con `"internal"`: balanceador de aplicaciones interno regional
(`INTERNAL_MANAGED`) en la Shared VPC (`network`/`subnet`), con IP interna compartida entre 443 y
80, certificado regional de Certificate Manager (administrado con autorización DNS, o propio por
`certificate_manager_certificates`), política SSL regional y la misma redirección. La
especificación, en su sección "Componentes del datacenter", pide HTTPS con certificado
administrado, redirección de HTTP y Cloud Armor obligatorio en el externo: `security_policy` es
obligatoria por validación con `type = "external"`, la redirección y la política TLS 1.2 son fijas,
y el registro de los backends no se puede apagar (`log_sample_rate > 0`).

Backends: cada llave de `backends` es un servicio con su lista de grupos (grupo de instancias de
`compute-mig`, NEG serverless de `cloud-run` o NEG de GKE). Los NEG serverless (`serverless =
true`) no llevan verificación de salud; los demás usan una existente (`health_check_id`) o una que
crea el módulo (`health_check`). El modo de balanceo por defecto es `UTILIZATION` (grupos de
instancias); para NEG zonales de GKE hay que pasar `balancing_mode = "RATE"` y
`max_rate_per_endpoint`. La conmutación a DR del externo (§7.6) se hace con `dr_active`:
cada servicio pasa de `groups` a `dr_groups`. El interno es regional y sus backends deben estar
en su región: se crea uno por región (la etapa 5 agrega el de DR al conmutar) y sus reglas de
reenvío tienen `allow_global_access = true`, para que clientes de otras regiones y on-premises
por túneles o adjuntos de VLAN de otra región lleguen a él. La salida `backend_groups` publica
los grupos configurados en cada servicio de backend.

Precondiciones que el módulo no crea:

- Interno: la subred proxy-only (`REGIONAL_MANAGED_PROXY`) de `region` debe existir en la VPC
  (llaves `proxy`/`proxy_dr` del plan IP, creadas por `network-spoke`). Para la región de DR,
  la etapa pasa `region`, `subnet` y los grupos de esa región.
- Interno: una verificación de salud existente debe ser regional (la de `compute-mig` es global
  si así se creó); si no, usar `health_check` para que el módulo cree una regional.
- Externo: los registros DNS A de `domain_names` apuntan a `ip_address` para que el certificado
  se active. Interno con certificado administrado: crear los registros de
  `dns_authorization_records` en la zona pública del dominio.

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
| [google_certificate_manager_certificate.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/certificate_manager_certificate) | resource |
| [google_certificate_manager_dns_authorization.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/certificate_manager_dns_authorization) | resource |
| [google_compute_address.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_address) | resource |
| [google_compute_backend_service.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_backend_service) | resource |
| [google_compute_forwarding_rule.http](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_forwarding_rule) | resource |
| [google_compute_forwarding_rule.https](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_forwarding_rule) | resource |
| [google_compute_global_address.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_address) | resource |
| [google_compute_global_forwarding_rule.http](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_forwarding_rule) | resource |
| [google_compute_global_forwarding_rule.https](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_forwarding_rule) | resource |
| [google_compute_health_check.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_health_check) | resource |
| [google_compute_managed_ssl_certificate.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_managed_ssl_certificate) | resource |
| [google_compute_region_backend_service.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_backend_service) | resource |
| [google_compute_region_health_check.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_health_check) | resource |
| [google_compute_region_ssl_policy.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_ssl_policy) | resource |
| [google_compute_region_target_http_proxy.redirect](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_target_http_proxy) | resource |
| [google_compute_region_target_https_proxy.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_target_https_proxy) | resource |
| [google_compute_region_url_map.redirect](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_url_map) | resource |
| [google_compute_region_url_map.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_url_map) | resource |
| [google_compute_ssl_policy.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_ssl_policy) | resource |
| [google_compute_target_http_proxy.redirect](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_target_http_proxy) | resource |
| [google_compute_target_https_proxy.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_target_https_proxy) | resource |
| [google_compute_url_map.redirect](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map) | resource |
| [google_compute_url_map.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_backends"></a> [backends](#input\_backends) | Servicios de backend. Llave: nombre corto del servicio. Cada uno lleva:<br/>- groups: grupos de backend activos en operación normal (grupo de instancias de compute-mig,<br/>  NEG serverless de cloud-run o NEG de GKE), con su modo de balanceo opcional.<br/>- dr\_groups: grupos equivalentes en la región de DR; se usan cuando dr\_active = true.<br/>- serverless: true para NEG serverless (sin verificación de salud, port\_name ni timeout).<br/>- health\_check\_id: verificación de salud existente (global para "external", regional para<br/>  "internal"), o health\_check para que el módulo la cree. Una de las dos si no es serverless.<br/>- paths: rutas que el mapa de URL envía a este servicio (por ejemplo ["/api/*"]).<br/>- log\_sample\_rate: fracción de solicitudes registradas (mayor que 0; el registro no se apaga). | <pre>map(object({<br/>    description = optional(string)<br/>    protocol    = optional(string, "HTTP")<br/>    port_name   = optional(string, "http")<br/>    timeout_sec = optional(number, 30)<br/>    serverless  = optional(bool, false)<br/>    groups = list(object({<br/>      group                 = string<br/>      balancing_mode        = optional(string)<br/>      capacity_scaler       = optional(number, 1)<br/>      max_utilization       = optional(number)<br/>      max_rate_per_instance = optional(number)<br/>      max_rate_per_endpoint = optional(number)<br/>    }))<br/>    dr_groups = optional(list(object({<br/>      group                 = string<br/>      balancing_mode        = optional(string)<br/>      capacity_scaler       = optional(number, 1)<br/>      max_utilization       = optional(number)<br/>      max_rate_per_instance = optional(number)<br/>      max_rate_per_endpoint = optional(number)<br/>    })), [])<br/>    health_check_id = optional(string)<br/>    health_check = optional(object({<br/>      protocol            = optional(string, "HTTP")<br/>      port                = optional(number)<br/>      request_path        = optional(string, "/healthz")<br/>      check_interval_sec  = optional(number, 10)<br/>      timeout_sec         = optional(number, 5)<br/>      healthy_threshold   = optional(number, 2)<br/>      unhealthy_threshold = optional(number, 3)<br/>    }))<br/>    paths                           = optional(list(string), [])<br/>    log_sample_rate                 = optional(number, 1)<br/>    connection_draining_timeout_sec = optional(number, 300)<br/>  }))</pre> | n/a | yes |
| <a name="input_default_backend"></a> [default\_backend](#input\_default\_backend) | Llave de backends que atiende las solicitudes que no coinciden con ninguna ruta de paths. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno: dev, qa o prod. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes. Obligatorias: env, app, owner, cost\_center, managed\_by. | `map(string)` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (§4.2), por ejemplo "bnt". | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto de servicio donde vive el balanceador (ADR 0005). | `string` | n/a | yes |
| <a name="input_type"></a> [type](#input\_type) | "external": balanceador de aplicaciones externo global (EXTERNAL\_MANAGED). "internal": balanceador de aplicaciones interno regional (INTERNAL\_MANAGED) en la Shared VPC. | `string` | n/a | yes |
| <a name="input_certificate_manager_certificates"></a> [certificate\_manager\_certificates](#input\_certificate\_manager\_certificates) | Solo "internal": IDs de certificados de Certificate Manager regionales ya existentes (por ejemplo, emitidos por una CA privada para dominios internos). Vacío: el módulo crea un certificado administrado por Google con autorización DNS para domain\_names. | `list(string)` | `[]` | no |
| <a name="input_domain_names"></a> [domain\_names](#input\_domain\_names) | Dominios del certificado administrado por Google. Obligatorio en "external"; en "internal" se usa si no se pasan certificate\_manager\_certificates. | `list(string)` | `[]` | no |
| <a name="input_dr_active"></a> [dr\_active](#input\_dr\_active) | Conmutación a DR: true hace que cada servicio de backend use dr\_groups en lugar de groups (§7.6). | `bool` | `false` | no |
| <a name="input_internal_ip_address"></a> [internal\_ip\_address](#input\_internal\_ip\_address) | IP interna fija opcional para el balanceador interno, dentro de subnet. null: la asigna GCP. | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Nombre corto del balanceador (por ejemplo, la aplicación); forma parte del nombre de cada recurso. | `string` | `"web"` | no |
| <a name="input_network"></a> [network](#input\_network) | self\_link de la VPC de la Shared VPC (salida network\_self\_link de la etapa 3). Obligatoria en "internal". | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | Región del balanceador interno (uno por región: sus backends deben estar en esa región). No aplica en "external". | `string` | `null` | no |
| <a name="input_region_short_codes"></a> [region\_short\_codes](#input\_region\_short\_codes) | Código corto de cada región para los nombres (§4.2). | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_security_policy"></a> [security\_policy](#input\_security\_policy) | self\_link de la política de Cloud Armor (salida policy\_self\_link del módulo cloud-armor). Obligatoria en "external"; no aplica en "internal". | `string` | `null` | no |
| <a name="input_ssl_policy_profile"></a> [ssl\_policy\_profile](#input\_ssl\_policy\_profile) | Perfil de la política SSL (siempre con TLS 1.2 como mínimo): MODERN o RESTRICTED. | `string` | `"MODERN"` | no |
| <a name="input_subnet"></a> [subnet](#input\_subnet) | self\_link de la subred de la Shared VPC donde se reserva la IP interna (subred app de la región activa). Obligatoria en "internal". La subred proxy-only de esa región debe existir antes. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_backend_groups"></a> [backend\_groups](#output\_backend\_groups) | Mapa llave de backends → grupos (self links o IDs) que el servicio de backend tiene configurados: groups o, con dr\_active, dr\_groups. |
| <a name="output_backend_service_ids"></a> [backend\_service\_ids](#output\_backend\_service\_ids) | Mapa llave de backends → ID del servicio de backend. |
| <a name="output_dns_authorization_records"></a> [dns\_authorization\_records](#output\_dns\_authorization\_records) | Solo "internal" con certificado creado por el módulo: dominio → registro DNS (name, type, data) que hay que crear para emitir el certificado. |
| <a name="output_forwarding_rule_names"></a> [forwarding\_rule\_names](#output\_forwarding\_rule\_names) | Nombres de las reglas de reenvío, llaves https y http. |
| <a name="output_health_check_ids"></a> [health\_check\_ids](#output\_health\_check\_ids) | Mapa llave de backends → ID de la verificación de salud usada (null en backends serverless). |
| <a name="output_internal_certificate_ids"></a> [internal\_certificate\_ids](#output\_internal\_certificate\_ids) | Solo "internal": certificados de Certificate Manager que usa el proxy HTTPS regional (los recibidos en certificate\_manager\_certificates o el que crea el módulo). Vacía en "external". |
| <a name="output_ip_address"></a> [ip\_address](#output\_ip\_address) | IP del balanceador: pública global en "external" (para los registros DNS A de domain\_names), interna regional en "internal". |
| <a name="output_url_map_id"></a> [url\_map\_id](#output\_url\_map\_id) | ID del mapa de URL principal (HTTPS). |
| <a name="output_url_map_name"></a> [url\_map\_name](#output\_url\_map\_name) | Nombre del mapa de URL principal; sirve para filtrar métricas del balanceador (resource.label.url\_map\_name). |
<!-- END_TF_DOCS -->
