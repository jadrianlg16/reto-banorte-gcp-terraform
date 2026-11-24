#!/usr/bin/env python3
"""Arma las variables de una raíz para pr.yml, drift.yml y _terraform-root.yml.

Uso: TFVARS_JSON='{"common": {"project_id": "..."}, "stages/1-base": {...}}' \\
       python3 scripts/root-tfvars.py <raíz>

    <raíz>  carpeta de la raíz, relativa a gcp-datacenter/ (stages/...) o absoluta. La llave de
            GCP_TFVARS_JSON es la ruta tal como llega.

1. Copia terraform.tfvars.example a terraform.tfvars, si existe.
2. Escribe zz-ci.auto.tfvars.json con "common" + la llave de la raíz (los *.auto.tfvars.json se
   cargan después de terraform.tfvars y lo sobrescriben).

Sale con 2, sin escribir nada, si TFVARS_JSON no es un objeto JSON (vacío vale como {}), si la
raíz no existe, o si la raíz declara la variable project_id y GCP_TFVARS_JSON no la trae (ni en
"common" ni en la llave de la raíz). El proyecto único entra por
GCP_TFVARS_JSON.common.project_id (ADR 0029 §1); sin él, el plan tomaría el marcador de
terraform.tfvars.example. Ver docs/pipeline.md §2. Solo biblioteca estándar; Python 3.8 o
posterior.
"""

import glob
import json
import os
import re
import shutil
import sys

PROJECT_VAR = re.compile(r'^\s*variable\s+"project_id"', re.M)


def declares_project_id(root):
    for path in glob.glob(os.path.join(root, "*.tf")):
        with open(path, encoding="utf-8") as handle:
            if PROJECT_VAR.search(handle.read()):
                return True
    return False


def main(argv):
    for stream in (sys.stdout, sys.stderr):  # texto en español también en la consola de Windows
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    if len(argv) != 1 or not argv[0]:
        sys.stderr.write("Uso: TFVARS_JSON='{...}' python3 scripts/root-tfvars.py <raíz>\n")
        return 2
    root = argv[0]
    if not os.path.isdir(root):
        sys.stderr.write("ERROR: la raíz %s no existe\n" % root)
        return 2
    try:
        data = json.loads(os.environ.get("TFVARS_JSON") or "{}")
    except ValueError:
        data = None
    if not isinstance(data, dict):
        sys.stderr.write("ERROR: GCP_TFVARS_JSON no es un objeto JSON\n")
        return 2
    variables = {}
    for key in ("common", root):
        part = data.get(key) or {}
        if not isinstance(part, dict):
            sys.stderr.write("ERROR: GCP_TFVARS_JSON[%r] no es un objeto JSON\n" % key)
            return 2
        variables.update(part)

    project = variables.get("project_id")
    if declares_project_id(root) and not (isinstance(project, str) and project.strip()):
        sys.stderr.write("ERROR: %s declara project_id y GCP_TFVARS_JSON no lo trae: agregar \"project_id\" "
                         "(salida project_id de 0-bootstrap) en \"common\" (ADR 0029 §1, docs/pipeline.md §2)\n" % root)
        return 2

    example = os.path.join(root, "terraform.tfvars.example")
    if os.path.isfile(example):
        shutil.copyfile(example, os.path.join(root, "terraform.tfvars"))
    with open(os.path.join(root, "zz-ci.auto.tfvars.json"), "w", encoding="utf-8", newline="\n") as out:
        json.dump(variables, out, ensure_ascii=False, indent=2)
        out.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
