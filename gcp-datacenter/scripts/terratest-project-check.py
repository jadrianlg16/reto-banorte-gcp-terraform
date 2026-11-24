#!/usr/bin/env python3
"""Comprueba que el proyecto de Terratest no sea el de la landing zone (terratest.yml).

Uso: TERRATEST_PROJECT_ID=... TFVARS_JSON='{"common": {"project_id": "..."}}' \\
       python3 scripts/terratest-project-check.py [archivo]

Compara TERRATEST_PROJECT_ID con GCP_TFVARS_JSON.common.project_id (el proyecto único de la
landing zone, ADR 0029 §1) sin imprimir ninguno de los dos:
  - iguales: sale con 1. Las pruebas crean y destruyen recursos con nombres de prueba en su
    proyecto: en el de la landing zone, drift.yml los vería como no administrados y un error de
    limpieza dejaría restos junto a los entornos reales;
  - distintos, o sin uno de los dos (GCP_TFVARS_JSON vacío, que no es JSON o sin
    common.project_id; TERRATEST_PROJECT_ID vacío): sale con 0. Si no puede comparar, lo avisa.
Con [archivo] (en el flujo, $GITHUB_ENV) agrega TERRATEST_LANDING_ZONE_PROJECT_ID=<proyecto de
la landing zone> para que tests/helpers (RequireProjectEnv) repita la comprobación en cada
prueba, y los mensajes van a la salida estándar como comandos de GitHub Actions (::error:: y
::notice::). Solo se escribe un ID con la forma de un ID de proyecto de GCP.

Ver tests/README.md. Solo biblioteca estándar; Python 3.8 o posterior.
"""

import json
import os
import re
import sys

PROJECT_ID = re.compile(r"[a-z][a-z0-9-]{4,28}[a-z0-9]")
EXPORT = "TERRATEST_LANDING_ZONE_PROJECT_ID"


def landing_zone_project(raw):
    """common.project_id de GCP_TFVARS_JSON, o None si no se puede leer."""
    try:
        data = json.loads(raw or "")
    except ValueError:
        return None
    common = data.get("common") if isinstance(data, dict) else None
    project = common.get("project_id") if isinstance(common, dict) else None
    if not isinstance(project, str) or not project.strip():
        return None
    return project.strip().lower()


def main(argv):
    for stream in (sys.stdout, sys.stderr):  # texto en español y "\n" también en Windows
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", newline="\n")
    if len(argv) > 1:
        sys.stderr.write("Uso: TERRATEST_PROJECT_ID=... TFVARS_JSON=... python3 scripts/terratest-project-check.py [archivo]\n")
        return 2
    target = argv[0] if argv else None

    def say(kind, text):
        if target:
            sys.stdout.write("::%s::%s\n" % (kind, text))
        else:
            sys.stderr.write("%s%s\n" % ("ERROR: " if kind == "error" else "", text))

    landing = landing_zone_project(os.environ.get("TFVARS_JSON", ""))
    tests = os.environ.get("TERRATEST_PROJECT_ID", "").strip().lower()
    if landing is None:
        say("notice", "GCP_TFVARS_JSON no trae common.project_id: no se puede comprobar que "
                      "TERRATEST_PROJECT_ID sea otro proyecto que el de la landing zone.")
        return 0
    if tests and tests == landing:
        say("error", "TERRATEST_PROJECT_ID es el proyecto de la landing zone "
                     "(GCP_TFVARS_JSON.common.project_id). Las pruebas crean y destruyen recursos "
                     "ahí y drift.yml los vería como no administrados: usar un proyecto aparte "
                     "(tests/README.md). No se corre ninguna prueba.")
        return 1
    if target and PROJECT_ID.fullmatch(landing):
        with open(target, "a", encoding="utf-8", newline="\n") as out:
            out.write("%s=%s\n" % (EXPORT, landing))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
