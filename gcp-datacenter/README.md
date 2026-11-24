# gcp-datacenter

Landing zone de Google Cloud escrita en Terraform, toda dentro de **un solo proyecto de GCP**:
estado e identidad del pipeline, controles que existen una vez por proyecto (auditoría, KMS,
Secret Manager, Binary Authorization), red hub y spoke con conectividad híbrida y las cargas de
cada entorno (`dev`, `qa`, `prod`), con políticas de Conftest y flujos de GitHub Actions. El
diseño de varios proyectos vive en la rama `archivo/multiproyecto`.

**Estado:** todo se construyó y se probó **sin acceso a GCP**. Nada se ha aplicado todavía. Lo
que este documento dice del comportamiento en GCP es diseño, no resultado; lo que solo se
comprueba con un apply está en [`docs/pendientes-apply.md`](docs/pendientes-apply.md).

El diseño vigente es el del [ADR 0029](docs/adr/0029-un-solo-proyecto.md), que manda sobre
[`docs/CONTRATO.md`](docs/CONTRATO.md) donde choquen. Las demás decisiones están en
[`docs/adr/`](docs/adr/README.md), el pipeline en [`docs/pipeline.md`](docs/pipeline.md) y los
procedimientos de operación en [`docs/runbooks/`](docs/runbooks/).

Para desplegarlo por primera vez en un proyecto propio (desde crear el proyecto hasta el
destroy, con un prompt para Claude Code): [`docs/guia-colaborador-gcp.md`](docs/guia-colaborador-gcp.md).
Lo que falta para terminar el proyecto: [`docs/backlog.md`](docs/backlog.md). Sesiones para
entregar la operación: [`docs/transferencia-de-conocimiento.md`](docs/transferencia-de-conocimiento.md).

## Arquitectura en breve

- **Un proyecto, tres entornos.** Una persona crea el proyecto y lo liga a una cuenta de
  facturación de pago; ninguna raíz lo crea ni lo borra. `dev`, `qa` y `prod` conviven en él,
  separados por una VPC por entorno, por los nombres `<prefix>-<env>-` y la etiqueta `env`, y
  por una cuenta del pipeline por entorno ligada a su entorno de GitHub (ADR 0029 §9). Lo que
  ya no separa (los permisos sin condición de las cuentas de entorno sobre Compute, GKE, Cloud
  Run, Cloud SQL, Memorystore, Filestore, Backup and DR y Monitoring, los agentes de servicio y
  las cuotas) queda como riesgo aceptado en el mismo ADR, con lo que lo detecta y lo que lo
  cerraría.
- **La organización es opcional** (`org_id`, `null` por defecto). Con organización,
  `0-bootstrap`, que aplica una persona, aplica políticas de organización al proyecto y, con
  `access_policy_id`, un perímetro de VPC-SC en dry-run que rodea todo el proyecto
  (`stages/0-bootstrap/org.tf`). Ninguna cuenta del pipeline recibe roles de organización ni de
  la política de acceso. Sin organización esos controles no existen: los cubren las reglas de
  Conftest de cada PR y pasos manuales del [runbook 01](docs/runbooks/01-arranque-etapa-0.md).
  Que no se puedan usar sin organización es HYPOTHESIS (ADR 0029 §1).
- **Estado e identidad** (`0-bootstrap`, a mano): bucket de estado en la multirregión `US`,
  cifrado con una llave propia ([0008](docs/adr/0008-llave-kms-propia-de-la-etapa-0.md),
  [0022](docs/adr/0022-estado-y-conmutacion-sin-depender-de-la-region-primaria.md)), con un
  prefijo por raíz e IAM condicionado
  ([0010](docs/adr/0010-bucket-de-estado-unico-con-iam-por-prefijo.md)); nueve cuentas del
  pipeline, una por raíz y entorno más `tf-read` de solo lectura; Workload Identity Federation
  para GitHub por ID numérico del repositorio. Cada cuenta que escribe solo acepta tokens de un
  trabajo de `main`, de un flujo de `.github/workflows/` de este repositorio y de su entorno de
  GitHub (`attribute.deploy`); `tf-read`, de cualquier trabajo del repositorio
  ([0007](docs/adr/0007-ci-cd-con-github-actions.md),
  [0023](docs/adr/0023-endurecimiento-de-la-identidad-del-pipeline.md)). Una política de
  denegación en el proyecto protege el estado y las cuentas con la etiqueta `<prefix>-proteccion`
  y niega a las nueve cuentas pedir tokens o firmas de cualquier cuenta de servicio (HYPOTHESIS
  que la etiqueta funcione sin organización, ADR 0029 §5). Las cuentas de ejecución de las
  cargas (`<prefix>-<env>-<app>-<uso>`) las crea `1-base` con sus permisos; la cuenta de cargas
  de cada entorno solo puede adjuntar las de su entorno. Las personas tienen IAM de solo
  lectura, por grupos; solo el pipeline despliega
  ([diagrama 1](docs/diagramas/01-organizacion-gobierno-acceso.md)).
