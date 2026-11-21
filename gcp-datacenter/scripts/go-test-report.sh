#!/usr/bin/env bash
# Resumen de una corrida de `go test -json` y control de pruebas omitidas.
#
# Uso: scripts/go-test-report.sh <salida-de-go-test-json> <máximo-de-omitidas> [resumen.md]
#
# Cuenta las pruebas (y subpruebas) que pasaron, fallaron y se omitieron (t.Skip), lista las
# omitidas con su motivo y sale con:
#   0  ninguna falló y las omitidas no pasan del máximo;
#   1  alguna falló, o hay más omitidas que el máximo (una omisión silenciosa no deja pasar
#      la corrida: hay que aceptarla subiendo el máximo a propósito);
#   2  error de uso o archivo ilegible.
# Si se da [resumen.md], agrega allí el resumen en Markdown (por ejemplo $GITHUB_STEP_SUMMARY).
#
# Solo bash, grep y sed (sin jq): compatible con bash 3.2 (macOS), Git Bash y Linux.

set -uo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Uso: scripts/go-test-report.sh <salida-json> <máximo-de-omitidas> [resumen.md]" >&2
  exit 2
fi
log="$1"
max="$2"
summary="${3:-}"
case "$max" in
  '' | *[!0-9]*)
    echo "ERROR: el máximo de omitidas debe ser un entero >= 0 (recibido: '$max')." >&2
    exit 2
    ;;
esac
if [ ! -r "$log" ]; then
  echo "ERROR: no se puede leer $log" >&2
  exit 2
fi

# Líneas de evento de una prueba: {"Time":...,"Action":"pass","Package":"...","Test":"TestX",...}
test_events() {
  grep -E "\"Action\":\"$1\"" "$log" | grep -E '"Test":"' |
    sed -E 's/.*"Package":"([^"]*)".*"Test":"([^"]*)".*/\1 \2/' | LC_ALL=C sort -u
}

passed="$(test_events pass)"
failed="$(test_events fail)"
skipped="$(test_events skip)"
count() { if [ -z "$1" ]; then echo 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi; }
n_pass="$(count "$passed")"
n_fail="$(count "$failed")"
n_skip="$(count "$skipped")"

# Motivo de cada omisión: la línea de salida "    x_test.go:NN: se omite: ..." de esa prueba.
skip_reason() {
  grep -F "\"Test\":\"$2\"" "$log" | grep -F "\"Package\":\"$1\"" | grep -E '"Action":"output"' |
    grep -E 'se omite|SKIP|Skip' | grep -v -- '--- SKIP' | head -n 1 |
    sed -E 's/.*"Output":"(.*)"[^"]*$/\1/; s/\\n$//; s/\\t/ /g; s/^ +//'
}

echo "Pruebas: ${n_pass} pasaron, ${n_fail} fallaron, ${n_skip} omitidas (máximo aceptado: ${max})."
if [ -n "$skipped" ]; then
  echo "Omitidas:"
  printf '%s\n' "$skipped" | while read -r pkg name; do
    echo "  ${name} (${pkg##*/}): $(skip_reason "$pkg" "$name")"
  done
fi
if [ -n "$failed" ]; then
  echo "Fallaron:"
  printf '%s\n' "$failed" | sed 's/^/  /'
fi

status=0
verdict="OK"
if [ "$n_fail" -gt 0 ]; then
  status=1
  verdict="FALLA: ${n_fail} prueba(s) fallaron"
elif [ "$n_skip" -gt "$max" ]; then
  status=1
  verdict="FALLA: ${n_skip} pruebas omitidas, más que el máximo aceptado (${max})"
elif [ "$((n_pass + n_fail + n_skip))" -eq 0 ]; then
  status=1
  verdict="FALLA: no corrió ninguna prueba"
fi
echo "Resultado: ${verdict}"

if [ -n "$summary" ]; then
  {
    echo "| Pasaron | Fallaron | Omitidas | Máximo de omitidas |"
    echo "|---|---|---|---|"
    echo "| ${n_pass} | ${n_fail} | ${n_skip} | ${max} |"
    echo
    echo "**${verdict}**"
    if [ -n "$skipped" ]; then
      echo
      echo "| Omitida | Paquete | Motivo |"
      echo "|---|---|---|"
      printf '%s\n' "$skipped" | while read -r pkg name; do
        echo "| \`${name}\` | \`${pkg##*/}\` | $(skip_reason "$pkg" "$name" | sed 's/|/\\|/g') |"
      done
    fi
    echo
  } >>"$summary"
fi
exit "$status"
