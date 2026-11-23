# gcp-datacenter

Landing zone de Google Cloud escrita en Terraform: jerarquía de organización y gobierno,
seguridad (KMS, Secret Manager, VPC Service Controls), red hub y spoke con conectividad
híbrida, un proyecto de servicio por aplicación y las cargas de cada entorno (`dev`, `qa`,
`prod`), con políticas de Conftest y flujos de GitHub Actions.

**Estado:** todo se construyó y se probó **sin acceso a GCP**. Nada se ha aplicado todavía. Lo
que este documento dice del comportamiento en GCP es diseño, no resultado; lo que solo se
comprueba con un apply está en [`docs/pendientes-apply.md`](docs/pendientes-apply.md).

La fuente única de diseño es [`docs/CONTRATO.md`](docs/CONTRATO.md); las decisiones están en
[`docs/adr/`](docs/adr/README.md), el pipeline en [`docs/pipeline.md`](docs/pipeline.md) y los
procedimientos de operación en [`docs/runbooks/`](docs/runbooks/).

## Arquitectura en breve

- Organización con carpetas `bootstrap`, `common`, `dev`, `qa` y `prod`, nueve políticas de
  organización e IAM solo por grupos y de solo lectura para personas; solo el pipeline despliega
  ([diagrama 1](docs/diagramas/01-organizacion-gobierno-acceso.md)).
- Proyecto semilla con el bucket de estado en la multirregión `US`, cifrado con una llave propia
  de la etapa 0 ([ADR 0008](docs/adr/0008-llave-kms-propia-de-la-etapa-0.md),
  [0022](docs/adr/0022-estado-y-conmutacion-sin-depender-de-la-region-primaria.md)), un prefijo
  por etapa con IAM condicionado ([0010](docs/adr/0010-bucket-de-estado-unico-con-iam-por-prefijo.md)),
  Workload Identity Federation para GitHub por ID numérico del repositorio y una política de
  denegación de IAM que protege la carpeta `bootstrap` ([0007](docs/adr/0007-ci-cd-con-github-actions.md),
  [0023](docs/adr/0023-endurecimiento-de-la-identidad-del-pipeline.md)).
- Hub `<prefix>-common-net-hub` con dos HA VPN de dos túneles y BGP (una por región; la de DR
  menos preferida), reenvío de DNS y política de firewall jerárquica; on-premises simulado con
  la VPC `onprem-sim` mientras no haya sitio real
  ([0006](docs/adr/0006-on-premises-simulado-con-ha-vpn-entre-vpc.md),
  [diagrama 2](docs/diagramas/02-red-y-conectividad.md)).
- Una VPC por entorno (host de Shared VPC) unida al hub por peering, sin peering entre spokes
  ([0003](docs/adr/0003-vpc-por-entorno-unida-al-hub-por-peering.md)); Cloud NAT en cada spoke
  y región ([0004](docs/adr/0004-cloud-nat-en-cada-spoke.md)).
- Balanceador HTTPS global con Cloud Armor en el proyecto de servicio de cada entorno y
  balanceador interno uno por región con acceso global
  ([0005](docs/adr/0005-balanceador-y-cloud-armor-en-el-proyecto-de-servicio.md)); GKE, MIG y
  Cloud Run con interruptores ([0012](docs/adr/0012-gke-mig-y-cloud-run.md),
  [diagrama 3](docs/diagramas/03-aplicacion-y-proteccion-de-datos.md)); imágenes en un
  repositorio multirregional de Artifact Registry por aplicación, con Binary Authorization
  ([0024](docs/adr/0024-artifact-registry-y-binary-authorization-por-proyecto.md)).
- Datos solo por IP privada: Cloud SQL, Memorystore y Filestore por Private Service Access;
  Cloud Storage y demás APIs (incluidos `gcr.io`, `pkg.dev` y `run.app`) por Private Google
  Access y el VIP restringido ([0026](docs/adr/0026-api-de-google-por-el-vip-restringido-en-todos-los-entornos.md)).
  CMEK en todo; las llaves de las cargas viven en el proyecto `security` y rotan cada 90 días.
- Perímetro de VPC-SC de prod creado en la etapa 2 y ampliado en la 4, en dry-run por defecto
  ([0009](docs/adr/0009-perimetro-vpc-sc-en-dos-etapas-y-dry-run.md)).
