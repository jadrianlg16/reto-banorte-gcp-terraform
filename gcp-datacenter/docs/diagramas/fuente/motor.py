"""Motor de diagramas: contenedores pastel, tarjetas con ícono, flechas y revisión automática.

Cada diagrama se arma con coordenadas absolutas sobre un lienzo de 1920x1080 y se escribe como
un HTML autocontenido (íconos SVG incrustados como data URI). Chrome sin cabeza lo convierte en
PNG. Un script dentro de la página revisa textos que no caben, tarjetas encimadas, flechas que
cruzan tarjetas y etiquetas encimadas; el resultado se lee con --dump-dom.
"""
from __future__ import annotations

import base64
import html
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

W, H = 1920, 1080
FUENTE = "Arial, Helvetica, sans-serif"

AZUL = "#1A73E8"        # flechas
AZUL_TEXTO = "#1967D2"  # etiquetas de flechas
GRIS = "#80868B"        # flechas de "no hay" o de referencia

# Paleta pastel propia (los códigos de la leyenda oficial no se conocen).
PALETA = {
    "gcloud":   dict(fill="#FFFFFF", border="#9AA0A6", text="#3C4043", nombre="Google Cloud"),
    "proyecto": dict(fill="#F1F3F4", border="#C9CDD2", text="#3C4043", nombre="Proyecto"),
    "logico":   dict(fill="#E4F7FB", border="#93D5E3", text="#00687A", nombre="Agrupación lógica"),
    "region":   dict(fill="#E8F0FE", border="#A8C7FA", text="#1859B8", nombre="Región"),
    "zona":     dict(fill="#FEF7E0", border="#F2CF63", text="#7A5000", nombre="Zona"),
    "vpc":      dict(fill="#E6F4EA", border="#7CC48F", text="#0F6A2E", nombre="VPC"),
    "subred":   dict(fill="#F3E8FD", border="#CFA3F7", text="#7B2CBF", nombre="Subred"),
    "cluster":  dict(fill="#FCE4EC", border="#F08CB0", text="#A8124A", nombre="Clúster de Kubernetes"),
    "mig":      dict(fill="#FFEBD9", border="#F6AE6E", text="#954400", nombre="Grupo de instancias"),
    "firewall": dict(fill="#FCE8E6", border="#F08B84", text="#A50E0E", nombre="Firewall"),
    "externo":  dict(fill="#FFFFFF", border="#BDC1C6", text="#3C4043", nombre="Fuera de Google Cloud"),
}

# --------------------------------------------------------------------------------------------
# Íconos
# --------------------------------------------------------------------------------------------

# Íconos oficiales: clave -> patrón del nombre de archivo dentro de la carpeta de íconos.
ICONOS_OFICIALES = {
    # Productos con ícono propio (core-products-icons)
    "cloud-run": "CloudRun-512-color*.svg",
    "cloud-sql": "CloudSQL-512-color*.svg",
    "cloud-storage": "Cloud_Storage-512-color*.svg",
    "compute-engine": "ComputeEngine-512-color*.svg",
    "gke": "GKE-512-color*.svg",
    "scc": "SecurityCommandCenter-512-color*.svg",
    # Categorías (category-icons)
    "cat-networking": "Networking-512-color*.svg",
    "cat-security": "SecurityIdentity-512-color*.svg",
    "cat-databases": "Databases-512-color*.svg",
    "cat-storage": "Storage-512-color*.svg",
    "cat-devtools": "Developer_Tools-512-color*.svg",
    "cat-observability": "Observability-512-color*.svg",
    "cat-integration": "IntegrationServices-512-color*.svg",
    "cat-management": "ManagementTools-512-color*.svg",
    "cat-compute": "Compute-512-color*.svg",
    "cat-containers": "Containers-512-color*.svg",
}

