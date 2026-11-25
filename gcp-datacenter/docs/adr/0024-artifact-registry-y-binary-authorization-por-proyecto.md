# ADR 0024: Artifact Registry y política de Binary Authorization por proyecto de servicio

## Estado

Aceptado, 2026-11-21. Completa el ADR 0012.

Enmendado el 2026-11-24: con el proyecto único ([ADR 0029](0029-un-solo-proyecto.md) §4) los
repositorios y la política los crea `1-base` (`stages/1-base/artifacts.tf`): un repositorio por
entorno y aplicación (`<prefix>-<env>-<app>`) y una sola política de Binary Authorization para
todo el proyecto. La regla de entrada de VPC-SC por aplicación ya no existe. El título y el
nombre del archivo se conservan.

Enmendado otra vez el 2026-11-24, con los arreglos de la revisión de seguridad del código:

- la política admite un atestador por entorno (`binary_authorization_env_attestors`), que cierra
  el riesgo de la lista global cuando se usa;
- la lectura de cada repositorio la da `1-base` a las cuentas de ejecución, porque ahora las crea
  esa raíz, y desaparece el rol `<prefix>TfRepositoryIamGranter`;
- `binary_authorization_allowlist_patterns` vuelve a tener validación de formato.

Tipo: Aclaración.

## Contexto

La especificación exige Binary Authorization para los contenedores (columna "Exige" del módulo
`gke` en §8 del contrato). El módulo `gke` usa `PROJECT_SINGLETON_POLICY_ENFORCE` y `cloud-run`
usa `use_default = true`, pero ninguna etapa creaba un `google_binary_authorization_policy`.
Según el inicio rápido de Binary Authorization de Google, la política por defecto de un proyecto
admite todas las imágenes: el requisito se cumplía solo en apariencia. Tampoco había un
repositorio de imágenes que sobreviviera a la conmutación (punto 25 de los pendientes).

Con el proyecto único, un proyecto tiene **una** política de Binary Authorization: ya no puede
haber una por entorno. Es un recurso único del proyecto, así que no puede vivir en una raíz de
entorno (regla de recursos únicos, contrato §7.5).

## Decisión

En `1-base` (`stages/1-base/artifacts.tf`), por cada entorno de `environments` y aplicación de
`applications`:

- **Repositorio.** `google_artifact_registry_repository.this`, formato `DOCKER`, nombre
  `<prefix>-<env>-<app>`, en `artifact_registry_location` (`us` por defecto; una precondición
  exige `us`, `primary_region` o `dr_region`, donde hay llave `artifacts`), con etiquetas
  inmutables y CMEK con la llave `artifacts` del entorno en esa ubicación. El agente de Artifact
  Registry lo crea `0-bootstrap` (`google_project_service_identity`) y `1-base` le da la llave.
  La salida `artifact_registry_repositories` publica entorno → aplicación →
  `<ubicación>-docker.pkg.dev/<proyecto>/<repositorio>`; `3-workloads` exige con una
  postcondición que exista el de su entorno y aplicación.
- **Lectura.** El agente de Cloud Run (uno por proyecto) recibe `roles/artifactregistry.reader`
  sobre todos los repositorios (`artifacts.tf`). Las cuentas de ejecución `gke_nodes` y `mig` de
  cada entorno y aplicación reciben `reader` solo sobre su repositorio
  (`stages/1-base/runtime_accounts.tf`): los nodos de dev no leen las imágenes de prod. Ninguna
  cuenta del pipeline de entorno tiene IAM sobre los repositorios.
- **Publicación.** `roles/artifactregistry.writer` sobre el repositorio de cada entorno y
  aplicación a los miembros de `artifact_registry_publishers[<env>][<app>]`. Las imágenes se
  referencian con una versión o un digest, nunca `latest`: con etiquetas inmutables una etiqueta
  publicada no se mueve.
