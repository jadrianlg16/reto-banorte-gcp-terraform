#!/usr/bin/env bash
# ¿Sigue vigente el commit de esta ejecución para desplegar? Lo usa _terraform-root.yml antes de
# planear y otra vez justo antes del apply.
#
# Regla: <sha> está en la rama (por defecto main de origin) y ningún commit posterior de la rama
# cambia las rutas que afectan un despliegue (por defecto gcp-datacenter/ y .github/workflows/,
# desde la raíz del repositorio, sin gcp-datacenter/docs/ ni los .md de gcp-datacenter/). Así:
# - una ejecución vieja que se vuelve a correr ("Re-run jobs"), o una aprobación que llega
#   después de otro merge que sí cambia Terraform o los flujos, falla sin planear ni aplicar
#   código viejo encima de lo que ya aplicó una ejecución más nueva;
# - un merge que no toca esas rutas (README de la raíz, labs/, la configuración de Dependabot,
#   documentación de gcp-datacenter/) no detiene la cadena en curso. apply.yml solo se dispara
#   con cambios en esas mismas rutas (paths del push: gcp-datacenter/** y .github/workflows/**
#   menos !gcp-datacenter/docs/** y !gcp-datacenter/**.md; selftest.sh comprueba que eligen los
#   mismos archivos), así que ese merge no traería otra ejecución que la retome.
#
# Dos comprobaciones, las dos obligatorias: `git log` de las rutas (lista los commits que las
# tocan) y `git diff` entre el árbol de <sha> y el de la punta. La segunda cubre lo que la
# primera no ve: `git log -- <rutas>` simplifica la historia y, en un merge cuyo resultado en
# esas rutas es igual al de uno de sus padres, sigue solo a ese padre; un merge que descarta un
# cambio de <sha> (resuelto a favor de la otra rama) no aparece en el log aunque el contenido
# de las rutas ya sea otro.
#
# Uso: scripts/check-main-tip.sh <sha> [remoto] [rama]
# Variables: DEPLOY_PATHS (pathspecs de git separados por espacio, desde la raíz del
# repositorio; admite exclusiones como :(exclude)<ruta>).
# Sale con 0 si está vigente, 1 si no, 2 si no se puede decidir (falla cerrado): sin sha, remoto
# ilegible, historia superficial que no se puede completar o <sha> desconocido.
#
# Necesita la historia de la rama: con un clon superficial (actions/checkout con fetch-depth 1)
# intenta completarla con `git fetch --unshallow`; si sigue superficial, sale con 2.

set -uo pipefail

sha="${1:-}"
remote="${2:-origin}"
branch="${3:-main}"
read -r -a paths <<<"${DEPLOY_PATHS:-gcp-datacenter .github/workflows :(exclude)gcp-datacenter/docs :(exclude,glob)gcp-datacenter/**/*.md}"

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

stale() { # stale <detalle>: la ejecución ya no aplica
  {
    echo "::error::${branch} avanzó desde ${sha} (punta ${tip}) con cambios en ${paths[*]}." \
      "Esta ejecución ya no aplica: la del commit más nuevo planea y aplica desde el principio" \
      "(apply.yml se dispara con cambios en esas rutas; si esa ejecución no aparece, lanzarla a" \
      "mano con workflow_dispatch sobre ${branch}). $1"
  } >&2
  exit 1
}

changed="$(git log --format='%h %s' "${sha}..${tip}" -- "${paths[@]}")" ||
  err 2 "No se pudo leer la historia entre ${sha} y ${tip}; no se puede comprobar."
if [ -n "${changed}" ]; then
  stale "Commits posteriores que tocan esas rutas:
${changed}"
fi

# El log simplifica los merges (ver el encabezado): se compara además el contenido.
git diff --quiet "${sha}" "${tip}" -- "${paths[@]}"
case $? in
  0) ;;
  1) stale "Ningún commit posterior las toca por sí solo, pero su contenido en la punta es otro (un merge descartó o cambió algo). Archivos:
$(git diff --name-only "${sha}" "${tip}" -- "${paths[@]}")" ;;
  *) err 2 "No se pudo comparar ${sha} con ${tip}; no se puede comprobar." ;;
esac

echo "OK: ${branch} avanzó a ${tip}, pero ningún commit posterior a ${sha} toca ${paths[*]}."
