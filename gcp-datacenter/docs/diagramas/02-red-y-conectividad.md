# Diagrama 2: red y conectividad

Hub y spokes en el proyecto único, con el plan de direccionamiento de §5 del contrato (X = 10
dev, 20 qa, 30 prod), la conectividad híbrida, el DNS, la salida a internet y el acceso a las APIs
de Google. Es diseño: nada se ha aplicado.

![Red: hub-and-spoke en un solo proyecto, dos regiones](img/02-red.png)

El PNG sale de [`fuente/`](fuente/LEEME.md). Los rangos son los de los
`terraform.tfvars.example` de `stages/2-networks` y `stages/2-networks/envs/<env>`. El diagrama
de texto usa `prefix = "bnt"`.

```mermaid
flowchart LR
  users(["Usuarios de Internet"])
  xlb["Balanceador HTTPS global + Cloud Armor<br/>uno por entorno, en 3-workloads (ADR 0005)"]
  users -- "HTTPS" --> xlb

  subgraph ONP["On-premises · 192.168.0.0/16 · ASN 65001"]
    onp["Sitio real (simulate_onprem = false)<br/>o VPC onprem-sim 192.168.0.0/24 con gateway HA VPN<br/>en us-central1 y us-east4 (ADR 0006)<br/>política de red propia: DNS desde 35.199.192.0/19 y SSH por IAP"]
  end

  subgraph HUB["2-networks (hub) · VPC hub 10.0.0.0/16"]
    hsub["hub 10.0.0.0/24 (us-central1) · hub_dr 10.0.1.0/24 (us-east4)<br/>Private Google Access · flow logs al 100 %"]
    hvpn["HA VPN primaria: 2 túneles con BGP<br/>Cloud Router de us-central1 · ASN 64514 · prioridad 100"]
    hvpndr["HA VPN de DR: 2 túneles con BGP<br/>Cloud Router de us-east4 · prioridad 200 (enable_vpn_dr)"]
    hdns["Cloud DNS: reenvío de onprem_dns_domain<br/>política de servidor con reenvío entrante"]
    hfw["Política de firewall de red bnt-common-net-fw-hub<br/>solo la denegación por defecto"]
    hroute["Sin Cloud NAT ni ruta a internet<br/>ruta al VIP restringido 199.36.153.4/30"]
  end

  onp <-- "BGP · GCP anuncia 10.0.0.0/16, 10.10.0.0/16,<br/>10.20.0.0/16, 10.30.0.0/16 y 35.199.192.0/19" --> hvpn
  onp <-- "BGP · mismos anuncios, menos preferidos" --> hvpndr

  subgraph DEV["2-networks/envs/dev · VPC 10.10.0.0/16"]
    dsub["app · proxy · run · pods · services (us-central1)<br/>*_dr reservadas (enable_dr = false)"]
    dnat["Cloud Router + Cloud NAT us-central1"]
    dpsa["PSA 10.10.176.0/20"]
  end

  subgraph QA["2-networks/envs/qa · VPC 10.20.0.0/16"]
    qsub["app · proxy · run · pods · services (us-central1)<br/>*_dr reservadas (enable_dr = false)"]
    qnat["Cloud Router + Cloud NAT us-central1"]
    qpsa["PSA 10.20.176.0/20"]
  end

  subgraph PROD["2-networks/envs/prod · VPC 10.30.0.0/16"]
    psub["app 10.30.0.0/20 · proxy 10.30.32.0/23 · run 10.30.36.0/24<br/>pods 10.30.64.0/18 · services 10.30.128.0/20<br/>app_dr · proxy_dr · run_dr · pods_dr · services_dr en us-east4<br/>gke_master 10.30.38.0/28 y gke_master_dr reservados"]
    pnat["Cloud Router + Cloud NAT<br/>us-central1 y us-east4"]
    ppsa["PSA 10.30.176.0/20<br/>Cloud SQL · Memorystore · Filestore"]
    pdns["Zona privada prod.empresa.internal. (spoke y hub)<br/>zona de peering de onprem_dns_domain hacia el hub<br/>googleapis.com, gcr.io, pkg.dev y run.app → VIP de google_apis_vip"]
    pfw["Política de firewall de red del spoke<br/>salud y proxies → lb_backend · IAP → iap_ssh<br/>plano de control de GKE · tráfico interno<br/>retrollamadas NFS de Filestore (opcional)<br/>denegación por defecto"]
    pilb["Balanceador interno por región (3-workloads)<br/>us-central1 y, con dr_active, us-east4<br/>acceso global"]
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

  gapis[("APIs de Google<br/>VIP restringido 199.36.153.4/30")]
  DEV -- "Private Google Access" --> gapis
  QA -- "Private Google Access" --> gapis
  PROD -- "Private Google Access" --> gapis
```

