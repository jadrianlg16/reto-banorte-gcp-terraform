#!/usr/bin/env python3
"""Arma las variables de una raíz para pr.yml, drift.yml y _terraform-root.yml.

Uso: TFVARS_JSON='{"common": {"project_id": "..."}, "stages/1-base": {...}}' \\
       python3 scripts/root-tfvars.py <raíz>

    <raíz>  carpeta de la raíz, relativa a gcp-datacenter/ (stages/...) o absoluta. La llave de
            GCP_TFVARS_JSON es la ruta tal como llega.

1. Copia terraform.tfvars.example a terraform.tfvars, si existe.
2. Escribe zz-ci.auto.tfvars.json con "common" + la llave de la raíz (los *.auto.tfvars.json se
   cargan después de terraform.tfvars y lo sobrescriben; una variable que está en el JSON
   reemplaza entera a la del ejemplo).

Sale con 2, sin escribir nada:
  - si TFVARS_JSON no es un objeto JSON (vacío vale como {}) o la raíz no existe;
  - si la raíz declara la variable project_id y GCP_TFVARS_JSON no la trae (ni en "common" ni en
    la llave de la raíz). El proyecto único entra por GCP_TFVARS_JSON.common.project_id (ADR 0029
    §1); sin él, el plan tomaría el marcador de terraform.tfvars.example;
  - si algún valor RESUELTO de una variable que la raíz declara lleva un marcador de los
    ejemplos (MARKERS): el del JSON si la variable está en "common" o en la llave de la raíz; si
    no, el de terraform.tfvars.example (sin comentarios). Marcadores: dominios example.com,
    example.net y example.org; nombres example-... (el proyecto example-lz-000000,
    example-project-id, example-landing-zone, example-org/example-repo, example-images,
    example-team, example-cc); REEMPLAZAR; textos entre < > como <proyecto>; e IDs de solo
    ceros (000000000, 000000-000000-000000). Así no llegan al plan, por ejemplo, los correos de
    las alertas CIS y de los contactos esenciales, los grupos, los dominios o la imagen de Cloud
    Run de los ejemplos. El mensaje nombra la variable, de dónde vino y el marcador, nunca el
    valor. Las variables que la raíz no declara no se revisan (Terraform solo avisa y no las usa).

Ver docs/pipeline.md §2. Solo biblioteca estándar; Python 3.8 o posterior.
"""

import glob
import json
import os
import re
import shutil
import sys

VARIABLE_BLOCK = re.compile(r'^\s*variable\s+"([^"]+)"', re.M)

# Marcadores de los ejemplos (terraform.tfvars.example de stages/ y tests/e2e/config.example.json):
# (expresión, descripción). Se buscan en el texto del valor.
MARKERS = (
    (re.compile(r"example\.(com|net|org)\b", re.I), "dominio de ejemplo (example.com)"),
    (re.compile(r"(?<![a-z0-9-])example-[a-z0-9]", re.I), "nombre de ejemplo example-..."),
    (re.compile(r"REEMPLAZAR", re.I), "marcador REEMPLAZAR"),
    (re.compile(r"<[^<>\"\s=]+>"), "marcador <...> de los ejemplos"),
)
# Marcadores que son el texto completo de una cadena.
EXACT_MARKERS = (
    (re.compile(r"0{6,}|0{6}-0{6}-0{6}"), "ID de ejemplo de solo ceros"),
)
STRING_LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
TOP_LEVEL_ATTR = re.compile(r"([A-Za-z_][A-Za-z0-9_-]*)\s*=(?!=)")
HEREDOC = re.compile(r"<<-?([A-Za-z_][A-Za-z0-9_]*)\r?\n")


def declared_variables(root):
    names = set()
    for path in glob.glob(os.path.join(root, "*.tf")):
        with open(path, encoding="utf-8") as handle:
            names.update(VARIABLE_BLOCK.findall(handle.read()))
    return names


