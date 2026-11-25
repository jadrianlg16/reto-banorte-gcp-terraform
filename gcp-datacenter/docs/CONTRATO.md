# Contrato de construcción: Datacenter en GCP con Terraform

> Este contrato se reescribió el 24 nov 2026 para el diseño de **un solo proyecto de GCP**
> ([ADR 0029](adr/0029-un-solo-proyecto.md)). La versión de varios proyectos está en la rama
> `archivo/multiproyecto`.

Fuente única para quien construya o revise este repositorio (personas o agentes). Si algo de
aquí contradice la especificación de Banorte, gana la especificación, salvo las desviaciones
listadas en §2, que quedan registradas como ADR.

Estado al 24 nov 2026: todo se construye y se prueba **sin acceso a GCP**. Nada se ha aplicado.
Toda la landing zone vive en un proyecto que crea una persona; la organización es opcional
(ADR 0029 §1). Lo que este documento describe es lo que hace el código del commit en el que se
escribió; lo que solo un apply confirma está en [`pendientes-apply.md`](pendientes-apply.md).

Índice: 1 Reglas · 2 Decisiones cerradas · 3 Estructura · 4 Convenciones · 5 Plan IP ·
6 Estado e identidad · 7 Etapas · 8 Módulos · 9 Políticas, pruebas y pipeline ·
10 Documentación · 11 Paquetes de trabajo · 12 Pendientes del primer apply

---

## 1. Reglas para quien construye

1. Construye solo lo que pide tu paquete de trabajo (§11). No cambies interfaces de §7 y §8:
   si una interfaz no alcanza, detente y repórtalo; no la amplíes por tu cuenta.
2. "Terminado" sin GCP significa que, para tu pieza, pasan **todos**:
   `terraform fmt -check -recursive`, `terraform validate` (con `init -backend=false`),
   `tflint`, `checkov` y `terraform test`. Reporta el comando y la salida, no "pasa".
3. Nunca afirmes que algo "funciona en GCP". Lo que solo se puede comprobar con un apply se
   marca en el código con `# VERIFICAR-EN-APPLY: <qué>` y se agrega a
   `docs/pendientes-apply.md` (§12).
4. Sin valores de máquina ni de cuenta en el código: ni IDs de organización, ni proyectos, ni
   rutas locales, ni correos. Todo entra por variables. El mismo código corre en Windows,
   macOS y Linux (CI).
5. Sin secretos en código, en `tfvars` ni en valores por defecto.
6. Commits sin firma de coautor ni leyendas de herramienta. Una rama por paquete de trabajo.
7. No copies texto de la especificación de Banorte al repositorio: es confidencial. Cítala
   por sección.
8. Descripciones de variables, comentarios y documentación en español. Identificadores
   (variables, recursos, salidas) en inglés, como en la especificación.
9. Regla de recursos únicos (§7.5): una raíz de entorno no declara nada que exista una vez por
   proyecto ni permisos de proyecto para principales que no creó.

---

## 2. Decisiones cerradas

Cada fila es un ADR en `docs/adr/NNNN-titulo.md` (formato en
[`adr/README.md`](adr/README.md)). Las marcadas "desviación" se apartan de la especificación o
de su diagrama y deben decirlo. La columna "Estado" dice si el ADR sigue igual, si se enmendó
para el proyecto único o si lo reemplazó el ADR 0029.

| ADR | Decisión | Motivo | Tipo | Estado |
|---|---|---|---|---|
| [0001](adr/0001-versiones-de-terraform-y-proveedores.md) | Proveedores `hashicorp/google` y `google-beta` en `~> 6.0`; `required_version = ">= 1.9"` | Convención obligatoria de la especificación. La versión vigente del registry es mayor; se actualiza por PR cuando el cliente lo pida. Las pruebas exigen 1.11 (ADR 0021) | Conforme | Vigente |
| [0002](adr/0002-regiones-primaria-y-de-dr.md) | Regiones `us-central1` (primaria) y `us-east4` (DR), ambas como variables | Propuesta de la especificación; `northamerica-south1` si hubiera residencia de datos | Conforme | Enmendado 24 nov (2) |
| [0003](adr/0003-vpc-por-entorno-unida-al-hub-por-peering.md) | Una VPC por entorno (spoke) en el proyecto único, unida a la VPC hub por VPC Network Peering; sin peering entre spokes y sin Shared VPC | El diagrama dibuja una sola Shared VPC en el hub. En un proyecto suelto Shared VPC no existe (necesita organización y proyectos distintos para el host y el servicio). El aislamiento entre entornos lo da la red y no solo el firewall | Desviación del diagrama | Enmendado 24 nov |
| [0004](adr/0004-cloud-nat-en-cada-spoke.md) | Cloud NAT en cada spoke y región, no en el hub | Un Cloud NAT no da salida a redes unidas por peering | Desviación del diagrama | Vigente |
| [0005](adr/0005-balanceador-y-cloud-armor-en-el-proyecto-de-servicio.md) | Balanceador HTTPS global y Cloud Armor en la raíz de cargas de cada entorno (`3-workloads/envs/<env>`) | Ponerlo en el hub crearía una dependencia inversa (`2-networks` leería `3-workloads`), separaría al dueño de la aplicación de su política de Cloud Armor (que se asocia al servicio de backend) y mezclaría entornos en un estado común. El tráfico on-premises sí entra solo por el hub | Desviación del diagrama | Enmendado 24 nov |
| [0006](adr/0006-on-premises-simulado-con-ha-vpn-entre-vpc.md) | On-premises simulado con una VPC `onprem-sim` y HA VPN entre VPC, activable con `simulate_onprem`, y VM DNS opcional (`onprem_dns_vm`) | No hay sitio on-premises real para el equipo. Con `simulate_onprem = false` el mismo módulo apunta a un gateway externo, pero el plan del hub debe fallar en el pipeline (punto 151, por verificar) | Supuesto | Enmendado 24 nov (2) |
| [0007](adr/0007-ci-cd-con-github-actions.md) | CI/CD con GitHub Actions; las cuentas que escriben solo se toman desde `_terraform-root.yml` en `main`, con `push` o `workflow_dispatch` (`attribute.deploy`) | El equipo ya usa GitHub; la especificación lo deja a elección | Conforme | Enmendado 24 nov (3) |
| [0008](adr/0008-llave-kms-propia-de-la-etapa-0.md) | `0-bootstrap` crea su propia llave KMS para cifrar el bucket de estado | La especificación pide CMEK en el bucket de estado (etapa 0); las llaves de los entornos las crea `1-base` después. Sin llave propia habría una ventana sin CMEK | Aclaración | Enmendado 24 nov |
| [0009](adr/0009-perimetro-vpc-sc-en-dos-etapas-y-dry-run.md) | Perímetro de VPC-SC opcional: solo con `org_id` y `access_policy_id`, lo crea la persona de `0-bootstrap` alrededor de todo el proyecto y queda en dry-run | Sin proyectos de prod separados el perímetro no puede separar entornos, y sin organización no hay política de acceso | Aclaración | Reemplazado por 0029 |
| [0010](adr/0010-bucket-de-estado-unico-con-iam-por-prefijo.md) | Un solo bucket de estado con un prefijo por raíz. Cada cuenta escribe solo su prefijo y lee los prefijos que su raíz usa, con condiciones de IAM | La especificación pide a la vez "solo su prefijo" y leer las salidas de la etapa anterior; leer aguas arriba es la interpretación mínima que cumple ambas | Aclaración | Enmendado 24 nov |
| [0011](adr/0011-construccion-en-paralelo-y-despliegue-en-orden.md) | Los módulos y etapas se construyen en paralelo y sin GCP; se aplican en orden 0 → 1 → 2 → 3 cuando exista el proyecto | La regla "ningún sprint empieza sin cerrar el anterior" quedó bloqueada por la falta de acceso a GCP. Se cambia el orden de construcción, no el de despliegue | Desviación del plan | Enmendado 24 nov |
| [0012](adr/0012-gke-mig-y-cloud-run.md) | GKE para las cargas en contenedores y MIG para las que requieran VM; Cloud Run para servicios sin estado. Los tres módulos existen; cada entorno activa los que use en `3-workloads`, con las cuentas de ejecución de `1-base` y Workload Identity por clúster | La especificación exige los tres y pide este ADR | Conforme | Enmendado 24 nov (3) |
| [0013](adr/0013-modulos-propios-sin-modulos-de-terceros.md) | Módulos propios escritos con recursos del proveedor, sin envolver módulos de terceros | Permite pruebas con `mock_provider` sin descargar dependencias y deja cada recurso a la vista del revisor. La especificación permite ambos caminos | Conforme | Vigente |
| [0014](adr/0014-raiz-del-hub-y-raices-de-spoke.md) | La raíz del hub vive en `stages/2-networks/` y cada spoke en `stages/2-networks/envs/<env>/` | El árbol de la especificación solo muestra `envs/`; el hub necesita su propia raíz y su propio estado | Aclaración | Enmendado 24 nov |
| [0015](adr/0015-sin-contrasenas-ni-valores-de-secretos-en-terraform.md) | Sin contraseñas de base de datos: Cloud SQL usa autenticación IAM. El módulo `secrets` crea contenedores y permisos, nunca valores | "Secretos sin texto plano en Terraform": un valor generado por Terraform quedaría en el estado | Aclaración | Enmendado 24 nov (2) |
| [0016](adr/0016-valores-de-etiquetas-en-minusculas.md) | Los valores de etiquetas van en minúsculas (`ti-001`, no `TI-001`) | GCP rechaza mayúsculas en valores de etiquetas; el ejemplo de la especificación no sería válido | Desviación menor | Vigente |
| [0017](adr/0017-nombres-cortos-de-cuentas-de-servicio.md) | Cuentas del pipeline `<prefijo>-tf-<raíz>[-<env>]` (`tf-base`, `tf-net`, `tf-net-<env>`, `tf-wl-<env>`, `tf-read`) y de ejecución `<prefijo>-<env>-<app>-<uso>` (las crea `1-base`) | El límite de 30 caracteres del ID no deja espacio a la convención completa | Desviación menor | Enmendado 24 nov (2) |
| [0018](adr/0018-llave-kms-del-bucket-de-logs-en-la-etapa-1.md) | `1-base` crea la llave KMS del bucket de logs de auditoría (llavero común con las llaves `logs` y `pubsub`) | El bucket de logs exige CMEK desde el primer evento; mismo criterio que el ADR 0008 | Aclaración | Enmendado 24 nov |
| [0019](adr/0019-kms-y-secret-manager-fuera-de-los-servicios-restringidos.md) | Con el perímetro opcional alrededor del proyecto único, KMS y Secret Manager **sí** están en `vpc_sc_restricted_services` por defecto | Ya no hay un proyecto `security` que sirva a entornos fuera del perímetro: llaves, secretos y cargas están en el mismo proyecto | Aclaración | Reemplazado por 0029 |
| [0020](adr/0020-cloud-run-publico-detras-del-balanceador.md) | Cloud Run detrás del balanceador: entrada fija a "interno y balanceador" y verificación de invocador de IAM desactivada solo con `public_via_load_balancer = true`; nunca `allUsers` | Con organización, `iam.allowedPolicyMemberDomains` impide `allUsers`; sin ella la regla se mantiene por validación del módulo. El control de acceso público queda en el balanceador y Cloud Armor | Aclaración | Enmendado 24 nov |
| [0021](adr/0021-pruebas-con-terraform-1-11-y-codigo-con-1-9.md) | El código sigue en `>= 1.9`; las pruebas (`*.tftest.hcl`) usan `override_during = plan` y exigen Terraform 1.11 o mayor. `pr.yml` comprueba el código con 1.9.8 sin `terraform test` y todo con 1.16.5 | Las pruebas necesitan valores conocidos en el plan para afirmar sobre atributos calculados; subir el mínimo del código contradiría la convención | Aclaración | Enmendado 24 nov |
| [0022](adr/0022-estado-y-conmutacion-sin-depender-de-la-region-primaria.md) | Bucket de estado y su llave en la multirregión `US`/`us` (o doble región), segunda HA VPN en la región de DR, balanceador interno uno por región con acceso global y GKE fuera del balanceador externo mientras no haya NEG de DR | La conmutación a DR corre Terraform con la región primaria caída: nada de lo que necesita puede vivir solo ahí | Aclaración | Enmendado 24 nov (2) |
| [0023](adr/0023-endurecimiento-de-la-identidad-del-pipeline.md) | WIF por IDs numéricos del repositorio y del dueño; las cuentas que escriben solo desde `_terraform-root.yml` en `main`, con `push` o `workflow_dispatch` y su entorno de GitHub (`attribute.deploy`); política de denegación del proyecto con la etiqueta `<prefix>-proteccion` y cuatro reglas (la cuarta, sin llaves de cuentas de servicio para nadie); sin `serviceAccountAdmin` ni `tagUser` de proyecto; cuatro roles personalizados; roles de proyecto de las cuentas solo desde `0-bootstrap`, condicionados por nombre donde el servicio lo admite | Las revisiones encontraron caminos para que una cuenta ampliara su acceso; con los tres entornos en un proyecto, la cuenta de un entorno no debe alcanzar el estado ni las cuentas de otro | Aclaración | Enmendado 24 nov (3) |
| [0024](adr/0024-artifact-registry-y-binary-authorization-por-proyecto.md) | Un repositorio de Artifact Registry multirregional por entorno y aplicación, y una sola política de Binary Authorization del proyecto, en `1-base`, con dos modos: lista de permitidos global (riesgo aceptado: no limita los clústeres de prod a su repositorio) o un atestador por entorno (`binary_authorization_env_attestors`) | GKE y Cloud Run exigen Binary Authorization; la imagen debe sobrevivir a la región primaria; un proyecto tiene una sola política | Aclaración | Enmendado 24 nov (2) |
| [0025](adr/0025-plan-aprobacion-y-apply-separados.md) | Plan, aprobación y apply separados: plan sin entorno con la cuenta de lectura `tf-read` y `-lock=false`; apply en el entorno de GitHub con la cuenta de la raíz y la misma huella del plan; `common` protegido como `prod`; `plan-gate` y prueba de humo de dev | La aprobación debe ver el plan que se aplica | Aclaración | Enmendado 24 nov |
| [0026](adr/0026-api-de-google-por-el-vip-restringido-en-todos-los-entornos.md) | `googleapis.com`, `gcr.io`, `pkg.dev` y `run.app` resuelven al VIP de `google_apis_vip` (`restricted` por defecto en los tres entornos) | Imágenes y Cloud Run salían por IP públicas sin pasar por el VIP | Aclaración | Enmendado 24 nov |
| [0027](adr/0027-desviaciones-aceptadas-del-cis.md) | Desviaciones aceptadas del CIS v5.0 (1.1.3, 1.6, 2.1, 2.3, 2.4, 3.8, 3.9, 3.10 en dev y qa, 4.7, 4.11, 4.12, 6.9), cada una con su riesgo y lo que la cierra; flow logs al 100 % en prod, hub y `onprem-sim` y 0.5 en dev y qa; novena métrica de auditoría para políticas de firewall | El mapa CIS separa lo que falta construir de lo que se decidió no cumplir | Desviación del CIS | Enmendado 24 nov (3) |
| [0028](adr/0028-apagado-fuera-de-horario-de-dev-y-qa.md) | Apagado fuera de horario opcional de dev y qa (`off_hours_shutdown`, rechazado en prod): Cloud SQL y pools de GKE con trabajos de Cloud Scheduler que llaman a la API; MIG con programa de escalado. El rol mínimo `<prefix>OffHoursScheduler` lo crea `0-bootstrap` y lo publica `1-base`; la cuenta de los trabajos la crea `1-base` en `off_hours_environments`, con el rol condicionado a su entorno | Mitigación de costo de §8, sin deriva falsa en `drift.yml` y sin dar a ninguna cuenta del pipeline permisos para crear roles | Aclaración | Enmendado 24 nov (3) |
| [0029](adr/0029-un-solo-proyecto.md) | Toda la landing zone en un solo proyecto de GCP: cuatro etapas, organización opcional (la aplica la persona de `0-bootstrap`), nueve cuentas del pipeline, cuentas de ejecución en `1-base`, regla de recursos únicos y destroy sin borrar proyectos; riesgos aceptados: los cuatro residuales de la re-revisión y la lista exacta de roles sin condición | Pedido del cliente en la junta del 23 nov 2026 | Desviación (pedido del cliente) | Enmendado 24 nov (3) |

