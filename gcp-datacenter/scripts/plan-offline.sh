#!/usr/bin/env bash
# Plan real del proveedor sin GCP, para sacar planes de ejemplo de policies/fixtures.
#
# Uso: scripts/plan-offline.sh <directorio> <salida.json>
#   <directorio>  raíz de Terraform, relativa a gcp-datacenter/ (por ejemplo
#                 modules/compute-mig/examples/basic o stages/0-bootstrap) o ruta absoluta
#                 a una configuración propia (una sonda con recursos sueltos).
#   <salida.json> archivo donde queda `terraform show -json` del plan.
#
# Cómo funciona:
#   - Copia gcp-datacenter/ (sin .terraform, estados ni planes) a un directorio temporal: las
#     rutas relativas de los módulos siguen valiendo y el árbol de trabajo no se toca.
#   - Si la raíz declara un backend, agrega en la copia un *_override.tf con backend "local".
#   - Si hay terraform.tfvars.example, lo copia como terraform.tfvars.
#   - GOOGLE_OAUTH_ACCESS_TOKEN=dummy, `plan -refresh=false -lock=false`: el proveedor
#     calcula el plan sin llamar a las API. Lo que necesita una llamada (fuentes de datos,
#     terraform_remote_state de otra etapa) falla: solo sirven los ejemplos de módulo,
#     0-bootstrap y sondas que no lean nada.
#
# Después, recortar con scripts/cut-plan.py (ver policies/README.md, "Planes de ejemplo").
#
# Variables opcionales: TERRAFORM_CMD (por defecto `terraform`), TF_PLUGIN_CACHE_DIR,
# GOOGLE_PROJECT y GOOGLE_REGION (por defecto example-project y us-central1).
# Compatible con bash 3.2 (macOS), Git Bash (Windows) y Linux.

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Uso: scripts/plan-offline.sh <directorio> <salida.json>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TF="${TERRAFORM_CMD:-terraform}"

target="$1"
out="$2"
case "$out" in
  /*) ;;
  *) out="$(pwd)/$out" ;;
esac

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

case "$target" in
  /*)
    # Configuración externa: se copia sola.
    mkdir -p "$work/probe"
    (cd "$target" && tar --exclude=.terraform --exclude='*.tfstate*' --exclude=tfplan -cf - .) |
      (cd "$work/probe" && tar -xf -)
    dir="$work/probe"
    ;;
  *)
    if [ ! -d "$PROJECT_DIR/$target" ]; then
      echo "ERROR: no existe $PROJECT_DIR/$target" >&2
      exit 2
    fi
    (cd "$PROJECT_DIR" && tar --exclude=.terraform --exclude='*.tfstate*' --exclude=tfplan \
      --exclude=.git -cf - modules stages "$target") | (cd "$work" && tar -xf -)
    dir="$work/$target"
    ;;
esac

if grep -q -E '^[[:space:]]*backend[[:space:]]+"' "$dir"/*.tf 2>/dev/null; then
  printf 'terraform {\n  backend "local" {}\n}\n' > "$dir/zz_offline_backend_override.tf"
fi
if [ -f "$dir/terraform.tfvars.example" ] && [ ! -f "$dir/terraform.tfvars" ]; then
  cp "$dir/terraform.tfvars.example" "$dir/terraform.tfvars"
fi

export GOOGLE_OAUTH_ACCESS_TOKEN=dummy
export GOOGLE_PROJECT="${GOOGLE_PROJECT:-example-project}"
export GOOGLE_REGION="${GOOGLE_REGION:-us-central1}"
export TF_IN_AUTOMATION=1
export CHECKPOINT_DISABLE=1

cd "$dir"
"$TF" init -input=false -no-color >"$work/init.log" 2>&1 || {
  cat "$work/init.log" >&2
  exit 1
}
"$TF" plan -input=false -no-color -refresh=false -lock=false -out=tfplan >"$work/plan.log" 2>&1 || {
  cat "$work/plan.log" >&2
  exit 1
}
grep -E '^(Plan:|No changes\.)' "$work/plan.log" || true
"$TF" show -json tfplan >"$out"
echo "Plan en JSON: $out"
