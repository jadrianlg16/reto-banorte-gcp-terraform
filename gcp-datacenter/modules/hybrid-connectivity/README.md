# hybrid-connectivity

Crea la conectividad híbrida de una VPC sobre un Cloud Router existente: un gateway HA VPN,
dos túneles IKEv2 (uno por interfaz), la interfaz del router y la sesión BGP de cada túnel con
anuncios personalizados, y, solo con `enable_interconnect = true`, VLAN attachments de Cloud
Interconnect. La especificación (sección "Componentes del datacenter", conectividad híbrida)
exige dos túneles con BGP e Interconnect opcional: `bgp_sessions` se valida para tener
exactamente dos sesiones, una en la interfaz 0 y otra en la 1 (SLA de 99.99 %), con /30 propios
dentro de 169.254.0.0/16, e Interconnect queda apagado por defecto.

La punta remota (`peer`) es un gateway externo (`type = "external"`, con 1 o 2 IP) o el gateway
HA VPN de otra VPC (`type = "gcp"`). Para el on-premises simulado (ADR 0006) la raíz llama dos
veces al módulo, una por VPC, y cada instancia recibe el `gateway_self_link` de la otra; la
punta simulada invierte las IP de cada /30 con `router_ip` y `peer_ip`. `connection_name` evita
choques de nombres cuando las dos puntas viven en el mismo proyecto.

Secreto compartido: entra por `shared_secret`, variable `sensitive` sin valor por defecto y con
longitud mínima de 32. Ninguna salida lo expone. Es la interfaz más simple que funciona con
Terraform 1.9 (sin atributos de solo escritura): la raíz lo obtiene de
`data "google_secret_manager_secret_version"` con on-premises real o de un `random_password`
con on-premises simulado, y lo pasa a las dos puntas. En ambos casos el valor queda en el estado
de Terraform, cifrado con la llave CMEK del bucket de estado (ADR 0006 y 0008); se usa un mismo
secreto para los dos túneles.

