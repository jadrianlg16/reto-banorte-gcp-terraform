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
- Proyecto semilla con el bucket de estado cifrado con una llave propia de la etapa 0
  ([ADR 0008](docs/adr/0008-llave-kms-propia-de-la-etapa-0.md)), un prefijo por etapa con IAM
  condicionado ([0010](docs/adr/0010-bucket-de-estado-unico-con-iam-por-prefijo.md)) y Workload
  Identity Federation para GitHub ([0007](docs/adr/0007-ci-cd-con-github-actions.md)).
- Hub `<prefix>-common-net-hub` con HA VPN de dos túneles y BGP, reenvío de DNS y política de
  firewall jerárquica; on-premises simulado con la VPC `onprem-sim` mientras no haya sitio real
  ([0006](docs/adr/0006-on-premises-simulado-con-ha-vpn-entre-vpc.md),
  [diagrama 2](docs/diagramas/02-red-y-conectividad.md)).
- Una VPC por entorno (host de Shared VPC) unida al hub por peering, sin peering entre spokes
  ([0003](docs/adr/0003-vpc-por-entorno-unida-al-hub-por-peering.md)); Cloud NAT en cada spoke
  y región ([0004](docs/adr/0004-cloud-nat-en-cada-spoke.md)).
- Balanceador HTTPS global con Cloud Armor en el proyecto de servicio de cada entorno
  ([0005](docs/adr/0005-balanceador-y-cloud-armor-en-el-proyecto-de-servicio.md)); GKE, MIG y
  Cloud Run con interruptores ([0012](docs/adr/0012-gke-mig-y-cloud-run.md),
  [diagrama 3](docs/diagramas/03-aplicacion-y-proteccion-de-datos.md)).
- Datos solo por IP privada: Cloud SQL, Memorystore y Filestore por Private Service Access;
  Cloud Storage por Private Google Access y el VIP restringido. CMEK en todo; las llaves de las
  cargas viven en el proyecto `security` y rotan cada 90 días.
- Perímetro de VPC-SC de prod creado en la etapa 2 y ampliado en la 4, en dry-run por defecto
  ([0009](docs/adr/0009-perimetro-vpc-sc-en-dos-etapas-y-dry-run.md)).
- DR de prod en `us-east4`: réplica de Cloud SQL, bucket de doble región con turbo replication,
  Backup and DR y Backup for GKE; conmutación con `dr_active`
  ([0002](docs/adr/0002-regiones-primaria-y-de-dr.md),
  [diagrama 4](docs/diagramas/04-operacion-continuidad-automatizacion.md)).

## Mapa del repositorio

| Ruta | Contenido |
|---|---|
| `modules/` | 24 módulos propios, cada uno con `README.md`, `examples/basic/` y `tests/` (contrato §8) |
| `stages/0-bootstrap` | Carpeta y proyecto semilla, llave y bucket de estado, cuentas de etapa, WIF |
| `stages/1-org` | Carpetas, proyectos de `common`, políticas, sink de auditoría, SCC, presupuesto, IAM |
| `stages/2-security` | Llaves KMS, contenedores de secretos y perímetro de VPC-SC |
| `stages/3-networks` | Raíz del hub (ADR 0014) |
| `stages/3-networks/envs/{dev,qa,prod}` | Un spoke por entorno |
| `stages/4-projects/envs/{dev,qa,prod}` | Proyectos de servicio, cuentas de ejecución, permisos, alta en el perímetro |
| `stages/5-workloads/envs/{dev,qa,prod}` | Cómputo, datos, balanceadores, observabilidad y respaldo |
| `policies/` | Siete políticas de Conftest (Rego), sus pruebas y planes de ejemplo en `fixtures/` |
| `scripts/` | `check.sh`, `policy-check.sh`, `docs.sh`, `affected-roots.sh` |
| `tests/` | Terratest y prueba de extremo a extremo (paquete 13: compilan y sus fixtures validan, sin ejecutar contra GCP) |
| `docs/` | Contrato, ADR, pipeline, runbooks, diagramas y `pendientes-apply.md` |
| `../.github/workflows/` | `pr.yml`, `apply.yml`, `drift.yml`, `terratest.yml` y el reutilizable `_terraform-root.yml` |

## Requisitos previos

### Herramientas

| Herramienta | Versión | Uso |
|---|---|---|
| Terraform | `>= 1.9` (el equipo usa 1.16.5; `pr.yml` prueba 1.9.8 y 1.16.5) | todas las raíces y módulos |
| TFLint | 0.65 (0.65.0 en CI) | `scripts/check.sh` |
| checkov | 3.4 (3.4.6 en CI) | `scripts/check.sh` |
| Conftest | 0.71.1 en CI | `scripts/policy-check.sh` y Conftest sobre el plan |
| terraform-docs | 0.25 (0.25.1) | `scripts/docs.sh` |
| Go | la que fije `tests/go.mod` | Terratest (`tests/`) |
| Google Cloud CLI (`gcloud`) | reciente | etapa 0 y runbooks |
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
    `roles/resourcemanager.folderCreator`, `roles/resourcemanager.projectCreator` y
    `roles/iam.organizationRoleAdmin`;
  - en la cuenta de facturación: `roles/billing.admin`.
- Security Command Center activado a mano en la organización (el proveedor 6.x no tiene recurso
  para activarlo): paso del [runbook 01](docs/runbooks/01-arranque-etapa-0.md).
