# firewall

Crea una política de firewall de red global en el proyecto de una VPC, sus reglas y su
asociación con esa VPC. Crea además, si se piden, etiquetas seguras (por cada entrada de
`secure_tags`, una llave propia con propósito `GCE_FIREWALL` y un solo valor `enabled`) que las
reglas usan como origen o destino. La especificación (sección "Componentes del datacenter",
seguridad de red) exige denegar todo por defecto y reglas por etiqueta segura: el módulo crea
siempre una regla de denegación de entrada desde `0.0.0.0/0`, con registro y prioridad 65000,
que el llamador no puede quitar; las reglas del llamador solo admiten prioridades de 0 a 64999,
así que siempre se evalúan antes.

Decisiones del módulo:

- Solo política de red (ADR 0029 §6). Con toda la landing zone en un proyecto, sin carpetas y
  quizá sin organización, no hay dónde asociar una política jerárquica: la denegación por
  defecto que daba la organización la da ahora la política de cada VPC (hub, `onprem-sim` y
  cada spoke). Las reglas admiten solo `allow` y `deny`: la política de red es el último nivel
  configurado, y un `goto_next` solo pasaría a las reglas implícitas de la VPC.
- Una llave por etiqueta: un recurso admite un solo valor por llave de etiqueta, y una VM puede
  necesitar a la vez `lb_backend` e `iap_ssh`. Por eso cada entrada de `secure_tags` crea su
  llave `<prefix>-<environment>-net-fw-<entrada>` (guion bajo → guion) con un único valor
  `enabled`. Salidas: `secure_tag_ids` (entrada → `tagValues/…`) y `secure_tag_key_ids`
  (entrada → `tagKeys/…`).
