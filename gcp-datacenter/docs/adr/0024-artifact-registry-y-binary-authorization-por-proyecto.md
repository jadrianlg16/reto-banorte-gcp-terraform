# ADR 0024: Artifact Registry y política de Binary Authorization por proyecto de servicio

## Estado

Aceptado, 2026-11-21. Completa el ADR 0012.

Tipo: Aclaración.

## Contexto

La especificación exige Binary Authorization para los contenedores (columna "Exige" del módulo
`gke` en §8 del contrato). El módulo `gke` usa `PROJECT_SINGLETON_POLICY_ENFORCE` y `cloud-run`
usa `use_default = true`, pero ninguna etapa creaba un `google_binary_authorization_policy`.
Según el inicio rápido de Binary Authorization de Google, la política por defecto de un proyecto
admite todas las imágenes: el requisito se cumplía solo en apariencia. Tampoco había un
repositorio de imágenes: la API de Artifact Registry estaba habilitada, pero las imágenes de
ejemplo apuntaban a otro proyecto, y la de Cloud Run de prod a un repositorio regional de
`us-central1` que no sobreviviría a la conmutación (punto 25 de los pendientes, que este ADR
resuelve en el código).

## Decisión

En la etapa 4 (`stages/4-projects/envs/<env>/artifacts.tf`), por cada aplicación:

- **Repositorio.** `google_artifact_registry_repository.this`, formato `DOCKER`, nombre
  `<prefix>-<env>-app-<app>-images-<ubicación>`, en la multirregión
  `artifact_registry_location` (`us` por defecto; `us`, `eu` o `asia` por validación), con
  etiquetas inmutables y CMEK con `kms_key_ids[<env>][<ubicación>]["artifacts"]`. La etapa 2
  agrega el uso `artifacts` a las llaves regionales y a las de la multirregión `us`. La etapa 4
  crea el agente de Artifact Registry (`google_project_service_identity`) y le da la llave solo
  en la ubicación del repositorio; una postcondición de `remote_state.tf` exige que la llave
  exista.
- **Lectura.** `roles/artifactregistry.reader` sobre el repositorio (no sobre el proyecto) a la
  cuenta `gke_nodes`, a la cuenta `mig` y al agente de Cloud Run (Cloud Run descarga la imagen
  con su agente). La salida `artifact_registry_repositories` publica
  `<ubicación>-docker.pkg.dev/<proyecto>/<repositorio>` por aplicación.
- **Publicación.** `roles/artifactregistry.writer` sobre el repositorio de cada aplicación a los
  miembros de `artifact_registry_publishers[<app>]`, validados: solo `serviceAccount:` y
  `group:` (nunca `user:`, `allUsers` ni `allAuthenticatedUsers`) y solo llaves de
  `applications`. En prod, `artifactregistry.googleapis.com` es servicio restringido y la regla
  de entrada de la etapa 2 solo admite a las cuentas de las etapas, así que la etapa 4 (que ya
  tiene `policyEditor` sobre la política para las altas) agrega una regla de entrada por
  aplicación con publicadores: sus identidades, desde cualquier origen de red (como la regla de
  la etapa 2), solo hacia el proyecto de servicio de la aplicación y solo
  `artifactregistry.googleapis.com`; con el mismo criterio de modo que las altas
  (`..._ingress_policy` con el perímetro forzado, `..._dry_run_ingress_policy` en dry-run).
  `identities` admite cuentas de servicio, grupos e identidades de terceros individuales (no
  `principalSet://`), según la descripción del esquema del proveedor 6.50.0. Esa regla convive
  con el perímetro de la etapa 2 porque este ignora sus `ingress_policies` y la regla de las
  cuentas de etapa es un recurso de política aparte (`modules/vpc-sc`, ADR 0009); lo que falta
  comprobar en el apply está en el pendiente 53. Las imágenes se referencian con una
  versión o un digest, nunca `latest`: con etiquetas inmutables una etiqueta publicada no se
  mueve.
- **Política.** `google_binary_authorization_policy.this` con
  `global_policy_evaluation_mode = "ENABLE"`; regla por defecto `ALWAYS_DENY` con
  `ENFORCED_BLOCK_AND_AUDIT_LOG`; lista de permitidos con `<ruta del repositorio>/**` más
  `binary_authorization_allowlist_patterns` (vacía por defecto). La validación de esa variable
  exige `<registro>/<ruta>` con al menos un segmento de ruta y comodines solo al final, y `**`
  solo después de `/` (así no se puede escribir `*` solo ni un registro entero como `gcr.io/*`).
  Con `binary_authorization_attestors` no vacío, la regla por defecto pasa a
  `REQUIRE_ATTESTATION` con esos atestadores. `binaryauthorization.googleapis.com` está entre las
  APIs base del proyecto.
- Los módulos `gke` y `cloud-run` no cambian: la política del proyecto es la que aplican.

## Alternativas consideradas

- **Un registro compartido en otro proyecto.** Rechazada por ahora: exigiría permisos de lectura
  entre proyectos para cada agente y, en prod, una regla del perímetro de VPC-SC; un repositorio
  por proyecto de servicio queda dentro del mismo perímetro que sus consumidores.
- **Repositorio regional en `primary_region`.** Rechazada: con la región caída, el cómputo de DR
  no podría descargar imágenes (ADR 0022).
- **Solo atestaciones (`REQUIRE_ATTESTATION`) desde el inicio.** No se impone: exige un
  atestador, su llave y un paso de firma en el proceso de construcción de la aplicación, que
  está fuera de este repositorio. La variable lo deja encender.

## Consecuencias

- Positivas: en todos los entornos solo se despliegan imágenes del repositorio de la aplicación
  (más los patrones que se agreguen por PR); la imagen sobrevive a la pérdida de una región.
- Negativas: cualquier imagen pública (incluida la de muestra `us-docker.pkg.dev/cloudrun/container/hello`
  que usa `tests/e2e/config.example.json`) se rechaza al desplegar, salvo que se copie al
  repositorio o se agregue su patrón a `binary_authorization_allowlist_patterns`. El proceso de
  la aplicación tiene que publicar en el repositorio antes de desplegar, con una identidad de
  `artifact_registry_publishers`.
- Sin comprobar: que la etapa 4, como creadora del proyecto, pueda crear el repositorio, su IAM
  y la política (si no, necesita `roles/artifactregistry.admin` y
  `roles/binaryauthorization.policyEditor` en él), y que Artifact Registry funcione con el
  perímetro de prod forzado (`artifactregistry.googleapis.com` es servicio restringido;
  `binaryauthorization.googleapis.com` no está en la lista).
- Primer apply: la llave del repositorio (punto 41), la política con una imagen permitida y otra
  rechazada en Cloud Run y GKE (punto 42), los permisos de la etapa 4 (punto 47) y la
  publicación a través del perímetro (punto 53) de
  [`docs/pendientes-apply.md`](../pendientes-apply.md).
