# Diagrama 1: vista general, gobierno y acceso

Todo vive en un solo proyecto de Google Cloud ([ADR 0029](../adr/0029-un-solo-proyecto.md)).
Este diagrama muestra quién crea qué, cómo entra el pipeline y qué separa a los entornos. Es
diseño: nada se ha aplicado.

![Vista general: un proyecto, tres entornos y un pipeline](img/01-vista-general.png)

El PNG sale de [`fuente/`](fuente/LEEME.md). Las piezas de cada entorno son las que enciende su
`terraform.tfvars.example`. El diagrama de texto usa `prefix = "bnt"` y `{env}` por dev, qa o
prod.

```mermaid
flowchart TB
  subgraph GH["GitHub · repositorio privado"]
    team["Equipo<br/>solo lectura en GCP"]
    repo["Repositorio<br/>Terraform en 4 etapas"]
    gha["GitHub Actions<br/>un trabajo por raíz, con su environment<br/>escribe solo _terraform-root.yml en main"]
    team -- "pull request" --> repo -- "merge a main" --> gha
  end

  owner["Persona dueña del proyecto<br/>crea el proyecto y aplica 0-bootstrap, una vez"]

  subgraph P["Proyecto único · project_id · nombres bnt-{env}-…"]
    subgraph B0["0-bootstrap (a mano)"]
      apis["APIs del proyecto · OS Login<br/>cuenta de Compute por defecto sin Editor"]
      state["Bucket de estado bnt-bootstrap-ops-tfstate<br/>multirregión US · llave KMS en us · versionado"]
      wif["Pool y proveedor de WIF<br/>attribute_condition: repository_id y repository_owner_id<br/>attribute.deploy: main + flujo del repo + environment"]
      sas["9 cuentas del pipeline<br/>bnt-tf-base · bnt-tf-net · bnt-tf-net-{env}<br/>bnt-tf-wl-{env} · bnt-tf-read"]
      roles["4 roles personalizados del proyecto"]
      deny["Etiqueta bnt-proteccion = etapa-0<br/>política de denegación del proyecto"]
      budget["Presupuesto del proyecto"]
      orgc["Solo con org_id: políticas de organización en el proyecto<br/>con access_policy_id: VPC-SC en dry-run"]
    end
    subgraph B1["1-base (entorno common)"]
      audit["Auditoría del proyecto · sink → bucket de logs con CMEK<br/>alertas de auditoría · contactos esenciales · canal de operaciones"]
      keys["Llaves KMS y contenedores de secretos por entorno"]
      img["Repositorios bnt-{env}-app · Binary Authorization"]
      runsa["Cuentas de ejecución bnt-{env}-app-{uso}<br/>con sus permisos · cuenta de la VM DNS (opcional)"]
      people["Grupos de solo lectura (opcional)"]
    end
    subgraph N2["2-networks"]
      hub["hub (common): VPC hub, onprem-sim, VPN, DNS<br/>VM DNS de onprem-sim (opcional)"]
      spk["spoke por entorno: dev · qa · prod"]
    end
    subgraph W3["3-workloads"]
      wl["cargas por entorno: dev · qa · prod"]
    end
  end

  owner --> B0
  gha -- "token OIDC" --> wif --> sas
  sas -- "bnt-tf-base (common)" --> B1
  sas -- "bnt-tf-net (common) y bnt-tf-net-{env} ({env})" --> N2
  sas -- "bnt-tf-wl-{env} ({env})" --> W3
  runsa -. "tf-wl-{env} solo adjunta las de su entorno" .-> W3
  deny -. "niega a las 9 cuentas" .-> state
```

## Cómo se lee

- **Quién crea qué.** Una persona crea el proyecto (consola o `gcloud`), lo liga a una cuenta de
  facturación de pago y aplica `0-bootstrap` a mano una sola vez
  ([runbook 01](../runbooks/01-arranque-etapa-0.md)). Desde `1-base`, todo lo aplica el pipeline
  con una cuenta por raíz. Ninguna raíz crea ni borra el proyecto.
- **Raíces y cuentas** (`stages/0-bootstrap/README.md`):

  | Raíz | Prefijo del estado | Cuenta | Entorno de GitHub |
  |---|---|---|---|
  | `stages/0-bootstrap` | `0-bootstrap` | una persona | — |
  | `stages/1-base` | `1-base` | `<prefix>-tf-base` | `common` |
  | `stages/2-networks` (hub) | `2-networks/hub` | `<prefix>-tf-net` | `common` |
  | `stages/2-networks/envs/<env>` | `2-networks/<env>` | `<prefix>-tf-net-<env>` | `<env>` |
  | `stages/3-workloads/envs/<env>` | `3-workloads/<env>` | `<prefix>-tf-wl-<env>` | `<env>` |
  | plan, drift, prueba de humo, huérfanos | lee todo el bucket | `<prefix>-tf-read` | cualquiera |

- **WIF.** El proveedor acepta solo tokens del repositorio por su ID numérico y el de su dueño.
  Las cuentas que escriben se toman por `attribute.deploy`, que vale el entorno de GitHub solo si
  el trabajo es el `apply` de `_terraform-root.yml` de este repositorio leído de `main`
  (`job_workflow_ref` exacto), en una ejecución de `main` disparada por `push` o
  `workflow_dispatch`, y `none` si no (`stages/0-bootstrap/wif.tf`). `tf-base` y `tf-net`
  aceptan `common`; cada cuenta de entorno, solo su entorno. Cualquier otro trabajo, de
  cualquier rama o de otro flujo, solo obtiene `tf-read` (pendientes 123, 124 y 156). La regla
  "Deployment branches: `main`" de cada entorno de GitHub queda como segunda barrera.