- DR de prod en `us-east4`: réplica de Cloud SQL, bucket de doble región con turbo replication,
  Backup and DR y Backup for GKE; conmutación con `dr_active`, sin depender de la región primaria
  para el estado, la VPN ni el balanceador interno
  ([0002](docs/adr/0002-regiones-primaria-y-de-dr.md),
  [diagrama 4](docs/diagramas/04-operacion-continuidad-automatizacion.md)).

## Mapa del repositorio

| Ruta | Contenido |
|---|---|
| `modules/` | 24 módulos propios, cada uno con `README.md`, `examples/basic/` y `tests/` (contrato §8) |
| `stages/0-bootstrap` | Carpeta y proyecto semilla, llave y bucket de estado (multirregión), cuentas de etapa, roles personalizados, política de denegación, WIF |
| `stages/1-org` | Carpetas, proyectos de `common`, políticas, sink de auditoría, SCC, presupuesto, IAM de grupos y de las cuentas de etapa en `common` y las carpetas |
| `stages/2-security` | Llaves KMS (incluida `artifacts`), contenedores de secretos y perímetro de VPC-SC |
| `stages/3-networks` | Raíz del hub (ADR 0014): VPN primaria y de DR, DNS, política jerárquica, `onprem-sim` |
| `stages/3-networks/envs/{dev,qa,prod}` | Un spoke por entorno, con las zonas de las APIs de Google hacia el VIP |
| `stages/4-projects/envs/{dev,qa,prod}` | Proyectos de servicio, cuentas de ejecución, Artifact Registry y Binary Authorization, permisos (incluidos los de la etapa 5), alta en el perímetro |
| `stages/5-workloads/envs/{dev,qa,prod}` | Cómputo, Workload Identity, datos, balanceadores, observabilidad y respaldo |
| `policies/` | Siete políticas de Conftest (Rego), sus pruebas y 27 planes de ejemplo en `fixtures/` |
| `scripts/` | `check.sh`, `policy-check.sh`, `docs.sh`, `affected-roots.sh`, `selftest.sh`, `plan-fingerprint.py`, `unmanaged-resources.py` y otros auxiliares del pipeline |
| `tests/` | Terratest y prueba de extremo a extremo (paquete 13: compilan y sus fixtures validan, sin ejecutar contra GCP) |
| `docs/` | Contrato, ADR, pipeline, runbooks, diagramas y `pendientes-apply.md` |
| `../.github/workflows/` | `pr.yml`, `apply.yml`, `drift.yml`, `terratest.yml` y el reutilizable `_terraform-root.yml` |

## Requisitos previos

### Herramientas

| Herramienta | Versión | Uso |
|---|---|---|
| Terraform | `>= 1.9` para aplicar; **`>= 1.11` para `terraform test`** (las pruebas usan `override_during = plan`, ADR [0021](docs/adr/0021-pruebas-con-terraform-1-11-y-codigo-con-1-9.md)). El equipo usa 1.16.5; `pr.yml` corre 1.9.8 sin pruebas (`check.sh --skip test`) y 1.16.5 con todo | todas las raíces y módulos |
| TFLint | 0.65 (0.65.0 en CI) | `scripts/check.sh` |
| checkov | 3.4 (3.4.6 en CI) | `scripts/check.sh` |
| Conftest | 0.71.1 en CI | `scripts/policy-check.sh` y Conftest sobre el plan |
| terraform-docs | 0.25 (0.25.1) | `scripts/docs.sh` |
| Go | la que fije `tests/go.mod` | Terratest (`tests/`) |
| Google Cloud CLI (`gcloud`) | reciente | etapa 0 y runbooks |
| GitHub CLI (`gh`) y `jq` | recientes | IDs del repositorio para WIF, variables de GitHub, runbooks |
| Python 3 | el del sistema | `scripts/selftest.sh` y los scripts `.py` del pipeline |
| bash | 3.2 o mayor (Git Bash en Windows) | scripts |

### Google Cloud

- Una organización de GCP con Cloud Identity o Google Workspace, y su `directory_customer_id`
  (`gcloud organizations describe <org_id> --format="value(owner.directoryCustomerId)"`).
