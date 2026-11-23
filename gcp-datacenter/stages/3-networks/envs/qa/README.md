# Etapa `3-networks/envs/<env>` (spoke)

Raíz del spoke de un entorno (contrato §7.4, ADR 0003, 0004 y 0014). Las raíces
`envs/dev`, `envs/qa` y `envs/prod` son idénticas salvo `backend.tf` (prefijo
`3-networks/<env>`) y `terraform.tfvars.example`; las diferencias entre entornos entran solo
por variables (`environment`, `spoke_supernet`, `subnet_cidrs`, `enable_dr`).

## Qué crea

- Proyecto `<prefix>-<env>-net-spoke[-<project_suffix>]` en la carpeta del entorno
  (`folder_ids[env]` de `1-org`), habilitado como host de Shared VPC (módulo
  `project-factory`), con las APIs de Compute, DNS, Service Networking, GKE (un clúster de un
  proyecto de servicio sobre Shared VPC exige la API también en el host) y Network Management
  (las Connectivity Tests de la prueba de humo de dev se crean en este proyecto).
- VPC `<prefix>-<env>-net-spoke` (módulo `network-spoke`): subredes `app` (rangos secundarios
  `pods` y `services`), `run` y `proxy` (proxy-only) en la región primaria, y sus `*_dr` en la
  región de DR solo con `enable_dr = true`; Private Google Access y flow logs al 50 %
  (`flow_log_sampling`); rango y conexión de Private Service Access; peering con el hub en
  los dos sentidos (el hub exporta rutas personalizadas, el spoke las importa); rutas al VIP
  restringido y de salida por NAT; un Cloud Router con Cloud NAT por región activa (ADR 0004).
  `gke_master` y `gke_master_dr` quedan reservados, sin subred.
- Política de firewall de red `<prefix>-<env>-net-fw` asociada a la VPC (módulo `firewall`),
  con dos etiquetas seguras, **cada una con su propia llave y un solo valor `enabled`**
  (`<prefix>-<env>-net-fw-lb-backend` y `<prefix>-<env>-net-fw-iap-ssh`), para que una VM pueda
  llevar las dos. Reglas:

  | Regla | Prioridad | Origen | Destino | Puertos |
  |---|---|---|---|---|
  | `allow-lb-health-checks` | 1000 | 35.191.0.0/16, 130.211.0.0/22 | etiqueta `lb_backend` | TCP `lb_backend_ports` |
  | `allow-iap-ssh` | 1010 | 35.235.240.0/20 | etiqueta `iap_ssh` | TCP 22 |
  | `allow-proxy-to-backends` | 1020 | `proxy` (y `proxy_dr`) | etiqueta `lb_backend` | TCP `lb_backend_ports` |
  | `allow-gke-control-plane` | 1030 | `gke_master` (y `gke_master_dr`) | todas | TCP 443 y 10250 |
  | `allow-workload-internal` | 1040 | `app`, `pods`, `run` (y sus `*_dr`) | todas | todos |
  | `allow-filestore-nfs-callbacks` | 1050 | `psa` (Filestore) | todas | TCP 111, 2046, 4045; UDP 4045 (`filestore_nfs_lock_ports`) |
  | denegación por defecto (módulo) | 65000 | 0.0.0.0/0 | todas | todos, con registro |

  On-premises no tiene regla de entrada propia: llega a las cargas por el balanceador interno
  (proxies de la subred proxy-only). La política jerárquica del hub no permite nada: delega con
  `goto_next` las verificaciones de salud, el IAP, el tráfico interno y el de on-premises, así
  que `allow-lb-health-checks` y `allow-iap-ssh` son las reglas que de verdad los permiten, y
  solo hacia las VM con la etiqueta correspondiente (ver la nota del README del hub).

  `allow-filestore-nfs-callbacks` (con `enable_filestore_nfs_lock_callbacks = true`, por
  defecto) deja pasar las llamadas de Filestore a los clientes NFS para el bloqueo de archivos
  (portmapper, statd y nlockmgr; guía de firewall de Filestore de Google). Los puertos de statd
  y nlockmgr no tienen valor fijo en Linux: hay que fijarlos en las VM y nodos clientes a los
  de `filestore_nfs_lock_ports` (2046 y 4045 por defecto, los del ejemplo de Google). La salida
  `lb_backend_ports` publica los puertos abiertos hacia `lb_backend` para que la etapa 5
  compruebe los de sus backends.