- **Protección del estado.** La política de denegación del proyecto tiene cuatro reglas. A las
  nueve cuentas les niega, sobre lo que tenga la etiqueta (bucket y llavero del estado, las
  propias cuentas), borrar o cambiar su IAM y suplantar a las cuentas; sin condición, tocar WIF
  y los roles personalizados, crear llaves de cuentas, borrar el proyecto, cambiar los servicios
  habilitados y pedir tokens o firmas de cualquier cuenta de servicio (`actAs` sigue permitido;
  pendiente 127); y leer valores de secretos (salvo `tf-net`). A todos, también a la persona
  dueña, les niega crear llaves de cuentas de servicio (pendiente 155). Que las etiquetas y la
  denegación funcionen sin organización es HYPOTHESIS (ADR 0029 §5).
- **Cuentas de ejecución.** Las de las cargas (`<prefix>-<env>-<app>-<uso>`: `gke-nodes`,
  `workload`, `mig`, `run` y `sched` donde hay apagado) las crea `1-base` con sus permisos
  (`stages/1-base/runtime_accounts.tf`). `tf-wl-<env>` solo tiene `serviceAccountUser` sobre las
  de su entorno que adjunta; `3-workloads` no crea cuentas ni da roles de proyecto.
- **Gobierno sin organización.** Las políticas de organización y el perímetro de VPC-SC solo se
  crean con `org_id` (y `access_policy_id`), en `0-bootstrap` (`org.tf`), que aplica la persona
  con `roles/orgpolicy.policyAdmin` y `roles/accesscontextmanager.policyAdmin`; ninguna cuenta
  del pipeline recibe roles de organización. Sin organización no existen: los cubren las reglas
  de Conftest en cada PR y los pasos manuales del runbook 01. Que no se puedan usar sin
  organización es HYPOTHESIS (ADR 0029 §1).
- **Personas.** Solo lectura por grupos (`readers`, `security_admins`, `auditors` de `1-base`,
  opcionales). La excepción es la persona dueña del proyecto, que necesita `owner` para
  `0-bootstrap`.
- **Qué separa a los entornos** (ADR 0029 §9): una VPC por entorno sin peering entre ellas, el
  prefijo `<prefix>-<env>-` y la etiqueta `env`, una cuenta por entorno ligada a su entorno de
  GitHub y permisos condicionados en Storage, KMS, Secret Manager, Cloud SQL, GKE y Backup and
  DR. **No** los separan, como riesgo aceptado: los permisos sin condición de las cuentas de
  entorno sobre Compute, Cloud Run, Memorystore, Filestore, Backup for GKE, Certificate Manager
  y Monitoring, la creación de un clúster con el nombre de otro entorno (riesgo 3 del ADR 0029
  §9), los agentes de servicio, la regla por defecto de Binary Authorization (sin atestadores
  por entorno) y las cuotas.

## Lo que cambió del primer texto del ADR 0029 al código

El diagrama sigue al código de la rama `r3/cierre` (con el arreglo de la re-revisión de
seguridad, `r2/seg2`). Durante la construcción, las correcciones de R2 y ese arreglo cambió esto
respecto del primer texto del ADR 0029 (24 nov 2026):

| Tema | Primer texto del ADR 0029 | Código |
|---|---|---|
| Políticas de organización y VPC-SC | En `1-base` (§1) | En `0-bootstrap` (`org.tf`), las aplica la persona |
| Cuentas de ejecución de las cargas | Las crea cada raíz de entorno (§4) | Las crea `1-base` (`runtime_accounts.tf`); `3-workloads` solo las lee |
| Cuentas que escriben por WIF | Por `attribute.environment` (§3) | Por `attribute.deploy`: entorno de GitHub, `main`, `_terraform-root.yml` exacto y evento `push` o `workflow_dispatch` |
| Cuenta de Compute por defecto sin Editor (`DEPRIVILEGE`) | En `1-base` (§4) | En `0-bootstrap` (`main.tf`) |
| Rol `<prefix>OffHoursScheduler` | En `1-base` (§4) | Lo crea `0-bootstrap`; `1-base` lo publica como `off_hours_role_id` y se lo da a la cuenta `sched`, condicionado a la instancia y a los clústeres de su entorno |
| Lo que leen las raíces de red | `1-base` (y el hub, los spokes) (§2) | Ninguna lee `1-base`; los spokes leen solo el hub |
| Roles de `tf-read` | Cuatro roles más el bucket (§3) | Los mismos y `serviceusage.serviceUsageConsumer`, que tienen todas las cuentas |
| Regla sin condición de la denegación | WIF (§5) | WIF, roles personalizados, llaves de cuentas, borrar el proyecto, cambiar los servicios habilitados y pedir tokens o firmas; además, una regla que niega a todos crear llaves de cuentas de servicio |
| Roles de GKE y Monitoring de `tf-wl-<env>` | Sin condición (§3) | `container.clusterAdmin` (no `container.admin`), con Cloud SQL y Backup and DR condicionados al entorno; cinco roles finos de Monitoring (no `monitoring.editor`) |

El diseño anterior, de varios proyectos y carpetas, está en la rama `archivo/multiproyecto`.
