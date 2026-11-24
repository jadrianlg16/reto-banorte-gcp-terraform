# Etapa `2-networks/envs/<env>` (spoke)

Raíz del spoke de un entorno (ADR 0029 §2 y §6; ADR 0003, 0004 y 0014). Las raíces
`envs/dev`, `envs/qa` y `envs/prod` son idénticas salvo `backend.tf` (prefijo
`2-networks/<env>`) y `terraform.tfvars.example`; las diferencias entre entornos entran solo
por variables (`environment`, `spoke_supernet`, `subnet_cidrs`, `enable_dr`).

Sin Shared VPC (ADR 0029 §6): la VPC del spoke vive en el proyecto único (`project_id`), el
mismo del hub y de las cargas del entorno (`3-workloads/envs/<env>`), que la usan directamente.
Ya no hay proyecto `net-spoke` ni salida `host_project_id`.

## Qué crea

En el proyecto `project_id`, todo con nombre `<prefix>-<env>-…` (regla de recursos únicos,
ADR 0029 §4):

- VPC `<prefix>-<env>-net-spoke` (módulo `network-spoke`): subredes `app` (rangos secundarios
  `pods` y `services`), `run` y `proxy` (proxy-only) en la región primaria, y sus `*_dr` en la
  región de DR solo con `enable_dr = true`; Private Google Access y flow logs
  (`flow_log_sampling`: 1 por defecto y en prod, 0.5 en los ejemplos de dev y qa por costo;
  CIS 3.10, ADR 0027); rango y conexión de Private Service Access propios de esta VPC (ADR
  0004); peering con el hub en los dos sentidos (el hub exporta rutas personalizadas, el spoke
  las importa; el lado del hub se crea sobre la VPC hub); rutas al VIP restringido y de salida
  por NAT; un Cloud Router con Cloud NAT por región activa (ADR 0004). `gke_master` y
  `gke_master_dr` quedan reservados, sin subred.
- Política de firewall de red `<prefix>-<env>-net-fw` asociada a la VPC (módulo `firewall`),
  con dos etiquetas seguras con padre el proyecto y ligadas a la VPC, **cada una con su propia
  llave y un solo valor `enabled`** (`<prefix>-<env>-net-fw-lb-backend` y
  `<prefix>-<env>-net-fw-iap-ssh`), para que una VM pueda llevar las dos. Reglas:

  | Regla | Prioridad | Origen | Destino | Puertos |
  |---|---|---|---|---|
  | `allow-lb-health-checks` | 1000 | 35.191.0.0/16, 130.211.0.0/22 | etiqueta `lb_backend` | TCP `lb_backend_ports` |
  | `allow-iap-ssh` | 1010 | 35.235.240.0/20 | etiqueta `iap_ssh` | TCP 22 |
  | `allow-proxy-to-backends` | 1020 | `proxy` (y `proxy_dr`) | etiqueta `lb_backend` | TCP `lb_backend_ports` |
  | `allow-gke-control-plane` | 1030 | `gke_master` (y `gke_master_dr`) | todas | TCP 443 y 10250 |
  | `allow-workload-internal` | 1040 | `app`, `pods`, `run` (y sus `*_dr`) | todas | todos |
  | `allow-filestore-nfs-callbacks` | 1050 | `psa` (Filestore) | todas | TCP 111, 2046, 4045; UDP 4045 (`filestore_nfs_lock_ports`) |
  | `default-deny-ingress` (módulo) | 65000 | 0.0.0.0/0 | todas | todos, con registro |

  Sin política jerárquica (ADR 0029 §6), esta política es la única que decide la entrada al
  spoke, con la misma intención que antes: la denegación por defecto que daba la organización
  la da ahora `default-deny-ingress`, y lo que la organización delegaba con `goto_next`
  (verificaciones de salud, IAP, tráfico interno y de on-premises) lo permiten estas reglas solo
  hacia donde hace falta. On-premises no tiene regla de entrada propia: llega a las cargas por
  el balanceador interno (proxies de la subred proxy-only). El tráfico de los otros entornos
  tampoco: no hay peering entre spokes y su rango no está en `allow-workload-internal`.

  `allow-filestore-nfs-callbacks` (con `enable_filestore_nfs_lock_callbacks = true`, por
  defecto) deja pasar las llamadas de Filestore a los clientes NFS para el bloqueo de archivos
  (portmapper, statd y nlockmgr; guía de firewall de Filestore de Google). Los puertos de statd
  y nlockmgr no tienen valor fijo en Linux: hay que fijarlos en las VM y nodos clientes a los
  de `filestore_nfs_lock_ports` (2046 y 4045 por defecto, los del ejemplo de Google). La salida
  `lb_backend_ports` publica los puertos abiertos hacia `lb_backend` para que la raíz de cargas
  compruebe los de sus backends.

  Para adjuntar una etiqueta a una VM o nodo, quien crea el recurso necesita
  `roles/resourcemanager.tagUser` sobre el valor (salida `secure_tags`). Esta raíz se lo da a la
  cuenta de cargas del entorno, `<prefix>-tf-wl-<env>`, solo sobre `lb_backend` e `iap_ssh`
  (`google_tags_tag_value_iam_member`; el correo se arma con `prefix`, `environment` y
  `project_id`, como en `0-bootstrap`), y `roles/resourcemanager.tagHoldAdmin` sobre
  `lb_backend` al agente de GKE (guía de GKE de etiquetas para firewalls). El `tagUser` de
  proyecto del agente de GKE y de `<número>@cloudservices` lo da `0-bootstrap`.
