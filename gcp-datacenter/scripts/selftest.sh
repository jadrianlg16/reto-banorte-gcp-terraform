#!/usr/bin/env bash
# Pruebas sin GCP de los scripts que usan los flujos (datos de prueba en scripts/testdata/):
#   unmanaged-resources.py  recursos de Cloud Asset que no están en los estados
#   go-test-report.sh       conteo de pruebas omitidas de go test -json
#   module-tests.sh         pruebas de integración de cada módulo
#   plan-fingerprint.py     huella del plan revisado (apply.yml)
#   cut-plan.py             recorte de planes para policies/fixtures
#
# Uso: scripts/selftest.sh   (sale con 1 si algo no da lo esperado)
# Requiere python3 (o PYTHON con la ruta del intérprete). Compatible con bash 3.2.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR" || exit 2
PY="${PYTHON:-python3}"
DATA="scripts/testdata"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fails=0
check() { # check <descripción> <código esperado> <código obtenido>
  if [ "$2" = "$3" ]; then
    echo "OK    $1"
  else
    echo "FALLA $1 (código esperado $2, obtenido $3)"
    fails=$((fails + 1))
  fi
}

# --- unmanaged-resources.py ----------------------------------------------------------------
u="$DATA/unmanaged"
"$PY" scripts/unmanaged-resources.py --assets "$u/assets.json" \
  --state "$u/4-projects.state.json" --state "$u/5-workloads.show.json" --state "$u/2-security.state.json" \
  --summary "$tmp/summary.md" >"$tmp/out.txt" 2>&1
check "unmanaged-resources: sale con 1 si hay recursos no administrados" 1 $?
grep '^NO ADMINISTRADO ' "$tmp/out.txt" >"$tmp/got.txt"
if diff -u "$u/expected.txt" "$tmp/got.txt"; then
  echo "OK    unmanaged-resources: exactamente los 4 recursos manuales esperados"
else
  echo "FALLA unmanaged-resources: la lista de no administrados no coincide"
  cat "$tmp/out.txt"
  fails=$((fails + 1))
fi
grep -q '| \*\*No administrados\*\* | 4 |' "$tmp/summary.md"
check "unmanaged-resources: resumen en Markdown con el conteo" 0 $?
"$PY" scripts/unmanaged-resources.py --assets "$u/assets.json" \
  --state "$u/4-projects.state.json" --state "$u/5-workloads.show.json" --state "$u/2-security.state.json" \
  --report-only >/dev/null 2>&1
check "unmanaged-resources: --report-only sale con 0" 0 $?
# Sin el estado de 5-workloads, sus recursos pasan a no administrados (la comparación depende
# de los estados, no de la lista de permitidos).
"$PY" scripts/unmanaged-resources.py --assets "$u/assets.json" \
  --state "$u/4-projects.state.json" --state "$u/2-security.state.json" >"$tmp/out2.txt" 2>&1
n="$(grep -c '^NO ADMINISTRADO ' "$tmp/out2.txt")"
# 4 manuales + 7 de 5-workloads: bucket, plantilla, MIG, su VM y su disco, clúster y node pool.
check "unmanaged-resources: sin un estado, sus recursos salen como no administrados (11)" 11 "$n"
# Listados que no permiten concluir nada: error (2), nunca "0 no administrados" con 0, ni
# siquiera con --report-only.
printf '[]' >"$tmp/a-lista-vacia.json"
printf '{}' >"$tmp/a-objeto-vacio.json"
printf '{"results": []}' >"$tmp/a-results-vacio.json"
printf '{"nextPageToken": "x"}' >"$tmp/a-sin-results.json"
printf '[{"assetType": "storage.googleapis.com/Bucket"}]' >"$tmp/a-sin-name.json"
for a in lista-vacia objeto-vacio results-vacio sin-results sin-name; do
  "$PY" scripts/unmanaged-resources.py --assets "$tmp/a-$a.json" --state "$u/4-projects.state.json" \
    --report-only >/dev/null 2>&1
  check "unmanaged-resources: listado $a es error aunque haya --report-only" 2 $?