Los ADR 0001, 0002, 0005 a 0010, 0012, 0013, 0015 y 0018 se enmendaron el 21 nov 2026 y el 0009
otra vez el 23 nov. El 24 nov 2026 se enmendaron para el proyecto único los que dicen
"Enmendado 24 nov" en la tabla, y el 0009 y el 0019 quedaron reemplazados por el 0029 (ver la
línea de estado de cada uno). Ese mismo día, con el código final de las revisiones de seguridad e
integración (ramas `r2/*`), se enmendaron otra vez los que dicen "Enmendado 24 nov (2)", y con
el arreglo de la re-revisión de seguridad (rama `r2/seg2`) una tercera vez los que dicen
"Enmendado 24 nov (3)".

### 2.1 Decisiones de construcción sobre el ADR 0029

Los constructores del rediseño (24 nov 2026) y las ramas de arreglo de las revisiones de
seguridad e integración (`r2/*`, el mismo día) se apartaron del primer texto del ADR 0029 en
estos puntos. Son decisiones vigentes: el código las aplica, la enmienda del ADR 0029 del
2026-11-24 las recoge y el resto de este contrato las describe. La tabla queda como registro de
qué cambió y por qué.

| Decisión vigente | Dónde | Qué decía el primer texto del ADR 0029 | Por qué |
|---|---|---|---|
| `DEPRIVILEGE` de la cuenta de Compute por defecto en `0-bootstrap` | `stages/0-bootstrap/main.tf` | En `1-base` (§4) | Quitar un rol básico pide `setIamPolicy` sin condición, y ninguna cuenta del pipeline lo tiene |
| El rol `<prefix>OffHoursScheduler` lo crea `0-bootstrap`; `1-base` lo publica como `off_hours_role_id` | `stages/0-bootstrap/custom_roles.tf`, `stages/1-base/outputs.tf` | En `1-base` (§4) | Ninguna cuenta del pipeline tiene `iam.roleAdmin` |
| Políticas de organización y perímetro de VPC-SC en `0-bootstrap`, aplicados por la persona con `roles/orgpolicy.policyAdmin` y `roles/accesscontextmanager.policyAdmin`; `org_id`, `access_policy_id`, `directory_customer_id`, `additional_allowed_locations` y `vpc_sc_restricted_services` son variables de `0-bootstrap` | `stages/0-bootstrap/org.tf` | En `1-base`, con roles de organización para `tf-base` (§1) | `orgpolicy.policyAdmin` solo se da en la organización y alcanza a toda ella; quien edita la política de acceso cambia cualquier perímetro (puntos 125 y 126) |
| Las cuentas que escriben aceptan `attribute.deploy`, que vale el entorno de GitHub solo con `ref == refs/heads/main`, `job_workflow_ref == <repo>/.github/workflows/_terraform-root.yml@refs/heads/main` y `event_name` `push` o `workflow_dispatch` | `stages/0-bootstrap/wif.tf`, `service_accounts.tf` | `attribute.environment` (§3) | Cualquier rama que declarara el entorno obtenía la cuenta (puntos 123 y 124); la re-revisión encontró que el prefijo `.github/workflows/` dejaba pasar cualquier flujo, también uno con `pull_request_target` (hallazgo N3, punto 156) |
| Las cuentas de ejecución (`gke_nodes`, `workload`, `mig`, `run` y `sched`), sus roles, la lectura de secretos y repositorios, Cloud SQL condicionado y Workload Identity por clúster los crea `1-base`; `tf-wl-<env>` solo recibe `serviceAccountUser` sobre las que adjunta | `stages/1-base/runtime_accounts.tf` | Cada raíz de entorno crea sus principales (§4) | Con `TfServiceAccountManager`, `serviceAccountUser` y `projectIamAdmin` delegado a nivel de proyecto, la cuenta de cargas alcanzaba las cuentas de otros entornos (puntos 131 a 135) |
| `tf-base` recibe `<prefix>TfServiceAccountManager` en lugar de `iam.serviceAccountAdmin`; ninguna cuenta tiene `serviceAccountAdmin` | `stages/0-bootstrap/custom_roles.tf` | — | `serviceAccountAdmin` incluye `deleteTagBinding`, que no se puede negar: con `tagUser` dejaría quitar la etiqueta de protección |
| Ninguna cuenta del pipeline tiene `tagUser` ni `tagAdmin` de proyecto: los spokes usan `<prefix>TfNetworkTagManager` y dan a `tf-wl-<env>` `tagUser` solo sobre sus valores `lb_backend` e `iap_ssh`; el `tagUser` de los agentes de GKE y de `cloudservices` lo da `0-bootstrap` | `stages/0-bootstrap/custom_roles.tf`, `main.tf`, `stages/2-networks/envs/<env>/firewall.tf` | — (el primer código daba `tagAdmin` a los spokes y `tagUser` de proyecto a las cargas) | `tagUser` trae `iam.serviceAccounts.deleteTagBinding` (puntos 136 y 137) |
| La denegación tiene cuatro reglas: con etiqueta; sin condición (tokens y firmas de cualquier cuenta, WIF, roles, `serviceAccountKeys.create`, `projects.delete` y los servicios habilitados); valores de secretos para todas salvo `tf-net`; y `serviceAccountKeys.create` para `principalSet://goog/public:all`, sin excepción. La etiqueta se liga también al llavero del estado y a las nueve cuentas | `stages/0-bootstrap/deny_policy.tf` | WIF y roles; etiqueta en el bucket (§5) | Ninguna cuenta del pipeline los necesita; `actAs` no se niega porque adjuntar una cuenta lo pide (punto 127). Sin organización nada impedía que `tf-base` diera a otro principal el poder de crear llaves (hallazgos N2 y N4, puntos 154 y 155) |
| Binary Authorization con dos modos: sin atestadores por entorno, lista de permitidos global (las reglas de prod no limitan a su repositorio); con `binary_authorization_env_attestors`, cada clúster `<prefix>-<env>-<app>-gke[-dr]` exige el atestador de su entorno | `stages/1-base/artifacts.tf` | Una regla por clúster de prod que solo admite el repositorio de prod (§4) | Una imagen de la lista se admite sin importar las reglas; limitar prod exige atestaciones (ADR 0024, punto 139) |
| Solo las llaves KMS que alguien usa; las de `dr_region` y la `storage` de `us` solo en `dr_environments` (por defecto prod) | `stages/1-base/kms.tf` | — (el primer código creaba todas las llaves en las tres ubicaciones) | Costo (`estimacion-de-costos.md`) |
| Formatos de salida de `1-base`: `kms_key_ids` con llaves `<uso>`, `<uso>_dr` y `<uso>_us`; repositorios como URL; `notification_channel_ids = { security, operations }` (`operations` solo con `operations_alert_email`) | `stages/1-base/outputs.tf` | `kms_key_ids` entorno → uso; repositorios `{id, url}` | Mismo formato que leía la raíz de cargas anterior. `3-workloads` acepta también las otras formas y solo usa el canal `operations` (punto 138) |
| VM DNS opcional de `onprem-sim` (`onprem_dns_vm`), con su cuenta en `1-base` y `compute.instanceAdmin.v1` para el hub mientras esté encendida | `stages/2-networks/onprem_dns.tf`, `stages/1-base/onprem_dns.tf` | Se creaba a mano | Probar el reenvío DNS sin recursos manuales (puntos 128 a 130) |
| Personas solo como `group:`, con las llaves `readers`, `security_admins` y `auditors` | `stages/1-base/iam.tf` | "grupos o usuarios" (§4) | Regla 7 de Conftest (§9.1) |
| El módulo `org` ya no tiene `compute.skipDefaultNetworkCreation` | `modules/org/main.tf` | — | Solo actúa al crear un proyecto; la red `default` se borra a mano (runbook 01) |
| La llave `backup` es solo para Backup for GKE; la bóveda de Backup and DR no usa llave | `stages/1-base/kms.tf` | — | — |
| `cloudscheduler.admin` solo para `tf-wl-dev` y `tf-wl-qa` | `stages/0-bootstrap/service_accounts.tf` | — | Prod no admite el apagado (ADR 0028) |
| Las nueve cuentas reciben `serviceusage.serviceUsageConsumer` | `stages/0-bootstrap/service_accounts.tf` | No lo lista (§3) | Proyecto de cuota de las llamadas |
| La regla sin etiqueta de la denegación niega además `serviceAccountKeys.create`, `projects.delete` y `serviceusage.services.enable`, `services.disable` y `consumerpolicy.update`; la etiqueta se liga también al llavero del estado | `stages/0-bootstrap/deny_policy.tf` | WIF y roles; etiqueta en el bucket (§5) | Ninguna cuenta del pipeline los necesita; las APIs las habilita `0-bootstrap`, que aplica una persona (hallazgo N2, punto 154) |
| `tf-wl-<env>` tiene `container.clusterAdmin` en lugar de `container.admin`; `cloudsql.admin`, `container.clusterAdmin` y `backupdr.admin` van condicionados a los recursos de su entorno (`resource.type != <tipo> \|\| resource.name.startsWith(<prefijo>)`); Monitoring va con cinco roles finos en lugar de `monitoring.editor` | `stages/0-bootstrap/service_accounts.tf` | Compute, GKE, Cloud SQL y los demás servicios sin condición (§3) | `container.admin` trae permisos sobre los objetos de Kubernetes de todos los clústeres, también los secretos y tokens de prod; `monitoring.editor` trae permisos de Service Usage (hallazgos N1 y N2, puntos 152 y 153) |
| La cuenta `sched` recibe `<prefix>OffHoursScheduler` condicionado a la instancia de Cloud SQL y a los clústeres de su entorno | `stages/1-base/runtime_accounts.tf` | La raíz de entorno lo daba como permiso de proyecto, sin condición (§4) | El rol de un entorno alcanzaba las instancias y los clústeres de prod (hallazgo N4, punto 157) |
| Workload Identity por clúster: `1-base` enlaza la cuenta `workload` al `principalSet` de todos los pods de `<prefix>-<env>-<app>-gke[-dr]`; ya no existe `gke_workload_ksa_name` y la salida `gke_workload_identity_members` es entorno → aplicación → clúster | `stages/1-base/runtime_accounts.tf`, `outputs.tf` | Namespace `<app>-<env>` validado (§9) | El principal de un namespace vale desde cualquier clúster del proyecto: otro entorno con un namespace del mismo nombre tomaba la cuenta (hallazgo N1, punto 158) |
| Conftest (`env_root_scope`) rechaza todo `google_project_iam_member`, `google_project_iam_member_remove` y `google_service_account_iam_*` en las raíces de entorno; el IAM de recursos sigue permitido | `policies/env_root_scope.rego` | Solo el IAM de proyecto para principales que la raíz no creó (§4) | Las raíces de entorno ya no crean cuentas (hallazgo N5, punto 146) |
| La bóveda de Backup and DR lleva `access_restriction` por variable, `WITHIN_PROJECT` por defecto | `modules/backup-dr/main.tf`, `variables.tf` | — | Sin el campo la API usa `WITHIN_ORGANIZATION`, y el valor no se cambia después (punto 159) |
| `1-base` recibe `project_id` por variable, con una precondición que lo compara con `0-bootstrap` | `stages/1-base/main.tf` | — | Mismo origen que las demás raíces (`GCP_TFVARS_JSON.common`) |
| Las raíces de red no leen `1-base`; el hub no lee ningún estado | `stages/2-networks/`, `stages/0-bootstrap/service_accounts.tf` | Hub y spokes leen `1-base` (§2) | No usan ninguna salida de `1-base`, y `tflint` rechaza un dato remoto sin uso |
| El hub ya no publica `hub_project_id`; `spoke_supernets` es interfaz y el spoke la lee sin `try` | `stages/2-networks/outputs.tf`, `envs/<env>/remote_state.tf` | — | Todo vive en `project_id` |
| La política de red del hub no tiene reglas `allow` (solo la denegación por defecto); el módulo `firewall` no admite `goto_next` | `stages/2-networks/firewall.tf`, `modules/firewall/variables.tf` | — | Lo que antes se delegaba al hub terminaba en la denegación implícita de la VPC; en una política de red, `goto_next` solo pasaría a las reglas implícitas |
| `3-workloads` no lee `security_alert_email` y no tiene bloques `moved` | `stages/3-workloads/envs/<env>/` | — | Las alertas de auditoría están en `1-base`; el estado es nuevo |
| Terratest corre por defecto en un solo proyecto de pruebas (`TERRATEST_PROJECT_ID`), que no puede ser el de la landing zone (`scripts/terratest-project-check.py`); con `TEST_EPHEMERAL_PROJECTS=true`, un proyecto efímero por prueba. Sin `TERRATEST_ORG_ID`, `TestOrg` y `TestVPCSC` se omiten con la marca `[sin-organizacion]`. La prueba de extremo a extremo destruye el spoke solo con `TEST_E2E_DESTROY_NETWORK` | `tests/`, `.github/workflows/terratest.yml` | Un proyecto efímero por módulo (§9.2 anterior) | Puede no haber organización (punto 145) |
| `destroy-plan-check.py` rechaza además `google_project` y los recursos únicos del proyecto, y acepta un recurso hijo si su padre (de forma transitiva) está en el plan y pasó | `scripts/destroy-plan-check.py` | Solo nombres sin `<prefix>-<env>-` (§8) | Sin eso, el destroy legítimo del spoke se bloqueaba |
| Un cambio en `stages/0-bootstrap/` no planea ninguna raíz | `scripts/affected-roots.sh` | — | Las demás raíces leen el estado de `0-bootstrap`, que no cambia hasta que una persona la aplica |
| dev y qa se pueden dejar fuera del pipeline con la variable de repositorio `GCP_DISABLED_ENVS`; prod nunca | `.github/workflows/apply.yml`, `drift.yml`, `scripts/disabled-envs.py` | — | Rebanada solo-dev y entornos destruidos (puntos 143 y 144) |

Pendiente de decidir por el equipo (no bloquea la construcción): usuarios de GitHub para
`CODEOWNERS` (se usan marcadores `@PENDIENTE-red`, `@PENDIENTE-seguridad`,
`@PENDIENTE-plataforma`). `.github/`, `stages/0-bootstrap/`, `scripts/`, `.checkov.yaml`,
`.tflint.hcl` y `tests/e2e/` son solo de seguridad: deciden quién puede aplicar y qué se revisa.

---

## 3. Estructura del repositorio

El proyecto vive en `gcp-datacenter/` dentro del repositorio del equipo. `.github/` va en la
raíz del repositorio porque GitHub solo lee flujos de ahí; todos los flujos usan
`working-directory: gcp-datacenter`.