- Una cuenta de facturación activa (`gcloud billing accounts list`).
- Los siete grupos de Cloud Identity de la variable `groups` de la etapa 1: `org_admins`,
  `billing_admins`, `security_admins`, `network_admins`, `platform_devops`, `developers` y
  `auditors`.
- La persona administradora que corre la etapa 0, con credenciales de aplicación
  (`gcloud auth application-default login`) y estos roles (README de la etapa 0):
  - en la organización: `roles/resourcemanager.organizationAdmin`,
    `roles/resourcemanager.folderCreator`, `roles/resourcemanager.projectCreator`,
    `roles/iam.organizationRoleAdmin` y `roles/iam.denyAdmin` (política de denegación de la
    carpeta `bootstrap`);
  - en la cuenta de facturación: `roles/billing.admin`.
- Security Command Center activado a mano en la organización (el proveedor 6.x no tiene recurso
  para activarlo): paso del [runbook 01](docs/runbooks/01-arranque-etapa-0.md).
- El repositorio de GitHub (`<dueño>/<repositorio>`) y sus IDs numéricos, de los que WIF se
  fía (`gh api repos/<dueño>/<repositorio> --jq '.id, .owner.id'`), con las variables, entornos
  y protección de rama de [`docs/pipeline.md`](docs/pipeline.md) §2 y §4.

## Despliegue (0 → 5)

Orden fijo (ADR [0011](docs/adr/0011-construccion-en-paralelo-y-despliegue-en-orden.md)):

```
0-bootstrap → 1-org → 2-security → 3-networks (hub)
  → 3-networks/envs/dev  → 4-projects/envs/dev  → 5-workloads/envs/dev
  → 3-networks/envs/qa   → 4-projects/envs/qa   → 5-workloads/envs/qa
  → 3-networks/envs/prod → 4-projects/envs/prod → 5-workloads/envs/prod
```

La etapa 0 la corre una persona administradora una sola vez. Las etapas 1 a 5 las aplica
`apply.yml` al integrar en `main` con `GCP_ENABLED = true`, con la cuenta de servicio de cada
etapa por WIF. Los comandos de abajo son los que corre `_terraform-root.yml`; sirven para una
ejecución manual solo con una identidad que tenga los permisos de la cuenta de esa etapa (las
personas tienen solo lectura). Todas las rutas son relativas a `gcp-datacenter/`.

### Etapa 0: estado local y migración

Procedimiento completo, con verificaciones, en el
[runbook 01](docs/runbooks/01-arranque-etapa-0.md).

```bash
cd stages/0-bootstrap
cp terraform.tfvars.example terraform.tfvars          # org_id, billing_account, prefix, github_repository_id,
                                                      # github_repository_owner_id, state_bucket_location, labels
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

### Etapas 1 a 5

Desde `gcp-datacenter/`, por cada raíz `R`:

```bash
R=stages/1-org                                         # luego stages/2-security, stages/3-networks, …
cp "$R/terraform.tfvars.example" "$R/terraform.tfvars" # valores reales; state_bucket = salida de la etapa 0
terraform -chdir="$R" init -backend-config="bucket=<state_bucket>"
terraform -chdir="$R" plan -out=tfplan
terraform -chdir="$R" show -json tfplan > "$R/plan.json"
conftest test "$R/plan.json" --policy policies
terraform -chdir="$R" apply tfplan
rm "$R/tfplan" "$R/plan.json"
```

`tfplan` y `plan.json` contienen valores del estado: están en `.gitignore` (`tfplan`, `*.tfplan`,
`plan.json`) y además se borran después del apply.

| Raíz `R` | Prefijo de estado | Notas |
|---|---|---|
| `stages/1-org` | `1-org` | Activar SCC antes (runbook 01). `log_retention_locked = true` es irreversible. |
| `stages/2-security` | `2-security` | `vpc_sc_enforced = false` por defecto; `access_policy_id` si la organización ya tiene política de Access Context Manager. |
| `stages/3-networks` | `3-networks/hub` | Antes de cualquier spoke. `simulate_onprem = true` y `enable_vpn_dr = true` por defecto (ocho túneles en modo simulado: cuatro en el hub y cuatro en `onprem-sim`). |
| `stages/3-networks/envs/<env>` | `3-networks/<env>` | **Spokes de uno en uno** (dev, luego qa, luego prod), nunca en paralelo: cada spoke crea su peering sobre la VPC hub y GCP no admite dos operaciones de peering a la vez sobre una red. |
| `stages/4-projects/envs/<env>` | `4-projects/<env>` | `workloads_service_account` = `stage_service_accounts["5-workloads"]` de la etapa 0. |
| `stages/5-workloads/envs/<env>` | `5-workloads/<env>` | Imágenes de Cloud Run y GKE en el repositorio de `artifact_registry_repositories` de la etapa 4 (Binary Authorization rechaza otras). Con GKE detrás del balanceador: primer apply sin `gke_lb_negs`, desplegar la carga, segundo apply con los NEG. El rango del plano de control sale de `reserved_cidrs` de la etapa 3. |

Pasos fuera de Terraform después de la etapa 5: subir la imagen al repositorio de la aplicación
(antes de encender Cloud Run o GKE), registros DNS A de `domain_names` hacia la salida
`lb_ip_address` (el certificado administrado se activa entonces), registros de
`internal_lb_dns_authorization_records_by_region` en la zona pública del dominio interno, la
cuenta de Kubernetes anotada para Workload Identity, y `CREATE EXTENSION pgaudit;` en cada base
de Cloud SQL ([runbook 02](docs/runbooks/02-alta-proyecto-aplicacion.md)).

## Revisiones sin GCP

```bash
cd gcp-datacenter

