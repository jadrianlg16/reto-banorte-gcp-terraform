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

Un recurso es DEL ENTORNO (ADR 0029 §8: "contiene `<prefix>-<env>-`") si cumple alguna de:
  1. la etiqueta `env` es ENTORNO;
  2. su nombre, su displayName o su correo (cuentas de servicio) CONTIENEN `<prefix>-<env>-` en
     algún segmento de la ruta (el ID del proyecto no cuenta). Así entran los restos que GKE
     nombra con el clúster (`<prefix>-<env>-<app>-gke[-dr]`, ADR 0029 §4): firewalls
     `gke-<clúster>-<hash>-*` y VM, discos y grupos de los nodos `gke-<clúster>-<pool>-*`;
  3. el valor de alguna otra etiqueta contiene `<prefix>-<env>-` (la del nombre del clúster que
     GKE pone a sus recursos, `goog-k8s-cluster-name`);
  4. es un recurso que parece de GKE (ver abajo) y la red o la subred que trae Cloud Asset
     (`network`, `subnetwork`... dentro de `additionalAttributes` o de
     `versionedResources[].resource`) es del spoke del entorno. Solo para GKE: las rutas y reglas
     que GCP crea en un spoke que se conserva también están en su red y no son huérfanos;
  5. la descripción en JSON que GKE pone a sus recursos nombra un namespace que termina en
     `-<env>` (ADR 0029 §9: el namespace es `<app>-<env>`): discos `pvc-*` del controlador de
     PD (`kubernetes.io/created-for/pvc/namespace`), NEG (`namespace`) y firewalls de los
     Services (`kubernetes.io/service-name` = `<namespace>/<servicio>`);
  6. es un recurso que GKE nombra `k8s<n>-<uid de 8>-<namespace>-<servicio>-...` (NEG,
     reglas de reenvío, servicios de backend, health checks) y el resto del nombre lleva
     `-<env>-` (el namespace `<app>-<env>`).
La regla de destroy-plan-check.py, que BLOQUEA, sigue estricta (empieza con `<prefix>-<env>-`);
esta, que busca restos para avisar, es más amplia.

VPC, subredes, routers, políticas de firewall y cuentas de servicio no llevan etiquetas: se
reconocen por el nombre. Lo demás del proyecto (compartido u de otros entornos) se cuenta y no se
revisa; el proyecto mismo tampoco.

RESTOS DE GKE SIN ENTORNO (aviso, no falla): un recurso que parece de GKE (etiqueta `goog-gke-*`
o `goog-k8s-*`, nombre `gke-*`, `k8s*-*`, `pvc-<uuid>` o `a<32 hex>`, descripción de Kubernetes)
y que no se puede atribuir a ningún entorno (ni a este ni a dev, qa, prod o common). Por ejemplo,
un disco `pvc-*` que solo trae la etiqueta `goog-gke-volume`: puede ser de este entorno o de un
clúster que sigue vivo en otro. Se listan para revisarlos a mano
(`gcloud compute disks describe`, campo `users` y descripción); no hacen fallar el trabajo,
porque los de otros entornos aparecerían en cada destroy.

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
VERIFICAR-EN-APPLY (restos de GKE, sin el proyecto real ni la documentación de cada campo):
qué trae Cloud Asset para discos, NEG y firewalls que deja GKE (`description`, `labels`,
`network` en `additionalAttributes`); que los nombres `gke-*` y `k8s1-*` lleven el clúster y el
namespace sin recortar; y que el controlador de PD escriba el namespace en la descripción.
Los formatos de los datos de prueba (scripts/testdata/destroy/assets-gke.json) son HYPOTHESIS.

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


# Entornos a los que se puede atribuir un recurso: un resto de GKE que es de alguno de estos (y
# no del que se destruye) no es "sin entorno".
KNOWN_ENVS = ("bootstrap", "common", "dev", "qa", "prod")
# Llaves con la red o la subred de un recurso dentro de additionalAttributes o
# versionedResources[].resource (HYPOTHESIS: qué tipos las traen).
NETWORK_KEYS = {"network", "networks", "subnetwork", "subnetworks", "networkuri", "subnetworkuri"}
# Nombres que da GKE: nodos y firewalls del clúster (gke-), NEG y balanceadores de Services e
# Ingress (k8s-, k8s1-, k8s2-), discos de PersistentVolumeClaim (pvc-<uuid>) y reglas de
# reenvío de un Service LoadBalancer (a<32 hex>).
GKE_NAME = re.compile(r"^(gke-|k8s[0-9]?-|pvc-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$|a[0-9a-f]{31}$)")
# NEG y balanceadores de GKE: k8s<n>-<uid de 8>-<namespace>-<servicio>-<puerto>-<hash>.
K8S_NAMESPACED = re.compile(r"^k8s[0-9]?-[0-9a-f]{8}-(.+)$")


def state_of(asset):
    return str(asset.get("state") or "").upper()


def _dict(value):
    return value if isinstance(value, dict) else {}


def _last_segment(name):
    return name.rstrip("/").rsplit("/", 1)[-1] if isinstance(name, str) else ""


def contains_marker(value, marker):
    """True si algún segmento de la ruta o del correo (sin el ID del proyecto) contiene marker."""
    return isinstance(value, str) and any(marker in s for s in names.segments(value))


def _network_refs(value):
    """Cadenas bajo llaves de red o subred (NETWORK_KEYS), en dicts y listas anidados."""
    if isinstance(value, dict):
        for k, v in value.items():
            if str(k).lower() in NETWORK_KEYS:
                for item in (v if isinstance(v, list) else [v]):
                    if isinstance(item, str):
                        yield item
            else:
                yield from _network_refs(v)
    elif isinstance(value, list):
        for v in value:
            yield from _network_refs(v)


