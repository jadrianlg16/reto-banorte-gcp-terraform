#!/usr/bin/env python3
"""Entornos apagados con la variable de repositorio GCP_DISABLED_ENVS (apply.yml y drift.yml).

Uso:
  GCP_DISABLED_ENVS="dev,qa" python3 scripts/disabled-envs.py outputs [archivo]
      Escribe "dev=true|false" y "qa=true|false" (true: el entorno se despliega) en el archivo
      (se agrega al final; en los flujos, $GITHUB_OUTPUT) o en la salida estándar.
  GCP_DISABLED_ENVS="dev" python3 scripts/disabled-envs.py filter [archivo] < raices.txt
      Lee la línea "roots=<json>" de scripts/affected-roots.sh, quita las raíces de los entornos
      apagados y escribe "roots=<json>" en el archivo (se agrega al final) o en la salida estándar.

GCP_DISABLED_ENVS: nombres separados por comas o espacios, sin importar mayúsculas; vacía o sin
definir, no se apaga nada. Solo se pueden apagar dev y qa (los entornos que destroy.yml puede
destruir): con prod, common u otro nombre sale con 2 y el flujo falla. prod no se apaga con esta
variable; para no aplicar nada, GCP_ENABLED distinto de "true".

Mensajes: con [archivo], en la salida estándar como comandos de GitHub Actions (::notice:: y
::error::); sin archivo, en la salida de errores.

Ver docs/pipeline.md. Solo biblioteca estándar; Python 3.8 o posterior.
"""

import json
import os
import re
import sys

SWITCHABLE = ("dev", "qa")
VARIABLE = "GCP_DISABLED_ENVS"


class UsageError(Exception):
    pass


def parse(value):
    """Conjunto de entornos apagados; UsageError si el valor trae prod u otro nombre."""
    names = [n.lower() for n in re.split(r"[\s,]+", value or "") if n]
    if "prod" in names:
        raise UsageError("%s trae prod: prod no se puede apagar con esta variable. Quitarlo de %s; "
                         "para no aplicar nada, GCP_ENABLED distinto de \"true\" (docs/pipeline.md §2)."
                         % (VARIABLE, VARIABLE))
    unknown = sorted(set(n for n in names if n not in SWITCHABLE))
    if unknown:
        raise UsageError("%s trae nombres que no se pueden apagar: %s. Solo dev y qa, separados por "
                         "comas (docs/pipeline.md §2)." % (VARIABLE, ", ".join(unknown)))
    return set(names)


def outputs(disabled):
    return ["%s=%s" % (env, "false" if env in disabled else "true") for env in SWITCHABLE]


def filter_roots(text, disabled):
    """(línea roots=<json> sin los entornos apagados, raíces quitadas)."""
    lines = [l for l in text.splitlines() if l.startswith("roots=")]
    if len(lines) != 1:
        raise UsageError("la entrada no trae una sola línea roots=<json> (scripts/affected-roots.sh)")
    try:
        roots = json.loads(lines[0][len("roots="):])
    except ValueError:
        raise UsageError("la línea roots= no es JSON")
    if not isinstance(roots, list) or not all(isinstance(r, dict) and "environment" in r for r in roots):
        raise UsageError("la línea roots= no es una lista de objetos con environment")
    kept = [r for r in roots if r["environment"] not in disabled]
    dropped = [r.get("root", "?") for r in roots if r["environment"] in disabled]
    return "roots=" + json.dumps(kept, separators=(",", ":"), ensure_ascii=False), dropped


def main(argv):
    for stream in (sys.stdout, sys.stderr):  # texto en español y "\n" también en Windows
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", newline="\n")
    if not argv or argv[0] not in ("outputs", "filter") or len(argv) > 2:
        sys.stderr.write("Uso: GCP_DISABLED_ENVS=... python3 scripts/disabled-envs.py outputs|filter [archivo]\n")
        return 2
    mode, target = argv[0], (argv[1] if len(argv) == 2 else None)

    def say(kind, text):
        if target:
            sys.stdout.write("::%s::%s\n" % (kind, text))
        else:
            sys.stderr.write("%s%s\n" % ("ERROR: " if kind == "error" else "", text))

    try:
        disabled = parse(os.environ.get(VARIABLE, ""))
        if mode == "outputs":
            lines = outputs(disabled)
            if disabled:
                say("notice", "Entornos apagados por %s: %s; sus raíces no se aplican."
                    % (VARIABLE, ", ".join(sorted(disabled))))
        else:
            line, dropped = filter_roots(sys.stdin.read(), disabled)
            lines = [line]
            if dropped:
                say("notice", "Entornos apagados por %s: %s; se omiten %s."
                    % (VARIABLE, ", ".join(sorted(disabled)), ", ".join(dropped)))
    except UsageError as err:
        say("error", str(err))
        return 2

    if target:
        with open(target, "a", encoding="utf-8", newline="\n") as out:
            out.write("\n".join(lines) + "\n")
    else:
        sys.stdout.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