- DNS (módulo `dns`): zona privada `<env>.<dns_domain_base>` (por defecto
  `<env>.empresa.internal.`) adjunta a la VPC spoke y a la VPC hub (on-premises la resuelve por
  el reenvío entrante del hub; los otros entornos no la ven); zona de peering de
  `onprem_dns_domain` hacia la VPC hub; zona privada `googleapis.com.` con
  `<vip>.googleapis.com.` → VIP (registro A) y `*` → CNAME `<vip>.googleapis.com.`; zonas
  privadas `gcr.io.`, `pkg.dev.` y `run.app.` con el ápice → VIP (registro A) y `*` → CNAME al
  dominio (imágenes de Container y Artifact Registry y llamadas a Cloud Run por el VIP, no por
  IP públicas); política de servidor con registro de consultas. `<vip>` es `google_apis_vip`:
  `restricted` (199.36.153.4/30, por defecto en los tres entornos, ADR 0026) o `private`
  (199.36.153.8/30). Google recomienda `private` cuando no se usa VPC Service Controls; aquí el
  perímetro es opcional (solo con organización, ADR 0029 §1) y usar el mismo VIP en los tres
  entornos hace que una dependencia de una API sin soporte de VPC-SC falle antes de llegar a
  prod. La ruta al VIP restringido la crea `network-spoke`; el VIP privado lo cubre la ruta
  `0.0.0.0/0` del spoke.

No crea (regla de recursos únicos, ADR 0029 §4): APIs del proyecto (`compute`, `dns`,
`servicenetworking` y, para las Connectivity Tests de la prueba de humo, `networkmanagement`),
que habilita `0-bootstrap` una sola vez; métricas y alertas de auditoría (CIS 2.5 a 2.12), que
viven una sola vez en `1-base`; ni permisos de proyecto (solo IAM sobre sus valores de
etiqueta).

Validaciones del plan de direccionamiento (contrato §5): `spoke_supernet` es un /16, no se
traslapa con `onprem_cidrs` y coincide con `spoke_supernets[env]` del hub (lo que el hub
anuncia a on-premises; si el hub no tiene el entorno, el plan se detiene); cada rango de
`subnet_cidrs` cabe en `spoke_supernet` y no se traslapa con `onprem_cidrs`; las llaves `*_dr`
son obligatorias solo con `enable_dr = true`. El módulo `network-spoke` valida además las
llaves, el formato y el traslape entre rangos.

## Cómo se ejecuta

```sh
cd stages/2-networks/envs/<env>
cp terraform.tfvars.example terraform.tfvars   # ajustar valores
terraform init -backend-config="bucket=<state_bucket>"
terraform plan -out=tfplan
terraform apply tfplan
```