```
.github/
  workflows/{pr.yml, apply.yml, _terraform-root.yml, destroy.yml, drift.yml, terratest.yml}
  CODEOWNERS
  dependabot.yml
gcp-datacenter/
  README.md
  modules/<modulo>/          # 24 módulos (§8)
    main.tf  variables.tf  outputs.tf  versions.tf  README.md
    examples/basic/main.tf
    tests/<modulo>.tftest.hcl
  stages/
    0-bootstrap/             # una persona, a mano (runbook 01)
    1-base/                  # lo que existe una vez por proyecto (§7.1)
    2-networks/              # raíz del hub
      envs/{dev,qa,prod}/    # una raíz por spoke
    3-workloads/
      envs/{dev,qa,prod}/    # una raíz de cargas por entorno
  policies/                  # Rego para Conftest, sus pruebas y planes de ejemplo (fixtures/)
  tests/                     # Terratest (Go): integration/, e2e/, fixtures/, helpers/
  scripts/                   # check.sh, docs.sh, policy-check.sh, selftest.sh y utilidades
                             # del pipeline
  docs/{adr/, runbooks/, diagramas/, CONTRATO.md, pendientes-apply.md, pipeline.md, …}
```

Los 24 módulos (`ls gcp-datacenter/modules`, 24 nov 2026): `audit-alerts`, `backup-dr`,
`cloud-armor`, `cloud-run`, `cloud-sql`, `compute-mig`, `dns`, `filestore`, `firewall`, `gke`,
`hybrid-connectivity`, `iam`, `kms`, `load-balancer`, `log-export`, `memorystore`,
`network-hub`, `network-spoke`, `observability`, `off-hours-shutdown`, `org`, `secrets`,
`storage` y `vpc-sc`. `folders` y `project-factory` ya no existen: sin carpetas ni proyectos que
crear no tienen uso.

