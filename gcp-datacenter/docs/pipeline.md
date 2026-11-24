# Pipeline de GitHub Actions

Cómo están armados los flujos de `.github/workflows/` (en la raíz del repositorio) y qué tiene
que configurar el equipo en GitHub para activarlos, con toda la landing zone en un solo proyecto
de GCP ([ADR 0029](adr/0029-un-solo-proyecto.md) §2, §3 y §8). Contrato: §6 (estado e
identidad), §9.2 y §9.3, salvo donde el ADR 0029 diga otra cosa. Todos los flujos corren con
`working-directory: gcp-datacenter`. El pipeline del diseño de varios proyectos vive en la rama
`archivo/multiproyecto`.

Nada de esto se ha ejecutado en GitHub ni contra GCP: los flujos pasan `actionlint` 1.7.12
(`actionlint .github/workflows/*.yml` desde la raíz, 24 nov 2026: código 0, sin mensajes) y los
scripts que usan tienen pruebas sin GCP (`scripts/selftest.sh`). Lo que solo una ejecución real
puede probar está marcado **VERIFICAR**.

## 1. Los flujos

| Flujo | Disparo | Sin GCP (siempre) | Con `GCP_ENABLED = true` |
|---|---|---|---|
| `pr.yml` | Pull request (siempre, sin filtro de rutas) | `scripts/check.sh` con Terraform 1.9.8 (fmt, validate, tflint, checkov; sin `terraform test`) y con 1.16.5 (todo, incluido `terraform test`); `scripts/policy-check.sh`; `scripts/selftest.sh`; `scripts/docs.sh --check`; `go vet` y `go test` de `tests/` sin GCP; `plan-gate` | Plan por raíz afectada (`scripts/affected-roots.sh`) con la cuenta de lectura `tf-read` y `-lock=false`, Conftest sobre el plan, comentario en el PR con resumen y costo (Infracost); `plan-gate` resume los planes |
| `apply.yml` | Push a `main` con cambios en `gcp-datacenter/**` o `.github/workflows/**`, salvo `gcp-datacenter/docs/**` y los `.md` de `gcp-datacenter/`; o manual | Solo el trabajo `GCP habilitado`, que avisa que no se aplica nada | Por raíz, de `1-base` a las cargas de prod: plan con `tf-read` sin entorno y apply aprobado en su entorno con la cuenta de la raíz (abajo); prueba de humo de dev antes de qa; sin las raíces de los entornos de `GCP_DISABLED_ENVS` |
| `drift.yml` | Diario (12:17 UTC) y manual | Nada | `plan -detailed-exitcode -lock=false` por raíz con `tf-read` e incidencia `drift`, sin las raíces de `GCP_DISABLED_ENVS`; recursos no administrados del proyecto (Cloud Asset Inventory) |
| `terratest.yml` | Nocturno (06:41 UTC), manual y etiquetas `modules/<módulo>/vX.Y.Z` | `go vet ./...` y `go test -run XXX ./...` (solo compila) en `tests/`; si no hay `tests/go.mod`, avisa y termina en verde | Pruebas reales de Terratest sin `tests/e2e`, por defecto en un solo proyecto de pruebas que no puede ser el de la landing zone (con una etiqueta, solo las del módulo); falla si se omiten más pruebas que `TERRATEST_MAX_SKIPS`, sin contar las `[sin-organizacion]` |
| `destroy.yml` | Solo manual (`workflow_dispatch`) desde `main`, entradas `entorno` (`dev` o `qa`), `confirmacion` e `incluir_red` | El trabajo `pedido de destrucción` falla: sin GCP no se destruye nada | Destruye `3-workloads/envs/<env>` y, solo con `incluir_red = true`, el spoke `2-networks/envs/<env>`, con el mismo plan, huella y aprobación que `apply.yml`; busca huérfanos del entorno en el proyecto con Cloud Asset Inventory (§1.5) |
| `_terraform-root.yml` | Solo `workflow_call` | — | Trabajos `plan` (con `tf-read`) y `apply` (con la cuenta de la raíz) de una raíz; lo llama `apply.yml` y, con `destroy: true`, `destroy.yml` |

Cuentas del pipeline (las crea `0-bootstrap`, ADR 0029 §3; detalle en el README de
`stages/0-bootstrap`):

| Cuenta | Llave de `GCP_STAGE_SERVICE_ACCOUNTS` | Raíz que aplica | Quién la obtiene (§5) |
|---|---|---|---|
| `<prefix>-tf-base` | `1-base` | `stages/1-base` | Un trabajo de `main`, de un flujo de `.github/workflows/` del repositorio, en el entorno `common` |
| `<prefix>-tf-net` | `2-networks` | `stages/2-networks` (hub) | Igual, en `common` |
| `<prefix>-tf-net-<env>` | `2-networks/<env>` | `stages/2-networks/envs/<env>` | Igual, en `<env>` |
| `<prefix>-tf-wl-<env>` | `3-workloads/<env>` | `stages/3-workloads/envs/<env>` | Igual, en `<env>` |
| `<prefix>-tf-read` | — (variable `GCP_AUDIT_SERVICE_ACCOUNT`) | ninguna: solo lee | Cualquier trabajo del repositorio, de cualquier rama |

### 1.1 `pr.yml`

| Trabajo (nombre exacto) | Qué hace |
|---|---|
| `estático (terraform 1.9.8)` | `scripts/check.sh --skip test`: fmt, validate, tflint y checkov con la versión mínima del código (ADR 0001). Con `--skip test`, `init` y `validate` no leen `tests/*.tftest.hcl` (`-test-directory` inexistente y `-no-tests`): las pruebas pueden usar atributos de Terraform ≥ 1.11 (`override_during = plan`), que 1.9.8 rechaza al leer la configuración |
| `estático (terraform 1.16.5)` | `scripts/check.sh` completo, con `terraform test` |
| `conftest (pruebas y planes de ejemplo)` | `scripts/policy-check.sh`: `conftest verify` y cada plan de ejemplo de `policies/fixtures/` |
| `scripts (autopruebas)` | `scripts/selftest.sh`: los scripts de los flujos con datos de `scripts/testdata/` |
| `terraform-docs al día` | `scripts/docs.sh --check` |
| `go (vet y pruebas sin GCP)` | En `tests/`: `go vet ./...` y `go test -count=1 ./...`, sin credenciales (las pruebas que necesitan GCP se omiten solas) |
| `raíces afectadas`, `plan <raíz>` (uno por raíz), `comentario del plan` | Solo con GCP. El nombre de cada plan cambia con el PR: no se puede exigir uno por uno |
| `plan-gate` | Siempre (`if: always()`). Decide `scripts/plan-gate.sh` (probado en `scripts/selftest.sh`). Falla si `raíces afectadas` o algún `plan <raíz>` (que incluye Conftest sobre el plan real) terminó en `failure` o `cancelled`, si con GCP habilitado no corrió lo que debía, o si el PR viene de un fork y toca raíces (abajo). Pasa cuando la omisión es legítima: `GCP_ENABLED` distinto de `true` (y el PR no es de un fork que toque raíces), o ninguna raíz afectada |

`plan-gate` es lo que hace que una violación de política en el plan real bloquee el merge: sin
él, un trabajo de plan fallido no bloquea nada porque su nombre no se puede marcar como
obligatorio, y un trabajo omitido cuenta como aprobado.

**Raíces afectadas.** `scripts/affected-roots.sh` toma como raíz cada directorio de `stages/`
con `versions.tf`, salvo `0-bootstrap`, y da para cada una su llave de cuenta y su entorno de
GitHub (`stages/<etapa>` → `<etapa>` y `common`; `stages/<etapa>/envs/<env>` → `<etapa>/<env>`
y `<env>`). Un archivo de una raíz afecta solo a esa raíz; un cambio en `modules/` o
`policies/` afecta a todas; un cambio en `stages/0-bootstrap/` no planea ninguna, porque las
demás leen su estado, que no cambia hasta que una persona la aplica. Un `.md` no afecta a
ninguna, esté donde esté, y `docs/` está fuera de las raíces: un PR de solo documentación pasa
las comprobaciones sin planear nada (ningún `.tf` lee un `.md` ni `docs/`; lo comprueba
`scripts/selftest.sh`).

**Plan de cada raíz.** `plan <raíz>` se autentica por WIF con `GCP_AUDIT_SERVICE_ACCOUNT`
(`tf-read`): las cuentas que escriben solo aceptan tokens de un trabajo de `main`, de un flujo
del repositorio y con entorno de GitHub, y este trabajo no tiene entorno (§5). Arma las
variables con `scripts/root-tfvars.py` (§2) y corre `terraform plan -lock=false`, porque
`tf-read` no puede escribir el candado del estado.

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

