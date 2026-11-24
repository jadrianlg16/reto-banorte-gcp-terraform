# Runbook 02: alta de una aplicación o de un entorno en el proyecto

## Por qué cambió este runbook

Antes, dar de alta una aplicación era crear su proyecto de servicio. En el proyecto único
(ADR [0029](../adr/0029-un-solo-proyecto.md)) ya no hay proyectos de servicio ni Shared VPC: una
aplicación es un conjunto de recursos con nombre `<prefix>-<env>-<app>-…` dentro del mismo
proyecto. Por eso el runbook se reenfoca en dos casos:

- **A. Alta de una aplicación** en dev, qa o prod: repositorio de imágenes, secretos y cargas.
  Es el caso de operación normal.
- **B. Alta de un entorno** (por ejemplo, `uat`): no es operación, es un cambio de código. Se
  deja como lista de lo que hay que tocar.

El archivo conserva su nombre para no romper los enlaces que llegan a él.

Procedimiento diseñado, sin ejecutar en GCP.

## Prerrequisitos

- `1-base`, el hub y el spoke del entorno ya aplicados.
- Todo cambio entra por el pipeline: PR, o cambio de `GCP_TFVARS_JSON` y `apply.yml`. Las
  personas solo tienen lectura. Un cambio de `GCP_TFVARS_JSON` no pasa por revisión de PR:
  registrarlo antes en un PR o una incidencia (propuesta).
- Nombre de la aplicación `<app>`: de 2 a 8 caracteres, minúsculas y dígitos, empieza con letra,
  **sin guion** (`^[a-z][a-z0-9]{1,7}$`, validación de `application` en
  `stages/3-workloads/envs/<env>`). `1-base` admite desde 1 carácter; usa 2 o más para que pase
  en las dos raíces. Con el prefijo más largo (6) y `prod`, `<prefix>-prod-<app>-gke-nodes` llega
  justo a 30 caracteres, el límite del ID de cuenta de servicio (ADR 0017); la raíz lo valida.

## A. Alta de una aplicación

Rutas relativas a `gcp-datacenter/`. Los valores reales van en la llave de cada raíz de
`GCP_TFVARS_JSON` (por ejemplo `"stages/1-base"`).

1. **Secretos (si la aplicación los usa).** En `stages/1-base`, agregar los nombres cortos a
   `secret_names`:

   ```hcl
   secret_names = {
     <env> = ["<nombre-secreto>"]
   }
   ```

   Al aplicar, `1-base` crea el contenedor `<prefix>-<env>-sec-<nombre-secreto>`, sin valor
   (ADR 0015), con una réplica por región cifrada con la llave `secrets` de esa región. El valor
   lo carga una persona fuera de Terraform:

   ```bash
   gcloud secrets versions add <prefix>-<env>-sec-<nombre-secreto> \
     --data-file=<archivo-local> --project=<ID>
   ```

   Ningún grupo de `1-base` tiene `roles/secretmanager.secretVersionAdder`: definir quién carga
   los valores antes del alta ([pendientes](../pendientes-apply.md), §5).

2. **Repositorio de imágenes y quién publica.** En `stages/1-base`, agregar la aplicación a
   `applications` (conservando las que ya están) y declarar sus publicadores:

   ```hcl
   applications = ["app", "<app>"]
   artifact_registry_publishers = {
     <env> = { <app> = ["serviceAccount:<cuenta-del-ci>@<proyecto>.iam.gserviceaccount.com"] }
   }
   ```

   Publicadores: `serviceAccount:`, `group:`, `principal://` o `principalSet://`; nunca `user:`
   (validación de la variable). El plan de `1-base` debe agregar, solo para `<app>`:

   - un repositorio Docker `<prefix>-<env>-<app>` por entorno, en la multirregión `us`, con CMEK
     `artifacts` y etiquetas inmutables;
   - `roles/artifactregistry.writer` para cada publicador, solo sobre su repositorio;
   - el rol `<prefix>TfRepositoryIamGranter` para `tf-wl-<env>` sobre el repositorio de su
     entorno (con él, `3-workloads` da lectura a sus cuentas de ejecución);
   - en la política única de Binary Authorization, el patrón del repositorio en la lista de
     permitidos y la regla de los clústeres `<prefix>-prod-<app>-gke[-dr]`.

   No debe cambiar nada de las aplicaciones existentes. Revisar el plan en el PR y aplicar con
   `apply.yml`.

3. **Publicar la imagen.** Binary Authorization solo admite imágenes de los repositorios del
   proyecto y de `binary_authorization_allowlist_patterns`: una de otro registro, incluida la
   pública de ejemplo `us-docker.pkg.dev/cloudrun/container/hello`, se rechaza. La etiqueta es una
   versión o un digest, nunca `latest`: las etiquetas son inmutables.

   ```bash
   # URL del repositorio: salida artifact_registry_repositories de 1-base (entorno → app → {id, url})
   REPO=us-docker.pkg.dev/<ID>/<prefix>-<env>-<app>
   gcloud auth configure-docker us-docker.pkg.dev
   docker tag <imagen-local> "${REPO}/<imagen>:<versión>"
   docker push "${REPO}/<imagen>:<versión>"
   gcloud artifacts docker images list "${REPO}"
   ```

   Lo sube una identidad de `artifact_registry_publishers`. Sin publicadores declarados, ninguna
   cuenta del pipeline puede escribir en el repositorio.

   Ojo: una imagen de un repositorio de otro entorno también pasa Binary Authorization. La lista
   de permitidos es global y admite cualquier repositorio del proyecto (desviación del ADR 0029
   §4, comentario de `stages/1-base/artifacts.tf`; pendiente 42). Lo que impide que dev lea
   imágenes de prod es el IAM de lectura por repositorio.

