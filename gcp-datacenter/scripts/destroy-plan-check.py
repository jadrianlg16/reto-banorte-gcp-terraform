#!/usr/bin/env python3
"""Comprobaciones de un plan de destrucción (`terraform plan -destroy`, `terraform show -json`).

Uso: python3 scripts/destroy-plan-check.py plan.json [--summary RESUMEN.md] [--root RAÍZ]

Lo usa .github/workflows/_terraform-root.yml en modo destroy (destroy.yml), en el trabajo `plan`
antes de pedir la aprobación y otra vez en el trabajo `apply` antes de `terraform apply`. Ver
docs/pipeline.md §1.5.

Sale con:
  0  el plan solo destruye y nada conocido lo bloquea (puede haber avisos);
  1  hay bloqueos: el destroy fallaría o dejaría un recurso fuera de Terraform. Se detiene antes
     de borrar nada, en vez de dejar el entorno a medio destruir;
  2  no es un plan de destrucción (alguna acción que no es delete) o el JSON no sirve.

Bloqueos (se leen de `before`, el estado ya refrescado, porque el proveedor decide el borrado
con el valor del estado y no con el de la configuración):
  - `deletion_protection = true` en cualquier recurso (Cloud SQL, GKE, Cloud Run...), y
    `deletion_protection_enabled = true` (Filestore; `settings` de Cloud SQL);
  - `deletion_policy = "PREVENT"` en cualquier recurso; en `google_project`, todo lo que no sea
    "DELETE" (con "ABANDON" el proyecto queda vivo y la comprobación de huérfanos fallaría).
  Se corrigen cambiando la variable en GCP_TFVARS_JSON y corriendo apply.yml antes del destroy.

Avisos (no detienen; el destroy puede fallar por causas que el plan no ve):
  - bóveda de Backup and DR: los respaldos dentro de la retención forzada no se borran y, desde
    el 1 nov 2026, el proyecto recibe un gravamen (lien); con `backup_count` > 0 el borrado de la
    bóveda falla;
  - conexión de Private Service Access: no se borra hasta que el servicio productor libera sus
    recursos (cuatro días después de borrar una instancia de Cloud SQL);
  - bucket sin `force_destroy`: falla si tiene objetos;
  - `deletion_policy = "ABANDON"` fuera de `google_project`: el recurso queda en GCP.

Solo imprime direcciones y los valores de esas banderas, nunca otros valores del plan (que
pueden ser sensibles). Solo biblioteca estándar; Python 3.8 o posterior.
"""

import argparse
import json
import sys

ALLOWED_ACTIONS = (["delete"], ["no-op"])


def walk_flags(value, key, path=""):
    """(ruta, valor) de cada aparición de `key` dentro de `value` (dicts y listas anidados)."""
    if isinstance(value, dict):
        for k, v in value.items():
            here = "%s.%s" % (path, k) if path else k
            if k == key:
                yield here, v
            else:
                yield from walk_flags(v, key, here)
    elif isinstance(value, list):
        for i, v in enumerate(value):
            yield from walk_flags(v, key, "%s[%d]" % (path, i))


def backup_count(value):
    """backup_count de la bóveda (string en el esquema de google 6.50.0) como entero, o None."""
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None


