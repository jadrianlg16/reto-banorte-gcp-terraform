# Runbook 02: alta de un proyecto de aplicación

## Objetivo

Dar de alta una aplicación nueva en un entorno: su proyecto de servicio unido a la Shared VPC
del spoke, sus cuentas de ejecución y permisos (etapa 4, variable `applications`) y, después,
sus cargas (etapa 5). Procedimiento diseñado, sin ejecutar en GCP.

## Cuándo usarlo

- Un equipo necesita un proyecto propio para una aplicación en `dev`, `qa` o `prod`.
- Se quieren encender cargas (GKE, MIG, Cloud Run, Memorystore, Filestore, balanceador interno)
  de la aplicación por defecto `app`.

## Prerrequisitos

- Etapas 0 a 3 del entorno aplicadas (el spoke `3-networks/envs/<env>` existe).
- El cambio entra por el pipeline (`apply.yml`) o lo corre una identidad con los permisos de
  `<prefix>-tf-4-projects` y `<prefix>-tf-5-workloads`; las personas solo tienen lectura.
- Los valores reales de cada raíz viven en la variable de repositorio `GCP_TFVARS_JSON`
  ([`pipeline.md`](../pipeline.md) §2). Un cambio de esa variable no pasa por revisión de PR:
  registrar el cambio en un PR o una incidencia antes de aplicarlo (propuesta).
- Nombre de la aplicación `<app>`:
  - 2 a 8 caracteres, minúsculas y dígitos, empieza con letra, **sin guion**
    (`^[a-z][a-z0-9]{1,7}$`). Es la misma validación en las llaves de `applications` de la
    etapa 4 y en `application` de la etapa 5, así que una aplicación que tiene proyecto también
    puede tener cargas;
  - con el prefijo más largo (6 caracteres) y `prod`, `<prefix>-prod-<app>-gke-nodes` llega
    justo a 30 caracteres (límite del ID de cuenta de servicio, ADR 0017); la etapa 4 lo valida
    además por separado;
  - el ID de proyecto `<prefix>-<env>-<app>[-<project_suffix>]` cabe en 30 caracteres
    (validación de `project-factory`).
- `workloads_service_account` de la etapa 4 (llave `stages/4-projects/envs/<env>` de
  `GCP_TFVARS_JSON`) debe ser igual a `stage_service_accounts["5-workloads"]` de las salidas de
  la etapa 0 (`terraform output -json stage_service_accounts` en `stages/0-bootstrap`). La etapa 4
  rechaza un correo que no empiece con `<prefix>-tf-5-workloads@`; con otra cuenta del mismo
  nombre en otro proyecto la validación pasa, pero la etapa 5 falla por permisos al crear las
  cargas.

## Pasos

Rutas relativas a `gcp-datacenter/`.

1. **Secretos (si la aplicación los usa).** Agregar los nombres cortos a `secret_names` de la
   etapa 2 (llave `stages/2-security` de `GCP_TFVARS_JSON`) y aplicar la etapa 2:

   ```hcl
   secret_names = {
     <env> = ["<nombre-secreto>"]
   }
   ```

   ```bash
   R=stages/2-security
   terraform -chdir="$R" init -backend-config="bucket=<state_bucket>"
   terraform -chdir="$R" plan -out=tfplan      # solo agrega google_secret_manager_secret
   terraform -chdir="$R" apply tfplan
   ```

   El secreto queda como contenedor sin valor (`<prefix>-<env>-sec-<nombre-secreto>`, ADR 0015).
   El valor lo carga el equipo dueño fuera de Terraform:

   ```bash
   gcloud secrets versions add <prefix>-<env>-sec-<nombre-secreto> \
     --data-file=<archivo-local> --project=<security_project_id>
   ```

   Ninguna etapa otorga hoy `roles/secretmanager.secretVersionAdder` a un grupo: definir quién
   carga los valores antes de dar de alta la aplicación (ver
   [pendientes](../pendientes-apply.md), §5).

