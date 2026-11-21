# firewall

Crea una política de firewall con sus reglas y su asociación, de uno de dos tipos
(`policy_type`): jerárquica, con padre y asociación en una organización o carpeta, o de red
global, creada en el proyecto de la VPC y asociada a ella. Crea además, si se piden, etiquetas
seguras (una llave con propósito `GCE_FIREWALL` y un valor por entrada de `secure_tags`) que las
reglas usan como origen o destino. La especificación (sección "Componentes del datacenter",
seguridad de red) exige denegar todo por defecto y reglas por etiqueta segura: el módulo crea
siempre una regla de denegación de entrada desde `0.0.0.0/0`, con registro y prioridad 65000,
que el llamador no puede quitar; las reglas del llamador solo admiten prioridades de 0 a 64999,
así que siempre se evalúan antes.

Decisiones del módulo:

- `policy_type` se pide aparte de `parent` porque la VPC del spoke se crea en el mismo plan y su
  `self_link` no se conoce hasta el apply; con él el número de recursos se sabe en el plan.
- Política jerárquica y denegación por defecto: una regla `deny` en la organización es final y
  las políticas de red de abajo no pueden permitir lo que ella deniega. Por eso la política
  jerárquica debe delegar con reglas `goto_next` el tráfico que decide cada spoke (rangos
  internos y on-premises) y permitir aquí solo lo común (verificaciones de salud e IAP). Las
  reglas `goto_next` no se registran.
- Etiquetas seguras: en una política de red la llave queda ligada a la VPC
  (`purpose_data.network = <proyecto>/<red>`) y vive en el proyecto de la VPC. Una política
  jerárquica no puede usar etiquetas ligadas a una VPC: la llave se crea en la organización con
  `purpose_data.organization = auto` y por eso exige `secure_tag_parent = organizations/<id>`
  (una carpeta no puede ser padre de una llave de etiqueta).
- Validaciones de reglas: prioridades únicas y fuera del rango reservado, origen obligatorio en
  INGRESS y destino en EGRESS, CIDR válidos, etiquetas que existan en `secure_tags`,
  `target_resources` solo en jerárquica y ninguna regla INGRESS `allow` desde `/0` (el tráfico
  externo llega por los rangos del balanceador).
- `enable_egress_default_deny` agrega la denegación de salida (prioridad 65001); por defecto la
  salida queda abierta y la controla el NAT y el VIP restringido.
