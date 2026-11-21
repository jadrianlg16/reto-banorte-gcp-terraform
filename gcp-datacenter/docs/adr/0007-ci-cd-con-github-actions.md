# ADR 0007: CI/CD con GitHub Actions

## Estado

Aceptado, 2026-11-20.

Tipo: Conforme.

## Contexto

La especificación pide un pipeline que valide, planee y aplique la infraestructura con
aprobaciones, y deja la herramienta a elección del equipo. El repositorio ya vive en GitHub.
Los trabajos que tocan GCP no pueden usar llaves JSON: `iam.disableServiceAccountKeyCreation`
lo impide (§7.1).

## Decisión

GitHub Actions, con cuatro flujos en `.github/workflows/` (en la raíz del repositorio, con
`working-directory: gcp-datacenter`): `pr.yml` (revisiones estáticas, `terraform test`,
`conftest verify`; plan, Conftest sobre el plan e Infracost solo con `GCP_ENABLED = true`),
`apply.yml` (etapas 1 a 5 al hacer merge a `main`; dev automático, qa tras dev, prod en un
entorno protegido con dos revisores), `drift.yml` (diario, `plan -detailed-exitcode`) y
`terratest.yml`. La autenticación es Workload Identity Federation: la etapa 0 crea un pool y un
proveedor OIDC de GitHub con `attribute_condition` sobre `assertion.repository`, y cada cuenta
de servicio de etapa (`<prefix>-tf-<etapa>`, ADR 0017) acepta
`roles/iam.workloadIdentityUser` solo desde ese repositorio. `CODEOWNERS` asigna revisión por
etapa a los equipos de red, seguridad y plataforma.

## Alternativas consideradas

- **Cloud Build con disparadores de GitHub.** Rechazada: agrega una conexión de repositorio y
  otro sistema de permisos, y el equipo ya opera en GitHub.
- **Terraform Cloud o HCP Terraform.** Rechazada: el estado saldría del bucket con CMEK
  (ADR 0008) y añade un proveedor externo que la especificación no menciona.
- **GitLab CI u otro sistema.** Sin ventaja; el repositorio no está ahí.

## Consecuencias

- Positivas: sin llaves de larga duración; cada etapa se autentica con su propia cuenta y solo
  desde el repositorio declarado. Mientras `GCP_ENABLED` no sea `true`, los trabajos de GCP se
  omiten y el resto del pipeline demuestra las políticas sin GCP (§9.1).
- Negativas: la condición de WIF solo filtra por repositorio; cualquier rama del repositorio
  puede pedir el token. Restringir prod a `main` o al entorno protegido requiere condicionar
  también por `ref` o `environment` (los atributos ya se mapean, §6.3).
- Las reglas de protección de rama y los revisores obligatorios de entornos dependen del plan
  de GitHub en repositorios privados.
- `CODEOWNERS` usa marcadores hasta que el equipo defina los usuarios (§2 del contrato).
- Primer apply: protección de rama y revisores del entorno `prod` según el plan de GitHub
  (punto 12 de [`docs/pendientes-apply.md`](../pendientes-apply.md)) y tiempo del despliegue
  completo frente al objetivo de 90 minutos (punto 10).
