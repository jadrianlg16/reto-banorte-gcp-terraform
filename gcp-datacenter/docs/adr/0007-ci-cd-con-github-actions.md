# ADR 0007: CI/CD con GitHub Actions

## Estado

Aceptado, 2026-11-20. Enmendado el 2026-11-21: WIF por ID numérico del repositorio y del dueño
(ADR [0023](0023-endurecimiento-de-la-identidad-del-pipeline.md)); plan, aprobación y apply
separados, con `common` protegido (ADR [0025](0025-plan-aprobacion-y-apply-separados.md)).

Tipo: Conforme.

## Contexto

La especificación pide un pipeline que valide, planee y aplique la infraestructura con
aprobaciones, y deja la herramienta a elección del equipo. El repositorio ya vive en GitHub.
Los trabajos que tocan GCP no pueden usar llaves JSON: `iam.disableServiceAccountKeyCreation`
lo impide (§7.1).

## Decisión

GitHub Actions, con cuatro flujos en `.github/workflows/` (en la raíz del repositorio, con
`working-directory: gcp-datacenter`) y uno reutilizable (`_terraform-root.yml`): `pr.yml`
(revisiones estáticas con Terraform 1.9.8 sin pruebas y con 1.16.5 con `terraform test`,
`conftest verify`, autopruebas de los scripts y `terraform-docs`; plan, Conftest sobre el plan
e Infracost solo con `GCP_ENABLED = true`; el trabajo `plan-gate` resume el resultado),
`apply.yml` (etapas 1 a 5 al hacer merge a `main`; por cada raíz un trabajo `plan` sin entorno
y un trabajo `apply` en el entorno de GitHub de la raíz, que vuelve a planear y solo aplica si
la huella del plan coincide con la revisada, ADR 0025; `common` y `prod` con revisores, dev
automático seguido de la prueba de humo `dev-smoke`, qa tras ella), `drift.yml` (diario,
`plan -detailed-exitcode`, más el trabajo de recursos no administrados con Cloud Asset
Inventory) y `terratest.yml`. La autenticación es Workload Identity Federation: la etapa 0 crea
un pool y un proveedor OIDC de GitHub con `attribute_condition` sobre `assertion.repository_id`
y `assertion.repository_owner_id` (IDs numéricos, ADR 0023), y cada cuenta de servicio de etapa
(`<prefix>-tf-<etapa>`, ADR 0017) acepta `roles/iam.workloadIdentityUser` solo del
`principalSet` `attribute.repository_id/<id>`. `CODEOWNERS` asigna revisión por etapa a los
equipos de red, seguridad y plataforma; `.github/`, `stages/0-bootstrap/` y `scripts/` son solo
de seguridad.

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
  también por `ref` o `environment` (los atributos ya se mapean, §6.3); es un riesgo residual
  aceptado en el ADR 0023 y descrito en [`docs/pipeline.md`](../pipeline.md) §5.
- La protección de rama no bloquea nada por sí sola: hay que configurarla a mano con
  `plan-gate` y las demás comprobaciones como obligatorias ([`docs/pipeline.md`](../pipeline.md)
  §4), y tanto ella como los revisores obligatorios de entornos dependen del plan de GitHub en
  repositorios privados.
- `CODEOWNERS` usa marcadores hasta que el equipo defina los usuarios (§2 del contrato).
- Primer apply: protección de rama, comprobaciones obligatorias y revisores de `common` y
  `prod` según el plan de GitHub (punto 12 de
  [`docs/pendientes-apply.md`](../pendientes-apply.md)), estabilidad de la huella del plan
  (punto 48), recursos no administrados (punto 49), cuenta de auditoría y prueba de humo
  (punto 50), primera corrida de `pr.yml` (punto 51) y tiempo del despliegue completo frente al
  objetivo de 90 minutos (punto 10).
