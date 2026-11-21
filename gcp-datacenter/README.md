# gcp-datacenter

Landing zone de Google Cloud escrita en Terraform para el reto de Banorte: jerarquía de
organización, seguridad, redes hub y spoke, proyectos y cargas por entorno (`dev`, `qa`,
`prod`), con políticas de Conftest y flujos de GitHub Actions.

La fuente única de diseño es [`docs/CONTRATO.md`](docs/CONTRATO.md). Este README es un
esbozo; el paquete de trabajo 12 lo completa con requisitos previos, orden de despliegue y
comandos por etapa.

## Estructura

| Carpeta | Contenido |
|---|---|
| `modules/` | Módulos propios, uno por componente (CONTRATO §8) |
| `stages/` | Raíces de despliegue `0-bootstrap` … `5-workloads` (CONTRATO §7) |
| `policies/` | Políticas de Conftest (Rego) con sus pruebas y planes de ejemplo |
| `tests/` | Terratest y prueba de extremo a extremo |
| `scripts/` | `check.sh`, `docs.sh` y utilidades del pipeline |
| `docs/` | Contrato, ADR, runbooks, diagramas y pendientes del primer apply |

## Revisiones locales (sin GCP)

Herramientas: Terraform >= 1.9, TFLint, checkov, terraform-docs y Conftest.

```bash
cd gcp-datacenter

# Todo: fmt, validate, tflint, checkov y terraform test sobre módulos, ejemplos y raíces.
bash scripts/check.sh

# Solo algunos objetivos, u omitiendo pasos.
bash scripts/check.sh modules/kms modules/kms/examples/basic
bash scripts/check.sh --skip checkov
bash scripts/check.sh --list      # qué objetivos encontraría
bash scripts/check.sh --help

# READMEs de terraform-docs: regenerar, o comprobar que están al día.
bash scripts/docs.sh
bash scripts/docs.sh --check

# Pruebas de las políticas.
conftest verify --policy policies
```

`check.sh` lee el comando de checkov de la variable `CHECKOV_CMD` (por defecto `checkov`).
En Windows, donde el lanzador `checkov.cmd` falla, con uv:

```bash
export CHECKOV_CMD="uvx --from checkov python -m checkov.main"
```

Los proveedores se descargan una sola vez a la caché `TF_PLUGIN_CACHE_DIR` (por defecto
`$HOME/.terraform.d/plugin-cache`). No corras dos `check.sh` a la vez con la misma caché.

Cada ejemplo (`modules/<modulo>/examples/basic/`) se revisa como raíz independiente, así que
declara su propio bloque `terraform` con `required_version` y `required_providers`.

## Integración continua

`.github/workflows/pr.yml` (en la raíz del repositorio) corre en cada pull request las mismas
revisiones, `conftest verify` y la comprobación de terraform-docs. El plan por raíz contra
GCP, Conftest sobre el plan y el costo con Infracost solo corren cuando la variable de
repositorio `GCP_ENABLED` vale `true`; las variables que necesita están descritas al inicio
del flujo.
