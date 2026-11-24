#!/usr/bin/env python3
"""Huérfanos de un entorno en el proyecto después de destruirlo (destroy.yml, ADR 0029 §8).

Uso:
    python3 scripts/destroy-orphans.py --env ENTORNO --prefix PREFIJO --project ID
        --project-number N --assets ASSETS.json [--state S.tfstate ...]
        [--summary RESUMEN.md] [--report-only]

    --env, --prefix   entorno destruido y prefijo de los nombres (`var.prefix`).
    --project, --project-number
               ID y número del proyecto (salidas project_id y project_number de 0-bootstrap).
    ASSETS     salida de
               gcloud asset search-all-resources --scope=projects/<ID> --format=json
               (lista de objetos con name, assetType, project, labels, state...; también
               {"results": [...]}).
    --state    estados que siguen en el bucket (crudos o `terraform show -json`), uno por raíz.
               Lo que todavía administra un estado no es huérfano: por ejemplo, el spoke del
               entorno cuando destroy.yml corre sin incluir_red, o lo del entorno que vive en
               1-base. Las raíces destruidas quedan con el estado vacío y no cuentan.
    --summary  agrega un resumen en Markdown (para $GITHUB_STEP_SUMMARY).
    --report-only  sale con 0 aunque haya huérfanos.

Un recurso es DEL ENTORNO si tiene la etiqueta `env` igual a ENTORNO o si su nombre, su
displayName o su correo (cuentas de servicio) llevan `<prefix>-<env>-` (misma regla que
scripts/destroy-plan-check.py: el ID del proyecto no cuenta). VPC, subredes, routers, políticas
de firewall y cuentas de servicio no llevan etiquetas: se reconocen por el nombre. Lo demás del
proyecto (compartido u de otros entornos) se cuenta y no se revisa; el proyecto mismo tampoco.

De lo que es del entorno, es ESPERADO (se lista, no falla):
  1. lo que conserva 1-base (ADR 0029 §8, lista KEEP_TYPES): llaveros, llaves y versiones de
     Cloud KMS (no se pueden borrar), repositorios de Artifact Registry con sus imágenes y
     contenedores de secretos con sus versiones;
  2. lo que todavía administra un estado de --state (nombre, hijo o VM de un MIG, con las reglas
     de scripts/unmanaged-resources.py);
  3. un recurso en estado DELETED, DELETE_REQUESTED o DELETE_IN_PROGRESS (el índice todavía lo
     muestra);
  4. una versión de llave de Cloud KMS DESTROYED o DESTROY_SCHEDULED.
Todo lo demás es HUÉRFANO: se lista y el script sale con 1. Un bucket, una VM o una cuenta de
servicio del entorno que sobrevivieron al destroy (por ejemplo con deletion_policy ABANDON) son
huérfanos.

Sale con 2 si el listado no sirve: no es de Cloud Asset (objeto sin `results`, elementos sin
`name`), está vacío, no trae el proyecto mismo o trae recursos de otro proyecto (mismas reglas
que scripts/unmanaged-resources.py).

HYPOTHESIS (sin el proyecto real): que Cloud Asset devuelva `labels` y, para las cuentas de
servicio, `additionalAttributes.email`, y que liste el proyecto mismo con
--scope=projects/<ID>. VERIFICAR-EN-APPLY en el primer destroy de dev (pendiente 85).

Solo biblioteca estándar; Python 3.8 o posterior.
"""

import argparse
import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, filename):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# La regla del nombre es la de destroy-plan-check.py y la de "administrado por un estado", la de
# unmanaged-resources.py: una sola implementación de cada una.
names = _load("destroy_plan_check", "destroy-plan-check.py")
unmanaged = _load("unmanaged_resources", "unmanaged-resources.py")

KEY_VERSION_TYPE = "cloudkms.googleapis.com/CryptoKeyVersion"
GONE_STATES = {"DELETED", "DELETE_REQUESTED", "DELETE_IN_PROGRESS"}
KEY_VERSION_GONE = {"DESTROYED", "DESTROY_SCHEDULED"}
# Lo del entorno que conserva 1-base (ADR 0029 §4 y §8): no tiene destroy.
KEEP_TYPES = {
    "cloudkms.googleapis.com/KeyRing": "llavero de KMS de 1-base (GCP no lo borra)",
    "cloudkms.googleapis.com/CryptoKey": "llave de KMS de 1-base (GCP no la borra)",
    KEY_VERSION_TYPE: "versión de una llave de KMS de 1-base",
    "artifactregistry.googleapis.com/Repository": "repositorio de Artifact Registry de 1-base",
    "artifactregistry.googleapis.com/DockerImage": "imagen en un repositorio de 1-base",
    "secretmanager.googleapis.com/Secret": "contenedor de secretos de 1-base",
    "secretmanager.googleapis.com/SecretVersion": "versión de un secreto de 1-base (se carga a mano, ADR 0015)",
}


