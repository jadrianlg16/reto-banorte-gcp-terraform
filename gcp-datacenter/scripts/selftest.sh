#!/usr/bin/env bash
# Pruebas sin GCP de los scripts que usan los flujos (datos de prueba en scripts/testdata/):
#   unmanaged-resources.py  recursos de Cloud Asset que no están en los estados
#   go-test-report.sh       conteo de pruebas omitidas de go test -json
#   module-tests.sh         pruebas de integración de cada módulo
#   plan-fingerprint.py     huella del plan revisado (apply.yml)
#   cut-plan.py             recorte de planes para policies/fixtures
#   destroy-guard.sh, destroy-plan-check.py, destroy-orphans.py   destroy.yml
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
sha_d="$(tip_commit .github/workflows/x.yml D)"
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
# Merge que descarta los cambios C y D (resuelto a favor de una rama vieja que salió de B): el
# contenido de las rutas en la punta es igual al de esa rama, `git log -- <rutas>` simplifica la
# historia siguiendo solo a ese padre y no lista ningún commit posterior a D, pero lo que se
# desplegaría ya es otro. Lo detecta la comparación de árboles (git diff).
gitc "$r/dev" checkout -q -b vieja "$sha_b" 2>/dev/null
echo vieja >"$r/dev/otro.txt"
gitc "$r/dev" add -A 2>/dev/null && gitc "$r/dev" commit -q -m vieja-fuera-de-las-rutas
gitc "$r/dev" checkout -q main 2>/dev/null
gitc "$r/dev" merge -q --no-ff --no-commit vieja >/dev/null 2>&1
gitc "$r/dev" checkout -q vieja -- gcp-datacenter 2>/dev/null
gitc "$r/dev" rm -r -q .github/workflows >/dev/null 2>&1
gitc "$r/dev" commit -q -m "merge que descarta C y D" && git -C "$r/dev" push -q origin HEAD:main 2>/dev/null
[ "$(git -C "$r/dev" rev-list --count "$sha_d..HEAD")" -ge 2 ] &&
  [ -z "$(git -C "$r/dev" log --format=%h "$sha_d..HEAD" -- gcp-datacenter .github/workflows)" ]
check "check-main-tip: (preparación) el log de las rutas no lista el merge que descarta C y D" 0 $?
tip_run "$r/run" "$sha_d"
check "check-main-tip: un merge que descarta cambios de las rutas deja viejo el commit (diff de árboles)" 1 $?
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

# --- destroy.yml: destroy-guard.sh, destroy-plan-check.py y destroy-orphans.py -------------
d="$DATA/destroy"
guard() { # guard <descripción> <código esperado> <argumentos...>
  local desc="$1" want="$2"
  shift 2
  bash scripts/destroy-guard.sh "$@" >"$tmp/guard.txt" 2>&1
  check "destroy-guard: $desc" "$want" $?
}
guard "pedido de dev confirmado desde main pasa" 0 pedido dev dev refs/heads/main
guard "pedido de qa confirmado desde main pasa" 0 pedido qa qa refs/heads/main
guard "pedido de prod se rechaza" 1 pedido prod prod refs/heads/main
grep -q 'prod no se destruye' "$tmp/guard.txt"
check "destroy-guard: el rechazo de prod lo dice explícitamente" 0 $?
guard "PROD en mayúsculas se rechaza como prod" 1 pedido PROD PROD refs/heads/main
grep -q 'prod no se destruye' "$tmp/guard.txt"
check "destroy-guard: PROD se reconoce como prod" 0 $?
guard "' prod' con espacio se rechaza" 1 pedido " prod" " prod" refs/heads/main
guard "otro entorno (common) se rechaza" 1 pedido common common refs/heads/main
guard "entorno vacío se rechaza" 1 pedido "" "" refs/heads/main
guard "confirmación de otro entorno se rechaza" 1 pedido dev qa refs/heads/main
grep -q 'Confirmación incorrecta' "$tmp/guard.txt"
check "destroy-guard: el rechazo nombra la confirmación incorrecta" 0 $?
guard "confirmación vacía se rechaza" 1 pedido dev "" refs/heads/main
guard "confirmación con espacio final se rechaza" 1 pedido dev "dev " refs/heads/main
guard "confirmación en mayúsculas se rechaza" 1 pedido dev DEV refs/heads/main
guard "pedido desde otra rama se rechaza" 1 pedido dev dev refs/heads/feat/x
guard "raíz de 5-workloads de dev pasa" 0 raiz dev stages/5-workloads/envs/dev
guard "raíz de 4-projects de qa pasa" 0 raiz qa stages/4-projects/envs/qa
guard "raíz de 3-networks de qa pasa" 0 raiz qa stages/3-networks/envs/qa
guard "raíz de prod se rechaza" 1 raiz prod stages/5-workloads/envs/prod
guard "raíz de prod con entorno dev se rechaza" 1 raiz dev stages/5-workloads/envs/prod
guard "raíz de otro entorno se rechaza" 1 raiz dev stages/4-projects/envs/qa
guard "hub de 3-networks se rechaza" 1 raiz dev stages/3-networks
guard "1-org se rechaza" 1 raiz dev stages/1-org
guard "ruta con .. se rechaza" 1 raiz dev stages/5-workloads/envs/dev/../prod
guard "sin argumentos es error de uso" 2
guard "modo desconocido es error de uso" 2 todo dev dev refs/heads/main

