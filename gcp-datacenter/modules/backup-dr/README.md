# Módulo `backup-dr`

Crea el respaldo del entorno con dos servicios. Backup and DR Service: una bóveda
(`google_backup_dr_backup_vault`) en `dr_region` con retención mínima forzada igual a
`retention_days` y acceso restringido al proyecto (`access_restriction`), un plan diario por
cada tipo de recurso de `backup_plans` (por defecto VM de Compute Engine y Cloud SQL) en
`region`, y asociaciones
opcionales de recursos a esos planes (`protected_resources`). El plan de Cloud SQL fija
`log_retention_days = sql_log_retention_days` (7 por defecto): con respaldos mejorados el plan
sobrescribe la configuración de respaldos de la instancia y esos días son la ventana de
recuperación a un punto en el tiempo. Backup for GKE: con
`enable_gke_backup`, un plan diario del clúster `gke_cluster_id` en `dr_region`, con todos los
espacios de nombres, volúmenes y secretos, cifrado con CMEK (`gke_backup_kms_key`) y bloqueo de
borrado. La especificación, en su sección "Componentes del datacenter", pide política diaria,
retención de 30 días y región secundaria: la programación es siempre diaria (fija en los planes de
Backup and DR y validada en el cron de GKE), `retention_days` se valida en 30 o más, y la bóveda y
el plan de GKE van en `dr_region`, que debe ser distinta de `region`.

Ubicación: los planes de Backup and DR tienen que estar en la región del recurso que respaldan,
por eso van en `region`; la bóveda puede estar en otra región para VM, discos y Cloud SQL, y se
pone en la secundaria. Backup and DR no ofrece CMEK propia para la bóveda en el proveedor 6.x.