- DNS (módulo `dns`): zona privada `<env>.<dns_domain_base>` (por defecto
  `<env>.empresa.internal.`) adjunta a la VPC spoke y a la VPC hub (on-premises la resuelve por
  el reenvío entrante del hub; los otros entornos no la ven); zona de peering de
  `onprem_dns_domain` hacia la VPC hub; zona privada `googleapis.com.` con
  `<vip>.googleapis.com.` → VIP (registro A) y `*` → CNAME `<vip>.googleapis.com.`; zonas
  privadas `gcr.io.`, `pkg.dev.` y `run.app.` con el ápice → VIP (registro A) y `*` → CNAME al
  dominio (imágenes de Container y Artifact Registry y llamadas a Cloud Run por el VIP, no por
  IP públicas); política de servidor con registro de consultas. `<vip>` es `google_apis_vip`:
  `restricted` (199.36.153.4/30, por defecto en los tres entornos) o `private`
  (199.36.153.8/30). Google recomienda `private` cuando no se usa VPC Service Controls; aquí
  prod tiene perímetro y dev y qa usan el mismo VIP para que una dependencia de una API sin
  soporte de VPC-SC falle antes de llegar a prod. La ruta al VIP restringido la crea
  `network-spoke`; el VIP privado lo cubre la ruta `0.0.0.0/0` del spoke.

Validaciones del plan de direccionamiento (contrato §5): `spoke_supernet` es un /16, no se
traslapa con `onprem_cidrs` y coincide con `spoke_supernets[env]` del hub (lo que el hub
anuncia a on-premises); cada rango de `subnet_cidrs` cabe en `spoke_supernet` y no se traslapa
con `onprem_cidrs`; las llaves `*_dr` son obligatorias solo con `enable_dr = true`. El módulo
`network-spoke` valida además las llaves, el formato y el traslape entre rangos.

## Cómo se ejecuta

```sh
cd stages/3-networks/envs/<env>
cp terraform.tfvars.example terraform.tfvars   # ajustar valores
terraform init -backend-config="bucket=<state_bucket>"
terraform plan -out=tfplan
terraform apply tfplan
```

Orden: después del hub (`stages/3-networks`). **Los spokes se aplican de uno en uno** (dev,
luego qa, luego prod), nunca en paralelo: cada spoke crea su peering sobre la VPC hub y GCP no
admite dos operaciones de peering a la vez sobre la misma red.

En `dev` y `qa` el ejemplo deja `enable_dr = false` (las llaves `*_dr` se reservan pero no se
crean); en `prod`, `true`. `project_deletion_policy` vale `PREVENT` por defecto; para
desmontar dev (prueba de extremo a extremo) se usa `DELETE`, que `project-factory` rechaza en
prod.

## Roles de la cuenta de servicio `<prefix>-tf-3-networks`

Para los spokes:

| Alcance | Rol | Lo asigna | Para qué |
|---|---|---|---|
| Organización | `roles/resourcemanager.organizationViewer` | 0-bootstrap | Leer la organización |
| Cuenta de facturación | `roles/billing.user` | 0-bootstrap | Asociar el proyecto net-spoke |
| Proyecto semilla | `roles/serviceusage.serviceUsageConsumer` | 0-bootstrap | Proyecto de cuota |
| Bucket de estado | §6.2: escritura en `3-networks/<env>`, lectura de `1-org` y `3-networks/hub` | 0-bootstrap | Estado |
| Carpetas `dev`, `qa`, `prod` | `roles/resourcemanager.projectCreator` | 1-org | Crear el proyecto net-spoke |
| Carpetas `dev`, `qa`, `prod` | `roles/compute.xpnAdmin` | 1-org | Habilitar el host de Shared VPC |
| Proyecto `net-spoke` | `roles/owner` (implícito) | GCP, al crear el proyecto | APIs, VPC, subredes, rutas, routers, NAT, PSA, política de firewall de red, etiquetas seguras y DNS dentro del proyecto: no hace falta ningún rol más en las carpetas |
| Proyecto `net-hub` | `roles/compute.networkAdmin` | 1-org | Peering hub → spoke sobre la VPC hub |
| Proyecto `net-hub` | `roles/dns.admin` | 1-org | Adjuntar la zona privada del entorno a la VPC hub y zona de peering hacia ella (`dns.networks.bindPrivateDNSZone`, `dns.networks.targetWithPeeringZone`) |

