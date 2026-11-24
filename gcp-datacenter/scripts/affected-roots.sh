#!/usr/bin/env bash
# Raíces de etapa afectadas por un cambio (plan por raíz de pr.yml) o todas las raíces
# (drift.yml).
#
# Uso:
#   scripts/affected-roots.sh <commit_base> [commit_cabeza]   raíces afectadas por el cambio
#   scripts/affected-roots.sh --all                           todas las raíces
# Imprime una línea "roots=<json>" (formato de $GITHUB_OUTPUT), donde <json> es una lista de
# objetos {"root": "stages/...", "stage": "<llave>", "environment": "<entorno>"} ordenada por
# ruta:
#   stage        llave de GCP_STAGE_SERVICE_ACCOUNTS (salida stage_service_accounts de
#                0-bootstrap, ADR 0029 §2): stages/<etapa> → <etapa> y
#                stages/<etapa>/envs/<env> → <etapa>/<env>. Por ejemplo stages/2-networks →
#                2-networks (hub) y stages/3-workloads/envs/dev → 3-workloads/dev.
#   environment  entorno de GitHub del apply: common para stages/<etapa> y <env> para
#                stages/<etapa>/envs/<env>.
#
# Reglas (quién afecta a quién):
#   - Una raíz es un directorio de stages/ con versions.tf. 0-bootstrap queda fuera: la aplica
#     una persona a mano y no tiene cuenta de pipeline (ADR 0029 §2).
#   - Un archivo de stages/ dentro de una raíz afecta a la raíz más profunda que lo contiene:
#     un cambio en stages/2-networks/envs/dev afecta solo al spoke dev, no al hub.
#   - Un archivo de stages/ fuera de toda raíz (por ejemplo stages/3-workloads/README.md o
#     código común en stages/3-workloads/comun/) afecta a todas las raíces que cuelgan del
#     directorio más cercano que tenga raíces debajo (las tres de stages/3-workloads/envs).
#   - Un directorio local que una raíz usa como módulo (source = "../…" o "./…", fuera de
#     modules/) la afecta, también de forma transitiva: un cambio ahí planea esa raíz aunque el
#     directorio esté dentro de otra raíz.
#   - Un cambio en modules/ o policies/ afecta a todas las raíces.
# Sale con 2 si el uso es incorrecto o si una raíz no tiene la forma stages/<etapa> ni
# stages/<etapa>/envs/<env> (no se sabría con qué cuenta planearla).
#
# Compatible con bash 3.2 (macOS), Git Bash (Windows) y Linux.

set -euo pipefail

