# Guía para desplegar y probar el proyecto en una organización de GCP propia

Para la persona del equipo que tiene la cuenta de Google Cloud. Explica cómo crear la
organización desde cero, conectar este repositorio, hacer el primer despliegue y comprobar lo
que falta para los criterios de aceptación. Se puede seguir a mano o con Claude Code (al final
está el prompt).

**Estado de partida (23 nov 2026):** todo el código está construido y pasa las revisiones que
corren sin GCP. **Nada se ha desplegado nunca.** El primer despliegue es una prueba: es normal
que algo falle. Cada falla es un hallazgo que se anota y se corrige, no un error tuyo.

**Antes de empezar:**

- **Cuesta dinero.** Según [`estimacion-de-costos.md`](estimacion-de-costos.md) (precios de lista
  del 23 nov 2026), el despliegue mínimo de la sección D cuesta **20 a 22 USD por día** con los
  tres entornos, u **8 a 9 USD por día** si solo se despliega dev. El diseño completo cuesta 81 a
  117 USD por día. Pon una alerta de presupuesto y apaga todo al terminar (sección H).
- **El repositorio es privado y debe seguir así.** Nunca subas `terraform.tfvars`, estados
  (`*.tfstate`), llaves JSON ni contraseñas. El `.gitignore` ya los excluye; no lo cambies.
- **Nada de recursos a mano** fuera de lo que esta guía y el runbook 01 piden (la etapa 0, SCC y
  la cuenta de auditoría). Todo lo demás lo crea el pipeline.

Documentos que vas a usar (rutas relativas a `gcp-datacenter/`):

| Documento | Para qué |
|---|---|
| [`docs/runbooks/01-arranque-etapa-0.md`](runbooks/01-arranque-etapa-0.md) | Procedimiento exacto de la etapa 0, de GitHub y de la primera ejecución. Es la fuente de verdad; esta guía no repite sus comandos |
| [`docs/pipeline.md`](pipeline.md) | Variables de GitHub (§2), cómo se enciende GCP y la cuenta de auditoría (§3), configuración manual de GitHub (§4) |
| [`docs/pendientes-apply.md`](pendientes-apply.md) | Lo que solo un despliegue real puede confirmar: tu lista de pruebas |
| [`docs/runbooks/04-conmutacion-a-dr.md`](runbooks/04-conmutacion-a-dr.md) | Simulacro de DR |
| [`docs/cumplimiento-cis.md`](cumplimiento-cis.md) §6 | Cómo evaluar el CIS con Security Command Center |
| [`README.md`](../README.md) | Arquitectura, orden de despliegue y criterios de aceptación |

---

## A. Crear la organización de Google Cloud (~1 día, casi todo espera de DNS)

Una cuenta de Gmail sola no tiene organización. Hace falta un **dominio propio** y **Cloud
Identity Free** (sin costo).

1. **Dominio.** Usa uno que ya tengas o compra uno barato. Necesitas poder agregar registros DNS.
2. **Cloud Identity Free.** Regístrate en
   <https://workspace.google.com/gcpidentity/signup?sku=identitybasic> con ese dominio (guía de
   Google: <https://docs.cloud.google.com/identity/docs/set-up-cloud-identity-admin>). La cuenta
   que creas es la de **superadministrador**: usa una dirección de rol (por ejemplo
   `admin@<dominio>`), actívale la verificación en dos pasos y no la uses para el trabajo diario.
