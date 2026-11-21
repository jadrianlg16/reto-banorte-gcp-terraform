# ADR 0015: Sin contraseñas de base de datos ni valores de secretos en Terraform

## Estado

Aceptado, 2026-11-20.

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
  (`ssl_mode`).
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
- Primer apply: que las banderas y los roles condicionados se acepten
  (`VERIFICAR-EN-APPLY` en `modules/cloud-sql/main.tf`); no tiene entrada propia en §12 y se
  propone agregarla a [`docs/pendientes-apply.md`](../pendientes-apply.md).