- **Red:** cinco VPC en el proyecto. El hub `<prefix>-common-net-hub` con dos HA VPN de dos
  túneles y BGP (una por región; la de DR, menos preferida) y reenvío de DNS; on-premises
  simulado con la VPC `onprem-sim` mientras no haya sitio real
  ([0006](docs/adr/0006-on-premises-simulado-con-ha-vpn-entre-vpc.md)), con una VM DNS de
  prueba opcional (`onprem_dns_vm = true`) que responde por el dominio de on-premises; la VPN
  real (`simulate_onprem = false`) todavía no se puede planear desde el pipeline (pendiente
  151). Un spoke por entorno unido al hub por peering, sin peering entre spokes
  ([0003](docs/adr/0003-vpc-por-entorno-unida-al-hub-por-peering.md)), con Cloud NAT por región
  y su propia conexión de Private Service Access
  ([0004](docs/adr/0004-cloud-nat-en-cada-spoke.md)). Sin Shared VPC, que necesita
  organización y proyectos distintos para el host y el servicio: el spoke y sus cargas están en
  el mismo proyecto. Cada VPC tiene su política de firewall de red, en lugar de la jerárquica,
  que se asocia a una organización o a carpetas (ADR 0029 §6;
  [diagrama 2](docs/diagramas/02-red-y-conectividad.md)).
- **Cargas:** balanceador HTTPS global con Cloud Armor en la raíz de cargas de cada entorno y
  balanceador interno uno por región con acceso global
  ([0005](docs/adr/0005-balanceador-y-cloud-armor-en-el-proyecto-de-servicio.md)); GKE, MIG y
  Cloud Run con interruptores ([0012](docs/adr/0012-gke-mig-y-cloud-run.md),
  [diagrama 3](docs/diagramas/03-aplicacion-y-proteccion-de-datos.md)); imágenes en un
  repositorio de Artifact Registry por entorno y aplicación, con una sola política de Binary
  Authorization en el proyecto
  ([0024](docs/adr/0024-artifact-registry-y-binary-authorization-por-proyecto.md)). Sin
  atestadores, la lista de permitidos es global y un clúster de prod admite una imagen del
  repositorio de dev (riesgo aceptado); con `binary_authorization_env_attestors`, cada clúster
  exige el atestador de su entorno (los atestadores no los crea ninguna raíz; README de
  `stages/1-base`).
- **Datos solo por IP privada:** Cloud SQL, Memorystore y Filestore por Private Service Access;
  Cloud Storage y demás APIs (incluidos `gcr.io`, `pkg.dev` y `run.app`) por Private Google
  Access y el VIP restringido ([0026](docs/adr/0026-api-de-google-por-el-vip-restringido-en-todos-los-entornos.md)).
  CMEK en todo; los llaveros de cada entorno viven en `1-base` y sus llaves rotan cada 90 días.
- **CIS GCP Foundation Benchmark v5.0**, mapeado en
  [`docs/cumplimiento-cis.md`](docs/cumplimiento-cis.md): contactos esenciales, configuración
  de auditoría y métricas y alertas de auditoría una sola vez en el proyecto (`1-base`, módulo
  `audit-alerts`); los registros de acceso a datos valen para los tres entornos, porque la
  configuración de auditoría es única por proyecto (ADR 0029 §7). Cloud Asset y OS Login en el
  proyecto, flow logs al 100 % en prod y en el hub. Las desviaciones aceptadas están en el ADR
  [0027](docs/adr/0027-desviaciones-aceptadas-del-cis.md).
- **DR de prod en `us-east4`:** réplica de Cloud SQL, bucket de doble región con turbo
  replication, Backup and DR y Backup for GKE; conmutación con `dr_active`, sin depender de la
  región primaria para el estado, la VPN ni el balanceador interno
  ([0002](docs/adr/0002-regiones-primaria-y-de-dr.md),
  [diagrama 4](docs/diagramas/04-operacion-continuidad-automatizacion.md)).
- **Apagado fuera de horario** opcional en dev y qa (`off_hours_shutdown`, encendido en sus
  ejemplos, rechazado en prod): Cloud SQL y pools de GKE con trabajos de Cloud Scheduler, MIG
  con programa de escalado, sin deriva falsa en `drift.yml`
  ([0028](docs/adr/0028-apagado-fuera-de-horario-de-dev-y-qa.md)). El rol del apagado existe
  una vez en el proyecto (`0-bootstrap`); `1-base` crea la cuenta del apagado de dev y qa
  (`off_hours_environments`).

## Mapa del repositorio

