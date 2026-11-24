#!/usr/bin/env bash
# Pruebas sin GCP de los scripts que usan los flujos (datos de prueba en scripts/testdata/):
#   unmanaged-resources.py  recursos de Cloud Asset del proyecto que no están en los estados
#   affected-roots.sh       raíces que planea pr.yml (y drift.yml con --all)
#   root-tfvars.py          variables de cada raíz desde GCP_TFVARS_JSON
#   disabled-envs.py        entornos apagados con GCP_DISABLED_ENVS (apply.yml y drift.yml)
#   terratest-project-check.py   proyecto de Terratest distinto del de la landing zone
#   go-test-report.sh       conteo de pruebas omitidas de go test -json
#   module-tests.sh         pruebas de integración de cada módulo
#   plan-fingerprint.py     huella del plan revisado (apply.yml)
#   cut-plan.py             recorte de planes para policies/fixtures
#   check-main-tip.sh, plan-gate.sh
#   destroy-guard.sh, destroy-plan-check.py, destroy-orphans.py   destroy.yml
# y la estructura de los flujos que dependen de ellos (orden del ADR 0029 §2, cuentas del plan y
# del apply, destroy.yml).
#
# Uso: scripts/selftest.sh   (sale con 1 si algo no da lo esperado)
# Requiere python3 (o PYTHON con la ruta del intérprete) y git. Compatible con bash 3.2.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR" || exit 2
PY="${PYTHON:-python3}"
DATA="scripts/testdata"
WF="../.github/workflows"
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
gitc() { git -C "$1" -c user.name=t -c user.email=t@example.com -c core.autocrlf=false "${@:2}"; }

# --- unmanaged-resources.py ----------------------------------------------------------------
# Proyecto único (ADR 0029): example-landing-zone, número 111111111111. Estados de 0-bootstrap,
# 1-base y el spoke de dev (crudos) y de 3-workloads de dev (`terraform show -json`).
u="$DATA/unmanaged"
um() { "$PY" scripts/unmanaged-resources.py --project example-landing-zone --project-number 111111111111 "$@"; }
states=(--state "$u/0-bootstrap.state.json" --state "$u/1-base.state.json" --state "$u/2-networks-dev.state.json")
um --assets "$u/assets.json" "${states[@]}" --state "$u/3-workloads-dev.show.json" \
  --summary "$tmp/summary.md" >"$tmp/out.txt" 2>&1
check "unmanaged-resources: sale con 1 si hay recursos no administrados" 1 $?
grep '^NO ADMINISTRADO ' "$tmp/out.txt" >"$tmp/got.txt"
if diff -u "$u/expected.txt" "$tmp/got.txt"; then
  echo "OK    unmanaged-resources: exactamente los 5 recursos manuales esperados"
else
  echo "FALLA unmanaged-resources: la lista de no administrados no coincide"
  cat "$tmp/out.txt"
  fails=$((fails + 1))
fi
grep -q '| \*\*No administrados\*\* | 5 |' "$tmp/summary.md"
check "unmanaged-resources: resumen en Markdown con el conteo" 0 $?
grep -q '^  permitidos por regla: 4$' "$tmp/out.txt"
check "unmanaged-resources: la lista de permitidos cubre lo que GCP crea solo (4)" 0 $?
um --assets "$u/assets.json" "${states[@]}" --state "$u/3-workloads-dev.show.json" \
  --report-only >/dev/null 2>&1
check "unmanaged-resources: --report-only sale con 0" 0 $?
# Sin el estado de 3-workloads, sus recursos pasan a no administrados (la comparación depende
# de los estados, no de la lista de permitidos).
um --assets "$u/assets.json" "${states[@]}" >"$tmp/out2.txt" 2>&1
n="$(grep -c '^NO ADMINISTRADO ' "$tmp/out2.txt")"
# 5 manuales + 8 de 3-workloads: cuenta de servicio, bucket, plantilla, MIG, su VM y su disco,
# clúster y node pool.
check "unmanaged-resources: sin un estado, sus recursos salen como no administrados (13)" 13 "$n"
# Listados que no permiten concluir nada: error (2), nunca "0 no administrados" con 0, ni
# siquiera con --report-only.
printf '[]' >"$tmp/a-lista-vacia.json"
printf '{}' >"$tmp/a-objeto-vacio.json"
printf '{"results": []}' >"$tmp/a-results-vacio.json"
printf '{"nextPageToken": "x"}' >"$tmp/a-sin-results.json"
printf '[{"assetType": "storage.googleapis.com/Bucket"}]' >"$tmp/a-sin-name.json"
for a in lista-vacia objeto-vacio results-vacio sin-results sin-name; do
  um --assets "$tmp/a-$a.json" "${states[@]}" --report-only >/dev/null 2>&1
  check "unmanaged-resources: listado $a es error aunque haya --report-only" 2 $?
done
um --assets "$u/assets-otro-proyecto.json" "${states[@]}" --report-only >/dev/null 2>&1
check "unmanaged-resources: listado de otro proyecto es error" 2 $?
# Listado sin el proyecto mismo (otro alcance, truncado o sin permisos).
"$PY" -c '
import json, sys
a = json.load(open(sys.argv[1], encoding="utf-8"))
a = [x for x in a if x["assetType"] != "cloudresourcemanager.googleapis.com/Project"]
json.dump(a, open(sys.argv[2], "w", encoding="utf-8"))
' "$u/assets.json" "$tmp/a-sin-proyecto.json"
um --assets "$tmp/a-sin-proyecto.json" "${states[@]}" --report-only >"$tmp/out-sinp.txt" 2>&1
check "unmanaged-resources: listado que no trae el proyecto es error" 2 $?
grep -q 'no trae el proyecto example-landing-zone' "$tmp/out-sinp.txt"
check "unmanaged-resources: el error nombra el proyecto que falta" 0 $?
"$PY" scripts/unmanaged-resources.py --project X --project-number 111111111111 --assets "$u/assets.json" \
  "${states[@]}" --report-only >/dev/null 2>&1
check "unmanaged-resources: --project inválido es error" 2 $?
"$PY" scripts/unmanaged-resources.py --project example-landing-zone --project-number abc \
  --assets "$u/assets.json" "${states[@]}" --report-only >/dev/null 2>&1
check "unmanaged-resources: --project-number inválido es error" 2 $?
# APIs habilitadas: las dependencias de la lista cerrada se permiten; otra API habilitada a
# mano (aiplatform) se reporta.
um --assets "$u/assets-apis.json" --state "$u/0-bootstrap.state.json" >"$tmp/out3.txt" 2>&1
check "unmanaged-resources: una API habilitada a mano sale con 1" 1 $?
[ "$(grep '^NO ADMINISTRADO ' "$tmp/out3.txt")" = \
  "NO ADMINISTRADO serviceusage.googleapis.com/Service projects/111111111111/services/aiplatform.googleapis.com" ]
check "unmanaged-resources: solo la API manual sale; storage-api y containerfilesystem se permiten" 0 $?
# Imágenes de contenedor (DockerImage, HIPÓTESIS de formato): las del repositorio de 1-base son
# hijas del repositorio; la de un repositorio creado a mano (cloud-run-source-deploy) la permite
# la regla de imágenes, pero el repositorio sí sale como no administrado.
um --assets "$u/assets-imagenes.json" --state "$u/1-base.state.json" >"$tmp/out-img.txt" 2>&1
rc=$?
[ "$rc" = 1 ] && [ "$(grep '^NO ADMINISTRADO ' "$tmp/out-img.txt")" = \
  "NO ADMINISTRADO artifactregistry.googleapis.com/Repository projects/111111111111/locations/us-central1/repositories/cloud-run-source-deploy" ] &&
  grep -q '^  hijos de un recurso administrado: 2$' "$tmp/out-img.txt" &&
  grep -q '^  permitidos por regla: 1$' "$tmp/out-img.txt"
check "unmanaged-resources: imágenes permitidas (2 hijas del repositorio de 1-base, 1 por regla) y el repositorio manual sí sale" 0 $?
grep -v 'DockerImage' scripts/unmanaged-allowlist.txt >"$tmp/allow-sin-imagenes.txt"
um --assets "$u/assets-imagenes.json" --state "$u/1-base.state.json" --allowlist "$tmp/allow-sin-imagenes.txt" \
  >"$tmp/out-img2.txt" 2>&1
grep -c '^NO ADMINISTRADO artifactregistry.googleapis.com/DockerImage ' "$tmp/out-img2.txt" >"$tmp/n-img.txt"
check "unmanaged-resources: sin la regla de imágenes, la imagen del repositorio manual sale como no administrada" 1 "$(cat "$tmp/n-img.txt")"
# drift.yml lista el proyecto (no una carpeta) y pasa su ID y su número al script.
grep -qF -- '--scope="projects/${PROJECT_ID}"' "$WF/drift.yml" &&
  grep -qF -- '--project "${PROJECT_ID}" --project-number "${PROJECT_NUMBER}"' "$WF/drift.yml" &&
  ! grep -q -- '--folder' "$WF/drift.yml"
check "drift.yml: Cloud Asset con --scope=projects/<ID> y el script con --project y --project-number" 0 $?

# --- affected-roots.sh ---------------------------------------------------------------------
# Repositorio de prueba con el árbol del ADR 0029 §2: 0-bootstrap, 1-base, el hub 2-networks
# con sus spokes envs/{dev,qa,prod} y 3-workloads/envs/{dev,qa,prod}. El spoke de dev usa
# stages/2-networks/comun-red (dentro del hub) como módulo local; stages/3-workloads/comun no
# lo usa nadie, pero cuelga de 3-workloads.
ar="$tmp/ar"
ag="$ar/gcp-datacenter"
mkdir -p "$ag/scripts"
cp scripts/affected-roots.sh "$ag/scripts/"
for r in 0-bootstrap 1-base 2-networks 2-networks/envs/dev 2-networks/envs/qa 2-networks/envs/prod \
  3-workloads/envs/dev 3-workloads/envs/qa 3-workloads/envs/prod; do
  mkdir -p "$ag/stages/$r"
  echo 'terraform {}' >"$ag/stages/$r/versions.tf"
done
mkdir -p "$ag/stages/2-networks/comun-red" "$ag/stages/3-workloads/comun" "$ag/modules/storage" \
  "$ag/policies" "$ag/docs"
printf 'module "comun" {\n  source = "../../comun-red"\n}\n' >"$ag/stages/2-networks/envs/dev/main.tf"
for f in stages/2-networks/comun-red/main.tf stages/3-workloads/comun/main.tf stages/3-workloads/README.md \
  modules/storage/main.tf policies/p.rego docs/d.md; do
  echo base >"$ag/$f"
