"""Genera los cinco diagramas de arquitectura (proyecto único, ADR 0029) y los íconos en PNG.

Uso:
    python generar.py --iconos RUTA          # todo: HTML, PNG 1920x1080, PNG @2x, íconos y revisión
    python generar.py --iconos RUTA --img    # además copia los PNG 1x a ../img (los que usan los .md)
    python generar.py --solo 2 3             # solo esos diagramas
    python generar.py --sin-png              # solo HTML y revisión automática

La carpeta de íconos (los zip oficiales de https://cloud.google.com/icons, descomprimidos) llega
por --iconos o por la variable GCP_ICONS_DIR; no hay valor por defecto: los íconos no se suben al
repositorio. La salida (HTML con los íconos incrustados, PNG e íconos PNG) va por defecto a la
carpeta temporal del sistema (subcarpeta diagramas-gcp), fuera del repositorio; otra con --salida
o DIAGRAMAS_SALIDA.

Requisitos: Python 3.9+ (solo biblioteca estándar) y Chrome, Chromium o Edge (CHROME_PATH si no
se encuentra solo).
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True  # sin __pycache__ dentro del repositorio
from motor import (GRIS, PLANTILLA_ICONO, Chrome, Diagrama, Iconos, fila, leer_qa)  # noqa: E402

AQUI = Path(__file__).resolve().parent


# =============================================================================================
# 1. Vista general
# =============================================================================================
def d1() -> Diagrama:
    D = Diagrama("01-vista-general", "Vista general: un proyecto, tres entornos y un pipeline",
                 "Todo vive en un solo proyecto de Google Cloud. GitHub despliega con Terraform por etapas; "
                 "cada entorno tiene su VPC, sus cuentas del pipeline y su prefijo de nombres.", 1)

    # GitHub (fuera de Google Cloud, arriba)
    D.caja("gh", 330, 98, 980, 114, "externo", "GitHub", sub="repositorio privado")
    D.tarjeta("equipo", 346, 134, 236, 66, "gen-usuarios", "Equipo", "solo lectura en GCP", dentro="gh")
    D.tarjeta("repo", 702, 134, 236, 66, "gen-repositorio", "Repositorio", "Terraform en 4 etapas", dentro="gh")
    D.tarjeta("actions", 1058, 134, 236, 66, "gen-flujo", "GitHub Actions", "pipeline de despliegue", dentro="gh")
    D.flecha([D.p("equipo", "r"), D.p("repo", "l")], "pull request")
    D.flecha([D.p("repo", "r"), D.p("actions", "l")], "merge a main")

    # Orden del despliegue
    D.caja("orden", 1334, 98, 546, 114, "externo", "Orden del despliegue", sub="apply.yml, una raíz a la vez")
    chips = [("c1", "1-base", 70), ("c2", "hub", 52), ("c3", "dev", 52), ("c4", "prueba de humo", 140),
             ("c5", "qa", 44), ("c6", "prod", 58)]
    x = 1350
    prev = None
    for cid, txt, w in chips:
        D.chip(cid, x, 136, w, 32, txt, destacado=(cid == "c4"), dentro="orden")
        if prev:
            D.flecha([D.p(prev, "r"), D.p(cid, "l")])
        prev = cid
        x += w + 20
    D.texto(1352, 180, "0-bootstrap lo aplica una persona, a mano, una sola vez.", tam=14, color="#5F6368",
            id_="nota-orden")

    # Google Cloud y proyecto
    D.caja("gc", 330, 228, 1550, 808, "gcloud")
    D.caja("proj", 352, 266, 1506, 752, "proyecto", "Proyecto único",
           sub="<project_id> · cada recurso lleva el prefijo <prefix>-<env>-", dentro="gc")

    # Fila base
    D.caja("base", 372, 304, 1466, 132, "logico", "Base del proyecto",
           sub="0-bootstrap (una persona, una vez) y 1-base (pipeline)", dentro="proj")
    xs = fila(388, 1822, 5, 16)
    base = [
        ("estado", "cloud-storage", "Estado de Terraform", "Cloud Storage", "un prefijo por raíz · CMEK"),
        ("llaves", "cat-security", "Llaves y secretos", "Cloud KMS · Secret Manager", "por entorno"),
        ("wif", "cat-security", "Identidad del pipeline", "Workload Identity Federation", "9 cuentas tf-*, sin llaves"),
        ("imagenes", "cat-devtools", "Imágenes", "Artifact Registry", "con Binary Authorization"),
        ("auditoria", "cat-observability", "Auditoría y alertas", "Cloud Logging · Monitoring", "logs con CMEK"),
    ]
    for (x, w), (cid, ic, t, p, n) in zip(xs, base):
        D.tarjeta(cid, x, 340, w, 84, ic, t, p, n, dentro="base")
    D.flecha([(D.p("actions", "b")[0] + 0, D.p("actions", "b")[1]), (D.p("actions", "b")[0], 340)],
             "token OIDC", en=(D.p("actions", "b")[0], 247))

    # Fila hub
    D.caja("hub", 372, 450, 1398, 122, "logico", "Red común (hub)", sub="2-networks · us-central1 y us-east4",
           dentro="proj")
    cols = fila(388, 1754, 4, 16)
    hub = [
        ("vpn", "cat-networking", "Conectividad híbrida", "Cloud VPN (HA) + Cloud Router", "2 túneles con BGP por región"),
        ("dns", "cat-networking", "Nombres", "Cloud DNS", "reenvío a on-premises"),
        ("fw", "cat-security", "Firewall", "Política de firewall de red", "una por VPC, niega por defecto"),
        ("vpc-hub", "cat-networking", "VPC hub", "Virtual Private Cloud", "10.0.0.0/16 · sin salida a Internet"),
    ]
    for (x, w), (cid, ic, t, p, n) in zip(cols, hub):
        D.tarjeta(cid, x, 484, w, 78, ic, t, p, n, dentro="hub")

    # Entornos
    # Piezas encendidas según el terraform.tfvars.example de cada entorno
    entornos = [
        ("dev", 586, "10.10.0.0/16", "se apaga fuera de horario",
         ["cloud-run"], "Cloud Run", "GKE y MIG apagados",
         ["cloud-sql"], "Cloud SQL", "sin Memorystore ni Filestore"),
        ("qa", 724, "10.20.0.0/16", "se apaga fuera de horario",
         ["cloud-run", "compute-engine"], "Cloud Run · MIG", "GKE apagado",
         ["cloud-sql", "cat-databases"], "Cloud SQL · Memorystore", "sin Filestore"),
        ("prod", 862, "10.30.0.0/16", "HA regional y DR en us-east4",
         ["cloud-run", "gke", "compute-engine"], "Cloud Run · GKE · MIG", "",
         ["cloud-sql", "cat-databases", "cat-storage"], "Cloud SQL, Memorystore y Filestore", ""),
    ]
    for env, y, cidr, extra, ic_c, p_c, n_c, ic_d, p_d, n_d in entornos:
        D.caja(f"env-{env}", 372, y, 1398, 124, "logico", f"Entorno {env}",
               sub=f"2-networks/{env} y 3-workloads/{env} · cuentas tf-net-{env} y tf-wl-{env} · {extra}",
               dentro="proj")
        cy = y + 36
        (x0, w0), (x1, w1), (x2, w2), (x3, w3) = cols
        D.tarjeta(f"lb-{env}", x0, cy, w0, 80, "cat-networking", "Entrada pública", "Cloud Load Balancing",
                  "con Cloud Armor", dentro=f"env-{env}")
        D.tarjeta(f"comp-{env}", x1, cy, w1, 80, ic_c, "Cómputo", p_c, n_c, dentro=f"env-{env}", icono_px=32)
        D.tarjeta(f"datos-{env}", x2, cy, w2, 80, ic_d, "Datos", p_d, n_d, dentro=f"env-{env}", icono_px=32)
        D.tarjeta(f"vpc-{env}", x3, cy, w3, 80, "cat-networking", f"VPC {env}", cidr, "Cloud NAT · acceso privado",
                  dentro=f"env-{env}")

    # Peering hub-spoke (bus a la derecha)
    hx, hy = D.p("vpc-hub", "r")
    bus = 1806
    for env in ("dev", "qa", "prod"):
        ex, ey = D.p(f"vpc-{env}", "r")
        D.flecha([(hx, hy), (bus, hy), (bus, ey), (ex, ey)], grupo="peering", doble=True)
    D.flecha([(bus, hy + 30), (bus, hy + 31)], "peering", en=(bus, 590), rotar=-90, grupo="peering", sin_punta=True)
    # Sin peering entre spokes
    sx = D.p("vpc-dev", "b", 0.5)[0]
    D.flecha([D.p("vpc-dev", "b"), D.p("vpc-qa", "t")], "✕ sin peering entre spokes", color=GRIS, punteada=True,
             sin_punta=True, en=(sx, 717))

    # Fuera, a la izquierda
    vy = D.p("vpn", "l")[1]
    D.tarjeta("onprem", 40, vy - 40, 250, 80, "gen-edificio", "On-premises", "sitio real o simulado",
              "192.168.0.0/16")
    D.flecha([D.p("onprem", "r"), D.p("vpn", "l")], "IPsec + BGP", en=(339, vy - 20))
    uy = D.p("lb-prod", "l")[1]
    D.tarjeta("usuarios", 40, uy - 40, 250, 80, "gen-usuarios", "Usuarios de Internet", "navegador o API")
    D.flecha([D.p("usuarios", "r"), D.p("lb-prod", "l")], "HTTPS", en=(339, uy - 20))
    D.texto(374, 992, "Piezas encendidas según el terraform.tfvars.example de cada entorno; cada una se enciende "
                      "o apaga con una variable.", tam=14, color="#5F6368", id_="t-tfvars")
    D.leyenda(("gris", "No existe esa conexión"))
    return D


# =============================================================================================
# 2. Red
# =============================================================================================
def d2() -> Diagrama:
    D = Diagrama("02-red", "Red: hub-and-spoke en un solo proyecto, dos regiones",
                 "Cinco VPC globales; cada subred vive en una región. Los spokes se unen solo al hub; "
                 "on-premises (real o simulado) entra por HA VPN al hub.", 2)
    D.caja("gc", 40, 98, 1840, 938, "gcloud")
    D.caja("proj", 60, 136, 1800, 882, "proyecto", "Proyecto único",
           sub="las VPC son globales: cruzan las dos regiones", dentro="gc")
    D.texto(160, 180, "Global (toda la VPC)", tam=15, color="#5F6368", peso=700, id_="t-global")
    D.caja("use1", 490, 172, 760, 772, "region", "Región us-central1", sub="primaria", dentro="proj")
    D.caja("use4", 1270, 172, 574, 772, "region", "Región us-east4", sub="DR", dentro="proj")

    bandas = [
        ("onp", 212, "VPC onprem-sim", "192.168.0.0/24 · simula on-premises (opcional: simulate_onprem)", True),
        ("hub", 384, "VPC hub", "10.0.0.0/16", False),
        ("dev", 524, "VPC dev", "10.10.0.0/16", False),
        ("qa", 664, "VPC qa", "10.20.0.0/16", False),
        ("prod", 804, "VPC prod", "10.30.0.0/16", False),
    ]
    BX, BW, BH = 144, 1708, 128
    for bid, y, lab, sub, punt in bandas:
        D.caja(f"b-{bid}", BX, y, BW, BH, "vpc", lab, sub=sub, punteada=punt, alpha=0, dentro="proj")

    def cy(bid):
        return next(b[1] for b in bandas if b[0] == bid) + 36

    G = dict(x=160, w=310)       # columna global
    C1 = dict(sx=506, sw=350, cx=876, cw=358)     # us-central1: subred y tarjeta
    C4 = dict(sx=1286, sw=300, cx=1600, cw=228)   # us-east4

    # onprem-sim
    D.tarjeta("fw-onp", G["x"], cy("onp"), G["w"], 84, "cat-security", "Firewall propio",
              "Política de firewall de red", "DNS desde 35.199.192.0/19 e IAP", dentro="b-onp")
    # La VM DNS de prueba (stages/2-networks/onprem_dns.tf) vive en esta subred, en una zona de la
    # región primaria, y solo existe con onprem_dns_vm = true.
    D.caja("sn-onp", C1["sx"], cy("onp") - 2, C1["sw"], 88, "subred", "Subred onprem-sim",
           cuerpo=["192.168.0.0/24 · la única que anuncia la VPN", "VM DNS de prueba (opcional: onprem_dns_vm)"],
           dentro="use1")
    D.tarjeta("vpn-onp", C1["cx"], cy("onp"), C1["cw"], 84, "cat-networking", "Gateway HA VPN",
              "Cloud VPN (HA) + Cloud Router", "lado on-premises · ASN 65001", dentro="use1")
    D.tarjeta("vpn-onp-dr", C4["cx"] - 160, cy("onp"), C4["cw"] + 160, 84, "cat-networking", "Gateway de DR",
              "Cloud VPN (HA) + Cloud Router", "opcional: enable_vpn_dr", punteada=True, dentro="use4")
    # hub
    D.tarjeta("dns", G["x"], cy("hub"), G["w"], 84, "cat-networking", "DNS híbrido", "Cloud DNS",
              "reenvío a on-premises y entrada", dentro="b-hub")
    D.caja("sn-hub", C1["sx"], cy("hub") - 2, C1["sw"], 88, "subred", "Subred hub",
           cuerpo=["10.0.0.0/24", "acceso privado a las APIs de Google"], dentro="use1")
    D.tarjeta("vpn-hub", C1["cx"], cy("hub"), C1["cw"], 84, "cat-networking", "HA VPN primaria",
              "Cloud VPN (HA) + Cloud Router", "2 túneles · BGP · ASN 64514", dentro="use1")
    D.caja("sn-hub-dr", C4["sx"], cy("hub") - 2, C4["sw"] - 160, 88, "subred", "Subred hub_dr",
           cuerpo=["10.0.1.0/24"], dentro="use4")
    D.tarjeta("vpn-hub-dr", C4["cx"] - 160, cy("hub"), C4["cw"] + 160, 84, "cat-networking", "HA VPN de DR",
              "Cloud VPN (HA) + Cloud Router", "prioridad 200 · opcional", punteada=True, dentro="use4")
    # spokes
    for env, x in (("dev", 10), ("qa", 20), ("prod", 30)):
        bid = env
        D.tarjeta(f"psa-{env}", G["x"], cy(bid), G["w"], 84, "cat-networking", "Servicios privados",
                  "Private Service Access", f"10.{x}.176.0/20 · SQL, Redis, NFS", dentro=f"b-{bid}")
        cuerpo = [f"app 10.{x}.0.0/20 · proxy 10.{x}.32.0/23", f"run 10.{x}.36.0/24 · pods y services de GKE"]
        D.caja(f"sn-{env}", C1["sx"], cy(bid) - 2, C1["sw"], 88, "subred", f"Subredes de {env}", cuerpo=cuerpo,
               dentro="use1")
        D.tarjeta(f"nat-{env}", C1["cx"], cy(bid), C1["cw"], 84, "cat-networking", "Salida a Internet",
                  "Cloud NAT + Cloud Router", "una por spoke y región", dentro="use1")
        if env == "prod":
            D.caja("sn-prod-dr", C4["sx"], cy(bid) - 4, C4["sw"], 94, "subred", "Subredes de DR",
                   cuerpo=["app_dr 10.30.16.0/20", "proxy_dr 10.30.34.0/23", "run_dr 10.30.37.0/24"], dentro="use4")
            D.tarjeta("nat-prod-dr", C4["cx"], cy(bid), C4["cw"], 84, "cat-networking", "Salida a Internet",
                      "Cloud NAT", "en us-east4", dentro="use4")
        else:
            D.caja(f"sn-{env}-dr", C4["sx"], cy(bid) - 2, C4["sw"] + C4["cw"] + 14, 88, "subred",
                   "Subredes _dr reservadas", punteada=True,
                   cuerpo=["sin crear: enable_dr = false"], dentro="use4")

    # VPN entre onprem-sim y hub
    x1 = D.p("vpn-hub", "t")[0]
    D.flecha([D.p("vpn-onp", "b"), D.p("vpn-hub", "t")], "IPsec + BGP", doble=True, en=(x1, 362))
    x4 = D.p("vpn-hub-dr", "t")[0]
    D.flecha([D.p("vpn-onp-dr", "b"), D.p("vpn-hub-dr", "t")], "IPsec + BGP (DR)", doble=True, punteada=True,
             en=(x4, 362))

    # Peering
    hx, hy = D.p("b-hub", "l")
    lane = 104
    for env in ("dev", "qa", "prod"):
        ex, ey = D.p(f"b-{env}", "l")
        D.flecha([(hx, hy), (lane, hy), (lane, ey), (ex, ey)], grupo="peering", doble=True)
    D.flecha([(lane, hy + 10), (lane, hy + 11)], "peering", en=(lane, (hy + D.p("b-dev", "l")[1]) / 2), rotar=-90,
             grupo="peering", sin_punta=True)

    # Pie: firewall y sin peering entre spokes
    D.tarjeta("fw-red", 160, 956, 1060, 54, "cat-security", "Firewall: una política de firewall de red global por VPC",
              "niega por defecto; spokes: salud y proxies a lb_backend, IAP a iap_ssh, GKE y tráfico interno; "
              "hub: nada", dentro="proj", icono_px=34)
    D.tarjeta("nopeer", 1240, 956, 604, 54, "cat-networking", "Sin peering entre spokes",
              "el peering no es transitivo: dev, qa y prod no se ven", dentro="proj", icono_px=34)
    return D


# =============================================================================================
# 3. Aplicación y datos de prod
# =============================================================================================
def d3() -> Diagrama:
    D = Diagrama("03-aplicacion-y-datos", "Aplicación y datos de prod: del usuario a la base de datos",
                 "Entrada global con Cloud Armor, cómputo repartido en zonas, datos solo por IP privada "
                 "y copia en us-east4. dev y qa encienden menos piezas y no tienen DR.", 3)
    D.caja("gc", 310, 98, 1570, 938, "gcloud")
    D.caja("proj", 330, 136, 1530, 882, "proyecto", "Proyecto único",
           sub="entorno prod en la VPC prod · recursos <prefix>-prod-*", dentro="gc")

    # Entrada global
    D.caja("entrada", 350, 168, 670, 128, "logico", "Entrada global", dentro="proj")
    D.tarjeta("armor", 366, 204, 260, 80, "cat-security", "Filtro web", "Cloud Armor", "OWASP · límite de tasa",
              dentro="entrada")
    D.tarjeta("lb", 726, 204, 278, 80, "cat-networking", "Balanceador global", "Cloud Load Balancing",
              "HTTPS · TLS 1.2 mínimo", dentro="entrada")

    # Imágenes y llaves (columna izquierda)
    D.caja("img", 350, 330, 300, 236, "logico", "Imágenes", sub="multirregión us", dentro="proj")
    D.tarjeta("ar", 366, 366, 268, 84, "cat-devtools", "Repositorio de prod", "Artifact Registry",
              "imágenes de GKE y Cloud Run", dentro="img")
    D.tarjeta("binauthz", 366, 466, 268, 84, "cat-security", "Admisión de imágenes", "Binary Authorization",
              "solo repos del proyecto", dentro="img")
    D.caja("llaves", 350, 590, 300, 236, "logico", "Llaves y secretos", sub="1-base", dentro="proj")
    D.tarjeta("sm", 366, 626, 268, 84, "cat-security", "Secretos", "Secret Manager", "contenedores, sin valores",
              dentro="llaves")
    D.tarjeta("kms", 366, 726, 268, 84, "cat-security", "Llaves de cifrado", "Cloud KMS",
              "CMEK · rotación de 90 días", dentro="llaves")

    # Región primaria
    D.caja("use1", 680, 330, 798, 540, "region", "Región us-central1", sub="primaria", dentro="proj")
    zonas = [("a", 400), ("b", 496), ("c", 592)]
    for z, y in zonas:
        D.caja(f"z{z}", 696, y, 540, 88, "zona", f"zona {z}", dentro="use1")
    D.caja("gke", 768, 366, 226, 326, "cluster", "GKE regional", alpha=0.6, dentro="use1")
    D.caja("mig", 1004, 366, 226, 326, "mig", "MIG regional", alpha=0.6, dentro="use1")
    for z, y in zonas:
        D.tarjeta(f"nodo-{z}", 778, y + 7, 206, 74, "gke", "Nodos de GKE", "pods de <app>-prod", dentro="gke",
                  icono_px=36)
        D.tarjeta(f"vm-{z}", 1014, y + 7, 206, 74, "compute-engine", "VM de la app", "Compute Engine", dentro="mig",
                  icono_px=36)
    D.tarjeta("run", 1252, 400, 210, 92, "cloud-run", "Servicio web", "Cloud Run", "regional, sin zonas",
              dentro="use1")

    D.caja("datos", 696, 706, 766, 152, "logico", "Datos solo por IP privada",
           sub="Private Service Access 10.30.176.0/20", dentro="use1")
    dx = fila(712, 1446, 3, 14)
    datos = [
        ("redis", "cat-databases", "Caché", "Memorystore (Redis)", "HA en dos zonas · TLS"),
        ("nfs", "cat-storage", "Archivos NFS", "Filestore", "nivel regional"),
        ("sql", "cloud-sql", "Base de datos", "Cloud SQL", "PostgreSQL, HA regional, PITR y login por IAM"),
    ]
    for (x, w), (cid, ic, t, p, n) in zip(dx, datos):
        D.tarjeta(cid, x, 742, w, 104, ic, t, p, n, dentro="datos")

    # Región de DR
    D.caja("use4", 1500, 330, 344, 540, "region", "Región us-east4", sub="DR", dentro="proj")
    D.tarjeta("dr-comp", 1516, 400, 312, 110, ["cloud-run", "gke", "compute-engine"], "Cómputo de DR",
              "Cloud Run · GKE · MIG", "apagado: se crea con dr_active = true", punteada=True, dentro="use4",
              icono_px=30)
    D.tarjeta("bkp", 1516, 560, 312, 104, "cat-storage", "Respaldos", "Backup and DR",
              "bóveda: plan diario de Cloud SQL", dentro="use4")
    D.tarjeta("sql-dr", 1516, 742, 312, 104, "cloud-sql", "Réplica de lectura", "Cloud SQL",
              "se promueve en la conmutación", dentro="use4")

    # Doble región
    D.caja("dual", 680, 888, 1164, 118, "region", "Doble región", sub="us-central1 + us-east4", dentro="proj")
    D.tarjeta("gcs", 1250, 918, 460, 80, "cloud-storage", "Objetos y archivos", "Cloud Storage",
              "turbo replication · versionado · sin acceso público", dentro="dual")
    D.texto(700, 934, "Las cargas llegan a Cloud Storage y a las demás APIs de Google por Private Google Access "
                      "y el VIP restringido (199.36.153.4/30), sin salir a Internet.", tam=15, color="#3C4043",
            ancho=520, id_="t-pga")

    # Fuera
    D.tarjeta("usuarios", 40, 204, 250, 80, "gen-usuarios", "Usuarios de Internet", "navegador o API")
    D.tarjeta("pub", 40, 389, 250, 80, "gen-flujo", "Publicadores", "CI de la aplicación")

    # Flechas
    D.flecha([D.p("usuarios", "r"), D.p("armor", "l")], "HTTPS", en=(328, 226))
    D.flecha([D.p("armor", "r"), D.p("lb", "l")])
    D.flecha([(960, 284), (960, 366)], "NEG", en=(960, 313))
    D.flecha([D.p("lb", "r", 0.8), (1117, D.p("lb", "r", 0.8)[1]), (1117, 366)], "grupo de instancias",
             en=(1117, 313))
    D.flecha([D.p("lb", "r", 0.275), (1357, D.p("lb", "r", 0.275)[1]), (1357, 400)], "NEG sin servidor",
             en=(1190, D.p("lb", "r", 0.275)[1]))
    D.flecha([D.p("pub", "r"), D.p("ar", "l", (429 - 366) / 84)], "push", en=(328, 409))
    ay = D.p("ar", "r", 0.9)[1]
    D.flecha([D.p("ar", "r", 0.9), (768, ay)], "imágenes", en=(676, ay))
    by = D.p("binauthz", "r", 0.86)[1]
    D.flecha([D.p("binauthz", "r", 0.86), (768, by)], "admite o rechaza", punteada=True, en=(700, by))
    sy = D.p("sm", "r")[1]
    D.flecha([D.p("sm", "r"), (662, sy), (662, 640), (768, 640)], "secretos", punteada=True, en=(718, 640))
    ky = D.p("kms", "r")[1]
    D.flecha([D.p("kms", "r"), (696, ky)], "CMEK", punteada=True, en=(665, ky - 20))
    D.flecha([D.p("sql", "r"), D.p("sql-dr", "l")], "réplica", en=(1481, D.p("sql", "r")[1] - 20))
    sqx = D.p("sql", "t", 0.8)[0]
    D.flecha([(sqx, 742), (sqx, 612), (1516, 612)], "respaldo diario", en=(sqx, 660))
    D.leyenda(("punteada", "Control o dependencia"))
    return D


# =============================================================================================
# 4. Seguridad y operación
# =============================================================================================
def d4() -> Diagrama:
    D = Diagrama("04-seguridad-y-operacion", "Seguridad y operación: quién cambia qué y cómo nos enteramos",
                 "Cada trabajo del pipeline obtiene solo la cuenta de su entorno; la auditoría y las alertas viven "
                 "una vez por proyecto; dev y qa se apagan de noche.", 4)
    D.caja("gc", 310, 98, 1320, 938, "gcloud")
    D.caja("proj", 330, 136, 1280, 882, "proyecto", "Proyecto único", dentro="gc")

    # A. Identidad del pipeline
    D.caja("ident", 350, 172, 650, 432, "logico", "Identidad del pipeline", sub="0-bootstrap · nueve cuentas",
           dentro="proj")
    D.tarjeta("wif", 366, 210, 264, 100, "cat-security", "Identidad federada", "Workload Identity Federation",
              "sin llaves JSON", dentro="ident")
    D.tarjeta("estado", 366, 336, 264, 92, "cloud-storage", "Estado de Terraform", "Cloud Storage",
              "CMEK · un prefijo por raíz", dentro="ident")
    D.tarjeta("deny", 366, 470, 264, 112, "cat-security", "Protección del estado", "IAM Deny + etiqueta",
              "el pipeline no borra el bucket, no cambia WIF ni pide tokens; nadie crea llaves",
              dentro="ident")
    D.flecha([D.p("deny", "t"), D.p("estado", "b")], "protege", punteada=True, en=(498, 449))
    cuentas = [
        ("sa-common", "Cuentas de common", "tf-base · tf-net", "", 64),
        ("sa-dev", "Cuentas de dev", "tf-net-dev · tf-wl-dev", "", 64),
        ("sa-qa", "Cuentas de qa", "tf-net-qa · tf-wl-qa", "", 64),
        ("sa-prod", "Cuentas de prod", "tf-net-prod · tf-wl-prod", "", 64),
        ("sa-read", "Cuenta de lectura", "tf-read", "cualquier trabajo: plan, drift, humo", 82),
    ]
    y = 210
    wx, _ = D.p("wif", "r")
    for cid, t, p, n, h in cuentas:
        D.tarjeta(cid, 740, y, 244, h, "cat-security", t, p, n, dentro="ident", icono_px=34)
        cy = y + h / 2
        D.flecha([(wx, 242), (685, 242), (685, cy), (740, cy)], grupo="fan-wif")
        y += h + 10

    # B. Registro y auditoría
    D.caja("audit", 1020, 172, 570, 432, "logico", "Registro, auditoría y cuentas", sub="1-base, una vez por proyecto",
           dentro="proj")
    # El bucket de logs es de Cloud Storage (módulo log-export). Las métricas de las alertas se
    # calculan sobre los registros en Cloud Logging, no sobre el bucket: la flecha sale de los
    # registros y baja por la izquierda.
    D.tarjeta("logs", 1050, 208, 240, 112, "cat-observability", "Auditoría", "Cloud Audit Logs",
              "admin en todo; datos de KMS, secretos, IAM, SQL y Storage", dentro="audit")
    D.tarjeta("scc", 1320, 208, 254, 112, "scc", "Postura de seguridad", "Security Command Center",
              "activación manual", dentro="audit")
    D.tarjeta("bucket", 1050, 356, 240, 92, "cloud-storage", "Bucket de logs", "Cloud Storage",
              "destino del sink · retención", dentro="audit")
    D.tarjeta("kms-logs", 1320, 356, 254, 92, "cat-security", "Llave de logs", "Cloud KMS", "cifra el bucket (CMEK)",
              dentro="audit")
    D.tarjeta("alertas", 1320, 484, 254, 108, "cat-observability", "Alertas de auditoría", "Cloud Monitoring",
              "métricas de logs del CIS: IAM, firewall, rutas, red", dentro="audit")
    # Cuentas de ejecución de las cargas (stages/1-base/runtime_accounts.tf): las crea 1-base con
    # sus permisos; tf-wl-<env> solo puede adjuntar las de su entorno (serviceAccountUser).
    D.tarjeta("sa-run", 1050, 458, 240, 88, "cat-security", "Cuentas de cargas", "una por entorno, app y uso",
              "tf-wl-<env> solo las adjunta", dentro="audit", icono_px=34)
    D.flecha([D.p("logs", "b"), D.p("bucket", "t")], "sink", en=(1170, 338))
    D.flecha([D.p("kms-logs", "l"), D.p("bucket", "r")], punteada=True)
    lx, ly = D.p("logs", "l")
    ax, ay = D.p("alertas", "l", 0.7)
    D.flecha([(lx, ly), (1035, ly), (1035, ay), (ax, ay)], "métricas de logs", en=(1170, ay))

    # C. Apagado fuera de horario
    D.caja("apagado", 350, 624, 650, 380, "logico", "Apagado fuera de horario", sub="solo dev y qa; prod lo rechaza",
           dentro="proj")
    D.tarjeta("sched", 366, 690, 264, 104, "cat-integration", "Programador", "Cloud Scheduler",
              "lun-vie 07:00 a 20:00, America/Monterrey", dentro="apagado")
    D.tarjeta("sa-sched", 366, 860, 264, 120, "cat-security", "Cuenta -sched", "la crea 1-base, una por entorno y app",
              "rol OffHoursScheduler, solo su entorno", dentro="apagado")
    D.flecha([D.p("sa-sched", "t"), D.p("sched", "b")], "firma con", punteada=True, en=(498, 827))
    obj = [
        ("off-sql", "cloud-sql", "Detener y encender", "Cloud SQL", "activation policy", 78),
        ("off-gke", "gke", "Pools a cero", "GKE", "tamaño 0 de noche", 78),
        ("off-mig", "compute-engine", "MIG a cero", "Compute Engine", "programa de escalado", 78),
        ("off-run", "cloud-run", "Escala a cero sola", "Cloud Run", "", 66),
    ]
    yy = 660
    for cid, ic, t, p, n, h in obj:
        D.tarjeta(cid, 740, yy, 244, h, ic, t, p, n, dentro="apagado", icono_px=34)
        yy += h + 10
    sx, sy = D.p("sched", "r")
    for cid in ("off-sql", "off-gke"):
        ty = D.p(cid, "l")[1]
        D.flecha([(sx, sy), (685, sy), (685, ty), (740, ty)], grupo="fan-sched")

    # D. Monitoreo y continuidad
    D.caja("cont", 1020, 624, 570, 380, "logico", "Monitoreo y continuidad de prod", dentro="proj")
    D.tarjeta("mon", 1036, 662, 538, 92, "cat-observability", "Monitoreo y SLO", "Cloud Monitoring",
              "disponibilidad, errores 5xx, saturación, retraso de réplica · SLO 99.9 %", dentro="cont")
    D.caja("dr4", 1036, 774, 538, 214, "region", "Región us-east4", sub="DR", dentro="cont")
    D.tarjeta("bkp", 1052, 820, 253, 140, "cat-storage", "Respaldos", "Backup and DR",
              "bóveda; plan diario de Cloud SQL, 30 días", dentro="dr4")
    D.tarjeta("bkp-gke", 1315, 820, 243, 140, "gke", "Respaldo del clúster", "Backup for GKE",
              "plan de respaldo en us-east4", dentro="dr4")

    # Fuera
    # Centro a la altura de la flecha OIDC (y = 250). Las cuentas que escriben solo aceptan el
    # trabajo apply de _terraform-root.yml en main, con push o workflow_dispatch y environment
    # (attribute.deploy de stages/0-bootstrap/wif.tf).
    D.tarjeta("actions", 40, 200, 250, 100, "gen-flujo", "GitHub Actions", "trabajo con environment",
              "escribe solo _terraform-root.yml en main")
    D.flecha([D.p("actions", "r"), D.p("wif", "l", 0.4)], "OIDC", en=(328, 230))
    D.tarjeta("correo", 1660, 480, 220, 90, "gen-correo", "Correo de alertas", "canales y contactos esenciales")
    D.flecha([D.p("alertas", "r", 0.4), (1660, D.p("alertas", "r", 0.4)[1])])
    my = D.p("mon", "r")[1]
    D.flecha([D.p("mon", "r"), (1770, my), (1770, 570)], "correo", en=(1700, my))
    D.leyenda(("punteada", "Control o dependencia"))
    return D


# =============================================================================================
# 5. Pipeline
# =============================================================================================
def d5() -> Diagrama:
    D = Diagrama("05-pipeline", "Pipeline: de un pull request a los tres entornos",
                 "Nadie aplica a mano desde la etapa 1: GitHub Actions planea con una cuenta de solo lectura, "
                 "revisa políticas, pide aprobación y aplica con la cuenta de cada raíz.", 5)
    D.caja("gh", 40, 98, 1430, 938, "externo", "GitHub", sub="repositorio privado · GitHub Actions")
    D.caja("gc", 1494, 98, 386, 938, "gcloud")
    D.caja("proj", 1512, 136, 350, 882, "proyecto", "Proyecto único", dentro="gc")

    def carril(cid, y, h, etiqueta, sub, tarjetas, alto=104, gap=46, sin_flecha=()):
        D.caja(cid, 60, y, 1390, h, "logico", etiqueta, sub=sub, dentro="gh")
        xs = fila(76, 1434, len(tarjetas), gap)
        prev = None
        for (x, w), t in zip(xs, tarjetas):
            tid, ic, ti, pr, no = t[:5]
            punt = len(t) > 5 and t[5]
            D.tarjeta(tid, x, y + 38, w, alto, ic, ti, pr, no, punteada=punt, dentro=cid)
            if prev and tid not in sin_flecha:
                D.flecha([D.p(prev, "r"), D.p(tid, "l")], punteada=punt)
            prev = tid

    carril("l1", 136, 160, "1 · Pull request", "pr.yml", [
        ("pr", "gen-repositorio", "Pull request", "rama fix/… o verif/…", "nada directo a main"),
        ("rev", "gen-politica", "Revisiones sin GCP", "check.sh, 3 scripts y Go",
         "fmt, validate, tflint, checkov, terraform test"),
        ("plan1", "gen-plan", "Plan por raíz", "cuenta tf-read", "-lock=false, resumen y costo en el PR"),
        ("conf1", "gen-politica", "Conftest", "políticas sobre el plan", "una violación bloquea el merge"),
        ("gate", "gen-aprobacion", "plan-gate y revisión", "check obligatorio", "luego, merge a main"),
    ], gap=38)
    carril("l2", 326, 268, "2 · Despliegue", "apply.yml", [
        ("plan2", "gen-plan", "Plan y huella", "cuenta tf-read", "SHA-256 del plan, sin valores"),
        ("conf2", "gen-politica", "Conftest", "las mismas políticas", "una denegación detiene todo"),
        ("apro", "gen-aprobacion", "Aprobación", "entornos common y prod", "quien aprueba ve el resumen del plan"),
        ("apply", "gen-flujo", "Apply", "cuenta de la raíz", "solo si la huella coincide"),
    ], gap=60)
    # merge -> apply.yml
    gx, gy = D.p("gate", "b")
    D.flecha([(gx, gy), (gx, 311), (330, 311), (330, 364)], "el merge a main dispara apply.yml", en=(760, 311))
    # Orden
    D.texto(78, 512, "Orden:", tam=16, color="#00687A", peso=700, id_="t-orden")
    chips = [("o1", "1-base", 80), ("o2", "hub", 60), ("o3", "dev · red", 100), ("o4", "dev · cargas", 120),
             ("o5", "prueba de humo", 150), ("o6", "qa · red", 92), ("o7", "qa · cargas", 112),
             ("o8", "prod · red", 104), ("o9", "prod · cargas", 124)]
    x = 150
    prev = None
    for cid, txt, w in chips:
        D.chip(cid, x, 506, w, 32, txt, destacado=(cid == "o5"), dentro="l2")
        if prev:
            D.flecha([D.p(prev, "r"), D.p(cid, "l")])
        prev = cid
        x += w + 26
    D.texto(150, 552, "Una raíz a la vez; cada una espera a la anterior. Si la prueba de humo de dev falla, qa y prod "
                      "no se aplican. 0-bootstrap lo aplica una persona, fuera del pipeline.",
            tam=15, color="#3C4043", id_="t-humo")

    carril("l3", 624, 160, "3 · Revisión diaria", "drift.yml · 12:17 UTC", [
        ("drift", "gen-plan", "Plan diario", "cuenta tf-read", "plan -detailed-exitcode por raíz"),
        ("issue", "gen-incidencia", "Incidencia drift", "issue en GitHub", "se atiende con el runbook 05"),
        ("noadm", "cat-management", "No administrados", "Cloud Asset Inventory", "recursos que ningún estado conoce"),
    ], gap=120, sin_flecha=("noadm",))
    carril("l4", 814, 200, "4 · Destrucción bajo demanda", "destroy.yml · solo dev o qa", [
        ("pedido", "gen-aprobacion", "Pedido manual", "entorno + confirmación", "workflow_dispatch desde main"),
        ("dwl", "gen-borrar", "Destroy de cargas", "3-workloads/<env>", "mismo plan, huella y aprobación"),
        ("dnet", "gen-borrar", "Destroy de la red", "2-networks/<env>", "solo con incluir_red = true", True),
        ("huerf", "cat-management", "Huérfanos", "Cloud Asset Inventory", "etiqueta env y prefijo <prefix>-<env>-"),
    ])
    D.texto(78, 968, "Se conserva lo del entorno que vive en 1-base: llaves KMS, repositorios, contenedores de "
                     "secretos y cuentas de ejecución. GCP_DISABLED_ENVS evita que apply.yml lo vuelva a crear.",
            tam=15, color="#3C4043", id_="t-conserva")

    # Google Cloud
    g = [
        ("g-read", 174, 104, "cat-security", "Cuenta de lectura", "tf-read, por WIF",
         "la usan plan, drift, humo y huérfanos"),
        ("g-write", 364, 104, "cat-security", "Cuentas que escriben", "tf-base · tf-net · tf-*-<env>",
         "WIF: _terraform-root.yml en main, con environment"),
        ("g-state", 490, 96, "cloud-storage", "Estado de Terraform", "Cloud Storage",
         "el apply toma el candado; el plan no"),
        ("g-cai", 662, 104, "cat-management", "Inventario", "Cloud Asset Inventory", "alcance: el proyecto"),
        ("g-envs", 852, 104, ["cloud-run", "gke", "cloud-sql"], "Recursos del entorno", "prefijo <prefix>-<env>-",
         "cargas y red de dev o qa"),
    ]
    for cid, y, h, ic, t, p, n in g:
        D.tarjeta(cid, 1528, y, 318, h, ic, t, p, n, dentro="proj", icono_px=(30 if isinstance(ic, list) else 40))
    D.flecha([D.p("apply", "r"), (1528, D.p("apply", "r")[1])], "apply", en=(1489, 396))
    D.flecha([D.p("noadm", "r"), (1528, D.p("noadm", "r")[1])], "consulta", en=(1489, 694))
    D.flecha([D.p("huerf", "r"), (1528, D.p("huerf", "r")[1])], "busca", en=(1489, 884))
    D.leyenda(("punteada", "Opcional"))
    return D


DIAGRAMAS = {1: d1, 2: d2, 3: d3, 4: d4, 5: d5}

# Nombre del archivo PNG de cada ícono
NOMBRES_PNG = {
    "cloud-run": "cloud-run", "cloud-sql": "cloud-sql", "cloud-storage": "cloud-storage",
    "compute-engine": "compute-engine", "gke": "gke", "scc": "security-command-center",
    "cat-networking": "categoria-networking", "cat-security": "categoria-security-identity",
    "cat-databases": "categoria-databases", "cat-storage": "categoria-storage",
    "cat-devtools": "categoria-developer-tools", "cat-observability": "categoria-observability",
    "cat-integration": "categoria-integration-services", "cat-management": "categoria-management-tools",
    "cat-compute": "categoria-compute", "cat-containers": "categoria-containers",
}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--solo", nargs="*", type=int, help="números de diagrama (1 a 5)")
    ap.add_argument("--sin-png", action="store_true", help="no exportar PNG")
    ap.add_argument("--iconos", default=os.environ.get("GCP_ICONS_DIR"),
                    help="carpeta con los zip oficiales de íconos descomprimidos (o GCP_ICONS_DIR)")
    ap.add_argument("--salida", default=os.environ.get("DIAGRAMAS_SALIDA")
                    or str(Path(tempfile.gettempdir()) / "diagramas-gcp"),
                    help="carpeta de salida (por defecto <temporal del sistema>/diagramas-gcp)")
    ap.add_argument("--img", action="store_true",
                    help="copiar los PNG 1x a ../img, la carpeta que muestran los documentos")
    a = ap.parse_args(argv)

    if not a.iconos:
        raise SystemExit("Falta la carpeta de íconos: --iconos RUTA o GCP_ICONS_DIR "
                         "(zip oficiales de https://cloud.google.com/icons, descomprimidos).")
    carpeta_iconos = Path(a.iconos)
    if not carpeta_iconos.is_dir():
        raise SystemExit(f"No existe la carpeta de íconos: {carpeta_iconos} (usa --iconos o GCP_ICONS_DIR)")
    salida = Path(a.salida)
    (salida / "html").mkdir(parents=True, exist_ok=True)
    (salida / "png").mkdir(exist_ok=True)
    (salida / "iconos-png").mkdir(exist_ok=True)

    iconos = Iconos(carpeta_iconos)
    chrome = Chrome()
    hallazgos_total = {}
    try:
        numeros = a.solo or sorted(DIAGRAMAS)
        for n in numeros:
            D = DIAGRAMAS[n]()
            ruta = salida / "html" / f"{D.nombre}.html"
            ruta.write_text(D.html(iconos), encoding="utf-8")
            qa = leer_qa(chrome.dom(ruta))
            hallazgos_total[D.nombre] = qa
            graves = [q for q in qa if not q.startswith("info")]
            print(f"[{n}] {D.nombre}: {len(graves)} hallazgos" + ("" if not qa else ""))
            for q in qa:
                print("     ", q)
            if not a.sin_png:
                chrome.captura(ruta, salida / "png" / f"{D.nombre}.png", 1920, 1080, 1)
                chrome.captura(ruta, salida / "png" / f"{D.nombre}@2x.png", 1920, 1080, 2)
                if a.img:
                    img = AQUI.parent / "img"
                    img.mkdir(exist_ok=True)
                    shutil.copyfile(salida / "png" / f"{D.nombre}.png", img / f"{D.nombre}.png")

        if not a.sin_png and not a.solo:
            for clave in sorted(iconos.usados):
                nombre = NOMBRES_PNG.get(clave, clave)
                h = salida / "html" / f"icono-{nombre}.html"
                h.write_text(PLANTILLA_ICONO.replace("{{URI}}", iconos.uri(clave)), encoding="utf-8")
                chrome.captura(h, salida / "iconos-png" / f"{nombre}.png", 256, 256, 1, transparente=True)
                h.unlink()
            print(f"Íconos PNG: {len(iconos.usados)}")
        lineas = []
        for nombre, qa in hallazgos_total.items():
            lineas.append(f"{nombre}: {len([q for q in qa if not q.startswith('info')])} hallazgos")
            lineas.extend("  " + q for q in qa)
        (salida / "qa.txt").write_text("\n".join(lineas) + "\n", encoding="utf-8")
        print(f"Salida: {salida}" + (f"; PNG 1x copiados a {AQUI.parent / 'img'}" if a.img and not a.sin_png else ""))
    finally:
        chrome.cerrar()


if __name__ == "__main__":
    sys.exit(main())