`VERIFICAR-EN-APPLY`: que la cuenta que crea `net-spoke` quede como dueña del proyecto (lo hace
GCP al crear un proyecto) y que la política de organización no lo impida.

Lectura de estado: `1-org` (`folder_ids`) y `3-networks/hub` (`hub_network_self_link` y la
salida adicional `spoke_supernets`). §6.1 permite además `0-bootstrap`, que el spoke no
necesita.

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
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_dns"></a> [dns](#module\_dns) | ../../../../modules/dns | n/a |
| <a name="module_firewall"></a> [firewall](#module\_firewall) | ../../../../modules/firewall | n/a |
| <a name="module_project"></a> [project](#module\_project) | ../../../../modules/project-factory | n/a |
| <a name="module_spoke"></a> [spoke](#module\_spoke) | ../../../../modules/network-spoke | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [terraform_remote_state.hub](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |
| [terraform_remote_state.org](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | Cuenta de facturación del proyecto net-spoke (formato XXXXXX-XXXXXX-XXXXXX). | `string` | n/a | yes |
| <a name="input_dr_region"></a> [dr\_region](#input\_dr\_region) | Región de DR del spoke (subredes *\_dr, router y NAT; solo con enable\_dr = true). | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Entorno del spoke: dev, qa o prod. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes de la raíz (app, owner, cost\_center y las que se agreguen). env y managed\_by las fija la raíz. | `map(string)` | n/a | yes |
| <a name="input_onprem_cidrs"></a> [onprem\_cidrs](#input\_onprem\_cidrs) | Rangos de on-premises, real o simulado (plan: 192.168.0.0/16). Ningún rango del spoke puede traslaparse con ellos. | `list(string)` | n/a | yes |
| <a name="input_onprem_dns_domain"></a> [onprem\_dns\_domain](#input\_onprem\_dns\_domain) | Dominio DNS de on-premises (el mismo que en el hub). El spoke lo resuelve con una zona de peering hacia la VPC hub. Termina en punto. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa en los nombres (por ejemplo, bnt). | `string` | n/a | yes |
| <a name="input_primary_region"></a> [primary\_region](#input\_primary\_region) | Región primaria del spoke (subredes app, proxy y run, router y NAT). | `string` | n/a | yes |
| <a name="input_spoke_supernet"></a> [spoke\_supernet](#input\_spoke\_supernet) | /16 del spoke (plan: 10.X.0.0/16 con X = 10 dev, 20 qa, 30 prod). Todos los rangos de subnet\_cidrs deben caber aquí y debe coincidir con spoke\_supernets[environment] del hub, que es lo que se anuncia a on-premises. | `string` | n/a | yes |
| <a name="input_state_bucket"></a> [state\_bucket](#input\_state\_bucket) | Bucket de estado de Terraform (salida state\_bucket de 0-bootstrap) del que se leen las etapas anteriores. | `string` | n/a | yes |
| <a name="input_subnet_cidrs"></a> [subnet\_cidrs](#input\_subnet\_cidrs) | Rangos del plan de direccionamiento (contrato §5). Llaves: app, proxy, run, gke\_master, pods, services, psa y sus *\_dr (app\_dr, proxy\_dr, run\_dr, gke\_master\_dr, pods\_dr, services\_dr), obligatorias solo con enable\_dr = true. | `map(string)` | n/a | yes |
| <a name="input_dns_domain_base"></a> [dns\_domain\_base](#input\_dns\_domain\_base) | Dominio base de las zonas privadas por entorno: la zona del spoke es <environment>.<dns\_domain\_base>. Termina en punto. | `string` | `"empresa.internal."` | no |
| <a name="input_enable_dr"></a> [enable\_dr](#input\_enable\_dr) | Crea las subredes, el router y el NAT de la región de DR. En dev y qa las llaves *\_dr se reservan pero no se crean (false). | `bool` | `false` | no |
| <a name="input_enable_filestore_nfs_lock_callbacks"></a> [enable\_filestore\_nfs\_lock\_callbacks](#input\_enable\_filestore\_nfs\_lock\_callbacks) | Permite la entrada desde el rango de Private Service Access (donde viven las instancias de Filestore) hacia las cargas en los puertos de filestore\_nfs\_lock\_ports. Filestore llama de vuelta a los clientes para el bloqueo de archivos NFS (statd y nlockmgr); sin esta regla la denegación por defecto del spoke corta esas llamadas. | `bool` | `true` | no |
| <a name="input_filestore_nfs_lock_ports"></a> [filestore\_nfs\_lock\_ports](#input\_filestore\_nfs\_lock\_ports) | Puertos de los clientes NFS a los que llama Filestore para el bloqueo de archivos: tcp = 111 (portmapper), el de statd (STATDOPTS) y el TCP de nlockmgr (nlm\_tcpport); udp = el UDP de nlockmgr (nlm\_udpport, niveles Zonal, Regional y Enterprise). Por defecto 2046 y 4045, los que usa la guía de Google para fijar esos puertos; deben coincidir con lo que se fije en las VM y nodos clientes. | <pre>object({<br/>    tcp = list(string)<br/>    udp = list(string)<br/>  })</pre> | <pre>{<br/>  "tcp": [<br/>    "111",<br/>    "2046",<br/>    "4045"<br/>  ],<br/>  "udp": [<br/>    "4045"<br/>  ]<br/>}</pre> | no |
| <a name="input_flow_log_sampling"></a> [flow\_log\_sampling](#input\_flow\_log\_sampling) | Fracción de muestreo de los flow logs de las subredes. La especificación pide 0.5; solo se permite subirla. | `number` | `0.5` | no |
| <a name="input_google_apis_vip"></a> [google\_apis\_vip](#input\_google\_apis\_vip) | VIP de Private Google Access al que resuelven las zonas privadas googleapis.com., gcr.io., pkg.dev. y run.app.: restricted (199.36.153.4/30, solo servicios compatibles con VPC Service Controls) o private (199.36.153.8/30, todos). Por defecto restricted en los tres entornos: prod tiene perímetro y dev/qa usan el mismo VIP para que una dependencia de una API sin soporte de VPC-SC falle antes de llegar a prod. | `string` | `"restricted"` | no |
| <a name="input_lb_backend_ports"></a> [lb\_backend\_ports](#input\_lb\_backend\_ports) | Puertos TCP en los que los backends con la etiqueta lb\_backend reciben tráfico y verificaciones de salud de los balanceadores. | `list(string)` | <pre>[<br/>  "80",<br/>  "443",<br/>  "8080"<br/>]</pre> | no |
| <a name="input_project_deletion_policy"></a> [project\_deletion\_policy](#input\_project\_deletion\_policy) | deletion\_policy del proyecto net-spoke: PREVENT (por defecto), ABANDON o DELETE. El módulo project-factory solo admite PREVENT en prod; DELETE sirve para desmontar dev en la prueba de extremo a extremo. | `string` | `"PREVENT"` | no |
| <a name="input_project_suffix"></a> [project\_suffix](#input\_project\_suffix) | Sufijo opcional para que el ID del proyecto net-spoke sea único a nivel mundial. Vacío: sin sufijo. | `string` | `""` | no |
| <a name="input_region_short_names"></a> [region\_short\_names](#input\_region\_short\_names) | Mapa región → código corto que se agrega a los nombres de recursos regionales (contrato §4.2). | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_dns_zone_names"></a> [dns\_zone\_names](#output\_dns\_zone\_names) | Mapa env, onprem, googleapis, gcr, pkg, run → nombre de la zona de Cloud DNS. |
| <a name="output_firewall_policy_id"></a> [firewall\_policy\_id](#output\_firewall\_policy\_id) | ID de la política de firewall de red del spoke. |
| <a name="output_firewall_policy_rules"></a> [firewall\_policy\_rules](#output\_firewall\_policy\_rules) | Reglas de la política de red creadas por la raíz, leídas de los recursos (nombre → prioridad, acción, orígenes, etiquetas destino y protocolos/puertos). Además, el módulo crea la denegación por defecto de la entrada (prioridad 65000). |
| <a name="output_host_project_id"></a> [host\_project\_id](#output\_host\_project\_id) | ID del proyecto net-spoke (host de Shared VPC) del entorno. |
| <a name="output_host_project_number"></a> [host\_project\_number](#output\_host\_project\_number) | Número del proyecto net-spoke (para identificar sus agentes de servicio). |
| <a name="output_lb_backend_ports"></a> [lb\_backend\_ports](#output\_lb\_backend\_ports) | Puertos TCP que la política del spoke abre hacia los backends con lb\_backend (verificaciones de salud y proxies). La etapa 5 comprueba que los puertos de sus backends estén aquí. |
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
