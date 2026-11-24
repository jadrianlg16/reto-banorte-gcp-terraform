#!/usr/bin/env python3
"""Comprobaciones de un plan de destrucción (`terraform plan -destroy`, `terraform show -json`).

Uso: python3 scripts/destroy-plan-check.py plan.json --env ENTORNO [--prefix PREFIJO]
         [--summary RESUMEN.md] [--root RAÍZ]

    --env     entorno que se destruye (dev o qa en destroy.yml). Si el plan trae la variable
              `environment`, tiene que coincidir.
    --prefix  prefijo de los nombres (`var.prefix`). Por defecto, el valor de la variable
              `prefix` del plan (sección `variables` de `terraform show -json`).

Lo usa .github/workflows/_terraform-root.yml en modo destroy (destroy.yml), en el trabajo `plan`
antes de pedir la aprobación y otra vez en el trabajo `apply` antes de `terraform apply`. Ver
docs/pipeline.md §1.5.

Sale con:
  0  el plan solo destruye y nada conocido lo bloquea (puede haber avisos);
  1  hay bloqueos: el destroy fallaría, dejaría un recurso fuera de Terraform o tocaría algo
     que no es del entorno. Se detiene antes de borrar nada, en vez de dejar el entorno a medio
     destruir;
  2  no es un plan de destrucción (alguna acción que no es delete), el JSON no sirve o no se
     sabe el prefijo.

Bloqueos por protección (se leen de `before`, el estado ya refrescado, porque el proveedor
decide el borrado con el valor del estado y no con el de la configuración):
  - `deletion_protection = true` en cualquier recurso (Cloud SQL, GKE, Cloud Run...), y
    `deletion_protection_enabled = true` (Filestore; `settings` de Cloud SQL);
  - `deletion_policy = "PREVENT"` en cualquier recurso.
  Se corrigen cambiando la variable en GCP_TFVARS_JSON y corriendo apply.yml antes del destroy.

Bloqueos por alcance (ADR 0029 §1, §4 y §8; protegen lo compartido del proyecto único):
  - `google_project`: ninguna raíz borra el proyecto;
  - un recurso que existe una vez por proyecto (APIs, metadatos, auditoría, Binary
    Authorization, sinks y buckets de logs, presupuesto, roles personalizados, políticas de
    organización, la cuenta de Compute por defecto, IAM de proyecto autoritativo...): una raíz de
    entorno no lo declara y su destroy no lo puede borrar;
  - un recurso de GCP cuyo nombre no lleva `<prefix>-<env>-`. "Nombre" es cualquiera de los
    atributos de NAME_ATTRS: el nombre propio (`name`, `account_id`, `secret_id`...) o, para hijos
    y permisos, el recurso padre (`instance`, `network`, `crypto_key_id`, `bucket`...) o el
    miembro (`member`). Basta uno: un permiso sobre un recurso del entorno o para una cuenta del
    entorno es del entorno. En rutas y correos se mira cada segmento, salvo el que sigue a
    `projects`, `locations`, `regions` o `zones` (el ID del proyecto no cuenta), y del correo,
    solo la parte local. Los recursos de otros proveedores (terraform_data, random...) no se
    revisan: no existen en GCP.

Avisos (no detienen; el destroy puede fallar por causas que el plan no ve):
  - bóveda de Backup and DR: los respaldos dentro de la retención forzada no se borran y, desde
    el 1 nov 2026, el proyecto recibe un gravamen (lien); con `backup_count` > 0 el borrado de la
    bóveda falla;
  - conexión de Private Service Access: no se borra hasta que el servicio productor libera sus
    recursos (cuatro días después de borrar una instancia de Cloud SQL);
  - bucket sin `force_destroy`: falla si tiene objetos;
  - `deletion_policy = "ABANDON"`: el recurso queda en GCP.

Solo imprime direcciones, nombres y los valores de esas banderas, nunca otros valores del plan
(que pueden ser sensibles). Solo biblioteca estándar; Python 3.8 o posterior.
"""

import argparse
import json
import re
import sys

ALLOWED_ACTIONS = (["delete"], ["no-op"])

