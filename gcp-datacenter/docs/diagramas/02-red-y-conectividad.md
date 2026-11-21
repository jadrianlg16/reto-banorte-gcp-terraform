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
    onp["Sitio real con simulate_onprem = false<br/>o VPC bnt-common-net-onprem-sim 192.168.0.0/24<br/>con su Cloud Router y gateway HA VPN (ADR 0006)"]
  end

  subgraph HUB["bnt-common-net-hub · VPC hub · 10.0.0.0/16"]
    hsub["hub 10.0.0.0/24 (us-central1)<br/>hub_dr 10.0.1.0/24 (us-east4)<br/>Private Google Access · flow logs 0.5"]
    hcr["Cloud Router por región · ASN 64514"]
    hvpn["HA VPN: 2 túneles IKEv2 con BGP<br/>desde el router primario · Interconnect opcional"]
    hdns["Cloud DNS: zona de reenvío de onprem_dns_domain<br/>política de servidor con reenvío entrante"]
    hroute["Sin Cloud NAT ni ruta a internet<br/>ruta a 199.36.153.4/30"]
  end

  onp <-- "BGP · GCP anuncia 10.0.0.0/16, 10.10.0.0/16, 10.20.0.0/16, 10.30.0.0/16 y 35.199.192.0/19" --> hvpn

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
    pdns["Zona privada prod.empresa.internal. (spoke y hub)<br/>zona de peering de onprem_dns_domain hacia el hub<br/>zona googleapis.com → restricted.googleapis.com"]
    pfw["Política de firewall de red bnt-prod-net-fw<br/>etiquetas seguras lb_backend e iap_ssh<br/>una llave por etiqueta · denegación por defecto"]
  end

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

  hfw{{"Política de firewall jerárquica bnt-common-net-fw en la organización<br/>permite verificaciones de salud (35.191.0.0/16, 130.211.0.0/22) e IAP (35.235.240.0/20)<br/>delega con goto_next el tráfico interno y el de on-premises · deniega el resto"}}
  hfw -.- HUB
  hfw -.- PROD
```

## Cómo se lee

- Cada entorno tiene su propia VPC en su proyecto `net-spoke`, host de Shared VPC de sus
  proyectos de servicio, unida al hub por peering en los dos sentidos
  (ADR [0003](../adr/0003-vpc-por-entorno-unida-al-hub-por-peering.md)). dev y qa repiten la
  forma de prod con su X y sin las subredes de DR.
- On-premises entra solo por el hub: HA VPN con dos túneles y BGP, y el hub anuncia su /16, el
  /16 de cada spoke y el rango de reenvío de Cloud DNS. Las rutas aprendidas llegan a los spokes
  por el peering (pendiente 6). Las IP del rango `psa` y el plano de control de GKE están detrás
  de otro peering y no se alcanzan desde on-premises.
- La salida a internet es por el Cloud NAT de cada spoke y región: un NAT del hub no serviría a
  VPC unidas por peering (ADR [0004](../adr/0004-cloud-nat-en-cada-spoke.md)). Hay cuatro
  gateways con el plan actual.
- Cloud Storage y las demás APIs se alcanzan por Private Google Access y el VIP restringido
  (ruta y zona `googleapis.com` en cada spoke), no por Private Service Access.
- El balanceador externo y Cloud Armor viven en el proyecto de servicio de cada entorno; el
  diagrama dibuja solo el de prod.

## Cambios respecto a la versión de la fase 3

- El balanceador HTTPS global y Cloud Armor quedan en el proyecto de servicio de cada entorno
  (antes "ubicación por confirmar").
- Se confirma una VPC por entorno unida al hub por peering, cada una host de su Shared VPC.
- El hub no tiene reglas de firewall de VPC propias: la política jerárquica de la organización
  permite verificaciones de salud e IAP, delega el resto interno y de on-premises a la política
  de red de cada spoke y deniega lo demás.
- Cloud NAT se dibuja por spoke y región (uno en dev, uno en qa, dos en prod) y el hub queda sin
  salida a internet.
- On-premises puede ser el simulado `onprem-sim`; el hub anuncia también `35.199.192.0/19`.
- Las subredes incluyen `run`, las `*_dr` de prod y los rangos reservados del plano de control;
  el rango `psa` es para Cloud SQL, Memorystore y Filestore (antes solo Cloud SQL).
- Se agregan las zonas DNS del spoke: la privada del entorno, adjunta también a la VPC hub; la de
  peering hacia el hub para el dominio on-premises; y `googleapis.com` hacia el VIP restringido.
- La política de red de cada spoke usa dos etiquetas seguras con una llave propia cada una
  (`lb_backend`, `iap_ssh`).
