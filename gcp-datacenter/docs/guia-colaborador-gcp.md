# Guía para desplegar y probar el proyecto en GCP

Para la persona del equipo que tiene la cuenta de Google Cloud. Es el camino completo **desde
crear el proyecto**: herramientas, `0-bootstrap` a mano, GitHub, una rebanada vertical primero,
el resto del despliegue, cómo registrar lo comprobado y cómo apagar todo al terminar. Se puede
seguir a mano o con Claude Code (al final está el prompt).

Toda la landing zone vive en **un solo proyecto** de GCP
(ADR [0029](adr/0029-un-solo-proyecto.md)). No hace falta organización ni dominio: basta una
cuenta de Google con facturación de pago. El diseño anterior, de varios proyectos, está en la rama
`archivo/multiproyecto`.

**Estado de partida:** el código está construido y pasa las revisiones que corren sin GCP.
**Nada se ha desplegado nunca.** El primer despliegue es una prueba: es normal que algo falle.
Cada falla es un hallazgo que se anota y se corrige, no un error tuyo.

**Antes de empezar:**

- **Cuesta dinero.** Según [`estimacion-de-costos.md`](estimacion-de-costos.md) (precios de lista
  del 23 nov 2026, calculados sobre el diseño anterior), el despliegue mínimo cuesta **20.44 a
  21.91 USD por día** con los tres entornos, o **7.93 a 8.66 USD por día** solo con dev
  (escenario B). Con un solo proyecto puede cambiar: la cifra nueva sale de Infracost en los PR o
  de la factura real. Lo que más pesa en
  una prueba corta es lo fijo: Cloud SQL, los túneles de VPN y el balanceador con Cloud Armor.
  `0-bootstrap` crea un presupuesto con alertas (`budget_amount`). Apaga todo al terminar
  (sección I).
- **El repositorio es privado y debe seguir así.** Nunca subas `terraform.tfvars`, estados
  (`*.tfstate`), llaves JSON, el JSON de `GCP_TFVARS_JSON` ni contraseñas. El `.gitignore` ya los
  excluye; no lo cambies. Revisa `git status` antes de cada commit.
- **Nada de recursos a mano** fuera de lo que piden esta guía y el runbook 01 (el proyecto, la red
  `default`, las APIs mínimas, `0-bootstrap`, SCC y la imagen de prueba). Todo lo demás lo crea el
  pipeline; el trabajo de recursos no administrados de `drift.yml` encuentra lo que sobre.
- **Cada cambio en GCP o en GitHub** (apply, destroy, IAM, variables, lanzar flujos) se decide
  viendo antes su costo y su efecto.

Documentos que vas a usar (rutas relativas a `gcp-datacenter/`):

| Documento | Para qué |
|---|---|
| [`docs/runbooks/01-arranque-etapa-0.md`](runbooks/01-arranque-etapa-0.md) | Procedimiento exacto del proyecto y de `0-bootstrap`. Es la fuente de verdad; esta guía no repite sus comandos |
| [`docs/diagramas/`](diagramas/01-organizacion-gobierno-acceso.md) | Cinco diagramas del diseño, con su explicación |
| [`docs/pendientes-apply.md`](pendientes-apply.md) | Lo que solo un despliegue real puede confirmar: tu lista de pruebas |
| [`docs/runbooks/`](runbooks/02-alta-proyecto-aplicacion.md) | Alta de una aplicación (02), llaves (03), DR (04) y drift (05) |
| [`docs/backlog.md`](backlog.md) | Lo que falta para terminar el proyecto |
| [`docs/plan-presentacion-final.md`](plan-presentacion-final.md) §2 | Guion del video y qué no mostrar (sección J) |

---

## A. Crear el proyecto (sin organización)

