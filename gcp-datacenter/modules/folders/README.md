# Módulo `folders`

Crea carpetas de Resource Manager bajo una organización o una carpeta, una por entorno. La
especificación (sección "Componentes del datacenter", jerarquía de recursos) pide una carpeta
por entorno; por eso el módulo solo acepta los nombres de entorno de la convención de nombres
(`bootstrap`, `common`, `dev`, `qa`, `prod`) y rechaza cualquier otro por validación. Cada
nombre es a la vez el nombre visible de la carpeta y la llave estable del mapa `ids`. La
protección contra borrado del proveedor queda activa por defecto.

Uso típico: la etapa 0 crea `bootstrap` y la etapa 1 crea `common`, `dev`, `qa` y `prod`.

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
| [google_folder.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/folder) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_names"></a> [names](#input\_names) | Nombres de las carpetas, uno por entorno de la convención de nombres: bootstrap, common, dev, qa o prod. Cada nombre es el nombre visible y la llave del mapa de salida. | `set(string)` | n/a | yes |
| <a name="input_parent"></a> [parent](#input\_parent) | Padre de las carpetas: "organizations/<número>" o "folders/<número>". | `string` | n/a | yes |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Si es true, Terraform no puede borrar las carpetas. Solo se apaga para desmontar un entorno de pruebas. | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_folder_numbers"></a> [folder\_numbers](#output\_folder\_numbers) | Mapa nombre de carpeta → número de carpeta (sin el prefijo "folders/"). |
| <a name="output_ids"></a> [ids](#output\_ids) | Mapa nombre de carpeta → ID completo ("folders/<número>"). |
<!-- END_TF_DOCS -->