_G = "#5F6368"
_B = "#1A73E8"
# Íconos genéricos dibujados aquí (no son logotipos de nadie).
ICONOS_GENERICOS = {
    "gen-usuarios": f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
<circle cx="24" cy="20" r="9" fill="{_G}"/><path d="M6 50c0-10 8-17 18-17s18 7 18 17v4H6z" fill="{_G}"/>
<circle cx="44" cy="22" r="7.5" fill="#9AA0A6"/><path d="M38 35.5c1.9-.6 3.9-.9 6-.9 8.8 0 15 6 15 15v4H46v-4c0-5.6-2.9-10.6-8-14.1z" fill="#9AA0A6"/></svg>""",
    "gen-repositorio": f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none" stroke="{_G}" stroke-width="4" stroke-linecap="round">
<circle cx="18" cy="14" r="6"/><circle cx="18" cy="50" r="6"/><circle cx="46" cy="22" r="6"/>
<path d="M18 20v24"/><path d="M46 28c0 10-8 12-16 13-6 .8-10 2-12 4"/></svg>""",
    "gen-flujo": f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
<rect x="4" y="8" width="56" height="48" rx="7" fill="none" stroke="{_G}" stroke-width="4"/>
<path d="M4 20h56" stroke="{_G}" stroke-width="4"/>
<circle cx="18" cy="38" r="6" fill="{_B}"/><circle cx="46" cy="38" r="6" fill="{_G}"/>
<path d="M24 38h14" stroke="{_G}" stroke-width="4"/><path d="M34 32l6 6-6 6" fill="none" stroke="{_G}" stroke-width="4" stroke-linejoin="round"/></svg>""",
    "gen-edificio": f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
<path d="M10 58V10h28v48z" fill="{_G}"/><path d="M38 58V26h18v32z" fill="#9AA0A6"/>
<g fill="#fff"><rect x="16" y="16" width="6" height="6"/><rect x="26" y="16" width="6" height="6"/>
<rect x="16" y="28" width="6" height="6"/><rect x="26" y="28" width="6" height="6"/>
<rect x="16" y="40" width="6" height="6"/><rect x="26" y="40" width="6" height="6"/>
<rect x="43" y="32" width="8" height="5"/><rect x="43" y="42" width="8" height="5"/></g>
<path d="M4 58h56" stroke="{_G}" stroke-width="4"/></svg>""",
    "gen-politica": f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
<path d="M14 6h26l12 12v40H14z" fill="none" stroke="{_G}" stroke-width="4" stroke-linejoin="round"/>
<path d="M38 6v14h14" fill="none" stroke="{_G}" stroke-width="4" stroke-linejoin="round"/>
<path d="M22 38l7 7 13-14" fill="none" stroke="{_B}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/></svg>""",
    "gen-plan": f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" stroke-linecap="round">
<path d="M14 6h26l12 12v40H14z" fill="none" stroke="{_G}" stroke-width="4" stroke-linejoin="round"/>
<path d="M38 6v14h14" fill="none" stroke="{_G}" stroke-width="4" stroke-linejoin="round"/>
<path d="M22 30h10M22 39h20M22 48h16" stroke="{_B}" stroke-width="4"/>
<path d="M36 30h6" stroke="{_G}" stroke-width="4"/></svg>""",
    "gen-aprobacion": f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
<circle cx="24" cy="20" r="10" fill="{_G}"/><path d="M4 56c0-11 9-19 20-19 5 0 9 1.5 12.5 4.2L33 56z" fill="{_G}"/>
<circle cx="47" cy="45" r="14" fill="{_B}"/><path d="M40 45l5 5 9-10" fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/></svg>""",
    "gen-correo": f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
<rect x="6" y="14" width="52" height="38" rx="5" fill="none" stroke="{_G}" stroke-width="4"/>
<path d="M8 18l24 18 24-18" fill="none" stroke="{_B}" stroke-width="4" stroke-linejoin="round"/></svg>""",
    "gen-incidencia": f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
<circle cx="32" cy="32" r="24" fill="none" stroke="{_G}" stroke-width="4"/>
<path d="M32 18v18" stroke="{_B}" stroke-width="6" stroke-linecap="round"/><circle cx="32" cy="45" r="3.6" fill="{_B}"/></svg>""",
    "gen-prueba": f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
<path d="M24 6h16M28 6v16L12 52c-2 4 1 6 4 6h32c3 0 6-2 4-6L36 22V6" fill="none" stroke="{_G}" stroke-width="4" stroke-linejoin="round" stroke-linecap="round"/>
<path d="M19 42h26l5 10H14z" fill="{_B}"/></svg>""",
    "gen-borrar": f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none" stroke="{_G}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round">
<path d="M10 16h44"/><path d="M24 16V9h16v7"/><path d="M15 16l3 40h28l3-40"/>
<path d="M27 26v22M37 26v22" stroke="{_B}"/></svg>""",
}


def _buscar_icono(carpeta: Path, patron: str) -> Path:
    hallados = sorted(p for p in carpeta.rglob(patron) if p.suffix.lower() == ".svg")
    if not hallados:
        raise FileNotFoundError(f"No se encontró el ícono {patron!r} en {carpeta}")
    return hallados[0]


class Iconos:
    """Carga los SVG oficiales (sin modificarlos) y los genéricos; da data URIs."""

    def __init__(self, carpeta: Path):
        self.carpeta = carpeta
        self._cache: dict[str, bytes] = {}
        self.usados: set[str] = set()

    def svg(self, clave: str) -> bytes:
        if clave not in self._cache:
            if clave in ICONOS_OFICIALES:
                self._cache[clave] = _buscar_icono(self.carpeta, ICONOS_OFICIALES[clave]).read_bytes()
            elif clave in ICONOS_GENERICOS:
                self._cache[clave] = ICONOS_GENERICOS[clave].encode("utf-8")
            else:
                raise KeyError(f"Ícono desconocido: {clave}")
        return self._cache[clave]

    def ruta(self, clave: str) -> Path | None:
        if clave in ICONOS_OFICIALES:
            return _buscar_icono(self.carpeta, ICONOS_OFICIALES[clave])
        return None

    def uri(self, clave: str) -> str:
        self.usados.add(clave)
        return "data:image/svg+xml;base64," + base64.b64encode(self.svg(clave)).decode("ascii")