Interconnect: en `DEDICATED` Google asigna las IP BGP del attachment y el módulo crea la
interfaz y la sesión con ellas; en `PARTNER` la sesión la configura el proveedor y el módulo
solo crea el attachment (la llave de emparejamiento se consulta en la consola o con gcloud; no
se publica como salida).

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
| [google_compute_external_vpn_gateway.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_external_vpn_gateway) | resource |
| [google_compute_ha_vpn_gateway.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_ha_vpn_gateway) | resource |
| [google_compute_interconnect_attachment.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_interconnect_attachment) | resource |
| [google_compute_router_interface.interconnect](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router_interface) | resource |
| [google_compute_router_interface.vpn](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router_interface) | resource |
| [google_compute_router_peer.interconnect](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router_peer) | resource |
| [google_compute_router_peer.vpn](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router_peer) | resource |
| [google_compute_vpn_tunnel.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_vpn_tunnel) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_advertised_ranges"></a> [advertised\_ranges](#input\_advertised\_ranges) | Rangos que el Cloud Router anuncia al par en estas sesiones (modo CUSTOM). En el hub: el /16 del hub, los /16 de los spokes y 35.199.192.0/19 (reenvío de Cloud DNS). | `list(string)` | n/a | yes |
| <a name="input_bgp_sessions"></a> [bgp\_sessions](#input\_bgp\_sessions) | Exactamente dos sesiones, una por interfaz del gateway HA VPN (0 y 1), para el SLA de<br/>99.99 %. Llave = nombre corto del túnel. ip\_range: /30 en 169.254.0.0/16. Por defecto el<br/>Cloud Router usa la primera IP del /30 y el par la segunda; la punta simulada las invierte<br/>con router\_ip y peer\_ip. peer\_external\_interface: interfaz del gateway externo (por<br/>defecto la misma que vpn\_gateway\_interface con 2 IP, o 0 con 1 IP). | <pre>map(object({<br/>    vpn_gateway_interface     = number<br/>    ip_range                  = string<br/>    router_ip                 = optional(string)<br/>    peer_ip                   = optional(string)<br/>    peer_external_interface   = optional(number)<br/>    advertised_route_priority = optional(number, 100)<br/>  }))</pre> | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes. Obligatorias: env, app, owner, cost\_center, managed\_by. | `map(string)` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | self\_link o ID de la VPC local donde se crea el gateway HA VPN. | `string` | n/a | yes |
| <a name="input_peer"></a> [peer](#input\_peer) | Punta remota. type = external: gateway on-premises con external\_gateway\_ips (1 IP,<br/>redundancia interna, o 2 IP, una por interfaz). type = gcp: gateway HA VPN de otra VPC<br/>(on-premises simulado, ADR 0006) en gcp\_gateway\_self\_link. asn: ASN del router remoto. | <pre>object({<br/>    type                  = string<br/>    asn                   = number<br/>    external_gateway_ips  = optional(list(string), [])<br/>    gcp_gateway_self_link = optional(string)<br/>  })</pre> | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (por ejemplo, bnt). | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto de la VPC local (net-hub, o el de la VPC simulada de on-premises). | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Región del gateway HA VPN, de los túneles y del Cloud Router. | `string` | n/a | yes |
| <a name="input_router"></a> [router](#input\_router) | Nombre del Cloud Router existente en la región (salida routers del módulo network-hub). Su ASN es el ASN local de las sesiones. | `string` | n/a | yes |
| <a name="input_shared_secret"></a> [shared\_secret](#input\_shared\_secret) | Secreto compartido IKE de los túneles. No tiene valor por defecto ni sale en ninguna salida: la raíz lo lee de Secret Manager (on-premises real) o lo genera con random\_password (on-premises simulado). Queda en el estado de Terraform, que está cifrado con CMEK. | `string` | n/a | yes |
| <a name="input_connection_name"></a> [connection\_name](#input\_connection\_name) | Nombre corto de la conexión, parte de los nombres de gateway, túneles y sesiones. Distingue las dos puntas cuando el hub y la VPC simulada de on-premises (ADR 0006) viven en el mismo proyecto (por ejemplo onprem y onprem-sim). | `string` | `"onprem"` | no |
| <a name="input_enable_interconnect"></a> [enable\_interconnect](#input\_enable\_interconnect) | Crea los VLAN attachments de Cloud Interconnect de interconnect\_attachments. Apagado por defecto. | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno que se usa en los nombres. La conectividad híbrida vive en common (hub). | `string` | `"common"` | no |
| <a name="input_interconnect_attachments"></a> [interconnect\_attachments](#input\_interconnect\_attachments) | VLAN attachments (solo con enable\_interconnect = true). type DEDICATED: interconnect (URL), y opcionales bandwidth, vlan\_tag y candidate\_subnets (/29 en 169.254.0.0/16); el módulo crea la interfaz y la sesión BGP. type PARTNER: edge\_availability\_domain; la sesión la configura el proveedor. | <pre>map(object({<br/>    type                     = optional(string, "DEDICATED")<br/>    interconnect             = optional(string)<br/>    edge_availability_domain = optional(string)<br/>    bandwidth                = optional(string)<br/>    vlan_tag                 = optional(number)<br/>    candidate_subnets        = optional(list(string), [])<br/>    mtu                      = optional(number, 1440)<br/>  }))</pre> | `{}` | no |
| <a name="input_region_short_names"></a> [region\_short\_names](#input\_region\_short\_names) | Mapa región → código corto que se agrega a los nombres de recursos regionales. | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bgp_peer_names"></a> [bgp\_peer\_names](#output\_bgp\_peer\_names) | Mapa llave de bgp\_sessions → nombre de la sesión BGP del Cloud Router. |
| <a name="output_external_gateway_self_link"></a> [external\_gateway\_self\_link](#output\_external\_gateway\_self\_link) | self\_link del gateway externo, o null con peer.type = gcp. |
| <a name="output_gateway_ip_addresses"></a> [gateway\_ip\_addresses](#output\_gateway\_ip\_addresses) | IP externas de las interfaces del gateway HA VPN, en orden de interfaz (para configurar el equipo on-premises). Se conocen hasta el apply. |
| <a name="output_gateway_self_link"></a> [gateway\_self\_link](#output\_gateway\_self\_link) | self\_link del gateway HA VPN (la otra punta lo usa como peer.gcp\_gateway\_self\_link en el modo simulado). |
| <a name="output_interconnect_attachment_names"></a> [interconnect\_attachment\_names](#output\_interconnect\_attachment\_names) | Mapa llave de interconnect\_attachments → nombre del VLAN attachment (vacío con enable\_interconnect = false). |
| <a name="output_tunnel_names"></a> [tunnel\_names](#output\_tunnel\_names) | Mapa llave de bgp\_sessions → nombre del túnel. |
<!-- END_TF_DOCS -->
