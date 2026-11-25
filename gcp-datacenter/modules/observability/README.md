# Módulo `observability`

Crea la observabilidad base de un entorno en Cloud Monitoring: un canal de correo por cada
destinatario de `notification_emails` (sin valores por defecto: llegan de la etapa), las
verificaciones de disponibilidad de `uptime_checks` con una alerta por verificación, alertas base
(proporción de 5xx del balanceador, saturación de CPU y memoria en VM y nodos de GKE, retraso de
la réplica de Cloud SQL por debajo del RPO de 15 minutos), un tablero base y un servicio
personalizado con un SLO de disponibilidad por solicitudes del balanceador externo más su alerta
de consumo del presupuesto de errores (rápida a 1 h y lenta a 6 h). La especificación, en su
sección "Componentes del datacenter", pide alertas y tableros base y un SLO de 99.9 %: las
alertas, el tablero y el SLO se crean siempre, y `slo_target` se valida para que no baje de 0.999.

Notas: la alerta de memoria de VM usa la métrica de Ops Agent (las VM del MIG deben tenerlo); el
SLO, la alerta de 5xx y el tablero se filtran por `lb_url_map_name` (salida `url_map_name` de
`load-balancer`) o, si es null, cubren los balanceadores externos del entorno.

Alcance por entorno (proyecto único, ADR 0029): todos los filtros se limitan a los recursos del
entorno, para que las alertas de un entorno no vean los de otro en el mismo proyecto: mapas de
URL y clústeres de GKE cuyo nombre empieza con `<prefix>-<environment>-`, VM con la etiqueta
`env = <environment>`, instancias de Cloud SQL `<project_id>:<prefix>-<environment>-*` y, en el
tablero, solo los dominios de `uptime_checks` (sin verificaciones no hay mosaico de
disponibilidad). `extra_notification_channel_ids` agrega a todas las alertas canales que ya
existen (por ejemplo, los de `1-base`).

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
| [google_monitoring_alert_policy.lb_5xx_ratio](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.saturation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.slo_burn_rate](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.sql_replica_lag](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.uptime](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_custom_service.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_custom_service) | resource |
| [google_monitoring_dashboard.baseline](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_dashboard) | resource |
| [google_monitoring_notification_channel.email](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_notification_channel) | resource |
| [google_monitoring_slo.availability](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_slo) | resource |
| [google_monitoring_uptime_check_config.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_uptime_check_config) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno: dev, qa o prod. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes. Obligatorias: env, app, owner, cost\_center, managed\_by. | `map(string)` | n/a | yes |
| <a name="input_notification_emails"></a> [notification\_emails](#input\_notification\_emails) | Correos (de preferencia listas de grupo) que reciben las alertas. Sin valor por defecto: llegan desde tfvars de la etapa. | `list(string)` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (§4.2), por ejemplo "bnt". | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto donde se crean canales, verificaciones, alertas, tablero y SLO (el proyecto único, ADR 0029). | `string` | n/a | yes |
| <a name="input_cpu_utilization_threshold"></a> [cpu\_utilization\_threshold](#input\_cpu\_utilization\_threshold) | Uso de CPU (0 a 1) sostenido 5 minutos que dispara la alerta de saturación (VM y nodos de GKE). | `number` | `0.85` | no |
| <a name="input_extra_notification_channel_ids"></a> [extra\_notification\_channel\_ids](#input\_extra\_notification\_channel\_ids) | Canales de notificación que ya existen (projects/<proyecto>/notificationChannels/<id>) y que reciben también todas las alertas del módulo, además de los de notification\_emails. En el proyecto único, los de 1-base (salida notification\_channel\_ids). Vacío por defecto. | `list(string)` | `[]` | no |
| <a name="input_lb_5xx_ratio_threshold"></a> [lb\_5xx\_ratio\_threshold](#input\_lb\_5xx\_ratio\_threshold) | Fracción de respuestas 5xx del balanceador sobre el total que dispara la alerta. | `number` | `0.05` | no |
| <a name="input_lb_url_map_name"></a> [lb\_url\_map\_name](#input\_lb\_url\_map\_name) | Nombre del mapa de URL del balanceador externo (salida url\_map\_name de load-balancer) para filtrar el SLO, la alerta de 5xx y el tablero. null: todos los balanceadores del entorno (mapas de URL que empiezan con <prefix>-<environment>-). | `string` | `null` | no |
| <a name="input_memory_utilization_threshold"></a> [memory\_utilization\_threshold](#input\_memory\_utilization\_threshold) | Uso de memoria (0 a 1) sostenido 5 minutos que dispara la alerta de saturación (VM con Ops Agent y nodos de GKE). | `number` | `0.9` | no |
| <a name="input_slo_rolling_period_days"></a> [slo\_rolling\_period\_days](#input\_slo\_rolling\_period\_days) | Ventana móvil del SLO, en días. | `number` | `28` | no |
| <a name="input_slo_target"></a> [slo\_target](#input\_slo\_target) | Objetivo del SLO de disponibilidad por solicitudes del balanceador (la especificación pide 99.9 %). | `number` | `0.999` | no |
| <a name="input_sql_replica_lag_threshold_seconds"></a> [sql\_replica\_lag\_threshold\_seconds](#input\_sql\_replica\_lag\_threshold\_seconds) | Retraso de la réplica de Cloud SQL (segundos) que dispara la alerta. Debe quedar por debajo del RPO de 15 minutos (900 s) para avisar antes de incumplirlo. | `number` | `300` | no |
| <a name="input_uptime_checks"></a> [uptime\_checks](#input\_uptime\_checks) | Verificaciones de disponibilidad HTTP(S). Llave: nombre corto. host: dominio público a revisar<br/>(por ejemplo, uno de domain\_names del balanceador). Cada verificación genera además una alerta<br/>que avisa cuando falla desde más de una región. | <pre>map(object({<br/>    host             = string<br/>    path             = optional(string, "/")<br/>    port             = optional(number, 443)<br/>    use_ssl          = optional(bool, true)<br/>    validate_ssl     = optional(bool, true)<br/>    period           = optional(string, "60s")<br/>    timeout          = optional(string, "10s")<br/>    selected_regions = optional(list(string), [])<br/>    content_match    = optional(string)<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alert_policy_ids"></a> [alert\_policy\_ids](#output\_alert\_policy\_ids) | Mapa nombre → ID de cada política de alerta (lb\_5xx\_ratio, saturation, sql\_replica\_lag, slo\_burn\_rate y uptime-<llave>). |
| <a name="output_dashboard_ids"></a> [dashboard\_ids](#output\_dashboard\_ids) | Mapa nombre → ID del tablero (llave baseline). |
| <a name="output_notification_channel_ids"></a> [notification\_channel\_ids](#output\_notification\_channel\_ids) | Mapa correo → ID del canal de notificación. |
| <a name="output_slo_id"></a> [slo\_id](#output\_slo\_id) | Nombre completo del SLO de disponibilidad. |
| <a name="output_uptime_check_ids"></a> [uptime\_check\_ids](#output\_uptime\_check\_ids) | Mapa llave de uptime\_checks → ID de la verificación (uptime\_check\_id). |
<!-- END_TF_DOCS -->