| Ruta | Contenido |
|---|---|
| `modules/` | 24 módulos propios, cada uno con `README.md`, `examples/basic/` y `tests/` (contrato §8) |
| `stages/0-bootstrap` | La aplica una persona, a mano. Todas las APIs del proyecto, llave y bucket de estado (multirregión), las nueve cuentas del pipeline con sus roles de proyecto, cuatro roles personalizados, WIF, etiqueta de protección y política de denegación, `tagUser` de los agentes de GKE y de las APIs, cuenta de Compute por defecto sin Editor, presupuesto del proyecto; con organización, políticas de organización y VPC-SC opcional |
| `stages/1-base` | Lo que existe una vez por proyecto: configuración de auditoría, sink y bucket de logs, alertas de auditoría, canal de operaciones opcional, contactos esenciales y SCC opcional; llaveros KMS y contenedores de secretos por entorno; repositorios de Artifact Registry y la política de Binary Authorization; cuentas de ejecución de cada entorno y aplicación con sus permisos (y la de la VM DNS de `onprem-sim`, si se pide); IAM de personas |
| `stages/2-networks` | Raíz del hub (ADR 0014): VPC hub, VPN primaria y de DR, DNS, políticas de firewall de red del hub y de `onprem-sim`, VM DNS de prueba de `onprem-sim` opcional |
| `stages/2-networks/envs/{dev,qa,prod}` | Un spoke por entorno: VPC, Cloud NAT, PSA, peering con el hub, política de firewall de red con sus etiquetas seguras (y `tagUser` de la cuenta de cargas del entorno sobre sus valores) y zonas de las APIs de Google hacia el VIP |
| `stages/3-workloads/envs/{dev,qa,prod}` | Cómputo, datos, balanceadores, observabilidad, respaldo y apagado fuera de horario, con las cuentas de ejecución que crea `1-base` |
| `policies/` | Doce reglas de Conftest (Rego) más `lib.rego`, sus pruebas y 42 planes de ejemplo en `fixtures/` |
| `scripts/` | `check.sh`, `policy-check.sh`, `docs.sh`, `affected-roots.sh`, `root-tfvars.py`, `disabled-envs.py`, `selftest.sh`, `plan-fingerprint.py`, `destroy-plan-check.py`, `destroy-orphans.py`, `unmanaged-resources.py`, `terratest-project-check.py` y otros auxiliares del pipeline |
| `tests/` | Terratest y prueba de extremo a extremo; las pruebas sin GCP corren en cada PR (`go vet` y `go test`), las demás se omiten y no se han ejecutado contra GCP |
| `docs/` | Contrato, ADR, pipeline, runbooks, diagramas, `pendientes-apply.md`, `cumplimiento-cis.md`, `estimacion-de-costos.md`, la guía del colaborador, el plan del rediseño a un proyecto, el plan de transferencia de conocimiento y el `backlog.md` |
| `../.github/workflows/` | `pr.yml`, `apply.yml`, `destroy.yml`, `drift.yml`, `terratest.yml` y el reutilizable `_terraform-root.yml` |

## Requisitos previos

### Herramientas

| Herramienta | Versión | Uso |
|---|---|---|
| Terraform | `>= 1.9` para aplicar; **`>= 1.11` para `terraform test`** (las pruebas usan `override_during = plan`, ADR [0021](docs/adr/0021-pruebas-con-terraform-1-11-y-codigo-con-1-9.md)). El equipo usa 1.16.5; `pr.yml` corre 1.9.8 sin pruebas (`check.sh --skip test`) y 1.16.5 con todo. Con una versión anterior a 1.11, `terraform init` a mano falla en las raíces cuyas pruebas usan `override_during` (todas las de `stages/` salvo `1-base`): agregar `-test-directory=.sin-pruebas` (un directorio que no existe) al `init`, o usar la versión del pipeline (recomendado: las raíces 1 a 3 guardan su estado con ella) | todas las raíces y módulos |
| TFLint | 0.65 (0.65.0 en CI) | `scripts/check.sh` |
| checkov | 3.4 (3.4.6 en CI) | `scripts/check.sh` |
| Conftest | 0.71.1 en CI | `scripts/policy-check.sh` y Conftest sobre el plan |
| terraform-docs | 0.25 (0.25.1) | `scripts/docs.sh` |
| Go | la que fije `tests/go.mod` | Terratest (`tests/`) |
| Google Cloud CLI (`gcloud`) | reciente | proyecto, etapa 0 y runbooks |
| GitHub CLI (`gh`) y `jq` | recientes | IDs del repositorio para WIF, variables de GitHub, runbooks |
| Python 3 | el del sistema | `scripts/selftest.sh` y los scripts `.py` del pipeline |
| bash | 3.2 o mayor (Git Bash en Windows) | scripts |

### Google Cloud

Ya no hace falta crear una organización. Lo que sí hace falta:

- **Un proyecto de GCP creado a mano** (consola o `gcloud`) y ligado a una cuenta de
  facturación **de pago** (`gcloud billing accounts list`). Entra a Terraform como
  `project_id`; ninguna raíz lo crea ni lo borra (ADR 0029 §1). Si el proyecto está dentro de
  una organización, `org_id` (y `access_policy_id`, si la organización tiene política de Access
  Context Manager) encienden lo opcional de `0-bootstrap`. Van en su `terraform.tfvars`, con
  `directory_customer_id`, `additional_allowed_locations` y `vpc_sc_restricted_services`, no en
  `GCP_TFVARS_JSON`.
