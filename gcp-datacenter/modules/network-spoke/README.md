# network-spoke

Crea la VPC spoke de un entorno (ADR 0003, sin Shared VPC desde el ADR 0029: el spoke y las
cargas del entorno viven en el mismo proyecto, junto con el hub): subredes del plan de
direccionamiento con sus rangos secundarios, subredes proxy-only, el rango y la conexión de
Private Service Access, el peering con el hub en los dos sentidos, las rutas de salida y un
Cloud Router con Cloud NAT por región activa (ADR 0004). La especificación (sección
"Componentes del datacenter", red) exige Private Google Access, flow logs al 50 %, NAT por
región y ninguna IP pública: Private Google Access y los flow logs son fijos en las subredes
normales, el muestreo solo puede subir (`flow_log_sampling >= 0.5`), el NAT se crea siempre en
cada región activa y el módulo no crea ninguna dirección externa (el NAT usa `AUTO_ONLY`). El
muestreo vale 1 (100 %, CIS 3.10) por defecto; dev y qa lo bajan a 0.5 por costo (ADR 0027).

Decisiones del módulo:

- Subredes: `app` (rangos secundarios `pods` y `services`) y `run` en la región primaria;
  `app_dr` (`pods_dr` y `services_dr`) y `run_dr` en DR solo con `enable_dr = true`. Los rangos
  secundarios se llaman `pods` y `services` en las dos regiones, así `subnets[k].secondary_ranges`
  tiene siempre esas llaves y el valor es el nombre real del rango para GKE.
- `proxy` y `proxy_dr` son subredes `REGIONAL_MANAGED_PROXY`; GCP no admite en ellas Private
  Google Access ni flow logs (omisiones de checkov documentadas en el recurso).
- `gke_master` y `gke_master_dr` solo se reservan: se validan (/28, sin traslape) y salen en
  `reserved_cidrs`, sin crear subred.
- Validaciones: solo llaves conocidas, llaves base obligatorias, llaves `*_dr` obligatorias con
  `enable_dr`, CIDR IPv4 válidos y sin traslape entre sí. El traslape con `onprem_cidrs` y que
  todo quepa en el /16 lo valida la raíz de la etapa.
- Rutas: la VPC se crea sin la ruta por defecto y el módulo crea dos rutas explícitas, el VIP
  restringido `199.36.153.4/30` (Private Google Access por restricted.googleapis.com) y
  `0.0.0.0/0` hacia el gateway de internet, que solo sirve a Cloud NAT porque las VM no tienen IP
  pública. Ambas son parte de la red y no opciones de la raíz; la zona DNS de `googleapis.com` sí
  la crea la raíz con el módulo `dns`.
- Un proyecto, varias VPC (ADR 0029 §6): los nombres llevan `<prefix>-<environment>-`, así que
  las tres VPC spoke conviven con el hub y `onprem-sim` en el mismo proyecto, cada una con su
  propia conexión de Private Service Access (rango `psa` distinto por entorno en el plan de
  direccionamiento). Que varias VPC de un proyecto tengan cada una su conexión de PSA está
  marcado `VERIFICAR-EN-APPLY`.
- Peering: el lado del spoke importa rutas personalizadas y el lado del hub (creado sobre la red
  del hub, a partir de `hub_network_self_link`) las exporta. Se encadenan con `depends_on`
  detrás de la conexión de servicenetworking porque GCP no admite dos operaciones de peering a la
  vez sobre una red. La salida `peerings` lee los dos recursos (rutas importadas y
  exportadas) para que las pruebas de la raíz comprueben los sentidos.