done
echo base >"$ar/README.md"
git init -q "$ar" 2>/dev/null
gitc "$ar" add -A 2>/dev/null && gitc "$ar" commit -q -m base 2>/dev/null
roots_of() { # lee "roots=<json>" y escribe las raíces separadas por espacios
  "$PY" -c '
import json, sys
line = sys.stdin.read().strip()
if not line.startswith("roots="):
    sys.exit(1)
print(" ".join(r["root"] for r in json.loads(line[len("roots="):])))
'
}
ar_case() { # ar_case <descripción> <archivo relativo al repositorio> <raíces esperadas>
  local before got
  before="$(git -C "$ar" rev-parse HEAD)"
  mkdir -p "$(dirname "$ar/$2")"
  echo cambio >>"$ar/$2"
  gitc "$ar" add -A 2>/dev/null && gitc "$ar" commit -q -m "cambio en $2" 2>/dev/null
  got="$(bash "$ag/scripts/affected-roots.sh" "$before" HEAD 2>/dev/null | roots_of)"
  [ "$got" = "$3" ]
  check "affected-roots: $1" 0 $?
  [ "$got" = "$3" ] || echo "      esperado [$3], obtenido [$got]"
}
all_roots="stages/1-base stages/2-networks stages/2-networks/envs/dev stages/2-networks/envs/prod stages/2-networks/envs/qa stages/3-workloads/envs/dev stages/3-workloads/envs/prod stages/3-workloads/envs/qa"
workload_roots="stages/3-workloads/envs/dev stages/3-workloads/envs/prod stages/3-workloads/envs/qa"
bash "$ag/scripts/affected-roots.sh" --all >"$tmp/all.txt" 2>&1
check "affected-roots: --all sale con 0" 0 $?
want_all='roots=[{"root":"stages/1-base","stage":"1-base","environment":"common"},{"root":"stages/2-networks","stage":"2-networks","environment":"common"},{"root":"stages/2-networks/envs/dev","stage":"2-networks/dev","environment":"dev"},{"root":"stages/2-networks/envs/prod","stage":"2-networks/prod","environment":"prod"},{"root":"stages/2-networks/envs/qa","stage":"2-networks/qa","environment":"qa"},{"root":"stages/3-workloads/envs/dev","stage":"3-workloads/dev","environment":"dev"},{"root":"stages/3-workloads/envs/prod","stage":"3-workloads/prod","environment":"prod"},{"root":"stages/3-workloads/envs/qa","stage":"3-workloads/qa","environment":"qa"}]'
[ "$(cat "$tmp/all.txt")" = "$want_all" ]
check "affected-roots: --all da las 8 raíces con la llave de cuenta y el entorno de GitHub (sin 0-bootstrap)" 0 $?
sed 's/^roots=//' "$tmp/all.txt" >"$tmp/all.json"
ar_case "un cambio en el spoke de dev planea solo ese spoke" gcp-datacenter/stages/2-networks/envs/dev/main.tf \
  "stages/2-networks/envs/dev"
ar_case "un cambio en el hub planea solo el hub" gcp-datacenter/stages/2-networks/main.tf "stages/2-networks"
ar_case "un cambio en 1-base planea solo 1-base" gcp-datacenter/stages/1-base/main.tf "stages/1-base"
ar_case "un cambio en 3-workloads de qa planea solo esa raíz" gcp-datacenter/stages/3-workloads/envs/qa/main.tf \
  "stages/3-workloads/envs/qa"
ar_case "un cambio en 0-bootstrap no planea nada (la aplica una persona)" gcp-datacenter/stages/0-bootstrap/main.tf ""
ar_case "un cambio en modules/ planea todas las raíces" gcp-datacenter/modules/storage/main.tf "$all_roots"
ar_case "un cambio en policies/ planea todas las raíces" gcp-datacenter/policies/p.rego "$all_roots"
ar_case "stages/3-workloads/README.md no planea nada (los .md no cambian un plan)" \
  gcp-datacenter/stages/3-workloads/README.md ""
ar_case "el README de un módulo no planea nada (terraform-docs)" gcp-datacenter/modules/storage/README.md ""
ar_case "el README de una raíz no planea nada" gcp-datacenter/stages/1-base/README.md ""
ar_case "un .md en policies/ no planea nada" gcp-datacenter/policies/README.md ""
ar_case "código común en stages/3-workloads/comun planea las tres raíces de 3-workloads" \
  gcp-datacenter/stages/3-workloads/comun/main.tf "$workload_roots"
ar_case "un módulo local dentro del hub planea el hub y el spoke que lo usa" \
  gcp-datacenter/stages/2-networks/comun-red/main.tf "stages/2-networks stages/2-networks/envs/dev"
ar_case "un cambio en docs/ no planea nada" gcp-datacenter/docs/d.md ""
ar_case "un cambio fuera de gcp-datacenter/ no planea nada" README.md ""
bash "$ag/scripts/affected-roots.sh" >/dev/null 2>&1
check "affected-roots: sin argumentos es error de uso" 2 $?
bash "$ag/scripts/affected-roots.sh" --all extra >/dev/null 2>&1
check "affected-roots: --all con otro argumento es error de uso" 2 $?
mkdir -p "$ag/stages/3-workloads/envs/dev/extra"
echo 'terraform {}' >"$ag/stages/3-workloads/envs/dev/extra/versions.tf"
bash "$ag/scripts/affected-roots.sh" --all >/dev/null 2>&1
check "affected-roots: una raíz sin la forma stages/<etapa>[/envs/<env>] es error (2)" 2 $?
grep -qF 'bash scripts/affected-roots.sh "${BASE_SHA}" "${HEAD_SHA}"' "$WF/pr.yml" &&
  grep -qF 'bash scripts/affected-roots.sh --all' "$WF/drift.yml"
check "affected-roots: pr.yml lo llama con base y cabeza del PR y drift.yml con --all" 0 $?

# --- disabled-envs.py (GCP_DISABLED_ENVS) ---------------------------------------------------
de() { GCP_DISABLED_ENVS="$1" "$PY" scripts/disabled-envs.py "${@:2}"; }
[ "$(de "" outputs | tr '\n' ' ')" = "dev=true qa=true " ]
check "disabled-envs: vacía, ningún entorno apagado" 0 $?
[ "$(de "dev" outputs | tr '\n' ' ')" = "dev=false qa=true " ] &&
  [ "$(de " QA , dev " outputs | tr '\n' ' ')" = "dev=false qa=false " ] &&
  [ "$(de "qa qa" outputs | tr '\n' ' ')" = "dev=true qa=false " ]
check "disabled-envs: dev, qa y los dos (comas o espacios, sin importar mayúsculas)" 0 $?
de "dev,prod" outputs >/dev/null 2>"$tmp/de-err.txt"
[ $? = 2 ] && grep -q 'prod no se puede apagar' "$tmp/de-err.txt"
check "disabled-envs: prod en la variable es error (2) con mensaje" 0 $?
de "prod" filter </dev/null >/dev/null 2>&1
check "disabled-envs: prod también es error al filtrar (drift.yml)" 2 $?
de "common" outputs >/dev/null 2>&1
rc_common=$?
de "dev,test" outputs >/dev/null 2>&1
check "disabled-envs: common y nombres desconocidos son error" "2 2" "$rc_common $?"
: >"$tmp/de-out.txt"
de "dev,prod" outputs "$tmp/de-out.txt" >"$tmp/de-stdout.txt" 2>/dev/null
[ $? = 2 ] && [ ! -s "$tmp/de-out.txt" ] && grep -q '^::error::' "$tmp/de-stdout.txt"
check "disabled-envs: con archivo, el error va como ::error:: y no escribe salidas" 0 $?
printf 'otra=1\n' >"$tmp/de-out.txt"
de "qa" outputs "$tmp/de-out.txt" >"$tmp/de-stdout.txt" 2>&1
[ $? = 0 ] && [ "$(tr '\n' ' ' <"$tmp/de-out.txt")" = "otra=1 dev=true qa=false " ] &&
  grep -q '^::notice::.*qa' "$tmp/de-stdout.txt"
check "disabled-envs: con archivo agrega las salidas al final (GITHUB_OUTPUT) y avisa con ::notice::" 0 $?
bash scripts/affected-roots.sh --all >"$tmp/de-roots.txt"
de "dev" filter <"$tmp/de-roots.txt" >"$tmp/de-filtered.txt" 2>/dev/null
"$PY" -c '
import json, sys
got = json.loads(open(sys.argv[1], encoding="utf-8").read().strip()[len("roots="):])
want = [r for r in json.loads(open(sys.argv[2], encoding="utf-8").read().strip()[len("roots="):])
        if r["environment"] != "dev"]
sys.exit(0 if got == want and len(got) == 6 and all(r["environment"] != "dev" for r in got) else 1)
' "$tmp/de-filtered.txt" "$tmp/de-roots.txt" 2>/dev/null
check "disabled-envs: filter quita las 2 raíces de dev y deja las otras 6 en el mismo formato" 0 $?
[ "$(de "" filter <"$tmp/de-roots.txt")" = "$(cat "$tmp/de-roots.txt")" ]
check "disabled-envs: filter sin entornos apagados deja la lista igual" 0 $?
printf 'nada\n' | de "" filter >/dev/null 2>&1
check "disabled-envs: filter sin línea roots= es error" 2 $?
grep -qF 'python3 scripts/disabled-envs.py outputs "${GITHUB_OUTPUT}"' "$WF/apply.yml" &&
  grep -qF 'GCP_DISABLED_ENVS: ${{ vars.GCP_DISABLED_ENVS }}' "$WF/apply.yml" &&
  grep -qF 'python3 scripts/disabled-envs.py filter "${GITHUB_OUTPUT}" < "${RUNNER_TEMP}/roots.txt"' "$WF/drift.yml" &&
  grep -qF 'GCP_DISABLED_ENVS: ${{ vars.GCP_DISABLED_ENVS }}' "$WF/drift.yml"
check "disabled-envs: apply.yml (gate) y drift.yml (raíces) lo usan con la variable de repositorio" 0 $?