done
"$PY" scripts/unmanaged-resources.py --assets "$u/assets-otra-carpeta.json" \
  --state "$u/4-projects.state.json" --state "$u/2-security.state.json" >/dev/null 2>&1
check "unmanaged-resources: listado sin ningún proyecto de los estados (otra carpeta) es error" 2 $?
# APIs habilitadas: las dependencias de la lista cerrada se permiten; otra API habilitada a
# mano (aiplatform) se reporta.
"$PY" scripts/unmanaged-resources.py --assets "$u/assets-apis.json" \
  --state "$u/4-projects.state.json" >"$tmp/out3.txt" 2>&1
check "unmanaged-resources: una API habilitada a mano sale con 1" 1 $?
[ "$(grep '^NO ADMINISTRADO ' "$tmp/out3.txt")" = \
  "NO ADMINISTRADO serviceusage.googleapis.com/Service projects/111111111111/services/aiplatform.googleapis.com" ]
check "unmanaged-resources: solo la API manual sale; storage-api y containerfilesystem se permiten" 0 $?

# drift.yml revisa cada carpeta que crea 1-org (local environment + environments).
"$PY" -c '
import re, sys
tf = open("stages/1-org/main.tf", encoding="utf-8").read()
folders = set(re.findall(r"^\s*environment\s*=\s*\"([a-z]+)\"", tf, re.M))
m = re.search(r"^\s*environments\s*=\s*\[([^\]]*)\]", tf, re.M)
folders |= set(re.findall(r"\"([a-z]+)\"", m.group(1)))
wf = open("../.github/workflows/drift.yml", encoding="utf-8").read()
job = wf[wf.index("\n  unmanaged:"):]
matrix = set(re.search(r"^\s*env:\s*\[([^\]]*)\]", job, re.M).group(1).replace(" ", "").split(","))
print("carpetas de 1-org: %s; matriz de drift.yml: %s" % (sorted(folders), sorted(matrix)))
sys.exit(0 if folders and folders == matrix else 1)
' >"$tmp/drift-matrix.txt" 2>&1
check "drift.yml: recursos no administrados en todas las carpetas de 1-org ($(cat "$tmp/drift-matrix.txt"))" 0 $?

# --- go-test-report.sh ---------------------------------------------------------------------
g="$DATA/go-test"
bash scripts/go-test-report.sh "$g/tres-omitidas.json" 0 >/dev/null 2>&1
check "go-test-report: 3 omitidas con máximo 0 falla" 1 $?
bash scripts/go-test-report.sh "$g/tres-omitidas.json" 3 "$tmp/go.md" >/dev/null 2>&1
check "go-test-report: 3 omitidas con máximo 3 pasa" 0 $?
grep -q 'TestGKE' "$tmp/go.md"
check "go-test-report: el resumen lista las omitidas" 0 $?
bash scripts/go-test-report.sh "$g/una-falla.json" 99 >/dev/null 2>&1
check "go-test-report: una prueba fallida falla aunque no haya omitidas" 1 $?
bash scripts/go-test-report.sh "$g/tres-omitidas.json" x >/dev/null 2>&1
check "go-test-report: máximo inválido es error de uso" 2 $?

# --- module-tests.sh -----------------------------------------------------------------------
got="$(bash scripts/module-tests.sh firewall 2>/dev/null)"
[ "$got" = '^(TestFirewallHierarchical|TestFirewallNetwork)$' ]
check "module-tests: firewall incluye la variante jerárquica" 0 $?
missing=0
for d in modules/*/; do
  m="$(basename "$d")"
  bash scripts/module-tests.sh "$m" >/dev/null 2>&1 || {
    echo "      sin pruebas de integración: $m"
    missing=$((missing + 1))
  }
done
check "module-tests: los $(ls -d modules/*/ | wc -l | tr -d ' ') módulos tienen pruebas de integración" 0 "$missing"
bash scripts/module-tests.sh no-existe >/dev/null 2>&1
check "module-tests: un módulo inexistente falla" 1 $?