def _description_json(asset):
    try:
        value = json.loads(asset.get("description") or "")
    except (TypeError, ValueError):
        return {}
    return value if isinstance(value, dict) else {}


def _namespaces(description):
    """Namespaces de Kubernetes que nombra la descripción en JSON de un recurso de GKE."""
    out = []
    for k, v in description.items():
        if not isinstance(v, str):
            continue
        if k.lower().endswith("namespace"):  # namespace, kubernetes.io/created-for/pvc/namespace
            out.append(v)
        elif k == "kubernetes.io/service-name" and "/" in v:  # <namespace>/<servicio>
            out.append(v.split("/", 1)[0])
    return out


def env_reason(asset, env, prefix):
    """Por qué el recurso es del entorno env (texto corto), o None si no lo es."""
    marker = "%s-%s-" % (prefix, env)
    labels = _dict(asset.get("labels"))
    if labels.get("env") == env:
        return "etiqueta env"
    extra = _dict(asset.get("additionalAttributes"))
    if any(contains_marker(v, marker) for v in (asset.get("name"), asset.get("displayName"), extra.get("email"))):
        return "nombre"
    for key in sorted(labels):
        if key != "env" and isinstance(labels[key], str) and marker in labels[key]:
            return "etiqueta %s" % key
    # La red solo cuenta para lo que crea GKE: las rutas y reglas que GCP crea en un spoke que se
    # conserva (incluir_red = false) también están en esa red y no son huérfanos.
    versioned = [_dict(v).get("resource") for v in asset.get("versionedResources") or [] if isinstance(v, dict)]
    if looks_like_gke(asset) and any(contains_marker(ref, marker) for ref in _network_refs([extra, versioned])):
        return "red del spoke"
    description = _description_json(asset)
    if any(ns.endswith("-" + env) for ns in _namespaces(description)):
        return "namespace de GKE en la descripción"
    if any(isinstance(v, str) and marker in v for v in description.values()):
        return "descripción de GKE"
    m = K8S_NAMESPACED.match(_last_segment(asset.get("name")))
    if m and ("-%s-" % env) in m.group(1):
        return "namespace de GKE en el nombre"
    return None


def looks_like_gke(asset):
    """True si el recurso parece creado por GKE (etiquetas, nombre o descripción)."""
    if any(str(k).startswith(("goog-gke-", "goog-k8s-")) for k in _dict(asset.get("labels"))):
        return True
    if GKE_NAME.match(_last_segment(asset.get("name"))):
        return True
    return any(str(k).startswith("kubernetes.io/") or k == "cluster-uid" for k in _description_json(asset))


def classify(assets, env, prefix, project_number, managed, parents, mig_patterns, aliases):
    """(esperados, huérfanos, restos de GKE sin entorno, otros)."""
    expected, orphans, gke_unknown, others = [], [], [], 0
    for a in assets:
        atype = a.get("assetType", "")
        why = None if atype == unmanaged.PROJECT_ASSET_TYPE else env_reason(a, env, prefix)
        if not why:
            if (atype != unmanaged.PROJECT_ASSET_TYPE and state_of(a) not in GONE_STATES and looks_like_gke(a)
                    and not any(env_reason(a, other, prefix) for other in KNOWN_ENVS if other != env)):
                gke_unknown.append({"assetType": atype, "name": a["name"], "state": state_of(a)})
            else:
                others += 1
            continue
        entry = {"assetType": atype, "name": a["name"], "state": state_of(a), "why": why}
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
    return expected, orphans, gke_unknown, others


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

    expected, orphans, gke_unknown, others = classify(assets, args.env, args.prefix, args.project_number,
                                                      managed, parents, mig_patterns, aliases)
    key = lambda e: (e["assetType"], e["name"])  # noqa: E731
    print("recursos en el proyecto %s: %d (del entorno %s: %d; restos de GKE sin entorno: %d; otros: %d)"
          % (args.project, len(assets), args.env, len(expected) + len(orphans), len(gke_unknown), others))
    print("  esperados: %d" % len(expected))
    print("  HUÉRFANOS: %d" % len(orphans))
    print("  restos de GKE sin entorno (aviso, revisar a mano): %d" % len(gke_unknown))
    for e in sorted(expected, key=key):
        print("ESPERADO %s %s (%s)" % (e["assetType"], e["name"], e["reason"]))
    for e in sorted(orphans, key=key):
        print("HUERFANO %s %s%s" % (e["assetType"], e["name"], " [%s]" % e["state"] if e["state"] else ""))
    for e in sorted(gke_unknown, key=key):
        print("AVISO-GKE %s %s%s" % (e["assetType"], e["name"], " [%s]" % e["state"] if e["state"] else ""))

    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as out:
            out.write("- Recursos del entorno `%s` en el proyecto `%s`: %d (esperados %d, **huérfanos %d**); "
                      "restos de GKE sin entorno: %d; otros recursos del proyecto: %d\n\n"
                      % (args.env, args.project, len(expected) + len(orphans), len(expected), len(orphans),
                         len(gke_unknown), others))
            if orphans:
                out.write("| Huérfano | Nombre | Estado | Del entorno por |\n|---|---|---|---|\n")
                for e in sorted(orphans, key=key):
                    out.write("| `%s` | `%s` | %s | %s |\n" % (e["assetType"], e["name"], e["state"] or "—", e["why"]))
                out.write("\n")
            if gke_unknown:
                out.write("Restos de GKE que no se pueden atribuir a ningún entorno (pueden ser de este o de un "
                          "clúster vivo de otro; no hacen fallar el trabajo, revisarlos a mano):\n\n"
                          "| Aviso | Nombre | Estado |\n|---|---|---|\n")
                for e in sorted(gke_unknown, key=key):
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
