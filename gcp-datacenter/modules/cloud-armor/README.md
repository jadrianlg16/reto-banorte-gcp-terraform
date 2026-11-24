# Módulo `cloud-armor`

Crea la política de seguridad de Cloud Armor (`google_compute_security_policy`) que protege al
balanceador HTTPS global externo de cada entorno, en el proyecto de servicio (ADR 0005). La
especificación, en su sección "Componentes del datacenter", pide reglas OWASP preconfiguradas
(como mínimo inyección SQL y XSS) y un límite de tasa. El módulo lo cumple así: los conjuntos
WAF llegan por `owasp_rules` y una validación impide quitar el de SQLi (`sqli-*`) o el de XSS
(`xss-*`), poner una sensibilidad de 0 o usar una acción distinta de `deny(...)`; ninguna regla
queda en modo `preview`. El límite de tasa (`rate_limit`) es siempre parte de la política, en
modo `throttle` o `rate_based_ban`. Además: regla por defecto, Adaptive Protection opcional (activa
por defecto), análisis de cuerpos JSON y nivel de registro configurable. Los valores por defecto
incluyen también LFI, RFI, RCE, métodos, escáneres, ataques de protocolo y fijación de sesión.
La regla `cve-canary` (CVE críticas, incluida Log4Shell) es fija y no se puede quitar.

La política no admite etiquetas en el proveedor, por eso el módulo no recibe `labels`.

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
| [google_compute_security_policy.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_security_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno: dev, qa o prod. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa para los nombres (§4.2), por ejemplo "bnt". | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto donde se crea la política de seguridad (el proyecto único, ADR 0029). | `string` | n/a | yes |
| <a name="input_cve_canary_priority"></a> [cve\_canary\_priority](#input\_cve\_canary\_priority) | Prioridad de la regla fija cve-canary (CVE críticas, incluida Log4Shell). | `number` | `1090` | no |
| <a name="input_default_rule_action"></a> [default\_rule\_action](#input\_default\_rule\_action) | Acción de la regla por defecto (prioridad 2147483647) para el tráfico que no coincide con otra regla. | `string` | `"allow"` | no |
| <a name="input_enable_adaptive_protection"></a> [enable\_adaptive\_protection](#input\_enable\_adaptive\_protection) | Activa Adaptive Protection (detección de DDoS de capa 7). Recomendado en prod. | `bool` | `true` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Nivel de detalle de los registros de Cloud Armor en los logs del balanceador: NORMAL o VERBOSE. | `string` | `"VERBOSE"` | no |
| <a name="input_name"></a> [name](#input\_name) | Nombre corto de la aplicación o del balanceador que protege la política; forma parte del nombre del recurso. | `string` | `"web"` | no |
| <a name="input_owasp_rules"></a> [owasp\_rules](#input\_owasp\_rules) | Reglas WAF preconfiguradas de Cloud Armor (conjuntos OWASP ModSecurity CRS). Llave: nombre del<br/>conjunto tal como lo acepta evaluatePreconfiguredWaf (por ejemplo "sqli-v33-stable").<br/>Valor: prioridad, sensibilidad (1 a 4; 0 desactiva todas las firmas y no se permite), acción de<br/>denegación y firmas excluidas. Deben estar siempre un conjunto sqli-* y uno xss-*. | <pre>map(object({<br/>    priority         = number<br/>    sensitivity      = optional(number, 1)<br/>    action           = optional(string, "deny(403)")<br/>    opt_out_rule_ids = optional(list(string), [])<br/>    description      = optional(string)<br/>  }))</pre> | <pre>{<br/>  "lfi-v33-stable": {<br/>    "description": "Inclusión de archivos locales",<br/>    "priority": 1020<br/>  },<br/>  "methodenforcement-v33-stable": {<br/>    "description": "Métodos HTTP no permitidos",<br/>    "priority": 1050<br/>  },<br/>  "protocolattack-v33-stable": {<br/>    "description": "Ataques al protocolo HTTP",<br/>    "priority": 1070<br/>  },<br/>  "rce-v33-stable": {<br/>    "description": "Ejecución remota de código",<br/>    "priority": 1040<br/>  },<br/>  "rfi-v33-stable": {<br/>    "description": "Inclusión de archivos remotos",<br/>    "priority": 1030<br/>  },<br/>  "scannerdetection-v33-stable": {<br/>    "description": "Escáneres automatizados",<br/>    "priority": 1060<br/>  },<br/>  "sessionfixation-v33-stable": {<br/>    "description": "Fijación de sesión",<br/>    "priority": 1080<br/>  },<br/>  "sqli-v33-stable": {<br/>    "description": "Inyección SQL",<br/>    "priority": 1000<br/>  },<br/>  "xss-v33-stable": {<br/>    "description": "Cross-site scripting",<br/>    "priority": 1010<br/>  }<br/>}</pre> | no |
| <a name="input_rate_limit"></a> [rate\_limit](#input\_rate\_limit) | Límite de tasa por cliente. action: "throttle" (limita y responde exceed\_action) o<br/>"rate\_based\_ban" (además bloquea al cliente ban\_duration\_sec segundos). count e interval\_sec<br/>definen el umbral; enforce\_on\_key define la llave de conteo (por defecto, la IP del cliente). | <pre>object({<br/>    action           = optional(string, "rate_based_ban")<br/>    priority         = optional(number, 900)<br/>    count            = optional(number, 500)<br/>    interval_sec     = optional(number, 60)<br/>    ban_duration_sec = optional(number, 600)<br/>    exceed_action    = optional(string, "deny(429)")<br/>    enforce_on_key   = optional(string, "IP")<br/>  })</pre> | `{}` | no |
| <a name="input_user_ip_request_headers"></a> [user\_ip\_request\_headers](#input\_user\_ip\_request\_headers) | Encabezados de los que Cloud Armor toma la IP del cliente (por ejemplo, cuando hay una CDN delante). Vacío: la IP de la conexión. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_policy_id"></a> [policy\_id](#output\_policy\_id) | ID de la política de seguridad. |
| <a name="output_policy_name"></a> [policy\_name](#output\_policy\_name) | Nombre de la política de seguridad. |
| <a name="output_policy_self_link"></a> [policy\_self\_link](#output\_policy\_self\_link) | self\_link de la política de seguridad, para el argumento security\_policy del módulo load-balancer. |
<!-- END_TF_DOCS -->