# --- plan-fingerprint.py -------------------------------------------------------------------
# compute-mig-a y -b: dos planes reales del mismo ejemplo (scripts/plan-offline.sh), con
# distinta fecha y orden de relevant_attributes.
fa="$("$PY" scripts/plan-fingerprint.py "$DATA/fingerprint/compute-mig-a.json")"
fb="$("$PY" scripts/plan-fingerprint.py "$DATA/fingerprint/compute-mig-b.json")"
[ -n "$fa" ] && [ "$fa" = "$fb" ]
check "plan-fingerprint: dos planes reales de la misma configuración dan la misma huella" 0 $?
"$PY" -c '
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
for rc in p["resource_changes"]:
    if rc["type"] == "google_compute_region_instance_template":
        rc["change"]["after"]["machine_type"] = "e2-standard-8"
json.dump(p, open(sys.argv[2], "w", encoding="utf-8"))
' "$DATA/fingerprint/compute-mig-a.json" "$tmp/changed.json"
fc="$("$PY" scripts/plan-fingerprint.py "$tmp/changed.json")"
[ -n "$fc" ] && [ "$fc" != "$fa" ]
check "plan-fingerprint: un valor planeado distinto cambia la huella" 0 $?

# --- cut-plan.py ---------------------------------------------------------------------------
# Plan con texto no ASCII (descripciones en español): la salida debe ser UTF-8 y, al recortar
# un recorte, idéntica byte a byte (con la codificación de la consola de Windows no lo era).
f="policies/fixtures/shielded_vm_pass_real_gke.json"
"$PY" scripts/cut-plan.py "$f" 'module\.gke\..*' >"$tmp/cut.json"
check "cut-plan: recorta un plan" 0 $?
"$PY" -c '
import sys
a = open(sys.argv[1], "rb").read()
b = open(sys.argv[2], "rb").read()
b.decode("utf-8")
sys.exit(0 if a == b and any(c > 127 for c in a) else 1)
' "$f" "$tmp/cut.json" 2>/dev/null
check "cut-plan: recortar un recorte con texto no ASCII da los mismos bytes UTF-8" 0 $?
"$PY" scripts/cut-plan.py "$f" 'no\.coincide' >/dev/null 2>&1
check "cut-plan: una expresión sin coincidencias falla" 1 $?

# --- check-main-tip.sh ---------------------------------------------------------------------
# Remoto local con dos commits en main: el primero ya no es la punta (re-run de una ejecución
# vieja), el segundo sí.
r="$tmp/tip"
git init -q -b main "$r/work" >/dev/null 2>&1 || { git init -q "$r/work" && git -C "$r/work" checkout -q -b main; }
git -C "$r/work" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m uno
old_sha="$(git -C "$r/work" rev-parse HEAD)"
git -C "$r/work" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m dos
new_sha="$(git -C "$r/work" rev-parse HEAD)"
git clone -q --bare "$r/work" "$r/remote.git"
bash scripts/check-main-tip.sh "$new_sha" "$r/remote.git" main >/dev/null 2>&1
check "check-main-tip: la punta de main pasa" 0 $?
bash scripts/check-main-tip.sh "$old_sha" "$r/remote.git" main >/dev/null 2>&1
check "check-main-tip: un commit viejo (re-run tras avanzar main) falla" 1 $?
bash scripts/check-main-tip.sh "$new_sha" "$r/no-existe.git" main >/dev/null 2>&1
check "check-main-tip: un remoto ilegible es error, no pasa" 2 $?
n="$(grep -c 'scripts/check-main-tip.sh "${GITHUB_SHA}"' ../.github/workflows/_terraform-root.yml)"
check "check-main-tip: _terraform-root.yml lo llama en plan y antes del apply (2)" 2 "$n"
# Orden en el trabajo apply: la comprobación va después de volver a planear y antes del apply.
"$PY" -c '
import sys
t = open(sys.argv[1], encoding="utf-8").read()
apply_job = t[t.index("\n  apply:"):]
a = apply_job.index("check-main-tip.sh")
b = apply_job.index("terraform apply -input=false")
sys.exit(0 if a < b else 1)
' ../.github/workflows/_terraform-root.yml
check "check-main-tip: en el trabajo apply va antes de terraform apply" 0 $?

