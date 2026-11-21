# Etapa `3-networks` (hub)

Raíz del hub de red (contrato §7.3, ADR 0014). Los spokes de cada entorno viven en
`envs/{dev,qa,prod}` y tienen su propio estado (ver [envs/dev/README.md](envs/dev/README.md)).

## Qué crea

En el proyecto `net-hub` que crea `1-org` (`common_project_ids["net_hub"]`):

- APIs `compute.googleapis.com` y `dns.googleapis.com` (sin apagarlas al destruir).
- VPC hub `<prefix>-common-net-hub` (módulo `network-hub`): subredes `hub` (región primaria) y
  `hub_dr` (región de DR) con Private Google Access y flow logs al 50 %, un Cloud Router por
  región con `hub_asn`, sin ruta por defecto a internet y con la ruta al VIP restringido
  `199.36.153.4/30`.
- Dos HA VPN, cada una con dos túneles IKEv2 y BGP (módulo `hybrid-connectivity`, SLA
  99.99 %): la primaria en el router del hub en `primary_region` (`vpn_bgp_ranges`, prioridad
  anunciada 100) y, con `enable_vpn_dr = true` (por defecto), la de DR en el router del hub en
  `dr_region` (`vpn_dr_bgp_ranges`, 169.254.0.8/30 y 169.254.0.12/30 en el plan, prioridad
  `vpn_dr_route_priority`, 200 por defecto y siempre mayor que 100). On-premises recibe los
  mismos anuncios por las dos y prefiere la primaria (MED menor); si se pierde la región
  primaria, la de DR sigue dando camino a on-premises. Anuncios personalizados:
  `hub_supernet`, cada `/16` de `spoke_supernets` y `35.199.192.0/19` (origen del reenvío de
  Cloud DNS).
- Punta on-premises según `simulate_onprem` (ADR 0006):
  - `true`: VPC `<prefix>-common-net-onprem-sim` (`onprem_sim_cidr`, 192.168.0.0/24) con un
    Cloud Router (`onprem_asn`, que debe ser privado) y un gateway HA VPN en la región primaria
    y, con `enable_vpn_dr`, otro router y otro gateway en la región de DR (sin subred, solo
    para la VPN de DR); cada punta de `hybrid-connectivity` apunta al gateway de la otra. Una
    política de firewall de red `<prefix>-common-net-fw-onprem-sim` en esa VPC permite solo
    DNS (TCP/UDP 53) desde 35.199.192.0/19 y SSH por IAP, para poder probar el reenvío DNS con
    una VM DNS creada a mano en `onprem_dns_servers`. El secreto compartido lo genera
    `random_password` y **solo existe en el estado de Terraform**, cifrado con la llave CMEK
    del bucket de estado (ADR 0006 y 0008); no sale en ninguna salida.
  - `false`: gateway externo con `onprem_vpn_gateway_ips` (1 o 2 IP), uno por VPN (el de DR se
    llama `<prefix>-common-net-vpn-onprem-dr-peer` y usa las mismas IP). `onprem_asn` puede
    ser público de 2 o 4 bytes. El secreto se lee de Secret Manager (`onprem_vpn_secret_id`)
    con un origen de datos, en la versión numérica `onprem_vpn_secret_version` (`latest` no
    se admite); el valor también queda en el estado cifrado, nunca en variables.
  - Las validaciones exigen las entradas de cada modo y rechazan las del otro.
- Cloud Interconnect (VLAN attachments) solo con `enable_interconnect = true`.
- Política de firewall jerárquica `<prefix>-common-net-fw` asociada a la organización (módulo
  `firewall`) **sin reglas `allow`**: delega con `goto_next` a la política de red de cada spoke
  las verificaciones de salud y proxies de Google (35.191.0.0/16, 130.211.0.0/22, TCP), el IAP
  (35.235.240.0/20, TCP 22 y 3389), el tráfico interno (`hub_supernet` y `spoke_supernets`) y el
  de `onprem_cidrs`; con `simulate_onprem = true` delega además 35.199.192.0/19 (TCP/UDP 53)
  solo hacia la VPC `onprem-sim` (`target_resources`); deniega todo lo demás (regla del
  módulo, prioridad 65000, con registro).
