# Pipeline de GitHub Actions

Cómo están armados los flujos de `.github/workflows/` (en la raíz del repositorio) y qué tiene
que configurar el equipo en GitHub para activarlos. Contrato: §6 (estado e identidad), §9.2 y
§9.3. Todos los flujos corren con `working-directory: gcp-datacenter`.

## 1. Los flujos

| Flujo | Disparo | Sin GCP (siempre) | Con `GCP_ENABLED = true` |
|---|---|---|---|
| `pr.yml` | Pull request | `scripts/check.sh` (fmt, validate, tflint, checkov, `terraform test`) con Terraform 1.9.8 y 1.16.5; `scripts/policy-check.sh`; `scripts/docs.sh --check` | Plan por raíz afectada (`scripts/affected-roots.sh`), Conftest sobre el plan, comentario en el PR con resumen y costo (Infracost) |
| `apply.yml` | Push a `main` con cambios en `gcp-datacenter/**`, o manual | Solo el trabajo `GCP habilitado`, que avisa que no se aplica nada | Aplica las etapas 1 → 5 en orden (abajo) |
| `drift.yml` | Diario (12:17 UTC) y manual | Nada | `plan -detailed-exitcode -lock=false` por raíz; incidencia `drift` si hay cambios |
| `terratest.yml` | Nocturno (06:41 UTC), manual y etiquetas `modules/*/v*` | `go vet ./...` y `go test -run XXX ./...` (solo compila) en `tests/`; si no hay `tests/go.mod`, avisa y termina en verde | Pruebas reales de Terratest, sin `tests/e2e` |
| `_terraform-root.yml` | Solo `workflow_call` | — | Plan, Conftest y apply de una raíz; lo llama `apply.yml` |

### 1.1 `apply.yml`

Orden de los trabajos (cada uno espera a que el anterior termine con éxito):

```
gate
org (1-org) → security (2-security) → networks-hub (3-networks)
  → dev-networks → dev-projects → dev-workloads                  entorno dev (automático)
  → qa-networks  → qa-projects  → qa-workloads                   entorno qa (tras dev)
  → prod-networks → prod-projects → prod-workloads               entorno prod (protegido)
```

Cada trabajo llama a `_terraform-root.yml`, que hace:

1. Autenticación por Workload Identity Federation con la cuenta de la etapa
   (`GCP_STAGE_SERVICE_ACCOUNTS[<etapa>]`). Los spokes usan la de `3-networks`.
2. `terraform.tfvars.example` → `terraform.tfvars`, y encima `zz-ci.auto.tfvars.json` con
   `GCP_TFVARS_JSON` (`common` + la llave de la raíz); igual que `pr.yml`.
3. `terraform init -backend-config="bucket=$GCP_STATE_BUCKET"`.
4. `terraform plan -detailed-exitcode -out=tfplan`, y `terraform show -json` del plan.
5. `conftest test plan.json --policy policies`. Una denegación detiene la raíz y todo lo que
   viene después.
6. `terraform apply tfplan` (el mismo plan revisado por Conftest), solo si hubo cambios.

Reglas:

- `0-bootstrap` no está en el pipeline: la aplica una persona administradora, una vez y a mano
  (runbook de la etapa 0). No tiene cuenta de servicio de pipeline.
- Los spokes se aplican de uno en uno porque los entornos van en serie (dev → qa → prod): GCP
  no admite dos operaciones de peering a la vez sobre la VPC hub.
- `concurrency: apply-gcp-datacenter` sin cancelación: nunca corren dos `apply` a la vez. Si
  llegan varios push mientras uno corre, GitHub deja en espera solo el más reciente y descarta
  los intermedios (el más reciente contiene sus cambios).
- Los trabajos de Terraform exigen `github.ref == refs/heads/main`: una ejecución manual desde
  otra rama no aplica nada. Esto no cierra la limitación de §4 (una rama puede cambiar el
  propio flujo).
- Cada raíz de `prod` pide su propia aprobación del entorno `prod` antes de empezar (tres en
  total). La aprobación ocurre antes del plan: lo que se revisa es el plan que `pr.yml`
  publicó en el PR.

### 1.2 `drift.yml`

Para cada raíz con `versions.tf` en `stages/` (la misma definición que
`scripts/affected-roots.sh`), salvo `0-bootstrap`: plan con `-detailed-exitcode -lock=false`.