# Proveedores con recursos en GCP; los demás (terraform_data, random, time...) no se revisan.
GOOGLE_PROVIDERS = re.compile(r"(^|/)hashicorp/google(-beta)?$")

# Recursos que existen una vez por proyecto o que actúan sobre todo el proyecto (ADR 0029 §4).
# Una raíz de entorno no los declara; si aparecen en su destroy, se detiene.
PROJECT_SINGLETONS = {
    "google_project_service",
    "google_project_services",
    "google_compute_project_metadata",
    "google_compute_project_metadata_item",
    "google_project_iam_audit_config",
    "google_project_iam_binding",
    "google_project_iam_policy",
    "google_project_iam_custom_role",
    "google_project_default_service_accounts",
    "google_project_organization_policy",
    "google_org_policy_policy",
    "google_binary_authorization_policy",
    "google_essential_contacts_contact",
    "google_logging_project_sink",
    "google_logging_project_bucket_config",
    "google_logging_project_exclusion",
    "google_billing_budget",
    "google_scc_project_notification_config",
    "google_scc_v2_project_notification_config",
    "google_iam_deny_policy",
    "google_iam_workload_identity_pool",
    "google_iam_workload_identity_pool_provider",
    "google_access_context_manager_service_perimeter",
    "google_access_context_manager_service_perimeter_resource",
    "google_access_context_manager_service_perimeter_dry_run_resource",
}

# Atributos que identifican un recurso: su nombre o el de su padre, o el miembro de un permiso.
# `namespaced_name` (valores de etiquetas: <proyecto>/<llave>/<valor>) se mira sin su primer
# segmento, que es el proyecto.
NAME_ATTRS = (
    "name", "account_id", "secret_id", "repository_id", "backup_vault_id", "backup_plan_id",
    "backup_plan_association_id", "short_name", "slo_id", "service_id", "display_name",
    "namespaced_name", "self_link",
    "instance", "cluster", "router", "network", "managed_zone", "firewall_policy", "policy",
    "crypto_key_id", "key_ring_id", "bucket", "service_account_id", "repository", "service",
    "location_id", "member",
)
SKIP_AFTER = {"projects", "locations", "regions", "zones", "folders", "organizations"}
MEMBER_TYPE = re.compile(r"^(serviceAccount|user|group|domain|principal|principalSet|deleted:serviceAccount):")


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


def segments(value, skip_first=False):
    """Segmentos con nombre de una ruta, URL o correo (sin el ID del proyecto)."""
    text = MEMBER_TYPE.sub("", value.strip())
    parts = text.split("/")
    out = []
    for i, part in enumerate(parts):
        if (skip_first and i == 0) or (i > 0 and parts[i - 1] in SKIP_AFTER):
            continue
        out.append(part.split("@", 1)[0])
    return out


def env_named(value, marker, skip_first=False):
    return isinstance(value, str) and any(s.startswith(marker) for s in segments(value, skip_first))


def names_of(before):
    """(atributo, valor) de los atributos identificadores con texto."""
    out = []
    for attr in NAME_ATTRS:
        v = before.get(attr)
        if isinstance(v, str) and v.strip():
            out.append((attr, v))
    return out


def plan_variable(plan, name):
    v = (plan.get("variables") or {}).get(name)
    if isinstance(v, dict) and isinstance(v.get("value"), str):
        return v["value"]
    return None


