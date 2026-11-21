#!/usr/bin/env python3
"""Recursos de una carpeta de GCP que no están en ningún estado de Terraform.

Objetivo de la especificación: "cero recursos manuales", verificado con Cloud Asset Inventory.

Uso:
    python3 scripts/unmanaged-resources.py --assets ASSETS.json --state S.tfstate [--state ...]
        [--allowlist scripts/unmanaged-allowlist.txt] [--summary RESUMEN.md] [--report-only]

    ASSETS.json  salida de
                 gcloud asset search-all-resources --scope=folders/<N> --format=json
                 (lista de objetos con name, assetType, displayName, state...). También sirve
                 `gcloud asset list --format=json` (name y assetType).
    --state      estado de Terraform: el archivo crudo del backend (`terraform state pull` o
                 `gcloud storage cat gs://<bucket>/<prefijo>/default.tfstate`, versión 4) o
                 `terraform show -json`. Se repite una vez por raíz; conviene pasar todas.
    --allowlist  reglas de recursos que crea Google o un servicio administrado, no una persona
                 (por defecto scripts/unmanaged-allowlist.txt).
    --summary    escribe además un resumen en Markdown (para $GITHUB_STEP_SUMMARY).
    --report-only  sale con 0 aunque haya recursos no administrados.

Cómo decide que un recurso está administrado:
1. Nombre exacto. De cada instancia de recurso del estado se toman `id` y `self_link`, más
   formas construidas para tipos cuyo `id` no es el nombre de Cloud Asset
   (proyecto por número, cuenta de servicio por `unique_id`, API habilitada). Los nombres se
   normalizan: sin `//servicio.googleapis.com/`, sin `https://host/version/`, y cada
   `projects/<id>` se pasa a `projects/<número>` con los proyectos del estado (Cloud Asset usa
   el número en algunos servicios y el ID en otros).
2. Hijo de un recurso administrado: el nombre empieza con el de un recurso administrado de al
   menos cuatro segmentos más "/" (versiones de llaves KMS, revisiones de Cloud Run,
   versiones de secretos, que se cargan a mano por diseño, ADR 0015). Los proyectos, carpetas
   y ubicaciones no cuentan como padres, y los node pools de GKE no se aceptan por esta regla.
3. Instancia o disco de un grupo administrado (MIG) del estado: nombre
   `<base_instance_name>-xxxx` en el mismo proyecto.
4. Regla de la lista de permitidos: una expresión regular sobre
   "<assetType> <nombre normalizado> <displayName>".

Lo que queda es "no administrado": se lista y el script sale con 1.

Sale con 2 (también con --report-only) si el listado no sirve para concluir nada: vacío, mal
formado (`{}`, un objeto sin `results`, elementos sin `name`) o sin ninguno de los proyectos
de los estados (otra carpeta, listado incompleto o estados de otro entorno). Así un "0 no
administrados" solo sale de un listado que de verdad cubre el entorno.

VERIFICAR-EN-APPLY: el formato de `name` de Cloud Asset para cada tipo (número o ID del
proyecto, ID único de la cuenta de servicio) y que la lista de permitidos cubra los recursos que
crean GKE, los MIG y los servicios administrados. Solo se puede comprobar con una carpeta real.

Solo biblioteca estándar; Python 3.8 o posterior.
"""

import argparse
import json
import os
import re
import sys

GONE_STATES = {"DELETED", "DELETE_REQUESTED", "DELETE_IN_PROGRESS"}
# Hijos que una persona puede crear a mano y Terraform administra como recurso propio: no se
# aceptan solo por estar bajo un recurso administrado.
CHILD_RULE_EXCLUDED = {"container.googleapis.com/NodePool"}
PROJECT_ASSET_TYPE = "cloudresourcemanager.googleapis.com/Project"
ROOT_PREFIX = re.compile(r"(?:^|/)((?:projects|folders|organizations)/.*)$")


def normalize(name):
    """Nombre relativo comparable de un recurso de GCP."""
    if not isinstance(name, str) or not name:
        return None
    n = name.strip()
    n = re.sub(r"^//[^/]+/", "", n)  # //compute.googleapis.com/...
    n = re.sub(r"^https?://[^/]+/", "", n)  # https://www.googleapis.com/compute/v1/...
    m = ROOT_PREFIX.search(n)
    if m:
        n = m.group(1)
    return n.strip("/")