- Código 0: nada.
- Código 2: abre una incidencia `Drift: <raíz>` con la etiqueta `drift` (la crea si no existe)
  o, si ya hay una abierta para esa raíz, reemplaza su cuerpo y agrega un comentario. El cuerpo
  lleva solo las direcciones de los recursos con cambios y la línea `Plan:`; nunca valores,
  porque las incidencias de un repositorio público son públicas.
- Código 1: el trabajo falla.

La incidencia no se cierra sola cuando el drift desaparece: se cierra a mano al resolverlo.

### 1.3 `terratest.yml`

`compile` corre siempre. `integration` corre solo con `GCP_ENABLED = true` y si existe
`tests/go.mod`; excluye los paquetes `tests/e2e` (la prueba de extremo a extremo aplica 0 → 5
y se lanza a mano). Las pruebas reciben las variables `TERRATEST_*` de §2 como variables de
entorno con el mismo nombre, y `GOOGLE_CLOUD_PROJECT = TERRATEST_PROJECT_ID`.

## 2. Variables, secretos y entornos que crea el equipo

En Settings → Secrets and variables → Actions → **Variables** (de repositorio). Ninguna es
secreta: son nombres e identificadores, no credenciales. No hay llaves de cuenta de servicio
en ningún lado.

| Variable | Contenido | Ejemplo (marcador) |
|---|---|---|
| `GCP_ENABLED` | `true` activa los trabajos que tocan GCP; cualquier otro valor o ausente los omite | `true` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Salida `workload_identity_provider` de `0-bootstrap` | `projects/<número-proyecto-semilla>/locations/global/workloadIdentityPools/<pool>/providers/<proveedor>` |
| `GCP_STAGE_SERVICE_ACCOUNTS` | Salida `stage_service_accounts` de `0-bootstrap`, en JSON | `{"1-org": "<prefix>-tf-1-org@<proyecto-semilla>.iam.gserviceaccount.com", "2-security": "…", "3-networks": "…", "4-projects": "…", "5-workloads": "…"}` |
| `GCP_STATE_BUCKET` | Salida `state_bucket` de `0-bootstrap` | `<nombre-del-bucket-de-estado>` |
| `GCP_TFVARS_JSON` | Valores de las variables por raíz, en JSON. Para cada raíz se combinan `common` y la llave de la raíz, y se sobreponen a `terraform.tfvars.example` | `{"common": {"org_id": "<org_id>", "billing_account": "<cuenta>", "state_bucket": "<bucket>"}, "stages/1-org": {"groups": {…}}, "stages/5-workloads/envs/prod": {…}}` |
| `TERRATEST_SERVICE_ACCOUNT` | Cuenta de servicio de las pruebas de integración (no es de una etapa; ver §3) | `<cuenta>@<proyecto-de-pruebas>.iam.gserviceaccount.com` |
| `TERRATEST_PROJECT_ID` | Proyecto de pruebas (cuota y llamadas que no van a un proyecto efímero) | `<proyecto-de-pruebas>` |
| `TERRATEST_BILLING_ACCOUNT` | Cuenta de facturación de los proyectos efímeros | `<XXXXXX-XXXXXX-XXXXXX>` |
| `TERRATEST_ORG_ID` | ID numérico de la organización | `<org_id>` |
| `TERRATEST_FOLDER_ID` | Carpeta donde se crean los proyectos efímeros (opcional) | `<folder_id>` |

`GCP_TFVARS_JSON` tiene que llevar todos los valores reales: lo que no traiga se toma de
`terraform.tfvars.example`, que solo tiene valores de ejemplo.

**Secretos** (Settings → Secrets and variables → Actions → Secrets):

| Secreto | Uso |
|---|---|
| `INFRACOST_API_KEY` | Opcional, solo `pr.yml`. Sin él se omite el costo |

**Entornos** (Settings → Environments). Los trabajos de `apply.yml` se ligan a ellos; GitHub
crea un entorno sin reglas la primera vez que un trabajo lo usa, pero conviene crearlos antes.

| Entorno | Lo usan | Reglas |
|---|---|---|
| `common` | `1-org`, `2-security`, `3-networks` (hub) | Ninguna obligatoria |
| `dev` | raíces de dev | Ninguna (automático) |
| `qa` | raíces de qa | Ninguna; corre solo si dev terminó con éxito |
| `prod` | raíces de prod | **Required reviewers** con dos revisores, "Prevent self-review" y "Deployment branches: `main`" |