# apply.yml: las raíces, llaves y entornos de GitHub son los de affected-roots.sh y el orden es
# el del ADR 0029 §2 (cada trabajo depende, directa o indirectamente, del anterior; qa después
# de la prueba de humo de dev; los spokes en serie). Después simula el flujo: evalúa las
# condiciones if de cada trabajo (subconjunto de expresiones de GitHub Actions que usa el flujo,
# con el success() implícito cuando la condición no trae una función de estado; un trabajo
# omitido o fallido omite a los que lo necesitan, docs.github.com "jobs.<job_id>.needs") con
# las salidas reales de disabled-envs.py, y compara qué trabajos corren en cada escenario.
"$PY" - "$WF/apply.yml" "$tmp/all.json" "$PROJECT_DIR/scripts/disabled-envs.py" >"$tmp/apply-order.txt" 2>&1 <<'PYEOF'
import json, os, re, subprocess, sys
wf = open(sys.argv[1], encoding="utf-8").read()
roots = json.load(open(sys.argv[2], encoding="utf-8"))
script = sys.argv[3]
jobs = dict(re.findall(r"\n  ([a-z][a-z0-9-]*):\n(.*?)(?=\n  [a-z][a-z0-9-]*:\n|\Z)", wf[wf.index("\njobs:"):], re.S))
def field(body, key):
    m = re.search(r"^      %s: (.+)$" % key, body, re.M)
    return m.group(1).strip() if m else None
def needs(body):
    m = re.search(r"^    needs: (.+)$", body, re.M)
    if not m:
        return []
    v = m.group(1).strip()
    return [n.strip() for n in v.strip("[]").split(",")] if v.startswith("[") else [v]
def condition(body):
    m = re.search(r"^    if: (.*)$", body, re.M)
    if not m:
        return None
    v = m.group(1).strip()
    if v in (">-", ">"):
        rest = []
        for line in body[m.end() + 1:].splitlines():
            if not line.startswith("      "):
                break
            rest.append(line.strip())
        v = " ".join(rest)
    if v.startswith("${{") and v.endswith("}}"):
        v = v[3:-2].strip()
    return v
TOKEN = re.compile(r"\s*(?:(&&|\|\||==|!=|!|\(|\))|('[^']*')|([A-Za-z_][A-Za-z0-9_-]*(?:\.[A-Za-z0-9_-]+)*)(\(\))?)")
STATUS = ("success", "failure", "always", "cancelled")
def compile_expr(expr):
    out, pos, status = [], 0, False
    while pos < len(expr):
        m = TOKEN.match(expr, pos)
        if not m or m.end() == pos:
            raise ValueError("expresión no reconocida: %r" % expr[pos:])
        pos = m.end()
        op, lit, path, call = m.groups()
        if op:
            out.append({"&&": " and ", "||": " or ", "!": " not "}.get(op, op))
        elif lit:
            out.append(repr(lit[1:-1]))
        elif call:
            if path not in STATUS:
                raise ValueError("función no soportada: %s" % path)
            status = True
            out.append("F(%r)" % path)
        else:
            out.append("C(%r)" % path)
    code = "".join(out)
    return code if status else "F('success') and (%s)" % code
bad = []
deployed = []
for name, body in jobs.items():
    if "uses: ./.github/workflows/_terraform-root.yml" in body:
        deployed.append({"root": field(body, "root"), "stage": field(body, "stage"),
                         "environment": field(body, "environment")})
if sorted(deployed, key=lambda r: str(r["root"])) != sorted(roots, key=lambda r: r["root"]):
    bad.append("raíces de apply.yml distintas de affected-roots.sh --all: %s" % deployed)
need = {n: needs(b) for n, b in jobs.items()}
def ancestors(n, seen=None):
    seen = set() if seen is None else seen
    for p in need.get(n, []):
        if p not in seen:
            seen.add(p)
            ancestors(p, seen)
    return seen
label = {n: field(b, "root") or ("humo" if "TestDevSmoke" in b else n) for n, b in jobs.items()}
by_label = {v: k for k, v in label.items()}
want = ["gate", "stages/1-base", "stages/2-networks", "stages/2-networks/envs/dev", "stages/3-workloads/envs/dev",
        "humo", "stages/2-networks/envs/qa", "stages/3-workloads/envs/qa", "stages/2-networks/envs/prod",
        "stages/3-workloads/envs/prod"]
if sorted(label.values()) != sorted(want):
    bad.append("trabajos %s" % sorted(label.values()))
else:
    for a, b in zip(want, want[1:]):
        if by_label[a] not in ancestors(by_label[b]):
            bad.append("%s no espera a %s" % (b, a))
    for j in jobs:
        if j != "gate" and "gate" not in ancestors(j):
            bad.append("%s no espera a gate" % j)
try:
    conds = {n: compile_expr(condition(b)) for n, b in jobs.items() if n != "gate"}
except ValueError as e:
    conds = {}
    bad.append(str(e))
for n, b in jobs.items():
    if n != "gate" and condition(b) is None:
        bad.append("%s sin condición" % n)
for n, ps in need.items():
    for p in ps:
        if p not in jobs:
            bad.append("%s necesita %s, que no existe" % (n, p))
def gate_outputs(value):
    env = dict(os.environ, GCP_DISABLED_ENVS=value)
    r = subprocess.run([sys.executable, script, "outputs"], env=env, stdout=subprocess.PIPE,
                       stderr=subprocess.DEVNULL, universal_newlines=True)
    if r.returncode != 0:
        return "failure", {}
    return "success", dict(l.split("=", 1) for l in r.stdout.split())
def simulate(enabled, ref, disabled, fails):
    results, outputs = {}, {}
    pending = list(jobs)
    while pending:
        ready = [n for n in pending if all(p in results for p in need[n])]
        if not ready:
            raise ValueError("ciclo en needs")
        for n in ready:
            pending.remove(n)
            if n == "gate":
                results[n], outputs[n] = gate_outputs(disabled)
                continue
            def C(path, n=n):
                parts = path.split(".")
                if path == "vars.GCP_ENABLED":
                    return enabled
                if path == "github.ref":
                    return ref
                if parts[0] == "needs" and len(parts) >= 3:
                    if parts[1] not in need[n]:
                        raise ValueError("%s usa needs.%s sin necesitarlo" % (n, parts[1]))
                    if parts[2] == "result":
                        return results[parts[1]]
                    if parts[2] == "outputs" and len(parts) == 4:
                        return outputs.get(parts[1], {}).get(parts[3], "")
                raise ValueError("%s: contexto no soportado %s" % (n, path))
            def F(name, n=n):
                rs = [results[p] for p in need[n]]
                return {"success": all(r == "success" for r in rs), "failure": any(r == "failure" for r in rs),
                        "always": True, "cancelled": False}[name]
            if eval(conds[n], {"C": C, "F": F}):
                results[n] = fails.get(n, "success")
            else:
                results[n] = "skipped"
    return results
COMMON = {"base", "networks-hub"}
DEV = {"dev-networks", "dev-workloads", "dev-smoke"}
QA = {"qa-networks", "qa-workloads"}
PROD = {"prod-networks", "prod-workloads"}
F_ = "failure"
scenarios = [
    ("todo encendido", "true", "refs/heads/main", "", {}, COMMON | DEV | QA | PROD),
    ("dev apagado: qa sigue después del hub", "true", "refs/heads/main", "dev", {}, COMMON | QA | PROD),
    ("qa apagado: prod después de la prueba de humo de dev", "true", "refs/heads/main", "qa", {}, COMMON | DEV | PROD),
    ("dev y qa apagados: prod después del hub", "true", "refs/heads/main", "dev,qa", {}, COMMON | PROD),
    ("con espacios y mayúsculas", "true", "refs/heads/main", " QA ", {}, COMMON | DEV | PROD),
    ("falla la prueba de humo de dev", "true", "refs/heads/main", "", {"dev-smoke": F_}, COMMON | DEV),
    ("falla dev / 3-workloads (humo omitido)", "true", "refs/heads/main", "", {"dev-workloads": F_},
     COMMON | {"dev-networks", "dev-workloads"}),
    ("qa apagado y falla la prueba de humo", "true", "refs/heads/main", "qa", {"dev-smoke": F_}, COMMON | DEV),
    ("dev apagado y falla qa / 3-workloads", "true", "refs/heads/main", "dev", {"qa-workloads": F_}, COMMON | QA),
    ("falla qa / 2-networks", "true", "refs/heads/main", "", {"qa-networks": F_}, COMMON | DEV | {"qa-networks"}),
    ("dev apagado y falla el hub", "true", "refs/heads/main", "dev", {"networks-hub": F_}, COMMON),
    ("dev y qa apagados y falla el hub", "true", "refs/heads/main", "dev,qa", {"networks-hub": F_}, COMMON),
    ("falla 1-base", "true", "refs/heads/main", "", {"base": F_}, {"base"}),
    ("prod en GCP_DISABLED_ENVS: gate falla y nada corre", "true", "refs/heads/main", "dev,prod", {}, set()),
    ("nombre desconocido en GCP_DISABLED_ENVS", "true", "refs/heads/main", "test", {}, set()),
    ("GCP_ENABLED distinto de true", "false", "refs/heads/main", "", {}, set()),
    ("ejecución desde otra rama", "true", "refs/heads/otra", "dev", {}, set()),
]
if conds:
    for name, enabled, ref, disabled, fails, expected in scenarios:
        try:
            r = simulate(enabled, ref, disabled, fails)
        except ValueError as e:
            bad.append("%s: %s" % (name, e))
            continue
        ran = {n for n, v in r.items() if n != "gate" and v != "skipped"}
        if ran != expected:
            bad.append("%s: corren %s, se esperaba %s" % (name, sorted(ran), sorted(expected)))
print("; ".join(bad))
sys.exit(1 if bad else 0)
PYEOF
rc=$?
check "apply.yml: 1-base → hub → dev (red, cargas, humo) → qa → prod, spokes en serie, llaves y entornos de affected-roots y 17 escenarios de GCP_DISABLED_ENVS y fallas $(cat "$tmp/apply-order.txt")" 0 "$rc"

# Cuentas (ADR 0029 §3 y ADR 0025): todo plan corre con la cuenta de lectura y -lock=false; el
# apply, con la cuenta de la raíz y el candado.
"$PY" -c '
import re, sys
def job(text, name):
    m = re.search(r"\n  %s:\n(.*?)(?=\n  [a-z][a-z0-9_-]*:\n|\Z)" % name, text, re.S)
    return m.group(1) if m else ""
def plans(body):
    return [l.strip() for l in body.splitlines() if l.strip().startswith("terraform plan")]
read_sa = "service_account: ${{ vars.GCP_AUDIT_SERVICE_ACCOUNT }}"
bad = []
texts = {p: open(p, encoding="utf-8").read() for p in sys.argv[1:]}
for path, text in texts.items():
    body = job(text, "plan")
    if read_sa not in body:
        bad.append("%s plan sin la cuenta de lectura" % path)
    if not plans(body) or any("-lock=false" not in l for l in plans(body)):
        bad.append("%s plan sin -lock=false" % path)
    if "GCP_STAGE_SERVICE_ACCOUNTS)" in body:
        bad.append("%s plan usa una cuenta de raíz" % path)