- **Antes de `0-bootstrap`** ([runbook 01](docs/runbooks/01-arranque-etapa-0.md)): borrar la red
  `default`, que el proyecto trae con reglas abiertas (ADR 0029 §6), y revisar las cuotas del
  proyecto, que comparten los tres entornos (ADR 0029 §10).
- **La persona que corre `0-bootstrap`**, con credenciales de aplicación
  (`gcloud auth application-default login`) y estos roles (README de la etapa 0):
  `roles/owner` en el proyecto, `roles/iam.denyAdmin` (la política de denegación; `owner` no lo
  incluye) y `roles/billing.costsManager` en la cuenta de facturación (presupuesto). Con
  `org_id`, además `roles/orgpolicy.policyAdmin` en la organización (crea las políticas de
  organización del proyecto); con `access_policy_id`, `roles/accesscontextmanager.policyAdmin`
  (crea el perímetro).
- **Opcional:** grupos de solo lectura para personas (`groups` de `1-base`: `readers`,
  `security_admins` y `auditors`; solo grupos, nunca `user:`), y Security Command Center
  activado a mano en el proyecto antes de `enable_scc_notification = true` (el proveedor 6.x no
  tiene recurso para activarlo; que funcione sin organización es HYPOTHESIS, ADR 0029 §7).
- **El repositorio de GitHub** (`<dueño>/<repositorio>`) y sus IDs numéricos, de los que WIF se
  fía (`gh api repos/<dueño>/<repositorio> --jq '.id, .owner.id'`), con las variables, los
  entornos `common`, `dev`, `qa` y `prod` y la protección de rama de
  [`docs/pipeline.md`](docs/pipeline.md) §2 y §4.

## Despliegue (0 → 3)

Orden fijo (ADR [0011](docs/adr/0011-construccion-en-paralelo-y-despliegue-en-orden.md) y
ADR 0029 §2):

```
0-bootstrap (a mano) → 1-base → 2-networks (hub)
  → 2-networks/envs/dev  → 3-workloads/envs/dev → prueba de humo de dev
  → 2-networks/envs/qa   → 3-workloads/envs/qa
  → 2-networks/envs/prod → 3-workloads/envs/prod
```

La etapa 0 la corre una persona una sola vez. Las etapas 1 a 3 las aplica `apply.yml` al
integrar en `main` con `GCP_ENABLED = true`: cada raíz se planea con la cuenta de lectura
`tf-read` y se aplica con su propia cuenta por WIF, en su entorno de GitHub. Los comandos de
abajo son los que corre `_terraform-root.yml`; sirven para una ejecución manual solo con una
identidad que tenga los permisos de la cuenta de esa raíz (las personas tienen solo lectura).
Todas las rutas son relativas a `gcp-datacenter/`.

### Etapa 0: estado local y migración

Procedimiento completo, con verificaciones, en el
[runbook 01](docs/runbooks/01-arranque-etapa-0.md) y en el README de `stages/0-bootstrap`.

```bash
cd stages/0-bootstrap
cp terraform.tfvars.example terraform.tfvars          # project_id, billing_account, prefix, regiones,
                                                      # github_repository(_id, _owner_id), budget_amount,
                                                      # labels; org_id, access_policy_id y demás
                                                      # variables de organización solo con organización;
                                                      # onprem_dns_vm = true si se quiere la VM DNS
cp backend_override.tf.example backend_override.tf    # backend local, solo esta primera vez
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Migración al bucket. El nombre se toma ANTES de borrar el override: con el override borrado,
# `terraform output` falla ("Backend initialization required") hasta reinicializar.
STATE_BUCKET="$(terraform output -raw state_bucket)"
rm backend_override.tf
terraform init -migrate-state -backend-config="bucket=${STATE_BUCKET}"   # responder "yes"
terraform state list                                   # ahora se lee desde el bucket
rm terraform.tfstate terraform.tfstate.backup tfplan
```

Después, sus salidas pasan a GitHub ([`docs/pipeline.md`](docs/pipeline.md) §2 y §3):
`workload_identity_provider`, `stage_service_accounts`, `read_service_account` y
`state_bucket` como variables, y `project_id` en `GCP_TFVARS_JSON.common`. `GCP_TFVARS_JSON`
necesita además el valor real de cada variable cuyo ejemplo trae un marcador (`example.com`,
`example-…`): `scripts/root-tfvars.py` hace fallar el plan de la raíz si alguno llega al plan
(lista por raíz en [`docs/pipeline.md`](docs/pipeline.md) §2).

### Etapas 1 a 3

Desde `gcp-datacenter/`, por cada raíz `R`, en el orden de arriba:

```bash
R=stages/1-base                                        # luego stages/2-networks, stages/2-networks/envs/dev, …
cp "$R/terraform.tfvars.example" "$R/terraform.tfvars" # valores reales: project_id y state_bucket de la etapa 0
terraform -chdir="$R" init -backend-config="bucket=<state_bucket>"
terraform -chdir="$R" plan -out=tfplan
terraform -chdir="$R" show -json tfplan > "$R/plan.json"
conftest test "$R/plan.json" --policy policies
terraform -chdir="$R" apply tfplan
rm "$R/tfplan" "$R/plan.json"
```

`terraform.tfvars`, `tfplan` y `plan.json` contienen valores reales o del estado: están en
`.gitignore` (`*.tfvars`, `tfplan`, `*.tfplan`, `plan.json`) y además los planes se borran
después del apply.

| Raíz `R` | Prefijo de estado | Cuenta del pipeline | Notas |
|---|---|---|---|
| `stages/1-base` | `1-base` | `<prefix>-tf-base` (`common`) | `project_id` tiene que ser el de 0-bootstrap (precondición). Lee solo `0-bootstrap`. Crea las cuentas de ejecución de `environments` × `applications` (y la `sched` de `off_hours_environments`). `gke_workload_identity_bindings = true` solo después del primer clúster de GKE (el pool de Workload Identity lo crea GKE). `dr_environments` (por defecto prod) decide qué entornos tienen llaves de DR. Activar SCC a mano antes de `enable_scc_notification = true`. `log_retention_locked = true` es irreversible. |
| `stages/2-networks` | `2-networks/hub` | `<prefix>-tf-net` (`common`) | Antes de cualquier spoke. `simulate_onprem = true` y `enable_vpn_dr = true` por defecto (ocho túneles en modo simulado: cuatro en el hub y cuatro en `onprem-sim`). No lee ningún estado. VM DNS de `onprem-sim` con `onprem_dns_vm = true` aquí y en `0-bootstrap` (antes `1-base` crea su cuenta). Con `simulate_onprem = false` el plan falla en el pipeline: limitación conocida (punto 151). |
| `stages/2-networks/envs/<env>` | `2-networks/<env>` | `<prefix>-tf-net-<env>` (`<env>`) | **Spokes de uno en uno** (dev, luego qa, luego prod), nunca en paralelo: cada spoke crea su peering sobre la VPC hub y GCP no admite dos operaciones de peering a la vez sobre una red. Lee `2-networks/hub`. |
| `stages/3-workloads/envs/<env>` | `3-workloads/<env>` | `<prefix>-tf-wl-<env>` (`<env>`) | Lee `1-base` y `2-networks/<env>`. Usa las cuentas de ejecución que crea `1-base` (`runtime_service_accounts`); no crea cuentas ni asigna roles de proyecto. Imágenes de Cloud Run y GKE en el repositorio del entorno (`artifact_registry_repositories` de `1-base`; Binary Authorization rechaza otras). Con GKE detrás del balanceador: primer apply sin `gke_lb_negs`, desplegar la carga, segundo apply con los NEG. El rango del plano de control sale de `reserved_cidrs` del spoke. Con `enable_dr`, el entorno tiene que estar en `dr_environments` de `1-base`. En dev y qa, `off_hours_shutdown` (ejemplos) apaga Cloud SQL, el MIG y los pools de GKE de 20:00 a 07:00 y el fin de semana: un apply o la prueba de humo de noche encuentran Cloud SQL detenida (README de la raíz). |

Pasos fuera de Terraform después de `3-workloads`: subir la imagen al repositorio del entorno
(antes de encender Cloud Run o GKE), registros DNS A de `domain_names` hacia la salida
`lb_ip_address` (el certificado administrado se activa entonces), registros de
`internal_lb_dns_authorization_records_by_region` en la zona pública del dominio interno, los
valores de los secretos, la cuenta de Kubernetes anotada para Workload Identity en el namespace
`<app>-<env>` (y, después del primer clúster, `gke_workload_identity_bindings = true` en
`1-base`), y `CREATE EXTENSION pgaudit;` en cada base de Cloud SQL (README de
`stages/3-workloads/envs/dev` y [runbook 02](docs/runbooks/02-alta-proyecto-aplicacion.md)).

## Revisiones sin GCP

```bash
cd gcp-datacenter

bash scripts/check.sh                 # fmt, validate, tflint, checkov y terraform test (Terraform >= 1.11)
bash scripts/check.sh --skip test     # lo mismo sin terraform test (lo que corre con Terraform 1.9)
bash scripts/check.sh --list          # objetivos: 24 módulos, 24 ejemplos y 9 raíces (57)
bash scripts/check.sh --skip checkov stages/3-workloads/envs/prod
bash scripts/policy-check.sh          # conftest verify y los 42 planes de ejemplo (21 pasan, 21 se rechazan)
bash scripts/selftest.sh              # autopruebas de los scripts del pipeline
bash scripts/docs.sh --check          # READMEs de terraform-docs al día (24 módulos y 9 raíces)
bash scripts/docs.sh                  # regenerarlos
```