Orden (ADR 0029 §2): después del hub (`stages/2-networks`) y antes de las cargas del entorno.
**Los spokes se aplican de uno en uno** (dev, luego qa, luego prod), nunca en paralelo: cada
spoke crea su peering sobre la VPC hub y GCP no admite dos operaciones de peering a la vez
sobre la misma red. En el pipeline aplica la cuenta `<prefix>-tf-net-<env>` en el entorno de
GitHub `<env>`.

En `dev` y `qa` el ejemplo deja `enable_dr = false` (las llaves `*_dr` se reservan pero no se
crean); en `prod`, `true`. Destruir un spoke quita su VPC, su conexión de PSA y su peering con
el hub; el destroy de un entorno solo lo incluye con `incluir_red = true` (ADR 0029 §8).

## Permisos de la cuenta de servicio `<prefix>-tf-net-<env>`

Todos en el proyecto y otorgados por `0-bootstrap` (ADR 0029 §3). Lo que esta raíz necesita:

| Alcance | Rol | Para qué |
|---|---|---|
| Proyecto | `roles/compute.networkAdmin` | VPC, subredes, rutas, routers, NAT, PSA y el peering hub → spoke sobre la VPC hub |
| Proyecto | `roles/compute.securityAdmin` | Política de firewall de red, sus reglas y su asociación |
| Proyecto | `<prefix>TfNetworkTagManager` (rol personalizado de `0-bootstrap`) | Llaves y valores de las etiquetas seguras (padre: el proyecto) y su IAM; sin `*TagBinding`, `tagValueBindings` ni `tagHolds`, así que no liga ni quita etiquetas de recursos |
| Proyecto | `roles/dns.admin` | Zonas, registros y política de servidor; adjuntar la zona del entorno a la VPC hub y la zona de peering hacia ella (`dns.networks.bindPrivateDNSZone`, `dns.networks.targetWithPeeringZone`) |
| Proyecto | `roles/servicenetworking.networksAdmin` | Conexión de Private Service Access |
| Bucket de estado | escritura de `2-networks/<env>`, lectura de `2-networks/hub` | Estado |

Que estos roles alcancen (en especial `servicenetworking.networksAdmin` para la conexión de PSA
y el rol de etiquetas en un proyecto sin organización) es HYPOTHESIS (`VERIFICAR-EN-APPLY`).