ALL=0
case "${1:-}" in
  --all)
    [ $# -eq 1 ] || { echo "Uso: scripts/affected-roots.sh <commit_base> [commit_cabeza] | --all" >&2; exit 2; }
    ALL=1
    ;;
  "")
    echo "Uso: scripts/affected-roots.sh <commit_base> [commit_cabeza] | --all" >&2
    exit 2
    ;;
  *)
    [ $# -le 2 ] || { echo "Uso: scripts/affected-roots.sh <commit_base> [commit_cabeza] | --all" >&2; exit 2; }
    BASE="$1"
    HEAD="${2:-HEAD}"
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

ROOTS=()
if [ -d stages ]; then
  while IFS= read -r d; do
    case "$d" in
      stages/0-bootstrap | stages/0-bootstrap/*) continue ;;
    esac
    [ -n "$d" ] && ROOTS+=("$d")
  done < <(find stages -name versions.tf -type f -not -path '*/.terraform/*' |
    sed 's#/versions\.tf$##' | LC_ALL=C sort)
fi

# Llave de la cuenta y entorno de GitHub de una raíz (ADR 0029 §2).
stage_of() { # stage_of <raíz> -> "<llave> <entorno>"
  local rest="${1#stages/}"
  case "$rest" in
    */envs/*/* | */*/envs/*) return 1 ;;
    */envs/*) echo "${rest%%/*}/${rest##*/} ${rest##*/}" ;;
    */*) return 1 ;;
    *) echo "$rest common" ;;
  esac
}

for r in ${ROOTS[@]+"${ROOTS[@]}"}; do
  stage_of "$r" >/dev/null || {
    echo "ERROR: la raíz $r no tiene la forma stages/<etapa> ni stages/<etapa>/envs/<env> (ADR 0029 §2)." >&2
    exit 2
  }
done

if [ ${#ROOTS[@]} -eq 0 ]; then
  echo "roots=[]"
  exit 0
fi

# Directorios locales (fuera de modules/) que usa cada raíz como módulo, de forma transitiva.
# DEPS tiene una línea "<raíz> <directorio>" por dependencia.
local_sources() { # local_sources <directorio> -> directorios relativos a gcp-datacenter/
  local dir="$1" src abs
  for src in $(cat "$dir"/*.tf 2>/dev/null |
    sed -n -E 's#^[[:space:]]*source[[:space:]]*=[[:space:]]*"(\.\.?/[^"]*)".*#\1#p'); do
    abs="$(cd "$dir/$src" 2>/dev/null && pwd)" || continue
    case "$abs" in
      "$PROJECT_DIR"/*) echo "${abs#"$PROJECT_DIR"/}" ;;
    esac
  done
}
DEPS=""
for r in "${ROOTS[@]}"; do
  queue="$r"
  seen=" $r "
  while [ -n "$queue" ]; do
    cur="${queue%% *}"
    if [ "$cur" = "$queue" ]; then queue=""; else queue="${queue#* }"; fi
    for dep in $(local_sources "$cur"); do
      case "$dep" in modules | modules/*) continue ;; esac
      case "$seen" in *" $dep "*) continue ;; esac
      seen="$seen$dep "
      DEPS="$DEPS$r $dep
"
      queue="${queue:+$queue }$dep"
    done
  done
done

SELECTED=" "
select_root() {
  case "$SELECTED" in
    *" $1 "*) ;;
    *) SELECTED="$SELECTED$1 " ;;
  esac
}

all="$ALL"
if [ "$all" -eq 0 ]; then
  # Prefijo del proyecto dentro del repositorio git (por ejemplo "gcp-datacenter/").
  PREFIX="$(git rev-parse --show-prefix)"
  CHANGED=()
  while IFS= read -r f; do
    [ -n "$f" ] && CHANGED+=("${f#"$PREFIX"}")
  done < <(git diff --name-only "$BASE...$HEAD" -- .)

  for f in ${CHANGED[@]+"${CHANGED[@]}"}; do
    case "$f" in
      modules/* | policies/*)
        all=1
        break
        ;;
    esac
    # Raíces que usan como módulo local un directorio que contiene el archivo.
    while IFS=' ' read -r r dep; do
      [ -n "$r" ] || continue
      case "$f" in "$dep"/*) select_root "$r" ;; esac
    done <<EOF
$DEPS
EOF
    case "$f" in
      stages/*) ;;
      *) continue ;;
    esac
    best=""
    for r in "${ROOTS[@]}"; do
      case "$f" in
        "$r"/*) [ ${#r} -gt ${#best} ] && best="$r" ;;
      esac
    done
    if [ -n "$best" ]; then
      select_root "$best"
      continue
    fi
    # Fuera de toda raíz: las raíces del directorio más cercano que tenga raíces debajo.
    d="$(dirname "$f")"
    while [ "$d" != "." ] && [ "$d" != "/" ]; do
      found=0
      for r in "${ROOTS[@]}"; do
        case "$r" in
          "$d"/*)
            select_root "$r"
            found=1
            ;;
        esac
      done
      [ "$found" -eq 1 ] && break
      d="$(dirname "$d")"
    done
  done
fi

json="["
sep=""
for r in "${ROOTS[@]}"; do
  if [ "$all" -eq 0 ]; then
    case "$SELECTED" in
      *" $r "*) ;;
      *) continue ;;
    esac
  fi
  set -- $(stage_of "$r")
  json="$json$sep{\"root\":\"$r\",\"stage\":\"$1\",\"environment\":\"$2\"}"
  sep=","
done
json="$json]"

echo "roots=$json"
