# ADR 0024: Artifact Registry y política de Binary Authorization por proyecto de servicio

## Estado

Aceptado, 2026-11-21. Completa el ADR 0012.

Enmendado el 2026-11-24: con el proyecto único ([ADR 0029](0029-un-solo-proyecto.md) §4) los
repositorios y la política los crea `1-base` (`stages/1-base/artifacts.tf`): un repositorio por
entorno y aplicación (`<prefix>-<env>-<app>`) y una sola política de Binary Authorization para
todo el proyecto. La lista de permitidos es global y no limita los clústeres de prod al
repositorio de prod: se acepta como riesgo, con las atestaciones como alternativa. La regla de
entrada de VPC-SC por aplicación ya no existe. El título y el nombre del archivo se conservan.

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
  sobre todos los repositorios, desde `1-base`. Las cuentas `gke_nodes` y `mig` de cada entorno
  reciben `reader` solo sobre el repositorio de su entorno y aplicación, desde
  `3-workloads/envs/<env>`, que para eso tiene el rol `<prefix>TfRepositoryIamGranter`
  (`artifactregistry.repositories.{get,getIamPolicy,setIamPolicy}`) asignado por `1-base` sobre
  cada repositorio de su entorno.
- **Publicación.** `roles/artifactregistry.writer` sobre el repositorio de cada entorno y
  aplicación a los miembros de `artifact_registry_publishers[<env>][<app>]`. Las imágenes se
  referencian con una versión o un digest, nunca `latest`: con etiquetas inmutables una etiqueta
  publicada no se mueve.
- **Política.** `google_binary_authorization_policy.this`, una sola, con
  `global_policy_evaluation_mode = "ENABLE"`; lista de permitidos con
  `<ruta de cada repositorio>/**` (los de todos los entornos) más
  `binary_authorization_allowlist_patterns`; regla por defecto `ALWAYS_DENY` con
  `ENFORCED_BLOCK_AND_AUDIT_LOG`, o `REQUIRE_ATTESTATION` con `binary_authorization_attestors`.
  Hay una regla por clúster de prod, `<primaria>.<prefix>-prod-<app>-gke` y
  `<DR>.<prefix>-prod-<app>-gke-dr` (nombres fijos por convención, `modules/gke` valida el
  prefijo), con la misma evaluación que la regla por defecto.
- Los módulos `gke` y `cloud-run` no cambian: la política del proyecto es la que aplican.

### Riesgo aceptado: la lista de permitidos es global

El ADR 0029 §4 pedía que la regla de cada clúster de prod solo admitiera el repositorio de prod.
El código no lo logra: según la descripción del campo `admission_whitelist_patterns` en el
proveedor 6.x, una imagen que coincide con la lista de permitidos se admite sin importar las
reglas de admisión (por verificar en la documentación de Binary Authorization). Como la lista
tiene los repositorios de los tres entornos, **un clúster de prod admite una imagen del
repositorio de dev o de qa**. Las reglas de los clústeres de prod existen para que el cambio
futuro sea solo de evaluación.

Lo que lo limita hoy: solo `artifact_registry_publishers` puede publicar en cada repositorio, y el
manifiesto que despliega en prod pasa por un PR revisado. La alternativa que cierra el riesgo son
las **atestaciones**: sacar los repositorios de la lista de permitidos (dejarla solo para
patrones de sistema) y exigir en las reglas de los clústeres de prod un atestador que solo firme
imágenes promovidas a prod (`binary_authorization_attestors`). No se construye ahora porque
exige un atestador, su llave y un paso de firma en el proceso de construcción de la aplicación,
fuera de este repositorio.

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
- **Solo atestaciones (`REQUIRE_ATTESTATION`) desde el inicio.** No se impone, por lo dicho
  arriba. La variable lo deja encender.

## Consecuencias

- Positivas: en todos los entornos solo se despliegan imágenes de los repositorios del proyecto
  (más los patrones que se agreguen por PR); la imagen sobrevive a la pérdida de una región; los
  repositorios no se borran con el destroy de un entorno.
- Negativas: el riesgo de la lista global (arriba). El agente de Cloud Run lee los repositorios
  de los tres entornos (ADR 0029 §9). Cualquier imagen pública (incluida la de muestra
  `us-docker.pkg.dev/cloudrun/container/hello` que usa `tests/e2e/config.example.json`) se
  rechaza al desplegar, salvo que se copie al repositorio o se agregue su patrón a
  `binary_authorization_allowlist_patterns`. Esa variable ya no tiene la validación de formato
  del diseño anterior (`<registro>/<ruta>` con comodines solo al final): hoy un patrón como
  `gcr.io/*` pasaría y solo lo detendría la revisión del PR.
- Con el perímetro opcional forzado, `artifactregistry.googleapis.com` es servicio restringido y
  la regla de entrada solo admite a las nueve cuentas del pipeline: un publicador de fuera del
  perímetro no podría publicar. Hoy el perímetro siempre está en dry-run (ADR 0009, reemplazado).
- Primer apply: la llave del repositorio (punto 41), la política con una imagen permitida y otra
  rechazada en Cloud Run y GKE (punto 42) y los permisos de `tf-base` y `tf-wl-<env>` sobre los
  repositorios (`VERIFICAR-EN-APPLY` en `stages/1-base/artifacts.tf`) de
  [`docs/pendientes-apply.md`](../pendientes-apply.md).
