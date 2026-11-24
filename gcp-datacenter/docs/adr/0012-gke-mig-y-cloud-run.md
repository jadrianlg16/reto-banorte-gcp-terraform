# ADR 0012: GKE, MIG y Cloud Run como plataformas de cómputo

## Estado

Aceptado, 2026-11-20. Enmendado el 2026-11-21: enlace de Workload Identity de la cuenta
`workload`, imágenes en Artifact Registry con Binary Authorization por proyecto (ADR
[0024](0024-artifact-registry-y-binary-authorization-por-proyecto.md)) y usuarios IAM de Cloud
SQL por cómputo encendido. Enmendado el 2026-11-24: con el proyecto único
([ADR 0029](0029-un-solo-proyecto.md)) la raíz de cargas es `stages/3-workloads/envs/<env>`; el
namespace de Workload Identity pasa a `<app>-<env>` (el pool del proyecto es el mismo en los
tres entornos); la política de Binary Authorization es una para el proyecto (ADR 0024).

Enmendado otra vez el 2026-11-24, con los arreglos de la revisión de seguridad del código: las
cuentas de ejecución y el enlace de Workload Identity los crea `1-base`
(`stages/1-base/runtime_accounts.tf`), no la raíz de cargas; el namespace queda fijo en
`<app>-<env>`; la política de Binary Authorization admite un atestador por entorno (ADR 0024).

Tipo: Conforme.

## Contexto

La especificación, en su sección de componentes del datacenter, exige tres formas de cómputo
(contenedores orquestados, máquinas virtuales y servicios sin servidor) y pide un ADR que
explique cuándo usar cada una. Cada entorno debe poder activar solo las que use, para no pagar
clústeres vacíos en dev.

## Decisión

Existen los tres módulos y `stages/3-workloads/envs/<env>` los activa con interruptores
(`enable_gke`, `enable_mig`, `enable_cloud_run`):

- **GKE (`gke`)** para las cargas en contenedores que no encajan en Cloud Run (con estado,
  procesos largos, varios servicios acoplados o necesidades propias de Kubernetes). Clúster estándar, nodos privados, Workload Identity, Binary Authorization, CMEK en
  secretos de Kubernetes y discos, Dataplane V2, endpoint privado obligatorio en prod y clúster
  regional obligatorio en prod (validación).
- **MIG (`compute-mig`)** para cargas que requieran VM (software sin contenedor, licencias por
  máquina, agentes del sistema). Plantilla regional con Shielded VM, imagen endurecida por
  variable, autoescalado con mínimo de 2 en prod, autocuración, OS Login, sin IP pública y CMEK
  en el disco.
- **Cloud Run (`cloud-run`)** para servicios HTTP sin estado. Servicio v2 con salida directa a
  la VPC, entrada fija a interno y balanceador, cuenta de servicio propia, CMEK y Binary
  Authorization (ADR 0020 para el acceso público).

Los tres entregan un backend genérico al módulo `load-balancer` (grupo de instancias, NEG de
GKE o NEG sin servidor) y usan cuentas de servicio dedicadas
(`<prefix>-<env>-<app>-{gke-nodes,mig,run}`), que crea `1-base` y la raíz lee de
`runtime_service_accounts`; `tf-wl-<env>` solo tiene `iam.serviceAccountUser` sobre las que
adjunta. La cuenta de Compute por defecto se rechaza (y `0-bootstrap` le quita el rol Editor con
`DEPRIVILEGE`). El clúster de GKE se llama `<prefix>-<env>-<app>-gke[-dr]` (variable
`cluster_name` del módulo, que valida el prefijo `<prefix>-<env>-`).

Con GKE, `1-base` enlaza la cuenta de Kubernetes `<app>-<env>/<gke_workload_ksa_name>` a la
cuenta `workload` con `roles/iam.workloadIdentityUser`, y los pods usan esa cuenta. El pool de
Workload Identity (`<proyecto>.svc.id.goog`) es el mismo en los tres entornos y lo crea GKE con
el primer clúster: el enlace se enciende con `gke_workload_identity_bindings = true` después del
primer apply de cargas con GKE (punto 135), y el namespace es fijo para que un entorno no tome la
cuenta de otro (ADR 0029 §9). `1-base` publica el miembro en `gke_workload_identity_members`, y
la raíz lo repite en su salida `gke_workload_identity_member`. Cada cuenta de ejecución cuyo
cómputo está encendido (`workload` con GKE, `run` con Cloud Run, `mig` con el MIG) es usuario IAM
de Cloud SQL (ADR 0015): el usuario lo crea la raíz de cargas y el permiso, condicionado a las
instancias `<prefix>-<env>-data-`, lo da `1-base` (puntos 132 y 133). Las imágenes de GKE y Cloud
Run salen del repositorio de Artifact Registry del entorno y la aplicación (salida
`artifact_registry_repositories` de `1-base`), con la política de Binary Authorization del
proyecto (ADR 0024).

## Alternativas consideradas

- **Solo GKE (incluido Autopilot).** Rechazada: la especificación exige los tres, y las cargas
  en VM no encajan en Kubernetes.
- **GKE Autopilot en lugar de estándar.** No se adopta por ahora: el diseño fija pools de nodos
  (`gke_node_pools`) que la especificación nombra como variable común. Queda como opción futura.
- **Un solo módulo de cómputo con un selector.** Rechazada: mezclaría tres recursos con
  validaciones distintas y complicaría las pruebas.

## Consecuencias

- Positivas: cada entorno paga solo lo que activa; el balanceador no necesita saber qué hay
  detrás.
- Negativas: tres superficies de endurecimiento y de observabilidad que mantener. El plano de
  control privado de GKE no es alcanzable desde el hub ni desde on-premises (peering no
  transitivo, ADR 0003); hace falta un bastión en el spoke o el endpoint por DNS (no construido).
- El pool de Workload Identity se toma de `module.gke["primary"]`. HIPÓTESIS: durante una
  conmutación con la región primaria caída, leer ese clúster en el plan podría fallar y exigir
  `-refresh=false` o `-target` (no comprobado; runbook 04).
- Primer apply: rango del plano de control si GKE usa Private Service Connect y `gke_master`
  queda sin uso (punto 8), cuotas de CPU, IP y clústeres para prod (punto 9), el enlace de
  Workload Identity (punto 46) y Binary Authorization con la imagen de la aplicación (punto 42
  de [`docs/pendientes-apply.md`](../pendientes-apply.md)).