Los números de los comentarios salen de correr estos comandos el 24 nov 2026 desde
`gcp-datacenter/`, con Terraform 1.16.5 y `PATH="$HOME/go/bin:$PATH"` (Conftest instalado con
Go):

- `bash scripts/check.sh --list | wc -l` → 57: 24 `modules/<m>`, 24 `.../examples/basic` y 9
  `stages/...` (contados con `grep -c`).
- `ls -d modules/*/ | wc -l` → 24 módulos.
- `bash scripts/policy-check.sh` → "134 tests, 134 passed, 0 warnings, 0 failures" y
  "RESULTADO: 42 planes con el resultado esperado." (21 con resultado `pasa` y 21 con
  `rechaza`; 18 de los 42 son recortes de planes reales sin GCP,
  `ls policies/fixtures | grep -c _real_` → 18).
- `bash scripts/selftest.sh` → 218 líneas `OK` (`grep -c '^OK'`), 0 `FALLA` y "RESULTADO: todas
  las comprobaciones pasaron." (si no encuentra Conftest, una línea sale como `INFO`).
- `bash scripts/docs.sh --check` → "Resultado: PASS (33)".
- `ls modules/*/tests/*.tftest.hcl | wc -l` → 24.
- `grep -rh '^run "' --include=*.tftest.hcl . | wc -l` → 493 bloques `run` de `terraform test`
  (263 en `modules/` y 230 en `stages/`, con el mismo comando sobre `modules` y sobre `stages`).
- En `tests/`, `go vet ./...` sale con 0 y `go test -count=1 -json ./...` (lo que corre el
  trabajo `go` de `pr.yml`, sin GCP) sale con 0: 47 eventos `pass`, 26 `skip` y 0 `fail`,
  contando pruebas y subpruebas (`"Action"` de cada línea con `"Test"`). Las 26 omitidas lo dicen
  en su salida: piden variables de GCP (`TERRATEST_PROJECT_ID`, `TERRATEST_ORG_ID`,
  `TEST_NOTIFICATION_EMAIL`, las de extremo a extremo) o una bandera para correr pruebas lentas,
  caras o de humo (`TEST_ALLOW_EXPENSIVE=true`, `TEST_SMOKE=true`).

`bash scripts/check.sh` completo (con `terraform test`, Terraform 1.16.5) lo reporta en cada PR
la pata `estático (terraform 1.16.5)`.

- `check.sh` lee el comando de checkov de `CHECKOV_CMD` (por defecto `checkov`). En Windows el
  lanzador `checkov.cmd` busca el Python del sistema y falla; con uv:
  `export CHECKOV_CMD="uvx --from checkov python -m checkov.main"`.
- `policy-check.sh` busca Conftest en `CONFTEST_CMD`, luego en el `PATH` y luego en
  `$HOME/go/bin`.
- Los proveedores se descargan una vez a `TF_PLUGIN_CACHE_DIR` (por defecto
  `$HOME/.terraform.d/plugin-cache`). No corras dos `check.sh` a la vez con la misma caché.
- Cada ejemplo (`modules/<modulo>/examples/basic/`) se revisa como raíz independiente, así que
  declara su propio bloque `terraform` con `required_version` y `required_providers`.

## Integración continua

`.github/workflows/pr.yml` (en la raíz del repositorio) corre en cada pull request, también
con solo documentación, `scripts/check.sh` con Terraform 1.9.8 (sin `terraform test`) y con
1.16.5 (con todo), `scripts/policy-check.sh`, `scripts/selftest.sh`, `scripts/docs.sh --check`
y el trabajo `go (vet y pruebas sin GCP)`, que es una comprobación obligatoria nueva: la
persona la agrega a la protección de `main`. El plan por raíz afectada (con la cuenta de
lectura `tf-read` y `-lock=false`), Conftest sobre ese plan y el costo con Infracost solo corren
con la variable de repositorio `GCP_ENABLED = true`; un cambio solo en `.md` o en `docs/` no
afecta ninguna raíz. El trabajo `plan-gate` resume esos planes con un nombre fijo para poder
exigirlo en la protección de `main`. `scripts/root-tfvars.py` hace fallar el plan de una raíz si
le falta `project_id` o si un valor de ejemplo (`example.com`, `example-…`) llegaría al plan.

