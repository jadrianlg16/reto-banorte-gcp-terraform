#!/usr/bin/env bash
# Regenera la sección de terraform-docs (entre <!-- BEGIN_TF_DOCS --> y <!-- END_TF_DOCS -->)
# del README.md de cada módulo y raíz de etapa, con la configuración .terraform-docs.yml.
#
# Uso: scripts/docs.sh [--check] [ruta ...]
#   Sin rutas: modules/* (con archivos .tf) y cada directorio de stages/ con versions.tf.
#   --check    No escribe nada; falla (código 1) si algún README no está al día o no existe.
#
# Compatible con bash 3.2 (macOS), Git Bash (Windows) y Linux.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

native_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
  else
    printf '%s\n' "$1"
  fi
}

display_path() {
  case "$1" in
    "$REPO_DIR"/*) printf '%s\n' "${1#"$REPO_DIR"/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

has_tf_files() {
  compgen -G "$1/*.tf" >/dev/null 2>&1
}

CHECK=0
TARGET_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1 ;;
    -h | --help)
      sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "docs.sh: opción desconocida: $1" >&2
      exit 2
      ;;
    *) TARGET_ARGS+=("$1") ;;
  esac
  shift
done

TARGETS=()
if [ ${#TARGET_ARGS[@]} -gt 0 ]; then
  for p in "${TARGET_ARGS[@]}"; do
    if [ ! -d "$p" ] || ! has_tf_files "$p"; then
      echo "docs.sh: no es un directorio con archivos .tf: $p" >&2
      exit 2
    fi
    TARGETS+=("$(cd "$p" && pwd)")
  done
else
  for d in "$REPO_DIR"/modules/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    has_tf_files "$d" && TARGETS+=("$d")
  done
  if [ -d "$REPO_DIR/stages" ]; then
    while IFS= read -r d; do
      [ -n "$d" ] && TARGETS+=("$d")
    done < <(find "$REPO_DIR/stages" -name versions.tf -type f -not -path '*/.terraform/*' |
      sed 's#/versions\.tf$##' | LC_ALL=C sort)
  fi
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
  echo "docs.sh: no hay módulos ni raíces de etapa todavía. Nada que hacer."
  exit 0
fi

if ! command -v terraform-docs >/dev/null 2>&1; then
  echo "docs.sh: terraform-docs no está en el PATH" >&2
  exit 1
fi

CONFIG="$(native_path "$REPO_DIR/.terraform-docs.yml")"
failed=0

for t in "${TARGETS[@]}"; do
  name="$(display_path "$t")"
  if [ "$CHECK" -eq 1 ]; then
    if [ ! -f "$t/README.md" ]; then
      echo "FAIL  $name (falta README.md con los marcadores BEGIN_TF_DOCS / END_TF_DOCS)"
      failed=$((failed + 1))
    elif out="$(terraform-docs -c "$CONFIG" --output-check "$(native_path "$t")" 2>&1)"; then
      echo "PASS  $name"
    else
      echo "FAIL  $name (README desactualizado: corre scripts/docs.sh $name)"
      printf '%s\n' "$out" | awk '{ print "    | " $0 }'
      failed=$((failed + 1))
    fi
  else
    if out="$(terraform-docs -c "$CONFIG" "$(native_path "$t")" 2>&1)"; then
      echo "OK    $name"
    else
      echo "FAIL  $name"
      printf '%s\n' "$out" | awk '{ print "    | " $0 }'
      failed=$((failed + 1))
    fi
  fi
done

if [ "$failed" -gt 0 ]; then
  echo "Resultado: FAIL ($failed de ${#TARGETS[@]})"
  exit 1
fi
echo "Resultado: PASS (${#TARGETS[@]})"