- Para adjuntar una etiqueta a una VM o nodo, la cuenta que crea el recurso necesita
  `roles/resourcemanager.tagUser` sobre el valor (`secure_tag_ids`); ese permiso lo da la etapa
  que crea los proyectos de servicio.

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
| [google_compute_firewall_policy.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall_policy) | resource |
| [google_compute_firewall_policy_association.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall_policy_association) | resource |
| [google_compute_firewall_policy_rule.default_deny_egress](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall_policy_rule) | resource |
| [google_compute_firewall_policy_rule.default_deny_ingress](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall_policy_rule) | resource |
| [google_compute_firewall_policy_rule.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall_policy_rule) | resource |
| [google_compute_network_firewall_policy.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network_firewall_policy) | resource |
| [google_compute_network_firewall_policy_association.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network_firewall_policy_association) | resource |
| [google_compute_network_firewall_policy_rule.default_deny_egress](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network_firewall_policy_rule) | resource |
| [google_compute_network_firewall_policy_rule.default_deny_ingress](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network_firewall_policy_rule) | resource |
| [google_compute_network_firewall_policy_rule.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network_firewall_policy_rule) | resource |
| [google_tags_tag_key.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/tags_tag_key) | resource |
| [google_tags_tag_value.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/tags_tag_value) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno que se usa en los nombres: common (política jerárquica del hub), dev, qa o prod. | `string` | n/a | yes |
| <a name="input_parent"></a> [parent](#input\_parent) | Dónde vive y a qué se asocia la política. hierarchical: organizations/<id> o folders/<id>. network: self\_link o ID de la VPC (projects/<proyecto>/global/networks/<nombre>); la política se crea en ese proyecto. | `string` | n/a | yes |
| <a name="input_policy_type"></a> [policy\_type](#input\_policy\_type) | Tipo de política: hierarchical (parent = organizations/<id> o folders/<id>) o network (política de firewall de red global; parent = la VPC). Se pide aparte de parent porque la VPC suele crearse en el mismo plan y su self\_link no se conoce hasta el apply. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (por ejemplo, bnt). | `string` | n/a | yes |
| <a name="input_enable_egress_default_deny"></a> [enable\_egress\_default\_deny](#input\_enable\_egress\_default\_deny) | Además de la denegación de entrada (siempre presente), agrega una regla de salida que deniega todo con prioridad 65001. Con true, la salida necesaria (Google APIs, NAT, on-premises) debe permitirse con reglas EGRESS explícitas. | `bool` | `false` | no |
| <a name="input_rules"></a> [rules](#input\_rules) | Reglas de la política. Llave = nombre de la regla. priority entre 0 y 64999 (65000 en adelante se reserva para la denegación por defecto que crea el módulo). Las etiquetas seguras se refieren por su llave en secure\_tags. target\_resources (VPC) solo aplica a hierarchical. | <pre>map(object({<br/>    description             = optional(string, "")<br/>    priority                = number<br/>    direction               = optional(string, "INGRESS")<br/>    action                  = string<br/>    src_ip_ranges           = optional(list(string), [])<br/>    dest_ip_ranges          = optional(list(string), [])<br/>    src_secure_tags         = optional(list(string), [])<br/>    target_secure_tags      = optional(list(string), [])<br/>    target_service_accounts = optional(list(string), [])<br/>    target_resources        = optional(list(string), [])<br/>    enable_logging          = optional(bool, true)<br/>    layer4_configs = optional(list(object({<br/>      ip_protocol = string<br/>      ports       = optional(list(string), [])<br/>    })), [{ ip_protocol = "all" }])<br/>  }))</pre> | `{}` | no |
| <a name="input_secure_tag_parent"></a> [secure\_tag\_parent](#input\_secure\_tag\_parent) | Padre de la llave de etiqueta segura. Por defecto: projects/<proyecto de la VPC> en network. En hierarchical es obligatorio si hay secure\_tags y debe ser organizations/<id> (una carpeta no puede ser padre de una llave de etiqueta). | `string` | `null` | no |
| <a name="input_secure_tags"></a> [secure\_tags](#input\_secure\_tags) | Etiquetas seguras (valores de una llave con propósito GCE\_FIREWALL) que pueden usar las reglas. Llave = nombre lógico (por ejemplo lb\_backend, iap\_ssh). En network la llave de etiqueta queda ligada a la VPC; en hierarchical queda en la organización (purpose\_data organization = auto) y exige secure\_tag\_parent. | <pre>map(object({<br/>    description = optional(string, "")<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_policy_id"></a> [policy\_id](#output\_policy\_id) | ID de la política (locations/global/firewallPolicies/<id> en hierarchical; projects/<proyecto>/global/firewallPolicies/<nombre> en network). |
| <a name="output_policy_name"></a> [policy\_name](#output\_policy\_name) | Nombre de la política: ID numérico en hierarchical, nombre corto en network. |
| <a name="output_secure_tag_ids"></a> [secure\_tag\_ids](#output\_secure\_tag\_ids) | Mapa llave de secure\_tags → ID del valor de etiqueta (tagValues/<id>). Quien adjunta la etiqueta a una VM necesita roles/resourcemanager.tagUser sobre el valor. |
| <a name="output_secure_tag_key_id"></a> [secure\_tag\_key\_id](#output\_secure\_tag\_key\_id) | ID de la llave de etiqueta (tagKeys/<id>), o null si no hay secure\_tags. |
<!-- END_TF_DOCS -->