- Las reglas de firewall y las etiquetas seguras viven en el módulo `firewall`.

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
| [google_compute_global_address.psa](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_address) | resource |
| [google_compute_network.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network) | resource |
| [google_compute_network_peering.hub_to_spoke](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network_peering) | resource |
| [google_compute_network_peering.spoke_to_hub](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network_peering) | resource |
| [google_compute_route.internet_egress](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_route) | resource |
| [google_compute_route.restricted_vip](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_route) | resource |
| [google_compute_router.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router) | resource |
| [google_compute_router_nat.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router_nat) | resource |
| [google_compute_subnetwork.proxy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_subnetwork) | resource |
| [google_compute_subnetwork.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_subnetwork) | resource |
| [google_service_networking_connection.psa](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_networking_connection) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno del spoke: dev, qa o prod. | `string` | n/a | yes |
| <a name="input_hub_network_self_link"></a> [hub\_network\_self\_link](#input\_hub\_network\_self\_link) | self\_link (o ID projects/<proyecto>/global/networks/<nombre>) de la VPC hub. Se usa para el peering en ambos sentidos: el lado del hub se crea en el proyecto del hub. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes. Obligatorias: env, app, owner, cost\_center, managed\_by. | `map(string)` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (por ejemplo, bnt). | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto net-spoke del entorno (host de Shared VPC) donde se crea la VPC. | `string` | n/a | yes |
| <a name="input_regions"></a> [regions](#input\_regions) | Regiones del spoke: primary (primaria) y dr (recuperación). La de DR solo se usa con enable\_dr = true. | <pre>object({<br/>    primary = string<br/>    dr      = string<br/>  })</pre> | n/a | yes |
| <a name="input_subnet_cidrs"></a> [subnet\_cidrs](#input\_subnet\_cidrs) | Rangos del plan de direccionamiento. Llaves: app, proxy, run, gke\_master, pods, services, psa (siempre) y app\_dr, proxy\_dr, run\_dr, gke\_master\_dr, pods\_dr, services\_dr (obligatorias con enable\_dr = true). gke\_master y gke\_master\_dr son solo reservas: no crean subred. | `map(string)` | n/a | yes |
| <a name="input_enable_dr"></a> [enable\_dr](#input\_enable\_dr) | Crea las subredes, el router y el NAT de la región de DR (llaves *\_dr de subnet\_cidrs). En dev y qa las llaves *\_dr se reservan pero no se crean. | `bool` | `false` | no |
| <a name="input_flow_log_sampling"></a> [flow\_log\_sampling](#input\_flow\_log\_sampling) | Fracción de muestreo de los flow logs. La especificación pide 0.5 como mínimo; solo se permite subirla. Por defecto 1 (100 %, lo que pide el detector de CIS 3.10; ADR 0027). | `number` | `1` | no |
| <a name="input_region_short_names"></a> [region\_short\_names](#input\_region\_short\_names) | Mapa región → código corto que se agrega a los nombres de recursos regionales. | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_flow_log_sampling"></a> [flow\_log\_sampling](#output\_flow\_log\_sampling) | Mapa subred normal (llave de §5) → fracción de muestreo de sus flow logs (CIS 3.10, ADR 0027). |
| <a name="output_nat_names"></a> [nat\_names](#output\_nat\_names) | Mapa región → nombre del Cloud NAT. |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | ID de la VPC spoke (projects/<proyecto>/global/networks/<nombre>). |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Nombre de la VPC spoke. |
| <a name="output_network_self_link"></a> [network\_self\_link](#output\_network\_self\_link) | self\_link de la VPC spoke. |
| <a name="output_peerings"></a> [peerings](#output\_peerings) | Peerings con el hub, leídos de los recursos: spoke\_to\_hub y hub\_to\_spoke → { name, network, peer\_network, import\_custom\_routes, export\_custom\_routes }. El spoke importa y no exporta; el hub exporta y no importa. |
| <a name="output_psa_connection_id"></a> [psa\_connection\_id](#output\_psa\_connection\_id) | ID de la conexión de servicenetworking (para depends\_on de Cloud SQL, Memorystore y Filestore). |
| <a name="output_psa_range_name"></a> [psa\_range\_name](#output\_psa\_range\_name) | Nombre del rango reservado de Private Service Access. |
| <a name="output_reserved_cidrs"></a> [reserved\_cidrs](#output\_reserved\_cidrs) | Rangos reservados sin subred: gke\_master (y gke\_master\_dr con enable\_dr) para el plano de control de GKE. |
| <a name="output_routers"></a> [routers](#output\_routers) | Mapa región → nombre del Cloud Router del spoke. |
| <a name="output_subnets"></a> [subnets](#output\_subnets) | Llave del plan de direccionamiento → { self\_link, name, region, cidr, secondary\_ranges }. secondary\_ranges es un mapa nombre → CIDR con llaves pods y services (vacío en run, run\_dr, proxy y proxy\_dr). |
<!-- END_TF_DOCS -->
