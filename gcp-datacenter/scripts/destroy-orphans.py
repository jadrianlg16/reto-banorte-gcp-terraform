#!/usr/bin/env python3
"""Huérfanos en la carpeta de un entorno después de destruirlo (destroy.yml).

Uso:
    python3 scripts/destroy-orphans.py --folder folders/<N> --assets ASSETS.json
        [--summary RESUMEN.md] [--report-only]

    --folder   carpeta del entorno destruido (salida folder_ids de 1-org).
    ASSETS     salida de
               gcloud asset search-all-resources --scope=folders/<N> --format=json
               (lista de objetos con name, assetType, project, state...; también {"results": [...]}).
    --summary  agrega un resumen en Markdown (para $GITHUB_STEP_SUMMARY).
    --report-only  sale con 0 aunque haya huérfanos.

Después de destruir 5-workloads, 4-projects y 3-networks de un entorno, en su carpeta no debería
quedar nada vivo. Es ESPERADO (se lista, no falla):
  1. la carpeta misma (la crea y la conserva 1-org);
  2. un proyecto en estado DELETE_REQUESTED o DELETE_IN_PROGRESS: GCP lo borra del todo a los
     30 días y su ID no se vuelve a usar;
  3. cualquier recurso de un proyecto en ese estado (campo `project`, o el número o ID del
     proyecto en el nombre): se va con el proyecto;
  4. un recurso en estado DELETED, DELETE_REQUESTED o DELETE_IN_PROGRESS (el índice todavía lo
     muestra);
  5. una versión de llave de Cloud KMS DESTROYED o DESTROY_SCHEDULED (sin material o en camino
     de destruirse). Las llaves de los entornos viven en el proyecto `security` de common, fuera
     de esta carpeta: aquí solo aparecerían si alguien las creó a mano.
Todo lo demás es HUÉRFANO: se lista y el script sale con 1. Un proyecto ACTIVE (por ejemplo, con
deletion_policy ABANDON), un bucket o una red que sobrevivieron son huérfanos.

Sale con 2 si el listado no es de Cloud Asset (objeto sin `results`, elementos sin `name`). Un
listado vacío es el resultado esperado (carpeta vacía): un error de permisos hace fallar a gcloud
antes, no da una lista vacía.

HYPOTHESIS (sin carpeta real): que Cloud Asset muestre los proyectos en borrado con esos estados
(la referencia de searchAllResources los lista como estados posibles de un proyecto) y el nombre
`//cloudresourcemanager.googleapis.com/projects/<número>`. VERIFICAR-EN-APPLY en el primer
destroy de dev (pendiente 85).

Solo biblioteca estándar; Python 3.8 o posterior.
"""

import argparse
import json
import re
import sys

PROJECT_TYPE = "cloudresourcemanager.googleapis.com/Project"
FOLDER_TYPE = "cloudresourcemanager.googleapis.com/Folder"
KEY_VERSION_TYPE = "cloudkms.googleapis.com/CryptoKeyVersion"
GONE_STATES = {"DELETED", "DELETE_REQUESTED", "DELETE_IN_PROGRESS"}
KEY_VERSION_GONE = {"DESTROYED", "DESTROY_SCHEDULED"}


def read_assets(path):
    """(lista, None) o (None, motivo)."""
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError) as exc:
        return None, "no se pudo leer el listado: %s" % exc
    if isinstance(data, dict):
        key = next((k for k in ("results", "assets") if k in data), None)
        if key is None:
            return None, "objeto JSON sin 'results' ni 'assets': no es un listado de Cloud Asset"
        data = data[key]
    if not isinstance(data, list):
        return None, "se esperaba una lista de recursos y llegó %s" % type(data).__name__
    if not all(isinstance(a, dict) and a.get("name") for a in data):
        return None, "hay elementos sin 'name': no es un listado de Cloud Asset"
    return data, None


def folder_number(value):
    m = re.fullmatch(r"(?:folders/)?([0-9]+)", str(value or "").strip())
    return m.group(1) if m else None


def state_of(asset):
    return str(asset.get("state") or "").upper()