root = [t for p, t in texts.items() if p.endswith("_terraform-root.yml")][0]
apply_job = job(root, "apply")
if "service_account: ${{ fromJSON(vars.GCP_STAGE_SERVICE_ACCOUNTS)[inputs.stage] }}" not in apply_job:
    bad.append("_terraform-root apply sin la cuenta de la raíz")
if "GCP_AUDIT_SERVICE_ACCOUNT" in apply_job or not plans(apply_job) or any("-lock=false" in l for l in plans(apply_job)):
    bad.append("_terraform-root apply con la cuenta de lectura o sin candado")
for path, text in texts.items():
    if not path.endswith("_terraform-root.yml") and re.search(r"service_account:.*GCP_STAGE_SERVICE_ACCOUNTS", text):
        bad.append("%s usa una cuenta de raíz" % path)
print("; ".join(bad))
sys.exit(1 if bad else 0)
' "$WF/pr.yml" "$WF/drift.yml" "$WF/_terraform-root.yml" >"$tmp/accounts.txt" 2>&1
rc=$?
check "flujos: plan con la cuenta de lectura y -lock=false (pr, drift, _terraform-root); apply con la cuenta de la raíz $(cat "$tmp/accounts.txt")" 0 "$rc"

# --- root-tfvars.py ------------------------------------------------------------------------
rt="$tmp/rt"
mkdir -p "$rt/stages/1-base" "$rt/stages/sin-proyecto"
printf 'variable "project_id" {\n  type = string\n}\n' >"$rt/stages/1-base/variables.tf"
printf 'project_id = "REEMPLAZAR"\nprefix     = "bnt"\n' >"$rt/stages/1-base/terraform.tfvars.example"
printf 'variable "otra" {\n  type = string\n}\n' >"$rt/stages/sin-proyecto/variables.tf"
tfv() { # tfv <TFVARS_JSON> <raíz>: corre root-tfvars.py desde $rt; devuelve su código
  (cd "$rt" && TFVARS_JSON="$1" "$PY" "$PROJECT_DIR/scripts/root-tfvars.py" "$2" >/dev/null 2>&1)
}
tfv '{"common": {"project_id": "bnt-lz-pruebas", "prefix": "bnt"}, "stages/1-base": {"prefix": "otro"}}' stages/1-base
check "root-tfvars: con common.project_id escribe las variables" 0 $?
"$PY" -c '
import json, sys
v = json.load(open(sys.argv[1], encoding="utf-8"))
same = open(sys.argv[2], encoding="utf-8").read() == open(sys.argv[3], encoding="utf-8").read()
sys.exit(0 if v == {"project_id": "bnt-lz-pruebas", "prefix": "otro"} and same else 1)
' "$rt/stages/1-base/zz-ci.auto.tfvars.json" "$rt/stages/1-base/terraform.tfvars" \
  "$rt/stages/1-base/terraform.tfvars.example" 2>/dev/null
check "root-tfvars: common + la llave de la raíz (gana la raíz) y terraform.tfvars copiado del ejemplo" 0 $?
rm -f "$rt/stages/1-base/zz-ci.auto.tfvars.json" "$rt/stages/1-base/terraform.tfvars"
tfv '{"common": {"prefix": "bnt"}}' stages/1-base
check "root-tfvars: sin project_id en GCP_TFVARS_JSON es error si la raíz lo declara" 2 $?
[ ! -e "$rt/stages/1-base/zz-ci.auto.tfvars.json" ] && [ ! -e "$rt/stages/1-base/terraform.tfvars" ]
check "root-tfvars: sin project_id no escribe nada (el plan no toma el marcador del ejemplo)" 0 $?
tfv '{"common": {"project_id": " "}}' stages/1-base
check "root-tfvars: project_id en blanco es error" 2 $?
tfv '' stages/1-base
check "root-tfvars: GCP_TFVARS_JSON vacío es error si la raíz declara project_id" 2 $?
tfv 'no es json' stages/1-base
check "root-tfvars: GCP_TFVARS_JSON que no es JSON es error" 2 $?
tfv '["x"]' stages/1-base
check "root-tfvars: GCP_TFVARS_JSON que no es un objeto es error" 2 $?
tfv '{"common": "x"}' stages/1-base
check "root-tfvars: una llave que no es un objeto es error" 2 $?
tfv '{}' stages/sin-proyecto
check "root-tfvars: una raíz sin la variable project_id no lo exige" 0 $?
tfv '{"common": {"project_id": "bnt-lz-pruebas"}}' stages/no-existe
check "root-tfvars: una raíz que no existe es error" 2 $?
# Marcadores de los ejemplos (H6): un valor resuelto de una variable declarada con example.com,
# example-..., REEMPLAZAR, <...> o un ID de solo ceros es error (2) y no escribe nada. Resuelto:
# el del JSON si la variable está en common o en la llave de la raíz; si no, el del ejemplo sin
# comentarios. Las variables que la raíz no declara no se revisan.
mkdir -p "$rt/stages/marcas"
for v in project_id security_alert_email essential_contacts labels cloud_run_image github_id secret_id; do
  printf 'variable "%s" {}\n' "$v"
done >"$rt/stages/marcas/variables.tf"
printf '%s\n' '# Ejemplo con marcadores; los comentarios no cuentan: x@example.com' \
  'project_id           = "REEMPLAZAR"' \
  'security_alert_email = "seguridad@example.com"' \
  'essential_contacts = {' \
  '  "admin@example.com" = ["LEGAL", "SECURITY"]' \
  '}' \
  'labels = {' \
  '  app   = "red"' \
  '  owner = "example-team"' \
  '}' \
  '# cloud_run_image = "us-docker.pkg.dev/example-lz-000000/bnt-dev-app/api:1.0.0"' \
  'cloud_run_image = "us-docker.pkg.dev/bnt-lz-pruebas/bnt-dev-app/api:1.0.0" # no example.com' \
  'github_id = "000000000"' \
  'secret_id = "projects/<proyecto>/secrets/<nombre>"' \
  'no_declarada = "otro@example.com"' >"$rt/stages/marcas/terraform.tfvars.example"
tfv_err() { # tfv_err <TFVARS_JSON> <raíz>: como tfv, pero guarda stderr en $tmp/rt-err.txt
  (cd "$rt" && TFVARS_JSON="$1" "$PY" "$PROJECT_DIR/scripts/root-tfvars.py" "$2" >/dev/null 2>"$tmp/rt-err.txt")
}
tfv_err '{"common": {"project_id": "bnt-lz-pruebas"}}' stages/marcas
rc=$?
[ "$rc" = 2 ] && [ ! -e "$rt/stages/marcas/zz-ci.auto.tfvars.json" ] && [ ! -e "$rt/stages/marcas/terraform.tfvars" ]
check "root-tfvars: marcadores que llegan del ejemplo son error (2) y no escriben nada" 0 $?
[ "$(grep -oE '^  [a-z_]+ \(de terraform\.tfvars\.example\)' "$tmp/rt-err.txt" | awk '{print $1}' | tr '\n' ' ')" = \
  "essential_contacts github_id labels secret_id security_alert_email " ]