4. **Cargas.** La raíz `stages/3-workloads/envs/<env>` crea las cargas de **una** aplicación
   (variable `application`, por defecto `app`) con un solo estado (`3-workloads/<env>`).

   - **Para `app`:** encender los interruptores en la llave `stages/3-workloads/envs/<env>`
     (`enable_gke`, `enable_mig`, `enable_cloud_run`, `enable_memorystore`, `enable_filestore`,
     `enable_internal_lb`) con sus entradas obligatorias (`cloud_run_image` con Cloud Run;
     `mig_image` con MIG; los pools de nodos con GKE; `internal_domain_names` con el balanceador
     interno) y aplicar con `apply.yml`. Las cuentas `<prefix>-<env>-<app>-{gke-nodes,workload,mig,run}`
     las crea esta raíz. El rango del plano de control de GKE sale de `reserved_cidrs` del spoke.
   - **Workload Identity (con GKE).** El namespace por defecto es `<app>-<env>` y la cuenta de
     Kubernetes, `app`: el pool de Workload Identity es el mismo para los tres entornos (ADR 0029
     §9). Fuera de Terraform, en el clúster:

     ```bash
     kubectl create namespace <app>-<env>
     kubectl create serviceaccount app --namespace <app>-<env>
     kubectl annotate serviceaccount app --namespace <app>-<env> \
       iam.gke.io/gcp-service-account=<prefix>-<env>-<app>-workload@<ID>.iam.gserviceaccount.com
     ```

   - **Para una segunda aplicación en el mismo entorno:** hoy **no está soportado**. No hay raíz
     ni trabajo de pipeline para ella, y algunos nombres no llevan la aplicación: el servicio de
     Cloud Run es `<prefix>-<env>-app-run-<región>` y la instancia de Cloud SQL,
     `<prefix>-<env>-data-<sql_instance_name>-<región>` (por defecto `sql`). Dos aplicaciones en
     el mismo entorno chocarían. Hace falta un cambio de código (raíz o espacio de trabajo por
     aplicación, nombres con la aplicación y trabajos en `apply.yml` y `drift.yml`); queda para
     el backlog.

5. **Fuera de Terraform** (si hay balanceador): registros DNS A de `domain_names` hacia
   `lb_ip_address`; registros de `internal_lb_dns_authorization_records_by_region` con el
   balanceador interno; en Cloud SQL, `CREATE EXTENSION pgaudit;` en cada base.

### Verificación

```bash
gcloud artifacts repositories list --project=<ID> --location=us --filter="name~<prefix>-<env>-<app>"
gcloud artifacts repositories get-iam-policy <prefix>-<env>-<app> --location=us --project=<ID>
gcloud container binauthz policy export --project=<ID>
gcloud iam service-accounts list --project=<ID> --filter="email~^<prefix>-<env>-<app>-" --format="value(email)"
```

El repositorio existe con CMEK; su IAM tiene el `writer` de los publicadores y el `reader` de las
cuentas de ejecución encendidas; la política de Binary Authorization lista su patrón; las cuentas
del entorno existen. `drift.yml` no abre incidencias de `1-base` ni de `3-workloads/<env>`.

### Reversión

- Antes, apagar las cargas de la aplicación en `3-workloads` (`enable_*` en `false`) y aplicar.
- Quitar la aplicación de `applications` y de `artifact_registry_publishers` en `1-base` y
  aplicar. El repositorio se borra con sus imágenes (HYPOTHESIS: que Artifact Registry no
  bloquee borrar un repositorio con imágenes).
- Quitar sus secretos de `secret_names`: el contenedor se borra con sus versiones.

## B. Alta de un entorno

No es un procedimiento de operación: `dev`, `qa` y `prod` están fijos en el código. Una búsqueda
del 24 nov 2026 (`grep -rlE` de las listas `"dev", "qa", "prod"`, `dev|qa|prod` y parecidas en
`stages`, `modules`, `scripts`, `policies` y `.github`, sin `tests/`) los encontró en 32
archivos, casi todos validaciones de la variable `environment`. Un entorno nuevo es un PR que
toca, como mínimo:

| Dónde | Qué |
|---|---|
| `stages/0-bootstrap` (`service_accounts.tf`) | Las cuentas `tf-net-<env>` y `tf-wl-<env>`, su WIF por `attribute.environment/<env>` y sus condiciones del estado. Lo aplica la persona dueña |
| `stages/1-base` | `environments` y la validación de `secret_names` (llaveros, llaves, secretos y repositorios del entorno) |
| `stages/2-networks` | `spoke_supernets` del hub (el /16 del entorno, contrato §5) y una raíz nueva `envs/<env>` |
| `stages/3-workloads` | Una raíz nueva `envs/<env>` |
| Módulos | La validación de `environment` en cada módulo |
| `.github/workflows` | Los trabajos del entorno en `apply.yml`; `destroy.yml` y `scripts/destroy-guard.sh` si se podrá destruir |
| GitHub | El entorno `<env>` (con revisores si es productivo) y sus llaves en `GCP_STAGE_SERVICE_ACCOUNTS` y `GCP_TFVARS_JSON` |
| Cuotas | Una VPC más y un peering más en el hub (runbook 01, paso 2) |

Después del PR, el orden es el del arranque: `0-bootstrap` a mano, luego `apply.yml`.

El alta anterior, con proyecto de servicio por aplicación, está en la rama
`archivo/multiproyecto`.