`apply.yml` (al integrar en `main`, salvo que el cambio sea solo de `gcp-datacenter/docs/` o de
archivos `.md` de `gcp-datacenter/`) recorre 1-base → hub → spoke dev → cargas dev → prueba de humo de dev → spoke y
cargas de qa → spoke y cargas de prod. Por raíz separa un trabajo `plan` sin entorno, con
`tf-read`, y un trabajo `apply` en el entorno de GitHub de la raíz, con la cuenta de esa raíz,
que vuelve a planear con el candado y solo aplica si la huella del plan coincide con la
revisada; `common` y `prod` piden aprobación
(ADR [0025](docs/adr/0025-plan-aprobacion-y-apply-separados.md) y ADR 0029 §3). WIF solo da una
cuenta que escribe a un trabajo de `main`, de un flujo reutilizable de `.github/workflows/` de
este repositorio y con entorno de GitHub (`attribute.deploy` de `stages/0-bootstrap/wif.tf`);
cualquier otro trabajo, como el plan de un PR, solo obtiene `tf-read` (pendientes 123 y 124,
`VERIFICAR-EN-APPLY`). La variable de
repositorio `GCP_DISABLED_ENVS` (solo `dev` y `qa`; prod nunca se apaga) deja apagado un
entorno destruido: sus raíces no se planean ni se aplican y `drift.yml` no las revisa.
`drift.yml` (diario: drift por raíz con `tf-read` y recursos no administrados del proyecto con
Cloud Asset Inventory) y `terratest.yml` (nocturno, manual o por etiqueta de módulo; en un
proyecto de pruebas que no puede ser el de la landing zone) completan el pipeline.
`destroy.yml` (solo manual desde `main`, solo dev o qa, con el nombre del entorno escrito como
confirmación) destruye siempre
`3-workloads/envs/<env>` y el spoke solo con `incluir_red = true`, con el mismo plan, huella y
entorno de GitHub que `apply.yml`, y termina buscando huérfanos del entorno en el proyecto con
Cloud Asset Inventory ([`docs/pipeline.md`](docs/pipeline.md) §1.5). Las acciones van fijadas
por SHA.

**Nada de esto bloquea un merge ni un apply por sí solo:** la protección de `main` con sus
comprobaciones obligatorias (incluida `plan-gate`), los revisores de los entornos y la regla
"Deployment branches: `main`" se configuran a mano en GitHub y dependen del plan de GitHub del
equipo. La lista de lo que hay que configurar está en [`docs/pipeline.md`](docs/pipeline.md)
§2 a §4 (pendiente 12). Los módulos se consumen por ruta relativa: no hay versiones publicadas.

## Criterios de aceptación

Estado al 24 nov 2026, con el diseño de un solo proyecto (ADR 0029). "Demostrado sin GCP" dice
con qué comando; lo demás espera al primer apply. Los números de pendientes remiten a
[`docs/pendientes-apply.md`](docs/pendientes-apply.md).

