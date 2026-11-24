# ADR 0007: CI/CD con GitHub Actions

## Estado

Aceptado, 2026-11-20. Enmendado el 2026-11-21: WIF por ID numérico del repositorio y del dueño
(ADR [0023](0023-endurecimiento-de-la-identidad-del-pipeline.md)); plan, aprobación y apply
separados, con `common` protegido (ADR [0025](0025-plan-aprobacion-y-apply-separados.md)).
Enmendado el 2026-11-24: con el proyecto único ([ADR 0029](0029-un-solo-proyecto.md) §3)
`apply.yml` aplica las raíces de `1-base` a `3-workloads`; hay nueve cuentas; los `plan` usan
`tf-read`; `destroy.yml` destruye dev o qa sin borrar proyectos.

Enmendado otra vez el 2026-11-24, con los arreglos de la revisión de seguridad del código: las
cuentas que escriben solo aceptan tokens de `main`, de un flujo reutilizable del repositorio y con
su entorno de GitHub (`attribute.deploy`, ADR 0023), no de cualquier rama que declare el entorno;
`pr.yml` tiene un trabajo de Go sin GCP; dev y qa se pueden dejar fuera con `GCP_DISABLED_ENVS`;
`apply.yml` no corre por cambios solo de documentación.

Tipo: Conforme.

## Contexto

La especificación pide un pipeline que valide, planee y aplique la infraestructura con
aprobaciones, y deja la herramienta a elección del equipo. El repositorio ya vive en GitHub.
Los trabajos que tocan GCP no usan llaves JSON: con organización lo impide
`iam.disableServiceAccountKeyCreation`, y en todo caso la política de denegación del proyecto
niega a las cuentas del pipeline crear llaves (ADR 0023).

## Decisión

GitHub Actions, con cinco flujos en `.github/workflows/` (en la raíz del repositorio, con
`working-directory: gcp-datacenter`) y uno reutilizable (`_terraform-root.yml`): `pr.yml`
(revisiones estáticas con Terraform 1.9.8 sin pruebas y con 1.16.5 con `terraform test`,
`conftest verify` con las 12 reglas, autopruebas de los scripts, `terraform-docs` y
`go (vet y pruebas sin GCP)` de Terratest; plan, Conftest sobre el plan e Infracost solo con
`GCP_ENABLED = true`; el trabajo `plan-gate` resume el resultado),
`apply.yml` (`1-base`, hub, spoke y cargas de dev, qa y prod al hacer merge a `main`, salvo
cuando el cambio solo toca `gcp-datacenter/docs/**` o archivos `.md`; por cada raíz un trabajo
`plan` sin entorno con `tf-read` y un trabajo `apply` en el entorno de GitHub de la raíz, que
vuelve a planear y solo aplica si la huella del plan coincide con la revisada, ADR 0025; `common`
y `prod` con revisores, dev automático seguido de la prueba de humo `dev-smoke`, qa tras ella;
la variable de repositorio `GCP_DISABLED_ENVS` deja fuera a dev o qa, nunca a prod),
`destroy.yml` (manual, solo dev o qa: cargas y, con `incluir_red`, el spoke, más la búsqueda de
huérfanos), `drift.yml` (diario, `plan -detailed-exitcode -lock=false` con `tf-read` sobre las
raíces encendidas, más el trabajo de recursos no administrados con Cloud Asset Inventory) y
`terratest.yml`. La autenticación es Workload Identity Federation: `0-bootstrap` crea un pool y
un proveedor OIDC de GitHub con `attribute_condition` sobre `assertion.repository_id` y
`assertion.repository_owner_id` (IDs numéricos, ADR 0023). Las cuentas que escriben (ADR 0017)
aceptan `roles/iam.workloadIdentityUser` solo del `principalSet` `attribute.deploy/<entorno>` de
su raíz (`common` para `tf-base` y `tf-net`, `<env>` para las de entorno). `attribute.deploy` vale
el entorno de GitHub solo en un trabajo de `refs/heads/main` cuyo `job_workflow_ref` es un flujo
de `.github/workflows/` del repositorio; si no, `none`. `tf-read` se toma con el `principalSet`
`attribute.repository_id/<id>`. `CODEOWNERS`
asigna revisión por etapa a los equipos de red, seguridad y plataforma; `.github/`,
`stages/0-bootstrap/`, `scripts/`, `.checkov.yaml`, `.tflint.hcl` y `tests/e2e/` son solo de
seguridad.

## Alternativas consideradas

- **Cloud Build con disparadores de GitHub.** Rechazada: agrega una conexión de repositorio y
  otro sistema de permisos, y el equipo ya opera en GitHub.
- **Terraform Cloud o HCP Terraform.** Rechazada: el estado saldría del bucket con CMEK
  (ADR 0008) y añade un proveedor externo que la especificación no menciona.
- **GitLab CI u otro sistema.** Sin ventaja; el repositorio no está ahí.

## Consecuencias

- Positivas: sin llaves de larga duración; cada raíz se autentica con su propia cuenta, solo
  desde el repositorio declarado, solo desde `main` y solo en su entorno de GitHub. Mientras
  `GCP_ENABLED` no sea `true`, los trabajos de GCP se omiten y el resto del pipeline demuestra
  las políticas sin GCP (§9.1).
- Negativas: quien puede integrar a `main` o lanzar un flujo de `main` obtiene, por el
  pipeline, las cuentas que escriben; la regla "Deployment branches: main" y los revisores de
  los entornos de GitHub quedan como segunda barrera. `tf-read` lo obtiene cualquier trabajo del
  repositorio. Son riesgos residuales del ADR 0023, descritos en
  [`docs/pipeline.md`](../pipeline.md) §4 y §5. El valor real de `job_workflow_ref` y el mapeo
  en trabajos sin entorno son `VERIFICAR-EN-APPLY` (puntos 123 y 124).
- La protección de rama no bloquea nada por sí sola: hay que configurarla a mano con
  `plan-gate` y las demás comprobaciones como obligatorias ([`docs/pipeline.md`](../pipeline.md)
  §4), y tanto ella como los revisores obligatorios de entornos dependen del plan de GitHub en
  repositorios privados.
- `CODEOWNERS` usa marcadores hasta que el equipo defina los usuarios (§2 del contrato).
- Primer apply: protección de rama, comprobaciones obligatorias y revisores de `common` y
  `prod` según el plan de GitHub (punto 12 de
  [`docs/pendientes-apply.md`](../pendientes-apply.md)), estabilidad de la huella del plan
  (punto 48), recursos no administrados (punto 49), cuenta de auditoría y prueba de humo
  (punto 50), primera corrida de `pr.yml` (punto 51), `!cancelled()` con entornos apagados y
  filtro de rutas de `apply.yml` (puntos 143 y 144) y tiempo del despliegue completo frente al
  objetivo de 90 minutos (punto 10).
