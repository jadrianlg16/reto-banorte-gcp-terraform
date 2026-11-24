# Diagrama 2: red y conectividad

Hub y spokes con el plan de direccionamiento de §5 del contrato (X = 10 dev, 20 qa, 30 prod),
conectividad híbrida, DNS, salida a internet y acceso a las APIs de Google. Es diseño: nada se
ha aplicado.

```mermaid
flowchart LR
  users(["Usuarios de Internet"])
  xlb["Balanceador HTTPS global + Cloud Armor<br/>uno por entorno, en bnt-{env}-app (ADR 0005)"]
  users -- "HTTPS" --> xlb

  subgraph ONP["On-premises · 192.168.0.0/16 · ASN 65001"]
    onp["Sitio real con simulate_onprem = false<br/>o VPC bnt-common-net-onprem-sim 192.168.0.0/24<br/>con Cloud Router y gateway HA VPN en us-central1 y us-east4 (ADR 0006)<br/>política de red propia: DNS desde 35.199.192.0/19 y SSH por IAP<br/>política DNS solo con registro de consultas"]
  end

  subgraph HUB["bnt-common-net-hub · VPC hub · 10.0.0.0/16"]
    hsub["hub 10.0.0.0/24 (us-central1)<br/>hub_dr 10.0.1.0/24 (us-east4)<br/>Private Google Access · flow logs al 100 %"]
    hcr["Cloud Router por región · ASN 64514"]
    hvpn["HA VPN primaria: 2 túneles IKEv2 con BGP<br/>router de us-central1 · prioridad 100 · Interconnect opcional"]
    hvpndr["HA VPN de DR: 2 túneles IKEv2 con BGP<br/>router de us-east4 · prioridad 200 (enable_vpn_dr, ADR 0022)"]
    hdns["Cloud DNS: zona de reenvío de onprem_dns_domain<br/>política de servidor con reenvío entrante"]
    hroute["Sin Cloud NAT ni ruta a internet<br/>ruta a 199.36.153.4/30"]
  end

  onp <-- "BGP · GCP anuncia 10.0.0.0/16, 10.10.0.0/16, 10.20.0.0/16, 10.30.0.0/16 y 35.199.192.0/19" --> hvpn
  onp <-- "BGP · mismos anuncios, menos preferidos" --> hvpndr

  subgraph DEV["bnt-dev-net-spoke · VPC 10.10.0.0/16"]
    dsub["app · run · proxy (us-central1)<br/>pods y services en app<br/>*_dr reservadas (enable_dr = false)"]
    dnat["Cloud Router + Cloud NAT us-central1"]
    dpsa["PSA 10.10.176.0/20"]
  end

  subgraph QA["bnt-qa-net-spoke · VPC 10.20.0.0/16"]
    qsub["app · run · proxy (us-central1)<br/>pods y services en app<br/>*_dr reservadas (enable_dr = false)"]
    qnat["Cloud Router + Cloud NAT us-central1"]
    qpsa["PSA 10.20.176.0/20"]
  end

  subgraph PROD["bnt-prod-net-spoke · VPC 10.30.0.0/16"]
    psub["app 10.30.0.0/20 · proxy 10.30.32.0/23 · run 10.30.36.0/24<br/>pods 10.30.64.0/18 · services 10.30.128.0/20<br/>app_dr · proxy_dr · run_dr · pods_dr · services_dr en us-east4<br/>gke_master 10.30.38.0/28 y gke_master_dr reservados"]
    pnat["Cloud Router + Cloud NAT<br/>us-central1 y us-east4"]
    ppsa["PSA 10.30.176.0/20<br/>Cloud SQL · Memorystore · Filestore"]
    pdns["Zona privada prod.empresa.internal. (spoke y hub)<br/>zona de peering de onprem_dns_domain hacia el hub<br/>zonas googleapis.com, gcr.io, pkg.dev y run.app → VIP de google_apis_vip<br/>(restricted en los tres entornos, ADR 0026)"]
    pfw["Política de firewall de red bnt-prod-net-fw<br/>permite verificaciones de salud solo hacia lb_backend<br/>y SSH por IAP solo hacia iap_ssh<br/>retrollamadas NFS de Filestore desde psa (opcional)<br/>una llave por etiqueta · denegación por defecto"]
    pilb["Balanceador interno por región (bnt-prod-app)<br/>us-central1 y, con dr_active, us-east4<br/>acceso global: on-premises llega por cualquiera de las dos VPN"]
  end

  hvpn -. "acceso global" .-> pilb
  hvpndr -. "acceso global" .-> pilb

  HUB <-- "peering: el hub exporta rutas, el spoke las importa" --> DEV
  HUB <-- "peering" --> QA
  HUB <-- "peering" --> PROD
  nopeer["Sin peering entre spokes:<br/>el peering no es transitivo"]
  DEV ~~~ nopeer ~~~ QA

  xlb -- "backends: MIG, NEG de GKE, NEG sin servidor" --> PROD

  egress(["Internet (salida)"])
  dnat --> egress
  qnat --> egress
  pnat --> egress

  gapis[("APIs de Google: Cloud Storage y demás<br/>VIP restringido 199.36.153.4/30")]
  PROD -- "Private Google Access" --> gapis
  DEV -- "Private Google Access" --> gapis
  QA -- "Private Google Access" --> gapis

  hfw{{"Política de firewall jerárquica bnt-common-net-fw en la organización<br/>sin reglas allow: delega con goto_next las verificaciones de salud (35.191.0.0/16, 130.211.0.0/22),<br/>el IAP (35.235.240.0/20), el tráfico interno y el de on-premises · deniega el resto<br/>con simulate_onprem: delega 35.199.192.0/19 (DNS) solo a onprem-sim"}}
  hfw -.- HUB
  hfw -.- PROD
  hfw -.- ONP
```