# --------------------------------------------------------------------------------------------
# Diagrama
# --------------------------------------------------------------------------------------------

def _rgba(hex_color: str, alpha: float) -> str:
    h = hex_color.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return f"rgba({r},{g},{b},{alpha})"


def _e(texto: str) -> str:
    return html.escape(texto, quote=True)


def _t(texto: str) -> str:
    """Escapa y mantiene en una línea las palabras con guion (us-east4, 1-base, tf-net-dev)."""
    return re.sub(r"(\S*-\S*)", r'<span class="nw">\1</span>', _e(texto))


def fila(x0: float, x1: float, n: int, gap: float) -> list[tuple[float, float]]:
    """Reparte n elementos entre x0 y x1 con separación gap: lista de (x, ancho)."""
    w = (x1 - x0 - gap * (n - 1)) / n
    return [(x0 + i * (w + gap), w) for i in range(n)]


class Diagrama:
    def __init__(self, nombre: str, titulo: str, subtitulo: str, numero: int, total: int = 5):
        self.nombre = nombre
        self.titulo = titulo
        self.subtitulo = subtitulo
        self.numero = numero
        self.total = total
        self.cajas: list[dict] = []
        self.tarjetas: dict[str, dict] = {}
        self.chips: dict[str, dict] = {}
        self.flechas: list[dict] = []
        self.textos: list[dict] = []
        self.leyenda_tipos: list[str] = []
        self.leyenda_extra: list[tuple[str, str]] = []

    # ---- elementos ---------------------------------------------------------------------------
    def caja(self, id_, x, y, w, h, tipo, etiqueta="", sub="", punteada=False, alpha=1.0,
             cuerpo=None, dentro=None, etiqueta_abajo=False):
        """Contenedor de color. cuerpo: lista de líneas de texto debajo de la etiqueta."""
        self.cajas.append(dict(id=id_, x=x, y=y, w=w, h=h, tipo=tipo, etiqueta=etiqueta, sub=sub,
                               punteada=punteada, alpha=alpha, cuerpo=cuerpo or [], dentro=dentro,
                               abajo=etiqueta_abajo))
        if tipo not in self.leyenda_tipos and tipo not in ("gcloud",):
            self.leyenda_tipos.append(tipo)
        return self.cajas[-1]

    def tarjeta(self, id_, x, y, w, h, iconos, titulo, producto="", nota="", punteada=False,
                dentro=None, icono_px=40):
        if isinstance(iconos, str):
            iconos = [iconos]
        assert id_ not in self.tarjetas, id_
        self.tarjetas[id_] = dict(id=id_, x=x, y=y, w=w, h=h, iconos=iconos, titulo=titulo,
                                  producto=producto, nota=nota, punteada=punteada, dentro=dentro,
                                  icono_px=icono_px)
        return self.tarjetas[id_]

    def chip(self, id_, x, y, w, h, texto, destacado=False, punteado=False, dentro=None):
        self.chips[id_] = dict(id=id_, x=x, y=y, w=w, h=h, texto=texto, destacado=destacado,
                               punteado=punteado, dentro=dentro)
        return self.chips[id_]

    def texto(self, x, y, texto, tam=15, color="#3C4043", peso=400, ancho=None, alinear="left",
              id_=None, cursiva=False):
        self.textos.append(dict(x=x, y=y, texto=texto, tam=tam, color=color, peso=peso, ancho=ancho,
                                alinear=alinear, id=id_, cursiva=cursiva))

    def _rect(self, id_):
        e = self.tarjetas.get(id_) or self.chips.get(id_)
        if e is None:
            e = next(c for c in self.cajas if c["id"] == id_)
        return e

    def p(self, id_, lado, t=0.5, d=0):
        """Punto en el borde de una tarjeta, chip o caja. lado: l, r, t, b. t: fracción."""
        e = self._rect(id_)
        x, y, w, h = e["x"], e["y"], e["w"], e["h"]
        if lado == "l":
            return (x - d, y + h * t)
        if lado == "r":
            return (x + w + d, y + h * t)
        if lado == "t":
            return (x + w * t, y - d)
        if lado == "b":
            return (x + w * t, y + h + d)
        raise ValueError(lado)

    def flecha(self, puntos, etiqueta=None, en=None, punteada=False, doble=False, color=AZUL,
               grupo=None, sin_punta=False, rotar=0, id_=None, desde=None, hasta=None):
        """puntos: lista de (x, y). en: (x, y) de la etiqueta o fracción 0-1 del recorrido."""
        self.flechas.append(dict(puntos=[tuple(map(float, q)) for q in puntos], etiqueta=etiqueta,
                                 en=en, punteada=punteada, doble=doble, color=color, grupo=grupo,
                                 sin_punta=sin_punta, rotar=rotar,
                                 id=id_ or f"f{len(self.flechas) + 1}", desde=desde, hasta=hasta))

    def leyenda(self, *extra):
        self.leyenda_extra.extend(extra)

    # ---- HTML ---------------------------------------------------------------------------------
    def html(self, iconos: Iconos) -> str:
        partes = []
        # Encabezado
        partes.append(f'<div class="tit">{_e(self.titulo)}</div>')
        partes.append(f'<div class="sub">{_e(self.subtitulo)}</div>')
        partes.append(f'<div class="num">{self.numero} / {self.total}</div>')

        # Cajas
        for i, c in enumerate(self.cajas):
            pal = PALETA[c["tipo"]]
            fill = pal["fill"] if c["alpha"] >= 1 else (_rgba(pal["fill"], c["alpha"]) if c["alpha"] > 0 else "transparent")
            borde = f'{2 if c["tipo"] in ("gcloud",) else 1.5}px {"dashed" if c["punteada"] else "solid"} {pal["border"]}'
            if c["punteada"]:
                borde = f'2px dashed {pal["border"] if c["tipo"] != "externo" else "#9AA0A6"}'
            estilo = (f'left:{c["x"]}px;top:{c["y"]}px;width:{c["w"]}px;height:{c["h"]}px;'
                      f'background:{fill};border:{borde};z-index:{10 + i}')
            lab = ""
            if c["etiqueta"]:
                sub = f'<span class="bsub"> · {_e(c["sub"])}</span>' if c["sub"] else ""
                fondo = pal["fill"]
                pos = "bottom:6px" if c["abajo"] else "top:7px"
                lab = (f'<div class="blab" id="lab-{_e(c["id"])}" style="{pos};color:{pal["text"]};background:{fondo}">'
                       f'{_e(c["etiqueta"])}{sub}</div>')
            cuerpo = ""
            if c["cuerpo"]:
                lineas = "".join(f'<div>{_t(l)}</div>' for l in c["cuerpo"])
                cuerpo = f'<div class="bcuerpo">{lineas}</div>'
            gc = ""
            if c["tipo"] == "gcloud":
                lab = (f'<div class="blab gc" id="lab-{_e(c["id"])}" style="top:8px;color:{pal["text"]};background:#fff">'
                       f'{_e(c["etiqueta"] or "Google Cloud")}</div>')
            partes.append(f'<div class="box" id="{_e(c["id"])}" data-tipo="{c["tipo"]}" '
                          f'data-dentro="{_e(c["dentro"] or "")}" style="{estilo}">{lab}{cuerpo}{gc}</div>')

        # Flechas (SVG)
        svg = [f'<svg class="flechas" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
               "<defs>"]
        for nombre, col in (("az", AZUL), ("gr", GRIS)):
            svg.append(f'<marker id="p-{nombre}" viewBox="0 0 10 10" refX="9.5" refY="5" markerUnits="userSpaceOnUse" '
                       f'markerWidth="12" markerHeight="12" orient="auto-start-reverse">'
                       f'<path d="M0,0.5 L10,5 L0,9.5 z" fill="{col}"/></marker>')
        svg.append("</defs>")
        etiquetas = []
        for f in self.flechas:
            col = f["color"]
            m = "az" if col == AZUL else "gr"
            d = _ruta(f["puntos"])
            attrs = f'stroke="{col}" stroke-width="2.2" fill="none" stroke-linejoin="round"'
            if f["punteada"]:
                attrs += ' stroke-dasharray="7 5"'
            if not f["sin_punta"]:
                attrs += f' marker-end="url(#p-{m})"'
                if f["doble"]:
                    attrs += f' marker-start="url(#p-{m})"'
            pts = ";".join(f"{x:.1f},{y:.1f}" for x, y in f["puntos"])
            svg.append(f'<path id="{_e(f["id"])}" class="fl" data-pts="{pts}" data-grupo="{_e(f["grupo"] or "")}" '
                       f'data-desde="{_e(f["desde"] or "")}" data-hasta="{_e(f["hasta"] or "")}" d="{d}" {attrs}/>')
            if f["etiqueta"]:
                if f["en"] is None:
                    lx, ly = _punto_en(f["puntos"], 0.5)
                elif isinstance(f["en"], (int, float)):
                    lx, ly = _punto_en(f["puntos"], float(f["en"]))
                else:
                    lx, ly = f["en"]
                rot = f' rotate({f["rotar"]}deg)' if f["rotar"] else ""
                colt = AZUL_TEXTO if col == AZUL else "#5F6368"
                etiquetas.append(f'<div class="alab" id="lab-{_e(f["id"])}" style="left:{lx}px;top:{ly}px;color:{colt};'
                                 f'transform:translate(-50%,-50%){rot}">{_e(f["etiqueta"])}</div>')
        svg.append("</svg>")
        partes.append("".join(svg))

        # Tarjetas
        for t in self.tarjetas.values():
            ics = "".join(f'<img src="{iconos.uri(k)}" style="width:{t["icono_px"]}px;height:{t["icono_px"]}px" alt="">'
                          for k in t["iconos"])
            txt = f'<div class="t">{_t(t["titulo"])}</div>'
            if t["producto"]:
                txt += f'<div class="p">{_t(t["producto"])}</div>'
            if t["nota"]:
                txt += f'<div class="n">{_t(t["nota"])}</div>'
            cls = "card dashed" if t["punteada"] else "card"
            partes.append(f'<div class="{cls}" id="{_e(t["id"])}" data-dentro="{_e(t["dentro"] or "")}" '
                          f'style="left:{t["x"]}px;top:{t["y"]}px;width:{t["w"]}px;height:{t["h"]}px">'
                          f'<div class="ics">{ics}</div><div class="tx">{txt}</div></div>')
        for c in self.chips.values():
            cls = "chip" + (" dest" if c["destacado"] else "") + (" dashed" if c["punteado"] else "")
            partes.append(f'<div class="{cls}" id="{_e(c["id"])}" data-dentro="{_e(c["dentro"] or "")}" '
                          f'style="left:{c["x"]}px;top:{c["y"]}px;width:{c["w"]}px;height:{c["h"]}px">'
                          f'<div class="tx"><div class="ct">{_e(c["texto"])}</div></div></div>')
        for t in self.textos:
            anchura = f"width:{t['ancho']}px;" if t["ancho"] else "white-space:nowrap;"
            idattr = f' id="{_e(t["id"])}"' if t["id"] else ""
            est = "font-style:italic;" if t["cursiva"] else ""
            partes.append(f'<div class="txt"{idattr} style="left:{t["x"]}px;top:{t["y"]}px;{anchura}'
                          f'font-size:{t["tam"]}px;color:{t["color"]};font-weight:{t["peso"]};text-align:{t["alinear"]};{est}">'
                          f'{_t(t["texto"])}</div>')
        partes.extend(etiquetas)
        partes.append(self._html_leyenda())
        partes.append('<pre id="qa" style="display:none"></pre>')
        cuerpo = "\n".join(partes)
        return PLANTILLA.replace("{{TITULO}}", _e(self.titulo)).replace("{{CUERPO}}", cuerpo) \
                        .replace("{{QA}}", QA_JS).replace("{{FUENTE}}", FUENTE)

    def _html_leyenda(self) -> str:
        items = []
        for tipo in self.leyenda_tipos:
            pal = PALETA[tipo]
            items.append(f'<span class="li"><span class="sw" style="background:{pal["fill"]};'
                         f'border:1.5px solid {pal["border"]}"></span>{_e(pal["nombre"])}</span>')
        items.append('<span class="li"><span class="sw" style="background:#fff;border:2px dashed #9AA0A6"></span>'
                     'Opcional o apagado</span>')
        items.append(f'<span class="li"><svg width="34" height="12"><path d="M1 6h26" stroke="{AZUL}" stroke-width="2.2"/>'
                     f'<path d="M24 1 L33 6 L24 11z" fill="{AZUL}"/></svg>Flujo</span>')
        for muestra, texto in self.leyenda_extra:
            if muestra == "punteada":
                items.append(f'<span class="li"><svg width="34" height="12"><path d="M1 6h26" stroke="{AZUL}" '
                             f'stroke-width="2.2" stroke-dasharray="6 4"/><path d="M24 1 L33 6 L24 11z" fill="{AZUL}"/></svg>'
                             f'{_e(texto)}</span>')
            elif muestra == "gris":
                items.append(f'<span class="li"><svg width="34" height="12"><path d="M1 6h32" stroke="{GRIS}" '
                             f'stroke-width="2.2" stroke-dasharray="6 4"/></svg>{_e(texto)}</span>')
            else:
                items.append(f'<span class="li">{_e(texto)}</span>')
        return f'<div class="leyenda" id="leyenda">{"".join(items)}</div>'