Cada raíz de `stages/` contiene: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`,
`providers.tf`, `backend.tf`, `remote_state.tf` (si lee otras raíces), `terraform.tfvars.example`,
`README.md`, `.terraform.lock.hcl` y `tests/`. `0-bootstrap` reparte su contenido en
`service_accounts.tf`, `custom_roles.tf`, `wif.tf` y `deny_policy.tf`, y no tiene
`remote_state.tf` (sí `backend_override.tf.example`, para el arranque con estado local); tampoco
el hub, que no lee ningún estado (§2.1). `0-bootstrap` tiene además `org.tf` (organización y
VPC-SC). `1-base` reparte el suyo en `kms.tf`, `artifacts.tf`, `iam.tf`, `runtime_accounts.tf`
y `onprem_dns.tf`; el hub en `vpn.tf`, `dns.tf`, `firewall.tf` y `onprem_dns.tf`; cada spoke en
`dns.tf` y `firewall.tf`; `3-workloads` en `service_accounts.tf` (lee las cuentas de `1-base`),
`compute.tf`, `data.tf`, `load_balancing.tf`, `operations.tf` y `off_hours.tf`.

Las raíces de `envs/{dev,qa,prod}` de una misma etapa son idénticas salvo `backend.tf` (prefijo)
y `terraform.tfvars.example`. La lógica común va en los módulos, no copiada tres veces.

`scripts/` tiene, además de `check.sh`, `docs.sh`, `policy-check.sh` y `selftest.sh`, las
utilidades de los flujos: `affected-roots.sh`, `root-tfvars.py`, `plan-fingerprint.py`,
`plan-gate.sh`, `cut-plan.py`, `check-main-tip.sh`, `destroy-guard.sh`, `destroy-plan-check.py`,
`destroy-orphans.py`, `unmanaged-resources.py` (con `unmanaged-allowlist.txt`),
`disabled-envs.py`, `terratest-project-check.py`, `go-test-report.sh`, `module-tests.sh` y
`plan-offline.sh`.

---

## 4. Convenciones

### 4.1 Versiones

Todo `versions.tf`:

```hcl
terraform {
  required_version = ">= 1.9"
  required_providers {
    google      = { source = "hashicorp/google", version = "~> 6.0" }
    google-beta = { source = "hashicorp/google-beta", version = "~> 6.0" }
  }
}
```

Los módulos declaran solo los proveedores que usan y no contienen bloques `provider`.
Las raíces versionan `.terraform.lock.hcl` generado con
`terraform providers lock -platform=windows_amd64 -platform=linux_amd64 -platform=darwin_arm64`.
No usar en el código (`*.tf`) funciones ni atributos que exijan Terraform posterior a 1.9 (por
ejemplo, atributos de solo escritura). Las pruebas (`*.tftest.hcl`) sí usan
`override_during = plan`, que exige Terraform 1.11 o mayor (ADR 0021): con 1.9 solo corre
`bash scripts/check.sh --skip test`.

### 4.2 Nombres

`<empresa>-<entorno>-<dominio>-<recurso>`. `empresa` es `var.prefix` (ejemplo: `bnt`).
`entorno` es `bootstrap` (`0-bootstrap`), `common` (`1-base` y el hub), `dev`, `qa` o `prod`.
Dominios:

| Dominio | Uso |
|---|---|
| `net` | VPC, subredes, routers, NAT, VPN, DNS, firewall |
| `sec` | KMS, secretos, VPC-SC, WIF, política de denegación |
| `app` | Cómputo: GKE, MIG, Cloud Run, balanceadores |
| `data` | Cloud SQL, Memorystore, Storage, Filestore |
| `ops` | Logs, monitoreo, alertas, estado, presupuesto |
| `bkp` | Respaldo y DR |

Proyecto: uno solo. Lo crea una persona, lo liga a una cuenta de facturación de pago y entra a
todas las raíces como `project_id`; ninguna raíz crea ni borra proyectos (ADR 0029 §1). Los
nombres de bucket son globales: `0-bootstrap` y `1-base` aceptan `name_suffix` (hasta 8
minúsculas o dígitos, vacío por defecto) que se agrega al bucket de estado y al de logs.

Todo recurso de una raíz de entorno lleva `<prefix>-<env>-` en el nombre (o `<env>` dentro de
los nombres cortos que limita GCP, ADR 0017), salvo lo que GCP nombra dentro de un padre propio
del entorno: reglas de una política de firewall, valores de etiqueta y registros DNS (§7.5). Los
clústeres de GKE se llaman `<prefix>-<env>-<app>-gke[-dr]`, por convención fija (ADR 0024).

Los recursos con región agregan el código corto: `usc1` (us-central1), `use4` (us-east4).
El código corto se calcula con un mapa en variables, no se escribe a mano.

Dentro de Terraform, los nombres de recurso son descriptivos y en singular
(`google_compute_network.this` cuando el módulo crea uno solo).

### 4.3 Etiquetas

Toda raíz recibe `labels` (map(string)) y arma:

```hcl
locals {
  labels = merge(var.labels, {
    env        = var.environment
    managed_by = "terraform"
  })
}
```

`0-bootstrap` usa `env = bootstrap` y `1-base` y el hub `env = common`. Lo que `1-base` crea
para un entorno (llaves, secretos, repositorios) lleva el `env` de ese entorno: la búsqueda de
huérfanos del destroy reconoce los recursos de un entorno por esa etiqueta (ADR 0029 §8).

Todo módulo que cree recursos etiquetables recibe `labels` con esta validación (copiarla tal cual):

```hcl
variable "labels" {
  description = "Etiquetas comunes. Obligatorias: env, app, owner, cost_center, managed_by."
  type        = map(string)

  validation {
    condition = alltrue([
      for k in ["env", "app", "owner", "cost_center", "managed_by"] : contains(keys(var.labels), k)
    ])
    error_message = "Faltan etiquetas obligatorias: env, app, owner, cost_center, managed_by."
  }
  validation {
    condition     = lookup(var.labels, "managed_by", "") == "terraform"
    error_message = "managed_by debe ser \"terraform\"."
  }
  validation {
    condition     = alltrue([for v in values(var.labels) : can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "Los valores de etiquetas van en minúsculas, dígitos, guion o guion bajo."
  }
}
```

Los recursos que no admiten etiquetas (por ejemplo, políticas de organización) no las llevan;
la política de Conftest solo las exige en los tipos de recurso que las admiten.

### 4.4 Variables y salidas

- Toda variable lleva `description` y `type`. Las de formato conocido llevan `validation`:
  CIDR (`can(cidrhost(v, 0))`), `environment` (`dev`, `qa`, `prod`), regiones, IDs.
- Variables comunes y sus nombres exactos (los de la especificación): `org_id` (opcional, `null`
  por defecto; solo en `0-bootstrap`), `billing_account` (solo `0-bootstrap`, para el
  presupuesto), `environment`, `primary_region`, `dr_region`, `subnet_cidrs`, `onprem_cidrs`,
  `gke_node_pools`, `sql_tier`, `labels`. Además: `project_id` (todas las raíces), `prefix`,
  `name_suffix` y `state_bucket` (las raíces que leen estado).
- Toda salida lleva `description`. Ninguna salida es sensible; si lo fuera, el diseño está mal.
- Sin `count` para colecciones con identidad: usar `for_each` con llaves estables.

### 4.5 Cada módulo entrega

`README.md` con los marcadores `<!-- BEGIN_TF_DOCS -->` / `<!-- END_TF_DOCS -->` (lo llena
terraform-docs) y un párrafo que diga qué crea y qué exige la especificación; un ejemplo que
valida en `examples/basic/`; y al menos una prueba en `tests/` (§9.2).

---

## 5. Plan de direccionamiento

Propuesta del equipo (coincide con los diagramas entregados). `X` = 10 (dev), 20 (qa), 30 (prod).
Estos valores van en los `terraform.tfvars.example`, nunca dentro de los módulos. Las cinco VPC
(hub, `onprem-sim` y los tres spokes) están en el mismo proyecto (ADR 0029 §6).

| Llave de `subnet_cidrs` | Rango | Región | Uso |
|---|---|---|---|
| `app` | 10.X.0.0/20 | primaria | VM y nodos de GKE |
| `app_dr` | 10.X.16.0/20 | DR | igual, en DR |
| `proxy` | 10.X.32.0/23 | primaria | subred proxy-only del balanceador interno |
| `proxy_dr` | 10.X.34.0/23 | DR | |
| `run` | 10.X.36.0/24 | primaria | salida directa a VPC de Cloud Run |
| `run_dr` | 10.X.37.0/24 | DR | |
| `gke_master` | 10.X.38.0/28 | primaria | plano de control de GKE |
| `gke_master_dr` | 10.X.38.16/28 | DR | |
| `pods` | 10.X.64.0/18 | primaria | rango secundario de `app` |
| `services` | 10.X.128.0/20 | primaria | rango secundario de `app` |
| `services_dr` | 10.X.160.0/20 | DR | rango secundario de `app_dr` |
| `psa` | 10.X.176.0/20 | global | Private Service Access (Cloud SQL, Memorystore, Filestore) |
| `pods_dr` | 10.X.192.0/18 | DR | rango secundario de `app_dr` |

Libres en cada /16: 10.X.39.0 – 10.X.63.255 y 10.X.144.0 – 10.X.159.255.

| Red | Rango |
|---|---|
| Hub | 10.0.0.0/16: `hub` 10.0.0.0/24 (primaria), `hub_dr` 10.0.1.0/24 (DR) |
| On-premises (real o simulado) | 192.168.0.0/16 (`onprem_cidrs`); la VPC simulada usa 192.168.0.0/24 |
| Sesiones BGP | VPN primaria 169.254.0.0/30 y 169.254.0.4/30 (`vpn_bgp_ranges`); VPN de DR 169.254.0.8/30 y 169.254.0.12/30 (`vpn_dr_bgp_ranges`, con `enable_vpn_dr`) |
| ASN | Hub 64514 (`hub_asn`); on-premises 65001 (`onprem_asn`) |
| DNS | Zonas privadas `<env>.empresa.internal.`; dominio on-premises `var.onprem_dns_domain` |

Validaciones obligatorias en las raíces de `2-networks`: ningún rango de `subnet_cidrs` ni del
hub se traslapa con `onprem_cidrs`, y los rangos de un spoke caben en su /16.

En dev y qa las llaves `*_dr` se reservan pero no se crean (`enable_dr = false`).

---

## 6. Estado remoto e identidad del pipeline

### 6.1 Bucket y prefijos

Un bucket en el proyecto único, `<prefix>-bootstrap-ops-tfstate[-<name_suffix>]`: versionado,
acceso uniforme, sin acceso público, `prevent_destroy` y CMEK con la llave de `0-bootstrap`
(ADR 0008). El backend `gcs` bloquea el estado de forma nativa. El bucket y su llave están en
`state_bucket_location` (multirregión `US` y llavero `us` por defecto) o en una doble región
(`state_bucket_dual_regions`), no en `primary_region`: la conmutación a DR necesita el estado
con la región primaria caída (ADR 0022).

| Raíz | Prefijo | Cuenta que aplica | Entorno de GitHub | Lee además |
|---|---|---|---|---|
| `0-bootstrap` | `0-bootstrap` | una persona, a mano | — | nada |
| `1-base` | `1-base` | `<prefix>-tf-base` | `common` | `0-bootstrap` |
| `2-networks` (hub) | `2-networks/hub` | `<prefix>-tf-net` | `common` | nada |
| `2-networks/envs/<env>` | `2-networks/<env>` | `<prefix>-tf-net-<env>` | `<env>` | `2-networks/hub` |
| `3-workloads/envs/<env>` | `3-workloads/<env>` | `<prefix>-tf-wl-<env>` | `<env>` | `1-base`, `2-networks/<env>` |
| todas (plan, drift, humo) | — | `<prefix>-tf-read` | cualquiera | todo el bucket |

La columna "Lee además" es la lista `reads` de `local.stage_roots` en
`stages/0-bootstrap/service_accounts.tf`, que la publica la salida `state_iam_conditions`. Las
raíces de red no leen `1-base` (§2.1). Ninguna raíz lee un prefijo que no esté en su fila.

`backend.tf` de cada raíz fija solo el prefijo; el bucket llega por
`terraform init -backend-config="bucket=<bucket>"`. Las lecturas usan
`data "terraform_remote_state"` con `var.state_bucket` y se concentran en `remote_state.tf`,
que expone `locals` con los valores usados. El hub no tiene `state_bucket` porque no lee nada.

`0-bootstrap` arranca con estado local y lo migra al bucket con `terraform init -migrate-state`;
ese paso manual está permitido porque pertenece a la etapa 0 y se documenta en su runbook.

### 6.2 Permisos sobre el estado

Por cada cuenta que escribe: `roles/storage.objectAdmin` condicionado a los objetos de su
prefijo, y `roles/storage.objectViewer` condicionado a los prefijos de "Lee además". Las
condiciones usan `resource.name.startsWith("projects/_/buckets/<bucket>/objects/<prefijo>/")`:
la barra final da coincidencia exacta de prefijo. `storage.objects.list` se evalúa sobre el
bucket, así que una condición solo por nombre de objeto impediría listar: cada condición agrega
`resource.type == "storage.googleapis.com/Bucket" ||` para permitir el listado. Consecuencia
aceptada: toda cuenta ve los nombres de los objetos del bucket, no su contenido.
`<prefix>-tf-read` tiene `roles/storage.objectViewer` sobre todo el bucket, sin condición.
`# VERIFICAR-EN-APPLY`: que el backend funcione con la condición; alternativa documentada:
carpetas administradas de Cloud Storage con IAM propio (ADR 0010).

### 6.3 Cuentas del pipeline y sus roles

Nueve cuentas, todas en el proyecto y creadas por `0-bootstrap`
(`stages/0-bootstrap/service_accounts.tf`). Los roles de proyecto se dan **solo** desde
`0-bootstrap`, con el módulo `iam`: ninguna raíz de entorno declara un rol de proyecto para una
cuenta del pipeline (§7.5). Que cada lista alcance para aplicar su raíz es HYPOTHESIS hasta el
primer apply (`VERIFICAR-EN-APPLY` en el mismo archivo); un permiso que falte se agrega ahí, con
el rol predefinido más chico.

Condiciones de IAM que se usan
([atributos de recurso](https://docs.cloud.google.com/iam/docs/conditions-resource-attributes)):

- **Buckets por dominio de nombres:** `resource.name.startsWith("projects/_/buckets/<prefix>-<dominio>-")`,
  con `<dominio>` = `common` para `tf-base` y `<env>` para `tf-wl-<env>`. Ninguna cuenta tiene
  `roles/storage.admin` sin condición, así que ninguna alcanza el bucket de estado
  (`<prefix>-bootstrap-…`).
- **KMS sin el llavero del estado** (`tf-base`): todo `projects/<id>/locations/…/keyRings/…`
  salvo los llaveros `<prefix>-bootstrap-` de la ubicación del estado.
- **Concesión delegada** (solo `tf-base`): `roles/resourcemanager.projectIamAdmin` con
  `api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([...])`: la cuenta
  solo puede agregar o quitar los roles de la lista. Limita los roles, no a quién se dan. La
  documentación limita la lista a 10 roles
  ([límites](https://cloud.google.com/iam/docs/setting-limits-on-granting-roles)), así que son
  dos asignaciones, una por lista.
- **Cloud SQL, GKE y Backup and DR por entorno** (`tf-wl-<env>`, `local.workloads_conditions`):
  `resource.type != <tipo> || resource.name.startsWith(<prefijo>)`, que limita el nombre solo
  cuando el permiso se evalúa sobre ese tipo y deja pasar lo que se evalúa sobre otro (por
  ejemplo, el proyecto):
  - `cloudsql.admin`: tipos `sqladmin.googleapis.com/Instance` y `BackupRun`, prefijo
    `projects/<id>/instances/<prefix>-<env>-data-`;
  - `container.clusterAdmin`: tipo `container.googleapis.com/Cluster`, prefijo
    `projects/<id>/locations/<primary_region o dr_region>/clusters/<prefix>-<env>-`;
  - `backupdr.admin`: tipo `backupdr.googleapis.com/BackupVaults`, prefijo
    `projects/<id>/locations/<primary_region o dr_region>/backupVaults/<prefix>-<env>-`.

  La referencia de permisos de GKE evalúa `container.clusters.create` sobre el proyecto, así que
  la condición no limita el nombre de un clúster nuevo; la documentación de Cloud SQL no dice
  cómo se evalúa crear una instancia (ADR 0029 §9, riesgo 3; `VERIFICAR-EN-APPLY`, punto 152).
- Compute, Cloud Run, Memorystore, Filestore, Backup for GKE, Certificate Manager, Monitoring,
  red, cuentas de servicio y etiquetas van **sin condición**: no admiten `resource.name`, o su
  rol abarca tipos que no lo admiten, y una condición por nombre sobre un tipo que no la admite
  niega todo. La lista exacta de lo que eso deja alcanzar en otro entorno está en el ADR 0029 §9
  (riesgo aceptado).

Roles en el proyecto (`base_roles`, `hub_roles`, `net_env_roles`, `workloads_roles` y
`read_roles` de `stages/0-bootstrap/service_accounts.tf`):

| Cuenta | Aplica | Roles en el proyecto (condición) |
|---|---|---|
| `<prefix>-tf-base` | `1-base` | `cloudkms.admin` (KMS sin el llavero del estado); `<prefix>TfSecretContainerAdmin`; `<prefix>TfServiceAccountManager` (cuentas de ejecución y de la VM DNS); `artifactregistry.admin`; `binaryauthorization.policyEditor`; `logging.configWriter`; `monitoring.alertPolicyEditor`; `monitoring.notificationChannelEditor`; `essentialcontacts.admin`; `pubsub.admin`; `securitycenter.notificationConfigEditor`; `storage.admin` (buckets `<prefix>-common-`); `resourcemanager.projectIamAdmin` dos veces, con concesión delegada: personas (`cloudkms.viewer`, `iam.securityReviewer`, `logging.privateLogViewer`, `logging.viewer`, `monitoring.viewer` y `viewer`, `base_grantable_roles`) y cuentas de ejecución (`autoscaling.metricsWriter`, `cloudsql.client`, `cloudsql.instanceUser`, `cloudtrace.agent`, `logging.logWriter`, `monitoring.metricWriter`, `monitoring.viewer`, `stackdriver.resourceMetadata.writer` y `<prefix>OffHoursScheduler`, `runtime_grantable_roles`) |
| `<prefix>-tf-net` | hub de `2-networks` | `compute.networkAdmin`, `compute.securityAdmin`, `dns.admin`; con `onprem_dns_vm = true`, además `compute.instanceAdmin.v1` (VM DNS de `onprem-sim`) |
| `<prefix>-tf-net-<env>` | spoke de `<env>` | `compute.networkAdmin`, `compute.securityAdmin`, `dns.admin`, `<prefix>TfNetworkTagManager` (etiquetas seguras del spoke y su IAM) y `servicenetworking.networksAdmin` (PSA) |
| `<prefix>-tf-wl-<env>` | `3-workloads/envs/<env>` | Con condición: `backupdr.admin` (bóvedas `<prefix>-<env>-`), `cloudsql.admin` (instancias `<prefix>-<env>-data-`), `container.clusterAdmin` (clústeres `<prefix>-<env>-`) y `storage.admin` (buckets `<prefix>-<env>-`). Sin condición: `certificatemanager.editor`, `compute.instanceAdmin.v1`, `compute.loadBalancerAdmin`, `compute.securityAdmin`, `compute.networkUser`, `file.editor`, `gkebackup.admin`, `monitoring.alertPolicyEditor`, `monitoring.dashboardEditor`, `monitoring.notificationChannelEditor`, `monitoring.servicesEditor`, `monitoring.uptimeCheckConfigEditor`, `redis.admin` y `run.admin`; en dev y qa, `cloudscheduler.admin`. Ni `container.admin` (trae permisos sobre los objetos de Kubernetes de todos los clústeres) ni `monitoring.editor` (trae permisos de Service Usage). Ningún rol de cuentas de servicio, de IAM de proyecto, de KMS, de secretos ni de etiquetas en el proyecto |
| `<prefix>-tf-read` | ninguna: `plan` de `pr.yml` y `apply.yml`, `drift.yml`, prueba de humo y huérfanos | `viewer`, `iam.securityReviewer`, `cloudasset.viewer`, `networkmanagement.admin` (Connectivity Tests de la prueba de humo) y `storage.objectViewer` sobre todo el bucket de estado. Que `viewer` alcance para refrescar todo es HYPOTHESIS (`VERIFICAR-EN-APPLY`) |

Las nueve reciben además `serviceusage.serviceUsageConsumer` (proyecto de cuota de las
llamadas). Ninguna tiene `iam.roleAdmin`, `iam.serviceAccountAdmin`, `iam.denyAdmin`,
`resourcemanager.tagUser` ni `tagAdmin` de proyecto, `storage.admin` sin condición,
`projectIamAdmin` sin condición ni roles de organización o de la política de acceso.

Permisos sobre recursos sueltos que no da `0-bootstrap`:

- `1-base` (`stages/1-base/runtime_accounts.tf` y `onprem_dns.tf`) da a `tf-wl-<env>`
  `iam.serviceAccountUser` solo sobre sus cuentas `gke_nodes`, `mig`, `run` y `sched`, y a
  `tf-net` solo sobre la cuenta de la VM DNS.
- Cada spoke (`stages/2-networks/envs/<env>/firewall.tf`) da a `tf-wl-<env>`
  `resourcemanager.tagUser` solo sobre sus valores `lb_backend` e `iap_ssh`, y al agente de GKE
  `tagHoldAdmin` sobre `lb_backend`.
- `0-bootstrap` (`main.tf`) da `resourcemanager.tagUser` de proyecto al agente de GKE y a
  `<número>@cloudservices`, que ligan las etiquetas a nodos y VM.

Sincronía obligatoria: `local.base_grantable_roles` de `0-bootstrap` coincide con los roles de
`stages/1-base/iam.tf`, y `local.runtime_grantable_roles` con los de
`stages/1-base/runtime_accounts.tf`.

Roles personalizados de proyecto (`stages/0-bootstrap/custom_roles.tf`, salida
`custom_role_ids` con las llaves `secret_container_admin`, `service_account_manager`,
`network_tag_manager` y `off_hours_scheduler`). Viven en `0-bootstrap` para que ninguna cuenta
del pipeline necesite `iam.roleAdmin`; que todos sus permisos se admitan en roles de proyecto es
`VERIFICAR-EN-APPLY`.

| Rol | Permisos | Quién lo tiene |
|---|---|---|
| `<prefix>TfSecretContainerAdmin` | `secretmanager.secrets.{create,delete,get,getIamPolicy,list,setIamPolicy,update}` y `secretmanager.locations.{get,list}`; sin versiones (ADR 0015). Con `setIamPolicy` podría darse `secretAccessor`: la denegación le niega el valor (§6.5) | `tf-base` |
| `<prefix>TfServiceAccountManager` | `iam.serviceAccounts.{create,delete,disable,enable,get,getIamPolicy,list,setIamPolicy,undelete,update}` y `resourcemanager.projects.get`; sin `createTagBinding` ni `deleteTagBinding` | `tf-base` |
| `<prefix>TfNetworkTagManager` | `resourcemanager.tagKeys.{create,delete,get,getIamPolicy,list,setIamPolicy,update}` y `resourcemanager.tagValues.{create,delete,get,getIamPolicy,list,setIamPolicy,update}`; sin `tagValueBindings`, `*TagBinding` ni `tagHolds` | `tf-net-<env>` |
| `<prefix>OffHoursScheduler` | `cloudsql.instances.{get,update}` y `container.clusters.update` | cuenta `<prefix>-<env>-<app>-sched` que crea `1-base` (dev y qa, `off_hours_environments`), condicionado a la instancia `<prefix>-<env>-data-` y a los clústeres `<prefix>-<env>-` de su entorno (`local.off_hours_condition`) |

### 6.4 Workload Identity Federation

`0-bootstrap` crea el pool `<prefix>-bootstrap-sec-wif-pool` y el proveedor OIDC de GitHub
`<prefix>-bootstrap-sec-github` con `attribute_condition` que exige
`assertion.repository_id == var.github_repository_id` y
`assertion.repository_owner_id == var.github_repository_owner_id` (IDs numéricos, que no se
reutilizan como un nombre; ADR 0023), y mapea `repository_id`, `repository_owner_id`,
`repository`, `ref`, `environment` y `deploy`. `attribute.deploy` (`local.wif_deploy` de
`stages/0-bootstrap/wif.tf`) es:

```text
('environment' in assertion
 && assertion.ref == 'refs/heads/main'
 && 'job_workflow_ref' in assertion
 && assertion.job_workflow_ref == '<github_repository>/.github/workflows/_terraform-root.yml@refs/heads/main'
 && 'event_name' in assertion
 && (assertion.event_name == 'push' || assertion.event_name == 'workflow_dispatch'))
? assertion.environment : 'none'
```

Es decir: vale el entorno de GitHub del trabajo solo si el token viene de `main`, del archivo
exacto `_terraform-root.yml` en `main` (`local.wif_deploy_workflow`) y de un evento `push` o
`workflow_dispatch` (`local.wif_deploy_events`, los únicos de los bloques `on:` de `apply.yml` y
`destroy.yml`); si no, `none`, que ninguna cuenta acepta. Otro archivo de flujo, el mismo archivo
en otra rama o un flujo nuevo con `pull_request_target`, `workflow_run` o `issue_comment` (cuyo
`ref` también es la rama por defecto) no obtiene una cuenta que escribe. Los trabajos que
escriben son el `apply` de `_terraform-root.yml`, que `apply.yml` y `destroy.yml` llaman como
flujo reutilizable; si esos flujos cambian de eventos o el archivo se renombra, la lista o el
nombre se cambian en `wif.tf` y se vuelve a aplicar `0-bootstrap`. Quién puede tomar cada cuenta
(`roles/iam.workloadIdentityUser`):

- `tf-base` y `tf-net`: solo `principalSet://iam.googleapis.com/<pool>/attribute.deploy/common`.
- `tf-net-<env>` y `tf-wl-<env>`: solo `…/attribute.deploy/<env>`.
- `tf-read`: `…/attribute.repository_id/<id>`, cualquier trabajo del repositorio.

Un trabajo sin entorno de GitHub, de otra rama, de otro archivo de flujo o de otro evento solo
obtiene `tf-read`. El valor real de `job_workflow_ref` y de `event_name` en el trabajo `apply`
llamado con `uses: ./.github/workflows/…` (GitHub no documenta el `ref` de una llamada con ruta
local: si fuera el SHA, `attribute.deploy` queda en `none` y el apply falla en la autenticación)
y que el mapeo no falle en trabajos sin entorno son `VERIFICAR-EN-APPLY`
(`stages/0-bootstrap/wif.tf`, puntos 123, 124 y 156). La regla
"Deployment branches: main" y los revisores de cada entorno de GitHub
([`pipeline.md`](pipeline.md) §4) quedan como segunda barrera. `github_repository` tiene que
coincidir con la afirmación `repository`: si el repositorio se renombra, `attribute.deploy` queda
en `none` hasta volver a aplicar `0-bootstrap`. Sin llaves JSON en ningún lado (con
organización, además lo impide `iam.disableServiceAccountKeyCreation`; en todo caso lo niega la
política de denegación, §6.5).

Los `plan` corren con `tf-read` y `-lock=false`, porque esa cuenta no puede escribir el
candado del estado; el apply vuelve a planear con la cuenta de la raíz y toma el candado
(ADR 0025).

### 6.5 Protección del estado y de la etapa 0

Sin carpeta, la política de denegación va en el proyecto y reconoce lo protegido por una
etiqueta, porque las condiciones de denegación solo admiten funciones de etiquetas
([deny](https://docs.cloud.google.com/iam/docs/deny-overview)). Todo en
`stages/0-bootstrap/deny_policy.tf`:

- **Etiqueta** (con `enable_protection_tags`, `true` por defecto): clave `<prefix>-proteccion`
  con padre `projects/<id>` y valor `etapa-0`, ligada al bucket de estado, al llavero del estado
  y a las nueve cuentas del pipeline.
- **Política de denegación** `<prefix>-bootstrap-sec-deny-pipeline` (con `enable_deny_policy`,
  `true` por defecto), con cuatro reglas; las tres primeras contra las nueve cuentas:
  1. sobre lo que tiene la etiqueta (solo con `enable_protection_tags`): borrar el bucket o
     cambiar su configuración, su IAM y sus etiquetas; cambiar el IAM del llavero o de la llave,
     cambiar la llave o destruir versiones; cambiar el IAM de las cuentas del pipeline,
     suplantarlas (`actAs`, `getAccessToken`, `getOpenIdToken`, `implicitDelegation`, `signBlob`,
     `signJwt`), cambiarlas, borrarlas o deshabilitarlas;
  2. en todo el proyecto, sin condición (`untagged_denied_permissions`): pedir tokens o firmas
     de **cualquier** cuenta de servicio (`getAccessToken`, `getOpenIdToken`,
     `implicitDelegation`, `signBlob`, `signJwt`); crear, cambiar o borrar pools y proveedores de
     WIF y roles personalizados; crear llaves de cuentas de servicio
     (`serviceAccountKeys.create`); borrar el proyecto (`projects.delete`); y habilitar,
     deshabilitar o cambiar la política de consumidor de los servicios
     (`serviceusage.googleapis.com/services.enable`, `services.disable` y
     `consumerpolicy.update`), porque las APIs solo las habilita `0-bootstrap`.
     `serviceusage.services.use` no se niega: las nueve cuentas usan el proyecto como proyecto de
     cuota. `actAs` tampoco: adjuntar una cuenta de ejecución a un recurso lo pide (punto 127);
  3. valores de secretos: `secretmanager.versions.access` para las nueve salvo `tf-net`, que lee
     la llave de la VPN real;
  4. llaves de cuentas de servicio para **todos**: `serviceAccountKeys.create` negado a
     `principalSet://goog/public:all`, sin excepción. Sin organización no existe
     `iam.disableServiceAccountKeyCreation`, y `tf-base` administra el IAM de las cuentas de
     ejecución: podría dar a otro principal el poder de crear llaves. La persona de la etapa 0
     puede quitar o cambiar la regla con `iam.denyAdmin` si alguna vez necesita una llave. Que
     ningún agente de servicio necesite crear llaves administradas por el usuario es HYPOTHESIS
     (`VERIFICAR-EN-APPLY`, punto 155). Que la regla impida también subir una llave pública es
     HYPOTHESIS: la documentación de la subida no nombra el permiso que pide. Con organización,
     la subida la bloquearía `iam.disableServiceAccountKeyUpload`, que `modules/org` no aplica.
- Quien aplica `0-bootstrap` necesita `roles/iam.denyAdmin` en el proyecto (el rol `owner` no lo
  incluye; `VERIFICAR-EN-APPLY`).

Límites conocidos: `iam.serviceAccounts.createTagBinding`/`deleteTagBinding`,
`cloudkms.keyRings.deleteTagBinding` y `resourcemanager.tagValueBindings.*` no se pueden negar
([permisos que se pueden negar](https://cloud.google.com/iam/docs/deny-permissions-support)),
por eso ninguna cuenta tiene esos permisos sobre lo protegido: ninguna tiene `tagUser`,
`tagAdmin` ni `serviceAccountAdmin` de proyecto, `tf-base` usa `<prefix>TfServiceAccountManager`
y no tiene KMS sobre el llavero del estado, y las de spoke usan `<prefix>TfNetworkTagManager`.
Los permisos `iam.denypolicies.*` no se pueden negar y ninguna cuenta tiene `iam.denyAdmin`. Los
permisos de objeto de Cloud Storage no se niegan: los prefijos se separan con las condiciones de
§6.2. Las cuentas de spoke alcanzan también la clave de protección (su IAM y sus valores) y
podrían darse `tagUser` sobre su valor; sin `deleteTagBinding` sobre cuentas, buckets ni
llaveros no deberían poder quitar la etiqueta de lo protegido (prueba
`ningun_rol_del_pipeline_liga_etiquetas` de `stages/0-bootstrap/tests/`; en GCP, HYPOTHESIS).

Que el bucket y el llavero admitan la etiqueta, que la llave la herede y que las etiquetas y la
denegación funcionen en un proyecto sin organización es HYPOTHESIS (`VERIFICAR-EN-APPLY`, puntos
90 a 93). Si no funcionan, `enable_protection_tags = false` y la protección queda en que ninguna
cuenta tiene `storage.admin` sin condición, `iam.serviceAccountAdmin`, `tagUser` ni
`projectIamAdmin` sin condición, más las reglas sin etiqueta si la denegación sí funciona. Riesgo
de ese caso: `tf-base` tiene `setIamPolicy` sobre las cuentas a nivel de proyecto
(`<prefix>TfServiceAccountManager`), así que sin la regla con etiqueta podría darse acceso a otra
cuenta del pipeline.

---

## 7. Contrato de cada etapa

Las salidas listadas como interfaz son las de la tabla "Interfaces entre etapas" del ADR 0029,
con los formatos de §2.1: sus nombres y tipos no se cambian sin actualizar este documento. Cada
raíz puede tener más variables internas, todas con descripción; la lista completa de cada una
está en su README.

### 7.0 `0-bootstrap`

La aplica una persona, a mano y una sola vez (runbook 01), sobre el proyecto que ya existe.

Crea: las APIs del proyecto (todas, una sola vez: `local.apis` más `additional_apis`, con
`disable_on_destroy = false`); los agentes de servicio que 1-base necesita antes del primer uso
de su servicio (`google_project_service_identity` de Artifact Registry, Filestore, Backup for
GKE, Pub/Sub, Memorystore, Secret Manager y Cloud SQL); OS Login en los metadatos del proyecto
(CIS 4.4); `DEPRIVILEGE` de la cuenta de Compute por defecto (§2.1);
`resourcemanager.tagUser` de proyecto para el agente de GKE y `<número>@cloudservices` (ligan
las etiquetas seguras a nodos y VM; punto 137); llavero
`<prefix>-bootstrap-sec-keyring-<ubicación>` y llave `state` (rotación de 90 días) en
`lower(state_bucket_location)`; el bucket de estado (§6.1); las nueve cuentas del pipeline con
sus roles, su acceso al estado y su WIF (§6.2 a §6.4); los cuatro roles personalizados (§6.3);
la etiqueta y la política de denegación (§6.5); el presupuesto del proyecto
`<prefix>-bootstrap-ops-budget`, filtrado por `projects/<número>` (quien aplica necesita
`roles/billing.costsManager` en la cuenta de facturación).

Solo con organización (`org.tf`): con `org_id`, las políticas de organización aplicadas al
proyecto (módulo `org`, con `additional_allowed_locations` y `directory_customer_id`); con
`access_policy_id`, el perímetro de VPC-SC alrededor de todo el proyecto, siempre en dry-run, con
las nueve cuentas en la regla de entrada y `vpc_sc_restricted_services` (incluye `cloudkms` y
`secretmanager` por defecto, ADR 0029). Quien aplica necesita `roles/orgpolicy.policyAdmin` en la
organización y `roles/accesscontextmanager.policyAdmin` sobre la política de acceso (runbook 01;
puntos 125 y 126). Ninguna cuenta del pipeline recibe esos roles.

Lee: nada.

Entradas obligatorias: `project_id`, `billing_account`, `prefix`, `primary_region`, `dr_region`,
`github_repository` (tiene que coincidir con la afirmación `repository` del token: entra en
`attribute.deploy`), `github_repository_id`, `github_repository_owner_id`, `budget_amount`,
`labels`. Con valor por defecto: `org_id`, `additional_allowed_locations`,
`directory_customer_id`, `access_policy_id`, `vpc_sc_restricted_services`, `name_suffix`,
`location_short_codes`, `state_bucket_location`, `state_bucket_dual_regions`,
`state_versions_to_keep`, `additional_apis`, `budget_alert_thresholds`,
`enable_protection_tags`, `enable_deny_policy`, `onprem_dns_vm` (da al hub
`compute.instanceAdmin.v1` y hace que `1-base` cree la cuenta de la VM DNS).

| Salida | Tipo | Contenido |
|---|---|---|
| `project_id` | string | el proyecto único |
| `project_number` | string | su número |
| `state_bucket` | string | nombre del bucket de estado |
| `state_kms_key_id` | string | llave del estado |
| `stage_service_accounts` | map(string) | llaves `1-base`, `2-networks`, `2-networks/<env>`, `3-workloads/<env>` → correo |
| `read_service_account` | string | correo de `tf-read` (variable `GCP_AUDIT_SERVICE_ACCOUNT`) |
| `workload_identity_provider` | string | nombre completo del proveedor, para GitHub Actions |
| `workload_identity_pool` | string | nombre completo del pool |
| `custom_role_ids` | map(string) | `secret_container_admin`, `service_account_manager`, `network_tag_manager`, `off_hours_scheduler` → `projects/<id>/roles/<rol>` |
| `org_policies_enabled` | bool | `true` si llegó `org_id` y se aplicaron las políticas de organización |
| `vpc_sc_perimeter_name` | string o null | perímetro opcional |
| `onprem_dns_vm_enabled` | bool | valor de `onprem_dns_vm`; lo lee `1-base` |
| `state_iam_conditions` | map(object) | raíz → `{ writes, reads }`: prefijos que escribe y lee cada cuenta |

### 7.1 `1-base`

Lo que existe una vez por proyecto y no es de la etapa 0 (ADR 0029 §4).

Crea:

- **Auditoría:** configuración de auditoría del proyecto (`ADMIN_READ` para `allServices`;
  `DATA_READ` y `DATA_WRITE` para `cloudkms`, `iam`, `secretmanager`, `sqladmin` y `storage`, en
  los tres entornos, ADR 0029 §7); llavero común `<prefix>-common-sec-keyring-<código de la primaria>` con
  las llaves `logs` y `pubsub` (ADR 0018); bucket de logs
  `<prefix>-common-ops-audit-logs[-<name_suffix>]` con CMEK y retención (`log_retention_days`,
  `log_retention_locked`, irreversible una vez aplicado) y sink de proyecto con el filtro de
  auditoría y la exclusión `bucket-de-logs`; métricas y alertas de auditoría (módulo
  `audit-alerts`, CIS 2.5 a 2.12 más políticas de firewall, ADR 0027) hacia
  `security_alert_email`; contactos esenciales del proyecto (CIS 1.17); con
  `operations_alert_email`, el canal de operaciones, el único que reciben también las alertas de
  los entornos (punto 138); con `enable_scc_notification`, el tema
  `<prefix>-common-ops-scc-findings` (CMEK regional, `enforce_in_transit`) y la notificación de
  SCC del proyecto. SCC se activa a mano; que funcione sin organización es HYPOTHESIS
  ([activación](https://docs.cloud.google.com/security-command-center/docs/activate-scc-overview)).
- **Llaves y secretos:** por entorno y ubicación un llavero `<prefix>-<env>-sec-keyring-<código>`
  con solo las llaves que alguien usa: en `primary_region`, `gke`, `compute`, `run`, `sql`,
  `storage`, `redis`, `filestore` y `secrets`; en `dr_region`, solo para los entornos de
  `dr_environments` (por defecto prod), `gke`, `compute`, `run`, `sql`, `backup` y `secrets`; en
  la multirregión `us`, `storage` solo para `dr_environments`; y `artifacts` solo en
  `artifact_registry_location`. Rotación `key_rotation_period` (90 días por defecto) y
  `cryptoKeyEncrypterDecrypter` para el agente de servicio de cada uso. Contenedores de secretos
  `<prefix>-<env>-sec-<nombre>` de `secret_names`, con su llave `secrets` (y una segunda réplica
  en `dr_region` solo en `dr_environments`; ADR 0015). Los agentes son uno por proyecto y quedan
  con las llaves de los tres entornos (riesgo aceptado). Un entorno de `3-workloads` con
  `enable_dr` que no esté en `dr_environments` falla en su plan por falta de llaves.
- **Imágenes:** repositorios Docker `<prefix>-<env>-<app>` en `artifact_registry_location` (`us`
  por defecto) con CMEK `artifacts` y etiquetas inmutables; lectura del agente de Cloud Run sobre
  todos; `artifactregistry.writer` para `artifact_registry_publishers`; la única política de
  Binary Authorization, con lista global o con un atestador por entorno
  (`binary_authorization_env_attestors`, ADR 0024).
- **Cuentas de ejecución** (`runtime_accounts.tf`): por entorno y aplicación,
  `<prefix>-<env>-<app>-{gke-nodes,workload,mig,run}` y, en `off_hours_environments` (dev y qa
  por defecto; prod se rechaza), `<prefix>-<env>-<app>-sched`. Les da, por la concesión
  delegada de `tf-base`, sus roles de proyecto (telemetría, `cloudsql.client` y
  `cloudsql.instanceUser` condicionados a las instancias `<prefix>-<env>-data-`, y el rol del
  apagado a `sched`, condicionado a la instancia y a los clústeres de su entorno,
  `local.off_hours_condition`); `secretAccessor` sobre los secretos de su entorno a `workload` y
  `run`; `artifactregistry.reader` sobre su repositorio a `gke_nodes` y `mig`; el enlace de
  Workload Identity por clúster a `workload` (con `gke_workload_identity_bindings = true`,
  después del primer clúster): `roles/iam.workloadIdentityUser` para
  `principalSet://iam.googleapis.com/projects/<número>/locations/global/workloadIdentityPools/<proyecto>.svc.id.goog/kubernetes.cluster/https://container.googleapis.com/v1/projects/<proyecto>/locations/<ubicación>/clusters/<prefix>-<env>-<app>-gke[-dr]`,
  todos los pods del clúster primario y, en `dr_environments`, del de DR (ADR 0012, punto 158);
  y a `tf-wl-<env>` `iam.serviceAccountUser` solo sobre `gke_nodes`, `mig`, `run` y `sched`
  (puntos 131 a 135).
- **Cuenta de la VM DNS** (`onprem_dns.tf`, solo con `onprem_dns_vm_enabled` de `0-bootstrap`):
  `<prefix>-common-net-dns` con `logging.logWriter`, y `serviceAccountUser` para `tf-net` solo
  sobre ella.
- **IAM de personas:** grupos de solo lectura (`readers`, `security_admins`, `auditors`; solo
  `group:`) y lectura del bucket de logs para `auditors`.

Lee: `0-bootstrap` (`project_id` para la precondición, `project_number`,
`stage_service_accounts`, `custom_role_ids`, `onprem_dns_vm_enabled`).

Entradas obligatorias: `project_id`, `state_bucket`, `prefix`, `primary_region`, `dr_region`,
`security_alert_email`, `essential_contacts`, `labels`. Con valor por defecto: `name_suffix`,
`location_short_codes`, `environments`, `applications`, `off_hours_environments`,
`gke_workload_identity_bindings`, `artifact_registry_location`,
`artifact_registry_publishers`, `binary_authorization_allowlist_patterns`,
`binary_authorization_attestors`, `binary_authorization_env_attestors`, `secret_names`,
`key_rotation_period`, `dr_environments`, `operations_alert_email`, `groups`,
`essential_contacts_language`, `log_retention_days`, `log_retention_locked`,
`enable_scc_notification`, `scc_notification_filter`. Las variables de organización y VPC-SC
ya no están aquí: son de `0-bootstrap` (§7.0).

| Salida | Tipo | Contenido |
|---|---|---|
| `kms_key_ids` | map(map(string)) | entorno → llave → ID; llave `<uso>` en la región primaria, `<uso>_dr` en la de DR y `<uso>_us` en la multirregión; solo las llaves que existen |
| `secret_ids` | map(map(string)) | entorno → nombre corto → ID del secreto (ninguna raíz la lee hoy) |
| `artifact_registry_repositories` | map(map(string)) | entorno → aplicación → URL `<ubicación>-docker.pkg.dev/<proyecto>/<repositorio>` |
| `runtime_service_accounts` | map(map(map(string))) | entorno → aplicación → uso (`gke_nodes`, `workload`, `mig`, `run` y, en `off_hours_environments`, `scheduler`) → correo |
| `gke_workload_identity_members` | map(map(map(string))) | entorno → aplicación → clúster (`primary` y, en `dr_environments`, `dr`) → `principalSet://…/kubernetes.cluster/…/clusters/<prefix>-<env>-<app>-gke[-dr]`; mientras `gke_workload_identity_bindings` sea `false`, el valor de cada aplicación es null |
| `onprem_dns_service_account` | string o null | cuenta de la VM DNS; ninguna raíz la lee (el hub arma el correo por nombre) |
| `off_hours_role_id` | string | `projects/<id>/roles/<prefix>OffHoursScheduler` (lo crea `0-bootstrap`; ninguna raíz la lee hoy) |
| `security_alert_email` | string | destino de las alertas de auditoría |
| `notification_channel_ids` | map(string) | `security` → canal de las alertas de auditoría; con `operations_alert_email`, `operations` → canal de operaciones |
| `log_bucket` | string | bucket de logs de auditoría |

### 7.2 `2-networks` (hub)

Crea, en `project_id`: VPC hub `<prefix>-common-net-hub` y sus dos subredes; Cloud Router por
región; HA VPN con dos túneles y BGP hacia on-premises (SLA 99.99 %) en la región primaria y,
con `enable_vpn_dr = true` (por defecto), otra HA VPN en el router de `dr_region` con prioridad
de anuncio `vpn_dr_route_priority` (200; on-premises prefiere la primaria, ADR 0022); anuncios
BGP personalizados con el /16 del hub, los /16 de los spokes y 35.199.192.0/19 (reenvío de Cloud
DNS); dos políticas de firewall de red (ADR 0029 §6): `<prefix>-common-net-fw-hub`, solo con la
denegación por defecto de la entrada (el hub no tiene cargas, §2.1), y, con
`simulate_onprem = true`, `<prefix>-common-net-fw-onprem-sim` (DNS desde 35.199.192.0/19 y SSH
por IAP); DNS: zona de reenvío hacia on-premises y política de servidor entrante; con
`simulate_onprem = true`, la VPC `onprem-sim` con su gateway y router (y un router más en
`dr_region` para la VPN de DR) y una política DNS solo con registro de consultas (CIS 2.13)
(ADR 0006); con `onprem_dns_vm = true` (exige `simulate_onprem` y el mismo valor en
`0-bootstrap`, y `1-base` aplicada después), la VM DNS de `onprem-sim` (`onprem_dns.tf`:
e2-micro debian-12 sin IP pública, con la cuenta `<prefix>-common-net-dns` de `1-base`, en la
primera IP de `onprem_dns_servers`; puntos 128 a 130); Interconnect solo si
`enable_interconnect = true`. Las subredes del hub y de `onprem-sim` usan el muestreo de flow
logs por defecto de `network-hub` (1.0, ADR 0027). Las APIs las habilita `0-bootstrap`.

Lee: nada (§2.1).

Entradas obligatorias: `project_id`, `prefix`, `primary_region`, `dr_region`, `hub_supernet`
(/16 del hub que se anuncia por BGP; contiene `hub_cidrs`), `hub_cidrs`, `spoke_supernets` (map
entorno → /16), `onprem_cidrs`, `hub_asn`, `onprem_asn` (privado en modo simulado; en modo real
admite un ASN público de 2 o 4 bytes), `vpn_bgp_ranges`, `onprem_dns_domain`,
`onprem_dns_servers`, `labels`. Con valor por defecto: `region_short_names`, `enable_vpn_dr`,
`vpn_dr_bgp_ranges`, `vpn_dr_route_priority`, `simulate_onprem`, `onprem_sim_cidr`,
`onprem_vpn_gateway_ips`, `onprem_vpn_secret_id`, `onprem_vpn_secret_version`,
`onprem_vpn_secret_version_overrides`, `onprem_dns_vm`, `onprem_dns_vm_zone`,
`enable_interconnect`, `interconnect_attachments`.

El secreto compartido de la VPN nunca va en variables: con on-premises real se lee de Secret
Manager en una versión numérica (`onprem_vpn_secret_version`, sin `latest`; por túnel con
`onprem_vpn_secret_version_overrides`, llaves `primary-if0`, `primary-if1`, `dr-if0`, `dr-if1`,
para rotar de a un túnel); en modo simulado se genera y solo existe en el estado cifrado
(ADR 0006). Con on-premises real, `tf-net` necesita `secretAccessor` sobre el secreto, que da una
persona (la denegación deja a `tf-net` fuera de la regla de valores). Limitación conocida: la
fuente de datos se lee en cada plan, y los `plan` del pipeline corren con `tf-read`, que no tiene
acceso y tiene negado el valor; con `simulate_onprem = false` el plan del hub debe fallar en el
pipeline (por verificar, punto 151). Las salidas posibles están en el comentario de `vpn.tf` y en
la §5 de `pendientes-apply.md`; ninguna está construida.

| Salida | Tipo | Contenido |
|---|---|---|
| `hub_network_self_link` | string | para peering y zonas de peering DNS |
| `spoke_supernets` | map(string) | entorno → /16 que el hub anuncia; cada spoke comprueba el suyo |
| `onprem_dns_vm` | object o null | `{ name, zone, ip, record }` de la VM DNS; null sin `onprem_dns_vm` |

Salidas adicionales: `hub_network_name`, `firewall_policy_id` (política de red del hub),
`firewall_policy_rules` (vacía a propósito), `hub_routers`, `bgp_advertised_ranges`,
`vpn_tunnel_names`, `vpn_gateway_ip_addresses`, `vpn_dr_tunnel_names`,
`vpn_dr_gateway_ip_addresses`, `dns_inbound_forwarder_ips`, `onprem_sim_network_name`,
`onprem_sim_firewall_policy_id`.

### 7.3 `2-networks/envs/<env>` (spoke)

Crea, en `project_id` y sin Shared VPC (las cargas del entorno usan esta VPC desde el mismo
proyecto): VPC; subredes de §5 con Private Google Access y flow logs (`flow_log_sampling`: 1.0
por defecto y en prod, 0.5 en los ejemplos de dev y qa, ADR 0027); subredes proxy-only; rango y
conexión de Private Service Access (una por VPC,
[PSA](https://docs.cloud.google.com/vpc/docs/configure-private-services-access)); peering con el
hub en ambos sentidos (el hub exporta rutas personalizadas, el spoke las importa,
[VPC peering](https://docs.cloud.google.com/vpc/docs/vpc-peering)); Cloud NAT por región
(ADR 0004); la política de firewall de red `<prefix>-<env>-net-fw`, asociada a la VPC, con las
etiquetas seguras `lb_backend` e `iap_ssh` (cada una su llave, con padre el proyecto, propósito
`GCE_FIREWALL` ligado a la VPC y un solo valor `enabled`), las reglas `allow-lb-health-checks`
(35.191.0.0/16 y 130.211.0.0/22 hacia `lb_backend`), `allow-iap-ssh` (35.235.240.0/20 hacia
`iap_ssh`), `allow-proxy-to-backends`, `allow-gke-control-plane`, `allow-workload-internal` y,
con `enable_filestore_nfs_lock_callbacks`, `allow-filestore-nfs-callbacks` desde el rango `psa`,
más la denegación por defecto del módulo (prioridad 65000, con registro). Que las etiquetas con
padre proyecto funcionen sin organización es HYPOTHESIS. DNS: zona privada
`<env>.<dns_domain_base>`, adjunta a la VPC del spoke y a la del hub (on-premises la resuelve por
el reenvío entrante del hub); zona de peering DNS hacia el hub para el dominio on-premises;
zonas privadas de `googleapis.com`, `gcr.io`, `pkg.dev` y `run.app` hacia el VIP de
`google_apis_vip` (`restricted`, 199.36.153.4/30, por defecto en los tres entornos; o
`private`, 199.36.153.8/30) y la ruta al VIP restringido (ADR 0026); política de servidor solo
con registro de consultas.

Los spokes se aplican de uno en uno: cada uno crea su lado del peering sobre la VPC hub y GCP
no admite dos operaciones de peering a la vez sobre la misma red (`apply.yml` los encadena).

Lee: `2-networks/hub` (`hub_network_self_link`, `spoke_supernets`).

Entradas obligatorias: `project_id`, `prefix`, `environment`, `primary_region`, `dr_region`,
`spoke_supernet` (/16 del entorno; contiene `subnet_cidrs` y coincide con
`spoke_supernets[environment]` del hub), `subnet_cidrs`, `onprem_cidrs`, `onprem_dns_domain`,
`labels`, `state_bucket`. Con valor por defecto: `region_short_names`, `enable_dr`,
`dns_domain_base`, `flow_log_sampling`, `lb_backend_ports`,
`enable_filestore_nfs_lock_callbacks`, `filestore_nfs_lock_ports`, `google_apis_vip`.

| Salida | Tipo | Contenido |
|---|---|---|
| `network_self_link` | string | |
| `subnets` | map(object) | llave de §5 → `{ self_link, name, region, cidr, secondary_ranges }` (`secondary_ranges`: map nombre → CIDR, llaves `pods` y `services`) |
| `psa_range_name` | string | |
| `secure_tags` | map(string) | llaves `lb_backend`, `iap_ssh` → ID del valor de etiqueta (`tagValues/…`) |
| `secure_tag_keys` | map(string) | mismas llaves → ID de la llave de etiqueta (`tagKeys/…`) |
| `reserved_cidrs` | map(string) | rangos sin subred (`gke_master` y, con `enable_dr`, `gke_master_dr`); `3-workloads` los toma de aquí |
| `lb_backend_ports` | list(string) | puertos que la política del spoke abre hacia `lb_backend`; `3-workloads` comprueba sus backends contra ellos |
| `dns_zone_names` | map(string) | llaves `env`, `onprem`, `googleapis`, `gcr`, `pkg`, `run` → nombre de la zona |

Salidas adicionales: `network_name`, `network_id`, `routers`, `nat_names`,
`firewall_policy_id`, `firewall_policy_rules`, `private_dns_domain`. Ya no existen
`host_project_id` ni `host_project_number`.

El spoke administra sus etiquetas con `<prefix>TfNetworkTagManager` y da
`roles/resourcemanager.tagUser` a `tf-wl-<env>` solo sobre sus valores `lb_backend` e `iap_ssh`
(`firewall.tf`), y `tagHoldAdmin` sobre `lb_backend` al agente de GKE. El `tagUser` de proyecto
del agente de GKE y de `<número>@cloudservices` lo da `0-bootstrap`. Que alcance para crear la
plantilla del MIG y los nodos con las etiquetas es `VERIFICAR-EN-APPLY` (puntos 136 y 137).

### 7.4 `3-workloads/envs/<env>`

Crea, en `project_id`, solo recursos del entorno. No crea cuentas de servicio ni asigna roles de
proyecto: usa las cuentas de ejecución que crea `1-base` (`runtime_service_accounts`, §7.1) y
las adjunta a nodos, plantillas, servicios y trabajos con el `serviceAccountUser` que `1-base` le
da sobre cada una (ADR 0029 §4).

- **Cargas**, con interruptores (`enable_gke`, `enable_mig`, `enable_cloud_run`,
  `enable_filestore`, `enable_memorystore`, `enable_internal_lb`, `enable_backup`): GKE (clúster
  `<prefix>-<env>-<app>-gke[-dr]`), MIG, Cloud Run, Cloud SQL (`sql_instance_name` opcional),
  Memorystore, Cloud Storage, Filestore, balanceador HTTPS global con Cloud Armor y certificado
  administrado, balanceador interno, observabilidad (filtros limitados al entorno; las alertas
  van también al canal `operations` de `1-base`, si existe) y respaldo. Los usuarios IAM de
  Cloud SQL (`workload`, `run` y `mig` según el cómputo encendido) los crea esta raíz con
  `grant_iam_login_roles = false`: los roles de conexión los da `1-base`. En prod con `enable_dr = true`: réplica de
  Cloud SQL en la región de DR, bucket de doble región con turbo replication, plan de Backup for
  GKE. Con `dr_active = true` (conmutación): cómputo en la región de DR, backends del balanceador
  externo hacia ella (GKE sale del externo mientras `gke_lb_negs.dr` esté vacío) y un segundo
  balanceador interno en DR (`module.internal_lb` es uno por región, con `allow_global_access`;
  ADR 0022). El certificado del balanceador interno y sus autorizaciones DNS los crea la raíz por
  región: con `enable_dr`, también el de la región de DR aunque `dr_active` sea false. El
  registro DNS interno no lo administra ninguna raíz: la salida `internal_lb_dns_records` da los
  registros A de la región activa. `dr_teardown = true` (exige `dr_active`) quita la protección
  contra borrado solo del clúster de GKE y del servicio de Cloud Run de DR, para que la vuelta
  (`dr_active = false`) los pueda destruir en prod.
- **Workload Identity:** el enlace de la cuenta `workload` con todos los pods de cada clúster
  `<prefix>-<env>-<app>-gke[-dr]` lo crea `1-base` (el pool `<proyecto>.svc.id.goog` es el
  mismo en los tres entornos y el principal de un namespace valdría desde cualquier clúster,
  [Workload Identity](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity),
  ADR 0029 §9). Esta raíz solo lo lee (`gke_workload_identity_members`) y el
  `check "workload_identity_enlazada"` avisa si hay GKE sin enlace en algún clúster activo
  (`local.compute_regions`). El namespace `<app>-<env>` queda solo como convención.
- **Apagado fuera de horario:** con `off_hours_shutdown.enabled` (dev y qa; se rechaza en prod y
  con `enable_dr`, ADR 0028), trabajos de Cloud Scheduler (módulo `off-hours-shutdown`) con la
  cuenta `scheduler` de `1-base` (que tiene el rol del apagado condicionado a la instancia y a
  los clústeres de su entorno), que detienen y encienden Cloud SQL y llevan a 0 y devuelven los
  pools de GKE; programa de escalado en el MIG; y la ventana de Backup and DR dentro del horario
  encendido.

Las subredes y los rangos reservados salen del estado del spoke (`subnets`, `reserved_cidrs`); la
raíz no tiene `subnet_cidrs`.

Lee: `1-base` (`kms_key_ids`, `artifact_registry_repositories`, `runtime_service_accounts`,
`gke_workload_identity_members` y solo `notification_channel_ids["operations"]`; ya no
`secret_ids` ni `off_hours_role_id`) y `2-networks/<env>` (`network_self_link`, `subnets`,
`psa_range_name`, `secure_tags`, `secure_tag_keys`, `reserved_cidrs`, `lb_backend_ports`).
Postcondiciones y precondiciones exigen las llaves que la configuración pide, el repositorio de
la aplicación, las cuentas `gke_nodes`, `workload`, `mig` y `run` (y `scheduler` con el
apagado), la VPC dentro de `project_id`, el /28 del plano de control con GKE y los puertos de los
backends.

Entradas obligatorias: `project_id`, `prefix`, `environment`, `state_bucket`, `labels` (con
`app = application`), `domain_names` (certificado), `notification_emails`. Con valor por
defecto, entre otras: `application`, `primary_region`, `dr_region`, `enable_dr`, `dr_active`,
`dr_teardown`, `deletion_protection`, los interruptores, `gke_node_pools`, `gke_lb_negs`,
`cloud_run_image`, `sql_tier`, `sql_instance_name`, `sql_database_version`,
`internal_domain_names`, `off_hours_shutdown` (lista completa en el README de la raíz). Ya no
existen `application_secrets`, `gke_workload_namespace` ni `gke_workload_ksa_name`: los secretos
se configuran en `1-base` y el enlace de Workload Identity es por clúster, sin cuenta de
Kubernetes fija (en `1-base` tampoco existe ya `gke_workload_ksa_name`).

| Salida | Tipo | Contenido |
|---|---|---|
| `lb_ip_address` | string | IP del balanceador externo |
| `gke_cluster_names` | map(string) | región → nombre |
| `sql_instance_connection_name` | string | |
| `bucket_names` | map(string) | |
| `internal_lb_ip_address` | string | IP del balanceador interno de la región activa |
| `internal_lb_ip_addresses` | map(string) | región → IP de cada balanceador interno |
| `internal_lb_dns_authorization_records_by_region` | map | región → registros DNS de autorización del certificado interno (con `enable_dr`, las dos regiones) |
| `internal_lb_dns_records` | map | dominio de `internal_domain_names` → registro A (`type`, `rrdatas`) con la IP del balanceador interno de la región activa |
| `gke_workload_identity_member` | map(string) | clúster (`primary` y, en los `dr_environments` de `1-base`, `dr`) → `principalSet` de todos los pods de `<prefix>-<env>-<app>-gke[-dr]` enlazado a la cuenta `workload` (lo repite de `1-base`; null sin `enable_gke` o mientras `1-base` no lo enlace) |
| `service_accounts` | map(string) | uso (`gke_nodes`, `workload`, `mig`, `run`) → correo de la cuenta de ejecución (de `1-base`) |
| `scheduler_service_account` | string | correo de la cuenta `-sched` (de `1-base`); null sin apagado |

Salidas adicionales: `sql_replica_connection_name`, `cloud_run_service_names`,
`mig_instance_groups`, `internal_lb_dns_authorization_records`, `internal_lb_certificate_ids`,
`redis_host`, `filestore_ip_address`, `backup_vault_id`, `backup_plan_ids`, `active_region`,
`off_hours_shutdown` (ventana e IDs de los trabajos; null sin apagado).

### 7.5 Regla de recursos únicos

Una raíz de entorno (`2-networks/envs/<env>`, `3-workloads/envs/<env>`) **no puede** declarar
(ADR 0029 §4):

1. Nada que exista una vez por proyecto: APIs (`google_project_service`) y metadatos del
   proyecto; configuración de auditoría; la política de Binary Authorization, contactos
   esenciales, sinks y buckets de logs, el presupuesto y la notificación de SCC; roles
   personalizados y políticas de organización; llaveros y llaves KMS, secretos y repositorios
   de Artifact Registry.
2. Permisos de proyecto (`google_project_iam_member` y `_member_remove`) para cualquier
   principal (cuentas del pipeline, grupos, agentes de servicio, la cuenta de Compute por
   defecto y también las cuentas de ejecución, que ahora crea `1-base`) e IAM de cuentas de
   servicio (`google_service_account_iam_*`, también el enlace de Workload Identity). El IAM de
   un recurso propio del entorno sí se permite.
3. Recursos cuyo nombre no lleve `<prefix>-<env>-` (o `<env>` dentro de los nombres cortos que
   limita GCP), salvo lo que GCP nombra dentro de un padre propio del entorno (reglas de la
   política de firewall, valores de etiqueta, registros DNS, la conexión de PSA).

Por eso lo único del proyecto vive en `0-bootstrap` y `1-base` (§7.0 y §7.1), y lo persistente de
cada entorno (llaves, contenedores de secretos, repositorios y cuentas de ejecución) también vive
en `1-base`: el destroy de un entorno no lo toca. Lo hacen cumplir la regla de Conftest
`env_root_scope` en el plan de cada raíz cuyo `environment` es `dev`, `qa` o `prod` (§9.1;
punto 146), la revisión del plan y, en
el destroy, `scripts/destroy-plan-check.py`, que rechaza
`google_project`, los tipos únicos del proyecto (`PROJECT_SINGLETONS`) y todo recurso sin
`<prefix>-<env>-` cuyo padre no esté también en el plan (§2.1).

---

## 8. Catálogo de módulos

Todos reciben `labels` (§4.3) si crean recursos etiquetables, y `prefix` y `environment` para
armar nombres (§4.2). "Exige" resume la configuración mínima de la especificación (sección
"Componentes del datacenter"): debe quedar como valor fijo o como validación, no como opción
que se pueda apagar en prod. Todos reciben el proyecto por `project_id` (o por el `parent` de la
VPC en `firewall`); ninguno crea proyectos ni carpetas.

| Módulo | Crea | Exige | Entradas principales | Salidas principales |
|---|---|---|---|---|
| `org` | Políticas de organización aplicadas al proyecto (padre `projects/<id>`). Lo usa `1-base` solo con `org_id` | Siete fijas: `compute.vmExternalIpAccess`, `iam.disableServiceAccountKeyCreation`, `gcp.resourceLocations`, `compute.requireShieldedVm`, `storage.publicAccessPrevention`, `storage.uniformBucketLevelAccess`, `sql.restrictPublicIp`; más `iam.allowedPolicyMemberDomains` con `directory_customer_id`. Sin `compute.skipDefaultNetworkCreation` (§2.1) | `project_id`, `allowed_regions`, `additional_allowed_locations`, `directory_customer_id` | `policy_names`, `policy_parent` |
| `iam` | Asignaciones aditivas de roles, con condición opcional | Rechaza miembros `user:`, `domain:`, `allUsers` y `allAuthenticatedUsers`, y los roles `owner` y `editor` | `bindings` (lista de `{ scope, resource, role, member, key, condition }`; `scope`: `organization`, `project`, `service_account`, `storage_bucket`, `kms_key_ring`, `kms_crypto_key`, `secret`, `subnetwork`) | `members`, `bindings`, `conditions` |
| `network-hub` | VPC hub, subredes, routers | Subredes privadas, PGA, flow logs (1.0 por defecto, ADR 0027) | `project_id`, `subnets`, `router_asn`, `extra_router_regions` (routers sin subred, p. ej. el de DR de `onprem-sim`) | `network_self_link`, `network_name`, `routers` (map región → nombre) |
| `network-spoke` | VPC spoke en el proyecto del hub, subredes y rangos secundarios, proxy-only, PSA, peering con el hub en los dos sentidos, NAT | PGA; flow logs (1.0 por defecto, ADR 0027); NAT por región; sin IP públicas | `project_id`, `subnet_cidrs`, `regions`, `hub_network_self_link`, `enable_dr`, `flow_log_sampling` | las de §7.3, `peerings`, `psa_connection_id` |
| `firewall` | Política de firewall de red global asociada a una VPC, con reglas y etiquetas seguras (llaves con padre el proyecto de la VPC) | Denegar la entrada por defecto (prioridad 65000, con registro); acciones `allow` o `deny`, sin `goto_next`; ninguna entrada `allow` desde un origen más amplio que /8; reglas por etiqueta segura | `parent` (VPC), `rules`, `secure_tags`, `name_suffix` (más de una política por entorno), `enable_egress_default_deny` | `policy_id`, `network_id`, `secure_tag_ids`, `secure_tag_key_ids`, `rules`, `default_deny_rules` |
| `cloud-armor` | Política de seguridad | Reglas OWASP preconfiguradas (SQLi, XSS como mínimo) y límite de tasa | `project_id`, `owasp_rules`, `rate_limit` | `policy_self_link` |
| `load-balancer` | Balanceador HTTPS global externo, o interno regional (`type`) | HTTPS con certificado administrado; redirección de HTTP; política de Cloud Armor obligatoria en el externo | `project_id`, `type`, `backends`, `domain_names`, `security_policy`, `network`, `subnet` | `ip_address`, `backend_service_ids`, `backend_groups` |
| `dns` | Zonas privadas, de reenvío y de peering; política de servidor entrante | Zonas privadas por entorno; reenvío condicional a on-premises | `project_id`, `zones` (map con `type`: `private`, `forwarding`, `peering`), `networks` | `zone_names`, `inbound_forwarder_ips`, `zones`, `records` |
| `hybrid-connectivity` | HA VPN, túneles, sesiones BGP; opcional Interconnect | 2 túneles y BGP; Interconnect opcional | `project_id`, `network`, `router`, `peer` (gateway externo o de otra VPC), `advertised_ranges`, `bgp_sessions`, `shared_secret_overrides` (secreto por túnel, para rotar de a uno) | `gateway_self_link`, `tunnel_names`, `bgp_peers` |
| `compute-mig` | Plantilla, MIG regional, autoescalador, verificación de salud | Shielded VM; imagen por variable (endurecida); autoescalado y autocuración; sin IP pública (`stack_type = "IPV4_ONLY"`) | `project_id`, `subnet`, `image`, `machine_type`, `min_replicas`, `max_replicas`, `service_account`, `kms_key` | `instance_group`, `health_check_id`, `subnetwork`, `kms_key` |
| `gke` | Clúster y pools de nodos | Nodos privados; Workload Identity; Binary Authorization; regional si `environment = "prod"` (validación); protección contra borrado fija en prod salvo `teardown` | `project_id`, `network`, `subnet`, `pods_range`, `services_range`, `master_cidr`, `gke_node_pools`, `node_service_account`, `kms_key`, `teardown`, `cluster_name` (opcional; debe empezar con `<prefix>-<env>-`), `node_resource_manager_tags` | `cluster_name`, `cluster_id`, `workload_pool`, `subnetwork`, `kms_key`, `master_cidr`, `deletion_protection` |
| `cloud-run` | Servicio v2 con salida directa a la VPC | Solo tráfico interno y del balanceador; cuenta de servicio propia; protección contra borrado fija en prod salvo `teardown` | `project_id`, `region`, `image`, `subnet`, `service_account`, `kms_key`, `teardown` | `service_name`, `service_uri`, `subnetwork`, `kms_key`, `deletion_protection` |
| `storage` | Bucket | CMEK; versionado; reglas de ciclo de vida; acceso uniforme; sin acceso público | `project_id`, `location`, `kms_key`, `lifecycle_rules`, `dual_region` (objeto opcional con turbo replication) | `bucket_name` |
| `filestore` | Instancia | CMEK; red por PSA | `project_id`, `location`, `tier`, `capacity_gb`, `network`, `kms_key` | `instance_name`, `ip_address` |
| `cloud-sql` | Instancia, bases, usuarios IAM, réplica | IP privada únicamente; HA regional si prod (validación); PITR; réplica en DR si `enable_dr`; SSL obligatorio; CMEK; autenticación IAM | `project_id`, `region`, `dr_region`, `enable_dr`, `sql_tier`, `database_version`, `network`, `kms_key`, `dr_kms_key`, `iam_users`, `backup_plan_managed` (Backup and DR es dueño del horario y la retención) | `instance_name`, `connection_name`, `private_ip`, `replica_name` |
| `memorystore` | Instancia de Redis | IP privada; CMEK; HA si prod | `project_id`, `region`, `tier`, `memory_gb`, `network`, `kms_key` | `host`, `port` |
| `kms` | Llavero y llaves | Rotación de 90 días; `prevent_destroy` en las llaves | `project_id`, `location`, `keys` (map uso → opciones), `rotation_period` | `key_ids` (map), `keyring_id` |
| `secrets` | Contenedores de secretos e IAM | Nunca recibe valores; CMEK | `project_id`, `names`, `kms_keys`, `accessors` | `secret_ids` (map) |
| `vpc-sc` | Perímetro sobre una política de acceso que ya existe (ignora sus proyectos y reglas de entrada, que entran por recursos aparte), regla de entrada del pipeline como recurso aparte, reglas de salida. Lo usa `0-bootstrap` solo con `org_id` y `access_policy_id` | `restricted_services` incluye `storage.googleapis.com`; dry-run por defecto | `access_policy_id` (obligatoria), `environment` (`common` en `0-bootstrap`), `perimeter_name`, `resources`, `restricted_services`, `ingress_identities`, `egress_policies`, `enforced` | `perimeter_name`, `access_policy_id`, `status_ingress_policies`, `spec_ingress_policies` |
| `observability` | Canales de notificación, verificaciones de disponibilidad, alertas, tableros, SLO | Alertas y tableros base; SLO 99.9 %; filtros limitados al entorno (`<prefix>-<env>-` y la etiqueta `env`) | `project_id`, `notification_emails`, `extra_notification_channel_ids`, `uptime_checks`, `slo_target` | `notification_channel_ids`, `dashboard_ids` |
| `audit-alerts` | Métricas de log de auditoría, sus alertas y un canal de correo. Una sola vez por proyecto, en `1-base` | Los ocho filtros del CIS 2.5 a 2.12 tal como los revisa Security Health Analytics, más cambios de políticas de firewall de red (ADR 0027) | `project_id`, `notification_email`, `alignment_period` | `metric_names`, `metric_filters`, `alert_policy_ids`, `notification_channel_id` |
| `log-export` | Bucket de logs y sink de proyecto con exclusiones | CMEK; retención bloqueable (por variable) | `project_id`, `location`, `kms_key`, `retention_days`, `retention_locked`, `parent` (`projects/<id>` o null), `filter`, `exclusions` | `bucket_name`, `writer_identity`, `sink_name`, `destination` |
| `backup-dr` | Bóveda y plan de Backup and DR; plan de Backup for GKE | Política diaria; retención de 30 días; región secundaria | `project_id`, `region`, `dr_region`, `retention_days`, `gke_cluster_id` (opcional), `sql_log_retention_days` (7 por defecto) | `vault_id`, `plan_ids` |
| `off-hours-shutdown` | Trabajos de Cloud Scheduler que detienen y encienden Cloud SQL (`instances.patch`) y llevan a 0 y devuelven pools de GKE (`setAutoscaling`, `setSize`) | Solo dev y qa (validación); crons `M H * * D` con los mismos días; token OAuth de una cuenta administrada por el usuario (ADR 0028) | `project_id`, `environment`, `region`, `time_zone`, `start_schedule`, `stop_schedule`, `service_account_email`, `sql_instances`, `gke_node_pools` | `job_names`, `job_ids`, `window` |

Con el apagado fuera de horario (ADR 0028), `cloud-sql` recibe `allow_scheduled_stop` (ignora
`activation_policy`; sin él, una `postcondition` exige `ALWAYS`), `compute-mig` recibe
`business_hours` (programa de escalado, mínimo 0 fuera del horario) y `gke` recibe
`scheduled_scaling` (pools en un recurso que ignora `autoscaling`); los tres se rechazan en prod.

Sin módulo propio, a propósito: Persistent Disk (lo crean `compute-mig` y `gke`), Cloud
Interconnect (interruptor dentro de `hybrid-connectivity`), Cloud IDS y Private Service
Connect (aparecen en la especificación como servicios, no como configuración mínima exigida;
no se construyen y se anota en `docs/pendientes-apply.md` como alcance no cubierto).

Los repositorios de Artifact Registry y la política de Binary Authorization no tienen módulo: los
crea `1-base` (`stages/1-base/artifacts.tf`), un repositorio por entorno y aplicación y una sola
política para el proyecto (ADR 0024). El balanceador interno (`load-balancer` con
`type = "internal"`) pone `allow_global_access` en sus reglas de reenvío. `3-workloads` le pasa
su certificado por `certificate_manager_certificates` (lo crea la raíz por región, ver §7.4); el
módulo solo lo crea si no recibe ninguno.

Si un recurso no existe en el proveedor 6.x con el nombre que esperas, no lo inventes:
consulta el registro, y si la función no existe en 6.x, repórtalo.

---

## 9. Políticas, pruebas y pipeline

### 9.1 Políticas (Conftest, `policies/`)

Se evalúan sobre el plan en JSON (`terraform show -json`). Doce reglas, una por archivo `.rego`
(el detalle, los valores desconocidos y las limitaciones están en
[`policies/README.md`](../policies/README.md)):

1. Bucket sin `public_access_prevention = "enforced"` o con miembros `allUsers` /
   `allAuthenticatedUsers`: rechazado (`bucket_public_access`).
2. Instancia, plantilla o nodos de GKE sin Shielded VM: rechazados (`shielded_vm`).
3. Recurso etiquetable sin las cinco etiquetas o con `managed_by` distinto de `terraform`:
   rechazado (`required_labels`).
4. Instancia o plantilla con IP pública, o clúster de GKE sin nodos privados: rechazado
   (`compute_public_ip`).
5. Cloud SQL con IP pública o sin red privada: rechazado (`sql_public_ip`).
6. Llave KMS sin rotación o con rotación mayor a 90 días: rechazada (`kms_rotation`).
7. Asignación de IAM a `user:`: rechazada (`iam_user_principal`).
8. Asignación de IAM fuera de Cloud Storage a `allUsers` o `allAuthenticatedUsers`: rechazada
   (`iam_public_principal`).
9. Cualquier llave de cuenta de servicio: rechazada (`service_account_key`).
10. Bucket sin `uniform_bucket_level_access = true`: rechazado (`bucket_uniform_access`).
11. Ubicación fuera de `us-central1`, `us-east4` (y sus zonas), `us` y `global`: rechazada
    (`resource_locations`; las regiones están escritas en la regla, backlog).
12. En una raíz de entorno (`environment` = `dev`, `qa` o `prod`): tipos únicos del proyecto;
    llaves, secretos y repositorios; todo `google_project_iam_member` y
    `google_project_iam_member_remove` (sea cual sea el principal) y todo
    `google_service_account_iam_*`; y nombres sin `<prefix>-<env>-` (`env_root_scope`, ADR 0029
    §4). El IAM de un recurso (secretos, repositorios, valores de etiqueta, servicios de Cloud
    Run, buckets) sí se permite.

Sin organización, las reglas 1, 2, 4, 5 y 8 a 11 cubren en cada PR lo que harían las políticas de
organización (ADR 0029 §1); con organización corren igual y revisan el plan antes de que la API
lo rechace. Cada regla tiene pruebas en Rego (`conftest verify`) y al menos dos planes de ejemplo
en `policies/fixtures/` (uno que pasa y uno que viola). Comprobado el 24 nov 2026 desde
`gcp-datacenter/` (código de `r3/cierre`) con `PATH="$HOME/go/bin:$PATH" bash
scripts/policy-check.sh`: "138 tests, 138 passed, 0 warnings, 0 failures, 0 exceptions, 0
skipped" y "RESULTADO: 43 planes con el resultado esperado." (21 con resultado esperado `pasa` y
22 con `rechaza`, contados en la tabla que imprime el mismo script); 18 de los 43 son recortes de
un `terraform show -json` real sin GCP (`_real_` en el nombre; por ejemplo, la regla de IP pública
sobre un MIG de doble pila y sobre nodos de GKE públicos). Así el criterio "el pipeline bloquea un
PR que viola una política" se demuestra sin GCP en las pruebas; que bloquee un PR de verdad
depende de configurar `plan-gate` y las comprobaciones de §9.3 como obligatorias en GitHub. Que
las raíces de etapa pasen las reglas 11 y 12 solo lo confirma el primer plan real (puntos 146 y
147 de `pendientes-apply.md`).

### 9.2 Pruebas

| Nivel | Dónde | Sin GCP |
|---|---|---|
| Estático | `scripts/check.sh`: fmt, validate, tflint, checkov sobre módulos, ejemplos y raíces | Sí |
| Políticas | `conftest verify` y `conftest test` sobre los planes de ejemplo (`scripts/policy-check.sh`) | Sí |
| Unitario | `tests/*.tftest.hcl` de módulos y raíces con `mock_provider`, `command = plan` y `override_during = plan` (Terraform 1.11 o mayor, ADR 0021) | Sí |
| Scripts del pipeline | `scripts/selftest.sh`: huella del plan, raíces afectadas, variables por raíz (`root-tfvars.py`), entornos apagados (`disabled-envs.py`), proyecto de pruebas (`terratest-project-check.py`), recursos no administrados, guardas y comprobación del destroy, huérfanos, informe de Go | Sí |
| Go sin GCP | `go vet ./...` y `go test -count=1 ./...` en `tests/` (trabajo `go (vet y pruebas sin GCP)` de `pr.yml`): las pruebas que necesitan GCP se omiten solas y las demás corren | Sí |
| Integración | `tests/integration/` con Terratest: por defecto todas en un solo proyecto de pruebas (`TERRATEST_PROJECT_ID`, que no puede ser el de la landing zone: lo comprueba `scripts/terratest-project-check.py`) con nombres únicos por corrida; con `TEST_EPHEMERAL_PROJECTS=true`, un proyecto efímero por prueba (necesita facturación y una carpeta u organización). Sin `TERRATEST_ORG_ID`, `TestOrg` y `TestVPCSC` se omiten con la marca `[sin-organizacion]` y no cuentan contra `TERRATEST_MAX_SKIPS` | Solo se escribe y compila |
| Extremo a extremo | `tests/e2e/`: aplica 0 → 3 en el proyecto de la landing zone, segundo plan sin cambios, conectividad, destroy de las cargas de dev (y del spoke con `TEST_E2E_DESTROY_NETWORK`) y búsqueda de huérfanos; `TestDevSmoke` es la prueba de humo de `apply.yml` | Solo se escribe |

`scripts/check.sh` no da por hecho que `checkov` esté en el PATH: en Windows el lanzador
`checkov.cmd` busca el Python del sistema y falla (comprobado el 20 nov 2026 con checkov 3.4.6
instalado con uv). El script lee el comando de la variable de entorno `CHECKOV_CMD` y, si no
está definida, usa `checkov`. En Windows con uv: `uvx --from checkov python -m checkov.main`.

Cada prueba unitaria comprueba al menos: que las validaciones rechazan una entrada mala
(`expect_failures`), que los nombres siguen §4.2 y que la configuración "Exige" del módulo
está en el plan.

### 9.3 Flujos de GitHub Actions

| Flujo | Disparo | Qué hace |
|---|---|---|
| `pr.yml` | Pull request | fmt, validate, tflint y checkov con Terraform 1.9.8 (`check.sh --skip test`) y con 1.16.5 (con `terraform test`); `conftest verify` y los planes de ejemplo de las doce reglas (§9.1); autopruebas de los scripts; terraform-docs al día; `go vet` y `go test` de `tests/` sin GCP; si la variable de repositorio `GCP_ENABLED` es `true`: plan por raíz afectada (`affected-roots.sh`) con `tf-read` y `-lock=false`, Conftest sobre el plan, comentario con el resumen y el costo (Infracost). `plan-gate` resume los planes en un nombre fijo para marcarlo como obligatorio |
| `apply.yml` | Merge a `main` que toca `gcp-datacenter/` o `.github/workflows/`, salvo `gcp-datacenter/docs/` y los `.md` de `gcp-datacenter/`; también manual desde `main` | En orden: `1-base` → hub → spoke dev → cargas dev → prueba de humo de dev (`dev-smoke`) → spoke qa → cargas qa → spoke prod → cargas prod. Por cada raíz llama a `_terraform-root.yml`. `common` y `prod` con revisores; dev automático; qa tras la prueba de humo. La variable de repositorio `GCP_DISABLED_ENVS` (`dev`, `qa` o los dos; la valida `scripts/disabled-envs.py`, y con `prod` u otro nombre falla sin aplicar nada) deja fuera las raíces de esos entornos, y el siguiente entorno no los espera |
| `_terraform-root.yml` | Lo llaman `apply.yml` y `destroy.yml` | Por raíz, un trabajo `plan` sin entorno (cuenta `tf-read`, `-lock=false`, Conftest, resumen y huella) y, solo si hay cambios, un trabajo `apply` en el entorno de GitHub de la raíz, con la cuenta `fromJSON(GCP_STAGE_SERVICE_ACCOUNTS)[stage]`, que vuelve a planear con candado y solo aplica si la huella coincide con la revisada (ADR 0025). En modo destroy, `destroy-guard.sh` y `destroy-plan-check.py` |
| `destroy.yml` | Manual | Destroy de dev o qa con confirmación escrita: siempre `3-workloads/envs/<env>`; el spoke `2-networks/envs/<env>` solo con `incluir_red = true` (falso por defecto); después, búsqueda de huérfanos del entorno en el proyecto con Cloud Asset Inventory (`destroy-orphans.py`, con todos los estados: lo que conserva `1-base` o administra todavía un estado no es huérfano). Nunca prod, nunca `1-base` ni el hub; comparte el grupo de concurrencia de `apply.yml` (ADR 0029 §8). Para que el siguiente `apply.yml` no recree el entorno, se agrega a `GCP_DISABLED_ENVS` |
| `drift.yml` | Diario | `plan -detailed-exitcode -lock=false` con `tf-read` por raíz (sin `0-bootstrap` ni las raíces de los entornos de `GCP_DISABLED_ENVS`); si hay cambios, abre una incidencia. Además, recursos no administrados del proyecto con Cloud Asset Inventory (`--scope=projects/<ID>`, `unmanaged-resources.py`) |
| `terratest.yml` | Nocturno, manual y con una etiqueta `modules/<módulo>/vX.Y.Z` | Compila las pruebas siempre; con `GCP_ENABLED`, comprueba que `TERRATEST_PROJECT_ID` no sea el proyecto de la landing zone y corre Terratest (con una etiqueta, solo las pruebas de ese módulo); falla si hay más omitidas que `TERRATEST_MAX_SKIPS`, sin contar las `[sin-organizacion]` |

Los trabajos que tocan GCP se autentican con WIF (§6.4); nunca con llaves. Los `plan`, la prueba
de humo, la búsqueda de huérfanos y los recursos no administrados usan `GCP_AUDIT_SERVICE_ACCOUNT`
(salida `read_service_account` de `0-bootstrap`); los apply, la cuenta de la raíz de
`GCP_STAGE_SERVICE_ACCOUNTS` (salida `stage_service_accounts`). Las variables de cada raíz salen
de `GCP_TFVARS_JSON` (`scripts/root-tfvars.py` junta `common` con la llave de la raíz);
`common.project_id` es obligatorio. Los entornos de GitHub `common`, `dev`, `qa` y `prod` tienen
que existir. Mientras `GCP_ENABLED` no sea `true`, los trabajos de GCP se omiten y los demás
deben pasar. La protección de `main`, las comprobaciones obligatorias y los revisores de los
entornos se configuran a mano en GitHub y dependen del plan de GitHub
([`pipeline.md`](pipeline.md) §4): sin esa configuración, nada de lo anterior bloquea un merge
ni un apply.

`affected-roots.sh`: un cambio en `modules/` o `policies/` afecta a todas las raíces; uno dentro
de una raíz, solo a esa; uno en `stages/0-bootstrap/`, a ninguna (§2.1).

`CODEOWNERS` por etapa: red (`stages/2-networks/` y los módulos de red, balanceador y Cloud
Armor), seguridad (`stages/1-base/`, `policies/` y los módulos `org`, `iam`, `kms`, `secrets`,
`vpc-sc` y `audit-alerts`; solo seguridad: `.github/`, `stages/0-bootstrap/`, `scripts/`,
`.checkov.yaml`, `.tflint.hcl` y `tests/e2e/`), plataforma (el resto, incluida
`stages/3-workloads/`). Las acciones de los flujos van fijadas por SHA.

Versionado de módulos: las raíces consumen los módulos por ruta relativa. Una etiqueta Git
`modules/<modulo>/vX.Y.Z` solo dispara sus pruebas de integración; no hay etiquetas creadas ni
versiones publicadas (ADR 0013).

---

## 10. Documentación entregable

- `gcp-datacenter/README.md`: requisitos previos, orden de despliegue y comandos por etapa.
- `docs/adr/`: los ADR de §2, con su índice en [`adr/README.md`](adr/README.md).
- `docs/cumplimiento-cis.md`: mapa del CIS GCP Foundation Benchmark v5.0 contra el código.
- `docs/pipeline.md`: flujos, variables, entornos y configuración manual de GitHub.
- `docs/runbooks/`: arranque de la etapa 0 (con la red `default`, las cuotas y los controles
  manuales del CIS); alta de una aplicación nueva; rotación de llaves; conmutación a DR;
  respuesta a drift.
- `docs/diagramas/`: los cuatro diagramas, corregidos donde este contrato cambió el diseño
  (Cloud Storage se alcanza por Private Google Access, no por Private Service Access).
- `docs/guia-colaborador-gcp.md`: guía paso a paso para desplegar y probar en GCP.
- `docs/estimacion-de-costos.md`: costo del despliegue, con los registros de acceso a datos en
  los tres entornos (ADR 0029 §7).
- `docs/pendientes-apply.md` (§12).

---

## 11. Paquetes de trabajo

Cada paquete es una rama y un PR. "Nivel" indica la dificultad: A = riesgo de diseño alto,
B = directo. Los paquetes 0 a 14 de la construcción de varios proyectos están en la rama
`archivo/multiproyecto`; estos son los del rediseño a un solo proyecto
([plan](plan-rediseno-un-proyecto.md) §3).

| # | Paquete | Nivel | Depende de |
|---|---|---|---|
| R0 | ADR 0029 y nota en este contrato | A | nada |
| R1-a | `0-bootstrap` y `1-base`, con los módulos `org`, `iam`, `log-export` y `vpc-sc`; retiro de `folders` y `project-factory` | A | R0 |
| R1-b | `2-networks` (hub y spokes), con los módulos `firewall` y `network-spoke` | A | R0 |
| R1-c | `3-workloads`, con los módulos `gke` y `observability`; retiro de las raíces de entorno anteriores | A | R0 |
| R1-d | Pipeline, scripts, datos de prueba y `tests/` | B | R0 |
| R2 | Integración de R1, suite completa con 1.16.5 y 1.9.8, revisión independiente y correcciones | A | R1 |
| R3 | Documentación: este contrato, ADR, README, runbooks, diagramas, guía, mapa CIS, costos y pendientes | B | R2 |
| R4 | Rebanada vertical real: `0-bootstrap`, `1-base`, hub, spoke dev y Cloud Run con Cloud SQL | A | R3 y un proyecto de GCP |

Los paquetes R1-a a R1-d se construyen en paralelo, cada uno en su rama (`r1/<bloque>`).

---

## 12. Pendientes del primer apply

Lista inicial de `docs/pendientes-apply.md`. Cada entrada: qué verificar, dónde está en el
código y qué hacer si falla. Los números se conservan; el texto dice lo que cada punto
significa en el proyecto único.

1. Listado de objetos del backend `gcs` con IAM condicionado por prefijo (§6.2).
2. Activación de Security Command Center en el proyecto: se activa a mano (runbook 01); con
   `enable_scc_notification`, que `1-base` cree la notificación y que SCC publique en el tema.
   Que funcione sin organización es HYPOTHESIS.
3. Solo con organización: `gcp.resourceLocations` frente a la multirregión `us`, el bucket de
   doble región y los recursos globales.
4. Solo con perímetro: que las cargas sigan usando KMS y Secret Manager, ahora restringidos, con
   el perímetro alrededor del proyecto (antes: CMEK del proyecto `security` desde prod).
5. Solo con perímetro: regla de entrada para las nueve cuentas del pipeline.
6. Propagación de rutas: las aprendidas por BGP en el hub llegan a los spokes por el peering,
   y on-premises alcanza los /16 de los spokes.
7. Reenvío de DNS: on-premises recibe el anuncio de 35.199.192.0/19 y responde.
8. Rango del plano de control de GKE: si el clúster usa Private Service Connect, `gke_master`
   queda reservado sin uso.
9. Cuotas del proyecto (redes, peerings por red, CPU, IP, clústeres, instancias de Cloud SQL),
   compartidas por los tres entornos, frente a prod completo (ADR 0029 §10).
10. Tiempo total del despliegue 0 → 3 frente al objetivo de 90 minutos.
11. Segundo `plan` sin cambios en todas las raíces, y destroy de dev (cargas y, con
    `incluir_red`, el spoke) sin huérfanos.
12. Reglas de protección de rama, comprobaciones obligatorias (incluida `plan-gate`) y revisores
    obligatorios de los entornos `common` y `prod` en un repositorio privado, según el plan de
    GitHub del equipo; los entornos `common`, `dev`, `qa` y `prod` deben existir.

Con on-premises real, el plan del hub debe fallar en el pipeline porque lo corre `tf-read`, que
tiene negado el valor del secreto de la VPN (§7.2); mientras siga así, el modo real no se aplica
desde el pipeline. Por verificar: punto 151 y §5 de `pendientes-apply.md`.

La lista completa y vigente (más los marcadores `VERIFICAR-EN-APPLY` del código, los pendientes
nuevos del ADR 0029 y el alcance no cubierto) está en [`pendientes-apply.md`](pendientes-apply.md).
