# Pipeline de GitHub Actions

Cómo están armados los flujos de `.github/workflows/` (en la raíz del repositorio) y qué tiene
que configurar el equipo en GitHub para activarlos. Contrato: §6 (estado e identidad), §9.2 y
§9.3. Todos los flujos corren con `working-directory: gcp-datacenter`.

Nada de esto se ha ejecutado en GitHub ni contra GCP: los flujos pasan `actionlint` 1.7.12 y
los scripts que usan tienen pruebas sin GCP (`scripts/selftest.sh`). Lo que solo una ejecución
real puede probar está marcado **VERIFICAR**.

## 1. Los flujos

| Flujo | Disparo | Sin GCP (siempre) | Con `GCP_ENABLED = true` |
|---|---|---|---|
| `pr.yml` | Pull request | `scripts/check.sh` con Terraform 1.9.8 (fmt, validate, tflint, checkov; sin `terraform test`) y con 1.16.5 (todo, incluido `terraform test`); `scripts/policy-check.sh`; `scripts/selftest.sh`; `scripts/docs.sh --check`; `plan-gate` | Plan por raíz afectada (`scripts/affected-roots.sh`), Conftest sobre el plan, comentario en el PR con resumen y costo (Infracost); `plan-gate` resume los planes |
| `apply.yml` | Push a `main` con cambios en `gcp-datacenter/**` o `.github/workflows/**`, o manual | Solo el trabajo `GCP habilitado`, que avisa que no se aplica nada | Por raíz, de 1 a 5: plan sin entorno y apply aprobado en su entorno (abajo); prueba de humo de dev antes de qa |
| `drift.yml` | Diario (12:17 UTC) y manual | Nada | `plan -detailed-exitcode -lock=false` por raíz con incidencia `drift`; recursos no administrados por entorno (Cloud Asset Inventory) |
| `terratest.yml` | Nocturno (06:41 UTC), manual y etiquetas `modules/<módulo>/vX.Y.Z` | `go vet ./...` y `go test -run XXX ./...` (solo compila) en `tests/`; si no hay `tests/go.mod`, avisa y termina en verde | Pruebas reales de Terratest sin `tests/e2e` (con una etiqueta, solo las del módulo); falla si se omiten más pruebas que `TERRATEST_MAX_SKIPS` |
| `destroy.yml` | Solo manual (`workflow_dispatch`) desde `main`, entradas `entorno` (`dev` o `qa`) y `confirmacion` | El trabajo `pedido de destrucción` falla: sin GCP no se destruye nada | Destruye `5-workloads` → `4-projects` → `3-networks` del entorno con el mismo plan, huella y aprobación que `apply.yml`, y busca huérfanos en su carpeta con Cloud Asset Inventory (§1.5) |
| `_terraform-root.yml` | Solo `workflow_call` | — | Trabajos `plan` y `apply` de una raíz; lo llama `apply.yml` y, con `destroy: true`, `destroy.yml` |

### 1.1 `pr.yml`

| Trabajo (nombre exacto) | Qué hace |
|---|---|
| `estático (terraform 1.9.8)` | `scripts/check.sh --skip test`: fmt, validate, tflint y checkov con la versión mínima del código (ADR 0001). Con `--skip test`, `init` y `validate` no leen `tests/*.tftest.hcl` (`-test-directory` inexistente y `-no-tests`): las pruebas pueden usar atributos de Terraform ≥ 1.11 (`override_during = plan`), que 1.9.8 rechaza al leer la configuración |
| `estático (terraform 1.16.5)` | `scripts/check.sh` completo, con `terraform test` |
| `conftest (pruebas y planes de ejemplo)` | `scripts/policy-check.sh`: `conftest verify` y cada plan de ejemplo de `policies/fixtures/` |
| `scripts (autopruebas)` | `scripts/selftest.sh`: los scripts de los flujos con datos de `scripts/testdata/` |
| `terraform-docs al día` | `scripts/docs.sh --check` |
| `raíces afectadas`, `plan <raíz>` (uno por raíz), `comentario del plan` | Solo con GCP. El nombre de cada plan cambia con el PR: no se puede exigir uno por uno |
| `plan-gate` | Siempre (`if: always()`). Decide `scripts/plan-gate.sh` (probado en `scripts/selftest.sh`). Falla si `raíces afectadas` o algún `plan <raíz>` (que incluye Conftest sobre el plan real) terminó en `failure` o `cancelled`, si con GCP habilitado no corrió lo que debía, o si el PR viene de un fork y toca raíces (abajo). Pasa cuando la omisión es legítima: `GCP_ENABLED` distinto de `true` (y el PR no es de un fork que toque raíces), o ninguna raíz afectada |

`plan-gate` es lo que hace que una violación de política en el plan real bloquee el merge: sin
él, un trabajo de plan fallido no bloquea nada porque su nombre no se puede marcar como
obligatorio, y un trabajo omitido cuenta como aprobado.

**PR desde un fork.** HIPÓTESIS (documentación de GitHub, no probado): un `pull_request` desde
un fork corre con un token de solo lectura, sin token OIDC (no hay Workload Identity) y sin las
variables del repositorio, así que `GCP_ENABLED` llegaría vacío y, sin una regla propia,
`plan-gate` pasaría como si GCP estuviera apagado. Por eso `raíces afectadas` corre también en
forks (no necesita GCP), `plan <raíz>` y `comentario del plan` no corren en forks, y
`plan-gate` falla con un mensaje explícito si el fork toca alguna raíz, aunque `GCP_ENABLED`
esté apagado (no se puede distinguir de las variables ocultas). Un fork que no toca raíces
pasa. Para un cambio de Terraform que llega por fork, una persona con escritura sube la rama al
repositorio y abre el PR desde ahí.

### 1.2 `apply.yml`

Orden de los trabajos (cada uno espera a que el anterior termine con éxito):

```
gate
org (1-org) → security (2-security) → networks-hub (3-networks)      entorno common
  → dev-networks → dev-projects → dev-workloads                      entorno dev
  → dev-smoke (prueba de humo de dev)
  → qa-networks  → qa-projects  → qa-workloads                       entorno qa
  → prod-networks → prod-projects → prod-workloads                   entorno prod
```

Cada raíz llama a `_terraform-root.yml`, que tiene dos trabajos:

**`plan <raíz>`** (sin entorno de GitHub):

0. `scripts/check-main-tip.sh "$GITHUB_SHA"` (checkout con `fetch-depth: 0`): el commit de la
   ejecución tiene que estar en `main` y ningún commit posterior de `main` puede cambiar
   `gcp-datacenter/` ni `.github/workflows/`. Si no, falla sin planear. Ver "Ejecuciones
   viejas" abajo. Además guarda la huella (SHA-256) de `GCP_TFVARS_JSON`,
   `GCP_STAGE_SERVICE_ACCOUNTS` y `GCP_STATE_BUCKET` para compararla en el apply (§2).
