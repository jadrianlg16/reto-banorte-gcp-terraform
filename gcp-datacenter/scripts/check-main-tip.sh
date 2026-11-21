#!/usr/bin/env bash
# Comprueba que un commit sigue siendo la punta de una rama del remoto (por defecto, main de
# origin). Lo usa _terraform-root.yml antes de planear y otra vez justo antes del apply: una
# ejecución vieja de apply.yml que se vuelve a correr ("Re-run jobs") trae el github.sha de su
# momento y, si main avanzó, aplicaría código anterior encima de lo ya aplicado.
#
# Uso: scripts/check-main-tip.sh <sha> [remoto] [rama]
# Sale con 0 si <sha> es la punta, 1 si no lo es, 2 si no se pudo leer el remoto o falta el sha.
# Usa `git ls-remote`, así que funciona con el checkout superficial (fetch-depth 1) de Actions.

set -uo pipefail

sha="${1:-}"
remote="${2:-origin}"
branch="${3:-main}"

if [ -z "${sha}" ]; then
  echo "Uso: $0 <sha> [remoto] [rama]" >&2
  exit 2
fi

tip="$(git ls-remote "${remote}" "refs/heads/${branch}" 2>/dev/null | cut -f1)"
if [ -z "${tip}" ]; then
  echo "::error::No se pudo leer refs/heads/${branch} de ${remote}; no se continúa." >&2
  exit 2
fi

if [ "${tip}" != "${sha}" ]; then
  echo "::error::Esta ejecución es del commit ${sha}, pero la punta de ${branch} ya es ${tip}." \
    "No se planea ni se aplica código viejo: si es un 'Re-run' de una ejecución anterior, correr" \
    "apply.yml de nuevo (workflow_dispatch sobre ${branch}) o esperar la ejecución del último push." >&2
  exit 1
fi

echo "OK: ${sha} es la punta de ${remote}/${branch}."
