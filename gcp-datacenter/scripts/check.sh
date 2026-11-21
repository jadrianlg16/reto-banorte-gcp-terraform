#!/usr/bin/env bash
# Revisión estática y pruebas unitarias sin GCP (CONTRATO §1.2 y §9.2).
#
# Corre, por cada objetivo (módulo, ejemplo o raíz de etapa):
#   fmt       terraform fmt -check -recursive
#   validate  terraform init -backend=false -input=false  +  terraform validate
#   tflint    tflint con la configuración del repositorio (.tflint.hcl)
#   checkov   $CHECKOV_CMD con .checkov.yaml
#   test      terraform test, solo si el objetivo tiene tests/*.tftest.hcl
#
# No se detiene en la primera falla: corre todo, imprime un resumen por objetivo y paso, y
# termina con código distinto de cero si algo falló. Ver --help.
#
# Compatible con bash 3.2 (macOS), Git Bash (Windows) y Linux: sin arreglos asociativos ni
# mapfile.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ALL_STEPS="fmt validate tflint checkov test"

usage() {
  cat <<'EOF'
Uso: scripts/check.sh [opciones] [ruta ...]

Cada ruta es un directorio de módulo, de ejemplo o una raíz de etapa (relativa al directorio
actual o absoluta). Sin rutas, descubre todo lo que hay en el repositorio:
  modules/*                  (directorios con archivos .tf)
  modules/*/examples/*       (directorios con archivos .tf)
  stages/**                  (directorios que contienen versions.tf)

Pasos, en orden: fmt, validate, tflint, checkov, test.
  test solo corre si el objetivo tiene tests/*.tftest.hcl (si no, aparece como N/A).

Opciones:
  --skip PASOS     Pasos a omitir, separados por comas; se puede repetir.
                   Ejemplo: --skip checkov  o  --skip tflint,checkov
  --list           Solo lista los objetivos que se revisarían y termina.
  -v, --verbose    Muestra también la salida de los pasos que pasan.
  -h, --help       Muestra esta ayuda.

Variables de entorno:
  CHECKOV_CMD           Comando de checkov; puede tener varias palabras. Por defecto: checkov.
                        En Windows con uv: "uvx --from checkov python -m checkov.main".
  TF_PLUGIN_CACHE_DIR   Caché compartida de proveedores. Por defecto:
                        $HOME/.terraform.d/plugin-cache (se crea si no existe).
                        La caché no es segura con varias ejecuciones simultáneas: no corras
                        dos check.sh en paralelo con la misma caché.

Códigos de salida: 0 todo pasó (o no hay objetivos), 1 algún paso falló, 2 error de uso.
EOF
}

# Convierte una ruta de Git Bash (/c/...) a una que entiendan los ejecutables nativos de
# Windows (C:/...). En macOS y Linux no hay cygpath y la ruta queda igual.
native_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
  else
    printf '%s\n' "$1"
  fi
}

# Ruta para mostrar: relativa al repositorio si está dentro de él.
display_path() {
  case "$1" in
    "$REPO_DIR") printf '.\n' ;;
    "$REPO_DIR"/*) printf '%s\n' "${1#"$REPO_DIR"/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

has_tf_files() {
  compgen -G "$1/*.tf" >/dev/null 2>&1
}

is_skipped() {
  case " $SKIP_STEPS " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------------------
# Argumentos

SKIP_STEPS=""
VERBOSE=0
LIST_ONLY=0
TARGET_ARGS=()

add_skips() {
  local raw="$1" s
  local IFS=','
  for s in $raw; do
    s="${s// /}"
    [ -z "$s" ] && continue
    case " $ALL_STEPS " in
      *" $s "*) SKIP_STEPS="$SKIP_STEPS $s" ;;
      *)
        echo "check.sh: paso desconocido en --skip: '$s' (válidos: $ALL_STEPS)" >&2
        exit 2
        ;;
    esac
  done
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -v | --verbose)
      VERBOSE=1
      ;;
    --list)
      LIST_ONLY=1
      ;;
    --skip)
      if [ $# -lt 2 ]; then
        echo "check.sh: --skip necesita una lista de pasos" >&2
        exit 2
      fi
      add_skips "$2"
      shift
      ;;
    --skip=*)
      add_skips "${1#--skip=}"
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do
        TARGET_ARGS+=("$1")
        shift
      done
      break
      ;;
    -*)
      echo "check.sh: opción desconocida: $1 (usa --help)" >&2
      exit 2
      ;;
    *)
      TARGET_ARGS+=("$1")
      ;;
  esac
  shift
done

# ---------------------------------------------------------------------------------------
# Objetivos

TARGETS=()

add_target() {
  local t="$1" existing
  for existing in ${TARGETS[@]+"${TARGETS[@]}"}; do
    [ "$existing" = "$t" ] && return 0
  done
  TARGETS+=("$t")
}

if [ ${#TARGET_ARGS[@]} -gt 0 ]; then
  for p in "${TARGET_ARGS[@]}"; do
    if [ ! -d "$p" ]; then
      echo "check.sh: no existe el directorio: $p" >&2
      exit 2
    fi
    abs="$(cd "$p" && pwd)"
    if ! has_tf_files "$abs"; then
      echo "check.sh: el directorio no tiene archivos .tf: $p" >&2
      exit 2
    fi
    add_target "$abs"
  done
else
  for d in "$REPO_DIR"/modules/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    has_tf_files "$d" && add_target "$d"
  done
  for d in "$REPO_DIR"/modules/*/examples/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    has_tf_files "$d" && add_target "$d"
  done
  if [ -d "$REPO_DIR/stages" ]; then
    # Se ordenan los directorios (no los archivos) para que el hub quede antes que sus envs/.
    while IFS= read -r d; do
      [ -n "$d" ] && add_target "$d"
    done < <(find "$REPO_DIR/stages" -name versions.tf -type f -not -path '*/.terraform/*' |
      sed 's#/versions\.tf$##' | LC_ALL=C sort)
  fi
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
  echo "check.sh: no hay objetivos que revisar (sin módulos con .tf en modules/ ni raíces con versions.tf en stages/). Nada que hacer."
  exit 0
fi

if [ "$LIST_ONLY" -eq 1 ]; then
  for t in "${TARGETS[@]}"; do
    display_path "$t"
  done
  exit 0
fi

# ---------------------------------------------------------------------------------------
# Entorno y herramientas

: "${TF_PLUGIN_CACHE_DIR:=$HOME/.terraform.d/plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"
TF_PLUGIN_CACHE_DIR="$(native_path "$TF_PLUGIN_CACHE_DIR")"
export TF_PLUGIN_CACHE_DIR
export TF_IN_AUTOMATION=1
export TF_INPUT=0
export CHECKPOINT_DISABLE=1
# Salida sin códigos de color (checkov usa termcolor, que respeta estas variables).
export NO_COLOR=1
export ANSI_COLORS_DISABLED=1

CHECKOV_CMD="${CHECKOV_CMD:-checkov}"
read -r -a CHECKOV_ARGV <<<"$CHECKOV_CMD"

TFLINT_CONFIG="$(native_path "$REPO_DIR/.tflint.hcl")"
CHECKOV_CONFIG="$(native_path "$REPO_DIR/.checkov.yaml")"

LOG_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t checksh)"
trap 'rm -rf "$LOG_DIR"' EXIT

