# network-hub

Crea la VPC del hub en modo personalizado y con enrutamiento global, sus subredes y un Cloud
Router por cada región que usan las subredes (con el ASN del hub). La especificación (sección
"Componentes del datacenter", red) exige subredes privadas con Private Google Access y flow
logs al 50 %: el módulo fija Private Google Access y los flow logs en todas las subredes y solo
permite subir el muestreo (validación `flow_log_sampling >= 0.5`).

Decisiones del módulo:

- La VPC se crea sin la ruta por defecto a internet (`delete_default_routes_on_create`): el hub
  no tiene Cloud NAT (ADR 0004) ni salida a internet. Se crea solo la ruta a
  `199.36.153.4/30` (restricted.googleapis.com) para que Private Google Access funcione.
  Las rutas con siguiente salto al gateway de internet no se intercambian por peering, así que
  no llegan a los spokes.
- Los Cloud Router anuncian por defecto sus subredes; los anuncios personalizados hacia
  on-premises (el /16 del hub, los /16 de los spokes y 35.199.192.0/19) se fijan por sesión BGP
  en el módulo `hybrid-connectivity`.
- `network_suffix` permite reutilizar el módulo para la VPC simulada de on-premises
  (`onprem-sim`, ADR 0006) sin choque de nombres en el mismo proyecto.
- `extra_router_regions` crea un Cloud Router en regiones sin subred (por ejemplo, la región
  de DR de `onprem-sim`, que solo termina la VPN de DR).
- Las reglas de firewall no viven aquí: se crean con el módulo `firewall`.

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
| [google_compute_network.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network) | resource |
| [google_compute_route.restricted_vip](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_route) | resource |
| [google_compute_router.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router) | resource |
| [google_compute_subnetwork.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_subnetwork) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (por ejemplo, bnt). | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto donde se crea la VPC (proyecto net-hub). | `string` | n/a | yes |
| <a name="input_router_asn"></a> [router\_asn](#input\_router\_asn) | ASN privado de los Cloud Router del hub (hub\_asn del plan de direccionamiento, por ejemplo 64514). | `number` | n/a | yes |
| <a name="input_subnets"></a> [subnets](#input\_subnets) | Subredes de la VPC. Llave = nombre lógico (por ejemplo hub, hub\_dr); valor = región y CIDR primario. Todas son privadas, con Private Google Access y flow logs. | <pre>map(object({<br/>    region      = string<br/>    cidr        = string<br/>    description = optional(string, "")<br/>  }))</pre> | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno que se usa en los nombres. El hub vive en common. | `string` | `"common"` | no |
| <a name="input_extra_router_regions"></a> [extra\_router\_regions](#input\_extra\_router\_regions) | Regiones donde se crea un Cloud Router aunque la VPC no tenga subred allí (por ejemplo, la región de DR de la VPC simulada de on-premises, que solo necesita el router para su HA VPN). Por defecto ninguna: un router por región con subred. | `list(string)` | `[]` | no |
| <a name="input_flow_log_sampling"></a> [flow\_log\_sampling](#input\_flow\_log\_sampling) | Fracción de muestreo de los flow logs. La especificación pide 0.5 como mínimo; solo se permite subirla. | `number` | `0.5` | no |
| <a name="input_network_suffix"></a> [network\_suffix](#input\_network\_suffix) | Recurso que cierra el nombre de la VPC: <prefix>-<environment>-net-<network\_suffix>. Por defecto hub; la VPC simulada de on-premises (ADR 0006) usa onprem-sim. | `string` | `"hub"` | no |
| <a name="input_region_short_names"></a> [region\_short\_names](#input\_region\_short\_names) | Mapa región → código corto que se agrega a los nombres de recursos regionales. | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | ID de la VPC (projects/<proyecto>/global/networks/<nombre>). |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Nombre de la VPC. |
| <a name="output_network_self_link"></a> [network\_self\_link](#output\_network\_self\_link) | self\_link de la VPC (para peering, zonas de peering DNS y VPN). |
| <a name="output_routers"></a> [routers](#output\_routers) | Mapa región → nombre del Cloud Router. |
| <a name="output_subnets"></a> [subnets](#output\_subnets) | Mapa llave de subnets → { self\_link, name, region, cidr }. |
<!-- END_TF_DOCS -->
