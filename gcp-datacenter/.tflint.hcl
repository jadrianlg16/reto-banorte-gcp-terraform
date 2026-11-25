# Configuración de TFLint para módulos, ejemplos y raíces de etapas.
# scripts/check.sh la pasa con --config; las versiones de los plugins están fijas a
# versiones publicadas (comprobadas en GitHub el 20 nov 2026). Se actualizan por PR.

config {
  # Revisa también los módulos locales que llama cada raíz o ejemplo.
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
  version = "0.17.0"
  source  = "github.com/terraform-linters/tflint-ruleset-terraform"
}

plugin "google" {
  enabled = true
  version = "0.41.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
  # Sin deep_check: exigiría credenciales de GCP y el repositorio se prueba sin GCP.
}

# Reglas adicionales al preset "recommended" (algunas ya vienen en él; se declaran
# explícitamente para que no dependan de cambios del preset).

rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}
