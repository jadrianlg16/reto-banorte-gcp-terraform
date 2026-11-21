# dns

Crea zonas administradas de Cloud DNS, todas con visibilidad privada y adjuntas a las VPC de
`networks` (o a las de cada zona), de tres tipos: `private` (con registros propios),
`forwarding` (reenvío condicional a servidores DNS, por ejemplo on-premises) y `peering`
(resuelve con otra VPC, por ejemplo el hub). Opcionalmente crea la política de servidor con
reenvío entrante y registro de consultas. La especificación (sección "Componentes del
datacenter", DNS) exige zonas privadas por entorno y reenvío condicional a on-premises: el
módulo no admite zonas públicas y valida que una zona `forwarding` tenga servidores destino.

Con este módulo se expresan las zonas del contrato:

- privada del entorno `<env>.empresa.internal.` (`type = "private"`);
- reenvío hacia los servidores on-premises en el hub (`type = "forwarding"`, con
  `forwarding_path = "private"` para que el tráfico vaya por la VPN);
- peering desde cada spoke hacia el hub para el dominio on-premises (`type = "peering"`);
- `googleapis.com.` privada con el registro A `restricted` → 199.36.153.4/30 y el CNAME `*` →
  `restricted.googleapis.com.`, y `gcr.io.`, `pkg.dev.` y `run.app.` privadas con el ápice →
  VIP y el CNAME `*` → dominio (los registros solo se admiten en zonas `private`; `name = ""`
  es el ápice).

Las salidas `zones` (VPC adjuntas, red de peering y servidores de reenvío) y `records` se leen
de los recursos creados, para que las pruebas de las raíces comprueben lo que de verdad se crea.

`inbound_forwarder_ips`: GCP asigna las direcciones de reenvío entrante al aplicar la política
(una por región con subred) y el proveedor no las expone en `google_dns_policy`; el módulo las lee
con el origen de datos `google_compute_addresses` filtrado por propósito `DNS_RESOLVER`, así que
se conocen hasta el apply (marcado `VERIFICAR-EN-APPLY`). Una VPC admite una sola política de
servidor: si un spoke necesita registro de consultas, usa `server_policy` con
`enable_inbound_forwarding = false`.

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
| [google_dns_managed_zone.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/dns_managed_zone) | resource |
| [google_dns_policy.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/dns_policy) | resource |
| [google_dns_record_set.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/dns_record_set) | resource |
| [google_compute_addresses.inbound_forwarders](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/compute_addresses) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno que se usa en los nombres: common (hub), dev, qa o prod. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes. Obligatorias: env, app, owner, cost\_center, managed\_by. | `map(string)` | n/a | yes |
| <a name="input_networks"></a> [networks](#input\_networks) | self\_link (o ID) de las VPC a las que se adjuntan las zonas (y la política de servidor) cuando la zona no indica las suyas. | `list(string)` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (por ejemplo, bnt). | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto donde se crean las zonas y la política de servidor (el de la VPC). | `string` | n/a | yes |
| <a name="input_zones"></a> [zones](#input\_zones) | Zonas administradas. Llave = nombre lógico (forma parte del nombre de la zona). type:<br/>private (zona privada; admite records), forwarding (reenvío condicional a<br/>target\_name\_servers) o peering (resuelve con la VPC peer\_network). domain termina en punto.<br/>records: llave libre → { name (relativo al dominio; "" es el ápice), type, ttl, rrdatas }. | <pre>map(object({<br/>    type        = string<br/>    domain      = string<br/>    description = optional(string, "")<br/>    networks    = optional(list(string))<br/>    target_name_servers = optional(list(object({<br/>      ipv4_address    = string<br/>      forwarding_path = optional(string, "default")<br/>    })), [])<br/>    peer_network = optional(string)<br/>    records = optional(map(object({<br/>      name    = string<br/>      type    = string<br/>      ttl     = optional(number, 300)<br/>      rrdatas = list(string)<br/>    })), {})<br/>  }))</pre> | n/a | yes |
| <a name="input_server_policy"></a> [server\_policy](#input\_server\_policy) | Política de servidor DNS opcional sobre networks: enable\_inbound\_forwarding crea direcciones de reenvío entrante (una por región con subred) para que on-premises resuelva las zonas de Cloud DNS; enable\_logging registra las consultas. | <pre>object({<br/>    enable_inbound_forwarding = optional(bool, true)<br/>    enable_logging            = optional(bool, true)<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_inbound_forwarder_ips"></a> [inbound\_forwarder\_ips](#output\_inbound\_forwarder\_ips) | IP de reenvío entrante que on-premises usa para resolver las zonas de Cloud DNS (lista vacía sin reenvío entrante). Se conocen hasta el apply. |
| <a name="output_policy_name"></a> [policy\_name](#output\_policy\_name) | Nombre de la política de servidor DNS, o null si no se creó. |
| <a name="output_records"></a> [records](#output\_records) | Registros creados, leídos de los recursos: <zona>/<registro> → { name, type, rrdatas }. |
| <a name="output_zone_domains"></a> [zone\_domains](#output\_zone\_domains) | Mapa llave de zones → dominio DNS. |
| <a name="output_zone_names"></a> [zone\_names](#output\_zone\_names) | Mapa llave de zones → nombre de la zona administrada. |
| <a name="output_zones"></a> [zones](#output\_zones) | Zonas creadas, leídas de los recursos: llave de zones → { name, dns\_name, networks (VPC con visibilidad, ordenadas), peer\_network (null si no es de peering), forwarding\_targets (IP, vacío si no es de reenvío) }. |
<!-- END_TF_DOCS -->