Restricción de acceso: `access_restriction` vale `WITHIN_PROJECT` por defecto porque la bóveda,
los planes y los recursos respaldados están en el mismo proyecto (ADR 0029). Si no se indica, la
API usa `WITHIN_ORGANIZATION`, que supone una organización
([REST de `backupVaults`](https://docs.cloud.google.com/backup-disaster-recovery/docs/reference/rest/v1/projects.locations.backupVaults)).
Según la [documentación de las bóvedas](https://docs.cloud.google.com/backup-disaster-recovery/docs/concepts/backup-vault),
el valor es permanente: se elige antes de crear la bóveda. Que la bóveda se cree con
`WITHIN_PROJECT` en un proyecto sin organización es `VERIFICAR-EN-APPLY`.

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
| [google_backup_dr_backup_plan.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/backup_dr_backup_plan) | resource |
| [google_backup_dr_backup_plan_association.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/backup_dr_backup_plan_association) | resource |
| [google_backup_dr_backup_vault.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/backup_dr_backup_vault) | resource |
| [google_gke_backup_backup_plan.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/gke_backup_backup_plan) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_dr_region"></a> [dr\_region](#input\_dr\_region) | Región secundaria (DR) donde vive la bóveda de respaldos y el plan de Backup for GKE. Debe ser distinta de region. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno: dev, qa o prod. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes. Obligatorias: env, app, owner, cost\_center, managed\_by. | `map(string)` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (§4.2), por ejemplo "bnt". | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto donde se crean la bóveda y los planes (los planes de Backup and DR deben estar en el mismo proyecto que su bóveda). | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Región de las cargas protegidas (primaria). Los planes de Backup and DR se crean aquí: deben estar en la región del recurso que respaldan. | `string` | n/a | yes |
| <a name="input_access_restriction"></a> [access\_restriction](#input\_access\_restriction) | Desde dónde se puede respaldar en la bóveda y hacia dónde restaurar (access\_restriction de la API de Backup and DR). WITHIN\_PROJECT (por defecto): solo recursos del mismo proyecto, que es el diseño de un solo proyecto (ADR 0029). WITHIN\_ORGANIZATION y WITHIN\_ORG\_BUT\_UNRESTRICTED\_FOR\_BA suponen una organización; UNRESTRICTED no limita nada. La documentación dice que el valor es permanente: se elige antes de crear la bóveda. | `string` | `"WITHIN_PROJECT"` | no |
| <a name="input_backup_plans"></a> [backup\_plans](#input\_backup\_plans) | Planes de Backup and DR a crear. Llave: nombre corto del plan. Valor: tipo de recurso que respalda (compute.googleapis.com/Instance, compute.googleapis.com/Disk o sqladmin.googleapis.com/Instance). | `map(string)` | <pre>{<br/>  "sql": "sqladmin.googleapis.com/Instance",<br/>  "vm": "compute.googleapis.com/Instance"<br/>}</pre> | no |
| <a name="input_backup_time_zone"></a> [backup\_time\_zone](#input\_backup\_time\_zone) | Zona horaria (IANA) para interpretar la ventana diaria de respaldo. | `string` | `"America/Mexico_City"` | no |
| <a name="input_backup_window_start_hour"></a> [backup\_window\_start\_hour](#input\_backup\_window\_start\_hour) | Hora (0 a 17) en que abre la ventana diaria de respaldo; la ventana dura 6 horas. | `number` | `1` | no |
| <a name="input_enable_gke_backup"></a> [enable\_gke\_backup](#input\_enable\_gke\_backup) | Crea el plan de Backup for GKE para gke\_cluster\_id. Es un interruptor aparte porque el ID del clúster puede no conocerse en el plan. | `bool` | `false` | no |
| <a name="input_gke_backup_cron"></a> [gke\_backup\_cron](#input\_gke\_backup\_cron) | Programación cron (UTC) del respaldo diario de GKE. | `string` | `"0 7 * * *"` | no |
| <a name="input_gke_backup_delete_lock_days"></a> [gke\_backup\_delete\_lock\_days](#input\_gke\_backup\_delete\_lock\_days) | Días en que un respaldo de GKE no se puede borrar (protección contra borrado accidental o malicioso). No puede pasar de retention\_days. | `number` | `7` | no |
| <a name="input_gke_backup_kms_key"></a> [gke\_backup\_kms\_key](#input\_gke\_backup\_kms\_key) | Llave KMS (uso backup, en dr\_region) con la que Backup for GKE cifra los respaldos. Obligatoria con enable\_gke\_backup. | `string` | `null` | no |
| <a name="input_gke_cluster_id"></a> [gke\_cluster\_id](#input\_gke\_cluster\_id) | ID completo del clúster de GKE a respaldar (projects/<p>/locations/<l>/clusters/<n>, salida cluster\_id del módulo gke). Obligatorio con enable\_gke\_backup. | `string` | `null` | no |
| <a name="input_protected_resources"></a> [protected\_resources](#input\_protected\_resources) | Recursos que se asocian a un plan. Llave: nombre corto. resource: ID completo del recurso (por ejemplo projects/p/zones/z/instances/vm o projects/p/instances/sql); plan: llave de backup\_plans. El recurso debe estar en region. | <pre>map(object({<br/>    resource = string<br/>    plan     = string<br/>  }))</pre> | `{}` | no |
| <a name="input_region_short_codes"></a> [region\_short\_codes](#input\_region\_short\_codes) | Código corto de cada región para los nombres (§4.2). | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_retention_days"></a> [retention\_days](#input\_retention\_days) | Días que se conserva cada respaldo diario. También es la retención mínima forzada de la bóveda (los respaldos no se pueden borrar antes). La especificación pide 30 días como mínimo. | `number` | `30` | no |
| <a name="input_sql_log_retention_days"></a> [sql\_log\_retention\_days](#input\_sql\_log\_retention\_days) | Solo planes de Cloud SQL (sqladmin.googleapis.com/Instance): días de registros de transacciones que guarda el plan, es decir, la ventana de recuperación a un punto en el tiempo con respaldos mejorados. Igual que transaction\_log\_retention\_days del módulo cloud-sql (7 por defecto, máximo de ENTERPRISE). | `number` | `7` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_plan_association_ids"></a> [plan\_association\_ids](#output\_plan\_association\_ids) | Mapa llave de protected\_resources → ID de la asociación con su plan. |
| <a name="output_plan_ids"></a> [plan\_ids](#output\_plan\_ids) | Mapa llave → ID de cada plan: las llaves de backup\_plans (Backup and DR) y "gke" (Backup for GKE) si enable\_gke\_backup. |
| <a name="output_vault_id"></a> [vault\_id](#output\_vault\_id) | ID de la bóveda de Backup and DR (en dr\_region). |
| <a name="output_vault_service_account"></a> [vault\_service\_account](#output\_vault\_service\_account) | Cuenta de servicio de la bóveda; necesita permisos sobre los recursos protegidos. |
<!-- END_TF_DOCS -->