3. **Verifica el dominio** con el registro TXT que pida Google
   (<https://docs.cloud.google.com/identity/docs/how-to/verify-domain>). Tarda de minutos a horas.
4. **Entra a <https://console.cloud.google.com>** con el superadministrador y acepta los términos.
   Google crea la organización y le da a esa cuenta el rol de Administrador de la organización
   (<https://docs.cloud.google.com/resource-manager/docs/creating-managing-organization>).
5. **Crea tu usuario de trabajo** en <https://admin.google.com> → Directorio → Usuarios (por
   ejemplo `tu.nombre@<dominio>`), con verificación en dos pasos. Con él corres la etapa 0; el
   superadministrador queda solo para emergencias. Los controles de Cloud Identity que pide el
   CIS (verificación en dos pasos obligatoria, llaves de seguridad, etc.) están en el runbook 01,
   "Prerrequisitos".
6. **Cuenta de facturación.** Créala en Facturación. **Recomendación: de pago, no de prueba
   gratuita.** Según Google, con la prueba gratuita (300 USD por 90 días) no se pueden pedir
   aumentos de cuota (<https://docs.cloud.google.com/free/docs/free-cloud-features>) y este
   proyecto crea más de diez proyectos. Pon de una vez una alerta de presupuesto en la cuenta.
7. **Crea los siete grupos** en <https://admin.google.com> → Directorio → Grupos:

   | Llave en `groups` | Grupo sugerido |
   |---|---|
   | `org_admins` | `gcp-org-admins@<dominio>` |
   | `billing_admins` | `gcp-billing-admins@<dominio>` |
   | `security_admins` | `gcp-security-admins@<dominio>` |
   | `network_admins` | `gcp-network-admins@<dominio>` |
   | `platform_devops` | `gcp-platform-devops@<dominio>` |
   | `developers` | `gcp-developers@<dominio>` |
   | `auditors` | `gcp-auditors@<dominio>` |

   Agrégate a `gcp-org-admins`; a los compañeros que solo miran, a `gcp-auditors`. Si después vas
   a encender GKE en prod, crea también `gke-security-groups@<dominio>` (lo pide Google Groups
   for RBAC).
8. **Roles para tu usuario de trabajo** (los de "Prerrequisitos" del runbook 01). Con el
   superadministrador, en Git Bash:

   ```bash
   ORG=<org_id>                      # gcloud organizations list
   YO=user:<tu-usuario>@<dominio>
   for R in resourcemanager.organizationAdmin resourcemanager.folderCreator \
            resourcemanager.projectCreator iam.organizationRoleAdmin iam.denyAdmin \
            securitycenter.admin; do
     gcloud organizations add-iam-policy-binding "$ORG" --member="$YO" \
       --role="roles/$R" --condition=None
   done
   ```

   En la cuenta de facturación, `roles/billing.admin` para tu usuario (Facturación →
   Administración de cuentas → Agregar principal).
9. **Anota** `org_id`, la cuenta de facturación y el `directory_customer_id`
   (`gcloud organizations describe <org_id> --format="value(owner.directoryCustomerId)"`).

## B. Herramientas y acceso al repositorio (~1 hora)

1. El dueño del repositorio te agrega como colaborador (GitHub → Settings → Collaborators). En un
   repositorio de cuenta personal, un colaborador puede crear variables de Actions del
   repositorio y lanzar flujos; la configuración de entornos y de protección de rama la hace el
   dueño.
2. Instala Git (en Windows, con Git Bash), **Terraform 1.16.5** (la versión del pipeline; mínimo
   1.11, ver ADR 0021), Google Cloud CLI, GitHub CLI, `jq` y Python 3. Para correr las revisiones
   locales también TFLint, checkov, Conftest y terraform-docs (versiones en el README,
   "Herramientas").
3. Clona el repositorio y entra a la rama del proyecto:

   ```bash
   gh auth login
   gh repo clone jadrianlg16/reto-banorte-gcp-terraform
   cd reto-banorte-gcp-terraform
   git checkout feat/gcp-datacenter-build     # o main, si ya se integró
   ```

4. Comprueba que todo pasa en tu máquina antes de tocar GCP (tarda varios minutos; si el
   registro de Terraform da un timeout, vuelve a correrlo):

   ```bash
   cd gcp-datacenter
   bash scripts/check.sh
   ```

## C. Etapa 0 a mano (~2 horas)

Sigue el [runbook 01](runbooks/01-arranque-etapa-0.md), pasos 1 a 8, al pie de la letra, con tu
usuario de trabajo. En resumen: iniciar sesión con `gcloud`, llenar
`stages/0-bootstrap/terraform.tfvars`, aplicar con estado local, mover el estado al bucket que se
crea, activar Security Command Center y revisar Access Context Manager.

- Decide **antes** del primer apply la ubicación del bucket de estado (`US` por defecto): no se
  cambia después.
- En una organización nueva puede fallar una API por falta de proyecto de cuota: el runbook
  (paso 3) dice qué hacer.
- **Nivel de SCC:** Standard no tiene costo adicional según Google. Casi todos los detectores
  con mapeo CIS son de Premium ([`cumplimiento-cis.md`](cumplimiento-cis.md) §6): decide con el
  equipo si el criterio "sin hallazgos críticos ni altos" se evalúa con Standard.

## D. GitHub y primer despliegue

### D.1 Antes de encender el pipeline (lo decide el dueño del repositorio)

**Plan de GitHub.** Según la documentación de GitHub, en un repositorio **privado** de una
cuenta gratuita no hay protección de rama ni entornos con revisores obligatorios
([`pipeline.md`](pipeline.md) §4, punto 3). Consecuencia: `apply.yml` **no se detiene a pedir
aprobación** antes de `common` y `prod`; aplica todo seguido. Para la organización de prueba eso
se acepta así:

- Revisa el plan de cada raíz antes de lanzar `apply.yml` (los PR muestran el plan en un
  comentario cuando `GCP_ENABLED = true`).
- Lanza `apply.yml` solo cuando estés listo para que aplique todo.
- Anota en el pendiente 12 lo que GitHub haga realmente con los trabajos que declaran
  `environment:` en el repositorio privado.

**El código tiene que estar en `main`.** `apply.yml` solo aplica desde `main`: el dueño integra
el PR de `feat/gcp-datacenter-build` antes del paso D.4.

### D.2 Variables de GitHub

Paso 9 del runbook 01 y [`pipeline.md`](pipeline.md) §2 y §3: `GCP_STATE_BUCKET`,
`GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_STAGE_SERVICE_ACCOUNTS`, `GCP_TFVARS_JSON` y
`GCP_AUDIT_SERVICE_ACCOUNT`. **Todas son variables de repositorio, nunca de entorno.**

La cuenta de auditoría (`GCP_AUDIT_SERVICE_ACCOUNT`) la creas a mano. Antes de encender el
pipeline solo se le puede dar `workloadIdentityUser` y el rol sobre el bucket de estado; el resto
de sus roles se asigna **durante** la primera ejecución, a medida que existen las carpetas y los
proyectos (`pipeline.md` §3, "Orden").

### D.3 `GCP_TFVARS_JSON` para el despliegue mínimo

Lo que no traiga `GCP_TFVARS_JSON` se toma de los `terraform.tfvars.example`, que solo tienen
marcadores. La tabla de [`pipeline.md`](pipeline.md) §2 lista cada marcador que hay que
reemplazar. Para la **primera ejecución** no hay imágenes publicadas todavía (los repositorios de
Artifact Registry los crea la misma ejecución), así que Cloud Run y el MIG van apagados. Esqueleto
del despliegue mínimo (cambia cada `<...>`; guárdalo fuera del repositorio):

```json
{
  "common": {
    "org_id": "<org_id>",
    "billing_account": "<XXXXXX-XXXXXX-XXXXXX>",
    "prefix": "bnt",
    "project_suffix": "<el mismo de la etapa 0, o vacío>",
    "state_bucket": "<salida state_bucket de la etapa 0>"
  },
  "stages/1-org": {
    "directory_customer_id": "<C0xxxxxxx>",
    "budget_amount": 300,
    "groups": {
      "org_admins": "gcp-org-admins@<dominio>",
      "billing_admins": "gcp-billing-admins@<dominio>",
      "security_admins": "gcp-security-admins@<dominio>",
      "network_admins": "gcp-network-admins@<dominio>",
      "platform_devops": "gcp-platform-devops@<dominio>",
      "developers": "gcp-developers@<dominio>",
      "auditors": "gcp-auditors@<dominio>"
    }
  },
  "stages/3-networks": { "enable_vpn_dr": false },
  "stages/3-networks/envs/prod": { "enable_dr": false },
  "stages/4-projects/envs/dev": {
    "workloads_service_account": "<stage_service_accounts[\"5-workloads\"] de la etapa 0>",
    "artifact_registry_publishers": {}
  },
  "stages/4-projects/envs/qa": {
    "workloads_service_account": "<el mismo>",
    "artifact_registry_publishers": {}
  },
  "stages/4-projects/envs/prod": {
    "workloads_service_account": "<el mismo>",
    "artifact_registry_publishers": {}
  },
  "stages/5-workloads/envs/dev": {
    "enable_cloud_run": false, "enable_mig": false,
    "notification_emails": ["gcp-platform-devops@<dominio>"]
  },
  "stages/5-workloads/envs/qa": {
    "enable_cloud_run": false, "enable_mig": false, "enable_memorystore": false,
    "notification_emails": ["gcp-platform-devops@<dominio>"]
  },
  "stages/5-workloads/envs/prod": {
    "enable_cloud_run": false, "enable_mig": false, "enable_gke": false,
    "enable_internal_lb": false, "enable_filestore": false, "enable_memorystore": false,
    "enable_dr": false,
    "notification_emails": ["gcp-platform-devops@<dominio>"]
  }
}
```

- No pongas `labels` dentro de `common`: cada raíz valida las suyas.
- Si la organización ya tenía una política de Access Context Manager (runbook 01, paso 8), agrega
  `"stages/2-security": { "access_policy_id": "<número>" }`.
- Antes de cargarlo, compara con la tabla de `pipeline.md` §2 por si una variable cambió de
  nombre: `terraform validate` de cada raíz no lee este JSON.

Cárgalo con `gh variable set GCP_TFVARS_JSON < <ruta>/tfvars-ci.json`.

### D.4 Encender y lanzar

Lee antes la sección "Primera ejecución de `apply.yml`" del runbook 01: aprobaciones, roles de
la cuenta de auditoría a medida que existen los recursos, la prueba de humo hacia on-premises
simulado y **qué hacer si un trabajo falla**. Lo más importante: si un `apply` queda a medias,
"Re-run failed jobs" no sirve; corrige la causa y lanza `apply.yml` otra vez.

```bash
gh variable set GCP_ENABLED --body "true"
gh workflow run apply.yml --ref main
gh run watch
```

Orden: `1-org` → `2-security` → hub → dev → prueba de humo de dev → qa → prod. Si una raíz
falla, las siguientes no corren. Mide el tiempo total (el objetivo del cliente es menos de 90
minutos para un despliegue desde cero).

## E. Después del despliegue mínimo: cómputo, conectividad y DR

Cuando el despliegue mínimo esté verde, enciende lo demás de uno en uno, cada cambio con su PR
o con una ejecución nueva de `apply.yml` después de cambiar `GCP_TFVARS_JSON`:

1. **Imágenes y cómputo de dev:** runbook [02](runbooks/02-alta-proyecto-aplicacion.md), pasos
   3 y 4 (publicar la imagen, `enable_cloud_run = true`, lanzar `apply.yml`).
2. **Cómputo de prod** (MIG o GKE) para el criterio "una VM de prod alcanza on-premises por IP
   privada y resuelve su DNS".
3. **DR:** `enable_vpn_dr = true` en el hub y `enable_dr = true` en prod (red y cargas); después,
   el simulacro del [runbook 04](runbooks/04-conmutacion-a-dr.md), midiendo el RTO (objetivo:
   4 horas) y el RPO (objetivo: 15 minutos).

Esto sube el costo hacia el del diseño completo: hazlo en un bloque corto y apaga al terminar.

## F. Qué comprobar y cómo registrarlo

| Criterio de aceptación (README) | Cómo se comprueba |
|---|---|
| Despliegue desde cero sin errores | Ejecución de `apply.yml` en verde; tiempo total |
| Segundo `plan` sin cambios | `gh workflow run drift.yml` después del apply: debe terminar en verde |
| `destroy` de dev sin huérfanos | Sección H, paso 2, con dev; después, `gcloud asset search-all-resources` en la carpeta dev |
| El pipeline bloquea un PR que viola una política | PR de prueba que agregue, por ejemplo, una IP pública a una VM: `pr.yml` debe fallar en Conftest |
| Conectividad con on-premises | Prueba de humo de dev y, con cómputo en prod, una Connectivity Test desde prod |
| Sin hallazgos críticos ni altos en SCC | [`cumplimiento-cis.md`](cumplimiento-cis.md) §6 |
| Simulacro de DR dentro del RTO | Runbook 04 |

Para cada punto de [`pendientes-apply.md`](pendientes-apply.md) que compruebes, agrega debajo:

```
**Verificado el AAAA-MM-DD** con `<comando>`: <resultado en una línea>.
```

o, si falla, **Falló el AAAA-MM-DD** con el error exacto. Además:

- Guarda capturas de la consola y los enlaces a las ejecuciones de GitHub Actions.
- No corrijas código directo en `main`: rama `fix/<tema>` o `verif/<fecha>`, cambio y PR.
  `pr.yml` corre las mismas revisiones.
- Las pruebas de integración (Terratest) son opcionales y cuestan: [`tests/README.md`](../tests/README.md).

## G. Si algo falla

1. Copia el error completo, no solo la última línea, y el nombre del trabajo y la raíz.
2. Búscalo en `pendientes-apply.md`: muchos puntos ya dicen qué hacer si fallan.
3. Problema de cuota: pide el aumento en <https://console.cloud.google.com/iam-admin/quotas> y
   lanza `apply.yml` otra vez.
4. Timeout al descargar proveedores del registro de Terraform: vuelve a correr el trabajo.
5. Si no está documentado: abre una incidencia en GitHub con el error, la raíz y el commit, y
   agrega el caso a `pendientes-apply.md` en tu PR.

## H. Apagar todo al terminar

1. `gh variable set GCP_ENABLED --body "false"`: ningún flujo vuelve a aplicar.
2. Para el criterio de `destroy`: `terraform destroy` de dev de la etapa 5 a la 3 con la
   identidad de cada etapa (README, "Despliegue"). Prod no se desmonta con `destroy`: tiene
   protección contra borrado obligatoria.
3. Borra los proyectos (consola → Administrar recursos, o `gcloud projects delete <id>`): primero
   los de `dev`, `qa` y `prod`, luego los de `common` y al final el semilla. Un proyecto borrado
   tarda 30 días en eliminarse del todo y deja de cobrar al borrarse.
4. Desvincula la facturación de los proyectos que queden o cierra la cuenta de facturación de
   prueba.

Antes de borrar, guarda la evidencia: los estados viven en el bucket del proyecto semilla y se
pierden con él.

---

## Anexo: prompt para Claude Code

Abre Claude Code en la raíz del repositorio clonado (el `CLAUDE.md` de la raíz trae las reglas
del proyecto) y pega esto, cambiando lo que está entre `<...>`:

```text
Vas a ayudarme a desplegar y probar este proyecto en mi organización de Google Cloud. Soy
<nombre>, del equipo 2. Lee primero CLAUDE.md, gcp-datacenter/docs/guia-colaborador-gcp.md, el
runbook gcp-datacenter/docs/runbooks/01-arranque-etapa-0.md, gcp-datacenter/docs/pipeline.md §2
a §4 y gcp-datacenter/docs/pendientes-apply.md. Después dime en qué sección de la guía estoy y
qué sigue.

Dónde estoy: <por ejemplo: ya tengo el dominio verificado y la organización; no he corrido la
etapa 0>. Mi dominio es <dominio>. Mi presupuesto es de <monto> USD.

Reglas:
- Vamos sección por sección de la guía. Antes de cualquier comando que cree, cambie o borre algo
  en GCP o en GitHub (terraform apply, gcloud ... create/delete/add-iam-policy-binding, gh
  variable set, gh workflow run), muéstrame el comando, qué hace y cuánto cuesta, y espera mi sí.
- Las contraseñas, los códigos de verificación y los pasos en las consolas de Google y GitHub los
  hago yo; tú me dices exactamente dónde y qué.
- Nunca subas terraform.tfvars, estados, llaves ni el JSON de GCP_TFVARS_JSON; antes de cada
  commit revisa git status.
- Cuando algo falle, primero busca el error en pendientes-apply.md y en el runbook; dame el
  diagnóstico antes de cambiar código. Las correcciones van en una rama fix/<tema> con PR, nunca
  directo a main.
- Cada vez que comprobemos un punto de pendientes-apply.md, agrega la línea "Verificado el ..." o
  "Falló el ..." con el comando y el resultado.
- Lleva la cuenta del costo: dime cuánto llevamos encendido y recuérdame apagar (sección H).
```