# Planes de destrucción reales sin GCP (Terraform 1.16.5, 23 nov 2026): plan-real-dev y
# plan-real-protegido son `plan -destroy -refresh=false` con google 6.50.0 sobre un estado
# escrito a mano (token ficticio: el proveedor no llama a las API para planear un borrado);
# plan-real-terraform-data-a y -b, dos `plan -destroy` del mismo estado con recursos integrados.
pc() { "$PY" scripts/destroy-plan-check.py "$@"; }
pc "$d/plan-real-dev.json" --summary "$tmp/destroy.md" --root stages/5-workloads/envs/dev >"$tmp/pc.txt" 2>&1
check "destroy-plan-check: dev con protecciones apagadas y DELETE pasa" 0 $?
[ "$(grep -c '^AVISO ' "$tmp/pc.txt")" = 3 ] && grep -q 'google_backup_dr_backup_vault' "$tmp/pc.txt" &&
  grep -q 'google_service_networking_connection' "$tmp/pc.txt" && grep -q 'google_storage_bucket' "$tmp/pc.txt"
check "destroy-plan-check: avisa de la bóveda, la conexión de PSA y el bucket sin force_destroy (3)" 0 $?
grep -q 'Recursos que se destruyen: 6' "$tmp/destroy.md"
check "destroy-plan-check: resumen en Markdown con los recursos que se destruyen" 0 $?
pc "$d/plan-real-protegido.json" >"$tmp/pc2.txt" 2>&1
check "destroy-plan-check: protecciones en el estado detienen el destroy (1)" 1 $?
grep '^BLOQUEO ' "$tmp/pc2.txt" | sed 's/: .*//' >"$tmp/bloqueos.txt"
if diff -u "$d/bloqueos-esperados.txt" "$tmp/bloqueos.txt"; then
  echo "OK    destroy-plan-check: exactamente los 6 bloqueos (deletion_protection, settings, Filestore, GKE, PREVENT, ABANDON)"
else
  echo "FALLA destroy-plan-check: la lista de bloqueos no coincide"
  fails=$((fails + 1))
fi
grep -q 'backup_count 3).*FALLA' "$tmp/pc2.txt"
check "destroy-plan-check: con backup_count > 0 avisa que el borrado de la bóveda falla" 0 $?
pc "$d/plan-real-terraform-data-a.json" >/dev/null 2>&1
check "destroy-plan-check: plan de destrucción real de recursos integrados pasa" 0 $?
"$PY" -c '
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
p["resource_changes"][0]["change"]["actions"] = ["update"]
json.dump(p, open(sys.argv[2], "w", encoding="utf-8"))
' "$d/plan-real-dev.json" "$tmp/no-destroy.json"
pc "$tmp/no-destroy.json" >/dev/null 2>&1
check "destroy-plan-check: un plan con una acción que no es delete es error (2)" 2 $?
printf '{"resource_changes": {}}' >"$tmp/rc-objeto.json"
pc "$tmp/rc-objeto.json" >/dev/null 2>&1
check "destroy-plan-check: resource_changes que no es lista es error (2)" 2 $?
printf 'no es json' >"$tmp/no-json.json"
pc "$tmp/no-json.json" >/dev/null 2>&1
check "destroy-plan-check: un archivo que no es JSON es error (2)" 2 $?
# La huella del plan también vale para planes de destrucción: dos planes del mismo estado, con
# distinta fecha, dan la misma huella.
fa="$("$PY" scripts/plan-fingerprint.py "$d/plan-real-terraform-data-a.json")"
fb="$("$PY" scripts/plan-fingerprint.py "$d/plan-real-terraform-data-b.json")"
[ -n "$fa" ] && [ "$fa" = "$fb" ] && ! cmp -s "$d/plan-real-terraform-data-a.json" "$d/plan-real-terraform-data-b.json"
check "plan-fingerprint: dos planes de destrucción reales distintos del mismo estado dan la misma huella" 0 $?

