#!/usr/bin/env bash
# Pruebas de integración (tests/integration) de un módulo, como expresión para `go test -run`.
#
# Uso: scripts/module-tests.sh <módulo>
#   Imprime "^(TestA|TestB)$" con las funciones Test* que aplican tests/fixtures/<módulo> o una
#   variante tests/fixtures/<módulo>-<algo> (p. ej. firewall-hierarchical). Sale con 1 si el
#   módulo no existe en modules/ o si ninguna prueba lo usa.
#
# Lo usa terratest.yml con las etiquetas modules/<módulo>/vX.Y.Z: la etiqueta de un módulo
# corre solo sus pruebas. Compatible con bash 3.2 (macOS), Git Bash y Linux.

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Uso: scripts/module-tests.sh <módulo>" >&2
  exit 2
fi
module="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

case "$module" in
  '' | *[!a-z0-9-]*)
    echo "ERROR: nombre de módulo inválido: '$module'" >&2
    exit 1
    ;;
esac
if [ ! -d "$PROJECT_DIR/modules/$module" ]; then
  echo "ERROR: no existe modules/$module" >&2
  exit 1
fi

# awk recuerda la función Test* en curso y la imprime cuando ve FixtureOptions(t, "<fixture>"
# con el fixture del módulo.
names="$(awk -v m="$module" '
  /^func Test[A-Za-z0-9_]*\(/ {
    fn = $2
    sub(/\(.*/, "", fn)
  }
  match($0, /FixtureOptions\(t, "[a-z0-9-]+"/) {
    f = substr($0, RSTART, RLENGTH)
    sub(/^FixtureOptions\(t, "/, "", f)
    sub(/"$/, "", f)
    if (fn != "" && (f == m || index(f, m "-") == 1)) print fn
  }
' "$PROJECT_DIR"/tests/integration/*_test.go | LC_ALL=C sort -u)"

if [ -z "$names" ]; then
  echo "ERROR: ninguna prueba de tests/integration usa tests/fixtures/$module" >&2
  exit 1
fi
printf '^(%s)$\n' "$(printf '%s\n' "$names" | paste -sd '|' -)"