def check(plan, env, prefix):
    """(bloqueos, avisos, borrados) o lanza ValueError si el plan no sirve."""
    if not isinstance(plan, dict):
        raise ValueError("el plan no es un objeto JSON")
    changes = plan.get("resource_changes")
    if changes is None:
        changes = []
    if not isinstance(changes, list):
        raise ValueError("resource_changes no es una lista")
    marker = "%s-%s-" % (prefix, env)

    blockers, warnings, deletes = [], [], []
    plan_env = plan_variable(plan, "environment")
    if plan_env is not None and plan_env != env:
        blockers.append(("(variables)", "el plan es del entorno %s y se pidió destruir %s" % (plan_env, env)))

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
            before = {}

        for key in ("deletion_protection", "deletion_protection_enabled"):
            for path, value in walk_flags(before, key):
                if value is True:
                    blockers.append((address, "%s = true en el estado: el proveedor no lo borra. Poner la "
                                     "variable en false (deletion_protection de 3-workloads) y correr apply.yml antes" % path))

        if GOOGLE_PROVIDERS.search(str(rc.get("provider_name") or "")):
            if rtype == "google_project":
                blockers.append((address, "google_project: ninguna raíz borra el proyecto (ADR 0029 §1)"))
            elif rtype in PROJECT_SINGLETONS:
                blockers.append((address, "%s existe una vez por proyecto: una raíz de entorno no lo declara "
                                 "ni lo borra (ADR 0029 §4)" % rtype))
            else:
                names = names_of(before)
                if not any(env_named(v, marker, attr == "namespaced_name") for attr, v in names):
                    shown = ", ".join("%s=%s" % (a, v) for a, v in names[:3]) or "sin atributo de nombre"
                    blockers.append((address, "nombre sin %s (%s): no es del entorno %s y su destroy borraría algo "
                                     "compartido o de otro entorno (ADR 0029 §8)" % (marker, shown, env)))

        policy = before.get("deletion_policy")
        if policy == "PREVENT":
            blockers.append((address, "deletion_policy = \"PREVENT\" en el estado: el destroy falla"))
        elif policy == "ABANDON":
            warnings.append((address, "deletion_policy = \"ABANDON\": Terraform lo suelta sin borrarlo y queda en GCP"))

        if rtype == "google_backup_dr_backup_vault":
            count = backup_count(before.get("backup_count"))
            text = "bóveda de Backup and DR (retención forzada %s, backup_count %s)" % (
                before.get("backup_minimum_enforced_retention_duration") or "?", "?" if count is None else count)
            if count is None or count > 0:
                text += (". Con respaldos el borrado FALLA: ninguno se borra antes de la retención forzada y, desde el "
                         "1 nov 2026, Backup and DR pone un gravamen (lien) en el proyecto. El resto de la raíz se "
                         "destruye y la bóveda queda")
            if before.get("ignore_inactive_datasources") is not True and before.get("force_delete") is not True:
                text += (". Sin ignore_inactive_datasources (el módulo backup-dr no lo fija), una bóveda que tuvo "
                         "respaldos puede no borrarse aunque ya esté vacía (HYPOTHESIS)")
            warnings.append((address, text))
        elif rtype == "google_service_networking_connection":
            warnings.append((address, "conexión de Private Service Access: no se borra mientras el servicio productor tenga "
                             "recursos; tras borrar Cloud SQL espera cuatro días. Si falla, volver a lanzar destroy.yml "
                             "con incluir_red después de ese plazo (ADR 0029 §8)"))
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
    parser.add_argument("--env", required=True, help="entorno que se destruye (dev o qa)")
    parser.add_argument("--prefix", help="prefijo de los nombres; por defecto, la variable prefix del plan")
    parser.add_argument("--summary", help="agrega un resumen en Markdown a este archivo")
    parser.add_argument("--root", help="raíz, para el título del resumen")
    args = parser.parse_args(argv)
    for stream in (sys.stdout, sys.stderr):  # texto en español también en la consola de Windows
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")

    if not re.fullmatch(r"[a-z][a-z0-9]*", args.env):
        sys.stderr.write("ERROR: --env no válido: %r\n" % args.env)
        return 2
    try:
        with open(args.plan, encoding="utf-8") as handle:
            plan = json.load(handle)
        prefix = args.prefix or (plan_variable(plan, "prefix") if isinstance(plan, dict) else None)
        if not prefix or not re.fullmatch(r"[a-z][a-z0-9]*", prefix):
            raise ValueError("sin prefijo válido: pasar --prefix o planear una raíz con la variable prefix (llegó %r)"
                             % prefix)
        blockers, warnings, deletes = check(plan, args.env, prefix)
    except (OSError, ValueError) as exc:
        sys.stderr.write("ERROR: %s: %s\n" % (args.plan, exc))
        return 2

    print("se destruyen: %d recursos (entorno %s, nombres %s-%s-)" % (len(deletes), args.env, prefix, args.env))
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
