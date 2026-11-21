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
f="policies/fixtures/compute_public_ip_pass_real_mig_sin_stack_type.json"
"$PY" scripts/cut-plan.py "$f" 'module\.mig\..*' >"$tmp/cut.json"
check "cut-plan: recorta un plan" 0 $?
"$PY" -c 'import json,sys; a=json.load(open(sys.argv[1],encoding="utf-8")); b=json.load(open(sys.argv[2],encoding="utf-8")); sys.exit(0 if a==b else 1)' "$f" "$tmp/cut.json"
check "cut-plan: recortar un recorte no lo cambia" 0 $?
"$PY" scripts/cut-plan.py "$f" 'no\.coincide' >/dev/null 2>&1
check "cut-plan: una expresión sin coincidencias falla" 1 $?

echo
if [ "$fails" -gt 0 ]; then
  echo "RESULTADO: ${fails} comprobación(es) fallaron." >&2
  exit 1
fi
echo "RESULTADO: todas las comprobaciones pasaron."
