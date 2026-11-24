#!/usr/bin/env bash
# ¿Se puede destruir esto? Lo usan destroy.yml (pedido) y _terraform-root.yml en modo destroy
# (raíz), antes de autenticarse en GCP. Ver docs/pipeline.md §1.5.
#
# Uso:
#   scripts/destroy-guard.sh pedido <entorno> <confirmación> <ref>
#       El pedido manual de destroy.yml: <entorno> es dev o qa (prod nunca), <confirmación> es
#       exactamente el nombre del entorno y <ref> es refs/heads/main.
#   scripts/destroy-guard.sh raiz <entorno> <raíz>
#       Una raíz que _terraform-root.yml va a destruir: <entorno> es dev o qa y <raíz> es
#       stages/3-workloads/envs/<entorno> o stages/2-networks/envs/<entorno>, exactamente
#       (ADR 0029 §8). 0-bootstrap, 1-base y el hub no tienen destroy: guardan el estado, las
#       llaves, los repositorios y lo único del proyecto.
#
# Sale con 0 si se admite, 1 si se rechaza (con el motivo en ::error::) y 2 si el uso es
# incorrecto. Sin espacios ni mayúsculas tolerados: lo que no coincide exactamente se rechaza.
# Compatible con bash 3.2.

set -uo pipefail

reject() { # reject <mensaje>
  echo "::error::$1" >&2
  exit 1
}

usage() {
  echo "Uso: $0 pedido <entorno> <confirmación> <ref> | $0 raiz <entorno> <raíz>" >&2
  exit 2
}

# Entornos que se pueden destruir. prod no está y no se agrega: tiene protección contra borrado
# obligatoria y su desmontaje no es un destroy.
check_environment() { # check_environment <entorno>
  case "$1" in
    dev | qa) ;;
    prod) reject "prod no se destruye con este flujo (solo dev o qa). No se destruye nada." ;;
    *)
      case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" in
        prod) reject "'$1' es prod: prod no se destruye con este flujo (solo dev o qa). No se destruye nada." ;;
      esac
      reject "Entorno '$1' no admitido: solo dev o qa (en minúsculas, sin espacios). No se destruye nada."
      ;;
  esac
}

[ $# -ge 1 ] || usage
mode="$1"
shift

case "${mode}" in
  pedido)
    [ $# -eq 3 ] || usage
    env_name="$1" confirmation="$2" ref="$3"
    check_environment "${env_name}"
    [ "${confirmation}" = "${env_name}" ] ||
      reject "Confirmación incorrecta: hay que escribir exactamente '${env_name}' (se recibió '${confirmation}'). No se destruye nada."
    [ "${ref}" = "refs/heads/main" ] ||
      reject "destroy solo corre desde main (ref actual: ${ref}). No se destruye nada."
    echo "OK: destruir ${env_name} (confirmado) desde ${ref}."
    ;;
  raiz)
    [ $# -eq 2 ] || usage
    env_name="$1" root="$2"
    check_environment "${env_name}"
    case "${root}" in
      "stages/3-workloads/envs/${env_name}" | "stages/2-networks/envs/${env_name}") ;;
      *) reject "La raíz '${root}' no se destruye en el entorno ${env_name}: solo stages/3-workloads/envs/${env_name} y stages/2-networks/envs/${env_name}. No se destruye nada." ;;
    esac
    echo "OK: ${root} en el entorno ${env_name}."
    ;;
  *) usage ;;
esac