Lectura de estado: `2-networks/hub` (`hub_network_self_link` y `spoke_supernets`, interfaz del
ADR 0029). ADR 0029 §2 permite además `1-base`, del que el spoke no usa ninguna salida.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_dns"></a> [dns](#module\_dns) | ../../../../modules/dns | n/a |
| <a name="module_firewall"></a> [firewall](#module\_firewall) | ../../../../modules/firewall | n/a |
| <a name="module_spoke"></a> [spoke](#module\_spoke) | ../../../../modules/network-spoke | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [google_tags_tag_value_iam_member.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/tags_tag_value_iam_member) | resource |
| [google_project.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/project) | data source |
| [terraform_remote_state.hub](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_dr_region"></a> [dr\_region](#input\_dr\_region) | Región de DR del spoke (subredes *\_dr, router y NAT; solo con enable\_dr = true). | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno del spoke: dev, qa o prod. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes de la raíz (app, owner, cost\_center y las que se agreguen). env y managed\_by las fija la raíz. | `map(string)` | n/a | yes |
| <a name="input_onprem_cidrs"></a> [onprem\_cidrs](#input\_onprem\_cidrs) | Rangos de on-premises, real o simulado (plan: 192.168.0.0/16). Ningún rango del spoke puede traslaparse con ellos. | `list(string)` | n/a | yes |
| <a name="input_onprem_dns_domain"></a> [onprem\_dns\_domain](#input\_onprem\_dns\_domain) | Dominio DNS de on-premises (el mismo que en el hub). El spoke lo resuelve con una zona de peering hacia la VPC hub. Termina en punto. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa en los nombres (por ejemplo, bnt). | `string` | n/a | yes |
| <a name="input_primary_region"></a> [primary\_region](#input\_primary\_region) | Región primaria del spoke (subredes app, proxy y run, router y NAT). | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | ID del proyecto único de la landing zone (ADR 0029 §1; salida project\_id de 0-bootstrap), el mismo del hub. Aquí se crean la VPC spoke y todo lo de esta raíz. Lo crea una persona: esta raíz no lo crea ni lo borra. | `string` | n/a | yes |
| <a name="input_spoke_supernet"></a> [spoke\_supernet](#input\_spoke\_supernet) | /16 del spoke (plan: 10.X.0.0/16 con X = 10 dev, 20 qa, 30 prod). Todos los rangos de subnet\_cidrs deben caber aquí y debe coincidir con spoke\_supernets[environment] del hub, que es lo que se anuncia a on-premises. | `string` | n/a | yes |
| <a name="input_state_bucket"></a> [state\_bucket](#input\_state\_bucket) | Bucket de estado de Terraform (salida state\_bucket de 0-bootstrap) del que se leen las etapas anteriores. | `string` | n/a | yes |
| <a name="input_subnet_cidrs"></a> [subnet\_cidrs](#input\_subnet\_cidrs) | Rangos del plan de direccionamiento (contrato §5). Llaves: app, proxy, run, gke\_master, pods, services, psa y sus *\_dr (app\_dr, proxy\_dr, run\_dr, gke\_master\_dr, pods\_dr, services\_dr), obligatorias solo con enable\_dr = true. | `map(string)` | n/a | yes |
| <a name="input_dns_domain_base"></a> [dns\_domain\_base](#input\_dns\_domain\_base) | Dominio base de las zonas privadas por entorno: la zona del spoke es <environment>.<dns\_domain\_base>. Termina en punto. | `string` | `"empresa.internal."` | no |
| <a name="input_enable_dr"></a> [enable\_dr](#input\_enable\_dr) | Crea las subredes, el router y el NAT de la región de DR. En dev y qa las llaves *\_dr se reservan pero no se crean (false). | `bool` | `false` | no |
| <a name="input_enable_filestore_nfs_lock_callbacks"></a> [enable\_filestore\_nfs\_lock\_callbacks](#input\_enable\_filestore\_nfs\_lock\_callbacks) | Permite la entrada desde el rango de Private Service Access (donde viven las instancias de Filestore) hacia las cargas en los puertos de filestore\_nfs\_lock\_ports. Filestore llama de vuelta a los clientes para el bloqueo de archivos NFS (statd y nlockmgr); sin esta regla la denegación por defecto del spoke corta esas llamadas. | `bool` | `true` | no |
| <a name="input_filestore_nfs_lock_ports"></a> [filestore\_nfs\_lock\_ports](#input\_filestore\_nfs\_lock\_ports) | Puertos de los clientes NFS a los que llama Filestore para el bloqueo de archivos: tcp = 111 (portmapper), el de statd (STATDOPTS) y el TCP de nlockmgr (nlm\_tcpport); udp = el UDP de nlockmgr (nlm\_udpport, niveles Zonal, Regional y Enterprise). Por defecto 2046 y 4045, los que usa la guía de Google para fijar esos puertos; deben coincidir con lo que se fije en las VM y nodos clientes. | <pre>object({<br/>    tcp = list(string)<br/>    udp = list(string)<br/>  })</pre> | <pre>{<br/>  "tcp": [<br/>    "111",<br/>    "2046",<br/>    "4045"<br/>  ],<br/>  "udp": [<br/>    "4045"<br/>  ]<br/>}</pre> | no |
| <a name="input_flow_log_sampling"></a> [flow\_log\_sampling](#input\_flow\_log\_sampling) | Fracción de muestreo de los flow logs de las subredes. La especificación pide 0.5; solo se permite subirla. Por defecto 1 (100 %, CIS 3.10); los ejemplos de dev y qa usan 0.5 por costo (ADR 0027). | `number` | `1` | no |
| <a name="input_google_apis_vip"></a> [google\_apis\_vip](#input\_google\_apis\_vip) | VIP de Private Google Access al que resuelven las zonas privadas googleapis.com., gcr.io., pkg.dev. y run.app.: restricted (199.36.153.4/30, solo servicios compatibles con VPC Service Controls) o private (199.36.153.8/30, todos). Por defecto restricted en los tres entornos (ADR 0026): con organización, el perímetro opcional de VPC-SC rodea todo el proyecto (ADR 0029 §1), y usar el mismo VIP en todos hace que una dependencia de una API sin soporte de VPC-SC falle antes de llegar a prod. | `string` | `"restricted"` | no |
| <a name="input_lb_backend_ports"></a> [lb\_backend\_ports](#input\_lb\_backend\_ports) | Puertos TCP en los que los backends con la etiqueta lb\_backend reciben tráfico y verificaciones de salud de los balanceadores. | `list(string)` | <pre>[<br/>  "80",<br/>  "443",<br/>  "8080"<br/>]</pre> | no |
| <a name="input_region_short_names"></a> [region\_short\_names](#input\_region\_short\_names) | Mapa región → código corto que se agrega a los nombres de recursos regionales (contrato §4.2). | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_dns_zone_names"></a> [dns\_zone\_names](#output\_dns\_zone\_names) | Mapa env, onprem, googleapis, gcr, pkg, run → nombre de la zona de Cloud DNS. |
| <a name="output_firewall_policy_id"></a> [firewall\_policy\_id](#output\_firewall\_policy\_id) | ID de la política de firewall de red del spoke (projects/<proyecto>/global/firewallPolicies/<nombre>). |
| <a name="output_firewall_policy_rules"></a> [firewall\_policy\_rules](#output\_firewall\_policy\_rules) | Reglas de la política de red creadas por la raíz, leídas de los recursos (nombre → prioridad, acción, orígenes, etiquetas destino y protocolos/puertos). Además, el módulo crea la denegación por defecto de la entrada (prioridad 65000, con registro), que antes daba la política jerárquica. |
| <a name="output_lb_backend_ports"></a> [lb\_backend\_ports](#output\_lb\_backend\_ports) | Puertos TCP que la política del spoke abre hacia los backends con lb\_backend (verificaciones de salud y proxies). La raíz de cargas del entorno comprueba que los puertos de sus backends estén aquí. |
| <a name="output_nat_names"></a> [nat\_names](#output\_nat\_names) | Mapa región → nombre del Cloud NAT. |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | ID de la VPC spoke (projects/<proyecto>/global/networks/<nombre>). |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Nombre de la VPC spoke. |
| <a name="output_network_self_link"></a> [network\_self\_link](#output\_network\_self\_link) | self\_link de la VPC spoke. |
| <a name="output_private_dns_domain"></a> [private\_dns\_domain](#output\_private\_dns\_domain) | Dominio de la zona privada del entorno (<env>.empresa.internal. por defecto). |
| <a name="output_psa_range_name"></a> [psa\_range\_name](#output\_psa\_range\_name) | Nombre del rango reservado de Private Service Access. |
| <a name="output_reserved_cidrs"></a> [reserved\_cidrs](#output\_reserved\_cidrs) | Rangos reservados sin subred (plano de control de GKE: gke\_master y, con enable\_dr, gke\_master\_dr). |
| <a name="output_routers"></a> [routers](#output\_routers) | Mapa región → nombre del Cloud Router del spoke. |
| <a name="output_secure_tag_keys"></a> [secure\_tag\_keys](#output\_secure\_tag\_keys) | Etiquetas seguras lb\_backend e iap\_ssh → ID de su llave de etiqueta (tagKeys/…). |
| <a name="output_secure_tags"></a> [secure\_tags](#output\_secure\_tags) | Etiquetas seguras lb\_backend e iap\_ssh → ID del valor de etiqueta (tagValues/…). |
| <a name="output_subnets"></a> [subnets](#output\_subnets) | Llave del plan de direccionamiento → { self\_link, name, region, cidr, secondary\_ranges } (secondary\_ranges: nombre → CIDR, llaves pods y services en app y app\_dr). |
<!-- END_TF_DOCS -->