def canonical(name, aliases):
    """Reemplaza projects/<id> por projects/<número> cuando se conoce."""
    if name is None:
        return None

    def repl(m):
        return "projects/" + aliases.get(m.group(1), m.group(1))

    return re.sub(r"^projects/([^/]+)", repl, name)


# --- Lectura de estados ------------------------------------------------------------------


def state_instances(state):
    """(type, attributes) de cada instancia administrada, en cualquiera de los dos formatos."""
    if isinstance(state.get("resources"), list):  # estado crudo, versión 4
        for res in state["resources"]:
            if res.get("mode") != "managed":
                continue
            for inst in res.get("instances", []):
                attrs = inst.get("attributes")
                if isinstance(attrs, dict):
                    yield res.get("type", ""), attrs
        return
    stack = [state.get("values", {}).get("root_module", {})]
    while stack:  # terraform show -json
        module = stack.pop()
        for res in module.get("resources", []):
            if res.get("mode") == "managed" and isinstance(res.get("values"), dict):
                yield res.get("type", ""), res["values"]
        stack.extend(module.get("child_modules", []))


def build_managed(states):
    """Nombres administrados (canónicos), padres posibles y patrones de los MIG."""
    instances = []
    for state in states:
        instances.extend(state_instances(state))

    aliases = {}
    for rtype, attrs in instances:
        if rtype == "google_project" and attrs.get("project_id") and attrs.get("number"):
            aliases[str(attrs["project_id"])] = str(attrs["number"])

    raw = set()
    mig_patterns = []
    for rtype, attrs in instances:
        for key in ("id", "self_link"):
            raw.add(normalize(attrs.get(key)))
        project = attrs.get("project")
        if rtype == "google_project":
            raw.add("projects/%s" % attrs.get("project_id"))
            raw.add("projects/%s" % attrs.get("number"))
        elif rtype == "google_service_account" and project:
            for ident in (attrs.get("unique_id"), attrs.get("email")):
                if ident:
                    raw.add("projects/%s/serviceAccounts/%s" % (project, ident))
        elif rtype == "google_project_service" and project and attrs.get("service"):
            raw.add("projects/%s/services/%s" % (project, attrs["service"]))
        elif rtype in ("google_compute_region_instance_group_manager", "google_compute_instance_group_manager"):
            base = attrs.get("base_instance_name")
            if base and project:
                mig_patterns.append(re.compile(
                    r"^%s/zones/[^/]+/(instances|disks)/%s-[a-z0-9]{4}$"
                    % (re.escape(canonical("projects/" + project, aliases)), re.escape(base))
                ))
    raw.discard(None)
    raw.discard("projects/None")
    managed = {canonical(n, aliases) for n in raw}
    parents = {n for n in managed if len(n.split("/")) >= 4 and not re.search(r"/locations/[^/]+$", n)}
    return managed, parents, mig_patterns, aliases


# --- Lista de permitidos -------------------------------------------------------------------


