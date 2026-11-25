#!/usr/bin/env bash
# Decisión del trabajo plan-gate de pr.yml (comprobación obligatoria que resume los planes).
# Lee el resultado de los trabajos por variables de entorno:
#   GCP_ENABLED  vars.GCP_ENABLED
#   AFFECTED     needs.affected.result (success, failure, cancelled, skipped)
#   ROOTS        needs.affected.outputs.roots (JSON; "[]" sin raíces afectadas)
#   PLAN         needs.plan.result
#   IS_FORK      "true" si la rama del PR es de un fork
#   SUMMARY      archivo del resumen (por defecto $GITHUB_STEP_SUMMARY o /dev/null)
# Sale con 0 si el PR puede pasar y con 1 si no.
#
# Forks: un PR desde un fork no recibe token OIDC ni, según la documentación de GitHub, las
# variables del repositorio (HIPÓTESIS, docs/pipeline.md §1.1): no se puede planear. Sin esta
# regla, GCP_ENABLED llegaría vacío y el PR pasaría como si GCP estuviera apagado. Si el fork
# toca alguna raíz, plan-gate falla con un mensaje claro; si no toca ninguna, pasa.

set -uo pipefail

GCP_ENABLED="${GCP_ENABLED:-}"
AFFECTED="${AFFECTED:-}"
ROOTS="${ROOTS:-}"
PLAN="${PLAN:-}"
IS_FORK="${IS_FORK:-false}"
SUMMARY="${SUMMARY:-${GITHUB_STEP_SUMMARY:-/dev/null}}"

echo "gcp_enabled=${GCP_ENABLED} fork=${IS_FORK} affected=${AFFECTED} plan=${PLAN} roots=${ROOTS}"

fail() {
  echo "::error::$1"
  echo "plan-gate: FALLA. $1" >>"${SUMMARY}"
  exit 1
}
pass() {
  echo "plan-gate: $1" >>"${SUMMARY}"
  echo "OK: $1"
  exit 0
}

for r in "${AFFECTED}" "${PLAN}"; do
  case "${r}" in
    failure | cancelled) fail "Un trabajo de plan o de raíces afectadas terminó en ${r}." ;;
  esac
done

if [ "${IS_FORK}" = "true" ]; then
  [ "${AFFECTED}" = "success" ] || fail "PR desde un fork: no se calcularon las raíces afectadas (resultado: ${AFFECTED})."
  if [ "${ROOTS}" != "[]" ]; then
    fail "PR desde un fork que cambia raíces de Terraform (${ROOTS}): los PR de forks no reciben token OIDC ni las variables del repositorio, así que no se puede planear ni pasar Conftest sobre el plan real. Una persona con escritura debe subir la rama al repositorio y abrir el PR desde ahí (docs/pipeline.md §1.1)."
  fi
  pass "PR desde un fork sin raíces de Terraform afectadas; no hay planes que revisar."
fi

if [ "${GCP_ENABLED}" != "true" ]; then
  pass "GCP_ENABLED no es \"true\"; no hay planes que revisar (solo cuentan las comprobaciones sin GCP)."
fi
[ "${AFFECTED}" = "success" ] || fail "No se calcularon las raíces afectadas (resultado: ${AFFECTED})."
if [ "${ROOTS}" = "[]" ]; then
  [ "${PLAN}" = "skipped" ] || fail "Sin raíces afectadas, el plan debía omitirse (resultado: ${PLAN})."
  pass "ninguna raíz afectada."
fi
[ "${PLAN}" = "success" ] || fail "Los planes no terminaron con éxito (resultado: ${PLAN})."
pass "todos los planes y su Conftest pasaron."
