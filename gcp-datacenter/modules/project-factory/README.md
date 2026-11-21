# Módulo `project-factory`

Crea un proyecto de GCP dentro de una carpeta, lo asocia a la cuenta de facturación, habilita
sus APIs (una instancia de `google_project_service` por API, con el nombre como llave) y,
opcionalmente, lo habilita como host de Shared VPC o lo une como servicio a un host. El ID se
arma con la convención de nombres, `<prefix>-<environment>-<name>`, más `project_suffix` al
final si se indica, y se valida que no pase de 30 caracteres.

La especificación (sección "Componentes del datacenter", jerarquía de proyectos y convención
de etiquetas) pide proyectos sin red default y con las etiquetas obligatorias: por eso
`auto_create_network = false` es un valor fijo y `labels` se valida con la regla común del
repositorio. Para evitar borrados accidentales, `deletion_policy` vale `PREVENT` por defecto y
en `bootstrap`, `common` y `prod` no admite otro valor; en `dev` y `qa` se puede usar `DELETE`
para desmontar el entorno.

Notas de uso:

- Shared VPC: el host se habilita con `shared_vpc_host = true`; un proyecto de servicio se une
  con `shared_vpc_host_project`. Ambos agregan `compute.googleapis.com` a las APIs. El host
  debe existir y estar habilitado antes (en otra etapa o en otra instancia del módulo).
- Las salidas `project_id` y `project_number` dependen de las APIs habilitadas, así que los
  recursos que las usen esperan a que las APIs estén listas.
- Los permisos de uso de subred y de llaves KMS para los agentes de servicio no van aquí: se
  asignan con el módulo `iam` en la etapa que corresponda.

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
| [google_compute_shared_vpc_host_project.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_shared_vpc_host_project) | resource |
| [google_compute_shared_vpc_service_project.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_shared_vpc_service_project) | resource |
| [google_project.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project) | resource |
| [google_project_service.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | Cuenta de facturación que se asocia al proyecto (formato XXXXXX-XXXXXX-XXXXXX). | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno del proyecto según la convención de nombres: bootstrap, common, dev, qa o prod. | `string` | n/a | yes |
| <a name="input_folder_id"></a> [folder\_id](#input\_folder\_id) | Carpeta donde se crea el proyecto: "folders/<número>" o solo el número. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes. Obligatorias: env, app, owner, cost\_center, managed\_by. | `map(string)` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Parte del dominio y recurso del ID del proyecto (por ejemplo, net-hub, logging, seed, net-spoke, app). El ID queda <prefix>-<environment>-<name>[-<project\_suffix>]. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa en los nombres (por ejemplo, bnt). | `string` | n/a | yes |
| <a name="input_apis"></a> [apis](#input\_apis) | APIs que se habilitan en el proyecto (por ejemplo, container.googleapis.com). compute.googleapis.com se agrega sola si el proyecto participa en Shared VPC. | `set(string)` | `[]` | no |
| <a name="input_deletion_policy"></a> [deletion\_policy](#input\_deletion\_policy) | Qué hace Terraform al destruir el proyecto: PREVENT (falla), ABANDON (lo deja en GCP) o DELETE (lo borra). En bootstrap, common y prod solo se admite PREVENT. | `string` | `"PREVENT"` | no |
| <a name="input_disable_services_on_destroy"></a> [disable\_services\_on\_destroy](#input\_disable\_services\_on\_destroy) | Si es true, al quitar una API de la lista se deshabilita en el proyecto. Por defecto false: deshabilitar una API puede romper recursos que no administra este módulo. | `bool` | `false` | no |
| <a name="input_display_name"></a> [display\_name](#input\_display\_name) | Nombre visible del proyecto. Si es null se usa el ID del proyecto. | `string` | `null` | no |
| <a name="input_project_suffix"></a> [project\_suffix](#input\_project\_suffix) | Sufijo opcional para que el ID sea único a nivel mundial; se agrega al final con un guion. Vacío: sin sufijo. | `string` | `""` | no |
| <a name="input_shared_vpc_host"></a> [shared\_vpc\_host](#input\_shared\_vpc\_host) | Si es true, el proyecto se habilita como host de Shared VPC. | `bool` | `false` | no |
| <a name="input_shared_vpc_host_project"></a> [shared\_vpc\_host\_project](#input\_shared\_vpc\_host\_project) | ID del proyecto host de Shared VPC al que se une este proyecto como servicio. null: no se une. Excluyente con shared\_vpc\_host. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_enabled_apis"></a> [enabled\_apis](#output\_enabled\_apis) | APIs habilitadas por el módulo, incluida compute.googleapis.com si se agregó por Shared VPC. |
| <a name="output_project_id"></a> [project\_id](#output\_project\_id) | ID del proyecto. Se publica después de habilitar las APIs y Shared VPC, para que quien lo use no llegue antes. |
| <a name="output_project_number"></a> [project\_number](#output\_project\_number) | Número del proyecto (para identificar agentes de servicio). |
| <a name="output_shared_vpc_host_project"></a> [shared\_vpc\_host\_project](#output\_shared\_vpc\_host\_project) | Proyecto host al que se unió este proyecto como servicio, o null. |
<!-- END_TF_DOCS -->