1. **Cuenta de facturación de pago.** Según Google, con la prueba gratuita no se pueden pedir
   aumentos de cuota ([funciones de la prueba gratuita](https://docs.cloud.google.com/free/docs/free-cloud-features)),
   y los tres entornos comparten las cuotas de un solo proyecto (ADR 0029 §10).
2. **El proyecto.** Lo creas tú, con la consola o con `gcloud`, y lo ligas a esa facturación:
   [runbook 01](runbooks/01-arranque-etapa-0.md), paso 1. Ninguna raíz de Terraform lo crea ni lo
   borra. Tu cuenta queda como `owner`: eres la única persona con permisos de escritura; todos los
   demás leen.
3. **El primer día:** cuotas (paso 2), red `default` (paso 3) y APIs mínimas (paso 4) del mismo
   runbook. Pide los aumentos de cuota que hagan falta en cuanto los veas: tardan.

**Si existe una organización** (dominio con Cloud Identity), aprovéchala así:

| Qué cambia | Dónde |
|---|---|
| El proyecto se crea dentro de la organización | runbook 01, paso 1 (`--organization`) |
| `org_id` y, si hay política de Access Context Manager, `access_policy_id` | `0-bootstrap` y la llave `stages/1-base` de `GCP_TFVARS_JSON` |
| `1-base` aplica las políticas de organización al proyecto y el perímetro de VPC-SC en dry-run | `stages/1-base/org.tf` |
| `directory_customer_id` para la política de dominios | llave `stages/1-base` |
| Grupos de Cloud Identity para las personas (`groups`: `readers`, `security_admins`, `auditors`) | llave `stages/1-base` |
| Controles del CIS de Cloud Identity (grupo 2) | runbook 01, "Controles manuales del CIS" |

Con organización, quien aplica `0-bootstrap` necesita además poder dar
`roles/orgpolicy.policyAdmin` en la organización y, con `access_policy_id`,
`roles/accesscontextmanager.policyAdmin` (`stages/0-bootstrap/README.md`). Sin organización,
nada de esto existe: lo cubren las reglas de Conftest y los pasos manuales del runbook 01.

## B. Herramientas y acceso al repositorio

1. El dueño del repositorio te agrega como colaborador (GitHub → Settings → Collaborators). Si no
   tienes permiso para algo de Settings (entornos, protección de `main`), pídeselo a él.
2. Instala Git (en Windows, con Git Bash), **Terraform 1.16.5** (la versión del pipeline; mínimo
   1.11, ADR 0021), Google Cloud CLI, GitHub CLI, `jq`, Python 3 y Docker (para la imagen de la
   sección E). Para las revisiones locales, también TFLint, checkov, Conftest y terraform-docs
   (versiones en el README).
3. Clona el repositorio y trabaja en una rama de verificación:

   ```bash
   gh auth login
   gh repo clone <dueño>/<repositorio>
   cd <repositorio>
   git checkout -b verif/<AAAA-MM-DD>
   ```

4. Comprueba que todo pasa en tu máquina antes de tocar GCP (un timeout del registro de
   Terraform se arregla volviendo a correr):

   ```bash
   cd gcp-datacenter
   bash scripts/check.sh
   bash scripts/policy-check.sh
   bash scripts/selftest.sh
   bash scripts/docs.sh --check
   ```

## C. `0-bootstrap` a mano

Sigue el [runbook 01](runbooks/01-arranque-etapa-0.md), pasos 5 a 8, al pie de la letra. En
resumen: llenar `stages/0-bootstrap/terraform.tfvars`, aplicar con estado local, migrar el estado
al bucket que se crea, sacar las salidas y activar SCC en el proyecto.

- **Decide antes del primer apply** la ubicación del bucket de estado (`US` por defecto): no se
  cambia después.
- **`enable_protection_tags` y `enable_deny_policy` en `true`.** El segundo exige que tengas
  `roles/iam.denyAdmin` en el proyecto (runbook 01, paso 1). Si un apply demuestra que las
  etiquetas no funcionan en el proyecto, pon `enable_protection_tags = false` y anótalo en
  `pendientes-apply.md`: de la política de denegación queda solo la regla sin condición de
  etiqueta (runbook 01, paso 5).
- **Nivel de SCC:** Standard no tiene cargo según la
  [página de precios de SCC](https://cloud.google.com/security-command-center/pricing) (citada en
  [`estimacion-de-costos.md`](estimacion-de-costos.md)). Casi todos los detectores con mapeo CIS
  son de Premium ([`cumplimiento-cis.md`](cumplimiento-cis.md) §6): decide con el equipo
  con qué nivel se evalúa el criterio "sin hallazgos críticos ni altos". Que SCC funcione en un
  proyecto sin organización es HYPOTHESIS.

## D. GitHub: entornos, variables y secretos

### D.1 Entornos

En Settings → Environments, crea `common`, `dev`, `qa` y `prod`. Los trabajos `apply` de
`apply.yml` corren en ellos y cada cuenta que aplica solo acepta tokens de su entorno (ADR 0029
§3): `common` para `1-base` y el hub; `dev`, `qa` y `prod` para su spoke y sus cargas. La cuenta
de lectura (`tf-read`) acepta cualquier trabajo del repositorio: los `plan` corren sin entorno.

- **Revisores.** Pon "Required reviewers" en `common` y `prod`. En un repositorio **privado**, que
  esa regla exista depende del plan de GitHub ([`pipeline.md`](pipeline.md) §4); sin ella,
  `apply.yml` aplica todo seguido, sin pausa. Anota en el pendiente 12 lo que GitHub haga de
  verdad.
- **No definas variables ni secretos en los entornos**: el trabajo `apply` compara las variables
  con las del `plan` (que corre sin entorno) y se detiene si son distintas.

### D.2 Variables de repositorio

Salen de `0-bootstrap` (runbook 01, paso 7). Todas son de **repositorio**. Desde
`gcp-datacenter/`:

```bash
B=stages/0-bootstrap
gh variable set GCP_STATE_BUCKET --body "$(terraform -chdir=$B output -raw state_bucket)"
gh variable set GCP_WORKLOAD_IDENTITY_PROVIDER --body "$(terraform -chdir=$B output -raw workload_identity_provider)"
gh variable set GCP_AUDIT_SERVICE_ACCOUNT --body "$(terraform -chdir=$B output -raw read_service_account)"
gh variable set GCP_STAGE_SERVICE_ACCOUNTS --body "$(terraform -chdir=$B output -json stage_service_accounts)"
gh variable set GCP_TFVARS_JSON < <ruta-fuera-del-repo>/tfvars-ci.json      # D.3
```

`GCP_ENABLED` se pone al final, en la sección E. La cuenta de lectura ya no se crea a mano: es
`<prefix>-tf-read`, con sus roles y su WIF desde `0-bootstrap`.

### D.3 `GCP_TFVARS_JSON` para la rebanada vertical

Para cada raíz, el pipeline copia su `terraform.tfvars.example` y encima escribe `common` más la
llave de la raíz (`scripts/root-tfvars.py`). **`common.project_id` es obligatorio**: sin él, el
plan de una raíz que lo declara falla (el script sale con 2). Lo que no traiga el JSON queda con
el valor del ejemplo, que es un marcador. Esqueleto (cambia cada `<...>`; guárdalo fuera del
repositorio):

```json
{
  "common": {
    "project_id": "<salida project_id de 0-bootstrap>",
    "prefix": "<el mismo prefix de 0-bootstrap, por ejemplo bnt>",
    "state_bucket": "<salida state_bucket de 0-bootstrap>"
  },
  "stages/1-base": {
    "security_alert_email": "<correo-del-equipo>",
    "essential_contacts": {
      "<correo-del-equipo>": ["LEGAL", "SECURITY", "SUSPENSION", "TECHNICAL"]
    },
    "groups": {}
  },
  "stages/2-networks": { "enable_vpn_dr": false },
  "stages/3-workloads/envs/dev": {
    "enable_cloud_run": false,
    "enable_backup": false,
    "off_hours_shutdown": { "enabled": false },
    "domain_names": ["<dominio-de-prueba>"],
    "notification_emails": ["<correo-del-equipo>"]
  }
}
```

- `state_bucket` va en `common` aunque el hub no lo declare: Terraform lo avisa como valor de una
  variable no declarada, sin fallar.
- Lo que pongas en `stages/1-base` reemplaza entera la variable del ejemplo: `essential_contacts`
  y `groups` del ejemplo traen correos `example.com` que no deben llegar a GCP.
- `groups` vacío mientras no haya grupos: nadie más recibe lectura por Terraform, y `user:` está
  prohibido. Con organización, los correos de grupos de Cloud Identity; sin ella, que sirva un
  grupo de Google Groups es HYPOTHESIS.
- `enable_cloud_run = false` en la primera ejecución: todavía no hay imagen (sección E).
- `enable_backup = false` en dev, para que el destroy de la sección I no lo frene la bóveda de
  respaldos.
- `off_hours_shutdown` apagado durante las pruebas: con Cloud SQL detenida de noche, la prueba de
  humo de dev falla a propósito. Probar el apagado son los puntos 70 a 81 de los pendientes.
- `domain_names`: el certificado administrado del balanceador solo se emite si el dominio apunta a
  su IP.
- No pongas `labels` en `common`: cada raíz valida las suyas.
- `terraform validate` no lee este JSON: compáralo con los `variables.tf` de cada raíz por si una
  variable cambió de nombre.

### D.4 Secretos y protección de `main`

- **Secreto opcional** `INFRACOST_API_KEY`: sin él, `pr.yml` omite el costo
  (`gh secret set INFRACOST_API_KEY`).
- **Protección de `main`** (la configura el dueño, si el plan de GitHub lo permite): PR
  obligatorio y estas comprobaciones de `pr.yml` como obligatorias: `estático (terraform 1.9.8)`,
  `estático (terraform 1.16.5)`, `conftest (pruebas y planes de ejemplo)`,
  `scripts (autopruebas)`, `terraform-docs al día` y `plan-gate`.

## E. Rebanada vertical primero

Antes de desplegar todo, una rebanada delgada de punta a punta: `1-base`, hub, spoke de dev y
cargas de dev en modo mínimo, con Cloud Run y Cloud SQL
([plan de rediseño](plan-rediseno-un-proyecto.md), R4). Encuentra las fallas del primer apply con
el menor costo.

### E.1 Antes de lanzar

- **El código tiene que estar en `main`**: `apply.yml` solo aplica desde `main`. El dueño integra
  el PR. Con `GCP_ENABLED` sin poner, el `apply.yml` que dispara el merge no toca GCP.
- **Cómo detenerse después de dev.** `apply.yml` sigue solo hacia qa y prod cuando la prueba de
  humo de dev pasa, y no tiene una entrada para detenerse antes. Dos opciones:
  1. Revisores obligatorios también en el entorno `qa` y **rechazar** el despliegue de
     `qa / 2-networks` cuando lo pida. Depende del plan de GitHub (D.1).
  2. **Cancelar la ejecución** en cuanto termine `dev / prueba de humo`, mientras corre el trabajo
     `plan` de `qa / 2-networks` (solo lee, sin candado). Nunca canceles un trabajo `apply`: deja
     la raíz a medias.

  Agregar esa entrada a `apply.yml` es un cambio de código pendiente (backlog).
- **Cada merge a `main` que toque `gcp-datacenter/` o `.github/workflows/` dispara `apply.yml`**,
  aunque solo cambie documentación (por ejemplo, `pendientes-apply.md`). Con `GCP_ENABLED` en
  `"true"`, esa ejecución recorre toda la cadena, qa y prod incluidos. Integra los PR de registro
  con `GCP_ENABLED` en `"false"`, o prepárate para detenerla como arriba.

### E.2 Primera ejecución: Cloud SQL sin Cloud Run

```bash
gh variable set GCP_ENABLED --body "true"
gh workflow run apply.yml --ref main
gh run watch
```

Orden: `1-base` → `2-networks (hub)` → `dev / 2-networks` → `dev / 3-workloads` →
`dev / prueba de humo`; ahí te detienes (E.1). Cada raíz tiene un trabajo `plan` (cuenta de
lectura) y, si hay cambios, uno `apply` (cuenta de la raíz) que solo aplica si la huella del plan
coincide con la revisada. Mide el tiempo de cada raíz.

La prueba de humo (`tests/e2e/smoke_test.go`) crea Connectivity Tests con la cuenta de lectura:
dev → Cloud SQL por IP privada (siempre; debe ser alcanzable), Internet → balanceador de dev en
443 (solo si hay un backend encendido) y dev → `onprem-sim` (solo exige que la ruta exista; el
firewall puede descartar el paquete). Sus permisos son el pendiente 50 y la ruta, el 6.

**Si un trabajo falla:**

- `plan <raíz>` o `dev / prueba de humo`: no cambiaron nada. Corrige la causa y usa "Re-run failed
  jobs". Si `main` avanzó desde esa ejecución, el trabajo lo detecta y falla: lanza una nueva.
- `apply <raíz>` a medias: "Re-run failed jobs" **no sirve** (su plan nuevo ya no tiene la huella
  revisada). Corrige la causa y lanza `apply.yml` otra vez: las raíces al día dan "sin cambios" y
  la que quedó a medias muestra solo lo que falta.
- Si la corrección es un cambio de código, va por PR desde tu rama `verif/<fecha>` o una
  `fix/<tema>`; el merge trae su propia ejecución.

### E.3 Publicar una imagen y encender Cloud Run

`1-base` ya creó el repositorio de dev (`<prefix>-dev-app`, salida `artifact_registry_repositories`).
Binary Authorization solo admite imágenes de los repositorios del proyecto: la pública de ejemplo
se copia ahí.

```bash
REPO=us-docker.pkg.dev/<ID>/<prefix>-dev-app
gcloud auth configure-docker us-docker.pkg.dev
docker pull us-docker.pkg.dev/cloudrun/container/hello
docker tag us-docker.pkg.dev/cloudrun/container/hello "${REPO}/hello:1.0.0"
docker push "${REPO}/hello:1.0.0"
```

La sube una identidad de `artifact_registry_publishers` de `1-base` (nunca `user:`). En la prueba,
como dueña del proyecto, tu cuenta ya puede escribir (HYPOTHESIS: que `owner` alcance); anótalo
como paso manual. Después, en la llave `stages/3-workloads/envs/dev` de `GCP_TFVARS_JSON`:
`"enable_cloud_run": true` y `"cloud_run_image": "<REPO>/hello:1.0.0"` (una versión, nunca
`latest`). Lanza `apply.yml` otra vez y detente después de dev.

### E.4 Qué mirar al terminar la rebanada

- La ejecución en verde hasta `dev / prueba de humo`, con su tiempo.
- `gh workflow run drift.yml`: ninguna incidencia nueva (segundo plan sin cambios) y el trabajo de
  recursos no administrados en verde. La lista de permitidos nunca se probó contra un proyecto
  real (pendiente 49): si lista algo que creó Google o la imagen de E.3 (HYPOTHESIS: que Cloud
  Asset la indexe), se agrega una regla con su motivo por PR ([runbook 05](runbooks/05-respuesta-a-drift.md)).
- En la consola: las VPC hub, `dev` y `onprem-sim` con sus peerings, los túneles de VPN arriba,
  Cloud SQL con IP privada, el servicio de Cloud Run detrás del balanceador.
- Registra cada punto comprobado (sección G). Los primeros: 1 (estado por prefijo), 13
  (migración), 48 (huella), 50 (prueba de humo) y 55 (primera ejecución).

## F. El resto del despliegue

Con la rebanada en verde ([plan de rediseño](plan-rediseno-un-proyecto.md), R5):

1. **qa y prod en modo mínimo.** En sus llaves de `stages/3-workloads/envs/<env>`, todo `enable_*`
   en `false` salvo lo que se quiera mostrar, y en prod `enable_dr = false` también en
   `stages/2-networks/envs/prod`. Cloud SQL se crea siempre. Publica antes la imagen en los
   repositorios de qa y prod si vas a encender Cloud Run.
2. **Antes de desplegar prod, decide cómo vas a apagarlo:** prod no tiene flujo de destroy y su
   Cloud SQL exige `deletion_protection = true` (sección I).
3. Lanza `apply.yml` sin detenerte. Mide el tiempo total del despliegue.
4. **Opcional, si hay presupuesto:**
   - Cómputo en prod, para el criterio "una VM de prod alcanza on-premises y resuelve su DNS"
     (pendientes 6, 7, 36 y 37). En modo simulado falta un servidor DNS en `onprem-sim` que el
     código no crea (README, criterios de aceptación): si lo creas a mano, anótalo como paso
     manual y espera que el trabajo de recursos no administrados lo liste.
   - DR (`enable_vpn_dr = true` en el hub y `enable_dr = true` en las dos raíces de prod) con el
     simulacro del [runbook 04](runbooks/04-conmutacion-a-dr.md).

   Esto acerca el costo al del diseño completo: hazlo en un bloque corto.

## G. Qué comprobar y cómo registrarlo

| Criterio de aceptación (README) | Cómo se comprueba |
|---|---|
| Despliegue desde cero sin errores | Ejecución de `apply.yml` en verde; tiempo total |
| Segundo `plan` sin cambios | `drift.yml` después del apply: ninguna incidencia nueva |
| `destroy` de dev sin huérfanos | Sección I: `destroy.yml` con dev en verde, incluida la búsqueda de huérfanos en el proyecto |
| El pipeline bloquea un PR que viola una política | PR de prueba que cambie algo desplegado, por ejemplo una IP pública en la instancia de Cloud SQL de dev o un miembro `user:` en un IAM: `pr.yml` debe fallar en Conftest (pendiente 51). No lo integres |
| Una VM de prod alcanza on-premises y resuelve su DNS | Prueba de humo de dev (ruta hacia `onprem-sim`) y, con cómputo en prod, una Connectivity Test y una consulta DNS desde una VM de prod (sección F) |
| Sin hallazgos críticos ni altos en SCC | [`cumplimiento-cis.md`](cumplimiento-cis.md) §6 |
| Simulacro de DR dentro del RTO | Runbook 04 |
| Cero recursos creados a mano | Trabajo de recursos no administrados de `drift.yml` en verde |

Para cada punto de [`pendientes-apply.md`](pendientes-apply.md) que compruebes, agrega debajo
una línea con este formato exacto:

```text
Verificado el AAAA-MM-DD con `<comando>`: <resultado en una línea>.
Falló el AAAA-MM-DD con `<comando>`: <error exacto>.
```

Además:

- Guarda capturas y los enlaces a las ejecuciones de GitHub Actions, fuera del repositorio si
  muestran correos, IDs o la cuenta de facturación.
- Los registros van en tu rama `verif/<AAAA-MM-DD>` y entran por PR. Nada directo a `main`: el
  merge dispara `apply.yml` (sección E.1).
- Las pruebas de integración (Terratest) son opcionales y cuestan:
  [`tests/README.md`](../tests/README.md).

## H. Si algo falla

1. Copia el error completo, no solo la última línea, y el nombre del trabajo y la raíz.
2. Búscalo en `pendientes-apply.md`: muchos puntos ya dicen qué hacer si fallan.
3. Problema de cuota: pide el aumento en la consola (IAM y administración → Cuotas) y lanza
   `apply.yml` otra vez.
4. Timeout al descargar proveedores del registro de Terraform: vuelve a correr el trabajo.
5. Permiso que le falta a una cuenta del pipeline: el diagnóstico primero; el arreglo es un PR a
   `0-bootstrap` (la única raíz que da roles de proyecto a las cuentas) y lo aplicas tú a mano.
6. Si no está documentado: abre una incidencia con el error, la raíz y el commit, y agrega el caso
   a `pendientes-apply.md` en tu PR.

## I. Apagar todo al terminar

1. **Destroy de dev y qa con `destroy.yml`** (criterio "`destroy` de dev sin huérfanos"), con
   `GCP_ENABLED` todavía en `"true"` (el flujo lo exige):

   ```bash
   gh workflow run destroy.yml --ref main -f entorno=dev -f confirmacion=dev
   gh run watch
   ```

   Destruye `3-workloads/envs/dev` y termina buscando huérfanos en el proyecto con Cloud Asset
   Inventory. Guarda el resumen como evidencia. Después, el spoke, con
   `-f incluir_red=true`: la conexión de Private Service Access puede tardar días en poder
   borrarse después de borrar Cloud SQL (HYPOTHESIS, ADR 0029 §8); si falla por eso, vuelve a
   lanzarlo días después (las raíces ya vacías se saltan). Lo mismo para qa. Si se detiene, el
   resumen dice en qué raíz y por qué (puntos 11 y 85 a 89 de los pendientes).
2. **`gh variable set GCP_ENABLED --body "false"`** en cuanto termine: con `"true"`, el siguiente
   push a `main` vuelve a crear lo destruido. Para recrear un entorno pronto, cambia
   `sql_instance_name` (por ejemplo `sql2`): el nombre de una instancia borrada no se reutiliza de
   inmediato (HYPOTHESIS, descripción de la variable).
3. **Lo que queda** no tiene flujo de destroy, a propósito:

   | Qué | Dónde | Cuesta |
   |---|---|---|
   | prod (si se desplegó): cargas, Cloud SQL con protección contra borrado, spoke | `3-workloads/envs/prod`, `2-networks/envs/prod` | Sí, Cloud SQL y NAT |
   | Hub: VPN (y `onprem-sim` con la suya), Cloud DNS | `2-networks` | Sí, los túneles de VPN |
   | Llaves, secretos, repositorios, bucket de logs, alertas | `1-base` | Poco; las llaves KMS no se pueden borrar |
   | Bucket de estado, cuentas, WIF, presupuesto | `0-bootstrap` | Muy poco |

   Opciones, que decide el equipo y no el pipeline:
   - **Conservar el proyecto** (por ejemplo, para entregarlo o mostrarlo): lo que más cuesta es
     la VPN del hub y, si existe, prod.
   - **Cerrar el proyecto**, si ya no se va a usar: lo hace la persona dueña en la consola o con
     `gcloud projects delete <ID>`. No es parte del diseño (ninguna raíz borra el proyecto y la
     política de denegación se lo niega a las cuentas del pipeline). Antes, guarda la evidencia:
     los estados y los logs viven en buckets del proyecto. Según la
     [documentación de Resource Manager](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects)
     (citada en [`pipeline.md`](pipeline.md)), un proyecto borrado se elimina del todo a los 30
     días; que deje de cobrar en cuanto se cierra es HYPOTHESIS.

## J. Grabar el video

El guion está en [`plan-presentacion-final.md`](plan-presentacion-final.md) §2, con las reglas de
**qué no mostrar** (la cuenta de facturación, tokens, `terraform.tfvars`, `GCP_TFVARS_JSON`, el
correo de la cuenta, los miembros `user:` y `group:`, la página de variables del repositorio). Se
graba en el **ensayo**,
una ejecución que ya pasó al menos una vez, no la primera. La escena de `0-bootstrap` solo ocurre
una vez: si se quiere en el video, graba la terminal en la sección C con un perfil limpio y
recorta lo que esas reglas piden.

---

## Anexo: prompt para Claude Code

Abre Claude Code en la raíz del repositorio clonado y pega esto, cambiando lo que está entre
`<...>`:

```text
Vas a ayudarme a desplegar y probar este proyecto en un proyecto de Google Cloud. Soy <nombre>,
del equipo 2. Mi proyecto es <ID del proyecto> (<sin organización | dentro de la organización
<org_id>>). Mi presupuesto es de <monto> USD. Dónde estoy: <por ejemplo: ya creé el proyecto y
borré la red default; no he corrido 0-bootstrap>.

Lee primero, en este orden:
1. CLAUDE.md de la raíz del repositorio. Sus reglas mandan.
2. gcp-datacenter/README.md.
3. gcp-datacenter/docs/guia-colaborador-gcp.md (esta guía) y
   gcp-datacenter/docs/runbooks/01-arranque-etapa-0.md.
4. gcp-datacenter/docs/adr/0029-un-solo-proyecto.md y los cinco documentos de
   gcp-datacenter/docs/diagramas/.
5. gcp-datacenter/docs/pendientes-apply.md y gcp-datacenter/docs/backlog.md.
Después dime en qué sección de la guía estoy y qué sigue, con su costo.

Reglas:
- Respeta todo lo de CLAUDE.md: el repositorio es privado; no abras ni copies la carpeta docs/ de
  la raíz ni labs/README.md; las etapas 1 a 3 solo las aplica el pipeline y 0-bootstrap es la
  única manual; afirmaciones sobre GCP o GitHub solo con fuente oficial o comprobadas, lo demás
  marcado HYPOTHESIS.
- Antes de cualquier cambio en GCP o en GitHub (terraform apply o destroy, gcloud ... create,
  delete o add-iam-policy-binding, gh variable set, gh secret set, gh workflow run, cambios de
  entornos o de protección de rama), muéstrame el comando, qué efecto tiene y cuánto cuesta, y
  espera mi sí. Un sí vale para ese paso, no para los siguientes.
- Las contraseñas, los códigos de verificación y los pasos en las consolas de Google y GitHub
  los hago yo; tú me dices exactamente dónde y qué.
- Nunca subas terraform.tfvars, estados, llaves, el JSON de GCP_TFVARS_JSON ni credenciales.
  Revisa git status antes de cada commit. No muestres valores de secretos en el chat.
- Trabaja en la rama verif/<AAAA-MM-DD> (créala si no existe). Nada directo a main: todo entra
  por PR, porque el merge a main dispara apply.yml. Los arreglos de código van en una rama
  fix/<tema> con PR.
- Antes de proponer un cambio de código, corre desde gcp-datacenter/: bash scripts/check.sh,
  bash scripts/policy-check.sh, bash scripts/selftest.sh y bash scripts/docs.sh --check.
- Cuando algo falle, busca primero el error en pendientes-apply.md y en los runbooks, y dame el
  diagnóstico antes de cambiar nada.
- Cada vez que comprobemos un punto de pendientes-apply.md, agrega debajo
  "Verificado el AAAA-MM-DD con `<comando>`: <resultado>" o
  "Falló el AAAA-MM-DD con `<comando>`: <error>".
- Haz primero la rebanada vertical (sección E de la guía) y detente después de dev.
- Lleva la cuenta del costo: dime cuánto tiempo llevamos con recursos encendidos y recuérdame
  apagar (sección I de la guía).
```