def _ruta(puntos, radio=10.0) -> str:
    """Trayectoria con esquinas redondeadas."""
    if len(puntos) == 2:
        (x0, y0), (x1, y1) = puntos
        return f"M{x0:.1f},{y0:.1f} L{x1:.1f},{y1:.1f}"
    d = [f"M{puntos[0][0]:.1f},{puntos[0][1]:.1f}"]
    for i in range(1, len(puntos) - 1):
        (xa, ya), (xb, yb), (xc, yc) = puntos[i - 1], puntos[i], puntos[i + 1]
        l1 = math.hypot(xb - xa, yb - ya)
        l2 = math.hypot(xc - xb, yc - yb)
        r = min(radio, l1 / 2, l2 / 2)
        if l1 == 0 or l2 == 0:
            d.append(f"L{xb:.1f},{yb:.1f}")
            continue
        p1 = (xb - (xb - xa) / l1 * r, yb - (yb - ya) / l1 * r)
        p2 = (xb + (xc - xb) / l2 * r, yb + (yc - yb) / l2 * r)
        d.append(f"L{p1[0]:.1f},{p1[1]:.1f} Q{xb:.1f},{yb:.1f} {p2[0]:.1f},{p2[1]:.1f}")
    d.append(f"L{puntos[-1][0]:.1f},{puntos[-1][1]:.1f}")
    return " ".join(d)