# Variables de entorno de GitHub: el apply compara la huella de las variables con la del plan
# y el mensaje de huella distinta nombra las variables de repositorio.
"$PY" -c '
import sys
t = open(sys.argv[1], encoding="utf-8").read()
plan_job = t[t.index("\n  plan:"):t.index("\n  apply:")]
apply_job = t[t.index("\n  apply:"):]
ok = ("vars_fingerprint: ${{ steps.vars.outputs.fingerprint }}" in plan_job
      and "PLAN_VARS_FINGERPRINT: ${{ needs.plan.outputs.vars_fingerprint }}" in apply_job
      and apply_job.index("PLAN_VARS_FINGERPRINT") < apply_job.index("terraform init")
      and "sean variables de repositorio" in apply_job)
sys.exit(0 if ok else 1)
' ../.github/workflows/_terraform-root.yml
check "_terraform-root: el apply compara las variables con las del plan antes de init" 0 $?

# --- plan-gate.sh --------------------------------------------------------------------------
gate() { # gate <descripción> <código esperado> VAR=valor...
  local desc="$1" want="$2"
  shift 2
  env -i PATH="$PATH" SUMMARY="$tmp/gate.md" "$@" bash scripts/plan-gate.sh >/dev/null 2>&1
  check "plan-gate: $desc" "$want" $?
}
gate "GCP apagado y sin fork pasa" 0 GCP_ENABLED= AFFECTED=skipped PLAN=skipped IS_FORK=false
gate "planes con éxito pasan" 0 GCP_ENABLED=true AFFECTED=success ROOTS='[{"root":"stages/1-org"}]' PLAN=success IS_FORK=false
gate "un plan fallido falla" 1 GCP_ENABLED=true AFFECTED=success ROOTS='[{"root":"stages/1-org"}]' PLAN=failure IS_FORK=false
gate "sin raíces afectadas y plan omitido pasa" 0 GCP_ENABLED=true AFFECTED=success ROOTS='[]' PLAN=skipped IS_FORK=false
gate "con GCP, plan omitido habiendo raíces falla" 1 GCP_ENABLED=true AFFECTED=success ROOTS='[{"root":"stages/1-org"}]' PLAN=skipped IS_FORK=false
# Fork: las variables pueden no llegar (GCP_ENABLED vacío) y el plan se omite.
gate "fork que toca raíces falla aunque GCP_ENABLED llegue vacío" 1 GCP_ENABLED= AFFECTED=success ROOTS='[{"root":"stages/1-org"}]' PLAN=skipped IS_FORK=true
gate "fork que toca raíces falla con GCP_ENABLED=true" 1 GCP_ENABLED=true AFFECTED=success ROOTS='[{"root":"stages/1-org"}]' PLAN=skipped IS_FORK=true
gate "fork sin raíces afectadas pasa" 0 GCP_ENABLED= AFFECTED=success ROOTS='[]' PLAN=skipped IS_FORK=true
gate "fork sin raíces calculadas falla" 1 GCP_ENABLED= AFFECTED=skipped PLAN=skipped IS_FORK=true
grep -q 'fork' "$tmp/gate.md"
check "plan-gate: el resumen explica el motivo del fork" 0 $?

# --- policies/fixtures: UTF-8 y JSON válidos ------------------------------------------------
bad="$("$PY" -c '
import glob, json, sys
bad = []
for p in sorted(glob.glob("policies/fixtures/*.json")):
    try:
        json.loads(open(p, "rb").read().decode("utf-8"))
    except Exception as exc:
        bad.append("%s: %s" % (p, exc))
print("\n".join(bad))
')"
[ -z "$bad" ]
check "policies/fixtures: todos los planes de ejemplo son JSON en UTF-8 válido" 0 $?
[ -n "$bad" ] && printf '      %s\n' "$bad"

echo
if [ "$fails" -gt 0 ]; then
  echo "RESULTADO: ${fails} comprobación(es) fallaron." >&2
  exit 1
fi
echo "RESULTADO: todas las comprobaciones pasaron."