## Cómo se lee

- **Cinco VPC en un proyecto.** Hub, `dev`, `qa`, `prod` y, con `simulate_onprem = true`,
  `onprem-sim`. Sin Shared VPC: cada spoke y sus cargas viven en el mismo proyecto (ADR 0029 §6).
  Cada spoke se une al hub por peering en los dos sentidos
  (ADR [0003](../adr/0003-vpc-por-entorno-unida-al-hub-por-peering.md)); los spokes no se unen
  entre sí. Los spokes se aplican de uno en uno: GCP no admite dos operaciones de peering a la
  vez sobre la misma red (comentario de `stages/2-networks/envs/dev/main.tf`).
- **On-premises entra solo por el hub.** Dos HA VPN con dos túneles y BGP cada una, una por
  región. La de DR anuncia lo mismo con prioridad 200, para que on-premises prefiera la primaria
  (ADR [0022](../adr/0022-estado-y-conmutacion-sin-depender-de-la-region-primaria.md)). El hub
  anuncia su /16, el /16 de cada spoke y el rango del reenvío de Cloud DNS. Las rutas aprendidas
  llegan a los spokes por el peering (pendiente 6).
- **Firewall.** Sin organización no hay política jerárquica. Cada VPC tiene su propia política de
  firewall de red global con denegación por defecto (prioridad 65000, con registro):
  - hub: solo la denegación; no tiene cargas. Que la VPN y el reenvío DNS entrante no dependan de
    sus reglas es HYPOTHESIS (`VERIFICAR-EN-APPLY` en `stages/2-networks/firewall.tf`);
  - `onprem-sim`: DNS desde `35.199.192.0/19` (TCP y UDP 53) y SSH por IAP;
  - cada spoke: verificaciones de salud y proxies hacia la etiqueta segura `lb_backend`, SSH por
    IAP hacia `iap_ssh`, plano de control de GKE hacia los nodos, tráfico interno de las cargas
    y, con `enable_filestore_nfs_lock_callbacks`, las retrollamadas NFS desde el rango `psa`.
  Las etiquetas seguras tienen como padre el proyecto; que funcionen sin organización es
  HYPOTHESIS (ADR 0029 §6).
- **Salida a internet.** Por el Cloud NAT de cada spoke y región activa: uno en dev, uno en qa y
  dos en prod (prod tiene `enable_dr = true`). El hub no tiene salida
  (ADR [0004](../adr/0004-cloud-nat-en-cada-spoke.md)).
- **APIs de Google.** Por Private Google Access y el VIP de `google_apis_vip` (restringido en los
  tres ejemplos), con zonas privadas `googleapis.com`, `gcr.io`, `pkg.dev` y `run.app` en cada
  spoke (ADR [0026](../adr/0026-api-de-google-por-el-vip-restringido-en-todos-los-entornos.md)).
- **DNS.** El hub reenvía el dominio on-premises por la VPN y acepta consultas entrantes. Cada
  spoke tiene su zona privada `<env>.empresa.internal.`, adjunta también a la VPC hub para que
  on-premises la resuelva, y una zona de peering hacia el hub para el dominio on-premises.
- **Private Service Access por spoke.** Cloud SQL, Memorystore y Filestore toman IP del rango
  `psa` de su spoke. Esas IP y el plano de control de GKE están detrás de otro peering y no se
  alcanzan desde on-premises.
- **Balanceador interno de prod.** Uno por región, con acceso global: on-premises llega al de DR
  también por la VPN primaria (pendiente 44).

El diseño anterior, de varios proyectos y Shared VPC, está en la rama `archivo/multiproyecto`.
