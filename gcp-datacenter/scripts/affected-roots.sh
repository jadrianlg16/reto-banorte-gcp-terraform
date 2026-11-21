#!/usr/bin/env bash
# Lista las raíces de etapa afectadas por un cambio, para el plan por raíz de pr.yml.
#
# Uso: scripts/affected-roots.sh <commit_base> [commit_cabeza]
#   Imprime una línea "roots=<json>" (formato de $GITHUB_OUTPUT), donde <json> es una lista
#   de objetos {"root": "stages/...", "stage": "N-nombre"} ordenada por ruta.
#
# Reglas:
#   - Una raíz es un directorio de stages/ con versions.tf. 0-bootstrap queda fuera: la
#     aplica un administrador a mano y no tiene cuenta de servicio de pipeline (CONTRATO §6.1).
#   - Un archivo de stages/ afecta a la raíz más profunda que lo contiene (un cambio en
#     stages/3-networks/envs/dev afecta solo al spoke dev, no al hub).
#   - Un cambio en modules/ o policies/ afecta a todas las raíces.
#
# Compatible con bash 3.2 (macOS), Git Bash (Windows) y Linux.

set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "Uso: scripts/affected-roots.sh <commit_base> [commit_cabeza]" >&2
  exit 2
fi
BASE="$1"
HEAD="${2:-HEAD}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

# Prefijo del proyecto dentro del repositorio git (por ejemplo "gcp-datacenter/").
PREFIX="$(git rev-parse --show-prefix)"

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

if [ ${#ROOTS[@]} -eq 0 ]; then
  echo "roots=[]"
  exit 0
fi

CHANGED=()
while IFS= read -r f; do
  [ -n "$f" ] && CHANGED+=("${f#"$PREFIX"}")
done < <(git diff --name-only "$BASE...$HEAD" -- .)

all=0
SELECTED=" "
for f in ${CHANGED[@]+"${CHANGED[@]}"}; do
  case "$f" in
    modules/* | policies/*)
      all=1
      break
      ;;
    stages/*)
      best=""
      for r in "${ROOTS[@]}"; do
        case "$f" in
          "$r"/*)
            [ ${#r} -gt ${#best} ] && best="$r"
            ;;
        esac
      done
      if [ -n "$best" ]; then
        case "$SELECTED" in
          *" $best "*) ;;
          *) SELECTED="$SELECTED$best " ;;
        esac
      fi
      ;;
  esac
done

json="["
sep=""
for r in "${ROOTS[@]}"; do
  if [ "$all" -eq 1 ]; then
    :
  else
    case "$SELECTED" in
      *" $r "*) ;;
      *) continue ;;
    esac
  fi
  stage="${r#stages/}"
  stage="${stage%%/*}"
  json="$json$sep{\"root\":\"$r\",\"stage\":\"$stage\"}"
  sep=","
done
json="$json]"

echo "roots=$json"
