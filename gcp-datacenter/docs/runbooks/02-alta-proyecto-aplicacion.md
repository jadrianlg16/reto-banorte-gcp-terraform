# Runbook 02: alta de una aplicación o de un entorno en el proyecto

## Por qué cambió este runbook

Antes, dar de alta una aplicación era crear su proyecto de servicio. En el proyecto único
(ADR [0029](../adr/0029-un-solo-proyecto.md)) ya no hay proyectos de servicio ni Shared VPC: una
aplicación es un conjunto de recursos con nombre `<prefix>-<env>-<app>-…` dentro del mismo
proyecto. Por eso el runbook se reenfoca en dos casos:

- **A. Alta de una aplicación** en dev, qa o prod: repositorio de imágenes, cuentas de
  ejecución, secretos y cargas. Es el caso de operación normal.
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
  **sin guion** (`^[a-z][a-z0-9]{1,7}$`, la misma validación en `applications` de `1-base` y en
  `application` de `stages/3-workloads/envs/<env>`). Con el prefijo más largo (6) y `prod`,
  `<prefix>-prod-<app>-gke-nodes` llega justo a 30 caracteres, el límite del ID de cuenta de
  servicio (ADR 0017); `1-base`, que crea las cuentas, lo valida.

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
   (ADR 0015), con una réplica en la región primaria y, si el entorno está en `dr_environments`
   (por defecto solo prod), otra en la región de DR, cada una cifrada con la llave `secrets` de su
   región. `1-base` también da `roles/secretmanager.secretAccessor` sobre cada secreto del entorno
   a las cuentas `workload` y `run` de **todas** las aplicaciones del entorno: la frontera es el
   entorno, no la aplicación (ADR 0029 §3). `3-workloads` ya no tiene una lista de secretos. El
   valor lo carga una persona fuera de Terraform:

   ```bash
   gcloud secrets versions add <prefix>-<env>-sec-<nombre-secreto> \
     --data-file=<archivo-local> --project=<ID>
   ```

   Ningún grupo de `1-base` tiene `roles/secretmanager.secretVersionAdder`: definir quién carga
   los valores antes del alta ([pendientes](../pendientes-apply.md), §5).

2. **Repositorio, cuentas de ejecución y quién publica.** En `stages/1-base`, agregar la
   aplicación a `applications` (conservando las que ya están; la lista vale para todos los
   entornos de `environments`) y declarar sus publicadores:

   ```hcl
   applications = ["app", "<app>"]
   artifact_registry_publishers = {
     <env> = { <app> = ["serviceAccount:<cuenta-del-ci>@<proyecto>.iam.gserviceaccount.com"] }
   }
   ```

   Publicadores: `serviceAccount:`, `group:`, `principal://` o `principalSet://`; nunca `user:`
   (validación de la variable). El plan de `1-base` debe agregar, solo para `<app>` y en cada
   entorno:

   - un repositorio Docker `<prefix>-<env>-<app>` en `artifact_registry_location` (la
     multirregión `us` por defecto), con CMEK `artifacts` y etiquetas inmutables, y lectura para
     el agente de Cloud Run (uno por proyecto: lee los repositorios de los tres entornos, riesgo
     aceptado del ADR 0029 §9);
   - `roles/artifactregistry.writer` para cada publicador, solo sobre su repositorio;
   - las cuentas de ejecución `<prefix>-<env>-<app>-{gke-nodes,workload,mig,run}` y, en los
     entornos de `off_hours_environments` (dev y qa por defecto), `<prefix>-<env>-<app>-sched`
     (`stages/1-base/runtime_accounts.tf`), con sus roles de proyecto (telemetría; el rol del
     apagado para `sched`), `roles/artifactregistry.reader` solo sobre su repositorio para
     `gke-nodes` y `mig`, `cloudsql.client` y `cloudsql.instanceUser` condicionados a las
     instancias `<prefix>-<env>-data-` para `workload`, `run` y `mig`, y la lectura de los
     secretos del entorno (paso 1);
   - `roles/iam.serviceAccountUser` para `tf-wl-<env>` solo sobre `gke-nodes`, `mig`, `run` y
     `sched` de su entorno (las que adjunta a sus recursos);
   - en la política única de Binary Authorization: sin `binary_authorization_env_attestors` (lo de
     hoy), el patrón del repositorio en la lista de permitidos y la regla de los clústeres
     `<prefix>-prod-<app>-gke[-dr]`; con atestadores por entorno, la regla de los clústeres
     `<prefix>-<env>-<app>-gke[-dr]` de cada entorno con el atestador de su entorno.

   No debe cambiar nada de las aplicaciones existentes. Revisar el plan en el PR y aplicar con
   `apply.yml`. Que `3-workloads` pueda usar las cuentas nuevas en el apply siguiente, sin
   errores de propagación, es el pendiente 131; las condiciones de Cloud SQL, el 133.

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

   Ojo: sin `binary_authorization_env_attestors` (el valor por defecto), una imagen de un
   repositorio de otro entorno también pasa Binary Authorization. La lista de permitidos es
   global y admite cualquier repositorio del proyecto (desviación del ADR 0029 §4, comentario de
   `stages/1-base/artifacts.tf`; pendiente 42). Lo que impide que los nodos de GKE y las VM de dev
   descarguen imágenes de prod es el IAM de lectura por repositorio; Cloud Run descarga con el
   agente del proyecto, que lee todos. Con un atestador por entorno, los repositorios salen de la
   lista y cada clúster exige la atestación de su entorno; Cloud Run solo tiene la regla por
   defecto (pendiente 139). Los atestadores no los crea ninguna raíz.