- Etiquetas seguras con padre proyecto: la llave vive en el proyecto de la VPC y queda ligada a
  ella (`purpose_data.network = <proyecto>/<red>`). La
  [guía de etiquetas para firewalls](https://docs.cloud.google.com/firewall/docs/tags-firewalls-overview)
  dice que una llave puede tener padre proyecto y que, con propósito de red, debe apuntar a una
  VPC del mismo proyecto; que funcione en un proyecto sin organización es HYPOTHESIS
  (`VERIFICAR-EN-APPLY` en `main.tf`).
- Varias políticas en un proyecto: el nombre `<prefix>-<environment>-net-fw[-<name_suffix>]`
  distingue la de cada VPC (por ejemplo `bnt-common-net-fw-hub`, `bnt-common-net-fw-onprem-sim`
  y `bnt-dev-net-fw`), y lo mismo las llaves de etiqueta.
- Validaciones de reglas: prioridades únicas y fuera del rango reservado, nombres
  `default-deny-*` reservados, origen obligatorio en INGRESS y destino en EGRESS, CIDR válidos,
  etiquetas que existan en `secure_tags` y ninguna regla INGRESS `allow` desde un origen más
  amplio que `/8` (el tráfico externo llega por los rangos del balanceador).
- `enable_egress_default_deny` agrega la denegación de salida (prioridad 65001); por defecto la
  salida queda abierta y la controla el NAT y el VIP restringido.
- Las salidas `rules` y `default_deny_rules` se arman con los recursos de regla (no con la
  variable): prioridad, acción, orígenes, etiquetas destino traducidas a su llave lógica y
  protocolos. `network_id` sale del recurso de asociación. Sirven para que las pruebas de las
  raíces comprueben lo que de verdad se crea.
- Para adjuntar una etiqueta a una VM o nodo, la cuenta que crea el recurso necesita
  `roles/resourcemanager.tagUser` sobre el valor (`secure_tag_ids`); el módulo no lo otorga.

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
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno que se usa en los nombres: common (VPC hub y onprem-sim), dev, qa o prod. | `string` | n/a | yes |
| <a name="input_parent"></a> [parent](#input\_parent) | VPC a la que se asocia la política: self\_link o ID (projects/<proyecto>/global/networks/<nombre>). La política, sus reglas y las llaves de etiqueta se crean en ese proyecto. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (por ejemplo, bnt). | `string` | n/a | yes |
| <a name="input_enable_egress_default_deny"></a> [enable\_egress\_default\_deny](#input\_enable\_egress\_default\_deny) | Además de la denegación de entrada (siempre presente), agrega una regla de salida que deniega todo con prioridad 65001. Con true, la salida necesaria (Google APIs, NAT, on-premises) debe permitirse con reglas EGRESS explícitas. | `bool` | `false` | no |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Sufijo opcional del nombre de la política y de las llaves de etiqueta: <prefix>-<environment>-net-fw-<name\_suffix>. Vacío (por defecto): <prefix>-<environment>-net-fw. Sirve cuando un mismo proyecto tiene políticas de varias VPC del mismo entorno (por ejemplo hub y onprem-sim, las dos de common). | `string` | `""` | no |
| <a name="input_rules"></a> [rules](#input\_rules) | Reglas de la política. Llave = nombre de la regla. priority entre 0 y 64999 (65000 en adelante se reserva para la denegación por defecto que crea el módulo). action: allow o deny (la política de red es el último nivel: no hay a quién delegar). Las etiquetas seguras se refieren por su llave en secure\_tags. | <pre>map(object({<br/>    description             = optional(string, "")<br/>    priority                = number<br/>    direction               = optional(string, "INGRESS")<br/>    action                  = string<br/>    src_ip_ranges           = optional(list(string), [])<br/>    dest_ip_ranges          = optional(list(string), [])<br/>    src_secure_tags         = optional(list(string), [])<br/>    target_secure_tags      = optional(list(string), [])<br/>    target_service_accounts = optional(list(string), [])<br/>    enable_logging          = optional(bool, true)<br/>    layer4_configs = optional(list(object({<br/>      ip_protocol = string<br/>      ports       = optional(list(string), [])<br/>    })), [{ ip_protocol = "all" }])<br/>  }))</pre> | `{}` | no |
| <a name="input_secure_tags"></a> [secure\_tags](#input\_secure\_tags) | Etiquetas seguras que pueden usar las reglas. Cada entrada crea su propia llave con propósito GCE\_FIREWALL (<prefix>-<environment>-net-fw-<entrada>), con padre el proyecto de la VPC y ligada a ella, y un solo valor (enabled), para que un recurso pueda llevar varias a la vez. Llave = nombre lógico (por ejemplo lb\_backend, iap\_ssh). | <pre>map(object({<br/>    description = optional(string, "")<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_default_deny_rules"></a> [default\_deny\_rules](#output\_default\_deny\_rules) | Denegaciones por defecto que crea el módulo, leídas de los recursos: ingress (siempre) y egress (solo con enable\_egress\_default\_deny) → { priority, action, direction, enable\_logging, src\_ip\_ranges, dest\_ip\_ranges }. |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | VPC a la que quedó asociada la política (projects/<proyecto>/global/networks/<nombre>), leída del recurso de asociación. |
| <a name="output_policy_id"></a> [policy\_id](#output\_policy\_id) | ID de la política de firewall de red (projects/<proyecto>/global/firewallPolicies/<nombre>). |
| <a name="output_policy_name"></a> [policy\_name](#output\_policy\_name) | Nombre corto de la política de firewall de red. |
| <a name="output_rules"></a> [rules](#output\_rules) | Reglas creadas por el llamador, leídas de los recursos de regla (no de la variable rules): nombre → { priority, action, direction, enable\_logging, src\_ip\_ranges, dest\_ip\_ranges, target\_secure\_tags (llaves lógicas de secure\_tags), layer4\_configs }. No incluye las denegaciones por defecto del módulo (ver default\_deny\_rules). |
| <a name="output_secure_tag_ids"></a> [secure\_tag\_ids](#output\_secure\_tag\_ids) | Mapa llave de secure\_tags → ID del valor de etiqueta (tagValues/<id>). Quien adjunta la etiqueta a una VM necesita roles/resourcemanager.tagUser sobre el valor. |
| <a name="output_secure_tag_key_ids"></a> [secure\_tag\_key\_ids](#output\_secure\_tag\_key\_ids) | Mapa llave de secure\_tags → ID de su llave de etiqueta (tagKeys/<id>). Cada entrada es una llave propia con un solo valor (enabled); vacío si no hay secure\_tags. |
<!-- END_TF_DOCS -->