- **Política.** `google_binary_authorization_policy.this`, una sola, con
  `global_policy_evaluation_mode = "ENABLE"` y `ENFORCED_BLOCK_AND_AUDIT_LOG` en todas las reglas.
  Tiene dos modos, según `binary_authorization_env_attestors` (entorno → atestador):
  - **Sin atestadores por entorno** (por defecto). La lista de permitidos tiene
    `<ruta de cada repositorio>/**` de los tres entornos más
    `binary_authorization_allowlist_patterns`. La regla por defecto es `ALWAYS_DENY`, o
    `REQUIRE_ATTESTATION` con `binary_authorization_attestors`. Hay reglas solo para los
    clústeres de prod, `<primaria>.<prefix>-prod-<app>-gke` y `<DR>.<prefix>-prod-<app>-gke-dr`,
    con la misma evaluación que la regla por defecto.
  - **Con un atestador por entorno.** La lista de permitidos queda solo con
    `binary_authorization_allowlist_patterns`: los repositorios salen de ella. Cada clúster
    `<primaria>.<prefix>-<env>-<app>-gke` y `<DR>.<prefix>-<env>-<app>-gke-dr` de cada entorno
    exige el atestador de su entorno más los de `binary_authorization_attestors`. La regla por
    defecto (Cloud Run, que no admite reglas por clúster, y todo clúster fuera de la convención)
    exige `binary_authorization_attestors` o, si está vacío, el atestador del primer entorno de
    la promoción (dev, qa, prod). Binary Authorization pide la atestación de **todos** los
    atestadores de una regla, así que "cualquiera de los de entorno" no se puede expresar.
    Una validación exige un atestador para cada entorno de `environments` o ninguno.

  Los nombres de los clústeres son fijos por convención (`modules/gke` valida el prefijo). Los
  atestadores, su llave y el paso de firma no los crea este repositorio (punto 139 de
  [`pendientes-apply.md`](../pendientes-apply.md)).
- **Patrones adicionales.** `binary_authorization_allowlist_patterns` exige la forma
  `<registro>/<ruta>[/*|/**|*]`: al menos un segmento de ruta y comodines solo al final, así que
  `gcr.io/*` o `*` no pasan.
- Los módulos `gke` y `cloud-run` no cambian: la política del proyecto es la que aplican.

### Riesgo aceptado sin atestadores por entorno: la lista de permitidos es global

Según la descripción del campo `admission_whitelist_patterns` de la
[política](https://docs.cloud.google.com/binary-authorization/docs/reference/rest/v1/projects.policy),
una imagen que coincide con la lista de permitidos se admite sin importar las reglas de
admisión. Sin atestadores por entorno, la lista tiene los repositorios de los tres entornos, así
que **un clúster de prod admite una imagen del repositorio de dev o de qa**. Las reglas de los
clústeres de prod existen, pero no lo impiden.

Lo que lo limita en ese modo: solo `artifact_registry_publishers` puede publicar en cada
repositorio, y el manifiesto que despliega en prod pasa por un PR revisado. Lo cierra el modo con
atestadores por entorno, que exige un atestador, su llave y un paso de firma en el proceso de
construcción de la aplicación, fuera de este repositorio. Con ese modo, Cloud Run sigue con la
regla por defecto, común a los tres entornos.

## Alternativas consideradas

- **Un registro compartido en otro proyecto.** Rechazada: exigiría permisos de lectura entre
  proyectos y el cliente pidió un solo proyecto.
- **Un solo repositorio por aplicación para los tres entornos.** Rechazada: dev publicaría donde
  prod descarga, y el destroy de un entorno no podría distinguir sus imágenes.
- **Repositorios en `3-workloads/envs/<env>`.** Rechazada: el destroy del entorno los borraría
  con sus imágenes, y la política única no puede vivir en una raíz de entorno (§7.5 del
  contrato).
- **Repositorio regional en `primary_region`.** Rechazada: con la región caída, el cómputo de DR
  no podría descargar imágenes (ADR 0022).
- **Atestadores por entorno obligatorios desde el inicio.** No se impone: el atestador y la firma
  dependen del proceso de construcción de la aplicación. La variable lo deja encender.

## Consecuencias

- Positivas: en todos los entornos solo se despliegan imágenes de los repositorios del proyecto
  (más los patrones que se agreguen por PR); la imagen sobrevive a la pérdida de una región; los
  repositorios no se borran con el destroy de un entorno. Con atestadores por entorno, un clúster
  de prod solo admite imágenes con la atestación de prod.
- Negativas: el riesgo de la lista global mientras no haya atestadores por entorno (arriba). El
  agente de Cloud Run lee los repositorios de los tres entornos (ADR 0029 §9). Cualquier imagen
  pública (incluida la de muestra `us-docker.pkg.dev/cloudrun/container/hello` que usa
  `tests/e2e/config.example.json`) se rechaza al desplegar, salvo que se copie al repositorio o
  se agregue su patrón a `binary_authorization_allowlist_patterns`.
- Con el perímetro opcional forzado, `artifactregistry.googleapis.com` es servicio restringido y
  la regla de entrada solo admite a las nueve cuentas del pipeline: un publicador de fuera del
  perímetro no podría publicar. Hoy el perímetro siempre está en dry-run (ADR 0009, reemplazado).
- Primer apply: la llave del repositorio (punto 41), la política con una imagen permitida y otra
  rechazada en Cloud Run y GKE (punto 42), los atestadores por entorno (punto 139) y los permisos
  de `tf-base` sobre los repositorios (`VERIFICAR-EN-APPLY` en `stages/1-base/artifacts.tf`) de
  [`docs/pendientes-apply.md`](../pendientes-apply.md).