def _punto_en(puntos, frac):
    largos = [math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(puntos, puntos[1:])]
    total = sum(largos)
    objetivo = total * frac
    for (a, b), l in zip(zip(puntos, puntos[1:]), largos):
        if objetivo <= l and l > 0:
            k = objetivo / l
            return (a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k)
        objetivo -= l
    return puntos[-1]


PLANTILLA = """<!doctype html>
<html lang="es"><head><meta charset="utf-8"><title>{{TITULO}}</title>
<style>
html,body{margin:0;padding:0;background:#fff}
#lienzo{position:relative;width:1920px;height:1080px;overflow:hidden;background:#fff;font-family:{{FUENTE}};
  -webkit-font-smoothing:antialiased}
.tit{position:absolute;left:40px;top:22px;font-size:31px;font-weight:700;color:#202124;letter-spacing:-.2px}
.sub{position:absolute;left:40px;top:62px;font-size:17px;color:#5F6368;width:1700px;white-space:nowrap}
.num{position:absolute;right:40px;top:30px;font-size:15px;color:#5F6368}
.box{position:absolute;box-sizing:border-box;border-radius:6px}
.blab{position:absolute;left:10px;font-size:15px;font-weight:700;line-height:18px;padding:1px 5px;
  border-radius:3px;white-space:nowrap}
.blab.gc{font-size:18px;font-weight:700;left:12px;line-height:22px}
.bsub{font-weight:400}
.bcuerpo{position:absolute;left:15px;right:10px;top:29px;font-size:15px;line-height:19px;color:#3C4043}
svg.flechas{position:absolute;left:0;top:0;z-index:400;pointer-events:none}
.card{position:absolute;box-sizing:border-box;background:#fff;border-radius:4px;z-index:500;
  box-shadow:0 1px 2px rgba(60,64,67,.30),0 2px 6px 2px rgba(60,64,67,.15);
  display:flex;align-items:center;gap:11px;padding:6px 11px;overflow:hidden}
.card.dashed{border:2px dashed #9AA0A6;box-shadow:none;background:#fff}
.card .ics{display:flex;gap:3px;flex:none;align-items:center}
.card img{display:block}
.card .tx{min-width:0;flex:1}
.card .t{font-weight:700;font-size:17px;color:#202124;line-height:20px}
.card .p{font-size:15px;color:#4D5156;line-height:19px;margin-top:1px}
.card .n{font-size:14px;color:#5F6368;line-height:17px;margin-top:2px}
.chip{position:absolute;box-sizing:border-box;background:#fff;border:1.5px solid #BDC1C6;border-radius:16px;
  z-index:500;display:flex;align-items:center;justify-content:center;padding:0 8px;overflow:hidden}
.chip .ct{font-size:15px;font-weight:700;color:#3C4043;white-space:nowrap;text-align:center}
.chip.dest{border:2px solid #1A73E8;background:#E8F0FE}
.chip.dest .ct{color:#1859B8}
.chip.dashed{border:2px dashed #9AA0A6}
.txt{position:absolute;z-index:450;line-height:1.3}
.nw{white-space:nowrap}
.alab{position:absolute;z-index:700;font-size:14px;font-weight:700;line-height:17px;background:#fff;padding:1px 6px;
  border-radius:3px;white-space:nowrap;box-shadow:0 0 0 1px rgba(26,115,232,.18)}
.leyenda{position:absolute;left:40px;bottom:12px;display:flex;gap:20px;align-items:center;font-size:14px;color:#3C4043;
  white-space:nowrap;z-index:800}
.li{display:flex;align-items:center;gap:7px}
.sw{display:inline-block;width:24px;height:14px;border-radius:3px;box-sizing:border-box}
</style></head>
<body><div id="lienzo">
{{CUERPO}}
</div>
<script>{{QA}}</script>
</body></html>
"""

