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
  ya no separa (permisos de Compute, GKE, Cloud Run y Cloud SQL, agentes de servicio, cuotas)
  queda como riesgo aceptado en el mismo ADR.
- **La organización es opcional** (`org_id`, `null` por defecto). Con organización, `1-base`
  aplica políticas de organización al proyecto y, con `access_policy_id`, un perímetro de
  VPC-SC en dry-run que rodea todo el proyecto
  ([0009](docs/adr/0009-perimetro-vpc-sc-en-dos-etapas-y-dry-run.md)). Sin organización esos
  controles no existen: los cubren las reglas de Conftest de cada PR y pasos manuales del
  [runbook 01](docs/runbooks/01-arranque-etapa-0.md). Que no se puedan usar sin organización es
  HYPOTHESIS (ADR 0029 §1).
- **Estado e identidad** (`0-bootstrap`, a mano): bucket de estado en la multirregión `US`,
  cifrado con una llave propia ([0008](docs/adr/0008-llave-kms-propia-de-la-etapa-0.md),
  [0022](docs/adr/0022-estado-y-conmutacion-sin-depender-de-la-region-primaria.md)), con un
  prefijo por raíz e IAM condicionado
  ([0010](docs/adr/0010-bucket-de-estado-unico-con-iam-por-prefijo.md)); nueve cuentas del
  pipeline, una por raíz y entorno más `tf-read` de solo lectura; Workload Identity Federation
  para GitHub por ID numérico del repositorio, con cada cuenta que escribe ligada a un entorno
  de GitHub ([0007](docs/adr/0007-ci-cd-con-github-actions.md),
  [0023](docs/adr/0023-endurecimiento-de-la-identidad-del-pipeline.md)); y una política de
  denegación en el proyecto que protege el estado con la etiqueta `<prefix>-proteccion`
  (HYPOTHESIS que funcione sin organización, ADR 0029 §5). Las personas tienen IAM de solo
  lectura, por grupos; solo el pipeline despliega
  ([diagrama 1](docs/diagramas/01-organizacion-gobierno-acceso.md)).
- **Red:** cinco VPC en el proyecto. El hub `<prefix>-common-net-hub` con dos HA VPN de dos
  túneles y BGP (una por región; la de DR, menos preferida) y reenvío de DNS; on-premises
  simulado con la VPC `onprem-sim` mientras no haya sitio real
  ([0006](docs/adr/0006-on-premises-simulado-con-ha-vpn-entre-vpc.md)); y un spoke por entorno
  unido al hub por peering, sin peering entre spokes
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
  ([0024](docs/adr/0024-artifact-registry-y-binary-authorization-por-proyecto.md)). Las reglas
  por clúster no limitan los de prod al repositorio de prod: desviación explicada en el README
  de `stages/1-base`.
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
  una vez en el proyecto; cada entorno crea su propia cuenta del apagado.

## Mapa del repositorio

| Ruta | Contenido |
|---|---|
| `modules/` | 24 módulos propios, cada uno con `README.md`, `examples/basic/` y `tests/` (contrato §8) |
| `stages/0-bootstrap` | La aplica una persona, a mano. Todas las APIs del proyecto, llave y bucket de estado (multirregión), las nueve cuentas del pipeline con sus roles de proyecto, roles personalizados, WIF, etiqueta de protección y política de denegación, presupuesto del proyecto |
| `stages/1-base` | Lo que existe una vez por proyecto: configuración de auditoría, sink y bucket de logs, alertas de auditoría, contactos esenciales y SCC opcional; llaveros KMS y contenedores de secretos por entorno; repositorios de Artifact Registry y la política de Binary Authorization; IAM de personas; con organización, políticas de organización y VPC-SC opcional |
| `stages/2-networks` | Raíz del hub (ADR 0014): VPC hub, VPN primaria y de DR, DNS, políticas de firewall de red del hub y de `onprem-sim` |
| `stages/2-networks/envs/{dev,qa,prod}` | Un spoke por entorno: VPC, Cloud NAT, PSA, peering con el hub, política de firewall de red y zonas de las APIs de Google hacia el VIP |
| `stages/3-workloads/envs/{dev,qa,prod}` | Cuentas de ejecución y sus permisos, cómputo, Workload Identity, datos, balanceadores, observabilidad, respaldo y apagado fuera de horario |
| `policies/` | Siete políticas de Conftest (Rego), sus pruebas y 27 planes de ejemplo en `fixtures/` |
| `scripts/` | `check.sh`, `policy-check.sh`, `docs.sh`, `affected-roots.sh`, `root-tfvars.py`, `selftest.sh`, `plan-fingerprint.py`, `destroy-plan-check.py`, `destroy-orphans.py`, `unmanaged-resources.py` y otros auxiliares del pipeline |
| `tests/` | Terratest y prueba de extremo a extremo; compilan (`go vet` y `go test -run XXX`) y no se han ejecutado contra GCP |
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
  Context Manager) encienden lo opcional de `1-base`.
