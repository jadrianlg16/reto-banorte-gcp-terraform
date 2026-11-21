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
  - 2 a 10 caracteres, minúsculas y dígitos, empieza con letra, **sin guion**
    (`^[a-z][a-z0-9]{1,9}$`). La etapa 4 admitiría guiones, pero la variable `application` de la
    etapa 5 no (pendiente 26);
  - `<prefix>-<env>-<app>-gke-nodes` cabe en 30 caracteres (validación de la etapa 4, ADR 0017);
    con `prefix = "bnt"` y `prod` quedan 11 caracteres, así que el límite real es el de 10 de la
    etapa 5;
  - el ID de proyecto `<prefix>-<env>-<app>[-<project_suffix>]` cabe en 30 caracteres
    (validación de `project-factory`).

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
   ```

   ```bash
   R=stages/4-projects/envs/<env>
   terraform -chdir="$R" init -backend-config="bucket=<state_bucket>"
   terraform -chdir="$R" plan -out=tfplan
   ```

   El plan debe agregar, solo para `<app>`: el proyecto `<prefix>-<env>-<app>`, sus APIs, el
   alta como servicio de la Shared VPC, cuatro cuentas `<prefix>-<env>-<app>-{gke-nodes,workload,mig,run}`,
   los agentes de servicio, los permisos de subred, de llaves KMS, de secretos y de etiquetas
   seguras y, en prod, una alta en el perímetro de VPC-SC (`service/<app>`; el host ya estaba
   dado de alta). No debe cambiar nada de las aplicaciones existentes. Si falla una postcondición de
   `remote_state.tf` ("Algún secreto de applications[*].secrets no existe…"), falta el paso 1.

   ```bash
   terraform -chdir="$R" apply tfplan
   terraform -chdir="$R" output -json service_project_ids
   terraform -chdir="$R" output -json service_accounts
   ```

   En el pipeline: actualizar la variable y lanzar `gh workflow run apply.yml --ref main` (corre
   todas las raíces en orden; las que no cambian no aplican nada).

3. **Cargas (etapa 5).** La raíz `stages/5-workloads/envs/<env>` crea las cargas de **una**
   aplicación (variable `application`, por defecto `app`) con un solo estado
   (`5-workloads/<env>`).

   - Para la aplicación `app`: encender los interruptores en la llave
     `stages/5-workloads/envs/<env>` de `GCP_TFVARS_JSON` (`enable_gke`, `enable_mig`,
     `enable_cloud_run`, `enable_memorystore`, `enable_filestore`, `enable_internal_lb`) con
     sus entradas obligatorias (`gke_node_pools`, `gke_authenticator_security_group` y
     `subnet_cidrs["gke_master"]` con GKE; `mig_image` con MIG; `cloud_run_image` con Cloud Run;
     `internal_domain_names` con el balanceador interno) y aplicar:

     ```bash
     R=stages/5-workloads/envs/<env>
     terraform -chdir="$R" init -backend-config="bucket=<state_bucket>"
     terraform -chdir="$R" plan -out=tfplan
     terraform -chdir="$R" apply tfplan
     ```

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

4. **Pasos fuera de Terraform** (si hay balanceador): registros DNS A de `domain_names` hacia
   `lb_ip_address`; registros de `internal_lb_dns_authorization_records`; en Cloud SQL,
   `CREATE EXTENSION pgaudit;` en cada base.

## Verificación

```bash
gcloud projects describe <prefix>-<env>-<app> --format="value(lifecycleState,parent)"
gcloud compute shared-vpc associated-projects list <host_project_id>
gcloud iam service-accounts list --project=<prefix>-<env>-<app> --format="value(email)"
# Solo prod (dry-run por defecto; con el perímetro forzado, sin "dry-run"):
gcloud access-context-manager perimeters dry-run describe <prefix>_prod_sec_perimeter --policy=<access_policy_id>
terraform -chdir=stages/4-projects/envs/<env> plan -detailed-exitcode   # 0: sin cambios
```

El proyecto aparece `ACTIVE` en la carpeta del entorno, asociado al host; las cuatro cuentas
existen; en prod, el número del proyecto figura entre los recursos del perímetro.

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