# Motivo por el que un paso no puede correr en ningún objetivo (herramienta ausente, etc.).
UNAVAILABLE_fmt=""
UNAVAILABLE_validate=""
UNAVAILABLE_tflint=""
UNAVAILABLE_checkov=""
UNAVAILABLE_test=""

if ! command -v terraform >/dev/null 2>&1; then
  UNAVAILABLE_fmt="terraform no está en el PATH"
  UNAVAILABLE_validate="$UNAVAILABLE_fmt"
  UNAVAILABLE_test="$UNAVAILABLE_fmt"
fi

if ! is_skipped tflint; then
  if ! command -v tflint >/dev/null 2>&1; then
    UNAVAILABLE_tflint="tflint no está en el PATH"
  else
    echo "== tflint --init (plugins de .tflint.hcl)"
    if ! tflint --init --config "$TFLINT_CONFIG" >"$LOG_DIR/tflint-init.log" 2>&1; then
      awk '{ print "    | " $0 }' "$LOG_DIR/tflint-init.log"
      UNAVAILABLE_tflint="tflint --init falló (ver salida arriba)"
    fi
  fi
fi

if ! is_skipped checkov; then
  if [ ${#CHECKOV_ARGV[@]} -eq 0 ] || ! command -v "${CHECKOV_ARGV[0]}" >/dev/null 2>&1; then
    UNAVAILABLE_checkov="no se encontró el comando de checkov: '$CHECKOV_CMD' (define CHECKOV_CMD)"
  fi
fi

unavailable_reason() {
  eval "printf '%s' \"\$UNAVAILABLE_$1\""
}

# ---------------------------------------------------------------------------------------
# Ejecución

ROWS=()      # una fila por objetivo: "fmt validate tflint checkov test" con su estado
FAILED_STEPS=0
FAILED_TARGETS=0

# awk (y no sed) para que la última línea siempre termine en salto de línea; quita los
# códigos de color ANSI que checkov imprime aunque se le pida salida sin color.
print_log() {
  awk '{ gsub(/\033\[[0-9;]*m/, ""); print "    | " $0 }' "$1"
}

# run_step <paso> <dir> <log> <comando...>; deja el estado en STEP_STATUS.
run_step() {
  local step="$1" dir="$2" log="$3"
  shift 3
  local reason
  reason="$(unavailable_reason "$step")"
  if [ -n "$reason" ]; then
    echo "$reason" >"$log"
    STEP_STATUS="FAIL"
  elif (cd "$dir" && "$@") >>"$log" 2>&1; then
    STEP_STATUS="PASS"
  else
    STEP_STATUS="FAIL"
  fi
  printf '  %-4s  %s\n' "$STEP_STATUS" "$step"
  if [ "$STEP_STATUS" = "FAIL" ] || [ "$VERBOSE" -eq 1 ]; then
    print_log "$log"
  fi
}

# Con `--skip test`, init y validate no leen tests/*.tftest.hcl: los archivos de prueba pueden
# usar atributos posteriores a la versión mínima de Terraform (override_during, 1.11), y init
# y validate de una versión anterior fallarían al leerlos. La pata 1.9.8 de pr.yml usa esto.
# Un directorio de pruebas que no existe hace que init no lea ninguno (flags desde 1.6).
NO_TESTS_INIT=""
NO_TESTS_VALIDATE=""
if is_skipped test; then
  NO_TESTS_INIT="-test-directory=.check-sh-sin-pruebas"
  NO_TESTS_VALIDATE="-no-tests"
fi

report_status() {
  printf '  %-4s  %s\n' "$1" "$2"
}

idx=0
for target in "${TARGETS[@]}"; do
  idx=$((idx + 1))
  name="$(display_path "$target")"
  log_prefix="$LOG_DIR/$idx"
  echo
  echo "== [$idx/${#TARGETS[@]}] $name"

  # Las raíces de etapa (con backend.tf) versionan su .terraform.lock.hcl con los hashes de
  # las tres plataformas (§4.1); ahí la caché se usa sin más. En módulos y ejemplos el lock
  # no se versiona, y sin este permiso terraform descargaría el proveedor en cada objetivo.
  if [ -f "$target/backend.tf" ]; then
    lock_env=""
  else
    lock_env="${TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE:-true}"
  fi

  # fmt
  if is_skipped fmt; then
    s_fmt="SKIP"; report_status SKIP fmt
  else
    run_step fmt "$target" "$log_prefix-fmt.log" terraform fmt -check -recursive -diff -no-color
    s_fmt="$STEP_STATUS"
  fi

  # validate (init + validate)
  init_ok=0
  if is_skipped validate && is_skipped test; then
    s_validate="SKIP"; report_status SKIP validate
  else
    log="$log_prefix-validate.log"
    reason="$(unavailable_reason validate)"
    if [ -n "$reason" ]; then
      echo "$reason" >"$log"
    else
      echo "\$ terraform init -backend=false -input=false${NO_TESTS_INIT:+ $NO_TESTS_INIT}" >"$log"
      if (cd "$target" && env ${lock_env:+TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE="$lock_env"} \
        terraform init -backend=false -input=false -no-color ${NO_TESTS_INIT:+"$NO_TESTS_INIT"}) >>"$log" 2>&1; then
        init_ok=1
      fi
    fi
    if is_skipped validate; then
      s_validate="SKIP"; report_status SKIP validate
      if [ "$init_ok" -eq 0 ]; then
        echo "  (init falló; se necesita para test)"; print_log "$log"
      fi
    elif [ "$init_ok" -eq 1 ]; then
      echo "\$ terraform validate${NO_TESTS_VALIDATE:+ $NO_TESTS_VALIDATE}" >>"$log"
      run_step validate "$target" "$log" terraform validate -no-color ${NO_TESTS_VALIDATE:+"$NO_TESTS_VALIDATE"}
      s_validate="$STEP_STATUS"
    else
      s_validate="FAIL"; report_status FAIL validate; print_log "$log"
    fi
  fi

  # tflint
  if is_skipped tflint; then
    s_tflint="SKIP"; report_status SKIP tflint
  else
    run_step tflint "$target" "$log_prefix-tflint.log" \
      tflint --config "$TFLINT_CONFIG" --format compact --no-color
    s_tflint="$STEP_STATUS"
  fi

  # checkov
  if is_skipped checkov; then
    s_checkov="SKIP"; report_status SKIP checkov
  else
    run_step checkov "$target" "$log_prefix-checkov.log" \
      ${CHECKOV_ARGV[@]+"${CHECKOV_ARGV[@]}"} --config-file "$CHECKOV_CONFIG" -d .
    s_checkov="$STEP_STATUS"
  fi

  # test
  if is_skipped test; then
    s_test="SKIP"; report_status SKIP test
  elif ! compgen -G "$target/tests/*.tftest.hcl" >/dev/null 2>&1; then
    s_test="N/A"; report_status N/A "test (sin tests/*.tftest.hcl)"
  elif [ "$init_ok" -eq 0 ]; then
    s_test="FAIL"; report_status FAIL "test (terraform init falló; ver validate)"
  else
    run_step test "$target" "$log_prefix-test.log" terraform test -no-color
    s_test="$STEP_STATUS"
  fi

  row="$s_fmt $s_validate $s_tflint $s_checkov $s_test"
  ROWS+=("$row")
  n_fail=0
  for s in $row; do
    [ "$s" = "FAIL" ] && n_fail=$((n_fail + 1))
  done
  if [ "$n_fail" -gt 0 ]; then
    FAILED_STEPS=$((FAILED_STEPS + n_fail))
    FAILED_TARGETS=$((FAILED_TARGETS + 1))
  fi
done

# ---------------------------------------------------------------------------------------
# Resumen

width=8
for target in "${TARGETS[@]}"; do
  n="$(display_path "$target")"
  [ ${#n} -gt "$width" ] && width=${#n}
done

echo
echo "== Resumen"
printf "%-${width}s  %-8s %-8s %-8s %-8s %-8s\n" "OBJETIVO" fmt validate tflint checkov test
i=0
for target in "${TARGETS[@]}"; do
  # shellcheck disable=SC2086
  printf "%-${width}s  %-8s %-8s %-8s %-8s %-8s\n" "$(display_path "$target")" ${ROWS[$i]}
  i=$((i + 1))
done
echo

if [ "$FAILED_STEPS" -gt 0 ]; then
  echo "Resultado: FAIL ($FAILED_STEPS paso(s) fallaron en $FAILED_TARGETS de ${#TARGETS[@]} objetivo(s))"
  exit 1
fi
echo "Resultado: PASS (${#TARGETS[@]} objetivo(s))"
exit 0