check "root-tfvars: nombra las 5 variables con marcador (ni comentarios, ni project_id del JSON, ni no declaradas)" 0 $?
! grep -qE 'seguridad@|admin@|example-team|000000000|<proyecto>' "$tmp/rt-err.txt"
check "root-tfvars: el mensaje no muestra los valores" 0 $?
real='"security_alert_email": "seguridad@banorte-lz.test", "essential_contacts": {"admin@banorte-lz.test": ["LEGAL"]}, "labels": {"app": "red", "owner": "redes"}, "github_id": "123456789", "secret_id": "projects/bnt-lz-pruebas/secrets/vpn"'
tfv "{\"common\": {\"project_id\": \"bnt-lz-pruebas\", \"labels\": {\"owner\": \"example-team\"}}, \"stages/marcas\": {${real}}}" stages/marcas
check "root-tfvars: con los valores reales en el JSON pasa (la llave de la raíz pisa labels de common)" 0 $?
rm -f "$rt/stages/marcas/zz-ci.auto.tfvars.json" "$rt/stages/marcas/terraform.tfvars"
tfv_err "{\"common\": {\"project_id\": \"bnt-lz-pruebas\"}, \"stages/marcas\": {${real}, \"cloud_run_image\": \"us-docker.pkg.dev/example-lz-000000/bnt-dev-app/api:1.0.0\"}}" stages/marcas
[ $? = 2 ] && grep -q "cloud_run_image (de GCP_TFVARS_JSON\['stages/marcas'\]): nombre de ejemplo" "$tmp/rt-err.txt"
check "root-tfvars: un marcador en el JSON también es error y dice de qué llave viene" 0 $?
tfv_err "{\"common\": {\"project_id\": \"example-landing-zone\"}, \"stages/marcas\": {${real}}}" stages/marcas
[ $? = 2 ] && grep -q "project_id (de GCP_TFVARS_JSON\['common'\])" "$tmp/rt-err.txt"
check "root-tfvars: el proyecto de los ejemplos (example-landing-zone) es error" 0 $?
tfv_err "{\"common\": {\"project_id\": \"bnt-lz-pruebas\"}, \"stages/marcas\": {${real}, \"essential_contacts\": {\"x@example.com\": [\"LEGAL\"]}}}" stages/marcas
[ $? = 2 ] && grep -q '^  essential_contacts (de GCP_TFVARS_JSON' "$tmp/rt-err.txt"
check "root-tfvars: un marcador en una llave de un mapa del JSON (correo de essential_contacts) es error" 0 $?
# Los terraform.tfvars.example reales (copiados a la carpeta temporal: root-tfvars.py escribe en
# la raíz si pasa): con solo project_id, cada raíz del pipeline falla y nombra lo que hay que
# poner en GCP_TFVARS_JSON; el hub con esos valores pasa.
for r in 1-base 2-networks 2-networks/envs/dev 2-networks/envs/qa 2-networks/envs/prod \
  3-workloads/envs/dev 3-workloads/envs/qa 3-workloads/envs/prod; do
  mkdir -p "$rt/real/stages/$r"
  cp stages/"$r"/*.tf stages/"$r"/terraform.tfvars.example "$rt/real/stages/$r/"
done
missing_marks=""
while read -r r want; do
  (cd "$rt/real" && TFVARS_JSON='{"common": {"project_id": "bnt-lz-pruebas"}}' \
    "$PY" "$PROJECT_DIR/scripts/root-tfvars.py" "stages/$r" >/dev/null 2>"$tmp/rt-real.txt")
  [ $? = 2 ] || missing_marks="$missing_marks [$r no falla]"
  for v in $want; do
    grep -q "^  $v (de terraform.tfvars.example)" "$tmp/rt-real.txt" || missing_marks="$missing_marks [$r $v]"
  done
done <<'EOF'
1-base security_alert_email essential_contacts groups
2-networks onprem_dns_domain labels
2-networks/envs/dev onprem_dns_domain labels
2-networks/envs/qa onprem_dns_domain labels
2-networks/envs/prod onprem_dns_domain labels
3-workloads/envs/dev cloud_run_image domain_names notification_emails
3-workloads/envs/qa cloud_run_image domain_names notification_emails mig_image
3-workloads/envs/prod cloud_run_image domain_names notification_emails mig_image gke_authenticator_security_group internal_domain_names
EOF
[ -z "$missing_marks" ]
check "root-tfvars: los marcadores de los terraform.tfvars.example reales se detectan${missing_marks:+ (faltan:$missing_marks)}" 0 $?
(cd "$rt/real" && TFVARS_JSON='{"common": {"project_id": "bnt-lz-pruebas", "labels": {"app": "network", "owner": "redes", "cost_center": "ti-001"}}, "stages/2-networks": {"onprem_dns_domain": "corp.banorte-lz.internal."}}' \
  "$PY" "$PROJECT_DIR/scripts/root-tfvars.py" stages/2-networks >/dev/null 2>&1)
check "root-tfvars: el hub real con onprem_dns_domain y labels reales pasa (sin falsos positivos en su ejemplo)" 0 $?
n=0
for f in pr.yml drift.yml _terraform-root.yml; do
  n=$((n + $(grep -cF 'python3 scripts/root-tfvars.py "${ROOT}"' "$WF/$f")))
done
check "root-tfvars: los flujos lo usan antes de cada init (pr, drift y plan y apply de _terraform-root: 4)" 4 "$n"

# pr.yml corre las pruebas de Go sin GCP (config.example.json contra los variables.tf, entre
# otras): go vet y go test de todos los paquetes en tests/, sin id-token ni cuentas de GCP.
"$PY" -c '
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"\n  go:\n(.*?)(?=\n  [a-z][a-z0-9_-]*:\n|\Z)", t, re.S)
body = m.group(1) if m else ""
ok = (body and "name: go (vet y pruebas sin GCP)" in body and "working-directory: gcp-datacenter/tests" in body
      and "run: go vet ./..." in body and "run: go test -count=1 ./..." in body
      and "id-token" not in body and "google-github-actions/auth" not in body and "if:" not in body)
sys.exit(0 if ok else 1)
' "$WF/pr.yml"
check "pr.yml: trabajo go (vet y pruebas sin GCP) con go vet y go test de tests/, sin credenciales ni condición" 0 $?

# --- terratest-project-check.py --------------------------------------------------------------
# terratest.yml falla si TERRATEST_PROJECT_ID es el proyecto de la landing zone
# (GCP_TFVARS_JSON.common.project_id), sin mostrar ninguno de los dos, y exporta
# TERRATEST_LANDING_ZONE_PROJECT_ID para la guarda de tests/helpers (RequireProjectEnv).
tpc() { TERRATEST_PROJECT_ID="$1" TFVARS_JSON="$2" "$PY" scripts/terratest-project-check.py "${@:3}"; }
lzjson='{"common": {"project_id": "bnt-lz-pruebas"}, "stages/1-base": {"project_id": "otro"}}'
tpc bnt-lz-pruebas "$lzjson" >"$tmp/tpc-out.txt" 2>&1
rc=$?
[ "$rc" = 1 ] && ! grep -q 'bnt-lz-pruebas' "$tmp/tpc-out.txt"
check "terratest-project-check: el mismo proyecto que common.project_id es error (1) y no muestra el ID" 0 $?
tpc " BNT-LZ-Pruebas " "$lzjson" >/dev/null 2>&1
check "terratest-project-check: compara sin mayúsculas ni espacios" 1 $?
: >"$tmp/tpc-env.txt"
tpc bnt-lz-pruebas "$lzjson" "$tmp/tpc-env.txt" >"$tmp/tpc-out.txt" 2>&1
[ $? = 1 ] && [ ! -s "$tmp/tpc-env.txt" ] && grep -q '^::error::' "$tmp/tpc-out.txt"
check "terratest-project-check: con archivo, ::error:: y no exporta nada" 0 $?
: >"$tmp/tpc-env.txt"
tpc bnt-terratest "$lzjson" "$tmp/tpc-env.txt" >/dev/null 2>&1
[ $? = 0 ] && [ "$(cat "$tmp/tpc-env.txt")" = "TERRATEST_LANDING_ZONE_PROJECT_ID=bnt-lz-pruebas" ]
check "terratest-project-check: otro proyecto pasa y exporta TERRATEST_LANDING_ZONE_PROJECT_ID (GITHUB_ENV)" 0 $?
: >"$tmp/tpc-env.txt"
tpc bnt-terratest "" "$tmp/tpc-env.txt" >"$tmp/tpc-out.txt" 2>&1
rc1=$?
tpc bnt-terratest 'no es json' >/dev/null 2>&1
rc2=$?
tpc bnt-terratest '{"stages/1-base": {"project_id": "bnt-terratest"}}' >/dev/null 2>&1
rc3=$?
[ "$rc1 $rc2 $rc3" = "0 0 0" ] && [ ! -s "$tmp/tpc-env.txt" ] && grep -q '^::notice::.*no se puede comprobar' "$tmp/tpc-out.txt"
check "terratest-project-check: sin common.project_id que leer no falla y lo avisa" 0 $?
: >"$tmp/tpc-env.txt"
tpc bnt-terratest '{"common": {"project_id": "bnt-lz\nOTRA=1"}}' "$tmp/tpc-env.txt" >/dev/null 2>&1
[ $? = 0 ] && [ ! -s "$tmp/tpc-env.txt" ]
check "terratest-project-check: no exporta un valor que no tiene la forma de un ID de proyecto" 0 $?
"$PY" -c '
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
i = t.find("python3 scripts/terratest-project-check.py \"${GITHUB_ENV}\"")
j = t.find("go test -count=1 -json")
step = t[t.rfind("- name:", 0, i):i] if i >= 0 else ""
ok = 0 <= i < j and "TFVARS_JSON: ${{ vars.GCP_TFVARS_JSON }}" in step
go = open(sys.argv[2], encoding="utf-8").read()
py = open(sys.argv[3], encoding="utf-8").read()
m = re.search(r"EnvLandingZoneProjectID\s*=\s*\"([A-Z_]+)\"", go)
ok = ok and m and ("EXPORT = \"%s\"" % m.group(1)) in py
sys.exit(0 if ok else 1)
' "$WF/terratest.yml" tests/helpers/env.go scripts/terratest-project-check.py
check "terratest-project-check: terratest.yml lo corre antes de go test, con GCP_TFVARS_JSON, y exporta la variable que lee tests/helpers" 0 $?

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
[ "$got" = '^(TestFirewallNetwork)$' ]
check "module-tests: firewall solo tiene la política de red (ADR 0029 §6)" 0 $?
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
# Un merge que solo cambia documentación (gcp-datacenter/docs/ o un .md de gcp-datacenter/) no
# deja vieja a la ejecución en curso: apply.yml no se dispara por él. Un .tf sí.
sha_m="$(git -C "$r/dev" rev-parse HEAD)"
tip_commit gcp-datacenter/docs/pipeline.md E >/dev/null
tip_run "$r/run" "$sha_m"
check "check-main-tip: un cambio en gcp-datacenter/docs/ no detiene la cadena" 0 $?
tip_commit gcp-datacenter/stages/1-base/README.md F >/dev/null
tip_commit gcp-datacenter/README.md G >/dev/null
tip_run "$r/run" "$sha_m"
check "check-main-tip: un README.md de una raíz o de gcp-datacenter/ no detiene la cadena" 0 $?
tip_commit gcp-datacenter/stages/1-base/main.tf H >/dev/null
tip_run "$r/run" "$sha_m"
check "check-main-tip: después, un .tf sí deja viejo el commit (las exclusiones no tapan todo)" 1 $?
# apply.yml se dispara con las mismas rutas que el script considera del despliegue: si no, un
# commit que deja vieja a una ejecución no traería otra que la retome. Se compara qué archivos
# elige cada uno: los paths del push con la semántica de GitHub (docs.github.com, "Filter pattern
# cheat sheet": * no cruza /, ** sí; con !, el último patrón que coincide decide) y DEPLOY_PATHS
# con git ls-files en un repositorio con esos archivos.
pr_="$tmp/paths-repo"
git init -q "$pr_"
for f in gcp-datacenter/stages/1-base/main.tf gcp-datacenter/stages/1-base/README.md \
  gcp-datacenter/stages/1-base/terraform.tfvars.example gcp-datacenter/README.md \
  gcp-datacenter/modules/kms/README.md gcp-datacenter/modules/kms/main.tf \
  gcp-datacenter/modules/kms/docs/notas.md gcp-datacenter/modules/kms/docs/datos.json \
  gcp-datacenter/docs/pipeline.md gcp-datacenter/docs/adr/0029-un-solo-proyecto.md \
  gcp-datacenter/docs/diagramas/red.png gcp-datacenter/docsx/a.tf gcp-datacenter/stages/2-networks/docs.tf \
  gcp-datacenter/scripts/root-tfvars.py gcp-datacenter/policies/required_labels.rego \
  gcp-datacenter/tests/e2e/smoke_test.go gcp-datacenter/.terraform-docs.yml \
  gcp-datacenter/notas.markdown .github/workflows/apply.yml .github/workflows/README.md \
  .github/dependabot.yml README.md labs/x.tf docs/x.md; do
  mkdir -p "$pr_/$(dirname "$f")"
  echo x >"$pr_/$f"
done
gitc "$pr_" add -A
deploy_paths="$(sed -n -E 's/.*DEPLOY_PATHS:-([^}]*)\}.*/\1/p' scripts/check-main-tip.sh)"
read -r -a dp <<<"$deploy_paths"
git -C "$pr_" ls-files -- "${dp[@]}" | LC_ALL=C sort >"$tmp/paths-git.txt"
git -C "$pr_" ls-files | LC_ALL=C sort >"$tmp/paths-all.txt"
"$PY" - "$WF/apply.yml" "$tmp/paths-all.txt" "$tmp/paths-git.txt" >"$tmp/paths.txt" 2>&1 <<'PYEOF'
import re, sys
wf = open(sys.argv[1], encoding="utf-8").read()
push = wf[wf.index("  push:"):wf.index("  workflow_dispatch:")]
patterns = re.findall(r"^\s*-\s*\"([^\"]+)\"", push[push.index("paths:"):], re.M)
def to_regex(p):
    out, i = "", 0
    while i < len(p):
        if p.startswith("**", i):
            out, i = out + ".*", i + 2
        elif p[i] == "*":
            out, i = out + "[^/]*", i + 1
        elif p[i] in "?+[]":
            raise ValueError("patrón no soportado por esta prueba: %s" % p)
        else:
            out, i = out + re.escape(p[i]), i + 1
    return re.compile(out + r"\Z")