- El repositorio de GitHub de `github_repository` (`<dueño>/<repositorio>`) con las variables y
  entornos de [`docs/pipeline.md`](docs/pipeline.md) §2.

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
cp terraform.tfvars.example terraform.tfvars          # org_id, billing_account, prefix, github_repository, labels
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
| `stages/3-networks` | `3-networks/hub` | Antes de cualquier spoke. `simulate_onprem = true` por defecto. |
| `stages/3-networks/envs/<env>` | `3-networks/<env>` | **Spokes de uno en uno** (dev, luego qa, luego prod), nunca en paralelo: cada spoke crea su peering sobre la VPC hub y GCP no admite dos operaciones de peering a la vez sobre una red. |
| `stages/4-projects/envs/<env>` | `4-projects/<env>` | `workloads_service_account` = `stage_service_accounts["5-workloads"]` de la etapa 0. |
| `stages/5-workloads/envs/<env>` | `5-workloads/<env>` | Con GKE detrás del balanceador: primer apply sin `gke_lb_negs`, desplegar la carga, segundo apply con los NEG. |

Pasos fuera de Terraform después de la etapa 5: registros DNS A de `domain_names` hacia la
salida `lb_ip_address` (el certificado administrado se activa entonces), registros de
`internal_lb_dns_authorization_records` en la zona pública del dominio interno, y
`CREATE EXTENSION pgaudit;` en cada base de Cloud SQL.

## Revisiones sin GCP

```bash
cd gcp-datacenter

bash scripts/check.sh                 # fmt, validate, tflint, checkov y terraform test
bash scripts/check.sh --list          # objetivos: 24 módulos, 24 ejemplos y 13 raíces (61)
bash scripts/check.sh --skip checkov stages/5-workloads/envs/prod
bash scripts/policy-check.sh          # conftest verify y los 14 planes de ejemplo (7 pasan, 7 se rechazan)
bash scripts/docs.sh --check          # READMEs de terraform-docs al día (24 módulos y 13 raíces)
bash scripts/docs.sh                  # regenerarlos
```

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
`scripts/check.sh`, `scripts/policy-check.sh` y `scripts/docs.sh --check`. El plan por raíz
afectada, Conftest sobre ese plan y el costo con Infracost solo corren con la variable de
repositorio `GCP_ENABLED = true`. `apply.yml` (etapas 1 → 5 al integrar en `main`; prod en el
entorno protegido `prod`), `drift.yml` (diario) y `terratest.yml` (nocturno) se describen en
[`docs/pipeline.md`](docs/pipeline.md), con las variables, entornos y ajustes manuales de GitHub.

## Criterios de aceptación

Estado al 21 nov 2026. "Demostrado sin GCP" dice con qué comando; lo demás espera al primer
apply. Los números de pendientes remiten a [`docs/pendientes-apply.md`](docs/pendientes-apply.md).

| Criterio de la especificación | Cómo lo aborda el repositorio | Estado |
|---|---|---|
| Despliegue limpio de las etapas 0 a 5 | Orden fijo; interfaces de §7 del contrato; `remote_state.tf` con postcondiciones; `apply.yml` encadenado | **Pendiente del primer apply.** Sin GCP solo se demuestra que cada raíz valida y planea con proveedores simulados (`bash scripts/check.sh`) |
| Segundo `plan` sin cambios | `ignore_changes` donde hay altas externas (perímetro, pool por defecto de GKE); `drift.yml` diario con `-detailed-exitcode` | **Pendiente del primer apply** (pendiente 11) |
| `destroy` de dev sin huérfanos | `project_deletion_policy` / `deletion_policy = "DELETE"` y `deletion_protection = false` admitidos fuera de prod | **Pendiente del primer apply** (pendiente 11; la bóveda de respaldos con retención forzada puede bloquearlo) |
| El pipeline bloquea un PR que viola una política | Siete reglas Rego; `pr.yml` corre `policy-check.sh` siempre y Conftest sobre el plan real con `GCP_ENABLED` | **Demostrado sin GCP para las reglas:** `bash scripts/policy-check.sh` → 55 pruebas de Rego y 14 planes de ejemplo con el resultado esperado. Que un PR real quede bloqueado depende de exigir esas comprobaciones en la protección de `main` (pendiente 12) y del plan real (pendiente) |
| Una VM de prod alcanza on-premises y resuelve su DNS | HA VPN con BGP, anuncios del hub, peering con exportación de rutas, zona de reenvío en el hub y de peering DNS en el spoke | **Pendiente del primer apply** (pendientes 6 y 7). En modo simulado no hay servidor DNS on-premises: la resolución no se puede probar sin agregar uno |
| Sin hallazgos críticos ni altos en Security Command Center | Políticas de organización, checkov en cada PR, notificación de hallazgos altos y críticos a Pub/Sub | **Pendiente del primer apply** y de activar SCC (pendiente 2). checkov sin GCP no equivale a SCC |
| Simulacro de DR dentro del RTO | Réplica de Cloud SQL, bucket de doble región, `dr_active`; [runbook 04](docs/runbooks/04-conmutacion-a-dr.md) con tabla de tiempos | **Pendiente del primer apply.** RTO ≤ 4 h y RPO ≤ 15 min son objetivos sin medir |
| Cada módulo tiene README, ejemplo y prueba | Estructura de §4.5 del contrato | **Demostrado sin GCP:** los 24 módulos tienen `README.md`, `examples/basic/main.tf` y `tests/*.tftest.hcl` (`ls modules/*/tests/*.tftest.hcl \| wc -l` → 24); `bash scripts/docs.sh --check` → `PASS (37)` |