## 3. Cómo se enciende GCP

1. Una persona administradora aplica `0-bootstrap` (runbook de la etapa 0).
2. Carga sus salidas como variables: `GCP_WORKLOAD_IDENTITY_PROVIDER`,
   `GCP_STAGE_SERVICE_ACCOUNTS`, `GCP_STATE_BUCKET`; y escribe `GCP_TFVARS_JSON`.
3. Crea los entornos y la regla de revisores de `prod` (§4).
4. Pone `GCP_ENABLED = true`. Desde ese momento:
   - `pr.yml` planea las raíces afectadas por cada PR y comenta el resultado;
   - el siguiente push a `main` (o una ejecución manual de `apply`) aplica 1 → 5;
   - `drift.yml` corre cada día.
5. Para las pruebas reales de Terratest: crear a mano la cuenta `TERRATEST_SERVICE_ACCOUNT`
   (permiso para crear proyectos en `TERRATEST_FOLDER_ID`, `billing.user` en la cuenta de
   facturación) y darle `roles/iam.workloadIdentityUser` al
   `principalSet://…/attribute.repository/<dueño>/<repositorio>` del pool de la etapa 0.
   `0-bootstrap` no crea esa cuenta. Después, las variables `TERRATEST_*`.

Para apagarlo, `GCP_ENABLED` a cualquier otro valor: los trabajos de GCP vuelven a omitirse y
los flujos terminan en verde.

## 4. Configuración manual (no vive en el repositorio)

Nada de esto se puede declarar en YAML; lo hace una persona con permisos de administración del
repositorio.

1. **Protección de la rama `main`** (Settings → Branches o Rulesets): exigir PR, dos
   aprobaciones, revisión de Code Owners (solo después de reemplazar los marcadores de
   `.github/CODEOWNERS`, que GitHub ignora mientras no sean usuarios o equipos reales), las
   comprobaciones obligatorias de `pr.yml` que no dependen de GCP (`estático (terraform
   1.9.8)`, `estático (terraform 1.16.5)`, `conftest (pruebas y planes de ejemplo)`,
   `terraform-docs al día`), y prohibir push forzado y borrado.
2. **Entorno `prod` con dos revisores** (Settings → Environments → prod → Required
   reviewers). Ojo: según la documentación de GitHub, basta con que **uno** de los revisores
   listados apruebe; la regla no cuenta aprobaciones. La aprobación de dos personas la da la
   protección de `main` (dos aprobaciones del PR); el entorno agrega una aprobación más antes
   de cada raíz de prod. **Verificar** este comportamiento en la configuración real.
3. **Plan de GitHub.** Según la documentación de GitHub (no comprobado aquí): en repositorios
   públicos, protección de rama, entornos y revisores obligatorios están en todos los planes;
   en repositorios privados, la protección de rama exige GitHub Pro, Team o Enterprise, y los
   revisores obligatorios de un entorno, GitHub Enterprise. **Hay que verificarlo** con el plan
   del equipo antes de contar con estos controles (pendiente 12 del primer apply). Sin
   revisores obligatorios, `prod` se aplicaría sin aprobación.

## 5. Limitación conocida: WIF filtra solo por repositorio

Documentada en el README de `stages/0-bootstrap`. El proveedor de WIF acepta cualquier token
con `assertion.repository == <repositorio>`, y cada cuenta de etapa da
`roles/iam.workloadIdentityUser` al `principalSet` del repositorio completo. Por eso
**cualquier rama o flujo del repositorio** (incluido un PR desde una rama del mismo
repositorio) puede tomar la identidad de las cuentas de etapa, que pueden aplicar cambios. La
condición `github.ref == refs/heads/main` de `apply.yml` y la protección del entorno `prod` no
lo impiden: una rama puede traer su propio flujo modificado.

Mitigación prevista (no construida): restringir las cuentas que aplican a `main` o al entorno
`prod` con `attribute.ref` o `attribute.environment` en el `principalSet`, y separar cuentas de
solo lectura para los `plan` de los PR. Mientras tanto, limitar quién tiene permiso de
escritura en el repositorio.