def tfvars_assignments(text):
    """{variable: texto del valor} de las asignaciones de primer nivel de un .tfvars, sin comentarios.

    Lector mínimo de la sintaxis de HCL que usan los terraform.tfvars.example: cadenas con
    escapes, heredocs, comentarios #, // y /* */, y objetos, listas y paréntesis anidados.
    """
    out, current, buf = {}, None, []
    depth, i, n = 0, 0, len(text)
    while i < n:
        c = text[i]
        if c == "#" or text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if c == '"':
            j = i + 1
            while j < n and text[j] not in '"\n':
                j += 2 if text[j] == "\\" else 1
            if current:
                buf.append(text[i:j + 1])
            i = j + 1
            continue
        m = HEREDOC.match(text, i)
        if m:
            end = re.compile(r"^\s*%s\s*$" % re.escape(m.group(1)), re.M).search(text, m.end())
            stop = n if end is None else end.end()
            if current:
                buf.append(text[i:stop])
            i = stop
            continue
        if depth == 0 and not text[text.rfind("\n", 0, i) + 1:i].strip():
            m = TOP_LEVEL_ATTR.match(text, i)
            if m:
                if current:
                    out[current] = "".join(buf)
                current, buf = m.group(1), []
                i = m.end()
                continue
        if c in "{[(":
            depth += 1
        elif c in "}])":
            depth = max(0, depth - 1)
        if current:
            buf.append(c)
        i += 1
    if current:
        out[current] = "".join(buf)
    return out


def markers_in_text(text):
    """Descripciones de los marcadores de un texto (valor de HCL o cadena)."""
    found = [label for pattern, label in MARKERS if pattern.search(text)]
    for literal in STRING_LITERAL.findall(text) or [text]:
        found += [label for pattern, label in EXACT_MARKERS if pattern.fullmatch(literal.strip())]
    return sorted(set(found))


def json_strings(value):
    """Cadenas de un valor JSON, también las llaves de los objetos (correos de essential_contacts)."""
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for k, v in value.items():
            yield str(k)
            yield from json_strings(v)
    elif isinstance(value, list):
        for v in value:
            yield from json_strings(v)


def placeholder_errors(root, variables, sources, example_text):
    """Lista de (variable, origen, marcadores) de los valores resueltos que llevan un marcador."""
    declared = declared_variables(root)
    errors = []
    for name in sorted(declared):
        if name in variables:
            found = sorted({m for s in json_strings(variables[name]) for m in markers_in_text(s)})
            origin = "GCP_TFVARS_JSON[%r]" % sources[name]
        else:
            text = tfvars_assignments(example_text).get(name)
            if text is None:
                continue
            found = markers_in_text(text)
            origin = "terraform.tfvars.example"
        if found:
            errors.append((name, origin, found))
    return errors


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
    variables, sources = {}, {}
    for key in ("common", root):
        part = data.get(key) or {}
        if not isinstance(part, dict):
            sys.stderr.write("ERROR: GCP_TFVARS_JSON[%r] no es un objeto JSON\n" % key)
            return 2
        variables.update(part)
        sources.update({name: key for name in part})

    declared = declared_variables(root)
    project = variables.get("project_id")
    if "project_id" in declared and not (isinstance(project, str) and project.strip()):
        sys.stderr.write("ERROR: %s declara project_id y GCP_TFVARS_JSON no lo trae: agregar \"project_id\" "
                         "(salida project_id de 0-bootstrap) en \"common\" (ADR 0029 §1, docs/pipeline.md §2)\n" % root)
        return 2

    example = os.path.join(root, "terraform.tfvars.example")
    example_text = ""
    if os.path.isfile(example):
        with open(example, encoding="utf-8") as handle:
            example_text = handle.read()
    errors = placeholder_errors(root, variables, sources, example_text)
    if errors:
        sys.stderr.write("ERROR: %s: %d variable(s) llegarían al plan con valores de ejemplo; no se escribe nada:\n"
                         % (root, len(errors)))
        for name, origin, found in errors:
            sys.stderr.write("  %s (de %s): %s\n" % (name, origin, "; ".join(found)))
        sys.stderr.write("Poner el valor real de cada una en GCP_TFVARS_JSON, en \"common\" o en %r "
                         "(docs/pipeline.md §2).\n" % root)
        return 2

    if os.path.isfile(example):
        shutil.copyfile(example, os.path.join(root, "terraform.tfvars"))
    with open(os.path.join(root, "zz-ci.auto.tfvars.json"), "w", encoding="utf-8", newline="\n") as out:
        json.dump(variables, out, ensure_ascii=False, indent=2)
        out.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