2. **Proyecto de servicio (etapa 4).** Agregar la aplicación a `applications` en la llave
   `stages/4-projects/envs/<env>` de `GCP_TFVARS_JSON`, conservando las existentes:

   ```hcl
   applications = {
     app   = {}
     <app> = {
       apis    = ["<servicio>.googleapis.com"]   # adicionales a las base (README de la etapa 4)
       secrets = ["<nombre-secreto>"]            # deben existir en secret_ids[<env>] de la etapa 2
     }
   }
   # Quién publica las imágenes de <app> (paso 3): cuenta o grupo del pipeline de la aplicación.
   artifact_registry_publishers = {
     <app> = ["serviceAccount:<cuenta-del-pipeline>@<proyecto>.iam.gserviceaccount.com"]
   }
   ```

   ```bash
   R=stages/4-projects/envs/<env>
   terraform -chdir="$R" init -backend-config="bucket=<state_bucket>"
   terraform -chdir="$R" plan -out=tfplan
   ```

   El plan debe agregar, solo para `<app>`: el proyecto `<prefix>-<env>-<app>`, sus APIs, el
   alta como servicio de la Shared VPC, cuatro cuentas `<prefix>-<env>-<app>-{gke-nodes,workload,mig,run}`,
   los agentes de servicio (incluido el de Artifact Registry), los permisos de subred, de llaves
   KMS, de secretos y de etiquetas seguras; el repositorio Docker
   `<prefix>-<env>-app-<app>-images-us` (`google_artifact_registry_repository.this["<app>"]`) con
   lectura para `gke-nodes`, `mig` y el agente de Cloud Run y escritura
   (`google_artifact_registry_repository_iam_member.writer["<app>/<miembro>"]`) para cada
   publicador, y la política de Binary
   Authorization del proyecto (`google_binary_authorization_policy.this["<app>"]`); los permisos
   de la cuenta de la etapa 5 sobre el proyecto (`workloads_project_roles`, `projectIamAdmin`
   condicionado a los dos roles de Cloud SQL y `serviceAccountAdmin` sobre la cuenta `workload`)
   y `compute.networkViewer` en el host; y, en prod, una alta en el perímetro de VPC-SC
   (`service/<app>`; el host ya estaba dado de alta) y la regla de entrada de sus publicadores
   (`..._ingress_policy.artifact_publishers["<app>"]`, o `..._dry_run_ingress_policy` con el
   perímetro en dry-run). No debe cambiar nada de las aplicaciones
   existentes. Si falla una postcondición de `remote_state.tf` ("Algún secreto de
   applications[*].secrets no existe…"), falta el paso 1.

   ```bash
   terraform -chdir="$R" apply tfplan
   terraform -chdir="$R" output -json service_project_ids
   terraform -chdir="$R" output -json service_accounts
   terraform -chdir="$R" output -json artifact_registry_repositories
   ```

3. **Imagen de la aplicación en su repositorio.** Binary Authorization solo admite imágenes del
   repositorio de la aplicación (y los patrones de `binary_authorization_allowlist_patterns`;
   ADR 0024): una imagen de otro registro, incluida la pública de ejemplo
   `us-docker.pkg.dev/cloudrun/container/hello`, se rechaza. Antes de encender GKE o Cloud Run,
   el pipeline de la aplicación sube la imagen con una identidad declarada en
   `artifact_registry_publishers["<app>"]` de la etapa 4 (`serviceAccount:` o `group:`, nunca
   `user:`): recibe `roles/artifactregistry.writer` solo sobre ese repositorio y, en prod, entra
   al perímetro de VPC-SC por la regla `<prefix>-prod-<app>-artifact-push`, limitada a
   `artifactregistry.googleapis.com` en el proyecto de servicio de la aplicación (pendiente 53:
   falta comprobar en el apply que las reglas de las dos etapas convivan). Sin publicadores declarados nadie puede escribir en el
   repositorio. La etiqueta es una versión (o se usa el digest), nunca `latest`: el repositorio
   tiene etiquetas inmutables y una etiqueta publicada no se puede mover a otra imagen.

   ```bash
   REPO="$(terraform -chdir="$R" output -json artifact_registry_repositories | jq -r '.["<app>"]')"
   gcloud auth configure-docker us-docker.pkg.dev
   docker tag <imagen-local> "${REPO}/<imagen>:<versión>"
   docker push "${REPO}/<imagen>:<versión>"
   gcloud artifacts docker images list "${REPO}"
   ```

   `cloud_run_image` (y las imágenes de los despliegues de GKE) apuntan a `${REPO}/<imagen>:<versión>`.

   En el pipeline: actualizar la variable y lanzar `gh workflow run apply.yml --ref main` (corre
   todas las raíces en orden; las que no cambian no aplican nada).

4. **Cargas (etapa 5).** La raíz `stages/5-workloads/envs/<env>` crea las cargas de **una**
   aplicación (variable `application`, por defecto `app`) con un solo estado
   (`5-workloads/<env>`).

   - Para la aplicación `app`: encender los interruptores en la llave
     `stages/5-workloads/envs/<env>` de `GCP_TFVARS_JSON` (`enable_gke`, `enable_mig`,
     `enable_cloud_run`, `enable_memorystore`, `enable_filestore`, `enable_internal_lb`) con
     sus entradas obligatorias (`gke_node_pools` y `gke_authenticator_security_group` con GKE;
     `mig_image` con MIG; `cloud_run_image` del paso 3 con Cloud Run; `internal_domain_names`
     con el balanceador interno) y aplicar. El rango del plano de control de GKE no se escribe
     aquí: sale de `reserved_cidrs["gke_master"]` del estado de `3-networks/<env>` (una
     postcondición de `remote_state.tf` lo exige como /28). Con GKE, la cuenta de Kubernetes
     de la carga es `gke_workload_namespace`/`gke_workload_ksa_name` (por defecto `app`/`app`):

     ```bash
     R=stages/5-workloads/envs/<env>
     terraform -chdir="$R" init -backend-config="bucket=<state_bucket>"
     terraform -chdir="$R" plan -out=tfplan
     terraform -chdir="$R" apply tfplan
     terraform -chdir="$R" output -raw gke_workload_identity_member   # con GKE
     ```

     **Workload Identity (con GKE).** El apply enlaza la cuenta de Kubernetes a la cuenta
     `workload` (`google_service_account_iam_member.workload_identity`). Falta, fuera de
     Terraform, crear en el clúster el namespace y la cuenta de Kubernetes con la anotación que
     apunta a la cuenta `workload` (correo en `service_accounts` de la etapa 4), y usarla en los
     pods:

     ```bash
     kubectl create namespace app
     kubectl create serviceaccount app --namespace app
     kubectl annotate serviceaccount app --namespace app \
       iam.gke.io/gcp-service-account=<prefix>-<env>-<app>-workload@<proyecto>.iam.gserviceaccount.com
     ```

     La cuenta `workload` (y `run` con Cloud Run, `mig` con el MIG) es usuario IAM de Cloud SQL
     (ADR 0015): la aplicación entra con el conector de Cloud SQL o el proxy con token de IAM.

   - Para una aplicación adicional: no hay raíz ni pipeline para ella (limitación en
     [pendientes](../pendientes-apply.md), §5). Opción diseñada y **no probada**: un espacio de
     trabajo de Terraform en la misma raíz, cuyo estado cae en
     `5-workloads/<env>/<app>.tfstate`, dentro del prefijo que la cuenta de la etapa puede
     escribir:

     ```bash
     terraform -chdir="$R" init -backend-config="bucket=<state_bucket>"
     terraform -chdir="$R" workspace new <app>
     terraform -chdir="$R" plan -var="application=<app>" -var-file=<tfvars-de-la-app> -out=tfplan
     terraform -chdir="$R" apply tfplan
     ```

     `apply.yml` y `drift.yml` solo recorren el espacio `default`: este estado queda fuera del
     despliegue automático y de la detección de drift hasta que se extiendan los flujos.

5. **Pasos fuera de Terraform** (si hay balanceador): registros DNS A de `domain_names` hacia
   `lb_ip_address`; registros de `internal_lb_dns_authorization_records_by_region` (uno por
   región con balanceador interno); en Cloud SQL, `CREATE EXTENSION pgaudit;` en cada base.

## Verificación

```bash
gcloud projects describe <prefix>-<env>-<app> --format="value(lifecycleState,parent)"
gcloud compute shared-vpc associated-projects list <host_project_id>
gcloud iam service-accounts list --project=<prefix>-<env>-<app> --format="value(email)"
gcloud artifacts repositories list --project=<prefix>-<env>-<app> --location=us
gcloud container binauthz policy export --project=<prefix>-<env>-<app>
# Solo prod (dry-run por defecto; con el perímetro forzado, sin "dry-run"):
gcloud access-context-manager perimeters dry-run describe <prefix>_prod_sec_perimeter --policy=<access_policy_id>
terraform -chdir=stages/4-projects/envs/<env> plan -detailed-exitcode   # 0: sin cambios
```

El proyecto aparece `ACTIVE` en la carpeta del entorno, asociado al host; las cuatro cuentas
existen; el repositorio `<prefix>-<env>-app-<app>-images-us` existe con CMEK; la política de
Binary Authorization admite solo ese repositorio; en prod, el número del proyecto figura entre
los recursos del perímetro.

## Reversión

- Quitar la llave de `applications` y aplicar la etapa 4 destruye el proyecto **solo** si
  `deletion_policy` lo permite. Por defecto vale `PREVENT` (el apply falla) y en prod es el
  único valor admitido. En dev o qa: `deletion_policy = "DELETE"`, aplicar, y volver a
  `PREVENT`.
- Antes, destruir las cargas de la aplicación en la etapa 5 (o su espacio de trabajo) y dejar
  `enable_*` en `false`.
- En prod el proyecto no se borra desde Terraform. Propuesta, no probada: `terraform state rm`
  de sus recursos en la etapa 4 y baja del proyecto por la persona administradora, con
  `gcloud projects delete <prefix>-prod-<app>` (recuperable durante 30 días con
  `gcloud projects undelete`).
