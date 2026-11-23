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
# Carpeta de dev: folders/222222222222, con los proyectos example-dev-app y example-dev-data
# (4-projects.state.json); 4-projects-qa.state.json tiene un proyecto de otra carpeta.
u="$DATA/unmanaged"
um() { "$PY" scripts/unmanaged-resources.py --folder folders/222222222222 "$@"; }
dev_states=(--state "$u/4-projects.state.json" --state "$u/4-projects-qa.state.json")
um --assets "$u/assets.json" "${dev_states[@]}" \
  --state "$u/5-workloads.show.json" --state "$u/2-security.state.json" \
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
um --assets "$u/assets.json" "${dev_states[@]}" \
  --state "$u/5-workloads.show.json" --state "$u/2-security.state.json" \
  --report-only >/dev/null 2>&1
check "unmanaged-resources: --report-only sale con 0" 0 $?
# Sin el estado de 5-workloads, sus recursos pasan a no administrados (la comparación depende
# de los estados, no de la lista de permitidos).
um --assets "$u/assets.json" "${dev_states[@]}" --state "$u/2-security.state.json" >"$tmp/out2.txt" 2>&1
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
  um --assets "$tmp/a-$a.json" "${dev_states[@]}" --report-only >/dev/null 2>&1
  check "unmanaged-resources: listado $a es error aunque haya --report-only" 2 $?
done
um --assets "$u/assets-otra-carpeta.json" "${dev_states[@]}" --state "$u/2-security.state.json" >/dev/null 2>&1
check "unmanaged-resources: listado de una carpeta ajena es error" 2 $?
# Listado de la carpeta de qa con --folder de dev: trae un proyecto administrado (de qa), pero
# faltan los de dev.
um --assets "$u/assets-qa.json" "${dev_states[@]}" --report-only >/dev/null 2>&1
check "unmanaged-resources: listado de la carpeta de otro entorno es error" 2 $?
# Listado truncado: solo uno de los dos proyectos de dev.
"$PY" -c '
import json, sys
a = json.load(open(sys.argv[1], encoding="utf-8"))
a = [x for x in a if not x["name"].endswith("/projects/111111111112")]
json.dump(a, open(sys.argv[2], "w", encoding="utf-8"))
' "$u/assets.json" "$tmp/a-truncado.json"
um --assets "$tmp/a-truncado.json" "${dev_states[@]}" --state "$u/5-workloads.show.json" \
  --state "$u/2-security.state.json" --report-only >"$tmp/out-trunc.txt" 2>&1
check "unmanaged-resources: listado truncado (falta un proyecto del entorno) es error" 2 $?
grep -q 'example-dev-data' "$tmp/out-trunc.txt"
check "unmanaged-resources: el error nombra el proyecto que falta" 0 $?
"$PY" scripts/unmanaged-resources.py --folder folders/999 --assets "$u/assets.json" \
  "${dev_states[@]}" --report-only >/dev/null 2>&1
check "unmanaged-resources: --folder sin proyectos en los estados es error" 2 $?
# APIs habilitadas: las dependencias de la lista cerrada se permiten; otra API habilitada a
# mano (aiplatform) se reporta.
um --assets "$u/assets-apis.json" "${dev_states[@]}" >"$tmp/out3.txt" 2>&1
check "unmanaged-resources: una API habilitada a mano sale con 1" 1 $?
[ "$(grep '^NO ADMINISTRADO ' "$tmp/out3.txt")" = \
  "NO ADMINISTRADO serviceusage.googleapis.com/Service projects/111111111111/services/aiplatform.googleapis.com" ]