## Cómo se lee

- Cada entorno tiene su propia VPC en su proyecto `net-spoke`, host de Shared VPC de sus
  proyectos de servicio, unida al hub por peering en los dos sentidos
  (ADR [0003](../adr/0003-vpc-por-entorno-unida-al-hub-por-peering.md)). dev y qa repiten la
  forma de prod con su X y sin las subredes de DR.
- On-premises entra solo por el hub: dos HA VPN con dos túneles y BGP cada una, una por
  región; la de DR anuncia lo mismo con prioridad 200 para que on-premises prefiera la primaria
  mientras exista (ADR [0022](../adr/0022-estado-y-conmutacion-sin-depender-de-la-region-primaria.md)).
  El hub anuncia su /16, el /16 de cada spoke y el rango de reenvío de Cloud DNS. Las rutas
  aprendidas llegan a los spokes por el peering (pendiente 6). Las IP del rango `psa` y el plano
  de control de GKE están detrás de otro peering y no se alcanzan desde on-premises.
- El balanceador interno es uno por región, con acceso global: on-premises llega al de DR
  también por la VPN primaria (pendiente 44).
- La salida a internet es por el Cloud NAT de cada spoke y región: un NAT del hub no serviría a
  VPC unidas por peering (ADR [0004](../adr/0004-cloud-nat-en-cada-spoke.md)). Hay cuatro
  gateways con el plan actual.
- Cloud Storage y las demás APIs se alcanzan por Private Google Access y el VIP de
  `google_apis_vip` (restringido por defecto; zonas `googleapis.com`, `gcr.io`, `pkg.dev` y
  `run.app` y ruta en cada spoke), no por Private Service Access
  (ADR [0026](../adr/0026-api-de-google-por-el-vip-restringido-en-todos-los-entornos.md)).
- El balanceador externo y Cloud Armor viven en el proyecto de servicio de cada entorno; el
  diagrama dibuja solo el de prod.

## Cambios respecto a la versión de la fase 3

- El balanceador HTTPS global y Cloud Armor quedan en el proyecto de servicio de cada entorno
  (antes "ubicación por confirmar").
- Se confirma una VPC por entorno unida al hub por peering, cada una host de su Shared VPC.
- El hub no tiene reglas de firewall de VPC propias. La política jerárquica de la organización
  no tiene ninguna regla allow (una allow ahí es final y dejaría sin efecto las etiquetas del
  spoke): delega con `goto_next` las verificaciones de salud (`delegate-health-checks`), el IAP
  (`delegate-iap`), el tráfico interno y el de on-premises a la política de red de cada spoke, y
  deniega lo demás. El spoke los permite por etiqueta segura: `allow-lb-health-checks` solo
  hacia `lb_backend` y `allow-iap-ssh` (TCP 22) solo hacia `iap_ssh`.
- Cloud NAT se dibuja por spoke y región (uno en dev, uno en qa, dos en prod) y el hub queda sin
  salida a internet.
- On-premises puede ser el simulado `onprem-sim`; el hub anuncia también `35.199.192.0/19`.
- Las subredes incluyen `run`, las `*_dr` de prod y los rangos reservados del plano de control;
  el rango `psa` es para Cloud SQL, Memorystore y Filestore (antes solo Cloud SQL).
- Se agregan las zonas DNS del spoke: la privada del entorno, adjunta también a la VPC hub; la de
  peering hacia el hub para el dominio on-premises; y `googleapis.com` hacia el VIP restringido.
- La política de red de cada spoke usa dos etiquetas seguras con una llave propia cada una
  (`lb_backend`, `iap_ssh`).
- Ronda de correcciones del 21 nov 2026: segunda HA VPN en la región de DR (y router de DR en
  `onprem-sim`); política de red de `onprem-sim` y delegación del rango de DNS solo hacia ella,
  para probar el reenvío en modo simulado; zonas `gcr.io`, `pkg.dev` y `run.app` hacia el VIP;
  balanceador interno por región con acceso global; regla opcional de retrollamadas NFS de
  Filestore.
