#!/usr/bin/env bash
# Comprueba las políticas de Conftest sin GCP (§9.1 y §9.2 del contrato).
#
# 1. `conftest verify`: corre las pruebas de Rego de policies/*_test.rego.
# 2. Cada policies/fixtures/<regla>_pass.json debe pasar todas las políticas.
# 3. Cada policies/fixtures/<regla>_fail.json debe ser rechazado, y solo por <regla>
#    (los mensajes empiezan con "[<regla>]"). Un plan de falla que pasa es un error.
#
# Comando de Conftest: variable de entorno CONFTEST_CMD (puede llevar argumentos); si no
# está definida, `conftest` del PATH; si no, $HOME/go/bin/conftest (o conftest.exe).
# Sale con código distinto de cero ante cualquier diferencia.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "${script_dir}/.." && pwd)"
policy_dir="policies"
fixture_dir="${policy_dir}/fixtures"

find_conftest() {
  if [[ -n "${CONFTEST_CMD:-}" ]]; then
    printf '%s\n' "${CONFTEST_CMD}"
    return 0
  fi
  if command -v conftest >/dev/null 2>&1; then
    printf '%s\n' "conftest"
    return 0
  fi
  local candidate
  for candidate in "${HOME}/go/bin/conftest" "${HOME}/go/bin/conftest.exe"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

if ! conftest_line="$(find_conftest)"; then
  echo "ERROR: no se encontró conftest (defina CONFTEST_CMD o instálelo en el PATH o en \$HOME/go/bin)." >&2
  exit 2
fi
read -r -a conftest_cmd <<<"${conftest_line}"

# Rutas relativas a la raíz de gcp-datacenter: evita conversiones de ruta en Git Bash.
cd "${root_dir}" || exit 2

echo "== conftest: ${conftest_line}"
"${conftest_cmd[@]}" --version || {
  echo "ERROR: no se pudo ejecutar conftest." >&2
  exit 2
}

echo
echo "== conftest verify --policy ${policy_dir}"
if ! "${conftest_cmd[@]}" verify --policy "${policy_dir}" --no-color; then
  echo "ERROR: fallaron las pruebas de Rego." >&2
  exit 1
fi

echo
echo "== Planes de ejemplo (${fixture_dir})"
shopt -s nullglob
fixtures=("${fixture_dir}"/*_pass.json "${fixture_dir}"/*_fail.json)
shopt -u nullglob
if [[ ${#fixtures[@]} -eq 0 ]]; then
  echo "ERROR: no hay planes de ejemplo en ${fixture_dir}." >&2
  exit 1
fi

errors=0
printf '%-32s %-10s %-10s %s\n' "PLAN" "ESPERADO" "OBTENIDO" "RESULTADO"
for fixture in "${fixtures[@]}"; do
  name="$(basename "${fixture}" .json)"
  case "${name}" in
    *_pass) expected="pasa"; rule="${name%_pass}" ;;
    *_fail) expected="rechaza"; rule="${name%_fail}" ;;
  esac

  output="$("${conftest_cmd[@]}" test "${fixture}" --policy "${policy_dir}" --no-color 2>&1)"
  status=$?
  if [[ ${status} -eq 0 ]]; then actual="pasa"; else actual="rechaza"; fi

  verdict="OK"
  detail=""
  failures="$(printf '%s\n' "${output}" | grep '^FAIL - ' || true)"
  if [[ "${expected}" != "${actual}" ]]; then
    verdict="ERROR"
    detail="el resultado no coincide"
  elif [[ "${expected}" == "rechaza" ]]; then
    if [[ -z "${failures}" ]]; then
      verdict="ERROR"
      detail="conftest falló sin denegaciones (¿error de ejecución?)"
    elif ! printf '%s\n' "${failures}" | grep -qF "[${rule}]"; then
      verdict="ERROR"
      detail="ninguna denegación de [${rule}]"
    elif printf '%s\n' "${failures}" | grep -vqF "[${rule}]"; then
      verdict="ERROR"
      detail="también lo rechazan otras reglas"
    fi
  fi

  printf '%-32s %-10s %-10s %s\n' "${name}" "${expected}" "${actual}" "${verdict}${detail:+ (${detail})}"
  if [[ -n "${failures}" ]]; then
    printf '%s\n' "${failures}" | sed 's/^/    /'
  fi
  if [[ "${verdict}" != "OK" ]]; then
    errors=$((errors + 1))
    if [[ -z "${failures}" && ${status} -ne 0 ]]; then
      printf '%s\n' "${output}" | sed 's/^/    /'
    fi
  fi
done

echo
if [[ ${errors} -gt 0 ]]; then
  echo "RESULTADO: ${errors} de ${#fixtures[@]} planes no dieron el resultado esperado." >&2
  exit 1
fi
echo "RESULTADO: ${#fixtures[@]} planes con el resultado esperado."