def check(plan):
    """(bloqueos, avisos, borrados) o lanza ValueError si el plan no sirve."""
    if not isinstance(plan, dict):
        raise ValueError("el plan no es un objeto JSON")
    changes = plan.get("resource_changes")
    if changes is None:
        changes = []
    if not isinstance(changes, list):
        raise ValueError("resource_changes no es una lista")

    blockers, warnings, deletes = [], [], []
    for rc in changes:
        if not isinstance(rc, dict) or not isinstance(rc.get("change"), dict):
            raise ValueError("cambio sin 'change': no es un plan de Terraform")
        address = rc.get("address") or "?"
        actions = rc["change"].get("actions")
        if rc.get("mode") == "data":
            continue
        if actions not in ALLOWED_ACTIONS:
            raise ValueError("no es un plan de destrucción: %s tiene acciones %s" % (address, actions))
        if actions != ["delete"]:
            continue
        deletes.append(address)
        rtype = rc.get("type", "")
        before = rc["change"].get("before")
        if not isinstance(before, dict):
            continue

        for key in ("deletion_protection", "deletion_protection_enabled"):
            for path, value in walk_flags(before, key):
                if value is True:
                    blockers.append((address, "%s = true en el estado: el proveedor no lo borra. Poner la "
                                     "variable en false (deletion_protection de 5-workloads) y correr apply.yml antes" % path))

        policy = before.get("deletion_policy")
        if rtype == "google_project":
            if policy != "DELETE":
                blockers.append((address, "deletion_policy = %s en el estado: con PREVENT el destroy falla y con ABANDON el "
                                 "proyecto queda vivo (huérfano). Poner deletion_policy (4-projects) o "
                                 "project_deletion_policy (3-networks) en \"DELETE\" y correr apply.yml antes"
                                 % json.dumps(policy)))
        elif policy == "PREVENT":
            blockers.append((address, "deletion_policy = \"PREVENT\" en el estado: el destroy falla"))
        elif policy == "ABANDON":
            warnings.append((address, "deletion_policy = \"ABANDON\": Terraform lo suelta sin borrarlo y queda en GCP"))

        if rtype == "google_backup_dr_backup_vault":
            count = backup_count(before.get("backup_count"))
            text = "bóveda de Backup and DR (retención forzada %s, backup_count %s)" % (
                before.get("backup_minimum_enforced_retention_duration") or "?", "?" if count is None else count)
            if count is None or count > 0:
                text += (". Con respaldos el borrado FALLA: ninguno se borra antes de la retención forzada y, desde el "
                         "1 nov 2026, Backup and DR pone un gravamen (lien) en el proyecto, que 4-projects tampoco podría "
                         "borrar. El resto de la raíz se destruye y la bóveda queda")
            if before.get("ignore_inactive_datasources") is not True and before.get("force_delete") is not True:
                text += (". Sin ignore_inactive_datasources (el módulo backup-dr no lo fija), una bóveda que tuvo "
                         "respaldos puede no borrarse aunque ya esté vacía (HYPOTHESIS)")
            warnings.append((address, text))
        elif rtype == "google_service_networking_connection":
            warnings.append((address, "conexión de Private Service Access: no se borra mientras el servicio productor tenga "
                             "recursos; tras borrar Cloud SQL espera cuatro días. Si falla, volver a lanzar destroy.yml "
                             "después de ese plazo"))
        elif rtype == "google_storage_bucket" and before.get("force_destroy") is not True:
            warnings.append((address, "bucket sin force_destroy: el borrado falla si tiene objetos (también versiones "
                             "no actuales)"))
    return blockers, warnings, deletes


def write_summary(path, root, blockers, warnings, deletes):
    with open(path, "a", encoding="utf-8") as out:
        out.write("### Comprobaciones del destroy%s\n\n" % (" de `%s`" % root if root else ""))
        out.write("- Recursos que se destruyen: %d\n" % len(deletes))
        out.write("- Bloqueos: %d%s\n" % (len(blockers), " (no se destruye nada)" if blockers else ""))
        out.write("- Avisos: %d\n\n" % len(warnings))
        for title, items in (("Bloqueos", blockers), ("Avisos", warnings)):
            if items:
                out.write("| %s | Recurso | Motivo |\n|---|---|---|\n" % title)
                for address, reason in items:
                    out.write("| %s | `%s` | %s |\n" % (title[:-1].lower(), address, reason.replace("|", "\\|")))
                out.write("\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description="Comprobaciones de un plan de destrucción de Terraform.")
    parser.add_argument("plan")
    parser.add_argument("--summary", help="agrega un resumen en Markdown a este archivo")
    parser.add_argument("--root", help="raíz, para el título del resumen")
    args = parser.parse_args(argv)
    for stream in (sys.stdout, sys.stderr):  # texto en español también en la consola de Windows
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")

    try:
        with open(args.plan, encoding="utf-8") as handle:
            plan = json.load(handle)
        blockers, warnings, deletes = check(plan)
    except (OSError, ValueError) as exc:
        sys.stderr.write("ERROR: %s: %s\n" % (args.plan, exc))
        return 2

    print("se destruyen: %d recursos" % len(deletes))
    for address, reason in blockers:
        print("BLOQUEO %s: %s" % (address, reason))
    for address, reason in warnings:
        print("AVISO %s: %s" % (address, reason))
    if args.summary:
        write_summary(args.summary, args.root, blockers, warnings, deletes)
    if blockers:
        sys.stderr.write("ERROR: %d bloqueo(s): no se destruye nada (docs/pipeline.md §1.5, \"Preparación\").\n"
                         % len(blockers))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