check "unmanaged-resources: solo la API manual sale; storage-api y containerfilesystem se permiten" 0 $?
# drift.yml pasa la carpeta del entorno al script.
grep -q -- '--folder "${folder}"' ../.github/workflows/drift.yml
check "drift.yml: pasa --folder con la carpeta del entorno" 0 $?

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
rc=$?
check "drift.yml: recursos no administrados en todas las carpetas de 1-org ($(cat "$tmp/drift-matrix.txt"))" 0 "$rc"

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
# Repositorio de "desarrollo" que publica en un remoto local; la ejecución corre en un clon (como
# el checkout de Actions). Historia de main:
#   A  gcp-datacenter/a.tf       (commit de la ejecución)
#   B  README.md                 (merge que no toca el despliegue)
#   C  gcp-datacenter/a.tf       (cambio de Terraform: A queda viejo)
#   D  .github/workflows/x.yml   (cambio de flujo: C queda viejo)
tip_script="${CHECK_MAIN_TIP_SCRIPT:-$PROJECT_DIR/scripts/check-main-tip.sh}" # otro script solo para comparar
r="$tmp/tip"
gitc() { git -C "$1" -c user.name=t -c user.email=t@example.com "${@:2}"; }
tip_commit() { # tip_commit <archivo> <mensaje>: commit en dev y push al remoto; imprime el sha
  mkdir -p "$r/dev/$(dirname "$1")"
  echo "$2" >>"$r/dev/$1"
  gitc "$r/dev" add -A && gitc "$r/dev" commit -q -m "$2" && git -C "$r/dev" push -q origin HEAD:main 2>/dev/null
  git -C "$r/dev" rev-parse HEAD
}
tip_run() { # tip_run <clon> <sha>: corre el script como en Actions; devuelve su código
  (cd "$1/gcp-datacenter" 2>/dev/null || cd "$1"; bash "$tip_script" "$2" >/dev/null 2>&1)
}
git init -q --bare "$r/remote.git"
git -C "$r/remote.git" symbolic-ref HEAD refs/heads/main
git init -q "$r/dev" && git -C "$r/dev" remote add origin "$r/remote.git"
git -C "$r/dev" checkout -q -b main
sha_a="$(tip_commit gcp-datacenter/a.tf A)"
git clone -q "file://$r/remote.git" "$r/run"
tip_run "$r/run" "$sha_a"
check "check-main-tip: la punta de main pasa" 0 $?
sha_b="$(tip_commit README.md B)"
tip_run "$r/run" "$sha_a"
check "check-main-tip: un merge que no toca gcp-datacenter/ ni .github/workflows/ no detiene la cadena" 0 $?
sha_c="$(tip_commit gcp-datacenter/a.tf C)"
tip_run "$r/run" "$sha_a"
check "check-main-tip: re-run de un commit viejo tras un cambio de Terraform falla" 1 $?
tip_run "$r/run" "$sha_b"
check "check-main-tip: el commit B también queda viejo tras C" 1 $?
tip_commit .github/workflows/x.yml D >/dev/null
tip_run "$r/run" "$sha_c"
check "check-main-tip: un cambio posterior en .github/workflows/ también deja viejo el commit" 1 $?
gitc "$r/dev" checkout -q -b lado "$sha_a"
echo lado >"$r/dev/gcp-datacenter/lado.tf"
gitc "$r/dev" add -A && gitc "$r/dev" commit -q -m lado-no-main
side="$(git -C "$r/dev" rev-parse HEAD)"
git -C "$r/dev" push -q origin lado 2>/dev/null
git -C "$r/run" fetch -q origin lado 2>/dev/null
tip_run "$r/run" "$side"
check "check-main-tip: un commit que no está en main falla" 1 $?
# Clon superficial (fetch-depth 1): completa la historia y decide bien.
git clone -q --depth 1 "file://$r/remote.git" "$r/shallow"
tip_run "$r/shallow" "$sha_a"
check "check-main-tip: con clon superficial completa la historia y decide (A viejo)" 1 $?
git clone -q --depth 1 "file://$r/remote.git" "$r/shallow2"
git -C "$r/shallow2" remote set-url origin "file://$r/no-existe.git"
tip_run "$r/shallow2" "$(git -C "$r/shallow2" rev-parse HEAD)"
check "check-main-tip: clon superficial con el remoto ilegible falla cerrado (2)" 2 $?
tip_run "$r/run" "0123456789012345678901234567890123456789"
check "check-main-tip: un sha desconocido es error (2)" 2 $?
# apply.yml se dispara con las mismas rutas que el script considera del despliegue: si no, un
# commit que deja vieja a una ejecución no traería otra que la retome.
"$PY" -c '
import re, sys
wf = open(sys.argv[1], encoding="utf-8").read()
push = wf[wf.index("  push:"):wf.index("  workflow_dispatch:")]
trigger = {p.rstrip("*").rstrip("/") for p in re.findall(r"^\s*-\s*\"([^\"]+)\"", push, re.M)}
sh = open(sys.argv[2], encoding="utf-8").read()
deploy = set(re.search(r"DEPLOY_PATHS:-([^}]*)\}", sh).group(1).split())
print("disparo %s, script %s" % (sorted(trigger), sorted(deploy)))
sys.exit(0 if trigger == deploy else 1)
' ../.github/workflows/apply.yml scripts/check-main-tip.sh >"$tmp/paths.txt" 2>&1
rc=$?
check "check-main-tip: apply.yml se dispara con las rutas del despliegue ($(cat "$tmp/paths.txt"))" 0 "$rc"
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

# CODEOWNERS: lo que decide si un cambio pasa o se despliega es solo de seguridad (gana la
# última línea que coincide; aquí solo hay patrones de directorio y de archivo anclados).
"$PY" -c '
import sys
rules = []
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.split("#", 1)[0].strip()
    if line:
        pattern, *owners = line.split()
        rules.append((pattern, owners))
def owners(path):
    found = None
    for pattern, o in rules:
        if pattern == "*" or path == pattern or (pattern.endswith("/") and path.startswith(pattern)):
            found = o
    return found
need = ["/.github/workflows/pr.yml", "/.github/CODEOWNERS", "/gcp-datacenter/scripts/plan-gate.sh",
        "/gcp-datacenter/policies/required_labels.rego", "/gcp-datacenter/stages/0-bootstrap/wif.tf",
        "/gcp-datacenter/.checkov.yaml", "/gcp-datacenter/.tflint.hcl",
        "/gcp-datacenter/tests/e2e/smoke_test.go"]
bad = [p for p in need if owners(p) != ["@PENDIENTE-seguridad"]]
print(", ".join(bad))
sys.exit(1 if bad else 0)
' ../.github/CODEOWNERS >"$tmp/owners.txt" 2>&1
rc=$?
check "CODEOWNERS: flujos, scripts, políticas, 0-bootstrap, .checkov.yaml, .tflint.hcl y tests/e2e solo de seguridad $(cat "$tmp/owners.txt")" 0 "$rc"

# docs/pipeline.md §4 nombra los ajustes de GitHub sin los que la revisión no protege la
# compuerta (aprobaciones viejas, último push, sin excepciones) y explica por qué.
missing_doc=""
for s in "Dismiss stale pull request approvals" "Require approval of the most recent reviewable push" \
  "Do not allow bypassing" "merge commit del PR" "checkov:skip"; do
  grep -qF "$s" docs/pipeline.md || missing_doc="${missing_doc} [${s}]"
done
[ -z "$missing_doc" ]
rc=$?
check "docs/pipeline.md §4: ajustes de protección y guía de revisión${missing_doc:+ (faltan:$missing_doc)}" 0 "$rc"

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
