# Módulo `off-hours-shutdown`

Crea, en el proyecto de servicio de dev o qa, los trabajos de Cloud Scheduler que apagan fuera
de horario lo que cobra por hora encendido (ADR 0028): cada instancia de `sql_instances` se
detiene a la hora de `stop_schedule` y se enciende a la de `start_schedule` con
`instances.patch` de la API de Cloud SQL Admin (`settings.activationPolicy` en `NEVER` o
`ALWAYS`); cada pool de `gke_node_pools` se apaga en dos pasos (`setAutoscaling` con el
autoescalado desactivado y, `gke_step_minutes` después, `setSize` a 0) y se enciende en dos
(`setSize` al mínimo y `setAutoscaling` con sus límites). Los trabajos llaman directo a las
APIs de Google con destino HTTP y el token OAuth de `service_account_email`, una cuenta
dedicada que crea la etapa 4 con un rol personalizado que solo tiene
`cloudsql.instances.get`, `cloudsql.instances.update` y `container.clusters.update`. No hay
funciones ni código propio que mantener.

El MIG no pasa por este módulo: su autoescalador tiene programas de escalado nativos y la
etapa 5 le pasa la ventana de la salida `window` (variable `business_hours` del módulo
`compute-mig`). La especificación no pide este apagado: es la mitigación de costo de dev y qa
(contrato §8). prod se rechaza en `environment`. Para que el apagado no aparezca como deriva,
el módulo `cloud-sql` ignora `activation_policy` (y solo con `allow_scheduled_stop` admite una
instancia detenida: sin él, una `postcondition` hace fallar el plan) y los pools ignoran
`autoscaling` solo con `scheduled_scaling` (módulo `gke`); los dos interruptores se rechazan en
prod.

Los crons van en `time_zone` con la forma `M H * * D` (sin día del mes ni mes) y los mismos
días en los dos: el horario encendido empieza y termina el mismo día. Memorystore y Filestore
siguen cobrando su capacidad: no se encontró una operación para detenerlos (HYPOTHESIS, ADR
0028).

Cada trabajo solo ve la respuesta inicial de la API (una operación de larga duración), no su
final: si una operación falla después, el trabajo queda como exitoso. Los reintentos
(`retry_config`, unos 7.5 minutos en total) repiten la llamada cuando la respuesta no es 2xx,
por ejemplo si hay otra operación en curso sobre el mismo clúster. Para encender a mano antes
de hora: `gcloud scheduler jobs run <id>` con el ID de la salida `job_ids` (por ejemplo
`sql-primary-start`).

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
| [google_cloud_scheduler_job.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_scheduler_job) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno: dev o qa. prod no se admite: el apagado fuera de horario es solo para entornos que no son de producción (ADR 0028). | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (§4.2), por ejemplo bnt. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto de servicio donde viven los trabajos de Cloud Scheduler, la instancia de Cloud SQL y el clúster de GKE. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Región de los trabajos de Cloud Scheduler (la región primaria del entorno). | `string` | n/a | yes |
| <a name="input_service_account_email"></a> [service\_account\_email](#input\_service\_account\_email) | Correo de la cuenta de servicio dedicada cuyo token OAuth usan los trabajos (la crea la etapa 4 con un rol personalizado de permisos mínimos). No se admite la cuenta de Compute por defecto. | `string` | n/a | yes |
| <a name="input_gke_node_pools"></a> [gke\_node\_pools](#input\_gke\_node\_pools) | Pools de nodos de GKE que se apagan y encienden (llave corta → ubicación y nombre del clúster, nombre del pool y su autoescalado por zona). Los pools deben ignorar autoscaling en Terraform (scheduled\_scaling del módulo gke). | <pre>map(object({<br/>    location       = string<br/>    cluster        = string<br/>    node_pool      = string<br/>    min_node_count = number<br/>    max_node_count = number<br/>  }))</pre> | `{}` | no |
| <a name="input_gke_step_minutes"></a> [gke\_step\_minutes](#input\_gke\_step\_minutes) | Minutos entre los dos pasos del apagado y del encendido de cada pool de GKE (apagar el autoescalado y luego llevar el pool a 0; al encender, el tamaño mínimo y luego el autoescalado). | `number` | `10` | no |
| <a name="input_region_codes"></a> [region\_codes](#input\_region\_codes) | Mapa región → código corto que se agrega a los nombres (§4.2). | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_sql_instances"></a> [sql\_instances](#input\_sql\_instances) | Instancias de Cloud SQL que se detienen y encienden (llave corta → nombre de la instancia en project\_id). Solo primarias: una réplica de lectura no se puede detener. | `map(string)` | `{}` | no |
| <a name="input_start_schedule"></a> [start\_schedule](#input\_start\_schedule) | Cron de encendido en time\_zone, con la forma "M H * * D" (minuto, hora y días de la semana 0-6; día del mes y mes siempre *). Por ejemplo "0 7 * * 1-5": 07:00 de lunes a viernes. | `string` | `"0 7 * * 1-5"` | no |
| <a name="input_stop_schedule"></a> [stop\_schedule](#input\_stop\_schedule) | Cron de apagado en time\_zone, con la misma forma y los mismos días que start\_schedule. Debe caer al menos 60 minutos después del encendido del mismo día y antes de las 23:59 menos gke\_step\_minutes. | `string` | `"0 20 * * 1-5"` | no |
| <a name="input_time_zone"></a> [time\_zone](#input\_time\_zone) | Zona horaria (nombre IANA, por ejemplo America/Monterrey) en la que se leen start\_schedule y stop\_schedule. | `string` | `"America/Mexico_City"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_job_ids"></a> [job\_ids](#output\_job\_ids) | Mapa llave del trabajo → ID (projects/<p>/locations/<región>/jobs/<nombre>), para lanzarlo a mano con gcloud scheduler jobs run. |
| <a name="output_job_names"></a> [job\_names](#output\_job\_names) | Mapa llave del trabajo (sql-<llave>-stop\|start, gke-<llave>-stop-autoscaling\|stop-resize\|start-resize\|start-autoscaling) → nombre del trabajo de Cloud Scheduler. |
| <a name="output_window"></a> [window](#output\_window) | Horario encendido calculado de los crons: zona horaria, crons, días, minutos del día de encendido y apagado y duración en segundos. La etapa 5 lo usa para el programa de escalado del MIG (business\_hours) y para la ventana de Backup and DR. |
<!-- END_TF_DOCS -->