do_() { "$PY" scripts/destroy-orphans.py --folder folders/222222222222 "$@"; }
do_ --assets "$d/assets-esperados.json" --summary "$tmp/orphans.md" >"$tmp/do.txt" 2>&1
check "destroy-orphans: carpeta con proyectos en borrado, sus recursos y la carpeta misma pasa" 0 $?
[ "$(grep -c '^ESPERADO ' "$tmp/do.txt")" = 8 ]
check "destroy-orphans: lista los 8 esperados con su motivo" 0 $?
do_ --assets "$d/assets-huerfanos.json" --summary "$tmp/orphans.md" >"$tmp/do2.txt" 2>&1
check "destroy-orphans: un proyecto activo y sus recursos son huérfanos (1)" 1 $?
grep '^HUERFANO ' "$tmp/do2.txt" >"$tmp/huerfanos.txt"
if diff -u "$d/huerfanos-esperados.txt" "$tmp/huerfanos.txt"; then
  echo "OK    destroy-orphans: exactamente los 5 huérfanos esperados"
else
  echo "FALLA destroy-orphans: la lista de huérfanos no coincide"
  fails=$((fails + 1))
fi
grep -q 'huérfanos 5' "$tmp/orphans.md"
check "destroy-orphans: resumen en Markdown con el conteo" 0 $?
do_ --assets "$d/assets-huerfanos.json" --report-only >/dev/null 2>&1
check "destroy-orphans: --report-only sale con 0" 0 $?
printf '[]' >"$tmp/o-vacia.json"
do_ --assets "$tmp/o-vacia.json" >/dev/null 2>&1
check "destroy-orphans: carpeta vacía pasa" 0 $?
printf '{"results": []}' >"$tmp/o-results-vacio.json"
do_ --assets "$tmp/o-results-vacio.json" >/dev/null 2>&1
check "destroy-orphans: {\"results\": []} es carpeta vacía y pasa" 0 $?
for a in a-objeto-vacio a-sin-results a-sin-name; do
  do_ --assets "$tmp/$a.json" --report-only >/dev/null 2>&1
  check "destroy-orphans: listado ${a#a-} es error aunque haya --report-only" 2 $?
done
"$PY" scripts/destroy-orphans.py --folder dev --assets "$tmp/o-vacia.json" >/dev/null 2>&1
check "destroy-orphans: --folder que no es una carpeta es error" 2 $?

# Estructura de destroy.yml y del modo destroy de _terraform-root.yml.
"$PY" -c '
import re, sys
wf = open(sys.argv[1], encoding="utf-8").read()
apply_wf = open(sys.argv[2], encoding="utf-8").read()
root = open(sys.argv[3], encoding="utf-8").read()
bad = []
on = wf[wf.index("\non:"):wf.index("\npermissions:")]
triggers = set(re.findall(r"^  ([a-z_]+):", on, re.M))
if triggers != {"workflow_dispatch"}:
    bad.append("disparadores %s (solo workflow_dispatch)" % sorted(triggers))
opts = re.search(r"entorno:.*?options:\n((?:\s+- \S+\n)+)", on, re.S)
if not opts or re.findall(r"- (\S+)", opts.group(1)) != ["dev", "qa"]:
    bad.append("las opciones de entorno no son exactamente dev y qa")
group = lambda t: re.search(r"^concurrency:\n\s+group: (\S+)\n\s+cancel-in-progress: false", t, re.M)
if not group(wf) or not group(apply_wf) or group(wf).group(1) != group(apply_wf).group(1):
    bad.append("concurrency distinta de apply.yml (o con cancelación)")