rules = [(p.startswith("!"), to_regex(p.lstrip("!"))) for p in patterns]
def github(path):
    hit = False
    for negated, rx in rules:
        if rx.match(path):
            hit = not negated
    return hit
files = open(sys.argv[2], encoding="utf-8").read().split()
gh = {f for f in files if github(f)}
git = set(open(sys.argv[3], encoding="utf-8").read().split())
must_in = {"gcp-datacenter/stages/1-base/main.tf", "gcp-datacenter/modules/kms/main.tf", ".github/workflows/apply.yml",
           "gcp-datacenter/stages/2-networks/docs.tf", "gcp-datacenter/docsx/a.tf",
           "gcp-datacenter/modules/kms/docs/datos.json", "gcp-datacenter/tests/e2e/smoke_test.go"}
must_out = {"gcp-datacenter/README.md", "gcp-datacenter/stages/1-base/README.md", "gcp-datacenter/docs/pipeline.md",
            "gcp-datacenter/docs/diagramas/red.png", "gcp-datacenter/modules/kms/docs/notas.md", "README.md", "labs/x.tf"}
bad = []
if gh != git:
    bad.append("solo apply.yml: %s; solo check-main-tip: %s" % (sorted(gh - git), sorted(git - gh)))
if not must_in <= gh:
    bad.append("faltan del despliegue: %s" % sorted(must_in - gh))
if gh & must_out:
    bad.append("sobran en el despliegue: %s" % sorted(gh & must_out))
print("; ".join(bad) if bad else "%d archivos del despliegue de %d" % (len(gh), len(files)))
sys.exit(1 if bad else 0)
PYEOF
rc=$?
check "check-main-tip: apply.yml y DEPLOY_PATHS eligen los mismos archivos ($(cat "$tmp/paths.txt"))" 0 "$rc"
# Ningún .tf lee un .md ni algo de docs/: si lo hiciera, excluirlos dejaría fuera un cambio que
# sí cambia un plan.
! grep -rEn --include='*.tf' '(file|templatefile|filebase64|fileset|filemd5|filesha256|filesha1)\([^)]*(\.md|docs/)' \
  modules stages tests/fixtures >/dev/null 2>&1
check "check-main-tip: ningún .tf lee un .md ni docs/ (las exclusiones de apply.yml no esconden cambios de un plan)" 0 $?
n="$(grep -c 'scripts/check-main-tip.sh "${GITHUB_SHA}"' "$WF/_terraform-root.yml")"
check "check-main-tip: _terraform-root.yml lo llama en plan y antes del apply (2)" 2 "$n"
# Orden en el trabajo apply: la comprobación va después de volver a planear y antes del apply.
"$PY" -c '
import sys
t = open(sys.argv[1], encoding="utf-8").read()
apply_job = t[t.index("\n  apply:"):]
a = apply_job.index("check-main-tip.sh")
b = apply_job.index("terraform apply -input=false")
sys.exit(0 if a < b else 1)
' "$WF/_terraform-root.yml"
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
' "$WF/_terraform-root.yml"
check "_terraform-root: el apply compara las variables con las del plan antes de init" 0 $?

# CODEOWNERS: lo que decide si un cambio pasa o se despliega es solo de seguridad (gana la
# última línea que coincide; aquí solo hay patrones de directorio y de archivo anclados). Las
# raíces del ADR 0029: 1-base de seguridad, 2-networks de red y 3-workloads de plataforma; sin
# rutas de etapas que ya no existen.
"$PY" -c '
import re, sys
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
want = {p: ["@PENDIENTE-seguridad"] for p in (
    "/.github/workflows/pr.yml", "/.github/CODEOWNERS", "/gcp-datacenter/scripts/plan-gate.sh",
    "/gcp-datacenter/policies/required_labels.rego", "/gcp-datacenter/stages/0-bootstrap/wif.tf",
    "/gcp-datacenter/stages/1-base/main.tf", "/gcp-datacenter/.checkov.yaml", "/gcp-datacenter/.tflint.hcl",
    "/gcp-datacenter/tests/e2e/smoke_test.go")}
want["/gcp-datacenter/stages/2-networks/main.tf"] = ["@PENDIENTE-red"]
want["/gcp-datacenter/stages/2-networks/envs/dev/main.tf"] = ["@PENDIENTE-red"]
want["/gcp-datacenter/stages/3-workloads/envs/dev/main.tf"] = ["@PENDIENTE-plataforma"]
bad = ["%s→%s" % (p, owners(p)) for p, o in want.items() if owners(p) != o]
bad += ["ruta vieja %s" % p for p, _ in rules
        if re.match(r"/gcp-datacenter/stages/(?!(0-bootstrap|1-base|2-networks|3-workloads)/)", p)]
print(", ".join(bad))
sys.exit(1 if bad else 0)
' ../.github/CODEOWNERS >"$tmp/owners.txt" 2>&1
rc=$?
check "CODEOWNERS: flujos, scripts, políticas, 0-bootstrap, 1-base, .checkov.yaml, .tflint.hcl y tests/e2e solo de seguridad; 2-networks de red; 3-workloads de plataforma $(cat "$tmp/owners.txt")" 0 "$rc"

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
gate "planes con éxito pasan" 0 GCP_ENABLED=true AFFECTED=success ROOTS='[{"root":"stages/1-base"}]' PLAN=success IS_FORK=false
gate "un plan fallido falla" 1 GCP_ENABLED=true AFFECTED=success ROOTS='[{"root":"stages/1-base"}]' PLAN=failure IS_FORK=false
gate "sin raíces afectadas y plan omitido pasa" 0 GCP_ENABLED=true AFFECTED=success ROOTS='[]' PLAN=skipped IS_FORK=false
gate "con GCP, plan omitido habiendo raíces falla" 1 GCP_ENABLED=true AFFECTED=success ROOTS='[{"root":"stages/1-base"}]' PLAN=skipped IS_FORK=false
# Fork: las variables pueden no llegar (GCP_ENABLED vacío) y el plan se omite.
gate "fork que toca raíces falla aunque GCP_ENABLED llegue vacío" 1 GCP_ENABLED= AFFECTED=success ROOTS='[{"root":"stages/1-base"}]' PLAN=skipped IS_FORK=true
gate "fork que toca raíces falla con GCP_ENABLED=true" 1 GCP_ENABLED=true AFFECTED=success ROOTS='[{"root":"stages/1-base"}]' PLAN=skipped IS_FORK=true
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
# Raíces (ADR 0029 §8): solo 3-workloads y el spoke de dev o qa.
guard "3-workloads de dev pasa" 0 raiz dev stages/3-workloads/envs/dev
guard "3-workloads de qa pasa" 0 raiz qa stages/3-workloads/envs/qa
guard "spoke 2-networks de dev pasa" 0 raiz dev stages/2-networks/envs/dev
guard "spoke 2-networks de qa pasa" 0 raiz qa stages/2-networks/envs/qa
guard "3-workloads de prod se rechaza" 1 raiz prod stages/3-workloads/envs/prod
guard "raíz de prod con entorno dev se rechaza" 1 raiz dev stages/3-workloads/envs/prod
guard "raíz de otro entorno se rechaza" 1 raiz dev stages/2-networks/envs/qa
guard "hub (stages/2-networks) se rechaza" 1 raiz dev stages/2-networks
guard "1-base se rechaza" 1 raiz dev stages/1-base
guard "0-bootstrap se rechaza" 1 raiz dev stages/0-bootstrap
guard "ruta con .. se rechaza" 1 raiz dev stages/3-workloads/envs/dev/../prod
guard "ruta con barra final se rechaza" 1 raiz dev stages/3-workloads/envs/dev/
guard "ruta de una etapa que ya no existe (4-projects) se rechaza" 1 raiz dev stages/4-projects/envs/dev
guard "sin argumentos es error de uso" 2
guard "modo desconocido es error de uso" 2 todo dev dev refs/heads/main

# Planes de destrucción reales sin GCP (Terraform 1.16.5 con google 6.50.0, 24 nov 2026; token
# ficticio: el proveedor no llama a las API para planear un borrado con -refresh=false):
#   plan-real-spoke-dev (40 recursos) y plan-real-workloads-dev (90): `plan -destroy` de
#     stages/2-networks/envs/dev y stages/3-workloads/envs/dev (ramas r1/redes y r1/cargas)
#     sobre un estado armado con su plan de creación (los valores calculados llevan IDs
#     ficticios con el formato del proveedor);
#   plan-real-protegido (17): raíz de prueba con protecciones en el estado, recursos únicos del
#     proyecto y recursos sin el prefijo del entorno;
#   plan-real-terraform-data-a y -b: dos `plan -destroy` del mismo estado con recursos integrados.
pc() { "$PY" scripts/destroy-plan-check.py "$@"; }
pc "$d/plan-real-spoke-dev.json" --env dev --summary "$tmp/destroy-red.md" \
  --root stages/2-networks/envs/dev >"$tmp/pc-red.txt" 2>&1
check "destroy-plan-check: el destroy real del spoke de dev pasa (reglas, valores de etiqueta, DNS y PSA por su padre)" 0 $?
[ "$(grep -c '^AVISO ' "$tmp/pc-red.txt")" = 1 ] &&
  grep -q '^AVISO .*google_service_networking_connection' "$tmp/pc-red.txt"
check "destroy-plan-check: el spoke solo avisa de la conexión de PSA" 0 $?
grep -q 'Recursos que se destruyen: 40' "$tmp/destroy-red.md"
check "destroy-plan-check: resumen en Markdown con los recursos que se destruyen (40)" 0 $?
pc "$d/plan-real-workloads-dev.json" --env dev --summary "$tmp/destroy-wl.md" \
  --root stages/3-workloads/envs/dev >"$tmp/pc-wl.txt" 2>&1
check "destroy-plan-check: el destroy real de 3-workloads de dev pasa (tablero por su displayName)" 0 $?
[ "$(grep -c '^AVISO ' "$tmp/pc-wl.txt")" = 2 ] && grep -q 'google_backup_dr_backup_vault' "$tmp/pc-wl.txt" &&
  grep -q 'google_storage_bucket' "$tmp/pc-wl.txt"