- DNS (módulo `dns`): zona de reenvío de `onprem_dns_domain` hacia `onprem_dns_servers` por la
  VPN (`forwarding_path = private`) y política de servidor con reenvío entrante y registro de
  consultas sobre la VPC hub.

Validaciones del plan de direccionamiento (contrato §5): `hub_supernet`, `hub_cidrs` y cada
`spoke_supernets` no se traslapan con `onprem_cidrs` ni entre sí; `hub_cidrs` cabe en
`hub_supernet`; `onprem_sim_cidr` y `onprem_dns_servers` caben en `onprem_cidrs`.

### Notas de diseño

- **Una regla `allow` de la organización es final.** Por eso la política jerárquica no
  permite nada: las verificaciones de salud y el IAP llegan a la política de red del spoke,
  que solo los deja pasar hacia las VM con la etiqueta segura `lb_backend` (verificaciones de
  salud, puertos `lb_backend_ports`) o `iap_ssh` (TCP 22). Una VM sin etiqueta no los recibe;
  el acceso por IAP además exige `iap.tunnelInstances.accessViaIAP`. La VPC hub no tiene
  política de red: lo delegado se resuelve con sus reglas de VPC y la denegación implícita.
- **On-premises simulado sin servidor DNS.** La VPC `onprem-sim` no tiene un servidor DNS en
  `onprem_dns_servers`: la zona de reenvío queda creada pero las consultas a
  `onprem_dns_domain` no reciben respuesta hasta que se cree a mano una VM DNS con esa IP en
  `onprem-sim`. El firewall ya admite esa prueba (delegación solo hacia `onprem-sim` y su
  política de red).
- **Rotación del secreto de la VPN real.** En el proveedor, `shared_secret` fuerza el
  reemplazo del túnel, y los túneles tienen nombre fijo (se destruyen antes de crearse). Por
  eso la versión es numérica y una rotación entra por PR, y se hace de a un túnel:
  `onprem_vpn_secret_version_overrides = { "primary-if0" = "<nueva>" }`, aplicar, cambiar la
  llave en el equipo on-premises para ese túnel, comprobar que su sesión BGP vuelve, y repetir
  con `primary-if1`, `dr-if0` y `dr-if1`; al final se sube `onprem_vpn_secret_version` y se
  vacía el mapa. Mientras se reemplaza un túnel, los otros mantienen la conectividad.
- **Enrutamiento con dos VPN.** La VPC hub usa enrutamiento global: una VM aprende las rutas
  de on-premises por los dos routers, con el costo entre regiones sumado a las del router de
  la otra región, así que cada región sale por su VPN mientras las dos estén arriba.
  On-premises entra por la primaria (MED menor). El regreso de un flujo hacia la región de DR
  puede ser asimétrico (entra por la VPN primaria y vuelve por la de DR); un firewall con
  estado en on-premises debe admitirlo (`VERIFICAR-EN-APPLY`).
- Lectura de estado: solo `1-org` (§6.1 permite además `0-bootstrap`, que esta raíz no
  necesita).

## Cómo se ejecuta

```sh
cd stages/3-networks
cp terraform.tfvars.example terraform.tfvars   # ajustar valores
terraform init -backend-config="bucket=<state_bucket>"
terraform plan -out=tfplan
terraform apply tfplan
```

Orden: después de `1-org` y antes de cualquier spoke. Las salidas `vpn_gateway_ip_addresses`,
`vpn_dr_gateway_ip_addresses` y `dns_inbound_forwarder_ips` sirven para configurar el equipo y
el DNS de on-premises (cuatro túneles: dos por VPN).

## Roles de la cuenta de servicio `<prefix>-tf-3-networks`

Para el hub:

