# Módulo `audit-alerts`

Crea en un proyecto las métricas de log y las alertas de auditoría que pide el CIS Google Cloud
Platform Foundation Benchmark v5.0, recomendaciones 2.5 a 2.12 (2.4 a 2.11 en v3.0): cambios de
propietario, de la configuración de auditoría, de roles personalizados, de reglas de firewall de
VPC, de rutas, de redes, del IAM de buckets y de la configuración de Cloud SQL. Por cada una, un
contador (`google_logging_metric`, DELTA, INT64, unidad 1) y una política de alerta que avisa con
un evento o más en la ventana `alignment_period` (10 minutos por defecto) a un canal de correo
hacia el grupo `security_admins`. La especificación no lo pide por nombre; cierra los huecos del
mapa CIS ([`docs/cumplimiento-cis.md`](../../docs/cumplimiento-cis.md)).

Los detectores de Security Command Center (`OWNER_NOT_MONITORED` … `SQL_INSTANCE_NOT_MONITORED`)
revisan **cada proyecto** y buscan una métrica cuyo filtro sea el que documenta Google, con una
alerta asociada. Por eso:

- Los ocho filtros son los de la [página de hallazgos de SHA](https://docs.cloud.google.com/security-command-center/docs/concepts-vulnerabilities-findings),
  sin cambios (la prueba compara el texto exacto). Van en una sola línea; si el detector exige
  los saltos de línea de la documentación está por verificar (pendiente 58).
- Los cambios de **políticas de firewall** (lo que usa este repositorio en lugar de reglas de
  VPC: las políticas de red de los spokes y de `onprem-sim`) van en una novena métrica,
  `firewall_policy`, solo con el registro de actividad. Agregarlos al filtro de 2.8 arriesgaba
  que el detector dejara de reconocerlo. El filtro cubre también las políticas jerárquicas, que
  el proyecto único ya no crea (ADR 0029 §6); sus cambios se registrarían en la organización
  (HYPOTHESIS): una métrica de proyecto no los ve.
- Se instancia una sola vez, en `1-base`, para el proyecto único (ADR 0029). Las API
  `logging.googleapis.com` y `monitoring.googleapis.com` las habilita `0-bootstrap`.

La condición de cada alerta filtra por el tipo de recurso con que Cloud Logging escribe la serie
de la métrica: `global` para los registros de proyecto, rol, firewall, ruta y red (no son tipos
de Cloud Monitoring), `gcs_bucket` y `cloudsql_database` para buckets y Cloud SQL
([tabla de correspondencias](https://docs.cloud.google.com/logging/docs/api/v2/resource-list#resource-mappings)).
Con otro tipo la alerta nunca se dispara: está marcado `VERIFICAR-EN-APPLY`.

Las alertas también saltan con los cambios legítimos del pipeline (por ejemplo, el peering de
un spoke o una regla de una política de red): avisan de todo cambio, no solo de los manuales.

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
| [google_logging_metric.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_metric) | resource |
| [google_monitoring_alert_policy.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_notification_channel.email](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_notification_channel) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno del proyecto según la convención de nombres: bootstrap, common, dev, qa o prod. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes. Obligatorias: env, app, owner, cost\_center, managed\_by. | `map(string)` | n/a | yes |
| <a name="input_notification_email"></a> [notification\_email](#input\_notification\_email) | Correo del grupo security\_admins (groups.security\_admins de la etapa 1) que recibe las alertas. Sin valor por defecto: llega de la etapa. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (§4.2), por ejemplo "bnt". | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto donde se crean las métricas de log, las alertas y el canal. Los detectores de Security Command Center revisan cada proyecto por separado: hace falta una instancia por proyecto. | `string` | n/a | yes |
| <a name="input_alignment_period"></a> [alignment\_period](#input\_alignment\_period) | Ventana en la que se suman los eventos de cada métrica antes de compararlos con el umbral 0 (de 60s a 3600s). Por defecto 10 minutos: la documentación de Cloud Logging recomienda una ventana que cubra el retraso de ingesta de las métricas de log (hasta 10 minutos). | `string` | `"600s"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alert_policy_ids"></a> [alert\_policy\_ids](#output\_alert\_policy\_ids) | Mapa control → ID de la política de alerta. |
| <a name="output_metric_filters"></a> [metric\_filters](#output\_metric\_filters) | Mapa control → filtro de la métrica de log, para revisar contra los detectores de Security Command Center. |
| <a name="output_metric_names"></a> [metric\_names](#output\_metric\_names) | Mapa control (owner, audit\_config, custom\_role, firewall, route, network, bucket\_iam, sql\_instance, firewall\_policy) → nombre de la métrica de log. |
| <a name="output_notification_channel_id"></a> [notification\_channel\_id](#output\_notification\_channel\_id) | ID del canal de correo hacia el grupo security\_admins. |
| <a name="output_notification_email"></a> [notification\_email](#output\_notification\_email) | Correo del canal de notificación (en minúsculas). |
<!-- END_TF_DOCS -->