check "destroy-plan-check: avisa de la bóveda y del bucket sin force_destroy (2)" 0 $?
grep -q 'Recursos que se destruyen: 90' "$tmp/destroy-wl.md"
check "destroy-plan-check: el resumen cuenta los 90 recursos de 3-workloads" 0 $?
for p in spoke-dev workloads-dev; do
  pc "$d/plan-real-$p.json" --env qa >"$tmp/pc-qa.txt" 2>&1
  rc=$?
  [ "$rc" = 1 ] && grep -q '^BLOQUEO (variables)' "$tmp/pc-qa.txt" &&
    [ "$(grep -c '^BLOQUEO ' "$tmp/pc-qa.txt")" -gt "$(grep -c '^BLOQUEO (variables)' "$tmp/pc-qa.txt")" ]
  check "destroy-plan-check: el plan de dev ($p) pedido como qa se detiene (entorno y nombres)" 0 $?
done
pc "$d/plan-real-protegido.json" --env dev >"$tmp/pc2.txt" 2>&1
check "destroy-plan-check: protecciones y recursos ajenos al entorno detienen el destroy (1)" 1 $?
grep '^BLOQUEO ' "$tmp/pc2.txt" | sed 's/: .*//' >"$tmp/bloqueos.txt"
if diff -u "$d/bloqueos-esperados.txt" "$tmp/bloqueos.txt"; then
  echo "OK    destroy-plan-check: exactamente los 14 bloqueos (protecciones, proyecto, únicos del proyecto, sin prefijo del entorno)"
else
  echo "FALLA destroy-plan-check: la lista de bloqueos no coincide"
  fails=$((fails + 1))
fi
grep -q 'backup_count 3).*FALLA' "$tmp/pc2.txt"
check "destroy-plan-check: con backup_count > 0 avisa que el borrado de la bóveda falla" 0 $?
# Hijos sin nombre del entorno: un valor de etiqueta ("enabled") sin namespaced_name pasa por su
# llave, que está en el plan; sin la llave en el plan se detiene. Una regla de una política de
# firewall ajena se detiene.
"$PY" -c '
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
values = [rc for rc in p["resource_changes"] if rc["type"] == "google_tags_tag_value"]
for rc in values:
    rc["change"]["before"].pop("namespaced_name", None)
json.dump(p, open(sys.argv[2], "w", encoding="utf-8"))
p["resource_changes"] = [rc for rc in p["resource_changes"] if rc["type"] != "google_tags_tag_key"]
json.dump(p, open(sys.argv[3], "w", encoding="utf-8"))
rules = [rc for rc in p["resource_changes"] if rc["type"] == "google_compute_network_firewall_policy_rule"]
rules[0]["change"]["before"]["firewall_policy"] = "bnt-common-net-fw"
p["resource_changes"] = [rc for rc in p["resource_changes"] if rc["type"] != "google_tags_tag_value"]
json.dump(p, open(sys.argv[4], "w", encoding="utf-8"))
sys.exit(0 if values and rules else 1)
' "$d/plan-real-spoke-dev.json" "$tmp/tag-sin-ns.json" "$tmp/tag-sin-llave.json" "$tmp/regla-ajena.json"
check "destroy-plan-check: (preparación) variantes del plan del spoke" 0 $?
pc "$tmp/tag-sin-ns.json" --env dev >/dev/null 2>&1
check "destroy-plan-check: un valor de etiqueta sin namespaced_name pasa por su llave del entorno" 0 $?
pc "$tmp/tag-sin-llave.json" --env dev >"$tmp/pc-tag.txt" 2>&1
[ $? = 1 ] && [ "$(grep -c '^BLOQUEO ' "$tmp/pc-tag.txt")" = 2 ] &&
  [ "$(grep -c '^BLOQUEO .*google_tags_tag_value' "$tmp/pc-tag.txt")" = 2 ]
check "destroy-plan-check: valores de etiqueta cuya llave no está en el plan se detienen (2)" 0 $?
pc "$tmp/regla-ajena.json" --env dev >"$tmp/pc-regla.txt" 2>&1
[ $? = 1 ] && [ "$(grep -c '^BLOQUEO ' "$tmp/pc-regla.txt")" = 1 ] &&
  grep -q '^BLOQUEO .*firewall_policy_rule.*firewall_policy=bnt-common-net-fw' "$tmp/pc-regla.txt"
check "destroy-plan-check: una regla de la política de firewall de otro entorno se detiene" 0 $?
pc "$d/plan-real-terraform-data-a.json" --env dev --prefix bnt >/dev/null 2>&1
check "destroy-plan-check: plan de destrucción real de recursos integrados pasa" 0 $?
pc "$d/plan-real-terraform-data-a.json" --env dev >/dev/null 2>&1
check "destroy-plan-check: sin --prefix ni variable prefix en el plan es error (2)" 2 $?
pc "$d/plan-real-spoke-dev.json" >/dev/null 2>&1
check "destroy-plan-check: sin --env es error de uso (2)" 2 $?
"$PY" -c '
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
p["resource_changes"][0]["change"]["actions"] = ["update"]
json.dump(p, open(sys.argv[2], "w", encoding="utf-8"))
' "$d/plan-real-spoke-dev.json" "$tmp/no-destroy.json"
pc "$tmp/no-destroy.json" --env dev >/dev/null 2>&1
check "destroy-plan-check: un plan con una acción que no es delete es error (2)" 2 $?
printf '{"resource_changes": {}}' >"$tmp/rc-objeto.json"
pc "$tmp/rc-objeto.json" --env dev --prefix bnt >/dev/null 2>&1
check "destroy-plan-check: resource_changes que no es lista es error (2)" 2 $?
printf 'no es json' >"$tmp/no-json.json"
pc "$tmp/no-json.json" --env dev --prefix bnt >/dev/null 2>&1
check "destroy-plan-check: un archivo que no es JSON es error (2)" 2 $?
# La huella del plan también vale para planes de destrucción: dos planes del mismo estado, con
# distinta fecha, dan la misma huella.
fa="$("$PY" scripts/plan-fingerprint.py "$d/plan-real-terraform-data-a.json")"
fb="$("$PY" scripts/plan-fingerprint.py "$d/plan-real-terraform-data-b.json")"
[ -n "$fa" ] && [ "$fa" = "$fb" ] && ! cmp -s "$d/plan-real-terraform-data-a.json" "$d/plan-real-terraform-data-b.json"
check "plan-fingerprint: dos planes de destrucción reales distintos del mismo estado dan la misma huella" 0 $?

# destroy-orphans.py: listados del proyecto después del destroy de dev. Estados que quedan:
# 0-bootstrap, 1-base, el spoke de dev (sin incluir_red) y 3-workloads de dev ya vacío.
do_() { "$PY" scripts/destroy-orphans.py --env dev --prefix bnt --project example-landing-zone \
  --project-number 111111111111 "$@"; }
left=(--state "$u/0-bootstrap.state.json" --state "$u/1-base.state.json" --state "$d/3-workloads-dev-vacio.state.json")
do_ --assets "$d/assets-esperados.json" "${left[@]}" --state "$u/2-networks-dev.state.json" \
  --summary "$tmp/orphans.md" >"$tmp/do.txt" 2>&1
check "destroy-orphans: lo de 1-base, el spoke conservado y lo que se está borrando pasan" 0 $?
[ "$(grep -c '^ESPERADO ' "$tmp/do.txt")" = 10 ]
check "destroy-orphans: lista los 10 esperados del entorno con su motivo (los de otros entornos no cuentan)" 0 $?
do_ --assets "$d/assets-esperados.json" "${left[@]}" >"$tmp/do-red.txt" 2>&1
[ $? = 1 ] && [ "$(grep -c '^HUERFANO ' "$tmp/do-red.txt")" = 2 ] &&
  grep -q '^HUERFANO compute.googleapis.com/Network .*bnt-dev-net-spoke' "$tmp/do-red.txt"
check "destroy-orphans: sin el estado del spoke, su VPC y su subred son huérfanos (2)" 0 $?
do_ --assets "$d/assets-huerfanos.json" --state "$u/1-base.state.json" \
  --state "$d/3-workloads-dev-vacio.state.json" --summary "$tmp/orphans2.md" >"$tmp/do2.txt" 2>&1
check "destroy-orphans: recursos del entorno que sobrevivieron al destroy son huérfanos (1)" 1 $?
grep '^HUERFANO ' "$tmp/do2.txt" >"$tmp/huerfanos.txt"
if diff -u "$d/huerfanos-esperados.txt" "$tmp/huerfanos.txt"; then
  echo "OK    destroy-orphans: exactamente los 6 huérfanos esperados (por etiqueta env, nombre o correo)"
else
  echo "FALLA destroy-orphans: la lista de huérfanos no coincide"
  fails=$((fails + 1))
fi
grep -q 'huérfanos 6' "$tmp/orphans2.md"
check "destroy-orphans: resumen en Markdown con el conteo" 0 $?
do_ --assets "$d/assets-huerfanos.json" --report-only >/dev/null 2>&1
check "destroy-orphans: --report-only sale con 0" 0 $?
"$PY" scripts/destroy-orphans.py --env qa --prefix bnt --project example-landing-zone \
  --project-number 111111111111 --assets "$d/assets-huerfanos.json" >"$tmp/do-qa.txt" 2>&1
[ $? = 1 ] && [ "$(grep '^HUERFANO ' "$tmp/do-qa.txt")" = "HUERFANO storage.googleapis.com/Bucket //storage.googleapis.com/bnt-qa-data-app-usc1" ]
check "destroy-orphans: con --env qa solo cuenta lo de qa" 0 $?
for a in a-lista-vacia a-objeto-vacio a-sin-results a-sin-name a-sin-proyecto; do
  do_ --assets "$tmp/$a.json" --report-only >/dev/null 2>&1
  check "destroy-orphans: listado ${a#a-} es error aunque haya --report-only" 2 $?
done
do_ --assets "$u/assets-otro-proyecto.json" --report-only >/dev/null 2>&1
check "destroy-orphans: listado de otro proyecto es error" 2 $?
do_ --assets "$d/assets-huerfanos.json" --project X >/dev/null 2>&1
check "destroy-orphans: --project inválido es error" 2 $?
"$PY" scripts/destroy-orphans.py --env Dev --prefix bnt --project example-landing-zone \
  --project-number 111111111111 --assets "$d/assets-huerfanos.json" >/dev/null 2>&1