1. Autenticación por Workload Identity Federation con la cuenta de la etapa
   (`GCP_STAGE_SERVICE_ACCOUNTS[<etapa>]`). Los spokes usan la de `3-networks`.
2. `terraform.tfvars.example` → `terraform.tfvars`, y encima `zz-ci.auto.tfvars.json` con
   `GCP_TFVARS_JSON` (`common` + la llave de la raíz); igual que `pr.yml`.
3. `terraform init -backend-config="bucket=$GCP_STATE_BUCKET"`.
4. `terraform plan -detailed-exitcode -out=tfplan` y `terraform show -json`.
5. Huella del plan: `scripts/plan-fingerprint.py` (SHA-256 de dirección, acciones, `after`,
   `after_unknown` y `after_sensitive` de cada cambio, y acciones de las salidas; no incluye el
   estado anterior ni la fecha).
6. `conftest test plan.json --policy policies`. Una denegación detiene la raíz y todo lo que
   viene después, antes de pedir aprobación.
7. Resumen del trabajo: resultado del plan y de Conftest, la línea `Plan:`, la huella y la lista
   de recursos con cambios (acción y dirección). Se ve en la página de la ejecución mientras el
   apply espera la aprobación; los valores están en el registro del trabajo.

**`apply <raíz>`** (en el entorno de la raíz; solo si el plan tiene cambios):

1. El entorno aplica sus reglas antes de que el trabajo empiece (revisores en `common` y
   `prod`). Sin cambios, el trabajo se omite: no hay pedido de aprobación.
2. Huella de las tres variables igual a la del trabajo `plan`; si no, falla antes de `init`
   con un mensaje que nombra el entorno (§2).
3. Mismos pasos 1 a 4 sobre el mismo commit, y huella del plan nuevo. Si no es igual a la
   revisada (algo cambió entre el plan y la aprobación), falla sin aplicar nada: hay que volver
   a correr el flujo y revisar el plan nuevo.
4. Conftest sobre ese plan.
5. Otra vez `scripts/check-main-tip.sh "$GITHUB_SHA"`, justo antes del apply: `main` pudo
   cambiar el despliegue mientras se esperaba la aprobación.
6. `terraform apply tfplan`: el archivo que revisó Conftest en este mismo trabajo, cuyo
   contenido es el que se aprobó.

**Ejecuciones viejas.** `github.sha` queda fijo en una ejecución: un "Re-run jobs" de una
ejecución anterior, o una aprobación que llega después de otro merge, planearía y aplicaría el
código de ese commit encima de lo que ya aplicó una ejecución más nueva. Regla de
`scripts/check-main-tip.sh`, en el trabajo `plan` y otra vez justo antes de `terraform apply`:

- `github.sha` está en `main` (si no, falla);
- ningún commit posterior de `main` cambia `gcp-datacenter/` ni `.github/workflows/` (si
  alguno lo hace, falla y lista esos commits). Un merge que no toca esas rutas (README de la
  raíz, `labs/`, `.github/dependabot.yml`) no detiene la ejecución en curso;