if "destroy-guard.sh pedido" not in wf[wf.index("\n  gate:"):wf.index("\n  workloads:")]:
    bad.append("el trabajo gate no llama a destroy-guard.sh pedido")
order = [("workloads", "gate", "5-workloads"), ("projects", "workloads", "4-projects"),
         ("networks", "projects", "3-networks"), ("orphans", "networks", None)]
for job, need, stage in order:
    m = re.search(r"\n  %s:\n(.*?)(?=\n  [a-z]+:\n|\Z)" % job, wf, re.S)
    body = m.group(1) if m else ""
    cond = re.search(r"^    if: (.*)$", body, re.M)
    if not cond or "github.ref == \x27refs/heads/main\x27" not in cond.group(1) \
            or "vars.GCP_ENABLED == \x27true\x27" not in cond.group(1) \
            or "(inputs.entorno == \x27dev\x27 || inputs.entorno == \x27qa\x27)" not in cond.group(1):
        bad.append("%s: if sin main, sin GCP_ENABLED o sin limitar a dev y qa" % job)
    if "needs: %s\n" % need not in body:
        bad.append("%s no espera a %s" % (job, need))
    if stage:
        want = ["root: stages/%s/envs/${{ inputs.entorno }}" % stage, "stage: %s" % stage,
                "environment: ${{ inputs.entorno }}", "destroy: true", "uses: ./.github/workflows/_terraform-root.yml"]
        bad += ["%s sin \"%s\"" % (job, w) for w in want if w not in body]
    elif "vars.GCP_AUDIT_SERVICE_ACCOUNT" not in body or "destroy-orphans.py" not in body:
        bad.append("orphans sin la cuenta de auditoría o sin destroy-orphans.py")
for u in re.findall(r"uses: (\S+)", wf):
    if not u.startswith("./") and not re.search(r"@[0-9a-f]{40}$", u):
        bad.append("acción sin SHA completo: %s" % u)
plan_job = root[root.index("\n  plan:"):root.index("\n  apply:")]
apply_job = root[root.index("\n  apply:"):]
for name, job in (("plan", plan_job), ("apply", apply_job)):
    g = job.find("destroy-guard.sh raiz")
    if g < 0 or g > job.index("google-github-actions/auth") or g > job.index("terraform init"):
        bad.append("_terraform-root %s: destroy-guard.sh raiz falta o va después de autenticar" % name)
    if "destroy-plan-check.py" not in job:
        bad.append("_terraform-root %s: falta destroy-plan-check.py" % name)
    if "terraform plan \"${mode[@]}\"" not in job:
        bad.append("_terraform-root %s: el plan no recibe -destroy" % name)
if apply_job.index("destroy-plan-check.py") > apply_job.index("terraform apply -input=false"):
    bad.append("_terraform-root apply: destroy-plan-check.py después de terraform apply")
print("; ".join(bad))
sys.exit(1 if bad else 0)
' ../.github/workflows/destroy.yml ../.github/workflows/apply.yml ../.github/workflows/_terraform-root.yml >"$tmp/destroy-wf.txt" 2>&1
rc=$?
check "destroy.yml: solo manual, dev/qa, concurrencia de apply.yml, orden 5→4→3, guardias y SHA $(cat "$tmp/destroy-wf.txt")" 0 "$rc"

# Conftest sobre los planes de destrucción (las políticas no deben rechazar un plan sin `after`).
conftest_cmd="${CONFTEST_CMD:-$(command -v conftest 2>/dev/null || true)}"
[ -z "$conftest_cmd" ] && [ -x "$HOME/go/bin/conftest" ] && conftest_cmd="$HOME/go/bin/conftest"
[ -z "$conftest_cmd" ] && [ -x "$HOME/go/bin/conftest.exe" ] && conftest_cmd="$HOME/go/bin/conftest.exe"
if [ -n "$conftest_cmd" ]; then
  "$conftest_cmd" test "$d/plan-real-dev.json" "$d/plan-real-protegido.json" --policy policies --no-color >/dev/null 2>&1
  check "conftest: las políticas aceptan los planes de destrucción reales" 0 $?
else
  echo "INFO  conftest no está en el PATH: no se prueba Conftest sobre los planes de destrucción"
fi

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
