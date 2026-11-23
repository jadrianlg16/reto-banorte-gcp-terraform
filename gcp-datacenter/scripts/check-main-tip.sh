#!/usr/bin/env bash
# ¿Sigue vigente el commit de esta ejecución para desplegar? Lo usa _terraform-root.yml antes de
# planear y otra vez justo antes del apply.
#
# Regla: <sha> está en la rama (por defecto main de origin) y ningún commit posterior de la rama
# cambia las rutas que afectan un despliegue (por defecto gcp-datacenter/ y .github/workflows/,
# desde la raíz del repositorio). Así:
# - una ejecución vieja que se vuelve a correr ("Re-run jobs"), o una aprobación que llega
#   después de otro merge que sí cambia Terraform o los flujos, falla sin planear ni aplicar
#   código viejo encima de lo que ya aplicó una ejecución más nueva;
# - un merge que no toca esas rutas (README de la raíz, labs/, la configuración de Dependabot)
#   no detiene la cadena en curso. apply.yml solo se dispara con cambios en gcp-datacenter/**,
#   así que ese merge no traería otra ejecución que la retome.
#
# Uso: scripts/check-main-tip.sh <sha> [remoto] [rama]
# Variables: DEPLOY_PATHS (rutas separadas por espacio, desde la raíz del repositorio).
# Sale con 0 si está vigente, 1 si no, 2 si no se puede decidir (falla cerrado): sin sha, remoto
# ilegible, historia superficial que no se puede completar o <sha> desconocido.
#
# Necesita la historia de la rama: con un clon superficial (actions/checkout con fetch-depth 1)
# intenta completarla con `git fetch --unshallow`; si sigue superficial, sale con 2.

set -uo pipefail

sha="${1:-}"
remote="${2:-origin}"
branch="${3:-main}"
read -r -a paths <<<"${DEPLOY_PATHS:-gcp-datacenter .github/workflows}"

err() { # err <código> <mensaje>
  echo "::error::$2" >&2
  exit "$1"
}

[ -n "${sha}" ] || err 2 "Uso: $0 <sha> [remoto] [rama]"
top="$(git rev-parse --show-toplevel 2>/dev/null)" || err 2 "No es un repositorio de git."
cd "${top}" || err 2 "No se pudo entrar a ${top}."

ref="refs/remotes/${remote}/${branch}"
git fetch --quiet --no-tags "${remote}" "+refs/heads/${branch}:${ref}" 2>/dev/null ||
  err 2 "No se pudo leer ${branch} de ${remote}; no se continúa."
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
  git fetch --quiet --no-tags --unshallow "${remote}" "+refs/heads/${branch}:${ref}" 2>/dev/null ||
    err 2 "Clon superficial y no se pudo traer la historia de ${branch}; no se puede comprobar."
  [ "$(git rev-parse --is-shallow-repository)" = "false" ] ||
    err 2 "La historia de ${branch} sigue incompleta; no se puede comprobar."
fi

tip="$(git rev-parse --verify --quiet "${ref}^{commit}")" || err 2 "No existe ${ref}."
git cat-file -e "${sha}^{commit}" 2>/dev/null || err 2 "El commit ${sha} no está en la historia traída."

if [ "${tip}" = "${sha}" ]; then
  echo "OK: ${sha} es la punta de ${remote}/${branch}."
  exit 0
fi

git merge-base --is-ancestor "${sha}" "${tip}" ||
  err 1 "El commit ${sha} no está en ${branch} (punta ${tip}): no se planea ni se aplica."

changed="$(git log --format='%h %s' "${sha}..${tip}" -- "${paths[@]}")"
if [ -n "${changed}" ]; then
  {
    echo "::error::${branch} avanzó desde ${sha} (punta ${tip}) con cambios en ${paths[*]}." \
      "Esta ejecución ya no aplica: la del commit más nuevo planea y aplica desde el principio" \
      "(apply.yml se dispara con gcp-datacenter/**; si solo cambió .github/workflows/, lanzarla a" \
      "mano con workflow_dispatch). Commits posteriores que tocan esas rutas:"
    printf '%s\n' "${changed}"
  } >&2
  exit 1
fi

echo "OK: ${branch} avanzó a ${tip}, pero ningún commit posterior a ${sha} toca ${paths[*]}."