- el contenido de esas rutas en la punta de `main` es igual al de `github.sha` (`git diff`
  entre los dos árboles; si no, falla y lista los archivos). Cubre lo que el `git log` por rutas
  no ve: en un merge cuyo resultado en esas rutas es igual al de uno de sus padres, `git log`
  sigue solo a ese padre, así que un merge que descarta un cambio (resuelto a favor de la otra
  rama) no aparece en el listado aunque lo que se desplegaría ya es otro. Reproducido sin
  GitHub el 23 nov 2026 (`scripts/selftest.sh`, caso "un merge que descarta cambios de las
  rutas").

Son las mismas rutas con las que se dispara `apply.yml` (`paths` del `push`; `selftest.sh`
comprueba que coinciden). Por eso un commit que deja vieja a una ejecución siempre encola otra:
la `concurrency` `apply-gcp-datacenter` la deja esperando hasta que la vieja termine (o falle
por esta regla) y entonces planea y aplica desde `1-org` con el código nuevo.

**Estado a medias.** Si la ejecución vieja falla por esta regla después de aplicar algunas
raíces (por ejemplo `common` y `dev` con el commit A, y la de `qa` se detiene porque se fusionó
el commit C), las raíces de `qa` y `prod` quedan con lo que tenían de la última ejecución que
las aplicó, y `dev` ya tiene A. No hay que deshacer nada: la ejecución de C vuelve a planear
todas las raíces; las que ya están al día dan "sin cambios" y no piden aprobación, y las demás
se aplican en orden. Si esa ejecución no aparece (por ejemplo, alguien la canceló), lanzar
`apply.yml` a mano con `workflow_dispatch` sobre `main`. Mientras tanto, `drift.yml` puede
reportar diferencias en las raíces pendientes.

`workflow_dispatch`: la ejecución manual sobre `main` toma la punta del momento en que se
lanza; queda vieja solo si después se fusiona un cambio en esas rutas, que trae su propia
ejecución.

Clones superficiales: los checkouts de `_terraform-root.yml` usan `fetch-depth: 0`; si aun así
el clon es superficial, el script intenta `git fetch --unshallow` y, si no lo logra, sale con 2
(falla cerrado), igual que con un remoto ilegible o un commit desconocido. Usa la credencial que
deja `actions/checkout` (no se pone `persist-credentials: false`). Probado sin GitHub en
`scripts/selftest.sh` con un remoto local: punta, merge ajeno a las rutas, cambio de Terraform,
cambio de flujo, commit fuera de `main`, clon superficial, remoto ilegible y merge que descarta
cambios de las rutas. **VERIFICAR** en la primera ejecución real.

Por qué se vuelve a planear en vez de pasar `tfplan` entre trabajos: el archivo del plan y su
JSON llevan los valores sensibles en claro, y un artefacto de Actions lo descarga cualquiera con
lectura del repositorio; cifrarlo exigiría administrar una llave. La huella es un hash, no expone
valores, y deja la misma garantía: se aplica exactamente lo revisado. Dos planes reales del mismo
ejemplo, sin GCP, dan la misma huella aunque su JSON difiere en la fecha y en el orden de
`relevant_attributes` (`scripts/testdata/fingerprint/`, `scripts/selftest.sh`). **VERIFICAR**
con GCP que un segundo plan sin cambios reales en el medio da la misma huella en cada raíz (un
valor que el proveedor recalcule en cada plan haría fallar el apply, nunca aplicar algo no
revisado).

**`dev / prueba de humo`** (`dev-smoke`, después de `dev-workloads`; qa depende de él): corre
`TestDevSmoke` (`tests/e2e/smoke_test.go`) con la cuenta `GCP_AUDIT_SERVICE_ACCOUNT`. No aplica
nada: lee las salidas de `3-networks` (hub), `3-networks/envs/dev` y `5-workloads/envs/dev` desde
el bucket de estado y corre las Connectivity Tests de dev (dev → Cloud SQL por IP privada,
Internet → balanceador de dev en 443, dev → on-premises simulado). Falla si no hay ninguna prueba
expresable, si alguna no da lo esperado (se exige REACHABLE o UNREACHABLE; UNDETERMINED,
AMBIGUOUS o un paso `abort` fallan siempre), si no se puede leer una salida o describir la
instancia de Cloud SQL (una salida en null por un recurso deshabilitado solo omite su prueba),
o si la prueba se omite (máximo de omitidas 0 en
`scripts/go-test-report.sh`). Solo se salta en una ejecución manual con la entrada
`omitir_prueba_de_humo = true`, que queda como advertencia y en el resumen con el nombre de quien
la pidió.

Reglas:

- `0-bootstrap` no está en el pipeline: la aplica una persona administradora, una vez y a mano
  (runbook de la etapa 0). No tiene cuenta de servicio de pipeline.
- Los spokes se aplican de uno en uno porque los entornos van en serie (dev → qa → prod): GCP
  no admite dos operaciones de peering a la vez sobre la VPC hub.
- `concurrency: apply-gcp-datacenter` sin cancelación: nunca corren dos `apply.yml` a la vez. Si
  llegan varios push mientras uno corre, GitHub deja en espera solo el más reciente y descarta
  los intermedios (el más reciente contiene sus cambios). Una ejecución que espera aprobación
  también retiene el grupo, así que conviene aprobar o rechazar pronto (las aprobaciones
  pendientes vencen a los 30 días, según la documentación de GitHub).
- Los trabajos de Terraform exigen `github.ref == refs/heads/main`: una ejecución manual desde
  otra rama no aplica nada. Esto no cierra la limitación de §5 (una rama puede cambiar el
  propio flujo).
- Cada raíz con cambios en `common` o `prod` pide su propia aprobación (hasta tres por entorno),
  y la persona que aprueba ve antes el resumen del plan de esa raíz.

### 1.3 `drift.yml`

**Drift.** Para cada raíz con `versions.tf` en `stages/` (la misma definición que
`scripts/affected-roots.sh`), salvo `0-bootstrap`: plan con `-detailed-exitcode -lock=false`.

- Código 0: nada.
- Código 2: abre una incidencia `Drift: <raíz>` con la etiqueta `drift` (la crea si no existe)
  o, si ya hay una abierta para esa raíz, reemplaza su cuerpo y agrega un comentario. El cuerpo
  lleva solo las direcciones de los recursos con cambios y la línea `Plan:`; nunca valores.
- Código 1: el trabajo falla.

La incidencia no se cierra sola cuando el drift desaparece: se cierra a mano al resolverlo.

**Recursos no administrados** (`recursos no administrados (<carpeta>)`, uno por cada carpeta
de `1-org`: common, dev, qa y prod; common tiene los proyectos del hub de red, seguridad,
registros y respaldo): objetivo "cero recursos manuales, verificado con Cloud Asset Inventory".

1. Con `GCP_AUDIT_SERVICE_ACCOUNT`, descarga todos los estados del bucket
   (`gs://$GCP_STATE_BUCKET/**/default.tfstate`) a la carpeta temporal del runner; llevan
   valores sensibles y no se suben como artefacto.
2. Toma la carpeta del entorno de la salida `folder_ids` de `1-org` y la lista con
   `gcloud asset search-all-resources --scope=<carpeta> --format=json`.
3. `scripts/unmanaged-resources.py` compara cada recurso con los estados: administrado (nombre
   igual al `id` o `self_link` de algún recurso de algún estado, con formas construidas para
   proyectos por número, cuentas de servicio por ID único y APIs habilitadas), hijo de uno
   administrado (versiones de llaves, revisiones de Cloud Run, versiones de secretos, que se
   cargan a mano por diseño, ADR 0015), VM o disco de un MIG administrado, o permitido por una
   regla de `scripts/unmanaged-allowlist.txt` (recursos que crean Google o GKE; de las APIs
   habilitadas, solo una lista cerrada de dependencias que ninguna raíz declara). Lo que queda
   se lista en el resumen y el trabajo falla.
4. Cobertura: el script recibe la carpeta (`--folder`) y toma como proyectos del entorno los
   `google_project` de los estados cuyo `folder_id` es esa carpeta. Es error (código 2, el
   trabajo falla) un listado vacío o mal formado (`[]`, `{}`, `{"results": []}`, elementos sin
   `name`), que ningún proyecto de los estados esté en esa carpeta, o que falte en el listado
   cualquiera de los proyectos del entorno (listado de otra carpeta, truncado o hecho sin
   permisos sobre un proyecto); el error nombra los que faltan. Así "0 no administrados" solo
   sale de un listado que trae todos los proyectos del entorno. HIPÓTESIS: que `folder_id` del
   estado guarde el número de la carpeta (se acepta también `folders/<N>`).

Un recurso creado a mano no aparece en ningún plan, así que el drift no lo ve: por eso es un
trabajo aparte. Probado sin GCP con `scripts/testdata/unmanaged/` (`scripts/selftest.sh`).
**VERIFICAR** con una carpeta real: el formato de `name` que devuelve Cloud Asset para cada tipo
y que la lista de permitidos cubra lo que crean GKE, los MIG y los servicios administrados (la
primera corrida probablemente marque recursos legítimos; se agregan reglas con su motivo, nunca
un tipo completo sin razón).

### 1.4 `terratest.yml`

`compile` corre siempre. `integration` corre solo con `GCP_ENABLED = true` y si existe
`tests/go.mod`:

- Nocturno y manual: todos los paquetes salvo `tests/e2e` (la prueba de extremo a extremo aplica
  0 → 5 y se lanza a mano).
- Etiqueta `modules/<módulo>/vX.Y.Z`: solo las pruebas de ese módulo, las que aplican
  `tests/fixtures/<módulo>` o una variante (`scripts/module-tests.sh`; `firewall` corre
  `TestFirewallNetwork` y `TestFirewallHierarchical`). Una etiqueta con otra forma hace fallar el
  trabajo. Las etiquetas no fijan versiones: las raíces consumen los módulos por ruta relativa.
- Las pruebas reciben como variables de entorno las `TERRATEST_*` y las `TEST_*` de §2 con el
  mismo nombre, y `GOOGLE_CLOUD_PROJECT = TERRATEST_PROJECT_ID`.
- `go test -json` pasa por `scripts/go-test-report.sh`: el resumen del trabajo lista cuántas
  pasaron, fallaron y se omitieron, y cada omitida con su motivo. El trabajo falla si alguna
  falló o si hay más omitidas que `TERRATEST_MAX_SKIPS` (0 si no se define). Sin las compuertas
  (`TEST_ALLOW_EXPENSIVE`, `TEST_ALLOW_ORG`) y sus datos, la corrida nocturna falla en rojo hasta
  que el equipo las configure o acepte las omisiones subiendo ese número a propósito.

### 1.5 `destroy.yml`

Desmonta dev o qa; es como se demuestra el criterio "`destroy` de dev sin huérfanos"
(pendiente 11). No hay otra forma: las etapas 1 a 5 solo las aplican sus cuentas de servicio, que
solo se obtienen por WIF desde Actions, y las personas tienen solo lectura.

Se lanza a mano desde `main` (Actions → destroy → Run workflow, o
`gh workflow run destroy.yml --ref main -f entorno=dev -f confirmacion=dev`) con
`GCP_ENABLED = true`. Entradas: `entorno` (lista cerrada `dev`, `qa`) y `confirmacion` (el nombre
del entorno, escrito exactamente).

```
pedido de destrucción
  → <env> / destruir 5-workloads → <env> / destruir 4-projects → <env> / destruir 3-networks
  → <env> / huérfanos (Cloud Asset)
```

1. **`pedido de destrucción`**: `scripts/destroy-guard.sh pedido`. Falla si el entorno no es
   `dev` o `qa` (prod con un mensaje propio, también `PROD` o con espacios), si la confirmación no
   es exactamente el nombre del entorno, si la rama no es `main` o si `GCP_ENABLED` no es `true`
   (a diferencia de `apply.yml`, falla: se pidió destruir y no se destruiría nada). Deja en el
   resumen quién lo pidió.
2. **Una raíz por trabajo, en orden inverso al de `apply.yml`**, cada una con la cuenta de su
   etapa (`5-workloads`, `4-projects`, `3-networks`) y `_terraform-root.yml` con
   `destroy: true`: los mismos trabajos `plan` y `apply` de §1.2 (aquí `plan -destroy <raíz>` y
   `destroy <raíz>`), con estas diferencias:
   - `scripts/destroy-guard.sh raiz` en los dos trabajos, antes de autenticarse: solo
     `stages/{3-networks,4-projects,5-workloads}/envs/<entorno>` con entorno `dev` o `qa`;
   - `terraform plan -destroy`, con el plan guardado, la huella y Conftest de siempre (las
     políticas aceptan un plan de destrucción: probado con los planes de
     `scripts/testdata/destroy/`);
   - `scripts/destroy-plan-check.py` sobre ese plan, en el trabajo `plan` (antes de la
     aprobación, con una tabla en el resumen) y otra vez en `destroy` (antes de
     `terraform apply`). Sale con 2 si alguna acción no es `delete`, con 1 si el estado tiene un
     **bloqueo** (abajo) y con 0 con **avisos**;
   - el resumen se titula "Plan de DESTRUCCIÓN" y lista `delete <dirección>` de cada recurso;
   - `destroy <raíz>` corre en el entorno de GitHub `dev` o `qa`, compara las variables y la
     huella con las del plan revisado, repite `check-main-tip.sh` y aplica ese `tfplan`.

   Una raíz ya destruida planea "sin cambios" y no pide aprobación ni aplica. Comprobado sin
   GCP el 23 nov 2026 con Terraform 1.16.5 y recursos integrados: con el estado vacío,
   `plan -destroy -detailed-exitcode` sale con 0 aunque la raíz de la que lee ya no tenga
   salidas; con recursos en el estado y la de arriba sin salidas, falla (por eso el orden
   inverso). Así, **volver a lanzar el flujo** retoma un destroy que falló a medias. "Re-run
   failed jobs" no sirve después de un destroy parcial: el trabajo `destroy` vuelve a planear,
   la huella ya no es la revisada y falla sin aplicar.
3. **`huérfanos`**, con `GCP_AUDIT_SERVICE_ACCOUNT` (los roles de §3 ya alcanzan): toma la
   carpeta del entorno de la salida `folder_ids` del estado de `1-org`, la lista con
   `gcloud asset search-all-resources --scope=<carpeta> --format=json` y
   `scripts/destroy-orphans.py` falla con la lista de lo que quede. Si quedan recursos, vuelve a
   listar hasta tres veces con cinco minutos entre intentos (HYPOTHESIS: el índice de Cloud Asset
   tarda en reflejar los borrados; la documentación no da un plazo). Es **esperado** (se lista
   en el resumen, no falla):
   - la carpeta misma (es de `1-org`);
   - un proyecto en `DELETE_REQUESTED` o `DELETE_IN_PROGRESS` (estados que la
     [referencia de searchAllResources](https://docs.cloud.google.com/asset-inventory/docs/reference/rest/v1/TopLevel/searchAllResources#ResourceSearchResult)
     lista para un proyecto) y todo lo que esté dentro de él: según la
     [documentación de Resource Manager](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects),
     un proyecto borrado se elimina del todo a los 30 días;
   - un recurso en estado `DELETED`, `DELETE_REQUESTED` o `DELETE_IN_PROGRESS`;
   - una versión de llave de KMS `DESTROYED` o `DESTROY_SCHEDULED`. Las llaves de los entornos
     viven en `security` (carpeta `common`) y este flujo no las toca: en la carpeta del entorno
     solo aparecerían si alguien las creó a mano.

   Todo lo demás es **huérfano**: un proyecto `ACTIVE` (por ejemplo, con `deletion_policy =
   "ABANDON"`), una red, un bucket. Un listado vacío pasa (un error de permisos hace fallar a
   `gcloud`); un listado mal formado sale con 2. Lo que el destroy deja fuera de la carpeta (el
   peering y la zona DNS sobre la VPC hub, IAM sobre las llaves de `security`) lo destruyen las
   mismas raíces; si algo quedara, lo ve el trabajo de recursos no administrados de `common` en
   `drift.yml` (§1.3).

**Contra un destroy de prod.** En el flujo, cuatro barreras independientes: la lista cerrada de
`entorno` (HYPOTHESIS: que GitHub rechace por API un valor fuera de `options`; la
[sintaxis de flujos](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
solo dice que el valor por defecto debe estar en la lista), `destroy-guard.sh pedido`, la
condición `inputs.entorno == 'dev' || inputs.entorno == 'qa'` de cada trabajo y
`destroy-guard.sh raiz` en los dos trabajos de cada raíz. Además, en Terraform, prod exige
`deletion_protection = true` en `5-workloads` y `deletion_policy = "PREVENT"` en sus proyectos
(validaciones de la raíz y de `project-factory`), que el proveedor respeta y
`destroy-plan-check.py` detiene antes de borrar. No cierra la limitación de §5: una rama puede
traer su propio flujo y tomar la identidad de las cuentas.

**Contra un commit viejo.** Lo mismo que `apply.yml`: `check-main-tip.sh` en el trabajo `plan` y
justo antes de `terraform apply`, y el grupo de concurrencia `apply-gcp-datacenter`, el mismo de
`apply.yml`: un destroy no corre mientras corre un apply, ni al revés. Según la
[documentación de concurrencia de GitHub](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency),
el grupo es de todo el repositorio y una ejecución nueva en espera cancela la que esperaba: un
destroy lanzado mientras corre un apply queda cancelado si llega otro push antes de que empiece
(hay que lanzarlo otra vez), y el `apply.yml` de un push durante un destroy espera y, al terminar
el destroy, intenta volver a crear el entorno (ver "Después del destroy").

**Aprobación.** El trabajo `destroy` corre en el entorno de GitHub `dev` o `qa`, que no tienen
revisores (§2): no se detiene a pedir aprobación y aplica en cuanto el plan pasa. La
confirmación escrita es el paso humano. Si el equipo quiere revisar el plan de destrucción
antes, tiene que agregar revisores a `dev` y `qa` (también frenaría `apply.yml`; propuesta).

**Preparación.** El proveedor decide el borrado con el valor del **estado**, no con el de la
configuración (descripciones de `deletion_protection` de `google_container_cluster` y
`google_cloud_run_v2_service` en el esquema de google 6.50.0): el valor tiene que llegar al estado
con un `apply.yml` antes del destroy. En `GCP_TFVARS_JSON`, para el entorno:

| Llave | Valor | Ejemplo actual |
|---|---|---|
| `stages/5-workloads/envs/<env>` | `"deletion_protection": false` | `false` en dev y qa |
| `stages/4-projects/envs/<env>` | `"deletion_policy": "DELETE"` | `DELETE` en dev, `PREVENT` en qa |
| `stages/3-networks/envs/<env>` | `"project_deletion_policy": "DELETE"` | sin valor: `PREVENT` por defecto en los tres |

Después, `apply.yml` (cambios en el lugar) y entonces `destroy.yml`. Si falta, el trabajo
`plan -destroy` de la raíz falla en `destroy-plan-check.py` con un **bloqueo** que nombra el
recurso y la variable, antes de borrar nada. Bloqueos: `deletion_protection = true` o
`deletion_protection_enabled = true` (también en `settings` de Cloud SQL) en cualquier recurso,
`deletion_policy = "PREVENT"` en cualquier recurso y, en `google_project`, todo lo que no sea
`"DELETE"` (con `"ABANDON"` el proyecto quedaría vivo y sería un huérfano).

**Lo que el plan no ve (avisos) y qué hacer:**

| Caso | Qué pasa | Qué hacer |
|---|---|---|
| Bóveda de Backup and DR con respaldos (`enable_backup = true`, retención forzada de 30 días en `stages/5-workloads/envs/*/operations.tf`) | Según la [documentación de la bóveda](https://docs.cloud.google.com/backup-disaster-recovery/docs/concepts/backup-vault), ningún respaldo se borra antes de la retención forzada y, desde el 1 nov 2026, Backup and DR pone un gravamen (lien) en el proyecto que los tenga. El destroy de `5-workloads` borra lo demás (incluida la asociación, que deja de crear respaldos) y falla en la bóveda | Para la prueba de destroy, desplegar dev con `"enable_backup": false`. Con respaldos: esperar a que venzan y volver a lanzar; puede seguir fallando sin `ignore_inactive_datasources` (pendiente 86) |
| Conexión de Private Service Access | Según la [documentación de PSA](https://docs.cloud.google.com/vpc/docs/configure-private-services-access), después de borrar una instancia de Cloud SQL el servicio espera cuatro días antes de liberar sus recursos y la conexión no se borra mientras tanto | `3-networks` falla; volver a lanzar `destroy.yml` pasados cuatro días (`5-workloads` y `4-projects` se saltan) (pendiente 87) |
| Bucket de la aplicación sin `force_destroy` | Si tiene objetos, el borrado falla | Pendiente 89 |
| `deletion_policy = "ABANDON"` fuera de un proyecto | Terraform lo suelta y queda en GCP | La comprobación de huérfanos lo ve si está en la carpeta |

**Después del destroy.**

- **El siguiente `apply.yml` vuelve a crear el entorno**: cualquier push a `main` que toque
  `gcp-datacenter/**` o `.github/workflows/**`, o una ejecución manual. Para que no lo haga,
  `GCP_ENABLED` a otro valor después del destroy (guía del colaborador, sección H).
- **IDs de proyecto nuevos antes de recrear.** Según la
  [documentación de Resource Manager](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects),
  el ID de un proyecto borrado no se puede volver a usar. Con el mismo `project_suffix`, el
  `apply.yml` siguiente fallaría al crear el proyecto `net-spoke` del entorno y, como los entornos
  van en cadena, tampoco aplicaría los que vienen después. Antes de recrear, poner un
  `project_suffix` nuevo (hasta 8 minúsculas o dígitos) en las llaves
  `stages/3-networks/envs/<env>` y `stages/4-projects/envs/<env>` de `GCP_TFVARS_JSON`
  (pendiente 88).
- **`drift.yml` se queja hasta recrear el entorno**: las raíces destruidas planean todo como
  creación (incidencias `Drift: …`), la de `5-workloads` puede fallar al leer salidas que ya no
  existen, y el trabajo de recursos no administrados del entorno sale con 2 (ningún proyecto de
  los estados está en la carpeta). Se cierran a mano después de recrear.

Probado sin GCP (`scripts/selftest.sh`): rechazos de `destroy-guard.sh` (prod, mayúsculas,
espacios, confirmación distinta, otra rama, raíz de otro entorno o etapa, `..`), los bloqueos y
avisos de `destroy-plan-check.py` sobre dos planes de destrucción reales de google 6.50.0
(`plan -destroy -refresh=false` sobre un estado escrito a mano), la huella de dos planes de
destrucción reales del mismo estado, la clasificación de `destroy-orphans.py` y la estructura de
`destroy.yml` y del modo destroy de `_terraform-root.yml`. **VERIFICAR** en el primer destroy de
dev (pendiente 85).

## 2. Variables, secretos y entornos que crea el equipo

En Settings → Secrets and variables → Actions → **Variables** (de repositorio). Ninguna es
secreta: son nombres e identificadores, no credenciales. No hay llaves de cuenta de servicio
en ningún lado.

| Variable | Contenido | Ejemplo (marcador) |
|---|---|---|
| `GCP_ENABLED` | `true` activa los trabajos que tocan GCP; cualquier otro valor o ausente los omite | `true` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Salida `workload_identity_provider` de `0-bootstrap` | `projects/<número-proyecto-semilla>/locations/global/workloadIdentityPools/<pool>/providers/<proveedor>` |
| `GCP_STAGE_SERVICE_ACCOUNTS` | Salida `stage_service_accounts` de `0-bootstrap`, en JSON | `{"1-org": "<prefix>-tf-1-org@<proyecto-semilla>.iam.gserviceaccount.com", "2-security": "…", "3-networks": "…", "4-projects": "…", "5-workloads": "…"}` |
| `GCP_STATE_BUCKET` | Salida `state_bucket` de `0-bootstrap` | `<nombre-del-bucket-de-estado>` |
| `GCP_TFVARS_JSON` | Valores de las variables por raíz, en JSON. Para cada raíz se combinan `common` y la llave de la raíz, y se sobreponen a `terraform.tfvars.example` | `{"common": {"org_id": "<org_id>", "billing_account": "<cuenta>", "state_bucket": "<bucket>"}, "stages/1-org": {"groups": {…}}, "stages/5-workloads/envs/prod": {…}}` |
| `GCP_AUDIT_SERVICE_ACCOUNT` | Cuenta de solo lectura de la prueba de humo de dev y de los recursos no administrados (ver §3; `0-bootstrap` no la crea) | `<cuenta>@<proyecto-semilla>.iam.gserviceaccount.com` |
| `TERRATEST_SERVICE_ACCOUNT` | Cuenta de servicio de las pruebas de integración (no es de una etapa; ver §3) | `<cuenta>@<proyecto-de-pruebas>.iam.gserviceaccount.com` |
| `TERRATEST_PROJECT_ID` | Proyecto de pruebas (cuota y llamadas que no van a un proyecto efímero) | `<proyecto-de-pruebas>` |
| `TERRATEST_BILLING_ACCOUNT` | Cuenta de facturación de los proyectos efímeros | `<XXXXXX-XXXXXX-XXXXXX>` |
| `TERRATEST_ORG_ID` | ID numérico de la organización | `<org_id>` |
| `TERRATEST_FOLDER_ID` | Carpeta donde se crean los proyectos efímeros (opcional) | `<folder_id>` |
| `TERRATEST_MAX_SKIPS` | Máximo de pruebas omitidas que acepta `terratest.yml` (por defecto 0) | `0` |
| `TEST_ALLOW_EXPENSIVE`, `TEST_ALLOW_ORG` | Compuertas de las pruebas caras y de organización (`tests/README.md`) | `true` |
| `TEST_DIRECTORY_CUSTOMER_ID`, `TEST_ACCESS_POLICY_ID`, `TEST_NOTIFICATION_EMAIL`, `TEST_GKE_SECURITY_GROUP` | Datos que piden `TestOrg`, `TestVPCSC`, `TestObservability` y `TestGKE` | `C0xxxxxxx`, `<número>`, `<buzón>`, `gke-security-groups@<dominio>` |
| `TEST_MIG_IMAGE`, `TEST_CLOUD_RUN_IMAGE`, `TEST_LB_DOMAIN`, `TEST_REGION`, `TEST_DR_REGION` | Ajustes opcionales de las pruebas (tienen valor por defecto) | — |

`GCP_TFVARS_JSON` tiene que llevar todos los valores reales: lo que no traiga se toma de
`terraform.tfvars.example`, que solo tiene valores de ejemplo.

**Marcadores de los ejemplos que hay que reemplazar antes de la primera ejecución.** Lista
sacada de los `terraform.tfvars.example` el 23 nov 2026. La columna "Si queda el ejemplo" dice
lo que valida Terraform; lo que diga la API de GCP es HIPÓTESIS hasta el primer apply
(pendiente 55).

| Llave de `GCP_TFVARS_JSON` | Variables | Si queda el ejemplo |
|---|---|---|
| `common` | `org_id`, `billing_account`, `state_bucket`; `prefix` si la etapa 0 usó otro; `project_suffix` si los IDs de proyecto lo necesitan para ser únicos | `000000000000` y `000000-000000-000000` no existen; `state_bucket` de ejemplo solo coincide con `prefix = "bnt"` sin sufijo |
| `stages/1-org` | `directory_customer_id`, `groups` (los siete grupos reales), `budget_amount` | `directory_customer_id` es el único cliente que admite `iam.allowedPolicyMemberDomains`: con el marcador `C00000000` la política rechazaría a los grupos y cuentas propios. Los grupos `@example.com` no existen |
| `stages/2-security` | `access_policy_id` (si la organización ya tiene política, runbook 01 paso 8), `secret_names` | Con una política existente y `access_policy_id = null`, la etapa intenta crear otra |
| `stages/3-networks` y `stages/3-networks/envs/<env>` | Ninguna obligatoria con on-premises simulado; `labels` | Etiquetas `example-team` y `example-cc` en los recursos |
| `stages/4-projects/envs/<env>` | `workloads_service_account` (salida `stage_service_accounts["5-workloads"]` de la etapa 0), `artifact_registry_publishers` | El correo de ejemplo solo coincide con `prefix = "bnt"` sin `project_suffix` en la etapa 0 (con otro proyecto la validación pasa y la etapa 5 falla por permisos). El publicador de ejemplo (`bnt-ci-app@example-cicd…`) no existe: `{}` o identidades reales |
| `stages/5-workloads/envs/<env>` | `cloud_run_image`, `mig_image` (qa y prod), `gke_authenticator_security_group` y `gke_master_authorized_networks` (prod), `domain_names`, `internal_domain_names` (prod), `notification_emails` | Las imágenes de ejemplo apuntan a proyectos `example-*` que no son del equipo (ver abajo); con dominios de ejemplo los certificados no se emiten; las alertas irían a `@example.com` |

No poner `labels` en `common`: cada raíz valida las suyas (en `5-workloads`, `labels.app` tiene
que ser igual a `application`) y `common` las pisaría en todas.

**Primera ejecución: sin imágenes todavía.** El repositorio de Artifact Registry de cada
aplicación lo crea `4-projects/envs/<env>` en la misma ejecución que después aplica
`5-workloads/envs/<env>`, así que en la primera ejecución no puede haber una imagen publicada.
Los ejemplos de dev, qa y prod traen `enable_cloud_run = true` (y qa y prod, `enable_mig = true`
con una imagen de ejemplo). Para la primera ejecución, en la llave de cada raíz de
`5-workloads`: `enable_cloud_run = false` y `enable_mig = false`; en prod, además,
`enable_internal_lb = false` (el balanceador interno exige un backend `mig` o `run`) y
`enable_gke = false` mientras no exista el grupo `gke-security-groups@<dominio>`. Con todo el
cómputo apagado la raíz sigue planeando: datos, observabilidad y respaldo, sin balanceadores
(pruebas `primera_ejecucion_sin_computo` y `prod_primera_ejecucion_sin_computo` de
`stages/5-workloads/envs/*/tests/`, con proveedores simulados). Después, el runbook
[02](runbooks/02-alta-proyecto-aplicacion.md), pasos 3 y 4: publicar la imagen, cambiar la
variable y lanzar `apply.yml` otra vez.

**Solo variables de repositorio, nunca de entorno.** `GCP_TFVARS_JSON`,
`GCP_STAGE_SERVICE_ACCOUNTS` y `GCP_STATE_BUCKET` (y en general todas las de esta tabla) se
definen solo a nivel de repositorio. El trabajo `apply` corre en un entorno de GitHub y el de
`plan` no: una variable con el mismo nombre en Settings → Environments → `<entorno>` le daría
al apply otro valor que al plan revisado, y la huella del plan nunca coincidiría (o, peor, el
apply usaría otra cuenta u otro bucket). `_terraform-root.yml` compara la huella de esas tres
variables entre los dos trabajos y falla antes de `init` con un mensaje que nombra el entorno;
el mensaje de huella de plan distinta también lo recuerda.

**Secretos** (Settings → Secrets and variables → Actions → Secrets):

| Secreto | Uso |
|---|---|
| `INFRACOST_API_KEY` | Opcional, solo `pr.yml`. Sin él se omite el costo |

**Entornos** (Settings → Environments). Los trabajos `apply` se ligan a ellos; GitHub crea un
entorno sin reglas la primera vez que un trabajo lo usa, así que hay que crearlos y protegerlos
**antes** de poner `GCP_ENABLED = true`.

| Entorno | Lo usan | Reglas |
|---|---|---|
| `common` | apply de `1-org`, `2-security`, `3-networks` (hub) | **Required reviewers** (seguridad y plataforma), "Prevent self-review" y "Deployment branches: `main`" |
| `dev` | apply de las raíces de dev; destroy de dev (`destroy.yml`) | Ninguna (automático); "Deployment branches: `main`" recomendado |
| `qa` | apply de las raíces de qa; destroy de qa (`destroy.yml`) | Ninguna; el apply corre solo después de dev y de la prueba de humo de dev |
| `prod` | apply de las raíces de prod | **Required reviewers** con dos revisores, "Prevent self-review" y "Deployment branches: `main`" |

Los trabajos `plan` no usan entorno: corren antes de la aprobación para que se vea el plan.

## 3. Cómo se enciende GCP

1. Una persona administradora aplica `0-bootstrap` (runbook de la etapa 0).
2. Carga sus salidas como variables: `GCP_WORKLOAD_IDENTITY_PROVIDER`,
   `GCP_STAGE_SERVICE_ACCOUNTS`, `GCP_STATE_BUCKET`; y escribe `GCP_TFVARS_JSON`.
3. Crea los entornos y sus reglas (§2 y §4).
4. Crea a mano la cuenta `GCP_AUDIT_SERVICE_ACCOUNT` (`0-bootstrap` no la crea), le da
   `roles/iam.workloadIdentityUser` al `principalSet://…/attribute.repository_id/<id-del-repositorio>`
   del pool de la etapa 0 (el mismo `github_repository_id` de su `terraform.tfvars`, igual que
   las cuentas de etapa), y estos roles de solo lectura (**VERIFICAR** con la documentación y
   la primera corrida):
   - `roles/storage.objectViewer` en el bucket de estado (lee todos los prefijos);
   - `roles/cloudasset.viewer` en las carpetas common, dev, qa y prod (`search-all-resources`);
   - `roles/networkmanagement.admin` en el proyecto host de dev (crear y borrar las
     Connectivity Tests), `roles/compute.networkViewer` en los proyectos host de dev y del hub,
     y `roles/cloudsql.viewer` en los proyectos de servicio de dev;
   - la API `cloudasset.googleapis.com` habilitada en el proyecto de cuota de la cuenta. La API
     `networkmanagement.googleapis.com` del proyecto host (donde se crean las Connectivity
     Tests) la habilita `3-networks/envs/<env>`; no se habilita a mano.

   **Orden.** Solo el bucket de estado y el proyecto semilla existen después de la etapa 0. Las
   carpetas y el proyecto del hub existen después del apply de `1-org`; el host de dev, después
   de `dev / 3-networks`; los proyectos de servicio de dev, después de `dev / 4-projects`. Por
   eso, antes de encender el pipeline solo se pueden crear la cuenta, su
   `workloadIdentityUser` y el rol sobre el bucket; el resto se asigna durante la primera
   ejecución, a medida que existen los recursos (los da una persona con
   `resourcemanager.projectIamAdmin` o administración de la organización; las personas de los
   grupos solo tienen lectura). Si `dev / prueba de humo` corre antes de que estén, falla y qa
   no empieza: asignar los roles y usar "Re-run failed jobs" en esa ejecución
   (`check-main-tip.sh` lo permite mientras `main` no cambie el despliegue). El trabajo de
   recursos no administrados de `drift.yml` falla igual hasta que la cuenta tenga
   `cloudasset.viewer` en las cuatro carpetas. El trabajo de huérfanos de `destroy.yml` (§1.5)
   usa los mismos roles: lectura del estado de `1-org` y `cloudasset.viewer` en la carpeta del
   entorno.
5. Pone `GCP_ENABLED = true`. Desde ese momento:
   - `pr.yml` planea las raíces afectadas por cada PR y comenta el resultado;
   - el siguiente push a `main` (o una ejecución manual de `apply`) planea y aplica 1 → 5,
     pidiendo aprobación en `common` y `prod` donde haya cambios;
   - `drift.yml` corre cada día.
6. Para las pruebas reales de Terratest: crear a mano la cuenta `TERRATEST_SERVICE_ACCOUNT`
   (permiso para crear proyectos en `TERRATEST_FOLDER_ID`, `billing.user` en la cuenta de
   facturación) y darle `roles/iam.workloadIdentityUser` al mismo `principalSet`.
   `0-bootstrap` no crea esa cuenta. Después, las variables `TERRATEST_*` y `TEST_*`.

Para apagarlo, `GCP_ENABLED` a cualquier otro valor: los trabajos de GCP vuelven a omitirse y
los flujos terminan en verde (`plan-gate` pasa).

## 4. Configuración manual (no vive en el repositorio)

Nada de esto se puede declarar en YAML; lo hace una persona con permisos de administración del
repositorio.

1. **Protección de la rama `main`** (Settings → Branches o Rulesets): exigir PR, dos
   aprobaciones, revisión de Code Owners (solo después de reemplazar los marcadores de
   `.github/CODEOWNERS`, que GitHub ignora mientras no sean usuarios o equipos reales), prohibir
   push forzado y borrado, y estas **comprobaciones obligatorias** de `pr.yml`, con el nombre
   exacto del trabajo:
   - `estático (terraform 1.9.8)`
   - `estático (terraform 1.16.5)`
   - `conftest (pruebas y planes de ejemplo)`
   - `scripts (autopruebas)`
   - `terraform-docs al día`
   - `plan-gate`

   Estos nombres no dependen del PR; si se cambia uno en el flujo, hay que cambiarlo también
   aquí y en la regla de GitHub.

   En la misma regla, además:
   - **"Dismiss stale pull request approvals when new commits are pushed"**;
   - **"Require approval of the most recent reviewable push"** (con la anterior, una
     aprobación vale solo para el código que se revisó);
   - **"Do not allow bypassing the above settings"** (en rulesets: sin "bypass list"; en la
     protección clásica: incluir a los administradores), para que nadie fusione sin las
     comprobaciones ni las aprobaciones.

   Las tres vienen apagadas por defecto. **Por qué importan:** en un `pull_request`, GitHub
   corre los flujos y los scripts del merge commit del PR (`GITHUB_SHA` es ese commit), no los
   de `main`. `pr.yml`, `scripts/plan-gate.sh`, `scripts/affected-roots.sh`,
   `scripts/policy-check.sh`, `scripts/check.sh`, las políticas de `policies/` y la
   configuración de checkov y tflint son los del PR: un PR puede debilitar su propia compuerta
   (por ejemplo, `exit 0` en `plan-gate.sh` o una exclusión en `.checkov.yaml`) y las
   comprobaciones obligatorias pasarían. Lo único que lo impide es la revisión de Code Owners
   (GitHub lee `CODEOWNERS` de la rama base): seguridad es dueña de `/.github/`,
   `scripts/`, `policies/`, `stages/0-bootstrap/`, `.checkov.yaml`, `.tflint.hcl` y
   `tests/e2e/` (la prueba de humo antes de qa). Sin las dos opciones de aprobación de arriba,
   un commit subido después de la aprobación de seguridad entraría sin revisión nueva.

   **Guía de revisión:** quien revisa un PR mira también los `#checkov:skip=` y
   `# tflint-ignore` en línea de los `.tf` (no pasan por un archivo con dueño de seguridad):
   cada uno con su motivo, y uno nuevo es motivo para pedir la revisión de seguridad.
2. **Revisores de los entornos `common` y `prod`** (Settings → Environments → Required
   reviewers). Según la documentación de GitHub, basta con que **uno** de los revisores listados
   apruebe; la regla no cuenta aprobaciones. La aprobación de dos personas la da la protección
   de `main` (dos aprobaciones del PR); el entorno agrega una aprobación por raíz con cambios,
   con el plan a la vista. **Verificar** este comportamiento en la configuración real.
3. **Plan de GitHub.** Según la documentación de GitHub (no comprobado aquí): en repositorios
   públicos, protección de rama, entornos y revisores obligatorios están en todos los planes;
   en repositorios privados, la protección de rama exige GitHub Pro, Team o Enterprise, y los
   revisores obligatorios de un entorno, GitHub Enterprise. **Hay que verificarlo** con el plan
   del equipo antes de contar con estos controles (pendiente 12 del primer apply). Sin
   revisores obligatorios, `common` y `prod` se aplicarían sin aprobación.

## 5. Limitación conocida: WIF filtra solo por repositorio

Documentada en el README de `stages/0-bootstrap` y en el ADR
[0023](adr/0023-endurecimiento-de-la-identidad-del-pipeline.md). El proveedor de WIF acepta
cualquier token con `assertion.repository_id == <id>` y `assertion.repository_owner_id == <id>`
(IDs numéricos: un repositorio borrado y vuelto a crear con el mismo nombre no hereda la
confianza), y cada cuenta de etapa da `roles/iam.workloadIdentityUser` al `principalSet` del
repositorio completo (`attribute.repository_id/<id>`). Por eso
**cualquier rama o flujo del repositorio** (incluido un PR desde una rama del mismo
repositorio) puede tomar la identidad de las cuentas de etapa, que pueden aplicar cambios. La
condición `github.ref == refs/heads/main` de `apply.yml` y la protección de los entornos no
lo impiden: una rama puede traer su propio flujo modificado. Lo mismo vale para el trabajo
`plan` de `_terraform-root.yml`, que usa la cuenta de la etapa sin entorno.

Mitigación prevista (no construida): restringir las cuentas que aplican a `main` o a un entorno
con `attribute.ref` o `attribute.environment` en el `principalSet`, y separar cuentas de solo
lectura para los `plan`. Mientras tanto, limitar quién tiene permiso de escritura en el
repositorio; `CODEOWNERS` pone `.github/`, `stages/0-bootstrap/`, `scripts/`, `policies/`,
`.checkov.yaml`, `.tflint.hcl` y `tests/e2e/` a cargo de seguridad.

## 6. Acciones fijadas por SHA

Cada `uses:` de los flujos apunta al SHA completo del commit de la versión, con la versión en un
comentario (`actions/checkout@<sha> # v7.0.1`). Las etiquetas se resolvieron con
`gh api repos/<dueño>/<repo>/git/ref/tags/<etiqueta>`, siguiendo las etiquetas anotadas hasta el
commit. Una etiqueta que se mueva no cambia lo que corre.

`.github/dependabot.yml` revisa las acciones cada semana y abre un PR agrupado con los SHA
nuevos; ese PR pasa por `pr.yml` y por la revisión de seguridad (`CODEOWNERS`).

Conftest y terraform-docs se descargan de sus releases y se comprueban con el `checksums.txt` o
`.sha256sum` del mismo release: eso da integridad de la descarga, no autenticidad (vienen del
mismo lugar).