bash scripts/check.sh                 # fmt, validate, tflint, checkov y terraform test (Terraform >= 1.11)
bash scripts/check.sh --skip test     # lo mismo sin terraform test (lo que corre con Terraform 1.9)
bash scripts/check.sh --list          # objetivos: 24 módulos, 24 ejemplos y 13 raíces (61)
bash scripts/check.sh --skip checkov stages/5-workloads/envs/prod
bash scripts/policy-check.sh          # conftest verify y los 27 planes de ejemplo (15 pasan, 12 se rechazan)
bash scripts/selftest.sh              # autopruebas de los scripts del pipeline
bash scripts/docs.sh --check          # READMEs de terraform-docs al día (24 módulos y 13 raíces)
bash scripts/docs.sh                  # regenerarlos
```

Los números de los comentarios salen de correr estos comandos el 23 nov 2026 desde
`gcp-datacenter/`, con `PATH="$HOME/go/bin:$PATH"` (Conftest instalado con Go):

- `bash scripts/check.sh --list` → 61 líneas: 24 `modules/<m>`, 24 `.../examples/basic` y 13
  `stages/...` (contadas con `grep -c`).
- `bash scripts/policy-check.sh` → "83 tests, 83 passed, 0 warnings, 0 failures" y
  "RESULTADO: 27 planes con el resultado esperado." (15 con resultado `pasa` y 12 con
  `rechaza`; 13 de los 27 son recortes de planes reales sin GCP, `ls policies/fixtures | grep -c _real_` → 13).
- `bash scripts/selftest.sh` → 58 líneas `OK`, 0 `FALLA` y "RESULTADO: todas las comprobaciones
  pasaron."
- `bash scripts/docs.sh --check` → "Resultado: PASS (37)".
- `ls modules/*/tests/*.tftest.hcl | wc -l` → 24.

`bash scripts/check.sh` completo (con `terraform test`) no se volvió a correr para este
documento; su resultado lo reporta cada PR en la pata `estático (terraform 1.16.5)`.

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
afectada, Conftest sobre ese plan y el costo con Infracost solo corren con la variable de
repositorio `GCP_ENABLED = true`; el trabajo `plan-gate` resume esos planes con un nombre fijo
para poder exigirlo en la protección de `main`.

`apply.yml` (etapas 1 → 5 al integrar en `main`) separa por raíz un trabajo `plan` sin entorno
y un trabajo `apply` en el entorno de GitHub, que vuelve a planear y solo aplica si la huella
del plan coincide con la revisada; `common` y `prod` piden aprobación, y después de dev corre
una prueba de humo antes de qa (ADR [0025](docs/adr/0025-plan-aprobacion-y-apply-separados.md)).
`drift.yml` (diario: drift por raíz y recursos no administrados con Cloud Asset Inventory) y
`terratest.yml` (nocturno, manual o por etiqueta de módulo) completan el pipeline. Las acciones
van fijadas por SHA.

**Nada de esto bloquea un merge ni un apply por sí solo:** la protección de `main` con sus
comprobaciones obligatorias (incluida `plan-gate`) y los revisores de los entornos se
configuran a mano en GitHub y dependen del plan de GitHub del equipo. La lista de lo que hay que
configurar está en [`docs/pipeline.md`](docs/pipeline.md) §2 a §4 (pendiente 12). Los módulos se
consumen por ruta relativa: no hay versiones publicadas.

## Criterios de aceptación

Estado al 21 nov 2026. "Demostrado sin GCP" dice con qué comando; lo demás espera al primer
apply. Los números de pendientes remiten a [`docs/pendientes-apply.md`](docs/pendientes-apply.md).

| Criterio de la especificación | Cómo lo aborda el repositorio | Estado |
|---|---|---|
| Despliegue limpio de las etapas 0 a 5 | Orden fijo; interfaces de §7 del contrato; `remote_state.tf` con postcondiciones; `apply.yml` encadenado | **Pendiente del primer apply.** Sin GCP solo se demuestra que cada raíz valida y planea con proveedores simulados (`bash scripts/check.sh`) |
| Segundo `plan` sin cambios | `ignore_changes` donde hay altas externas (perímetro, pool por defecto de GKE); `drift.yml` diario con `-detailed-exitcode` | **Pendiente del primer apply** (pendiente 11) |
| `destroy` de dev sin huérfanos | `project_deletion_policy` / `deletion_policy = "DELETE"` y `deletion_protection = false` admitidos fuera de prod | **Pendiente del primer apply** (pendiente 11; la bóveda de respaldos con retención forzada puede bloquearlo) |
| El pipeline bloquea un PR que viola una política | Siete reglas Rego; `pr.yml` corre `policy-check.sh` siempre y Conftest sobre el plan real con `GCP_ENABLED`; `plan-gate` falla si falla un plan | **Demostrado sin GCP para las reglas:** `PATH="$HOME/go/bin:$PATH" bash scripts/policy-check.sh` (23 nov 2026) → 83 pruebas de Rego y 27 planes de ejemplo (13 recortados de planes reales sin GCP) con el resultado esperado. Que un PR real quede bloqueado depende de configurar en GitHub la protección de `main` con `plan-gate` y las demás comprobaciones como obligatorias, del plan de GitHub (pendiente 12) y de la primera corrida de `pr.yml` (pendiente 51) |
| Una VM de prod alcanza on-premises y resuelve su DNS | Dos HA VPN con BGP, anuncios del hub, peering con exportación de rutas, zona de reenvío en el hub y de peering DNS en el spoke; en modo simulado, firewall de `onprem-sim` y delegación del rango de DNS ya construidos | **Pendiente del primer apply** (pendientes 6, 7, 36 y 37). En modo simulado falta crear a mano la VM DNS en `onprem-sim` |
| Sin hallazgos críticos ni altos en Security Command Center | Políticas de organización, checkov en cada PR, notificación de hallazgos altos y críticos a Pub/Sub | **Pendiente del primer apply** y de activar SCC (pendiente 2). checkov sin GCP no equivale a SCC |
| Simulacro de DR dentro del RTO | Réplica de Cloud SQL, bucket de doble región, `dr_active`; estado multirregional, VPN de DR y balanceador interno por región (ADR 0022); [runbook 04](docs/runbooks/04-conmutacion-a-dr.md) con tabla de tiempos | **Pendiente del primer apply.** RTO ≤ 4 h y RPO ≤ 15 min son objetivos sin medir |
| Cero recursos creados a mano | Trabajo de recursos no administrados en `drift.yml` (Cloud Asset Inventory frente a los estados) | **Construido y probado con datos de ejemplo** (`bash scripts/selftest.sh`, 23 nov 2026 → 58 OK, 0 FALLA); **pendiente** correrlo contra una carpeta real (pendiente 49) |
| Cada módulo tiene README, ejemplo y prueba | Estructura de §4.5 del contrato | **Demostrado sin GCP:** los 24 módulos tienen `README.md`, `examples/basic/main.tf` y `tests/*.tftest.hcl` (`ls modules/*/tests/*.tftest.hcl \| wc -l` → 24, 23 nov 2026); `bash scripts/docs.sh --check` → `PASS (37)` (23 nov 2026). Las pruebas exigen Terraform 1.11 o mayor |
