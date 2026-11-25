# ADR 0015: Sin contraseñas de base de datos ni valores de secretos en Terraform

## Estado

Aceptado, 2026-11-20. Enmendado el 2026-11-21: `run` y `mig` también son usuarios IAM de
Cloud SQL; las cuentas del pipeline no pueden leer valores de secretos (ADR
[0023](0023-endurecimiento-de-la-identidad-del-pipeline.md)). Enmendado el 2026-11-24: con el proyecto único ([ADR 0029](0029-un-solo-proyecto.md))
los contenedores de secretos los crea `1-base` con `tf-base`.

Enmendado otra vez el 2026-11-24, con los arreglos de la revisión de seguridad del código: la
lectura de los secretos y los roles de Cloud SQL de las cuentas de ejecución los da `1-base`, que
ahora crea esas cuentas; `tf-wl-<env>` ya no tiene IAM de secretos y desaparece
`<prefix>TfKmsSecretIamGranter`. La política de denegación niega a las cuentas del pipeline
(salvo `tf-net`) leer valores de secretos, así que el riesgo residual de darse `secretAccessor`
ya no alcanza el valor.

Tipo: Aclaración.

## Contexto

La especificación pide secretos sin texto plano en Terraform. Un valor que Terraform genera
(`random_password`) o recibe (variable, `google_secret_manager_secret_version`) queda en el
estado aunque se marque `sensitive`: `sensitive` solo lo oculta en la salida del plan. El
estado está cifrado con CMEK (ADR 0008), pero lo leen las cuentas del pipeline y cualquiera con
`objectViewer` sobre su prefijo (ADR 0010). Con Terraform 1.9 no hay atributos de solo escritura
(ADR 0001).

## Decisión

- **Cloud SQL** (`cloud-sql`) usa autenticación IAM: bandera `cloudsql.iam_authentication = on`,
  usuarios `CLOUD_IAM_USER`, `CLOUD_IAM_SERVICE_ACCOUNT` o `CLOUD_IAM_GROUP`, ningún
  `root_password` y ningún usuario integrado con contraseña. Con `grant_iam_login_roles = true`
  el módulo da `roles/cloudsql.client` y `roles/cloudsql.instanceUser`, condicionados a la
  instancia, a cuentas de servicio y grupos (nunca a `user:`). Las conexiones exigen TLS
  (`ssl_mode`). `stages/3-workloads/envs/<env>` da de alta como usuario IAM a cada cuenta de
  ejecución cuyo cómputo está encendido: `workload` (GKE, por Workload Identity), `run` (Cloud
  Run) y `mig` (MIG), y pasa `grant_iam_login_roles = false`. Los dos roles los da `1-base`
  (`stages/1-base/runtime_accounts.tf`) por la concesión delegada de `tf-base`, condicionados a
  las instancias `<prefix>-<env>-data-` del entorno de cada cuenta (puntos 132 y 133 de
  [`pendientes-apply.md`](../pendientes-apply.md)).
- **Cuentas del pipeline.** `tf-base` administra los contenedores (`1-base`) con el rol
  personalizado `<prefix>TfSecretContainerAdmin` (contenedores y su IAM, sin permisos de
  versiones), no con `roles/secretmanager.admin`, y da `secretAccessor` solo a las cuentas
  `workload` y `run` de cada entorno sobre los secretos de ese entorno. Las cuentas de entorno no
  tienen IAM de secretos. La política de denegación niega `secretmanager.versions.access` a las
  nueve cuentas salvo `tf-net`, que lee la llave de la VPN real (ADR 0023).
- **Secret Manager** (`secrets`) crea contenedores con replicación administrada por el usuario
  y CMEK por región, y da `roles/secretmanager.secretAccessor`; no tiene ninguna variable por
  la que entre un valor ni crea `google_secret_manager_secret_version`. Las versiones las carga
  el equipo dueño fuera de Terraform. Cloud Run las consume por referencia (`secret_env`).
- **Memorystore** (`memorystore`) deja AUTH apagado y no configurable, por la misma razón: con
  `auth_enabled = true` GCP genera la cadena AUTH y el proveedor la guarda en el estado
  (`auth_string`). La caché queda protegida por IP privada en el rango de PSA, firewall del
  spoke, TLS en tránsito (`SERVER_AUTHENTICATION`, puerto 6378) y el perímetro en prod.

## Alternativas consideradas

- **Contraseñas generadas con `random_password` y guardadas en Secret Manager por Terraform.**
  Rechazada: el valor queda en el estado dos veces (el recurso aleatorio y la versión).
- **Contraseñas cargadas a mano y leídas con un origen de datos.** Rechazada: el origen de datos
  también guarda el valor en el estado.
- **AUTH de Memorystore activo, aceptando el valor en el estado.** Rechazada por coherencia con
  esta regla. Si un caso exige autenticación por cliente, la opción sin secretos es Memorystore
  for Redis Cluster con autenticación IAM (otro recurso, fuera del módulo).

## Consecuencias

- Positivas: ninguna credencial de base de datos ni de aplicación vive en el estado ni en el
  plan; el acceso se revoca quitando un rol de IAM.
- Negativas: las aplicaciones deben usar los conectores de Cloud SQL o el proxy con tokens de
  IAM; `CREATE EXTENSION pgaudit` y los permisos dentro de PostgreSQL se ejecutan fuera de
  Terraform. Que el usuario `postgres` que crea GCP quede sin contraseña utilizable está por
  verificar. Redis sin AUTH confía en la red: cualquier cliente de la VPC del spoke que el
  firewall deje pasar puede usar la caché.
- Excepción conocida: el secreto compartido de la HA VPN sí queda en el estado del hub
  (ADR 0006), porque el túnel lo exige como argumento.
- Riesgo residual: `tf-base` tiene `secretmanager.secrets.setIamPolicy` sobre todos los secretos
  (lo necesita para dar `secretAccessor` a las cuentas de ejecución), así que podría darse
  `secretAccessor` a sí misma o dárselo a otra identidad. La tercera regla de la denegación le
  niega leer el valor (ADR 0023); que la denegación funcione en un proyecto sin organización es
  HYPOTHESIS (punto 93). `tf-net` queda fuera de esa regla. Con varias aplicaciones en un entorno,
  cada una lee todos los secretos de ese entorno.
- Primer apply: que las banderas y los roles condicionados se acepten
  (`VERIFICAR-EN-APPLY` en `modules/cloud-sql/main.tf`; punto 14 de
  [`docs/pendientes-apply.md`](../pendientes-apply.md)) y que los permisos de los roles
  personalizados se admitan (punto 33).
