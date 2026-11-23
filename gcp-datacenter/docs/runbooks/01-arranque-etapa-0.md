# Runbook 01: arranque de la etapa 0

## Objetivo

Crear, una sola vez, la base que necesita el pipeline: carpeta `bootstrap`, proyecto semilla,
llave KMS y bucket del estado, cuentas de servicio de las etapas 1 a 5, Workload Identity
Federation para GitHub, los dos roles personalizados (etapas 2 y 4) y la política de denegación
de la carpeta `bootstrap`; migrar el estado local de la etapa al bucket; activar Security
Command Center y dejar GitHub listo para aplicar las etapas 1 a 5.

Nada de esto se ha ejecutado todavía: los pasos son el procedimiento diseñado, pendiente de
verificar en el primer apply ([pendientes](../pendientes-apply.md), puntos 1, 2, 13, 22, 23,
27, 31, 32, 33, 50 y 55).

## Cuándo usarlo

- Al conectar la organización de GCP por primera vez.
- Para volver a aplicar la etapa 0 después (por ejemplo, si cambia el repositorio y con él
  `github_repository_id`): en ese caso solo aplican los pasos 3 y 9 con el backend ya en el
  bucket (ver "Cambios posteriores").

## Prerrequisitos

- Herramientas del [README](../../README.md#herramientas): Terraform, `gcloud`, `gh`
  (GitHub CLI) con sesión en el repositorio. Terraform: la versión del pipeline (1.16.5) o, como
  mínimo, 1.11. El código declara `>= 1.9`, pero con una versión anterior a 1.11 `terraform
  init` falla en esta raíz al leer `tests/0-bootstrap.tftest.hcl` (`Unsupported argument …
  override_during`; comprobado con 1.9.8, ADR 0021); en ese caso, agregar
  `-test-directory=.sin-pruebas` (un directorio que no existe) a **cada** `terraform init` de
  este runbook. Usar siempre la misma versión para la etapa 0: Terraform no abre un estado
  escrito por una versión más nueva.
- Organización, cuenta de facturación y los siete grupos de Cloud Identity
  ([README](../../README.md#google-cloud)).
- Persona administradora con, en la organización, `roles/resourcemanager.organizationAdmin`,
  `roles/resourcemanager.folderCreator`, `roles/resourcemanager.projectCreator`,
  `roles/iam.organizationRoleAdmin` (roles personalizados) y `roles/iam.denyAdmin` (política de
  denegación de la carpeta `bootstrap`, ADR 0023), y en la cuenta de facturación
  `roles/billing.admin`. Para activar SCC además hace falta `roles/securitycenter.admin` en la
  organización (pendiente de verificar el rol exacto que pide la consola).
- Valores: `<org_id>`, `<billing_account>` (`XXXXXX-XXXXXX-XXXXXX`), `<prefix>` (2 a 6
  minúsculas o dígitos, empieza con letra; ejemplo `bnt`), `<project_suffix>` (opcional, para
  que el ID del proyecto semilla y el nombre del bucket sean únicos), `<dueño>/<repositorio>` y
  los IDs numéricos del repositorio y de su dueño (paso 2).
- Decidir **antes del primer apply** la ubicación del estado: `state_bucket_location` (`US` por
  defecto, multirregión; `EU` o `ASIA`) y, si se quiere una doble región,
  `state_bucket_dual_regions` (debe incluir `primary_region`). La ubicación de un bucket y de un
  llavero no se cambia después (ADR 0022).

## Pasos

Todas las rutas son relativas a `gcp-datacenter/`.

1. Iniciar sesión y confirmar la organización y la facturación.

   ```bash
   gcloud auth login
   gcloud auth application-default login
   gcloud organizations list
   gcloud billing accounts list
   gcloud organizations get-iam-policy <org_id> \
     --flatten="bindings[].members" --filter="bindings.members:user:<correo-admin>" \
     --format="value(bindings.role)"
   ```

   La última orden debe listar los cinco roles de organización de los prerrequisitos (los
   roles que la persona recibe por un grupo no aparecen con este filtro: revisar también los
   grupos).

2. Preparar variables y el backend local temporal.

   ```bash
   gh api repos/<dueño>/<repositorio> --jq '.id, .owner.id'   # IDs numéricos para WIF
   cd stages/0-bootstrap
   cp terraform.tfvars.example terraform.tfvars
   # editar: org_id, billing_account, prefix, project_suffix, primary_region,
   #         github_repository (solo informativo), github_repository_id y
   #         github_repository_owner_id (los dos números de arriba, entre comillas),
   #         state_bucket_location y, si aplica, state_bucket_dual_regions,
   #         labels (app, owner, cost_center en minúsculas)
   cp backend_override.tf.example backend_override.tf
   ```

   WIF confía en esos dos IDs, no en el nombre (ADR 0023): un error en ellos no se nota en el
   plan, solo cuando el primer flujo de GitHub no consigue token.

   `backend_override.tf`, `terraform.tfvars` y `terraform.tfstate*` no se versionan
   (`.gitignore` de la raíz y de la etapa). Verificar antes de seguir:
   `git status --short` no debe mostrarlos.

3. Planear y aplicar con estado local.

   ```bash
   terraform init
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

   Revisar en el plan: carpeta `bootstrap`, proyecto `<prefix>-bootstrap-seed[-<sufijo>]`,
   llavero `<prefix>-bootstrap-sec-keyring-us` (o el código de `state_bucket_location`) con la
   llave `<prefix>-bootstrap-sec-state`, bucket `<prefix>-bootstrap-ops-tfstate[-<sufijo>]` en
   `US` (o la ubicación elegida), cinco cuentas `<prefix>-tf-<etapa>`, los roles personalizados
   `<prefix>TfKmsSecretIamGranter` y `<prefix>TfSecretContainerAdmin`, la política de denegación
   `google_iam_deny_policy.bootstrap_folder`, pool `<prefix>-bootstrap-sec-wif-pool` y proveedor
   `<prefix>-bootstrap-sec-github` con `attribute_condition` sobre `assertion.repository_id` y
   `assertion.repository_owner_id`, y ningún rol `roles/owner`, `roles/editor` ni
   `roles/resourcemanager.organizationAdmin`.

   Si la creación del bucket falla por permisos sobre la llave, repetir `terraform plan` y
   `terraform apply`: el permiso del agente de Cloud Storage puede tardar en propagarse
   (`main.tf:194`). El agente se consulta con el número del proyecto semilla para que la
   lectura ocurra en el apply y no en el plan, cuando el proyecto aún no existe; que la API lo
   acepte está por verificar (`main.tf:116`, pendiente 27). Si una API rechaza la llamada por
   falta de proyecto de cuota (HYPOTHESIS, pendiente 22; la API de políticas de denegación es
   el punto 32): `gcloud auth application-default set-quota-project <proyecto-existente>`. En
   una organización nueva puede no haber ningún proyecto: si el apply ya creó el proyecto
   semilla y habilitó sus APIs, sirve ese (`<prefix>-bootstrap-seed[-<sufijo>]`); después,
   repetir `terraform plan` y `terraform apply` (el apply continúa con lo que falta).

4. Migrar el estado al bucket. El nombre del bucket se toma **antes** de borrar el override:
   después, `terraform output` falla con `Backend initialization required` (comprobado sin GCP,
   pendiente 21). El README de `stages/0-bootstrap` sigue el mismo orden.

   ```bash
   STATE_BUCKET="$(terraform output -raw state_bucket)"
   echo "${STATE_BUCKET}"
   rm backend_override.tf
   terraform init -migrate-state -backend-config="bucket=${STATE_BUCKET}"
   # Terraform pregunta si copia el estado existente al backend nuevo: responder "yes".
   ```

5. Comprobar la migración y borrar el estado local.

   ```bash
   terraform state list | head
   gcloud storage ls "gs://${STATE_BUCKET}/0-bootstrap/"
   terraform plan -detailed-exitcode     # 0: sin cambios
   rm terraform.tfstate terraform.tfstate.backup tfplan
   ```

   El estado local no tiene secretos, pero describe toda la etapa: no se copia a otro lado.

6. Guardar las salidas que usan las demás etapas.

   ```bash
   terraform output -raw seed_project_id
   terraform output -raw workload_identity_provider
   terraform output -json stage_service_accounts
   terraform output -raw kms_secret_iam_role_id
   terraform output -raw secret_container_admin_role_id
   ```

   La etapa 1 lee los dos roles personalizados del estado de la etapa 0 y los asigna en el
   proyecto `security` (a `4-projects` y a `2-security`).

7. Activar Security Command Center (paso manual permitido; pendiente 2). En la consola de
   Google Cloud, con la organización seleccionada: Security → Security Command Center →
   activar en el nivel de la organización (Standard o Premium, según lo que decida el equipo).
   Hacerlo antes de la etapa 1: la notificación de hallazgos que crea la etapa 1 probablemente
   falla sin SCC activo (HYPOTHESIS, pendiente 23).

8. Revisar si la organización ya tiene política de Access Context Manager.

   ```bash
   gcloud access-context-manager policies list --organization=<org_id>
   ```

   Si devuelve una, su número va en `access_policy_id` de `stages/2-security` (solo puede
   haber una por organización).

9. Configurar GitHub ([`pipeline.md`](../pipeline.md) §2 a §4). Desde `stages/0-bootstrap`:

   ```bash
   gh variable set GCP_STATE_BUCKET --body "${STATE_BUCKET}"
   gh variable set GCP_WORKLOAD_IDENTITY_PROVIDER --body "$(terraform output -raw workload_identity_provider)"
   gh variable set GCP_STAGE_SERVICE_ACCOUNTS --body "$(terraform output -json stage_service_accounts)"
   gh variable set GCP_TFVARS_JSON < <ruta-a-tfvars-ci.json>
   ```

   `GCP_TFVARS_JSON` lleva `{"common": {...}, "stages/1-org": {...}, ...}` con todos los valores
   reales de cada raíz (incluido `state_bucket` en `common` y `workloads_service_account` en las
   raíces de `4-projects`). Lo que no traiga se toma de los `terraform.tfvars.example`: la tabla
   de marcadores que hay que reemplazar y los interruptores de la primera ejecución
   (`enable_cloud_run = false` y `enable_mig = false` en `5-workloads`, porque todavía no hay
   imágenes publicadas) están en `pipeline.md` §2. Crear los entornos `common`, `dev`, `qa` y
   `prod` (`common` y `prod` con revisores obligatorios), la protección de `main` con las
   comprobaciones obligatorias (incluida `plan-gate`) de `pipeline.md` §4, y la cuenta de
   auditoría `GCP_AUDIT_SERVICE_ACCOUNT` con su `principalSet` por `attribute.repository_id`
   (`pipeline.md` §3, paso 4; la etapa 0 no la crea):

   ```bash
   gh variable set GCP_AUDIT_SERVICE_ACCOUNT --body "<cuenta>@<proyecto>.iam.gserviceaccount.com"
   ```

   De sus roles de solo lectura, en este momento solo se puede asignar el del bucket de estado:
   las carpetas, el hub, el host de dev y los proyectos de servicio de dev todavía no existen
   (los crean las etapas 1, 3 y 4). El resto se asigna durante la primera ejecución (abajo).
   Sin esos roles, la prueba de humo de dev falla y qa y prod no se aplican.

10. Encender el pipeline, al final y solo con lo anterior listo.

    ```bash
    gh variable set GCP_ENABLED --body "true"
    gh workflow run apply.yml --ref main
    ```

### Primera ejecución de `apply.yml`

Lo que la primera ejecución tiene de distinto (nada de esto se ha ejecutado; pendientes 50 y 55):

- **Aprobaciones.** `1-org`, `2-security` y `3-networks` (hub) piden una aprobación cada una en
  el entorno `common`, con el resumen del plan a la vista. Si el plan de GitHub del repositorio
  no admite revisores obligatorios en entornos (repositorio privado, `pipeline.md` §4, punto 3),
  **no hay pausa**: la ejecución aplica de `1-org` a prod sin detenerse. Decidirlo antes del
  paso 10 (pendiente 12).
- **Roles de la cuenta de auditoría.** Asignarlos a medida que existan los recursos
  (`pipeline.md` §3, "Orden"): `roles/cloudasset.viewer` en las carpetas y
  `roles/compute.networkViewer` en el hub después de `1-org`; los roles sobre el host de dev
  después de `dev / 3-networks`; `roles/cloudsql.viewer` en los proyectos de servicio de dev
  después de `dev / 4-projects`. Si `dev / prueba de humo` falla por permisos, asignar lo que
  falte y usar "Re-run failed jobs".
- **Sin imágenes.** `5-workloads` corre con `enable_cloud_run = false` y `enable_mig = false`
  hasta publicar las imágenes en los repositorios que crea la etapa 4 (runbook
  [02](02-alta-proyecto-aplicacion.md), pasos 3 y 4). Sin cómputo no hay balanceador externo y
  la prueba de humo omite esa comprobación; las de Cloud SQL y on-premises simulado sí corren.
- **Prueba de humo hacia on-premises simulado.** Exige que cada traza pase por un túnel VPN y,
  después de él, no admite otro descarte que `FIREWALL_RULE`. En `onprem-sim` no hay ninguna VM
  en `192.168.0.10`: si Connectivity Tests termina la traza con otra causa (HIPÓTESIS, pendiente
  50), la prueba falla aunque la ruta exista. Revisar la traza en el registro del trabajo y, si
  la ruta por la VPN está, seguir con una ejecución manual con `omitir_prueba_de_humo = true`
  y abrir un PR que ajuste `routedThroughVPN` (`tests/e2e/connectivity_test.go`).
- **Otros flujos.** Con `GCP_ENABLED = true`, `drift.yml` (diario) y los `plan` de `pr.yml`
  fallan en las raíces que leen el estado de una etapa que todavía no se aplicó
  (`terraform_remote_state` sin estado). Es esperado hasta que la primera ejecución termine en
  prod.
- **Si un trabajo falla.** Depende de cuál (leído de `_terraform-root.yml`, sin ejecutar):
  - `plan <raíz>` o `dev / prueba de humo`: no cambiaron nada. Corregir la causa (un permiso,
    por ejemplo) y usar "Re-run failed jobs".
  - `apply <raíz>` a medias: lo que sí se creó queda en el estado. "Re-run failed jobs" no
    sirve: vuelve a correr solo el `apply`, que compara su plan nuevo (ya sin lo creado) y las
    variables con las huellas que guardó el `plan` de la ejecución original, y falla sin
    aplicar. Corregir la causa y lanzar `apply.yml` de nuevo (`gh workflow run apply.yml --ref
    main`): planea todo otra vez, las raíces al día dan "sin cambios" y la que quedó a medias
    muestra solo lo que falta. Lo mismo si la corrección es un cambio de `GCP_TFVARS_JSON`.
  - Si la corrección es un cambio de código, el merge trae su propia ejecución desde `1-org`.

## Verificación

- `terraform plan -detailed-exitcode` en `stages/0-bootstrap` sale con 0 desde el bucket.
- El bucket tiene CMEK, versionado, acceso uniforme y prevención de acceso público:

  ```bash
  gcloud storage buckets describe "gs://${STATE_BUCKET}" \
    --format="yaml(default_kms_key,versioning_enabled,uniform_bucket_level_access,public_access_prevention)"
  ```

- La llave rota cada 90 días:

  ```bash
  gcloud kms keys describe <prefix>-bootstrap-sec-state --keyring=<prefix>-bootstrap-sec-keyring-us \
    --location=us --project=<seed_project_id> --format="value(rotationPeriod,nextRotationTime)"
  ```

  (`us` es la ubicación por defecto; con otro `state_bucket_location`, su código en minúsculas.)

- La política de denegación está en la carpeta `bootstrap`:

  ```bash
  gcloud iam policies list \
    --attachment-point="cloudresourcemanager.googleapis.com/folders/<id-carpeta-bootstrap>" \
    --kind=denypolicies
  ```

  Debe listar `<prefix>-bootstrap-sec-deny-1-org` (sintaxis de `gcloud` por verificar en el
  primer uso, punto 32).

- El primer trabajo `1-org` de `apply.yml` autentica por WIF e inicializa el backend: es la
  primera prueba real del punto 1 de los pendientes (IAM condicionado por prefijo).

## Reversión

- Antes de la migración (paso 4): corregir y repetir `terraform apply`; el estado sigue local.
- Para volver el estado a local: `cp backend_override.tf.example backend_override.tf` y
  `terraform init -migrate-state`.
- Apagar el pipeline: `gh variable set GCP_ENABLED --body "false"` (los trabajos de GCP se
  omiten).
- La etapa 0 no se destruye por completo, a propósito: la llave y el bucket tienen
  `prevent_destroy`, los llaveros no se pueden borrar en GCP y un pool de WIF borrado reserva su
  ID durante 30 días. Para retirar algo hace falta un PR que quite el `prevent_destroy`,
  revisado por seguridad.

## Cambios posteriores

No hay cuenta de pipeline para la etapa 0. Cualquier cambio lo aplica una persona
administradora con el backend ya migrado:

```bash
cd stages/0-bootstrap
terraform init -backend-config="bucket=<state_bucket>"
terraform plan -out=tfplan
terraform apply tfplan
```