4. **Cargas.** La raíz `stages/3-workloads/envs/<env>` crea las cargas de **una** aplicación
   (variable `application`, por defecto `app`) con un solo estado (`3-workloads/<env>`).

   - **Para `app`:** encender los interruptores en la llave `stages/3-workloads/envs/<env>`
     (`enable_gke`, `enable_mig`, `enable_cloud_run`, `enable_memorystore`, `enable_filestore`,
     `enable_internal_lb`) con sus entradas obligatorias (`cloud_run_image` con Cloud Run;
     `mig_image` con MIG; los pools de nodos con GKE; `internal_domain_names` con el balanceador
     interno) y aplicar con `apply.yml`. Esta raíz no crea cuentas de servicio ni da roles: usa
     las que creó `1-base` en el paso 2 (salida `runtime_service_accounts`) y falla en su plan
     si no existen. Con `off_hours_shutdown.enabled`, el entorno tiene que estar en
     `off_hours_environments` de `1-base` (cuenta `sched`). El rango del plano de control de GKE
     sale de `reserved_cidrs` del spoke.
   - **Workload Identity (con GKE).** El namespace es `<app>-<env>` (fijo) y la cuenta de
     Kubernetes, `gke_workload_ksa_name` de `1-base` (`app` por defecto): el pool de Workload
     Identity es el mismo para los tres entornos (ADR 0029 §9). El enlace con la cuenta `workload`
     lo crea `1-base`, en dos pasadas: el pool `<ID>.svc.id.goog` lo crea GKE con el primer
     clúster, así que primero se aplica esta raíz con `enable_gke` (el plan avisa que falta el
     enlace) y después `gke_workload_identity_bindings = true` en la llave `stages/1-base` y
     `apply.yml` otra vez (pendiente 135). Fuera de Terraform, en el clúster:

     ```bash
     # <ksa>: gke_workload_ksa_name de 1-base (app por defecto)
     kubectl create namespace <app>-<env>
     kubectl create serviceaccount <ksa> --namespace <app>-<env>
     kubectl annotate serviceaccount <ksa> --namespace <app>-<env> \
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
gcloud iam service-accounts get-iam-policy <prefix>-<env>-<app>-run@<ID>.iam.gserviceaccount.com --project=<ID>
```

El repositorio existe con CMEK; su IAM tiene el `writer` de los publicadores y el `reader` de
`gke-nodes`, `mig` y el agente de Cloud Run; la política de Binary Authorization lista su patrón
(o, con atestadores por entorno, las reglas de sus clústeres); las cuentas del entorno existen y
`tf-wl-<env>` tiene `serviceAccountUser` sobre `run` (y sobre `gke-nodes`, `mig` y `sched`).
`drift.yml` no abre incidencias de `1-base` ni de `3-workloads/<env>`.

### Reversión

- Antes, apagar las cargas de la aplicación en `3-workloads` (`enable_*` en `false`) y aplicar:
  sin eso, quitar la aplicación de `1-base` borraría cuentas que todavía usan sus recursos, y el
  plan de `3-workloads` falla si sus cuentas no están en `runtime_service_accounts`.
- Quitar la aplicación de `applications` y de `artifact_registry_publishers` en `1-base` y
  aplicar. Se borran su repositorio con sus imágenes (HYPOTHESIS: que Artifact Registry no
  bloquee borrar un repositorio con imágenes) y sus cuentas de ejecución con sus permisos, en
  todos los entornos.
- Quitar sus secretos de `secret_names`: el contenedor se borra con sus versiones. Ojo: los
  secretos son del entorno, no de la aplicación; las demás aplicaciones del entorno también los
  leen.

## B. Alta de un entorno

No es un procedimiento de operación: `dev`, `qa` y `prod` están fijos en el código. Una búsqueda
del 24 nov 2026, desde `gcp-datacenter/`:

```bash
grep -rlE --exclude-dir=.terraform --exclude-dir=tests --exclude-dir=testdata \
  '"dev", *"qa", *"prod"|dev\|qa\|prod|\(dev\|qa\)|"dev", *"qa"' \
  stages modules scripts policies ../.github | wc -l
```

dio 36 archivos, casi todos validaciones de la variable `environment`. Un entorno nuevo es un PR
que toca, como mínimo:

| Dónde | Qué |
|---|---|
| `stages/0-bootstrap` (`service_accounts.tf`) | Las cuentas `tf-net-<env>` y `tf-wl-<env>`, su WIF por `attribute.deploy/<env>`, sus roles y sus condiciones del estado. Lo aplica la persona dueña |
| `stages/1-base` | `environments` y las validaciones de `secret_names`, `off_hours_environments` y `dr_environments` (llaveros, llaves, secretos, repositorios y cuentas de ejecución del entorno) |
| `stages/2-networks` | `spoke_supernets` del hub (el /16 del entorno, contrato §5) y una raíz nueva `envs/<env>` |
| `stages/3-workloads` | Una raíz nueva `envs/<env>` |
| Módulos | La validación de `environment` en cada módulo |
| `.github/workflows` y `scripts/` | Los trabajos del entorno en `apply.yml`; `scripts/disabled-envs.py` si se podrá apagar; `destroy.yml` y `scripts/destroy-guard.sh` si se podrá destruir |
| GitHub | El entorno `<env>` (con revisores si es productivo) y sus llaves en `GCP_STAGE_SERVICE_ACCOUNTS` y `GCP_TFVARS_JSON` |
| Cuotas | Una VPC más y un peering más en el hub (runbook 01, paso 2) |

Después del PR, el orden es el del arranque: `0-bootstrap` a mano, luego `apply.yml`.

El alta anterior, con proyecto de servicio por aplicación, está en la rama
`archivo/multiproyecto`.