| Alcance | Rol | Lo asigna | Para qué |
|---|---|---|---|
| Organización | `roles/compute.orgFirewallPolicyAdmin` | 0-bootstrap | Crear la política jerárquica y sus reglas |
| Organización | `roles/compute.orgSecurityResourceAdmin` | 0-bootstrap | Asociar la política a la organización |
| Organización | `roles/resourcemanager.organizationViewer` | 0-bootstrap | Leer la organización |
| Proyecto semilla | `roles/serviceusage.serviceUsageConsumer` | 0-bootstrap | Proyecto de cuota |
| Bucket de estado | §6.2: escritura de `3-networks/hub`, lectura de `1-org` | 0-bootstrap | Estado |
| Proyecto `net-hub` | `roles/compute.networkAdmin` | 1-org | VPC, subredes, routers, rutas, HA VPN, Interconnect |
| Proyecto `net-hub` | `roles/compute.securityAdmin` | 1-org | Política de firewall de red de `onprem-sim` y sus reglas (solo con `simulate_onprem = true`) |
| Proyecto `net-hub` | `roles/dns.admin` | 1-org | Zonas y política de servidor DNS |
| Proyecto `net-hub` | `roles/serviceusage.serviceUsageAdmin` | 1-org | Habilitar las APIs |
| Secreto `onprem_vpn_secret_id` | `roles/secretmanager.secretAccessor` | **nadie** (paso manual) | Solo con `simulate_onprem = false`: el secreto lo crea el equipo de red fuera de Terraform y le da este permiso a `<prefix>-tf-3-networks` |
| Bucket de estado | §6.2: escritura en `3-networks/hub`, lectura de `1-org` | Estado |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | ~> 6.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.6 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_dns"></a> [dns](#module\_dns) | ../../modules/dns | n/a |
| <a name="module_firewall_onprem_sim"></a> [firewall\_onprem\_sim](#module\_firewall\_onprem\_sim) | ../../modules/firewall | n/a |
| <a name="module_firewall_org"></a> [firewall\_org](#module\_firewall\_org) | ../../modules/firewall | n/a |
| <a name="module_hub"></a> [hub](#module\_hub) | ../../modules/network-hub | n/a |
| <a name="module_onprem_sim"></a> [onprem\_sim](#module\_onprem\_sim) | ../../modules/network-hub | n/a |
| <a name="module_vpn_hub"></a> [vpn\_hub](#module\_vpn\_hub) | ../../modules/hybrid-connectivity | n/a |
| <a name="module_vpn_hub_dr"></a> [vpn\_hub\_dr](#module\_vpn\_hub\_dr) | ../../modules/hybrid-connectivity | n/a |
| <a name="module_vpn_onprem_sim"></a> [vpn\_onprem\_sim](#module\_vpn\_onprem\_sim) | ../../modules/hybrid-connectivity | n/a |
| <a name="module_vpn_onprem_sim_dr"></a> [vpn\_onprem\_sim\_dr](#module\_vpn\_onprem\_sim\_dr) | ../../modules/hybrid-connectivity | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [google_project_service.hub](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [random_password.vpn_shared_secret](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [google_secret_manager_secret_version.vpn_shared_secret](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/secret_manager_secret_version) | data source |
| [terraform_remote_state.org](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_dr_region"></a> [dr\_region](#input\_dr\_region) | Región de recuperación (subred hub\_dr y su Cloud Router). | `string` | n/a | yes |
| <a name="input_hub_asn"></a> [hub\_asn](#input\_hub\_asn) | ASN privado de los Cloud Router del hub (plan: 64514). | `number` | n/a | yes |
| <a name="input_hub_cidrs"></a> [hub\_cidrs](#input\_hub\_cidrs) | Subredes del hub: llave hub (región primaria) y hub\_dr (región de DR) → CIDR (plan: 10.0.0.0/24 y 10.0.1.0/24). | `map(string)` | n/a | yes |
| <a name="input_hub_supernet"></a> [hub\_supernet](#input\_hub\_supernet) | Bloque /16 del hub (plan de direccionamiento: 10.0.0.0/16). Se anuncia a on-premises por BGP y debe contener hub\_cidrs. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Etiquetas comunes de la raíz (app, owner, cost\_center y las que se agreguen). env y managed\_by las fija la raíz. | `map(string)` | n/a | yes |
| <a name="input_onprem_asn"></a> [onprem\_asn](#input\_onprem\_asn) | ASN del router on-premises (plan: 65001). Con on-premises real puede ser público (de 2 o 4 bytes) o privado. En modo simulado es el ASN del Cloud Router de la VPC onprem-sim y debe ser privado. | `number` | n/a | yes |
| <a name="input_onprem_cidrs"></a> [onprem\_cidrs](#input\_onprem\_cidrs) | Rangos de on-premises, real o simulado (plan: 192.168.0.0/16). Las políticas de firewall delegan este tráfico en los spokes y ningún rango de GCP puede traslaparse con ellos. | `list(string)` | n/a | yes |
| <a name="input_onprem_dns_domain"></a> [onprem\_dns\_domain](#input\_onprem\_dns\_domain) | Dominio DNS de on-premises que el hub reenvía a onprem\_dns\_servers (por ejemplo corp.example.com.). Termina en punto. | `string` | n/a | yes |
| <a name="input_onprem_dns_servers"></a> [onprem\_dns\_servers](#input\_onprem\_dns\_servers) | IP de los servidores DNS de on-premises (destino del reenvío por la VPN). Deben estar dentro de onprem\_cidrs. | `list(string)` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | ID numérico de la organización de GCP (la política de firewall jerárquica se crea y se asocia aquí). | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefijo de la empresa en los nombres (por ejemplo, bnt). | `string` | n/a | yes |
| <a name="input_primary_region"></a> [primary\_region](#input\_primary\_region) | Región primaria (subred hub, HA VPN y su Cloud Router). | `string` | n/a | yes |
| <a name="input_spoke_supernets"></a> [spoke\_supernets](#input\_spoke\_supernets) | Mapa entorno (dev, qa, prod) → /16 de su spoke (plan: 10.10.0.0/16, 10.20.0.0/16, 10.30.0.0/16). El hub los anuncia a on-premises por BGP. | `map(string)` | n/a | yes |
| <a name="input_state_bucket"></a> [state\_bucket](#input\_state\_bucket) | Bucket de estado de Terraform (salida state\_bucket de 0-bootstrap) del que se leen las etapas anteriores. | `string` | n/a | yes |
| <a name="input_vpn_bgp_ranges"></a> [vpn\_bgp\_ranges](#input\_vpn\_bgp\_ranges) | Dos /30 de 169.254.0.0/16 para las sesiones BGP de los túneles de la interfaz 0 y 1 (plan: 169.254.0.0/30 y 169.254.0.4/30). El Cloud Router del hub toma la primera IP de cada /30. | `list(string)` | n/a | yes |
| <a name="input_enable_interconnect"></a> [enable\_interconnect](#input\_enable\_interconnect) | Crea los VLAN attachments de Cloud Interconnect de interconnect\_attachments en el router primario del hub. Apagado por defecto. | `bool` | `false` | no |
| <a name="input_enable_vpn_dr"></a> [enable\_vpn\_dr](#input\_enable\_vpn\_dr) | Crea la segunda HA VPN (dos túneles y BGP) en el Cloud Router del hub en dr\_region, y con simulate\_onprem = true su punta en onprem-sim. Sin ella, perder la región primaria deja a la región de DR sin camino a on-premises. | `bool` | `true` | no |
| <a name="input_interconnect_attachments"></a> [interconnect\_attachments](#input\_interconnect\_attachments) | VLAN attachments de Cloud Interconnect (solo con enable\_interconnect = true). Mismo formato que la variable del módulo hybrid-connectivity: type DEDICATED (interconnect, bandwidth, vlan\_tag, candidate\_subnets) o PARTNER (edge\_availability\_domain). | <pre>map(object({<br/>    type                     = optional(string, "DEDICATED")<br/>    interconnect             = optional(string)<br/>    edge_availability_domain = optional(string)<br/>    bandwidth                = optional(string)<br/>    vlan_tag                 = optional(number)<br/>    candidate_subnets        = optional(list(string), [])<br/>    mtu                      = optional(number, 1440)<br/>  }))</pre> | `{}` | no |
| <a name="input_onprem_sim_cidr"></a> [onprem\_sim\_cidr](#input\_onprem\_sim\_cidr) | Subred de la VPC simulada onprem-sim (plan: 192.168.0.0/24). Solo se usa con simulate\_onprem = true y debe caber en onprem\_cidrs. | `string` | `"192.168.0.0/24"` | no |
| <a name="input_onprem_vpn_gateway_ips"></a> [onprem\_vpn\_gateway\_ips](#input\_onprem\_vpn\_gateway\_ips) | IP públicas del gateway VPN on-premises (1 o 2). Obligatorias con simulate\_onprem = false; deben ir vacías con simulate\_onprem = true. | `list(string)` | `[]` | no |
| <a name="input_onprem_vpn_secret_id"></a> [onprem\_vpn\_secret\_id](#input\_onprem\_vpn\_secret\_id) | Secreto de Secret Manager con la llave compartida IKE de la VPN real, como projects/<proyecto>/secrets/<nombre>. Obligatorio con simulate\_onprem = false y null con simulate\_onprem = true. El valor nunca pasa por variables. | `string` | `null` | no |
| <a name="input_onprem_vpn_secret_version"></a> [onprem\_vpn\_secret\_version](#input\_onprem\_vpn\_secret\_version) | Versión numérica del secreto onprem\_vpn\_secret\_id que usan los túneles (obligatoria con simulate\_onprem = false). No se admite latest: cambiar el secreto reemplaza los túneles, y una versión nueva en Secret Manager no debe cambiar la VPN sin un PR. Para rotar un túnel a la vez, ver onprem\_vpn\_secret\_version\_overrides. | `string` | `null` | no |
| <a name="input_onprem_vpn_secret_version_overrides"></a> [onprem\_vpn\_secret\_version\_overrides](#input\_onprem\_vpn\_secret\_version\_overrides) | Versión del secreto propia de algunos túneles de la VPN real, para rotarlos de uno en uno: llave primary-if0, primary-if1, dr-if0 o dr-if1 → versión numérica. Los túneles sin entrada usan onprem\_vpn\_secret\_version. Solo con simulate\_onprem = false. | `map(string)` | `{}` | no |
| <a name="input_region_short_names"></a> [region\_short\_names](#input\_region\_short\_names) | Mapa región → código corto que se agrega a los nombres de recursos regionales (contrato §4.2). | `map(string)` | <pre>{<br/>  "northamerica-south1": "nas1",<br/>  "us-central1": "usc1",<br/>  "us-east4": "use4"<br/>}</pre> | no |
| <a name="input_simulate_onprem"></a> [simulate\_onprem](#input\_simulate\_onprem) | true: crea la VPC onprem-sim y una HA VPN entre VPC como punta on-premises (ADR 0006), con secreto generado. false: VPN hacia el gateway real de onprem\_vpn\_gateway\_ips con el secreto de onprem\_vpn\_secret\_id. | `bool` | `true` | no |
| <a name="input_vpn_dr_bgp_ranges"></a> [vpn\_dr\_bgp\_ranges](#input\_vpn\_dr\_bgp\_ranges) | Dos /30 de 169.254.0.0/16 para las sesiones BGP de la VPN de DR, interfaz 0 y 1 (plan: 169.254.0.8/30 y 169.254.0.12/30). Distintos entre sí y de vpn\_bgp\_ranges. | `list(string)` | <pre>[<br/>  "169.254.0.8/30",<br/>  "169.254.0.12/30"<br/>]</pre> | no |
| <a name="input_vpn_dr_route_priority"></a> [vpn\_dr\_route\_priority](#input\_vpn\_dr\_route\_priority) | advertised\_route\_priority (MED) de las sesiones BGP de la VPN de DR. Mayor que el de la primaria (100) para que on-premises prefiera la primaria mientras exista. | `number` | `200` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bgp_advertised_ranges"></a> [bgp\_advertised\_ranges](#output\_bgp\_advertised\_ranges) | Rangos que el hub anuncia a on-premises por BGP, leídos de la sesión if0 de la VPN primaria (ordenados). Todas las sesiones de las dos VPN anuncian los mismos. |
| <a name="output_dns_inbound_forwarder_ips"></a> [dns\_inbound\_forwarder\_ips](#output\_dns\_inbound\_forwarder\_ips) | IP de reenvío entrante de Cloud DNS en el hub, a las que on-premises reenvía las zonas de GCP. Se conocen hasta el apply. |
| <a name="output_firewall_policy_id"></a> [firewall\_policy\_id](#output\_firewall\_policy\_id) | ID de la política de firewall jerárquica de la organización (locations/global/firewallPolicies/<id>). |
| <a name="output_firewall_policy_rules"></a> [firewall\_policy\_rules](#output\_firewall\_policy\_rules) | Reglas de la política jerárquica creadas por la raíz, leídas de los recursos (nombre → prioridad, acción, orígenes, VPC destino y protocolos/puertos). Además, el módulo crea la denegación por defecto de la entrada (prioridad 65000). |
| <a name="output_hub_network_name"></a> [hub\_network\_name](#output\_hub\_network\_name) | Nombre de la VPC hub. |
| <a name="output_hub_network_self_link"></a> [hub\_network\_self\_link](#output\_hub\_network\_self\_link) | self\_link de la VPC hub, para el peering y las zonas de peering DNS de los spokes. |
| <a name="output_hub_project_id"></a> [hub\_project\_id](#output\_hub\_project\_id) | ID del proyecto net-hub. |
| <a name="output_hub_routers"></a> [hub\_routers](#output\_hub\_routers) | Mapa región → nombre del Cloud Router del hub. |
| <a name="output_onprem_sim_firewall_policy_id"></a> [onprem\_sim\_firewall\_policy\_id](#output\_onprem\_sim\_firewall\_policy\_id) | ID de la política de firewall de red de la VPC onprem-sim (DNS desde 35.199.192.0/19 e IAP), o null con simulate\_onprem = false. |
| <a name="output_onprem_sim_network_name"></a> [onprem\_sim\_network\_name](#output\_onprem\_sim\_network\_name) | Nombre de la VPC onprem-sim, o null con simulate\_onprem = false. |
| <a name="output_spoke_supernets"></a> [spoke\_supernets](#output\_spoke\_supernets) | Mapa entorno → /16 del spoke que el hub anuncia a on-premises. Cada spoke comprueba que su spoke\_supernet coincida. |
| <a name="output_vpn_dr_gateway_ip_addresses"></a> [vpn\_dr\_gateway\_ip\_addresses](#output\_vpn\_dr\_gateway\_ip\_addresses) | IP externas del gateway HA VPN de DR del hub, para configurar el equipo on-premises (vacía con enable\_vpn\_dr = false). Se conocen hasta el apply. |
| <a name="output_vpn_dr_tunnel_names"></a> [vpn\_dr\_tunnel\_names](#output\_vpn\_dr\_tunnel\_names) | Mapa interfaz → nombre del túnel HA VPN de DR del hub hacia on-premises (vacío con enable\_vpn\_dr = false). |
| <a name="output_vpn_gateway_ip_addresses"></a> [vpn\_gateway\_ip\_addresses](#output\_vpn\_gateway\_ip\_addresses) | IP externas del gateway HA VPN del hub, para configurar el equipo on-premises. Se conocen hasta el apply. |
| <a name="output_vpn_tunnel_names"></a> [vpn\_tunnel\_names](#output\_vpn\_tunnel\_names) | Mapa interfaz → nombre del túnel HA VPN del hub hacia on-premises. |
<!-- END_TF_DOCS -->