check "destroy-orphans: --env inválido es error" 2 $?
# Restos de GKE (ADR 0029 §8: el nombre "contiene" <prefix>-<env>-). assets-gke.json parte del
# listado de la revisión (firewall gke-bnt-dev-*, NEG k8s1-*-app-dev-*, disco pvc-* solo con
# goog-gke-volume, bnt-dev-leftover) y agrega: discos pvc-* con el namespace en la descripción o
# con la etiqueta del clúster, un firewall k8s-fw-* de un Service de app-dev, un NEG en la red
# del spoke de dev, una ruta de GCP en esa red, un disco ya borrado y restos de qa y prod. Los
# formatos de Cloud Asset son HYPOTHESIS (VERIFICAR-EN-APPLY en destroy-orphans.py).
do_ --assets "$d/assets-gke.json" --summary "$tmp/orphans-gke.md" >"$tmp/do-gke.txt" 2>&1
check "destroy-orphans: restos de GKE de dev sin estado son huérfanos (1)" 1 $?
grep '^HUERFANO ' "$tmp/do-gke.txt" >"$tmp/huerfanos-gke.txt"
if diff -u "$d/huerfanos-gke-esperados.txt" "$tmp/huerfanos-gke.txt"; then
  echo "OK    destroy-orphans: exactamente los 7 restos de dev (nombre que contiene bnt-dev-, namespace en el nombre o la descripción, etiqueta del clúster, red del spoke)"
else
  echo "FALLA destroy-orphans: la lista de restos de GKE de dev no coincide"
  fails=$((fails + 1))
fi
[ "$(grep -c '^AVISO-GKE ' "$tmp/do-gke.txt")" = 1 ] &&
  grep -q '^AVISO-GKE compute.googleapis.com/Disk .*/pvc-0f1e2d3c-' "$tmp/do-gke.txt"
check "destroy-orphans: un disco pvc-* que solo trae goog-gke-volume es aviso (sin entorno), no huérfano" 0 $?
! grep -E '^(ESPERADO|HUERFANO|AVISO-GKE) ' "$tmp/do-gke.txt" | grep -qE 'default-route|pvc-aaaaaaaa|bnt-qa-|app-qa-|app-prod-|pvc-12121212'
check "destroy-orphans: rutas de GCP en el spoke, restos borrados y restos de qa o prod no cuentan para dev" 0 $?
grep -q '| Del entorno por |' "$tmp/orphans-gke.md" && grep -q 'red del spoke' "$tmp/orphans-gke.md" &&
  grep -q 'no se pueden atribuir a ningún entorno' "$tmp/orphans-gke.md"
check "destroy-orphans: el resumen dice por qué cada resto es del entorno y lista los avisos de GKE" 0 $?
"$PY" scripts/destroy-orphans.py --env qa --prefix bnt --project example-landing-zone \
  --project-number 111111111111 --assets "$d/assets-gke.json" >"$tmp/do-gke-qa.txt" 2>&1
[ $? = 1 ] && [ "$(grep -c '^HUERFANO ' "$tmp/do-gke-qa.txt")" = 2 ] &&
  [ "$(grep -cE '^HUERFANO .*(gke-bnt-qa-app-gke-|k8s1-0f0f0f0f-app-qa-)' "$tmp/do-gke-qa.txt")" = 2 ]
check "destroy-orphans: con --env qa solo cuenta el firewall y el NEG de qa" 0 $?
"$PY" -c '
import json, sys
a = json.load(open(sys.argv[1], encoding="utf-8"))
keep = [x for x in a if x["assetType"].endswith("/Project") or "pvc-0f1e2d3c" in x["name"]]
json.dump(keep, open(sys.argv[2], "w", encoding="utf-8"))
' "$d/assets-gke.json" "$tmp/a-solo-aviso.json"
do_ --assets "$tmp/a-solo-aviso.json" >"$tmp/do-aviso.txt" 2>&1
[ $? = 0 ] && grep -q '^AVISO-GKE ' "$tmp/do-aviso.txt"
check "destroy-orphans: solo avisos de GKE sin entorno sale con 0 (los lista)" 0 $?
# La regla que bloquea (destroy-plan-check.py) sigue estricta: un nombre que contiene
# bnt-dev- sin empezar con él (gke-bnt-dev-*) se detiene; con bnt-dev- al inicio pasa.
for n in gke-bnt-dev-app-gke-1a2b3c4d-all bnt-dev-net-fw-extra; do
  printf '{"variables": {"prefix": {"value": "bnt"}, "environment": {"value": "dev"}}, "resource_changes": [{"address": "google_compute_firewall.x", "mode": "managed", "type": "google_compute_firewall", "provider_name": "registry.terraform.io/hashicorp/google", "change": {"actions": ["delete"], "before": {"name": "%s", "network": "projects/example-landing-zone/global/networks/default"}}}]}' \
    "$n" >"$tmp/pc-contiene-$n.json"
done
pc "$tmp/pc-contiene-gke-bnt-dev-app-gke-1a2b3c4d-all.json" --env dev >/dev/null 2>&1
check "destroy-plan-check: un nombre que contiene bnt-dev- sin empezar con él se detiene (regla estricta)" 1 $?
pc "$tmp/pc-contiene-bnt-dev-net-fw-extra.json" --env dev >/dev/null 2>&1
check "destroy-plan-check: el mismo recurso con bnt-dev- al inicio pasa" 0 $?

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
if not re.search(r"\n      incluir_red:\n(?:        .*\n)*?        type: boolean\n        default: false\n", on):
    bad.append("incluir_red no es booleana con false por defecto")
group = lambda t: re.search(r"^concurrency:\n\s+group: (\S+)\n\s+cancel-in-progress: false", t, re.M)
if not group(wf) or not group(apply_wf) or group(wf).group(1) != group(apply_wf).group(1):
    bad.append("concurrency distinta de apply.yml (o con cancelación)")
def job(name):
    m = re.search(r"\n  %s:\n(.*?)(?=\n  [a-z]+:\n|\Z)" % name, wf, re.S)
    return m.group(1) if m else ""
if "destroy-guard.sh pedido" not in job("gate"):
    bad.append("el trabajo gate no llama a destroy-guard.sh pedido")
conds = ("github.ref == \x27refs/heads/main\x27", "vars.GCP_ENABLED == \x27true\x27",
         "(inputs.entorno == \x27dev\x27 || inputs.entorno == \x27qa\x27)")
for name, need, stage in (("workloads", "gate", "3-workloads"), ("networks", "workloads", "2-networks"),
                          ("orphans", "[workloads, networks]", None)):
    body = job(name)
    m = re.search(r"^    if: (.*)$", body, re.M)
    cond = m.group(1) if m else ""
    if not cond or any(c not in cond for c in conds):
        bad.append("%s: if sin main, sin GCP_ENABLED o sin limitar a dev y qa" % name)
    if ("inputs.incluir_red" in cond) != (name != "workloads"):
        bad.append("%s: incluir_red mal usado en el if" % name)
    if "    needs: %s\n" % need not in body:
        bad.append("%s no espera a %s" % (name, need))
    if stage:
        want = ["root: stages/%s/envs/${{ inputs.entorno }}" % stage, "stage: %s/${{ inputs.entorno }}" % stage,
                "environment: ${{ inputs.entorno }}", "destroy: true", "uses: ./.github/workflows/_terraform-root.yml"]
        bad += ["%s sin \"%s\"" % (name, w) for w in want if w not in body]
    else:
        if "needs.workloads.result == \x27success\x27" not in cond:
            bad.append("orphans no exige que 3-workloads se haya destruido")
        for w in ("vars.GCP_AUDIT_SERVICE_ACCOUNT", "destroy-orphans.py", "--scope=\"projects/${PROJECT_ID}\"",
                  "--project-number \"${PROJECT_NUMBER}\"", "--env \"${ENV_NAME}\"", "--prefix \"${PREFIX}\""):
            if w not in body:
                bad.append("orphans sin %s" % w)
for u in re.findall(r"uses: (\S+)", wf):
    if not u.startswith("./") and not re.search(r"@[0-9a-f]{40}$", u):
        bad.append("acción sin SHA completo: %s" % u)
plan_job = root[root.index("\n  plan:"):root.index("\n  apply:")]
apply_job = root[root.index("\n  apply:"):]
for name, body in (("plan", plan_job), ("apply", apply_job)):
    g = body.find("destroy-guard.sh raiz")
    if g < 0 or g > body.index("google-github-actions/auth") or g > body.index("terraform init"):
        bad.append("_terraform-root %s: destroy-guard.sh raiz falta o va después de autenticar" % name)
    m = re.search(r"destroy-plan-check\.py[^\n]*", body)
    if not m or "--env" not in m.group(0):
        bad.append("_terraform-root %s: falta destroy-plan-check.py con --env" % name)
    if "terraform plan \"${mode[@]}\"" not in body:
        bad.append("_terraform-root %s: el plan no recibe -destroy" % name)
if apply_job.index("destroy-plan-check.py") > apply_job.index("terraform apply -input=false"):
    bad.append("_terraform-root apply: destroy-plan-check.py después de terraform apply")
if "value: ${{ jobs.plan.outputs.prefix }}" not in root or "PREFIX: ${{ needs.workloads.outputs.prefix }}" not in wf:
    bad.append("el prefijo del plan de 3-workloads no llega a orphans (salida prefix de _terraform-root)")
print("; ".join(bad))
sys.exit(1 if bad else 0)
' "$WF/destroy.yml" "$WF/apply.yml" "$WF/_terraform-root.yml" >"$tmp/destroy-wf.txt" 2>&1
rc=$?
check "destroy.yml: solo manual, dev/qa, incluir_red falso por defecto, concurrencia de apply.yml, 3-workloads → [spoke] → huérfanos del proyecto, guardias y SHA $(cat "$tmp/destroy-wf.txt")" 0 "$rc"

# Conftest sobre los planes de destrucción (las políticas no deben rechazar un plan sin `after`).
conftest_cmd="${CONFTEST_CMD:-$(command -v conftest 2>/dev/null || true)}"
[ -z "$conftest_cmd" ] && [ -x "$HOME/go/bin/conftest" ] && conftest_cmd="$HOME/go/bin/conftest"
[ -z "$conftest_cmd" ] && [ -x "$HOME/go/bin/conftest.exe" ] && conftest_cmd="$HOME/go/bin/conftest.exe"
if [ -n "$conftest_cmd" ]; then
  "$conftest_cmd" test "$d/plan-real-spoke-dev.json" "$d/plan-real-workloads-dev.json" \
    "$d/plan-real-protegido.json" --policy policies --no-color >/dev/null 2>&1
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