def load_allowlist(path):
    rules = []
    with open(path, encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            text = line.strip()
            if not text or text.startswith("#"):
                continue
            pattern, _, reason = text.partition(" # ")
            try:
                rules.append((re.compile(pattern.strip()), reason.strip() or "sin motivo", number))
            except re.error as exc:
                raise SystemExit("%s:%d: expresión inválida: %s" % (path, number, exc))
    return rules


# --- Clasificación -------------------------------------------------------------------------


def classify(assets, managed, parents, mig_patterns, aliases, rules):
    result = {"managed": [], "child": [], "mig": [], "allowed": [], "unmanaged": [], "gone": []}
    for asset in assets:
        name = canonical(normalize(asset.get("name")), aliases)
        atype = asset.get("assetType", "")
        entry = {"assetType": atype, "name": name or "", "displayName": asset.get("displayName", "")}
        if str(asset.get("state", "")).upper() in GONE_STATES:
            result["gone"].append(entry)
        elif name in managed:
            result["managed"].append(entry)
        elif atype not in CHILD_RULE_EXCLUDED and any(name.startswith(p + "/") for p in parents):
            result["child"].append(entry)
        elif any(p.match(name) for p in mig_patterns):
            result["mig"].append(entry)
        else:
            subject = "%s %s %s" % (atype, name, entry["displayName"])
            rule = next((r for r in rules if r[0].search(subject)), None)
            if rule:
                entry["reason"] = "%s (línea %d)" % (rule[1], rule[2])
                result["allowed"].append(entry)
            else:
                result["unmanaged"].append(entry)
    return result


def load_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def read_assets(path):
    """(lista de recursos, None) o (None, motivo) si el listado está vacío o mal formado."""
    try:
        data = load_json(path)
    except (OSError, ValueError) as exc:
        return None, "no se pudo leer el listado: %s" % exc
    if isinstance(data, dict):  # {"results": [...]} de la API REST
        key = next((k for k in ("results", "assets") if k in data), None)
        if key is None:
            return None, "objeto JSON sin 'results' ni 'assets': no es un listado de Cloud Asset"
        data = data[key]
    if not isinstance(data, list):
        return None, "se esperaba una lista de recursos y llegó %s" % type(data).__name__
    if not data:
        return None, "listado vacío: una carpeta de entorno siempre tiene al menos sus proyectos"
    if not all(isinstance(a, dict) and a.get("name") for a in data):
        return None, "hay elementos sin 'name': no es un listado de Cloud Asset"
    return data, None


def main(argv=None):
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description="Recursos de Cloud Asset Inventory que no están en los estados de Terraform.")
    parser.add_argument("--assets", required=True)
    parser.add_argument("--state", action="append", default=[], required=True)
    parser.add_argument("--allowlist", default=os.path.join(here, "unmanaged-allowlist.txt"))
    parser.add_argument("--summary")
    parser.add_argument("--report-only", action="store_true")
    args = parser.parse_args(argv)

    assets, error = read_assets(args.assets)
    if error:
        sys.stderr.write("ERROR: %s: %s\n" % (args.assets, error))
        return 2
    states = [load_json(p) for p in args.state]
    managed, parents, mig_patterns, aliases = build_managed(states)
    result = classify(assets, managed, parents, mig_patterns, aliases, load_allowlist(args.allowlist))

    # Un listado de otra carpeta, truncado o de una identidad sin permisos no trae ninguno de
    # los proyectos de los estados: sin esta comprobación daría "0 no administrados".
    projects = [e for e in result["managed"] if e["assetType"] == PROJECT_ASSET_TYPE]
    if not projects:
        sys.stderr.write(
            "ERROR: %s: ningún proyecto de los estados aparece en el listado (%d recursos); "
            "¿carpeta equivocada, listado incompleto o estados de otro entorno?\n"
            % (args.assets, len(assets)))
        return 2

    counts = {k: len(v) for k, v in result.items()}
    print("recursos en Cloud Asset: %d" % len(assets))
    print("  administrados por Terraform: %(managed)d" % counts)
    print("  hijos de un recurso administrado: %(child)d" % counts)
    print("  VM o discos de un MIG administrado: %(mig)d" % counts)
    print("  permitidos por regla: %(allowed)d" % counts)
    print("  eliminados (se ignoran): %(gone)d" % counts)
    print("  NO ADMINISTRADOS: %(unmanaged)d" % counts)
    for e in sorted(result["unmanaged"], key=lambda e: (e["assetType"], e["name"])):
        print("NO ADMINISTRADO %s %s" % (e["assetType"], e["name"]))

    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as out:
            out.write("| Clase | Recursos |\n|---|---|\n")
            for key, label in (("managed", "Administrados"), ("child", "Hijos de administrados"),
                               ("mig", "VM o discos de MIG"), ("allowed", "Permitidos por regla"),
                               ("unmanaged", "**No administrados**")):
                out.write("| %s | %d |\n" % (label, counts[key]))
            if result["unmanaged"]:
                out.write("\n| Tipo | Nombre |\n|---|---|\n")
                for e in sorted(result["unmanaged"], key=lambda e: (e["assetType"], e["name"])):
                    out.write("| `%s` | `%s` |\n" % (e["assetType"], e["name"]))
            out.write("\n")

    if result["unmanaged"] and not args.report_only:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