Orden de los trabajos (cada uno espera a que el anterior termine con éxito; ADR 0029 §2):

```
gate (GCP habilitado y GCP_DISABLED_ENVS)
base (1-base) → networks-hub (2-networks, hub)                       entorno common
  → dev-networks (2-networks/envs/dev) → dev-workloads (3-workloads/envs/dev)   entorno dev
  → dev-smoke (prueba de humo de dev)                                 sin entorno, tf-read
  → qa-networks → qa-workloads                                        entorno qa
  → prod-networks → prod-workloads                                    entorno prod
```

**Entornos apagados (`GCP_DISABLED_ENVS`).** Variable de repositorio opcional (§2): por
ejemplo `dev`, `qa` o `dev,qa`. El trabajo `gate` la valida con `scripts/disabled-envs.py`: solo
admite `dev` y `qa`; con `prod` o cualquier otro nombre sale con 2 y no se aplica nada. Las
raíces de un entorno apagado no se planean ni se aplican, y el entorno siguiente no lo espera:

| Apagado | qa empieza después de | prod empieza después de |
|---|---|---|
| Ninguno | la prueba de humo de dev | `qa / 3-workloads` |
| `dev` | el hub | `qa / 3-workloads` |
| `qa` | — | la prueba de humo de dev |
| `dev,qa` | — | el hub |

Un trabajo omitido solo cuenta como listo si su entorno está apagado: con dev encendido, si una
raíz de dev o su prueba de humo falla, qa y prod no corren. Los spokes siguen en serie aunque
haya entornos apagados. prod no se apaga con esta variable: para no aplicar nada, `GCP_ENABLED`
distinto de `true`. Las condiciones usan `!cancelled()` para evaluarse aunque un trabajo previo
se haya omitido; cómo trata GitHub ese resultado `skipped` es **VERIFICAR** en la primera
ejecución con `GCP_DISABLED_ENVS=dev` (pendiente 143).

| Trabajo | Nombre en GitHub | Raíz | Llave de la cuenta | Entorno |
|---|---|---|---|---|
| `base` | `1-base` | `stages/1-base` | `1-base` | `common` |
| `networks-hub` | `2-networks (hub)` | `stages/2-networks` | `2-networks` | `common` |
| `dev-networks` | `dev / 2-networks` | `stages/2-networks/envs/dev` | `2-networks/dev` | `dev` |
| `dev-workloads` | `dev / 3-workloads` | `stages/3-workloads/envs/dev` | `3-workloads/dev` | `dev` |
| `dev-smoke` | `dev / prueba de humo` | — (lee estados) | `GCP_AUDIT_SERVICE_ACCOUNT` | — |
| `qa-networks`, `qa-workloads` | `qa / 2-networks`, `qa / 3-workloads` | `stages/{2-networks,3-workloads}/envs/qa` | `2-networks/qa`, `3-workloads/qa` | `qa` |
| `prod-networks`, `prod-workloads` | `prod / 2-networks`, `prod / 3-workloads` | `stages/{2-networks,3-workloads}/envs/prod` | `2-networks/prod`, `3-workloads/prod` | `prod` |

Cada raíz llama a `_terraform-root.yml` con `root`, `stage` (la llave de la cuenta) y
`environment`, y ese flujo tiene dos trabajos:

**`plan <raíz>`** (sin entorno de GitHub, con la cuenta de lectura):

0. Falla si falta `GCP_AUDIT_SERVICE_ACCOUNT`. Luego `scripts/check-main-tip.sh "$GITHUB_SHA"`
   (checkout con `fetch-depth: 0`): el commit de la ejecución tiene que estar en `main` y
   ningún commit posterior de `main` puede cambiar las rutas del despliegue (`gcp-datacenter/`
   sin su documentación, y `.github/workflows/`).
   Si no, falla sin planear. Ver "Ejecuciones viejas" abajo. Además guarda la huella (SHA-256)
   de `GCP_TFVARS_JSON`, `GCP_STAGE_SERVICE_ACCOUNTS` y `GCP_STATE_BUCKET` para compararla en el
   apply (§2).
1. Autenticación por Workload Identity Federation con `GCP_AUDIT_SERVICE_ACCOUNT` (`tf-read`).
2. `scripts/root-tfvars.py <raíz>`: `terraform.tfvars.example` → `terraform.tfvars`, y encima
   `zz-ci.auto.tfvars.json` con `common` + la llave de la raíz de `GCP_TFVARS_JSON`; igual que
   `pr.yml` y `drift.yml`. Sale con 2, sin escribir nada, si la raíz declara `project_id` y no
   llega, o si una variable que la raíz declara queda con un marcador de los ejemplos (§2).
3. `terraform init -backend-config="bucket=$GCP_STATE_BUCKET"`.
4. `terraform plan -lock=false -detailed-exitcode -out=tfplan` y `terraform show -json`.
   `-lock=false` porque `tf-read` solo tiene `storage.objectViewer` sobre el bucket y no puede
   escribir el candado; el plan no escribe estado.
5. Huella del plan: `scripts/plan-fingerprint.py` (SHA-256 de dirección, acciones, `after`,
   `after_unknown` y `after_sensitive` de cada cambio, y acciones de las salidas; no incluye el
   estado anterior ni la fecha). Además publica la variable `prefix` del plan (salida `prefix`,
   que usa `destroy.yml`).
6. `conftest test plan.json --policy policies`. Una denegación detiene la raíz y todo lo que
   viene después, antes de pedir aprobación.
7. Resumen del trabajo: resultado del plan y de Conftest, la línea `Plan:`, la huella y la lista
   de recursos con cambios (acción y dirección). Se ve en la página de la ejecución mientras el
   apply espera la aprobación; los valores están en el registro del trabajo.

**VERIFICAR** (`VERIFICAR-EN-APPLY` en `_terraform-root.yml`): que `tf-read` pueda leer
(refrescar) cada recurso de cada raíz, también secretos, llaves e IAM. Que `roles/viewer`
alcance es HYPOTHESIS del ADR 0029 §3. Un permiso que falte hace fallar el plan; no lo debilita.

**`apply <raíz>`** (en el entorno de la raíz, con la cuenta de la raíz; solo si el plan tiene
cambios):

1. El entorno aplica sus reglas antes de que el trabajo empiece (revisores en `common` y
   `prod`, ramas permitidas en los cuatro; §2 y §4). Sin cambios, el trabajo se omite: no hay
   pedido de aprobación.
2. Huella de las tres variables igual a la del trabajo `plan`; si no, falla antes de `init`
   con un mensaje que nombra el entorno (§2).
3. Autenticación por WIF con `fromJSON(GCP_STAGE_SERVICE_ACCOUNTS)[<llave>]`: la cuenta de la
   raíz, que solo acepta tokens de un trabajo de `main`, de un flujo del repositorio y de ese
   entorno de GitHub (`attribute.deploy`, ADR 0029 §3; HYPOTHESIS hasta la primera ejecución,
   §5).
4. `scripts/root-tfvars.py` e `init`, como en el plan, sobre el mismo commit. Vuelve a planear
   **con** el candado (`-lock-timeout=5m`) y calcula la huella del plan nuevo. Si el plan ya no
   tiene cambios o su huella no es la revisada (algo cambió entre el plan y la aprobación),
   falla sin aplicar nada: hay que volver a correr el flujo y revisar el plan nuevo.
5. Conftest sobre ese plan.
6. Otra vez `scripts/check-main-tip.sh "$GITHUB_SHA"`, justo antes del apply: `main` pudo
   cambiar el despliegue mientras se esperaba la aprobación.
7. `terraform apply -lock-timeout=5m tfplan`: el archivo que revisó Conftest en este mismo
   trabajo, cuyo contenido es el que se aprobó.

**VERIFICAR** (`VERIFICAR-EN-APPLY` en `_terraform-root.yml`): que el plan con `tf-read` y el
del apply con la cuenta de la raíz den la misma huella. Una fuente de datos que dependa de la
identidad (por ejemplo `google_client_openid_userinfo`) la cambiaría en cada ejecución: el
apply se detendría sin aplicar, nunca aplicaría algo no revisado.

**Ejecuciones viejas.** `github.sha` queda fijo en una ejecución: un "Re-run jobs" de una
ejecución anterior, o una aprobación que llega después de otro merge, planearía y aplicaría el
código de ese commit encima de lo que ya aplicó una ejecución más nueva. Regla de
`scripts/check-main-tip.sh`, en el trabajo `plan` y otra vez justo antes de `terraform apply`:

- `github.sha` está en `main` (si no, falla);
- ningún commit posterior de `main` cambia las rutas del despliegue: `gcp-datacenter/` y
  `.github/workflows/`, sin `gcp-datacenter/docs/` ni los `.md` de `gcp-datacenter/`
  (`DEPLOY_PATHS` del script). Si alguno lo hace, falla y lista esos commits. Un merge que no
  toca esas rutas (README de la raíz o de un módulo, `docs/`, `labs/`,
  `.github/dependabot.yml`) no detiene la ejecución en curso;
- el contenido de esas rutas en la punta de `main` es igual al de `github.sha` (`git diff`
  entre los dos árboles; si no, falla y lista los archivos). Cubre lo que el `git log` por rutas
  no ve: en un merge cuyo resultado en esas rutas es igual al de uno de sus padres, `git log`
  sigue solo a ese padre, así que un merge que descarta un cambio (resuelto a favor de la otra
  rama) no aparece en el listado aunque lo que se desplegaría ya es otro. Reproducido sin
  GitHub el 23 nov 2026 (`scripts/selftest.sh`, caso "un merge que descarta cambios de las
  rutas").

Son las mismas rutas con las que se dispara `apply.yml` (`paths` del `push`, con las exclusiones
`!gcp-datacenter/docs/**` y `!gcp-datacenter/**.md` al final; `selftest.sh` comprueba que los
dos eligen los mismos archivos). Que GitHub aplique así los patrones `!` es **VERIFICAR**: un
merge de solo documentación no debe disparar `apply.yml` (pendiente 144). Por eso un commit que
deja vieja a una ejecución siempre encola otra:
la `concurrency` `apply-gcp-datacenter` la deja esperando hasta que la vieja termine (o falle
por esta regla) y entonces planea y aplica desde `1-base` con el código nuevo.

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
con GCP que un segundo plan sin cambios reales en el medio da la misma huella en cada raíz
(pendiente 48).

**`dev / prueba de humo`** (`dev-smoke`, después de `dev-workloads`; qa depende de él): corre
`TestDevSmoke` (`tests/e2e/smoke_test.go`) con la cuenta `GCP_AUDIT_SERVICE_ACCOUNT` (`tf-read`,
que tiene `roles/networkmanagement.admin` para las Connectivity Tests, ADR 0029 §3). No aplica
nada: lee las salidas de `2-networks` (hub), `2-networks/envs/dev` y `3-workloads/envs/dev`
desde el bucket de estado y corre las Connectivity Tests de dev en el proyecto (dev → Cloud SQL
por IP privada, Internet → balanceador de dev en 443, dev → on-premises simulado). Falla si no
hay ninguna prueba expresable, si alguna no da lo esperado (se exige REACHABLE o UNREACHABLE;
UNDETERMINED, AMBIGUOUS o un paso `abort` fallan siempre), si no se puede leer una salida o
describir la instancia de Cloud SQL (una salida en null por un recurso deshabilitado solo omite
su prueba), o si la prueba se omite (máximo de omitidas 0 en `scripts/go-test-report.sh`). Solo
se salta en una ejecución manual con la entrada `omitir_prueba_de_humo = true`, que queda como
advertencia y en el resumen con el nombre de quien la pidió. **VERIFICAR** los permisos de
`tf-read` para la prueba (pendiente 50).

**Prueba de humo fuera de horario (ADR 0028).** Con `off_hours_shutdown` en dev, un merge que
llega con Cloud SQL detenida hace fallar la prueba dev → Cloud SQL con un mensaje que lo dice
(`sqlStoppedError` de `tests/e2e/connectivity_test.go`: `settings.activationPolicy = NEVER`; el
`state` sigue en `RUNNABLE`). La prueba no la enciende: la cuenta de lectura no puede, y
encenderla de noche la dejaría prendida hasta el siguiente apagado. qa espera, porque depende de
este trabajo. Para seguir:

1. Volver a correr el trabajo fallido ("Re-run failed jobs") después de la hora de encendido.
   `check-main-tip.sh` no lo impide mientras `main` no cambie las rutas del despliegue; si
   cambió, la ejecución nueva de ese merge lleva el cambio.
2. O encenderla antes: `gcloud scheduler jobs run <id>`, con el `id` de
   `job_ids["sql-primary-start"]` de la salida `off_hours_shutdown` de `3-workloads/envs/dev`,
   por una identidad con `cloudscheduler.jobs.run` en el proyecto. Después, volver a correr el
   trabajo. La instancia queda encendida hasta el siguiente apagado programado.
3. O, si qa no puede esperar, lanzar `apply.yml` a mano con `omitir_prueba_de_humo = true`
   (queda registrado).

Reglas:

- `0-bootstrap` no está en el pipeline: la aplica una persona, una vez y a mano
  ([runbook 01](runbooks/01-arranque-etapa-0.md)). Crea las nueve cuentas del pipeline, pero
  ninguna la aplica a ella.
- Los spokes se aplican de uno en uno porque los entornos van en serie (dev → qa → prod),
  también con entornos apagados: GCP no admite dos operaciones de peering a la vez sobre la
  VPC hub.
- `concurrency: apply-gcp-datacenter` sin cancelación: nunca corren dos `apply.yml` a la vez. Si
  llegan varios push mientras uno corre, GitHub deja en espera solo el más reciente y descarta
  los intermedios (el más reciente contiene sus cambios). Una ejecución que espera aprobación
  también retiene el grupo, así que conviene aprobar o rechazar pronto (las aprobaciones
  pendientes vencen a los 30 días, según la documentación de GitHub).
- Los trabajos de Terraform exigen `github.ref == refs/heads/main`: una ejecución manual desde
  otra rama no aplica nada. Esa condición está en el YAML, que una rama puede cambiar; la
  barrera que no depende del YAML es WIF, que solo entrega las cuentas que escriben a un trabajo
  con `ref = refs/heads/main` (§5).
- Cada raíz con cambios en `common` o `prod` pide su propia aprobación (hasta dos por entorno:
  `1-base` y el hub en `common`, el spoke y las cargas en `prod`), y la persona que aprueba ve
  antes el resumen del plan de esa raíz.

### 1.3 `drift.yml`

**Drift.** Para cada raíz de `scripts/affected-roots.sh --all` (los directorios de `stages/` con
`versions.tf`, salvo `0-bootstrap`) menos las de los entornos de `GCP_DISABLED_ENVS`
(`scripts/disabled-envs.py filter`; con `prod` u otro nombre, el flujo falla como `apply.yml`):
autenticación con `tf-read`, `scripts/root-tfvars.py` y plan con
`-detailed-exitcode -lock=false`. Sin candado, el plan no bloquea ni espera a un apply en curso.

- Código 0: nada.
- Código 2: abre una incidencia `Drift: <raíz>` con la etiqueta `drift` (la crea si no existe)
  o, si ya hay una abierta para esa raíz, reemplaza su cuerpo y agrega un comentario. El cuerpo
  lleva solo las direcciones de los recursos con cambios y la línea `Plan:`; nunca valores.
- Código 1: el trabajo falla.

La incidencia no se cierra sola cuando el drift desaparece: se cierra a mano al resolverlo.

El flujo corre a las 12:17 UTC (06:17 en Monterrey): con `off_hours_shutdown` (ADR 0028), dev
y qa están apagados en ese momento. Lo que cambian los trabajos de Cloud Scheduler (estado de
Cloud SQL y autoescalado de los pools de GKE) está en `ignore_changes` y el tamaño del MIG lo
decide su autoescalador, así que el apagado no da código 2. El plan muestra la advertencia
del `check "cloud_sql_encendida"`, que no cambia el código de salida. En cambio, una instancia
de Cloud SQL detenida donde el apagado no está permitido (prod, o dev y qa sin
`off_hours_shutdown`) hace fallar el plan (`postcondition` del módulo `cloud-sql`): el trabajo
de esa raíz termina en error (código 1), no en incidencia. Un trabajo de Cloud Scheduler
pausado a mano sí da código 2.

**Recursos no administrados** (`recursos no administrados (proyecto)`, un solo trabajo):
objetivo "cero recursos manuales, verificado con Cloud Asset Inventory". Toda la landing zone
está en un proyecto, así que se lista ese proyecto y se compara con los estados de todas las
raíces.

1. Con `GCP_AUDIT_SERVICE_ACCOUNT`, descarga todos los estados del bucket
   (`gs://$GCP_STATE_BUCKET/**/default.tfstate`) al directorio temporal del runner; llevan
   valores sensibles y no se suben como artefacto. Del estado de `0-bootstrap` toma las salidas
   `project_id` y `project_number`; si no están, falla.
2. Lista el proyecto con
   `gcloud asset search-all-resources --scope=projects/<ID> --format=json`.
3. `scripts/unmanaged-resources.py` compara cada recurso con los estados. Está administrado si
   es el proyecto mismo (lo crea una persona, ADR 0029 §1); si su nombre es igual al `id` o
   `self_link` de algún recurso de algún estado (con formas construidas para cuentas de
   servicio por ID único, APIs habilitadas y métricas de log, y cada `projects/<id>` llevado a
   `projects/<número>`); si es hijo de uno administrado (versiones de llaves, revisiones de
   Cloud Run, versiones de secretos, que se cargan a mano por diseño, ADR 0015); si es VM o
   disco de un MIG administrado; o si lo permite una regla de `scripts/unmanaged-allowlist.txt`
   (recursos que crean Google o GKE; de las APIs habilitadas, solo una lista cerrada de
   dependencias que ninguna raíz declara). Lo que queda se lista en el resumen y el trabajo
   falla.
4. Cobertura: es error (código 2, el trabajo falla) un listado vacío o mal formado (`[]`, `{}`,
   `{"results": []}`, elementos sin `name`), un listado que no trae el proyecto mismo (otro
   alcance, o hecho sin permisos) o uno que trae recursos de otro proyecto. Así "0 no
   administrados" solo sale de un listado del proyecto pedido.

Un recurso creado a mano no aparece en ningún plan, así que el drift no lo ve: por eso es un
trabajo aparte. Probado sin GCP con `scripts/testdata/unmanaged/` (`scripts/selftest.sh`).
**VERIFICAR** con el proyecto real (pendiente 49; `VERIFICAR-EN-APPLY` en `drift.yml` y en
`scripts/unmanaged-resources.py`): que Cloud Asset liste el proyecto mismo con
`--scope=projects/<ID>` (si no, el script sale con 2 en cada corrida), el formato de `name` que
devuelve para cada tipo y que la lista de permitidos cubra lo que crean GKE, los MIG y los
servicios administrados (la primera corrida probablemente marque recursos legítimos; se agregan
reglas con su motivo, nunca un tipo completo sin razón).

### 1.4 `terratest.yml`

`compile` (`compilar (go vet y go test -run XXX)`) corre siempre. `integration`
(`pruebas reales en GCP`) corre solo con `GCP_ENABLED = true` y si existe `tests/go.mod`:

- **Dónde corren.** Por defecto, todas en el proyecto único de pruebas `TERRATEST_PROJECT_ID`,
  con nombres únicos por corrida y la etiqueta `env=test`; cada prueba destruye lo que creó.
  Ese proyecto **no puede ser el de la landing zone**: el paso "El proyecto de pruebas no es el
  de la landing zone" (`scripts/terratest-project-check.py`) falla si `TERRATEST_PROJECT_ID` es
  igual a `common.project_id` de `GCP_TFVARS_JSON`, sin imprimir ninguno, y exporta
  `TERRATEST_LANDING_ZONE_PROJECT_ID` para que `tests/helpers` repita la comprobación en cada
  prueba. Si no puede comparar (falta uno de los dos), solo avisa. Con
  `TEST_EPHEMERAL_PROJECTS = true`, cada prueba crea y destruye su
  propio proyecto efímero, que necesita `TERRATEST_BILLING_ACCOUNT` y `TERRATEST_FOLDER_ID` o
  `TERRATEST_ORG_ID`. Que las cuotas de un solo proyecto alcancen para las pruebas en paralelo
  es `VERIFICAR-EN-APPLY` (`tests/helpers/project.go`).
- Nocturno y manual: todos los paquetes salvo `tests/e2e` (la prueba de extremo a extremo aplica
  0 → 3 y se lanza a mano).
- Etiqueta `modules/<módulo>/vX.Y.Z`: solo las pruebas de ese módulo, las que aplican
  `tests/fixtures/<módulo>` o una variante (`scripts/module-tests.sh`; para `firewall`,
  `TestFirewallNetwork`). Una etiqueta con otra forma hace fallar el trabajo. Las etiquetas no
  fijan versiones: las raíces consumen los módulos por ruta relativa.
- Las pruebas reciben como variables de entorno las `TERRATEST_*` y las `TEST_*` de §2 con el
  mismo nombre, y `GOOGLE_CLOUD_PROJECT = TERRATEST_PROJECT_ID`. Faltar
  `TERRATEST_SERVICE_ACCOUNT` o `TERRATEST_PROJECT_ID` (y, con proyectos efímeros, sus datos)
  hace fallar el trabajo antes de correr.
- `go test -json` pasa por `scripts/go-test-report.sh`: el resumen del trabajo lista cuántas
  pasaron, fallaron y se omitieron, y cada omitida con su motivo. El trabajo falla si alguna
  falló o si hay más omitidas que `TERRATEST_MAX_SKIPS` (0 si no se define). Con
  `TERRATEST_ORG_ID` vacío (proyecto sin organización), `TestOrg` y `TestVPCSC` se omiten con la
  marca `[sin-organizacion]` y esas omisiones no cuentan contra el máximo (pendiente 145). Sin
  las demás compuertas (`TEST_ALLOW_EXPENSIVE`, `TEST_ALLOW_ORG`) y sus datos, la corrida
  nocturna falla en rojo hasta que el equipo las configure o acepte las omisiones subiendo ese
  número a propósito.

### 1.5 `destroy.yml`

Desmonta las cargas de dev o qa y, a pedido, su spoke; es como se demuestra el criterio
"`destroy` de dev sin huérfanos" (pendiente 11). En el proyecto único no se borra ningún
proyecto: se destruye recurso por recurso (ADR 0029 §8). No hay otra forma: las raíces 1 a 3
solo las aplican sus cuentas, que solo se obtienen por WIF desde un trabajo de `main` en su
entorno de GitHub (§5), y las personas tienen solo lectura.

Se lanza a mano desde `main` (Actions → destroy → Run workflow, o
`gh workflow run destroy.yml --ref main -f entorno=dev -f confirmacion=dev`, con
`-f incluir_red=true` para incluir el spoke) con `GCP_ENABLED = true`. Entradas: `entorno`
(lista cerrada `dev`, `qa`), `confirmacion` (el nombre del entorno, escrito exactamente) e
`incluir_red` (`false` por defecto).

```
pedido de destrucción
  → <env> / destruir 3-workloads
  → <env> / destruir 2-networks          (solo con incluir_red = true)
  → <env> / huérfanos (Cloud Asset)
```

1. **`pedido de destrucción`**: `scripts/destroy-guard.sh pedido`. Falla si el entorno no es
   `dev` o `qa` (prod con un mensaje propio, también `PROD` o con espacios), si la confirmación no
   es exactamente el nombre del entorno, si la rama no es `main` o si `GCP_ENABLED` no es `true`
   (a diferencia de `apply.yml`, falla: se pidió destruir y no se destruiría nada). Deja en el
   resumen quién lo pidió, qué se destruye y qué se conserva.
2. **Una raíz por trabajo, en orden inverso al de `apply.yml`**: `3-workloads/envs/<env>`
   siempre y `2-networks/envs/<env>` solo con `incluir_red`. Cada una pasa por
   `_terraform-root.yml` con `destroy: true`: los mismos trabajos `plan` y `apply` de §1.2 (aquí
   `plan -destroy <raíz>`, con `tf-read`, y `destroy <raíz>`, con `tf-wl-<env>` o
   `tf-net-<env>` en el entorno de GitHub `dev` o `qa`), con estas diferencias:
   - `scripts/destroy-guard.sh raiz` en los dos trabajos, antes de autenticarse: solo
     `stages/3-workloads/envs/<entorno>` o `stages/2-networks/envs/<entorno>`, con entorno `dev`
     o `qa`. `0-bootstrap`, `1-base` y el hub no tienen destroy;
   - `terraform plan -destroy`, con el plan guardado, la huella y Conftest de siempre (las
     políticas aceptan un plan de destrucción: probado con los planes de
     `scripts/testdata/destroy/`);
   - `scripts/destroy-plan-check.py` sobre ese plan, en el trabajo `plan` (antes de la
     aprobación, con una tabla en el resumen) y otra vez en `destroy` (antes de
     `terraform apply`). Sale con 2 si alguna acción no es `delete` o no sabe el prefijo, con 1
     si hay un **bloqueo** (abajo) y con 0 con **avisos**;
   - el resumen se titula "Plan de DESTRUCCIÓN" y lista `delete <dirección>` de cada recurso;
   - `destroy <raíz>` compara las variables y la huella con las del plan revisado, repite
     `check-main-tip.sh` y aplica ese `tfplan`.

   Por qué el spoke solo a pedido: la conexión de Private Service Access puede tardar días en
   poder borrarse después de borrar Cloud SQL (HYPOTHESIS de la revisión, ADR 0029 §8;
   pendiente 87). Conviene destruir las cargas primero y la red en otra ejecución, días después.

   Una raíz ya destruida planea "sin cambios" y no pide aprobación ni aplica. Comprobado sin
   GCP el 23 nov 2026 con Terraform 1.16.5 y recursos integrados: con el estado vacío,
   `plan -destroy -detailed-exitcode` sale con 0 aunque la raíz de la que lee ya no tenga
   salidas; con recursos en el estado y la de arriba sin salidas, falla (por eso el orden
   inverso). Así, **volver a lanzar el flujo** retoma un destroy que falló a medias. "Re-run
   failed jobs" no sirve después de un destroy parcial: el trabajo `destroy` vuelve a planear,
   la huella ya no es la revisada y falla sin aplicar.
3. **`huérfanos`**, con `GCP_AUDIT_SERVICE_ACCOUNT` (`tf-read`: `storage.objectViewer` en el
   bucket de estado y `cloudasset.viewer` en el proyecto). Corre si las cargas se destruyeron y
   el spoke se destruyó o no se pidió. Descarga todos los estados, toma `project_id` y
   `project_number` del estado de `0-bootstrap`, lista el proyecto con
   `gcloud asset search-all-resources --scope=projects/<ID> --format=json` y
   `scripts/destroy-orphans.py` (con el `prefix` del plan de `3-workloads`) falla con la lista de
   lo que quede. Si quedan recursos, vuelve a listar hasta tres veces con cinco minutos entre
   intentos (HYPOTHESIS: el índice de Cloud Asset tarda en reflejar los borrados; la
   documentación no da un plazo).

   Un recurso es **del entorno** si tiene la etiqueta `env` igual al entorno o si su nombre, su
   `displayName` o su correo **contienen** `<prefix>-<env>-` en algún segmento (ADR 0029 §8). Así
   entran los restos que GKE nombra con el clúster (`gke-<prefix>-<env>-<app>-gke-…`). Los
   demás restos de GKE se asocian al entorno por la red o la subred del spoke, por la etiqueta
   con el nombre del clúster o por el namespace `<app>-<env>` (discos `pvc-*`, NEG y firewalls
   de Services). VPC, subredes, routers, políticas de firewall y cuentas de servicio no llevan
   etiquetas: se reconocen por el nombre. Lo demás del proyecto (lo compartido y lo de otros
   entornos) no se revisa. Un resto de GKE que no se puede atribuir a ningún entorno se lista
   como aviso (`AVISO-GKE`), para revisarlo a mano, y no hace fallar el trabajo.
   `destroy-plan-check.py`, que bloquea, sigue estricto (el nombre empieza con
   `<prefix>-<env>-`). De lo que es del entorno, es **esperado** (se lista en el resumen, no
   falla):
   - lo que conserva `1-base` a propósito: llaveros, llaves y versiones de Cloud KMS (no se
     pueden borrar), repositorios de Artifact Registry con sus imágenes y contenedores de
     secretos con sus versiones;
   - lo que todavía administra un estado (por ejemplo, el spoke cuando `incluir_red = false`);
   - un recurso en estado `DELETED`, `DELETE_REQUESTED` o `DELETE_IN_PROGRESS` (estados que la
     [referencia de searchAllResources](https://docs.cloud.google.com/asset-inventory/docs/reference/rest/v1/TopLevel/searchAllResources#ResourceSearchResult)
     lista);
   - una versión de llave de KMS `DESTROYED` o `DESTROY_SCHEDULED`.

   Todo lo demás es **huérfano** y el trabajo falla: un bucket, una VM o una cuenta de servicio
   del entorno que sobrevivieron al destroy (por ejemplo, con `deletion_policy = "ABANDON"`). Un
   listado vacío, sin el proyecto mismo o con recursos de otro proyecto sale con 2.
   **VERIFICAR** en el primer destroy de dev (pendientes 85, 140 y 141): que Cloud Asset
   devuelva `labels` y, para las cuentas de servicio, `additionalAttributes.email`, que liste el
   proyecto mismo, el formato con que nombra los restos de GKE y si el listado trae la red en
   `additionalAttributes` o en `versionedResources` (el flujo no pasa `--read-mask`).

**Contra un destroy de prod.** En el flujo, cuatro barreras independientes: la lista cerrada de
`entorno` (HYPOTHESIS: que GitHub rechace por API un valor fuera de `options`; la
[sintaxis de flujos](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
solo dice que el valor por defecto debe estar en la lista), `destroy-guard.sh pedido`, la
condición `inputs.entorno == 'dev' || inputs.entorno == 'qa'` de cada trabajo y
`destroy-guard.sh raiz` en los dos trabajos de cada raíz. Además, `destroy-plan-check.py`
detiene todo recurso cuyo nombre no lleve `<prefix>-<env>-` del entorno pedido, y en Terraform
prod exige `deletion_protection = true` en `3-workloads` (validación de la raíz), que el
proveedor respeta y `destroy-plan-check.py` detiene antes de borrar. Fuera del flujo, WIF no
entrega `tf-wl-prod` ni `tf-net-prod` a un trabajo que no sea de `main` (§5): un flujo de otra
rama que declare `prod` no obtiene esas cuentas. Sigue abierto lo de §5: un flujo que llegue a
`main` por un PR aprobado.

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
| `stages/3-workloads/envs/<env>` | `"deletion_protection": false` | `false` en dev y qa |
| `stages/2-networks/envs/<env>` | nada: el spoke no tiene protección contra borrado | — |

Si falta, el trabajo `plan -destroy` de la raíz falla en `destroy-plan-check.py` con un
**bloqueo** que nombra el recurso y la variable, antes de borrar nada.

**Bloqueos** de `destroy-plan-check.py` (sale con 1 antes de borrar):

- por protección, leída del estado: `deletion_protection = true` o
  `deletion_protection_enabled = true` (también en `settings` de Cloud SQL) en cualquier recurso,
  y `deletion_policy = "PREVENT"` en cualquier recurso;
- por alcance (protegen lo compartido del proyecto, ADR 0029 §4 y §8): `google_project`; un
  recurso que existe una vez por proyecto (APIs, metadatos, configuración de auditoría, Binary
  Authorization, sinks y buckets de logs, presupuesto, roles personalizados, políticas de
  organización, la cuenta de Compute por defecto, WIF, IAM de proyecto autoritativo…); y un
  recurso de GCP cuyo nombre no lleve `<prefix>-<env>-`. Los hijos que GCP nombra dentro de un
  padre (reglas de una política de firewall, valores de etiquetas, registros DNS, la conexión de
  PSA) pasan por el atributo que nombra al padre o porque el padre está en el mismo plan y pasó;
  un tablero de Monitoring se reconoce por el `displayName` de su `dashboard_json`.

Así pasan enteros los destroy reales sin GCP del spoke de dev (40 recursos) y de `3-workloads`
de dev (90 recursos), `scripts/testdata/destroy/plan-real-spoke-dev.json` y
`plan-real-workloads-dev.json` (`plan -destroy -refresh=false` sin conexión; los valores
calculados son IDs ficticios).

**Lo que el plan no ve (avisos) y qué hacer:**

| Caso | Qué pasa | Qué hacer |
|---|---|---|
| Bóveda de Backup and DR con respaldos (`enable_backup = true`, retención forzada de 30 días en `stages/3-workloads/envs/*/operations.tf`) | Según la [documentación de la bóveda](https://docs.cloud.google.com/backup-disaster-recovery/docs/concepts/backup-vault), ningún respaldo se borra antes de la retención forzada y, desde el 1 nov 2026, Backup and DR pone un gravamen (lien) en el proyecto que los tenga. El destroy de `3-workloads` borra lo demás (incluida la asociación, que deja de crear respaldos) y falla en la bóveda | Para la prueba de destroy, desplegar dev con `"enable_backup": false`. Con respaldos: esperar a que venzan y volver a lanzar; puede seguir fallando sin `ignore_inactive_datasources` (pendiente 86) |
| Conexión de Private Service Access (solo con `incluir_red`) | Según la [documentación de PSA](https://docs.cloud.google.com/vpc/docs/configure-private-services-access), después de borrar una instancia de Cloud SQL el servicio espera cuatro días antes de liberar sus recursos y la conexión no se borra mientras tanto | `2-networks` falla; volver a lanzar `destroy.yml` con `incluir_red = true` pasados cuatro días (`3-workloads` se salta) (pendiente 87) |
| Bucket de la aplicación sin `force_destroy` | Si tiene objetos, el borrado falla | Pendiente 89 |
| `deletion_policy = "ABANDON"` | Terraform lo suelta y queda en GCP | La búsqueda de huérfanos lo ve si es del entorno |

**Después del destroy.**

- **El siguiente `apply.yml` vuelve a crear lo destruido**: cualquier push a `main` que toque
  las rutas del despliegue, o una ejecución manual. Para que no lo haga, agregar el entorno a
  `GCP_DISABLED_ENVS` (por ejemplo `dev` o `dev,qa`; §1.2) antes del siguiente push, o poner
  `GCP_ENABLED` a otro valor si no se quiere aplicar nada
  ([guía del colaborador](guia-colaborador-gcp.md), sección I). Con el entorno en
  `GCP_DISABLED_ENVS`, `drift.yml` tampoco lo planea.
- **Lo que queda a propósito** (llaves, repositorios y contenedores de secretos del entorno en
  `1-base`) se reutiliza al recrear: no hay IDs de proyecto que cambiar.
- **Nombre de Cloud SQL.** El nombre de una instancia borrada no se puede reutilizar de
  inmediato (HYPOTHESIS: hasta una semana; README de `stages/3-workloads/envs/dev`). Para
  recrear el entorno poco después, cambiar `sql_instance_name` (por ejemplo a `sql2`) en la
  llave `stages/3-workloads/envs/<env>` de `GCP_TFVARS_JSON`.
- **Sin `GCP_DISABLED_ENVS`, `drift.yml` se queja hasta recrear el entorno**: las raíces
  destruidas planean todo como creación (incidencias `Drift: …`) y la de `3-workloads` puede
  fallar al leer salidas del spoke que ya no existen (con `incluir_red`). Se cierran a mano.

Probado sin GCP (`bash scripts/selftest.sh` desde `gcp-datacenter/`, 24 nov 2026: 218 líneas
`OK`, 0 `FALLA`, en todo el script): rechazos de `destroy-guard.sh` (prod, mayúsculas,
espacios, confirmación distinta, otra rama, raíz de otro entorno, el hub, `1-base`,
`0-bootstrap`, `..` y etapas que ya no existen), los bloqueos y avisos de
`destroy-plan-check.py` sobre los dos planes reales de destrucción de dev y sobre un plan con
protecciones y recursos ajenos al entorno, la huella de dos planes de destrucción reales del
mismo estado, la clasificación de `destroy-orphans.py` (con restos de GKE de ejemplo) y la
estructura de `destroy.yml` y del modo destroy de `_terraform-root.yml`. **VERIFICAR** en el
primer destroy de dev (pendiente 85).

## 2. Variables, secretos y entornos que crea el equipo

En Settings → Secrets and variables → Actions → **Variables** (de repositorio). Ninguna es
secreta: son nombres e identificadores, no credenciales. No hay llaves de cuenta de servicio
en ningún lado.

| Variable | Contenido | Ejemplo (marcador) |
|---|---|---|
| `GCP_ENABLED` | `true` activa los trabajos que tocan GCP; cualquier otro valor o ausente los omite | `true` |
| `GCP_DISABLED_ENVS` | Opcional. Entornos apagados, separados por comas: sus raíces no se planean ni se aplican en `apply.yml` ni se planean en `drift.yml` (§1.2). Solo `dev` y `qa`; con `prod` u otro nombre, `scripts/disabled-envs.py` sale con 2 y el flujo falla. Vacía o sin definir: ninguno | `dev,qa` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Salida `workload_identity_provider` de `0-bootstrap` | `projects/<número-del-proyecto>/locations/global/workloadIdentityPools/<pool>/providers/<proveedor>` |
| `GCP_STAGE_SERVICE_ACCOUNTS` | Salida `stage_service_accounts` de `0-bootstrap`, en JSON: las ocho cuentas que aplican, por llave de raíz. Solo los trabajos `apply` de `apply.yml` y `destroy.yml` se autentican con ellas | `{"1-base": "<prefix>-tf-base@<proyecto>.iam.gserviceaccount.com", "2-networks": "<prefix>-tf-net@…", "2-networks/dev": "<prefix>-tf-net-dev@…", "2-networks/qa": "…", "2-networks/prod": "…", "3-workloads/dev": "<prefix>-tf-wl-dev@…", "3-workloads/qa": "…", "3-workloads/prod": "…"}` |
| `GCP_AUDIT_SERVICE_ACCOUNT` | Salida `read_service_account` de `0-bootstrap`: la cuenta de solo lectura `tf-read`. La usan los `plan` de `pr.yml`, `apply.yml` y `destroy.yml`, `drift.yml`, la prueba de humo y la búsqueda de huérfanos | `<prefix>-tf-read@<proyecto>.iam.gserviceaccount.com` |
| `GCP_STATE_BUCKET` | Salida `state_bucket` de `0-bootstrap` | `<prefix>-bootstrap-ops-tfstate` |
| `GCP_TFVARS_JSON` | Valores de las variables por raíz, en JSON. Para cada raíz, `scripts/root-tfvars.py` combina `common` y la llave de la raíz (gana la raíz) y los sobrepone a `terraform.tfvars.example`. **`common.project_id` es obligatorio**: las ocho raíces del pipeline declaran `project_id`. `root-tfvars.py` sale con 2, sin escribir nada y sin que corra el plan, si falta `project_id` o si alguna variable que la raíz declara queda con un marcador de los ejemplos (abajo). Las variables de organización (`org_id`, `access_policy_id`, `directory_customer_id`) no van aquí: son de `0-bootstrap` | `{"common": {"project_id": "<proyecto>", "state_bucket": "<bucket>"}, "stages/1-base": {"groups": {…}, "essential_contacts": {…}}, "stages/3-workloads/envs/prod": {…}}` |
| `TERRATEST_SERVICE_ACCOUNT` | Cuenta de servicio de las pruebas de integración (no es del pipeline; ver §3) | `<cuenta>@<proyecto-de-pruebas>.iam.gserviceaccount.com` |
| `TERRATEST_PROJECT_ID` | Proyecto único de pruebas, donde corren todas por defecto. Distinto del de la landing zone: si es igual a `common.project_id`, `terratest.yml` falla antes de correr (§1.4) | `<proyecto-de-pruebas>` |
| `TEST_EPHEMERAL_PROJECTS` | `true`: un proyecto efímero por prueba en vez del proyecto único (opcional) | — |
| `TERRATEST_BILLING_ACCOUNT` | Cuenta de facturación de los proyectos efímeros (solo con `TEST_EPHEMERAL_PROJECTS`) | `<XXXXXX-XXXXXX-XXXXXX>` |
| `TERRATEST_ORG_ID` | ID numérico de la organización: proyectos efímeros sin `TERRATEST_FOLDER_ID` y pruebas de organización (opcional). Vacía: `TestOrg` y `TestVPCSC` se omiten con `[sin-organizacion]` sin contar contra `TERRATEST_MAX_SKIPS` | `<org_id>` |
| `TERRATEST_FOLDER_ID` | Carpeta de GCP donde se crean los proyectos efímeros (opcional) | `<folder_id>` |
| `TERRATEST_MAX_SKIPS` | Máximo de pruebas omitidas que acepta `terratest.yml` (por defecto 0) | `0` |
| `TEST_ALLOW_EXPENSIVE`, `TEST_ALLOW_ORG` | Compuertas de las pruebas caras y de organización (`tests/README.md`) | `true` |
| `TEST_DIRECTORY_CUSTOMER_ID`, `TEST_ACCESS_POLICY_ID`, `TEST_NOTIFICATION_EMAIL`, `TEST_GKE_SECURITY_GROUP` | Datos que piden `TestOrg`, `TestVPCSC`, `TestObservability` y `TestAuditAlerts`, y `TestGKE` | `C0xxxxxxx`, `<número>`, `<buzón>`, `gke-security-groups@<dominio>` |
| `TEST_MIG_IMAGE`, `TEST_CLOUD_RUN_IMAGE`, `TEST_LB_DOMAIN`, `TEST_REGION`, `TEST_DR_REGION` | Ajustes opcionales de las pruebas (tienen valor por defecto) | — |

`GCP_TFVARS_JSON` tiene que llevar todos los valores reales: lo que no traiga se toma de
`terraform.tfvars.example`, que solo tiene valores de ejemplo. Una llave de `common` que una raíz
no declara (por ejemplo `state_bucket` en el hub, que no lee estados) llega igual a su
`zz-ci.auto.tfvars.json`.

**Marcadores de los ejemplos.** `scripts/root-tfvars.py` revisa el valor resuelto de cada
variable que la raíz declara (el del JSON si la variable está en `common` o en la llave de la
raíz; si no, el de `terraform.tfvars.example` sin comentarios) y sale con 2 si lleva un
marcador: dominios `example.com`, `example.net` o `example.org`; nombres `example-…`;
`REEMPLAZAR`; un texto entre `< >` como `<proyecto>`; o un ID de solo ceros. El mensaje nombra
la variable, de dónde vino y el marcador, nunca el valor. Una variable con marcador hay que
ponerla en `GCP_TFVARS_JSON` aunque su función esté apagada (por ejemplo `cloud_run_image` con
`enable_cloud_run = false`): la revisión no mira los interruptores.

Variables que hoy llevan marcador en los ejemplos, y que por eso `GCP_TFVARS_JSON` tiene que
traer con valores reales. Sacadas el 24 nov 2026 con
`TFVARS_JSON='{"common":{"project_id":"mi-proyecto-real"}}' python3 scripts/root-tfvars.py <raíz>`
sobre una copia del repositorio, raíz por raíz:

| Llave de `GCP_TFVARS_JSON` | Variables con marcador |
|---|---|
| `common` | `project_id` (obligatorio). Además `state_bucket` (salida de 0-bootstrap) y `prefix` si la etapa 0 usó otro: sus ejemplos no llevan marcador, pero solo coinciden con `prefix = "bnt"` sin `name_suffix` |
| `stages/1-base` | `security_alert_email`, `essential_contacts`, `groups` |
| `stages/2-networks` y `stages/2-networks/envs/<env>` | `labels`, `onprem_dns_domain` |
| `stages/3-workloads/envs/dev` | `cloud_run_image`, `domain_names`, `notification_emails` |
| `stages/3-workloads/envs/qa` | las de dev y `mig_image` |
| `stages/3-workloads/envs/prod` | las de qa, `gke_authenticator_security_group` e `internal_domain_names` |

Otras variables no llevan marcador pero conviene revisarlas: `secret_names`,
`artifact_registry_publishers` y `operations_alert_email` de `1-base`;
`gke_master_authorized_networks` de prod. Un `project_id` distinto del de 0-bootstrap detiene el
plan de `1-base` (precondición). Lo que diga la API de GCP de un valor real es HIPÓTESIS hasta el
primer apply (pendiente 55).

No poner `labels` en `common`: cada raíz valida las suyas (en `3-workloads`, `labels.app` tiene
que ser igual a `application`) y `common` las pisaría en todas.

**Primera ejecución: sin imágenes todavía.** El repositorio de Artifact Registry de cada
entorno y aplicación lo crea `1-base` en la misma ejecución que después aplica
`3-workloads/envs/<env>`, así que en la primera ejecución no puede haber una imagen publicada.
Los ejemplos de dev, qa y prod traen `enable_cloud_run = true` (y qa y prod, `enable_mig = true`
con una imagen de ejemplo). Para la primera ejecución, en la llave de cada raíz de
`3-workloads`: `enable_cloud_run = false` y `enable_mig = false`; en prod, además,
`enable_internal_lb = false` (el balanceador interno exige un backend `mig` o `run`) y
`enable_gke = false` mientras no exista el grupo `gke-security-groups@<dominio>`. Con todo el
cómputo apagado la raíz sigue planeando: datos, observabilidad y respaldo, sin balanceadores
(pruebas `primera_ejecucion_sin_computo` y `prod_primera_ejecucion_sin_computo` de
`stages/3-workloads/envs/*/tests/`, con proveedores simulados). Después, el runbook
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

**Entornos** (Settings → Environments): `common`, `dev`, `qa` y `prod`. Los trabajos `apply` se
ligan a ellos, y cada cuenta que escribe solo acepta tokens de un trabajo de `main`, de un flujo
del repositorio y de su entorno (§5): el entorno decide qué cuenta obtiene un trabajo de `main`,
y sus revisores, si la aplica sin aprobación. GitHub crea un entorno sin reglas la primera vez
que un trabajo lo usa, así que hay que crearlos y protegerlos **antes** de poner
`GCP_ENABLED = true`.

| Entorno | Lo usan | Cuentas que obtiene | Reglas |
|---|---|---|---|
| `common` | apply de `1-base` y del hub | `tf-base`, `tf-net` | **Required reviewers** (seguridad y plataforma), "Prevent self-review" y "Deployment branches: `main`" |
| `dev` | apply de las raíces de dev; destroy de dev (`destroy.yml`) | `tf-net-dev`, `tf-wl-dev` | Sin revisores (automático); "Deployment branches: `main`" |
| `qa` | apply de las raíces de qa; destroy de qa (`destroy.yml`) | `tf-net-qa`, `tf-wl-qa` | Sin revisores; "Deployment branches: `main`". Con dev encendido, el apply corre solo después de dev y de la prueba de humo de dev |
| `prod` | apply de las raíces de prod | `tf-net-prod`, `tf-wl-prod` | **Required reviewers** con dos revisores, "Prevent self-review" y "Deployment branches: `main`" |

"Deployment branches: `main`" es la segunda barrera: la primera es WIF, que ya exige
`ref = refs/heads/main` (§5).

Los trabajos `plan`, la prueba de humo, `drift.yml` y la búsqueda de huérfanos no usan entorno:
corren con `tf-read`, antes de la aprobación en el caso del plan, para que se vea lo que se
aprueba.

## 3. Cómo se enciende GCP

1. Una persona crea el proyecto y lo liga a una cuenta de facturación de pago, borra la red
   `default`, revisa las cuotas y aplica `0-bootstrap` con la migración del estado al bucket
   ([runbook 01](runbooks/01-arranque-etapa-0.md); comandos en el
   [README de `gcp-datacenter`](../README.md)).
   `0-bootstrap` crea las nueve cuentas del pipeline, incluida `tf-read`, sus roles, su acceso
   al estado y WIF: no hay cuentas del pipeline que crear a mano. Con organización, las
   variables `org_id`, `access_policy_id` y `directory_customer_id` van en el
   `terraform.tfvars` de `0-bootstrap` (no en `GCP_TFVARS_JSON`), y esa misma persona aplica
   las políticas de organización y el perímetro de VPC-SC en dry-run: ninguna cuenta del
   pipeline tiene roles de organización.
2. Carga sus salidas como variables de repositorio (§2):
   - `GCP_WORKLOAD_IDENTITY_PROVIDER` ← `workload_identity_provider`;
   - `GCP_STAGE_SERVICE_ACCOUNTS` ← `stage_service_accounts`
     (`terraform output -json stage_service_accounts`);
   - `GCP_AUDIT_SERVICE_ACCOUNT` ← `read_service_account`;
   - `GCP_STATE_BUCKET` ← `state_bucket`;

   y escribe `GCP_TFVARS_JSON` con `common.project_id` (salida `project_id`) y los valores
   reales de §2.
3. Crea los entornos `common`, `dev`, `qa` y `prod` con sus reglas (§2 y §4). Sin `common`,
   `1-base` y el hub no pueden tomar sus cuentas.
4. Pone `GCP_ENABLED = true`. Desde ese momento:
   - `pr.yml` planea con `tf-read` las raíces afectadas por cada PR y comenta el resultado;
   - el siguiente push a `main` (o una ejecución manual de `apply`) planea y aplica de `1-base`
     a las cargas de prod, pidiendo aprobación en `common` y `prod` donde haya cambios;
   - `drift.yml` corre cada día.

   `tf-read` ya tiene desde `0-bootstrap` todo lo que usan el plan, la prueba de humo, el drift y
   la búsqueda de huérfanos: `roles/viewer`, `roles/iam.securityReviewer`,
   `roles/cloudasset.viewer`, `roles/networkmanagement.admin` y
   `roles/serviceusage.serviceUsageConsumer` en el proyecto, y `roles/storage.objectViewer` en
   el bucket de estado. Las APIs `cloudasset` y `networkmanagement` también las habilita
   `0-bootstrap`. Que esos roles alcancen es HYPOTHESIS (`VERIFICAR-EN-APPLY` en
   `stages/0-bootstrap/service_accounts.tf`; pendiente 50); si falta uno, se agrega en
   `0-bootstrap`, nunca en una raíz.
5. Para las pruebas reales de Terratest: crear a mano la cuenta `TERRATEST_SERVICE_ACCOUNT`
   (`0-bootstrap` no la crea), darle `roles/iam.workloadIdentityUser` al `principalSet` del
   repositorio en el pool de `0-bootstrap`
   (`principalSet://…/attribute.repository_id/<id-del-repositorio>`, el mismo de `tf-read`,
   porque `terratest.yml` no usa entorno) y los roles que pide `tests/README.md` en el proyecto
   de pruebas (con proyectos efímeros, además permiso para crearlos y `billing.user` en la
   cuenta de facturación). Después, las variables `TERRATEST_*` y `TEST_*`.

Para apagarlo, `GCP_ENABLED` a cualquier otro valor: los trabajos de GCP vuelven a omitirse y
los flujos terminan en verde (`plan-gate` pasa). Para dejar fuera solo dev o qa (por ejemplo
después de destruirlos con `destroy.yml`), `GCP_DISABLED_ENVS` (§1.2).

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
   - `go (vet y pruebas sin GCP)` (trabajo nuevo: la persona que administra el repositorio lo
     agrega a la regla; mientras no lo haga, un PR que rompa las pruebas de Go no se bloquea)
   - `plan-gate`

   Estos nombres no dependen del PR; si se cambia uno en el flujo, hay que cambiarlo también
   aquí y en la regla de GitHub. `pr.yml` corre con cualquier PR, también de solo
   documentación, para que las comprobaciones obligatorias siempre se reporten.

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
   (GitHub lee `CODEOWNERS` de la rama base): seguridad es dueña de `/.github/`, `scripts/`,
   `policies/`, `stages/0-bootstrap/`, `stages/1-base/`, `.checkov.yaml`, `.tflint.hcl` y
   `tests/e2e/` (la prueba de humo antes de qa); red, de `stages/2-networks/` y los módulos de
   red; plataforma, del resto (`3-workloads` incluida). Sin las dos opciones de aprobación de
   arriba, un commit subido después de la aprobación de seguridad entraría sin revisión nueva.

   **Guía de revisión:** quien revisa un PR mira también los `#checkov:skip=` y
   `# tflint-ignore` en línea de los `.tf` (no pasan por un archivo con dueño de seguridad):
   cada uno con su motivo, y uno nuevo es motivo para pedir la revisión de seguridad.
2. **Revisores de los entornos `common` y `prod`** (Settings → Environments → Required
   reviewers). Según la documentación de GitHub, basta con que **uno** de los revisores listados
   apruebe; la regla no cuenta aprobaciones. La aprobación de dos personas la da la protección
   de `main` (dos aprobaciones del PR); el entorno agrega una aprobación por raíz con cambios,
   con el plan a la vista. **Verificar** este comportamiento en la configuración real.
3. **"Deployment branches: `main`" en los cuatro entornos** (Settings → Environments →
   Deployment branches and tags). Es la **segunda barrera**: WIF ya solo entrega las cuentas que
   escriben a un trabajo con `ref = refs/heads/main` (§5). Si el mapeo de WIF no se comporta
   como se espera (pendientes 123 y 124), esta regla es la que impide que un trabajo de otra
   rama que declare el entorno obtenga sus cuentas; en `dev` y `qa`, que no tienen revisores,
   no hay otra. Que GitHub no deje correr ese trabajo desde otra rama es HIPÓTESIS hasta
   comprobarlo en la configuración real (pendientes 12 y 121).
4. **Plan de GitHub.** Según la documentación de GitHub (no comprobado aquí): en repositorios
   públicos, protección de rama, entornos y revisores obligatorios están en todos los planes;
   en repositorios privados, la protección de rama exige GitHub Pro, Team o Enterprise, y los
   revisores obligatorios de un entorno, GitHub Enterprise. **Hay que verificarlo** con el plan
   del equipo antes de contar con estos controles (pendiente 12 del primer apply). Sin
   revisores obligatorios, `common` y `prod` se aplicarían sin aprobación.

## 5. WIF de escritura solo desde `main` y desde los flujos del repositorio

Documentado en el README de `stages/0-bootstrap` y en el ADR 0029 §3 (antes, ADR
[0023](adr/0023-endurecimiento-de-la-identidad-del-pipeline.md)). El proveedor de WIF
(`stages/0-bootstrap/wif.tf`) acepta solo tokens con `assertion.repository_id == <id>` y
`assertion.repository_owner_id == <id>` (IDs numéricos: un repositorio borrado y vuelto a crear
con el mismo nombre no hereda la confianza). Las cuentas que escriben se atan al atributo
`attribute.deploy`, que el proveedor calcula así:

```
('environment' in assertion
 && assertion.ref == 'refs/heads/main'
 && 'job_workflow_ref' in assertion
 && assertion.job_workflow_ref.startsWith('<github_repository>/.github/workflows/'))
 ? assertion.environment : 'none'
```

Es decir: el entorno de GitHub del trabajo, solo si la ejecución es de `main` y el trabajo viene
de un flujo reutilizable de `.github/workflows/` de este mismo repositorio; en cualquier otro
caso, `none`, que ninguna cuenta acepta. Las afirmaciones que el token puede no traer se leen
solo después de comprobar que están: un mapeo que falla dejaría sin token también a `tf-read`.
Cada cuenta da `roles/iam.workloadIdentityUser` a un `principalSet` distinto
(`stages/0-bootstrap/service_accounts.tf`):

| Cuenta | `principalSet` | La obtiene |
|---|---|---|
| `tf-base`, `tf-net` | `…/attribute.deploy/common` | un trabajo de `main`, de un flujo del repositorio, en el entorno `common` |
| `tf-net-<env>`, `tf-wl-<env>` | `…/attribute.deploy/<env>` | igual, en el entorno `<env>` |
| `tf-read` | `…/attribute.repository_id/<id>` | cualquier trabajo del repositorio, de cualquier rama |

Todos los trabajos que escriben son el trabajo `apply` de `_terraform-root.yml`, que `apply.yml`
y `destroy.yml` llaman como flujo reutilizable desde `main`. Lo que el diseño resuelve:

- un trabajo sin entorno de GitHub (el `plan` de `_terraform-root.yml`, `pr.yml`, `drift.yml`,
  la prueba de humo) solo obtiene `tf-read`, que no escribe;
- un trabajo de `dev` no obtiene las cuentas de `prod`, ni al revés;
- una rama que trae su propio flujo con `environment: prod` no obtiene las cuentas de prod,
  aunque cambie la condición `github.ref == refs/heads/main` del YAML: su `ref` no es `main`.
  "Deployment branches: `main`" queda como segunda barrera (§4; pendiente 121).

**HYPOTHESIS** hasta la primera ejecución (`VERIFICAR-EN-APPLY` en `stages/0-bootstrap/wif.tf`):
que el trabajo `apply` de `_terraform-root.yml` llamado desde `main` traiga `job_workflow_ref`
con el valor esperado (`<dueño>/<repo>/.github/workflows/_terraform-root.yml@refs/heads/main`)
y obtenga `attribute.deploy` igual a su entorno (pendiente 123); y que un trabajo sin entorno o
fuera de `main` obtenga `tf-read` con `attribute.deploy = none` sin que falle el mapeo
(pendiente 124). El nombre del repositorio se compara tal cual: si se renombra, todas las
cuentas que escriben quedan en `none` hasta volver a aplicar `0-bootstrap` con el nombre nuevo.

Lo que sigue abierto:

- **Quien fusiona a `main` decide el flujo.** Un flujo nuevo o cambiado en `main` que declare un
  entorno obtiene las cuentas de ese entorno. Entrar a `main` exige el PR revisado (§4):
  `CODEOWNERS` pone `.github/`, `stages/0-bootstrap/`, `stages/1-base/`, `scripts/`,
  `policies/`, `.checkov.yaml`, `.tflint.hcl` y `tests/e2e/` a cargo de seguridad. Conviene
  limitar quién tiene permiso de escritura en el repositorio.
- **Lo que alcanza una cuenta de entorno.** `tf-wl-<env>` tiene los roles de Compute, GKE, Cloud
  Run, Cloud SQL, Memorystore y Filestore sin condición, y `tf-net-<env>` los de red: la cuenta
  de dev puede, técnicamente, cambiar recursos de prod de esos servicios (riesgo aceptado,
  ADR 0029 §3 y §9).
- **`tf-read` la obtiene cualquier rama.** Es de solo lectura, pero lee todo el bucket de
  estado, y los estados llevan valores sensibles (por ejemplo, el secreto compartido de la VPN
  simulada solo existe en el estado del hub, README de `stages/2-networks`; pendiente 122).

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
