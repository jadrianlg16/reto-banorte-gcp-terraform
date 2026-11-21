# Runbook 01: arranque de la etapa 0

## Objetivo

Crear, una sola vez, la base que necesita el pipeline: carpeta `bootstrap`, proyecto semilla,
llave KMS y bucket del estado, cuentas de servicio de las etapas 1 a 5, Workload Identity
Federation para GitHub y el rol personalizado de la etapa 4; migrar el estado local de la etapa
al bucket; activar Security Command Center y dejar GitHub listo para aplicar las etapas 1 a 5.

Nada de esto se ha ejecutado todavía: los pasos son el procedimiento diseñado, pendiente de
verificar en el primer apply ([pendientes](../pendientes-apply.md), puntos 1, 2, 13, 21, 22 y 23).

## Cuándo usarlo

- Al conectar la organización de GCP por primera vez.
- Para volver a aplicar la etapa 0 después (por ejemplo, para cambiar `github_repository`): en
  ese caso solo aplican los pasos 3 y 9 con el backend ya en el bucket (ver "Cambios
  posteriores").

## Prerrequisitos

- Herramientas del [README](../../README.md#herramientas): Terraform `>= 1.9`, `gcloud`, `gh`
  (GitHub CLI) con sesión en el repositorio.
- Organización, cuenta de facturación y los siete grupos de Cloud Identity
  ([README](../../README.md#google-cloud)).
- Persona administradora con, en la organización, `roles/resourcemanager.organizationAdmin`,
  `roles/resourcemanager.folderCreator`, `roles/resourcemanager.projectCreator` y
  `roles/iam.organizationRoleAdmin`, y en la cuenta de facturación `roles/billing.admin`.
  Para activar SCC además hace falta `roles/securitycenter.admin` en la organización (pendiente
  de verificar el rol exacto que pide la consola).
- Valores: `<org_id>`, `<billing_account>` (`XXXXXX-XXXXXX-XXXXXX`), `<prefix>` (2 a 6
  minúsculas o dígitos, empieza con letra; ejemplo `bnt`), `<project_suffix>` (opcional, para
  que el ID del proyecto semilla y el nombre del bucket sean únicos), `<dueño>/<repositorio>`.

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

   La última orden debe listar los cuatro roles de organización de los prerrequisitos.

2. Preparar variables y el backend local temporal.

   ```bash
   cd stages/0-bootstrap
   cp terraform.tfvars.example terraform.tfvars
   # editar: org_id, billing_account, prefix, project_suffix, primary_region,
   #         github_repository, labels (app, owner, cost_center en minúsculas)
   cp backend_override.tf.example backend_override.tf
   ```

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
   llavero `<prefix>-bootstrap-sec-keyring-<código>` con la llave `<prefix>-bootstrap-sec-state`,
   bucket `<prefix>-bootstrap-ops-tfstate[-<sufijo>]`, cinco cuentas `<prefix>-tf-<etapa>`, pool
   `<prefix>-bootstrap-sec-wif-pool` y proveedor `<prefix>-bootstrap-sec-github`, y ningún rol
   `roles/owner`, `roles/editor` ni `roles/resourcemanager.organizationAdmin`.

   Si la creación del bucket falla por permisos sobre la llave, repetir `terraform plan` y
   `terraform apply`: el permiso del agente de Cloud Storage puede tardar en propagarse
   (`main.tf:159`). Si una API rechaza la llamada por falta de proyecto de cuota (HYPOTHESIS,
   pendiente 22): `gcloud auth application-default set-quota-project <proyecto-existente>`.

4. Migrar el estado al bucket. El nombre del bucket se toma **antes** de borrar el override:
   después, `terraform output` falla con `Backend initialization required` (comprobado sin GCP,
   pendiente 21).

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
   ```

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
   raíces de `4-projects`). Crear los entornos `common`, `dev`, `qa` y `prod` (este con los
   revisores obligatorios) y la protección de `main` de `pipeline.md` §4.

10. Encender el pipeline, al final y solo con lo anterior listo.

    ```bash
    gh variable set GCP_ENABLED --body "true"
    gh workflow run apply.yml --ref main
    ```

## Verificación

- `terraform plan -detailed-exitcode` en `stages/0-bootstrap` sale con 0 desde el bucket.
- El bucket tiene CMEK, versionado, acceso uniforme y prevención de acceso público:

  ```bash
  gcloud storage buckets describe "gs://${STATE_BUCKET}" \
    --format="yaml(default_kms_key,versioning_enabled,uniform_bucket_level_access,public_access_prevention)"
  ```

- La llave rota cada 90 días:

  ```bash
  gcloud kms keys describe <prefix>-bootstrap-sec-state --keyring=<prefix>-bootstrap-sec-keyring-<código> \
    --location=<primary_region> --project=<seed_project_id> --format="value(rotationPeriod,nextRotationTime)"
  ```

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
