#!/usr/bin/env python3
"""Huella de un plan de Terraform (`terraform show -json`), para comparar dos planes.

Uso: python3 scripts/plan-fingerprint.py plan.json   -> imprime un SHA-256 en hexadecimal

La usa .github/workflows/_terraform-root.yml: el trabajo `plan` calcula la huella del plan que
se revisa y el trabajo `apply`, ya aprobado, vuelve a planear y solo aplica si la huella es
igual. Así se aplica exactamente lo revisado sin mover el archivo del plan (que lleva los
valores sensibles en claro) entre trabajos.

Entra en la huella, por cada cambio que no es `no-op`, ordenado por dirección: la dirección,
las acciones, `after`, `after_unknown` y `after_sensitive`; y las acciones de cada salida.
No entra el estado anterior (`before`), `prior_state` ni la fecha del plan, que cambian sin
cambiar lo que se aplica. La huella es un SHA-256: no expone valores.

Solo biblioteca estándar; Python 3.8 o posterior.
"""

import hashlib
import json
import sys


def fingerprint(plan):
    changes = []
    for rc in plan.get("resource_changes") or []:
        change = rc.get("change") or {}
        actions = change.get("actions") or []
        if actions == ["no-op"]:
            continue
        changes.append({
            "address": rc.get("address"),
            "actions": actions,
            "after": change.get("after"),
            "after_unknown": change.get("after_unknown"),
            "after_sensitive": change.get("after_sensitive"),
        })
    changes.sort(key=lambda c: c["address"] or "")
    outputs = {k: (v or {}).get("actions") for k, v in sorted((plan.get("output_changes") or {}).items())}
    canonical = json.dumps({"resource_changes": changes, "output_changes": outputs},
                           sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("Uso: python3 scripts/plan-fingerprint.py plan.json\n")
        return 2
    with open(argv[1], encoding="utf-8") as handle:
        print(fingerprint(json.load(handle)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