- **Antes de `0-bootstrap`** ([runbook 01](docs/runbooks/01-arranque-etapa-0.md)): borrar la red
  `default`, que el proyecto trae con reglas abiertas (ADR 0029 §6), y revisar las cuotas del
  proyecto, que comparten los tres entornos (ADR 0029 §10).
- **La persona que corre `0-bootstrap`**, con credenciales de aplicación
  (`gcloud auth application-default login`) y estos roles (README de la etapa 0):
  `roles/owner` en el proyecto, `roles/iam.denyAdmin` (la política de denegación; `owner` no lo
  incluye) y `roles/billing.costsManager` en la cuenta de facturación (presupuesto). Con
  `org_id`, además permiso para dar `roles/orgpolicy.policyAdmin` en la organización; con
  `access_policy_id`, `roles/accesscontextmanager.policyAdmin`.
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
                                                      # labels; org_id y access_policy_id solo con organización
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
`state_bucket` como variables, y `project_id` en `GCP_TFVARS_JSON.common`.

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
| `stages/1-base` | `1-base` | `<prefix>-tf-base` (`common`) | `project_id` tiene que ser el de 0-bootstrap (precondición). Activar SCC a mano antes de `enable_scc_notification = true`. `log_retention_locked = true` es irreversible. Con organización: `org_id`, `directory_customer_id` y `access_policy_id`. |
| `stages/2-networks` | `2-networks/hub` | `<prefix>-tf-net` (`common`) | Antes de cualquier spoke. `simulate_onprem = true` y `enable_vpn_dr = true` por defecto (ocho túneles en modo simulado: cuatro en el hub y cuatro en `onprem-sim`). No lee ningún estado. |
| `stages/2-networks/envs/<env>` | `2-networks/<env>` | `<prefix>-tf-net-<env>` (`<env>`) | **Spokes de uno en uno** (dev, luego qa, luego prod), nunca en paralelo: cada spoke crea su peering sobre la VPC hub y GCP no admite dos operaciones de peering a la vez sobre una red. Lee `2-networks/hub`. |
| `stages/3-workloads/envs/<env>` | `3-workloads/<env>` | `<prefix>-tf-wl-<env>` (`<env>`) | Lee `1-base` y `2-networks/<env>`. Imágenes de Cloud Run y GKE en el repositorio del entorno (`artifact_registry_repositories` de `1-base`; Binary Authorization rechaza otras). Con GKE detrás del balanceador: primer apply sin `gke_lb_negs`, desplegar la carga, segundo apply con los NEG. El rango del plano de control sale de `reserved_cidrs` del spoke. En dev y qa, `off_hours_shutdown` (ejemplos) apaga Cloud SQL, el MIG y los pools de GKE de 20:00 a 07:00 y el fin de semana: un apply o la prueba de humo de noche encuentran Cloud SQL detenida (README de la raíz). |

Pasos fuera de Terraform después de `3-workloads`: subir la imagen al repositorio del entorno
(antes de encender Cloud Run o GKE), registros DNS A de `domain_names` hacia la salida
`lb_ip_address` (el certificado administrado se activa entonces), registros de
`internal_lb_dns_authorization_records_by_region` en la zona pública del dominio interno, los
valores de los secretos, la cuenta de Kubernetes anotada para Workload Identity en el namespace
`<app>-<env>`, y `CREATE EXTENSION pgaudit;` en cada base de Cloud SQL (README de
`stages/3-workloads/envs/dev` y [runbook 02](docs/runbooks/02-alta-proyecto-aplicacion.md)).