| Criterio de la especificación | Cómo lo aborda el repositorio | Estado |
|---|---|---|
| Despliegue limpio de las etapas 0 a 3 | Orden fijo; interfaces de la tabla del ADR 0029; `remote_state.tf` con postcondiciones; `apply.yml` encadenado con una cuenta por raíz y entorno | **Pendiente del primer apply.** Sin GCP solo se demuestra que cada raíz valida y planea con proveedores simulados (`bash scripts/check.sh`, 9 raíces en `--list`) |
| Segundo `plan` sin cambios | `ignore_changes` donde hay altas externas (perímetro opcional, pool por defecto de GKE) y donde cambia el apagado fuera de horario de dev y qa (ADR 0028); `drift.yml` diario con `-detailed-exitcode`; huella del plan con `tf-read` igual a la del apply con la cuenta de la raíz (`VERIFICAR-EN-APPLY` en `_terraform-root.yml`) | **Pendiente del primer apply** (pendientes 11, 48 y 80) |
| `destroy` de dev sin huérfanos | `destroy.yml` (dev o qa): siempre `3-workloads/envs/<env>` y el spoke solo con `incluir_red`, con plan guardado y huella; `scripts/destroy-plan-check.py` detiene una raíz con `deletion_protection` o `deletion_policy` que impidan borrar, con recursos únicos del proyecto o con nombres que no empiecen con `<prefix>-<env>-`; `scripts/destroy-orphans.py` falla si Cloud Asset Inventory muestra en el proyecto algo del entorno (etiqueta `env`, prefijo o restos de GKE con el namespace o la red del entorno) que no conserve `1-base` ni administre un estado. Queda a propósito lo del entorno que vive en `1-base`: llaves, repositorios y contenedores de secretos (ADR 0029 §8) y las cuentas de ejecución (`stages/1-base/runtime_accounts.tf`). Después, `GCP_DISABLED_ENVS` evita que el siguiente `apply.yml` lo vuelva a crear | **Construido y probado sin GCP** (`bash scripts/selftest.sh`, 24 nov 2026 → 218 OK, 0 FALLA: guardias, planes reales de destrucción del spoke y de las cargas de dev, de 40 y 90 recursos, y huérfanos y restos de GKE con datos de ejemplo); **pendiente** correrlo contra dev (pendientes 11 y 85; la bóveda con retención forzada, la conexión de PSA y el bucket con objetos pueden bloquearlo: 86, 87 y 89; restos de GKE en Cloud Asset: 140) |
| El pipeline bloquea un PR que viola una política | Doce reglas Rego (más `lib.rego`); `pr.yml` corre `policy-check.sh` siempre y Conftest sobre el plan real con `GCP_ENABLED`; `plan-gate` falla si falla un plan | **Demostrado sin GCP para las reglas:** `PATH="$HOME/go/bin:$PATH" bash scripts/policy-check.sh` (24 nov 2026) → `134 tests, 134 passed, 0 warnings, 0 failures` y 42 planes de ejemplo con el resultado esperado (21 pasan y 21 se rechazan); 18 están recortados de planes reales sin GCP (`ls policies/fixtures \| grep -c _real_` → 18). Que un PR real quede bloqueado depende de configurar en GitHub la protección de `main` con `plan-gate` y las demás comprobaciones como obligatorias, del plan de GitHub (pendiente 12) y de la primera corrida de `pr.yml` (pendiente 51) |
| Una VM de prod alcanza on-premises y resuelve su DNS | Dos HA VPN con BGP, anuncios del hub, peering con exportación de rutas, zona de reenvío en el hub y de peering DNS en el spoke; en modo simulado, política de firewall de `onprem-sim`, delegación del rango de DNS y la VM DNS de prueba de `onprem-sim` como código (`stages/2-networks/onprem_dns.tf`, opcional con `onprem_dns_vm = true` en `0-bootstrap` y en el hub; su cuenta la crea `1-base`) | **Pendiente del primer apply** (pendientes 6, 7, 36 y 37; la VM DNS: 128, 129 y 130; y que la VPN y el DNS entrante funcionen con la política de red del hub, `VERIFICAR-EN-APPLY` en `stages/2-networks/firewall.tf`). Con la VPN real (`simulate_onprem = false`) el plan del hub falla en el pipeline: limitación conocida (punto 151) |
| Sin hallazgos críticos ni altos en Security Command Center | checkov en cada PR; políticas de organización solo con organización; notificación opcional de hallazgos altos y críticos a Pub/Sub; mapa del CIS v5.0 ([`docs/cumplimiento-cis.md`](docs/cumplimiento-cis.md)) con las desviaciones aceptadas del ADR 0027 | **Pendiente del primer apply** y de activar SCC en el proyecto (pendiente 2; HYPOTHESIS que funcione sin organización, ADR 0029 §7); procedimiento de evaluación en el pendiente 56. checkov sin GCP no equivale a SCC |
| Simulacro de DR dentro del RTO | Réplica de Cloud SQL, bucket de doble región, `dr_active`; estado multirregional, VPN de DR y balanceador interno por región (ADR 0022); [runbook 04](docs/runbooks/04-conmutacion-a-dr.md) con tabla de tiempos | **Pendiente del primer apply.** RTO ≤ 4 h y RPO ≤ 15 min son objetivos sin medir |
| Cero recursos creados a mano | Trabajo de recursos no administrados en `drift.yml`: Cloud Asset Inventory con alcance del proyecto frente a los estados de todas las raíces (`scripts/unmanaged-resources.py`), con la lista cerrada de lo que crea Google de `scripts/unmanaged-allowlist.txt`. Sigue siendo a mano, a propósito: el proyecto (el script no lo reporta), el borrado de la red `default` (si sigue, se reporta), la activación de SCC, los valores de los secretos, las imágenes publicadas (permitidas, nunca un repositorio), los atestadores de Binary Authorization si se usan (`stages/1-base/artifacts.tf`), el secreto de la VPN real y su `secretAccessor` para `tf-net` (`stages/2-networks/vpn.tf`), y fuera de GCP la configuración de GitHub y `pgaudit`. Los atestadores y el secreto de la VPN real, si viven en el proyecto, saldrían como no administrados: la lista no tiene regla para ellos (HYPOTHESIS) | **Construido y probado con datos de ejemplo** (`bash scripts/selftest.sh`, 24 nov 2026 → 218 OK, 0 FALLA); **pendiente** correrlo contra el proyecto real (pendiente 49; que Cloud Asset liste el proyecto mismo con `--scope=projects/<ID>` y los formatos de nombre de la lista son `VERIFICAR-EN-APPLY` en `drift.yml` y en la lista; nombre de `DockerImage`: 142) |
| Cada módulo tiene README, ejemplo y prueba | Estructura de §4.5 del contrato | **Demostrado sin GCP:** los 24 módulos tienen `README.md`, `examples/basic/main.tf` y `tests/*.tftest.hcl` (`ls modules/*/README.md`, `ls modules/*/examples/basic/main.tf` y `ls modules/*/tests/*.tftest.hcl`, cada uno con `\| wc -l` → 24, 24 nov 2026); `bash scripts/docs.sh --check` → `PASS (33)` (24 nov 2026). Las pruebas exigen Terraform 1.11 o mayor |

En un solo proyecto el aislamiento entre entornos es más débil que con proyectos separados:
lo que queda como riesgo aceptado está en el ADR 0029 §9 y en
[`docs/pendientes-apply.md`](docs/pendientes-apply.md) §5.