def deleted_projects(assets):
    """Identificadores (número e ID) de los proyectos en borrado del listado."""
    ids = set()
    for a in assets:
        if a.get("assetType") == PROJECT_TYPE and state_of(a) in GONE_STATES:
            m = re.search(r"projects/([^/]+)$", a["name"])
            if m:
                ids.add(m.group(1))
            project_id = (a.get("additionalAttributes") or {}).get("projectId")
            if project_id:
                ids.add(str(project_id))
    return ids


def in_deleted_project(asset, gone):
    project = re.fullmatch(r"projects/([^/]+)", str(asset.get("project") or ""))
    if project and project.group(1) in gone:
        return True
    return any(("/projects/%s/" % p) in asset["name"] for p in gone)


def classify(assets, folder):
    number = folder_number(folder)
    gone = deleted_projects(assets)
    expected, orphans = [], []
    for a in assets:
        atype = a.get("assetType", "")
        entry = {"assetType": atype, "name": a["name"], "state": state_of(a)}
        if atype == FOLDER_TYPE and number and a["name"].endswith("/folders/%s" % number):
            entry["reason"] = "la carpeta del entorno (la administra 1-org)"
        elif atype == PROJECT_TYPE and entry["state"] in GONE_STATES:
            entry["reason"] = "proyecto en borrado (GCP lo elimina a los 30 días)"
        elif in_deleted_project(a, gone):
            entry["reason"] = "dentro de un proyecto en borrado"
        elif entry["state"] in GONE_STATES:
            entry["reason"] = "borrado (el índice todavía lo muestra)"
        elif atype == KEY_VERSION_TYPE and entry["state"] in KEY_VERSION_GONE:
            entry["reason"] = "versión de llave de KMS destruida o programada para destruir"
        else:
            orphans.append(entry)
            continue
        expected.append(entry)
    return expected, orphans


def main(argv=None):
    parser = argparse.ArgumentParser(description="Huérfanos en la carpeta de un entorno destruido.")
    parser.add_argument("--folder", required=True)
    parser.add_argument("--assets", required=True)
    parser.add_argument("--summary")
    parser.add_argument("--report-only", action="store_true")
    args = parser.parse_args(argv)
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")

    if folder_number(args.folder) is None:
        sys.stderr.write("ERROR: --folder debe ser folders/<número> o <número>: %s\n" % args.folder)
        return 2
    assets, error = read_assets(args.assets)
    if error:
        sys.stderr.write("ERROR: %s: %s\n" % (args.assets, error))
        return 2

    expected, orphans = classify(assets, args.folder)
    print("recursos en la carpeta %s: %d" % (args.folder, len(assets)))
    print("  esperados: %d" % len(expected))
    print("  HUÉRFANOS: %d" % len(orphans))
    for e in sorted(expected, key=lambda e: (e["assetType"], e["name"])):
        print("ESPERADO %s %s (%s)" % (e["assetType"], e["name"], e["reason"]))
    for e in sorted(orphans, key=lambda e: (e["assetType"], e["name"])):
        print("HUERFANO %s %s%s" % (e["assetType"], e["name"], " [%s]" % e["state"] if e["state"] else ""))

    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as out:
            out.write("- Recursos en la carpeta `%s`: %d (esperados %d, **huérfanos %d**)\n\n"
                      % (args.folder, len(assets), len(expected), len(orphans)))
            if orphans:
                out.write("| Huérfano | Nombre | Estado |\n|---|---|---|\n")
                for e in sorted(orphans, key=lambda e: (e["assetType"], e["name"])):
                    out.write("| `%s` | `%s` | %s |\n" % (e["assetType"], e["name"], e["state"] or "—"))
                out.write("\n")
            if expected:
                out.write("| Esperado | Nombre | Motivo |\n|---|---|---|\n")
                for e in sorted(expected, key=lambda e: (e["assetType"], e["name"])):
                    out.write("| `%s` | `%s` | %s |\n" % (e["assetType"], e["name"], e["reason"]))
                out.write("\n")

    if orphans and not args.report_only:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