# Revisión automática dentro de la página. Escribe un JSON en <pre id="qa">.
QA_JS = r"""
(function(){
  const R=[];
  const L=document.getElementById('lienzo').getBoundingClientRect();
  function rr(el){const r=el.getBoundingClientRect();return {l:r.left-L.left,t:r.top-L.top,r:r.right-L.left,b:r.bottom-L.top};}
  function inter(a,b,m){m=m||0;return a.l<b.r-m&&b.l<a.r-m&&a.t<b.b-m&&b.t<a.b-m;}
  const cards=[...document.querySelectorAll('.card,.chip')];
  const rc={};cards.forEach(c=>rc[c.id]=rr(c));
  cards.forEach(c=>{
    const tx=c.querySelector('.tx');
    if(tx && tx.scrollHeight>c.clientHeight-4) R.push('ALTO '+c.id+' '+tx.scrollHeight+'>'+(c.clientHeight-4));
    if(tx) [...tx.children].forEach(e=>{if(e.scrollWidth>e.clientWidth+1) R.push('ANCHO '+c.id);});
    const t=c.querySelector('.t'); if(t){const lh=parseFloat(getComputedStyle(t).lineHeight); if(t.clientHeight>lh*1.5) R.push('info: titulo en 2 lineas '+c.id);}
    const r=rc[c.id]; if(r.l<0||r.t<0||r.r>1920||r.b>1080) R.push('FUERA '+c.id);
    const dn=c.dataset.dentro; if(dn){const p=document.getElementById(dn); if(p){const q=rr(p); if(r.l<q.l+2||r.r>q.r-2||r.t<q.t+2||r.b>q.b-2) R.push('SALE '+c.id+' de '+dn);}}
  });
  for(let i=0;i<cards.length;i++)for(let j=i+1;j<cards.length;j++){
    if(inter(rc[cards[i].id],rc[cards[j].id],0)) R.push('ENCIMA '+cards[i].id+' / '+cards[j].id);}
  // Cajas: dentro de su contenedor y etiquetas sin tapar tarjetas
  document.querySelectorAll('.box').forEach(b=>{
    const dn=b.dataset.dentro; const r=rr(b);
    if(dn){const p=document.getElementById(dn); if(p){const q=rr(p); if(r.l<q.l||r.r>q.r||r.t<q.t||r.b>q.b) R.push('SALE caja '+b.id+' de '+dn);}}
    if(r.r>1920||r.b>1080) R.push('FUERA caja '+b.id);
  });
  document.querySelectorAll('.bcuerpo').forEach(c=>{const r=rr(c), q=rr(c.parentElement);
    if(r.b>q.b-2) R.push('CUERPO LARGO '+c.parentElement.id);
    [...c.children].forEach(l=>{if(l.scrollWidth>l.clientWidth+1||l.clientHeight>25) R.push('CUERPO ANCHO '+c.parentElement.id);});});
  const blabs=[...document.querySelectorAll('.blab')];
  blabs.forEach(l=>{const r=rr(l); const caja=l.parentElement; const q=rr(caja);
    if(r.r>q.r-2) R.push('ETIQUETA LARGA '+l.id);
    cards.forEach(c=>{if(inter(r,rc[c.id],0)) R.push('ETIQUETA TAPA '+l.id+' / '+c.id);});
  });
  const alabs=[...document.querySelectorAll('.alab')];
  const ra=alabs.map(rr);
  alabs.forEach((l,i)=>{
    cards.forEach(c=>{if(inter(ra[i],rc[c.id],0)) R.push('ROTULO TAPA '+l.id+' / '+c.id);});
    blabs.forEach(b=>{if(inter(ra[i],rr(b),0)) R.push('ROTULO TAPA '+l.id+' / '+b.id);});
    for(let j=i+1;j<alabs.length;j++) if(inter(ra[i],ra[j],0)) R.push('ROTULOS ENCIMA '+l.id+' / '+alabs[j].id);
  });
  document.querySelectorAll('.txt[id]').forEach(t=>{const r=rr(t); cards.forEach(c=>{if(inter(r,rc[c.id],0)) R.push('TEXTO TAPA '+t.id+' / '+c.id);});});
  // Flechas: segmentos que cruzan tarjetas ajenas y cruces entre flechas
  const fl=[...document.querySelectorAll('path.fl')].map(p=>({id:p.id,g:p.dataset.grupo,
     pts:p.dataset.pts.split(';').map(s=>s.split(',').map(Number))}));
  function segRect(a,b,r){ // muestreo
    const n=Math.max(2,Math.ceil(Math.hypot(b[0]-a[0],b[1]-a[1])/3));
    for(let k=0;k<=n;k++){const x=a[0]+(b[0]-a[0])*k/n,y=a[1]+(b[1]-a[1])*k/n;
      if(x>r.l+3&&x<r.r-3&&y>r.t+3&&y<r.b-3) return true;} return false;}
  const rb=blabs.map(b=>({id:b.id,r:rr(b)}));
  const rtx=[...document.querySelectorAll('.txt[id]')].map(t=>({id:t.id,r:rr(t)}));
  fl.forEach(f=>{
    for(let k=0;k<f.pts.length-1;k++){
      cards.forEach(c=>{if(segRect(f.pts[k],f.pts[k+1],rc[c.id])) R.push('CRUZA '+f.id+' / '+c.id);});
      rb.forEach(b=>{if(segRect(f.pts[k],f.pts[k+1],b.r)) R.push('CRUZA ETIQUETA '+f.id+' / '+b.id);});
      rtx.forEach(t=>{if(segRect(f.pts[k],f.pts[k+1],t.r)) R.push('CRUZA TEXTO '+f.id+' / '+t.id);});
    }
  });
  function cruce(a,b,c,d){const den=(b[0]-a[0])*(d[1]-c[1])-(b[1]-a[1])*(d[0]-c[0]); if(Math.abs(den)<1e-9) return false;
    const t=((c[0]-a[0])*(d[1]-c[1])-(c[1]-a[1])*(d[0]-c[0]))/den, u=((c[0]-a[0])*(b[1]-a[1])-(c[1]-a[1])*(b[0]-a[0]))/den;
    return t>0.02&&t<0.98&&u>0.02&&u<0.98;}
  for(let i=0;i<fl.length;i++)for(let j=i+1;j<fl.length;j++){
    if(fl[i].g&&fl[i].g===fl[j].g) continue;
    let x=false; for(let a=0;a<fl[i].pts.length-1&&!x;a++)for(let b=0;b<fl[j].pts.length-1&&!x;b++)
      if(cruce(fl[i].pts[a],fl[i].pts[a+1],fl[j].pts[b],fl[j].pts[b+1])) x=true;
    if(x) R.push('CRUCE '+fl[i].id+' / '+fl[j].id);}
  const lg=rr(document.getElementById('leyenda')); if(lg.r>1880) R.push('LEYENDA LARGA');
  document.querySelectorAll('.box').forEach(b=>{if(b.dataset.tipo==='gcloud'||b.dataset.tipo==='proyecto'){const r=rr(b); if(inter(lg,r,0)) R.push('LEYENDA TAPA '+b.id);}});
  document.getElementById('qa').textContent=JSON.stringify(R);
})();
"""

