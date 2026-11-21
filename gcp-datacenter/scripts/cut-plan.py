#!/usr/bin/env python3
"""Recorta un plan real (`terraform show -json`) a un plan de ejemplo para policies/fixtures.

Uso:
    python3 scripts/cut-plan.py PLAN.json REGEX [REGEX ...] > policies/fixtures/<regla>_<pass|fail>_<caso>.json

Conserva:
- `format_version` y `terraform_version`;
- los `resource_changes` cuya dirección completa (`address`) coincide entera con alguna REGEX;
- de `configuration`, solo los módulos y recursos de esos cambios (las políticas leen la
  configuración para saber si un atributo se declaró; ver policies/compute_public_ip.rego).

Reemplaza por "REDACTADO" los valores que el plan marca como sensibles (`after_sensitive`,
`before_sensitive`): `terraform show -json` los trae en claro.

Descarta `planned_values`, `prior_state`, `variables`, `output_changes`, `relevant_attributes`,
`checks` y `timestamp`: las políticas no los leen y solo agrandan el archivo.

Sale con código 1 si alguna REGEX no coincide con ningún recurso (evita planes de ejemplo vacíos
por un error de escritura). Solo biblioteca estándar; Python 3.8 o posterior.
"""

import json
import re
import sys


def module_names(module_address):
    """`module.a["x"].module.b` -> ["a", "b"] (sin índices de count o for_each)."""
    if not module_address:
        return []
    without_keys = re.sub(r"\[[^\]]*\]", "", module_address)
    return re.findall(r"module\.([^.]+)", without_keys)


def redact(value, sensitive):
    """Reemplaza por "REDACTADO" lo que `*_sensitive` marca como sensible.

    `terraform show -json` incluye los valores sensibles en claro; un plan de ejemplo no debe
    llevarlos aunque sean de prueba.
    """
    if sensitive is True:
        return None if value is None else "REDACTADO"
    if isinstance(value, dict) and isinstance(sensitive, dict):
        return {k: redact(v, sensitive.get(k)) for k, v in value.items()}
    if isinstance(value, list) and isinstance(sensitive, list):
        return [redact(v, sensitive[i] if i < len(sensitive) else None) for i, v in enumerate(value)]
    return value


def redact_change(rc):
    change = dict(rc.get("change", {}))
    for side in ("before", "after"):
        if side in change:
            change[side] = redact(change[side], change.get(side + "_sensitive"))
    out = dict(rc)
    out["change"] = change
    return out


def prune_module(module, wanted):
    """Copia de un módulo de `configuration` con solo los recursos y llamadas pedidos.

    `wanted` es un árbol: {"resources": {"tipo.nombre", ...}, "calls": {nombre: subárbol}}.
    """
    out = {}
    resources = [
        r for r in module.get("resources", [])
        if r.get("mode") == "managed" and r.get("address") in wanted["resources"]
    ]
    if resources:
        out["resources"] = resources
    calls = {}
    for name, sub in wanted["calls"].items():
        call = module.get("module_calls", {}).get(name)
        if call is None:
            continue
        new_call = {k: v for k, v in call.items() if k not in ("module", "expressions")}
        new_call["module"] = prune_module(call.get("module", {}), sub)
        calls[name] = new_call
    if calls:
        out["module_calls"] = calls
    return out


def main(argv):
    if len(argv) < 3:
        sys.stderr.write(__doc__)
        return 2
    with open(argv[1], encoding="utf-8") as handle:
        plan = json.load(handle)
    patterns = [re.compile(p) for p in argv[2:]]

    kept = []
    matched = [False] * len(patterns)
    for rc in plan.get("resource_changes", []):
        for i, pattern in enumerate(patterns):
            if pattern.fullmatch(rc.get("address", "")):
                matched[i] = True
                if rc not in kept:
                    kept.append(rc)
    missing = [argv[2 + i] for i, ok in enumerate(matched) if not ok]
    if missing:
        sys.stderr.write("ERROR: sin coincidencias para: %s\n" % ", ".join(missing))
        return 1

    tree = {"resources": set(), "calls": {}}
    for rc in kept:
        node = tree
        for name in module_names(rc.get("module_address", "")):
            node = node["calls"].setdefault(name, {"resources": set(), "calls": {}})
        node["resources"].add("%s.%s" % (rc["type"], rc["name"]))

    out = {
        "format_version": plan.get("format_version"),
        "terraform_version": plan.get("terraform_version"),
        "resource_changes": [redact_change(rc) for rc in kept],
    }
    root = plan.get("configuration", {}).get("root_module")
    if root is not None:
        out["configuration"] = {"root_module": prune_module(root, tree)}
    json.dump(out, sys.stdout, indent=2, sort_keys=True, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