def state_of(asset):
    return str(asset.get("state") or "").upper()


def of_environment(asset, env, marker):
    """True si el recurso es del entorno: etiqueta env o nombre con <prefix>-<env>-."""
    labels = asset.get("labels") if isinstance(asset.get("labels"), dict) else {}
    if labels.get("env") == env:
        return True
    email = (asset.get("additionalAttributes") or {}).get("email") if isinstance(
        asset.get("additionalAttributes"), dict) else None
    return any(names.env_named(v, marker) for v in (asset.get("name"), asset.get("displayName"), email))


def classify(assets, env, prefix, project_number, managed, parents, mig_patterns, aliases):
    marker = "%s-%s-" % (prefix, env)
    expected, orphans, others = [], [], 0
    for a in assets:
        atype = a.get("assetType", "")
        if atype == unmanaged.PROJECT_ASSET_TYPE or not of_environment(a, env, marker):
            others += 1
            continue
        entry = {"assetType": atype, "name": a["name"], "state": state_of(a)}
        canon = unmanaged.canonical(unmanaged.normalize(a["name"]), aliases)
        cls = unmanaged.managed_class(canon, atype, managed, parents, mig_patterns)
        if entry["state"] in GONE_STATES:
            entry["reason"] = "borrado (el índice todavía lo muestra)"
        elif atype == KEY_VERSION_TYPE and entry["state"] in KEY_VERSION_GONE:
            entry["reason"] = "versión de llave de KMS destruida o programada para destruir"
        elif atype in KEEP_TYPES:
            entry["reason"] = "lo conserva 1-base: " + KEEP_TYPES[atype]
        elif cls:
            entry["reason"] = "lo administra todavía un estado (%s)" % {
                "managed": "por nombre", "child": "hijo de un recurso administrado", "mig": "VM o disco de un MIG"}[cls]
        else:
            orphans.append(entry)
            continue
        expected.append(entry)
    return expected, orphans, others


def main(argv=None):
    parser = argparse.ArgumentParser(description="Huérfanos de un entorno destruido en el proyecto.")
    parser.add_argument("--env", required=True)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--project", required=True)
    parser.add_argument("--project-number", required=True)
    parser.add_argument("--assets", required=True)
    parser.add_argument("--state", action="append", default=[])
    parser.add_argument("--summary")
    parser.add_argument("--report-only", action="store_true")
    args = parser.parse_args(argv)
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")

    for flag, value in (("--env", args.env), ("--prefix", args.prefix)):
        if not re.fullmatch(r"[a-z][a-z0-9]*", value):
            sys.stderr.write("ERROR: %s no válido: %r\n" % (flag, value))
            return 2
    if not unmanaged.valid_project(args.project, args.project_number):
        sys.stderr.write("ERROR: --project o --project-number no válidos: %r, %r\n" % (args.project, args.project_number))
        return 2
    assets, error = unmanaged.read_assets(args.assets)
    if error:
        sys.stderr.write("ERROR: %s: %s\n" % (args.assets, error))
        return 2
    try:
        states = [unmanaged.load_json(p) for p in args.state]
    except (OSError, ValueError) as exc:
        sys.stderr.write("ERROR: estado ilegible: %s\n" % exc)
        return 2
    managed, parents, mig_patterns, aliases = unmanaged.build_managed(states, {args.project: args.project_number})
    error = unmanaged.coverage_error(assets, args.project, args.project_number, aliases)
    if error:
        sys.stderr.write("ERROR: %s: %s\n" % (args.assets, error))
        return 2

    expected, orphans, others = classify(assets, args.env, args.prefix, args.project_number,
                                         managed, parents, mig_patterns, aliases)
    print("recursos en el proyecto %s: %d (del entorno %s: %d; otros: %d)"
          % (args.project, len(assets), args.env, len(expected) + len(orphans), others))
    print("  esperados: %d" % len(expected))
    print("  HUÉRFANOS: %d" % len(orphans))
    for e in sorted(expected, key=lambda e: (e["assetType"], e["name"])):
        print("ESPERADO %s %s (%s)" % (e["assetType"], e["name"], e["reason"]))
    for e in sorted(orphans, key=lambda e: (e["assetType"], e["name"])):
        print("HUERFANO %s %s%s" % (e["assetType"], e["name"], " [%s]" % e["state"] if e["state"] else ""))

    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as out:
            out.write("- Recursos del entorno `%s` en el proyecto `%s`: %d (esperados %d, **huérfanos %d**); "
                      "otros recursos del proyecto: %d\n\n"
                      % (args.env, args.project, len(expected) + len(orphans), len(expected), len(orphans), others))
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