# --------------------------------------------------------------------------------------------
# Chrome
# --------------------------------------------------------------------------------------------

def buscar_chrome() -> str:
    env = os.environ.get("CHROME_PATH")
    if env and Path(env).exists():
        return env
    candidatos = []
    for base in (os.environ.get("PROGRAMFILES"), os.environ.get("PROGRAMFILES(X86)"), os.environ.get("LOCALAPPDATA")):
        if base:
            candidatos.append(Path(base) / "Google/Chrome/Application/chrome.exe")
            candidatos.append(Path(base) / "Microsoft/Edge/Application/msedge.exe")
    candidatos += [Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
                   Path("/Applications/Chromium.app/Contents/MacOS/Chromium")]
    for c in candidatos:
        if c.exists():
            return str(c)
    for nombre in ("google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "chrome", "msedge"):
        w = shutil.which(nombre)
        if w:
            return w
    raise SystemExit("No encontré Chrome. Define CHROME_PATH con la ruta del ejecutable.")


class Chrome:
    def __init__(self):
        self.exe = buscar_chrome()
        self._tmp = tempfile.TemporaryDirectory(prefix="perfil-chrome-")

    def _base(self):
        return [self.exe, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
                "--no-default-browser-check", "--disable-extensions", f"--user-data-dir={self._tmp.name}"]

    def captura(self, html_path: Path, png: Path, ancho: int, alto: int, escala: float = 1, transparente=False):
        args = self._base() + [f"--window-size={ancho},{alto}", f"--force-device-scale-factor={escala}",
                               f"--screenshot={png}"]
        if transparente:
            args.append("--default-background-color=00000000")
        args.append(html_path.resolve().as_uri())
        r = subprocess.run(args, capture_output=True, text=True, timeout=120)
        if r.returncode != 0 or not png.exists():
            raise RuntimeError(f"Chrome falló con {html_path}: {r.stderr[-800:]}")

    def dom(self, html_path: Path) -> str:
        args = self._base() + ["--window-size=1920,1080", "--dump-dom", html_path.resolve().as_uri()]
        r = subprocess.run(args, capture_output=True, text=True, timeout=120, encoding="utf-8")
        return r.stdout

    def cerrar(self):
        try:
            self._tmp.cleanup()
        except OSError:
            pass


def leer_qa(dom: str) -> list[str]:
    m = re.search(r'<pre id="qa"[^>]*>(.*?)</pre>', dom, re.S)
    if not m:
        return ["SIN RESULTADO DE QA"]
    try:
        return json.loads(html.unescape(m.group(1)) or "[]")
    except json.JSONDecodeError:
        return ["QA ILEGIBLE: " + m.group(1)[:200]]


PLANTILLA_ICONO = """<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;padding:0;background:transparent;overflow:hidden}
img{display:block;width:256px;height:256px}
</style></head><body><img src="{{URI}}" alt=""></body></html>"""