## Revisiones sin GCP

```bash
cd gcp-datacenter

bash scripts/check.sh                 # fmt, validate, tflint, checkov y terraform test (Terraform >= 1.11)
bash scripts/check.sh --skip test     # lo mismo sin terraform test (lo que corre con Terraform 1.9)
bash scripts/check.sh --list          # objetivos: 24 módulos, 24 ejemplos y 9 raíces (57)
bash scripts/check.sh --skip checkov stages/3-workloads/envs/prod
bash scripts/policy-check.sh          # conftest verify y los 27 planes de ejemplo (15 pasan, 12 se rechazan)
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
- `bash scripts/policy-check.sh` → "83 tests, 83 passed, 0 warnings, 0 failures" y
  "RESULTADO: 27 planes con el resultado esperado." (15 con resultado `pasa` y 12 con
  `rechaza`; 13 de los 27 son recortes de planes reales sin GCP,
  `ls policies/fixtures | grep -c _real_` → 13).
- `bash scripts/selftest.sh` → 162 líneas `OK` (`grep -c '^OK'`), 0 `FALLA` y "RESULTADO: todas
  las comprobaciones pasaron." (si no encuentra Conftest, una línea sale como `INFO`).
- `bash scripts/docs.sh --check` → "Resultado: PASS (33)".
- `ls modules/*/tests/*.tftest.hcl | wc -l` → 24.
- `grep -rh '^run "' --include=*.tftest.hcl . | wc -l` → 480 bloques `run` de `terraform test`
  (262 en `modules/` y 218 en `stages/`, con el mismo comando sobre `modules` y sobre `stages`).

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

`.github/workflows/pr.yml` (en la raíz del repositorio) corre en cada pull request
`scripts/check.sh` con Terraform 1.9.8 (sin `terraform test`) y con 1.16.5 (con todo),
`scripts/policy-check.sh`, `scripts/selftest.sh` y `scripts/docs.sh --check`. El plan por raíz
afectada (con la cuenta de lectura `tf-read` y `-lock=false`), Conftest sobre ese plan y el
costo con Infracost solo corren con la variable de repositorio `GCP_ENABLED = true`; el trabajo
`plan-gate` resume esos planes con un nombre fijo para poder exigirlo en la protección de
`main`.

`apply.yml` (al integrar en `main`) recorre 1-base → hub → spoke dev → cargas dev → prueba de
humo de dev → spoke y cargas de qa → spoke y cargas de prod. Por raíz separa un trabajo `plan`
sin entorno, con `tf-read`, y un trabajo `apply` en el entorno de GitHub de la raíz, con la
cuenta de esa raíz, que vuelve a planear con el candado y solo aplica si la huella del plan
coincide con la revisada; `common` y `prod` piden aprobación
(ADR [0025](docs/adr/0025-plan-aprobacion-y-apply-separados.md) y ADR 0029 §3). `drift.yml`
(diario: drift por raíz con `tf-read` y recursos no administrados del proyecto con Cloud Asset
Inventory) y `terratest.yml` (nocturno, manual o por etiqueta de módulo; por defecto en un solo
proyecto de pruebas) completan el pipeline. `destroy.yml` (solo manual desde `main`, solo dev o
qa, con el nombre del entorno escrito como confirmación) destruye siempre
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
| `destroy` de dev sin huérfanos | `destroy.yml`: siempre `3-workloads/envs/dev` y el spoke solo con `incluir_red`, con plan guardado y huella; `scripts/destroy-plan-check.py` detiene una raíz con `deletion_protection` o `deletion_policy` que impidan borrar, con recursos únicos del proyecto o con nombres sin `<prefix>-dev-`; `scripts/destroy-orphans.py` falla si Cloud Asset Inventory muestra en el proyecto algo de dev (etiqueta `env` o prefijo) que no conserve `1-base` ni administre un estado. Quedan a propósito las llaves, los repositorios y los contenedores de secretos de `1-base` (ADR 0029 §8) | **Construido y probado sin GCP** (`bash scripts/selftest.sh`, 24 nov 2026 → 162 OK, 0 FALLA: guardias, planes reales de destrucción del spoke y de las cargas de dev, de 40 y 90 recursos, y huérfanos con datos de ejemplo); **pendiente** correrlo contra dev (pendientes 11 y 85; la bóveda con retención forzada, la conexión de PSA y el bucket con objetos pueden bloquearlo: 86, 87 y 89) |
| El pipeline bloquea un PR que viola una política | Siete reglas Rego; `pr.yml` corre `policy-check.sh` siempre y Conftest sobre el plan real con `GCP_ENABLED`; `plan-gate` falla si falla un plan | **Demostrado sin GCP para las reglas:** `PATH="$HOME/go/bin:$PATH" bash scripts/policy-check.sh` (24 nov 2026) → 83 pruebas de Rego y 27 planes de ejemplo (13 recortados de planes reales sin GCP) con el resultado esperado. Que un PR real quede bloqueado depende de configurar en GitHub la protección de `main` con `plan-gate` y las demás comprobaciones como obligatorias, del plan de GitHub (pendiente 12) y de la primera corrida de `pr.yml` (pendiente 51) |
| Una VM de prod alcanza on-premises y resuelve su DNS | Dos HA VPN con BGP, anuncios del hub, peering con exportación de rutas, zona de reenvío en el hub y de peering DNS en el spoke; en modo simulado, política de firewall de `onprem-sim` y delegación del rango de DNS ya construidas | **Pendiente del primer apply** (pendientes 6, 7, 36 y 37; y que la VPN y el DNS entrante funcionen con la política de red del hub, `VERIFICAR-EN-APPLY` en `stages/2-networks/firewall.tf`). En modo simulado falta crear a mano la VM DNS en `onprem-sim` |
| Sin hallazgos críticos ni altos en Security Command Center | checkov en cada PR; políticas de organización solo con organización; notificación opcional de hallazgos altos y críticos a Pub/Sub; mapa del CIS v5.0 ([`docs/cumplimiento-cis.md`](docs/cumplimiento-cis.md)) con las desviaciones aceptadas del ADR 0027 | **Pendiente del primer apply** y de activar SCC en el proyecto (pendiente 2; HYPOTHESIS que funcione sin organización, ADR 0029 §7); procedimiento de evaluación en el pendiente 56. checkov sin GCP no equivale a SCC |
| Simulacro de DR dentro del RTO | Réplica de Cloud SQL, bucket de doble región, `dr_active`; estado multirregional, VPN de DR y balanceador interno por región (ADR 0022); [runbook 04](docs/runbooks/04-conmutacion-a-dr.md) con tabla de tiempos | **Pendiente del primer apply.** RTO ≤ 4 h y RPO ≤ 15 min son objetivos sin medir |
| Cero recursos creados a mano | Trabajo de recursos no administrados en `drift.yml`: Cloud Asset Inventory con alcance del proyecto frente a los estados de todas las raíces (`scripts/unmanaged-resources.py`) | **Construido y probado con datos de ejemplo** (`bash scripts/selftest.sh`, 24 nov 2026 → 162 OK, 0 FALLA); **pendiente** correrlo contra el proyecto real (pendiente 49; que Cloud Asset liste el proyecto mismo con `--scope=projects/<ID>` es `VERIFICAR-EN-APPLY` en `drift.yml`) |
| Cada módulo tiene README, ejemplo y prueba | Estructura de §4.5 del contrato | **Demostrado sin GCP:** los 24 módulos tienen `README.md`, `examples/basic/main.tf` y `tests/*.tftest.hcl` (`ls modules/*/README.md`, `ls modules/*/examples/basic/main.tf` y `ls modules/*/tests/*.tftest.hcl`, cada uno con `\| wc -l` → 24, 24 nov 2026); `bash scripts/docs.sh --check` → `PASS (33)` (24 nov 2026). Las pruebas exigen Terraform 1.11 o mayor |

En un solo proyecto el aislamiento entre entornos es más débil que con proyectos separados:
lo que queda como riesgo aceptado está en el ADR 0029 §9 y en
[`docs/pendientes-apply.md`](docs/pendientes-apply.md) §5.
