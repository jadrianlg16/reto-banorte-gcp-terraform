# Pruebas de integración y de extremo a extremo (Terratest)

> **Estado al 21 nov 2026: estas pruebas solo se han compilado (`go build`, `go vet`,
> `go test -run XXX`) y se ha comprobado que sin variables de entorno todas se omiten. Nunca
> se han ejecutado contra GCP.** Nada de lo que comprueban está verificado; cuando corran por
> primera vez, cada fallo es un hallazgo del módulo o de la prueba, no una regresión.

Niveles del contrato (§9.2) que viven aquí:

| Nivel | Carpeta | Qué hace | Sin GCP |
|---|---|---|---|
| Integración | `integration/` | Por módulo, en el proyecto único de pruebas (o en uno efímero): `init`/`apply` de `fixtures/<módulo>/`, comprobaciones en salidas y en la API de GCP, `destroy` | Solo se compila |
| Extremo a extremo | `e2e/` | Aplica 0 → 3 en el proyecto de la landing zone (ADR 0029), mide el tiempo, segundo plan sin cambios, conectividad, destroy de dev y búsqueda de huérfanos | Solo se compila (salvo las pruebas sin compuerta de `config.example.json`, del orden de raíces y de la evaluación de conectividad, que sí corren) |
| Prueba de humo de dev | `e2e/` (`TestDevSmoke`) | Sin aplicar nada: lee las salidas de dev ya aplicado y corre sus Connectivity Tests. La corre `apply.yml` antes de qa | Solo se compila |

Los niveles estático, de políticas y unitario no están aquí: `scripts/check.sh`, `policies/` y
`modules/<m>/tests/`.

## Estructura

```
tests/
  go.mod, go.sum          módulo Go gcp-datacenter/tests (Terratest v1.0.1, testify v1.12.1, Go 1.26)
  helpers/                variables de entorno, compuertas, nombres únicos, etiquetas, opciones
                          de Terraform con errores reintentables, gcloud en JSON, KMS
  fixtures/<módulo>/      una raíz por módulo que lo llama con entradas de forma real
  fixtures/support/       project (APIs en el proyecto único o proyecto efímero), cmek (llave de
                          apoyo), network (VPC de apoyo)
  integration/            pruebas de los 24 módulos
  e2e/                    prueba de extremo a extremo, config.example.json y la prueba de humo
                          de dev (smoke_test.go)
```

Cada prueba de integración:

1. se marca `t.Parallel()` (salvo `TestOrg`, ver Compuertas) y se omite (`t.Skip`) si faltan
   variables o su compuerta;
2. obtiene su proyecto con `fixtures/support/project`:
   - **por defecto**, el proyecto único de pruebas `TERRATEST_PROJECT_ID` (ADR 0029: un solo
     proyecto, sin carpetas ni organización). Solo habilita las APIs que pide, sin apagarlas al
     terminar (`disable_on_destroy = false`), y no lo borra;
   - con `TEST_EPHEMERAL_PROJECTS=true`, un proyecto efímero `tt-<módulo>-<id>` en
     `TERRATEST_FOLDER_ID` o en la organización `TERRATEST_ORG_ID`, que se borra al final.
     HYPOTHESIS: sin organización una cuenta de servicio no puede crear proyectos; por eso no es
     el modo por defecto;
3. copia `gcp-datacenter/` a una carpeta temporal (para no compartir `.terraform` ni estado entre
   pruebas en paralelo) y aplica `fixtures/<módulo>/`;
4. comprueba las exigencias del módulo (§8) en las salidas y con `gcloud ... --format=json` o el
   cliente de Cloud Storage de Go;
5. destruye el fixture (`defer`) y después, si es efímero, el proyecto (`t.Cleanup`).

Los nombres son únicos por corrida: `prefix` = `t` + cinco caracteres de `random.UniqueID()` en
minúsculas, y todo recurso etiquetable lleva las cinco etiquetas obligatorias más
`terratest_run=<id>`. Así varias pruebas comparten el proyecto único sin chocar. La etiqueta
`env` vale `test` (`helpers.TestEnvLabel`), que no es ningún entorno de la landing zone: un resto
de prueba no se confunde con un recurso de dev en `scripts/destroy-orphans.py` ni en una búsqueda
por `env=dev`. `policies/required_labels.rego` solo exige que la llave exista y los módulos solo
validan las llaves y `managed_by`; la variable `environment` de cada fixture sigue en `dev`
(`vpc-sc`, en `common`), porque los módulos sí validan su valor.
VERIFICAR-EN-APPLY: que las cuotas del proyecto (redes, routers, IP por región) alcancen para las
pruebas en paralelo (`go test -parallel`, por defecto el número de CPU).

## Variables de entorno

`.github/workflows/terratest.yml` exporta las `TERRATEST_*`, `GOOGLE_CLOUD_PROJECT` y las
`TEST_*` de esta tabla, con los mismos nombres que las variables de repositorio
(`docs/pipeline.md` §2); las que no estén definidas llegan vacías. Ningún ID, correo ni secreto
vive en el código.

| Variable | Uso | Quién la necesita |
|---|---|---|
| `TERRATEST_PROJECT_ID` | Proyecto único de pruebas, donde corren todas las de integración por defecto (también cuota y llamadas sin proyecto propio). Tiene que ser otro que el de la landing zone | Todas, salvo con `TEST_EPHEMERAL_PROJECTS=true` |
| `TERRATEST_LANDING_ZONE_PROJECT_ID` | Proyecto de la landing zone. Si está definida e igual a `TERRATEST_PROJECT_ID`, cada prueba de integración se detiene con un error (`helpers.RequireProjectEnv`). En CI la exporta `terratest.yml` desde `GCP_TFVARS_JSON.common.project_id`; en local, exportarla a mano | Opcional (guarda) |
| `TEST_EPHEMERAL_PROJECTS` | `true`: un proyecto efímero por prueba en vez del proyecto único (necesita las tres de abajo) | Opcional |
| `TERRATEST_BILLING_ACCOUNT` | Cuenta de facturación de los proyectos efímeros | Solo con `TEST_EPHEMERAL_PROJECTS=true` |
| `TERRATEST_FOLDER_ID` | Carpeta (`folders/<n>` o `<n>`) de los proyectos efímeros. Opcional: sin ella se usa la organización | Proyectos efímeros |
| `TERRATEST_ORG_ID` | Número de la organización. Sin ella se omiten las pruebas que solo valen con organización | Proyectos efímeros sin carpeta; `TestOrg`, `TestVPCSC` |
| `GOOGLE_CLOUD_PROJECT` | Proyecto por defecto de `gcloud` y del proveedor | Recomendado |
| `TEST_REGION` / `TEST_DR_REGION` | Regiones (por defecto `us-central1` / `us-east4`). Deben estar en los mapas de códigos cortos de los módulos | Opcional |
| `TEST_DIRECTORY_CUSTOMER_ID` | Cliente de Cloud Identity (`C…`). Opcional: con ella `TestOrg` también prueba `iam.allowedPolicyMemberDomains` | `TestOrg` |
| `TEST_ACCESS_POLICY_ID` | Política de Access Context Manager existente (una organización solo tiene una) | `TestVPCSC` |
| `TEST_NOTIFICATION_EMAIL` | Buzón real que recibe las alertas de prueba | `TestObservability`, `TestAuditAlerts` |
| `TEST_GKE_SECURITY_GROUP` | `gke-security-groups@<dominio>` | `TestGKE` |
| `TEST_MIG_IMAGE` | Imagen de la VM (por defecto `debian-cloud/debian-12`) | Opcional |
| `TEST_CLOUD_RUN_IMAGE` | Imagen del contenedor (por defecto la de muestra `cloudrun/container/hello`) | Opcional |
| `TEST_LB_DOMAIN` | Dominio del certificado (por defecto `<prefix>.terratest.example.com`; el certificado no llega a ACTIVE) | Opcional |

La identidad es la de Application Default Credentials (`gcloud auth application-default login`
en local; WIF con `TERRATEST_SERVICE_ACCOUNT` en CI). Necesita en el proyecto único los roles de
los recursos que crean los fixtures y habilitar APIs; solo con proyectos efímeros, crear
proyectos y asociarles facturación en el padre, y para las pruebas de organización, los roles de
cada recurso (`roles/orgpolicy.policyAdmin` en la organización para `TestOrg` y
`roles/accesscontextmanager.policyEditor` sobre la política de acceso para `TestVPCSC`). Los
módulos `org` y `vpc-sc` trabajan sobre el proyecto (ADR 0029 §1) y solo se usan con
organización, así que sus pruebas piden `TERRATEST_ORG_ID`. Las pruebas de `folders` y
`project-factory` se quitaron con esos módulos, y la variante jerárquica de `firewall` también:
el módulo solo crea la política de red de una VPC (ADR 0029 §6).

## Compuertas

| Compuerta | Pruebas | Motivo |
|---|---|---|
| `TEST_ALLOW_ORG=true` (más `TERRATEST_ORG_ID`) | `TestOrg`, `TestVPCSC` | Necesitan organización y permisos en ella. Para acotar el efecto: las políticas de `org` se aplican solo al proyecto de la prueba y el destroy las quita; mientras duran valen para todo el proyecto, por eso `TestOrg` no se marca `t.Parallel()` y `go test` la termina antes de soltar las paralelas del paquete. El perímetro va en dry-run |
| `TEST_ALLOW_EXPENSIVE=true` | `TestGKE`, `TestCloudSQL`, `TestMemorystore`, `TestFilestore`, `TestHybridConnectivity`, `TestBackupDR` | Lentas (10–20 min) o con cobro por hora relevante |
| `TEST_E2E=true` | `TestEndToEnd` | Aplica la landing zone completa en su proyecto real |
| `TEST_SMOKE=true` (más `TEST_E2E_STATE_BUCKET`) | `TestDevSmoke` | Lee el estado real y crea Connectivity Tests en dev; la activa `apply.yml` |

Sin compuerta (recursos baratos o gratuitos): `storage`, `kms`, `secrets`,
`log-export`, `iam`, `network-hub`, `network-spoke`, `firewall` (de
red), `dns`, `cloud-armor`, `cloud-run`, `compute-mig`, `load-balancer` (externo),
`observability`, `audit-alerts`.

## Advertencia de costo

Las pruebas crean recursos reales que se cobran a la facturación del proyecto de pruebas (o a
`TERRATEST_BILLING_ACCOUNT` con proyectos efímeros). Una corrida de
integración completa con `TEST_ALLOW_EXPENSIVE=true` levanta a la vez un clúster regional de
GKE, Cloud SQL, Redis, 1 TiB de Filestore, cuatro túneles HA VPN y un balanceador global durante
decenas de minutos. La de extremo a extremo despliega toda la landing zone y deja sin destruir
lo compartido. **HIPÓTESIS sin medir**: no hay cifras de costo porque nunca se ha corrido.

Lo que puede quedar después de una corrida (revisar a mano):

- Llaveros y llaves de KMS: GCP no los borra nunca. Las pruebas programan la destrucción de las
  versiones; en el proyecto único se acumulan (con el prefijo de cada corrida), en uno efímero
  desaparecen con el proyecto.
- Las APIs habilitadas en el proyecto único quedan habilitadas.
- Con proyectos efímeros, proyectos en `DELETE_REQUESTED` durante 30 días (cuentan contra la
  cuota de proyectos).
- Si un `destroy` falla, la prueba lo marca como error y los recursos siguen vivos; se reconocen
  por la etiqueta `terratest_run=<id>` o el prefijo de la corrida.

## Cómo correr

Desde `gcp-datacenter/tests`. Las pruebas largas necesitan `-timeout` mayor que el de Go
(10 min por defecto).

```bash
# Compilar todo sin ejecutar ninguna prueba (lo que hace CI siempre).
go vet ./...
go test -count=1 -run XXX ./...

# Una sola prueba de integración, en el proyecto único de pruebas.
export TERRATEST_PROJECT_ID=...
go test -count=1 -v -timeout 60m -run '^TestStorage$' ./integration

# Varias, cada una en un proyecto efímero (necesita organización o carpeta).
export TEST_EPHEMERAL_PROJECTS=true TERRATEST_BILLING_ACCOUNT=... TERRATEST_FOLDER_ID=...
go test -count=1 -v -timeout 90m -run 'TestStorage|TestKMS|TestSecrets' ./integration

# Todas las de integración, incluidas las caras y las de organización.
TEST_ALLOW_EXPENSIVE=true TEST_ALLOW_ORG=true go test -count=1 -v -timeout 170m ./integration

# Extremo a extremo (ver abajo).
TEST_E2E=true TEST_E2E_CONFIG=/ruta/a/e2e.json go test -count=1 -v -timeout 6h ./e2e
```

En Windows se usan las mismas órdenes (PowerShell: `$env:VAR = "..."`). El código no invoca
ningún shell: llama a `terraform` y `gcloud` directamente (en Windows, `gcloud.cmd` por
`PATHEXT`), usa `filepath` y la carpeta temporal del sistema.

## Qué hace CI

`.github/workflows/terratest.yml` (raíz del repositorio):

- **compile** (siempre): `go vet ./...` y `go test -count=1 -run XXX ./...`. Compila los binarios de
  prueba sin ejecutar ninguna.
- **integration** (solo si la variable de repositorio `GCP_ENABLED` es `true`): antes de todo,
  `scripts/terratest-project-check.py` falla si `TERRATEST_PROJECT_ID` es
  `GCP_TFVARS_JSON.common.project_id` (sin imprimir ninguno de los dos) y exporta
  `TERRATEST_LANDING_ZONE_PROJECT_ID` para la guarda de cada prueba. Después autentica con WIF y
  corre `go test -count=1 -json -timeout 170m` sobre todos los paquetes salvo `e2e`; con una
  etiqueta `modules/<módulo>/vX.Y.Z`, solo las pruebas de ese módulo
  (`scripts/module-tests.sh`). Las compuertas y datos (`TEST_ALLOW_EXPENSIVE`, `TEST_ALLOW_ORG` y
  las `TEST_*` específicas) llegan de variables de repositorio; sin ellas, esas pruebas se
  omiten. `scripts/go-test-report.sh` lista en el resumen cada prueba omitida con su motivo y
  hace fallar el trabajo si hay más omitidas que `TERRATEST_MAX_SKIPS` (0 por defecto): una
  omisión no pasa en silencio.
- La prueba de extremo a extremo no corre en CI: se lanza a mano.
- `TestDevSmoke` corre en `apply.yml` (trabajo `dev / prueba de humo`), no aquí, con
  `TEST_SMOKE=true`, `TEST_E2E_STATE_BUCKET` y la cuenta de lectura `GCP_AUDIT_SERVICE_ACCOUNT`
  (salida `read_service_account` de `0-bootstrap`); una omisión también la hace fallar.

## Exigencias que comprueba cada prueba de integración

| Prueba | Módulo | Comprueba |
|---|---|---|
| `TestStorage` | storage | CMEK con la llave pedida, versionado, acceso uniforme, PAP `enforced`, reglas de ciclo de vida, etiquetas, sin `allUsers` |
| `TestKMS` | kms | Rotación ≤ 90 días y próxima rotación, `ENCRYPT_DECRYPT`, nombres §4.2, `encrypter_decrypters` |
| `TestSecrets` | secrets | Sin versiones (nunca valores), réplica con CMEK en la región, etiquetas, accessor |
| `TestLogExport` | log-export | CMEK, retención de 30 días sin bloquear, PAP, sink de proyecto al bucket con la exclusión del propio bucket, `writer_identity` con `objectCreator` |
| `TestIAM` | iam | Rol de proyecto aditivo, rol condicionado en bucket |
| `TestOrg` | org | Exactamente las siete políticas (ocho con `TEST_DIRECTORY_CUSTOMER_ID`) con su valor, con padre `projects/<id>` |
| `TestVPCSC` | vpc-sc | Perímetro `common` en dry-run explícito sobre una política existente, proyecto en el perímetro, `storage` restringido, regla de entrada |
| `TestNetworkHub` | network-hub | VPC personalizada, PGA y flow logs al 100 % (valor por defecto) en cada subred, router por región con ASN 64514 |
| `TestNetworkSpoke` | network-spoke | PGA y flow logs al 100 % (valor por defecto), rangos secundarios, proxy-only, PSA, peering en ambos sentidos con rutas personalizadas, NAT |
| `TestFirewallNetwork` | firewall | Llave de etiqueta por etiqueta (`GCE_FIREWALL`), reglas por etiqueta, denegación por defecto, asociación a la VPC |
| `TestDNS` | dns | Zonas privadas en la VPC, VIP restringido, reenvío por ruta privada, reenvío entrante |
| `TestHybridConnectivity` | hybrid-connectivity | 2 interfaces, 2 túneles ESTABLISHED, BGP UP, anuncio CUSTOM con 35.199.192.0/19 |
| `TestComputeMIG` | compute-mig | Shielded VM, sin IP pública, disco con CMEK, cuenta propia, autocuración, límites del autoescalador |
| `TestGKE` | gke | Nodos y endpoint privados, Workload Identity, Binary Authorization, etcd con CMEK, nodos Shielded con cuenta propia |
| `TestCloudRun` | cloud-run | Entrada interna y del balanceador, cuenta propia, CMEK, salida a VPC, sin miembros públicos, NEG |
| `TestCloudSQL` | cloud-sql | Sin IP pública, SSL obligatorio, respaldos y PITR, CMEK, autenticación IAM, zonal en dev, etiquetas |
| `TestMemorystore` | memorystore | PSA, VPC autorizada, CMEK, BASIC en dev |
| `TestFilestore` | filestore | CMEK, red por PSA |
| `TestCloudArmor` | cloud-armor | Reglas OWASP de SQLi y XSS, límite de tasa |
| `TestLoadBalancerExternal` | load-balancer | HTTPS 443 con certificado, HTTP 80 redirige, Cloud Armor y registro en el backend |
| `TestObservability` | observability | Canal de correo, cuatro alertas base, SLO, tablero |
| `TestAuditAlerts` | audit-alerts | Nueve métricas de log con el filtro publicado, una alerta por métrica, canal de correo (que SCC las reconozca: pendiente 58) |
| `TestBackupDR` | backup-dr | Bóveda en DR con retención mínima de 30 días, planes diarios de 30 días |
| `TestOffHoursShutdown` | off-hours-shutdown | Seis trabajos de Cloud Scheduler habilitados (Cloud SQL y un pool de GKE que no existen) con su horario, zona horaria, método, URI, cuerpo y token OAuth de la cuenta del fixture; no su efecto (ADR 0028, pendiente 81) |

No cubierto por integración (sí por las pruebas unitarias o por la de extremo a extremo): las
validaciones que rechazan entradas (`user:`, prod sin HA, etc.), el balanceador interno, la réplica
de Cloud SQL en DR, Backup for GKE y el bucket de doble región.

## Prueba de extremo a extremo (`e2e/`)

Compuerta `TEST_E2E=true`. Variables:

| Variable | Uso |
|---|---|
| `TEST_E2E_CONFIG` | Ruta a un JSON con las variables de cada raíz (copiar `e2e/config.example.json`; los `*.json` de `e2e/` salvo el ejemplo están en `.gitignore`) |
| `TEST_E2E_ENVS` | Entornos, separados por coma (por defecto `dev`; dev siempre va). Por ejemplo `dev,prod` |
| `TEST_E2E_STATE_BUCKET` | La etapa 0 ya está arrancada: se salta el procedimiento de estado local |
| `TEST_E2E_IMPERSONATE` | `true`: las raíces 1 a 3 corren suplantando su cuenta de servicio (el operador necesita `iam.serviceAccountTokenCreator` sobre ellas) |
| `TEST_E2E_ENFORCE_DURATION` | `true`: falla si 0 → 3 tarda más de 90 minutos (si no, solo lo registra) |
| `TEST_E2E_CONNECTIVITY` | `false` omite las pruebas de conectividad |
| `TEST_E2E_ONPREM_IP` | IP de destino en on-premises (por defecto `192.168.0.10`) |
| `TEST_E2E_SKIP_DESTROY` | `true`: no destruye dev |
| `TEST_E2E_DESTROY_NETWORK` | `true`: destruye también el spoke de dev (como `incluir_red` de `destroy.yml`) |
| `TEST_E2E_RUN_ID` | ID de la corrida (etiqueta `e2e_run`); por defecto aleatorio |
| `PYTHON` | Intérprete para `scripts/destroy-orphans.py` (por defecto `python3`) |

Ya no hace falta `TERRATEST_ORG_ID`: el proyecto y su número salen de las salidas `project_id` y
`project_number` de `0-bootstrap`.

### Decisiones de `config.example.json`

- **Proyecto único.** `common.project_id` es el proyecto que creó una persona (ADR 0029 §1); las
  llaves de `stages` son las raíces del ADR 0029 §2 (`0-bootstrap`, `1-base`, `2-networks`,
  `2-networks/envs/dev`, `3-workloads/envs/dev`). `TestConfigExampleRoots` (sin GCP) lee con el
  analizador de HCL los bloques `variable` de los `*.tf` de cada raíz y, con las mismas
  variables que arma la prueba (common, la raíz y lo que inyecta: `state_bucket`,
  `deletion_protection` de las cargas de dev y `labels`), exige: solo raíces del ADR 0029 §2 y
  todas ellas; todas las variables sin `default`; que cada valor quepa en el tipo de su variable
  con la conversión de Terraform (un objeto no entra en `set` o `list`, un arreglo no entra en
  `map` u `object`, ni un texto en `number`; también lo de adentro), y que la llave de una raíz
  no traiga variables que la raíz no declara. Una variable de `common` que una raíz no declara
  solo produce una advertencia de Terraform (`-var-file`). Si una raíz agrega una variable
  obligatoria, la prueba falla hasta agregarla al ejemplo. `TestJSONFitsType` prueba la
  comparación de tipos con casos buenos y malos.
- **Imagen de Cloud Run y Binary Authorization.** `1-base` crea la única política de Binary
  Authorization del proyecto, que solo admite los repositorios de Artifact Registry del proyecto
  y `binary_authorization_allowlist_patterns` (ADR 0029 §4). La imagen de muestra
  (`us-docker.pkg.dev/cloudrun/container/hello:latest`) no está en esos repositorios, así que el
  ejemplo la admite con `binary_authorization_allowlist_patterns =
  ["us-docker.pkg.dev/cloudrun/container/hello*"]` en `1-base`. Se eligió el patrón y no
  publicar la imagen en el repositorio porque solo depende de esa variable (sin `docker` ni una
  identidad publicadora en la prueba). Si se cambia `cloud_run_image`, hay que cambiar el patrón;
  `TestConfigExampleBinaryAuthorization` (sin GCP) lo comprueba contra la validación de la
  variable en la raíz de `stages/` que la declare. **VERIFICAR-EN-APPLY**: que el `*` final
  admita la etiqueta `:latest`. Las pruebas de integración no cambian: no aplican `1-base`.
  HYPOTHESIS: si el proyecto único de pruebas es el mismo de la landing zone, su política de
  Binary Authorization también vale para `TestCloudRun` y `TestGKE`; por eso conviene un proyecto
  de pruebas aparte.
- **VPN de DR del hub.** `enable_vpn_dr = true` explícito, como en el diseño: el hub crea 8
  túneles (2 HA VPN de 2 túneles en el hub y sus puntas en `onprem-sim`). Se mantiene para que
  0 → 3 mida el tiempo y el costo del diseño real; con un tiempo acotado se puede poner `false`
  (4 túneles), y entonces la prueba no cubre la ruta de DR a on-premises.
  `TestConfigExampleVPNDR` exige que el valor esté escrito.

### Qué automatiza

1. **Etapa 0** según `stages/0-bootstrap/README.md`: copia `backend_override.tf.example` a
   `backend_override.tf`, aplica con estado local, borra el override, migra con
   `terraform init -migrate-state -backend-config=bucket=<state_bucket>`, comprueba que el estado
   remoto no está vacío y mueve `terraform.tfstate*` a la carpeta temporal de la prueba. Si ya
   existe un `terraform.tfstate` o un `backend_override.tf` en la raíz, falla sin tocar nada. Con
   `TEST_E2E_STATE_BUCKET`, solo inicializa contra ese bucket y aplica.
2. **Raíces 1 → 3** en el orden de `apply.yml` (ADR 0029 §2): `1-base`, el hub `2-networks` y,
   por cada entorno pedido, `2-networks/envs/<env>` y `3-workloads/envs/<env>`. Se usan en su
   lugar con `-backend-config=bucket=…` y `-reconfigure`. Por raíz escribe un `.tfvars.json`
   (fuera del repositorio) con `common` + la sección de la raíz + lo que la prueba conoce:
   `state_bucket` (salida de la etapa 0) y, solo en `3-workloads/envs/dev`,
   `deletion_protection = false` para poder destruir. Ninguna raíz crea ni borra proyectos.
   Todas las etiquetas llevan `e2e_run=<id>`.
3. **Tiempo** total de 0 → 3 frente al objetivo de 90 minutos (§12, pendiente 10): se registra
   siempre y falla solo con `TEST_E2E_ENFORCE_DURATION=true`.
4. **Segundo plan** `plan -detailed-exitcode` en cada raíz aplicada: exige exit 0 (pendiente 11).
5. **Conectividad** con Connectivity Tests (análisis de configuración, sin tráfico ni VM), todas
   en el proyecto único (el proyecto sale del `network_self_link` del spoke de dev):
   - dev → IP privada de Cloud SQL:5432: REACHABLE;
   - Internet → IP del balanceador de dev:443: REACHABLE;
   - dev → on-premises simulado (192.168.0.10:22 en `onprem-sim`): ruta por la HA VPN (el
     firewall puede descartar; lo exigido es la propagación de rutas, pendiente 6);
   - dev → prod (si se aplicó prod): UNREACHABLE (sin peering entre spokes, ADR 0003).

   Solo cuentan resultados definidos: UNDETERMINED, AMBIGUOUS, un paso `ABORT` o
   `VIEWER_PERMISSION_MISSING` fallan siempre. "Ruta por la HA VPN" exige evidencia positiva en
   cada traza: un paso `ARRIVE_AT_VPN_TUNNEL` o un `APPLY_ROUTE` con
   `route.nextHopType = NEXT_HOP_VPN_TUNNEL`; antes de ese paso no se admite ningún descarte y
   después solo `FIREWALL_RULE`. Así no pasa, por ejemplo, un paquete que sale por la ruta por
   defecto a Internet del spoke (`PRIVATE_TRAFFIC_TO_INTERNET`) ni un `ROUTING_LOOP`. La
   evaluación (`evaluateConnectivity`) se prueba sin GCP con respuestas escritas a mano en
   `e2e/testdata/connectivity/`, solo con estados y campos de la referencia v1 de la API de
   Network Management (la prueba rechaza un estado o campo que no exista)
   (`go test -run TestEvaluateConnectivity ./e2e/`). HIPÓTESIS: que la API devuelva esas trazas
   para la VPN hacia `onprem-sim`; VERIFICAR-EN-APPLY. Un error al
   leer una salida o al describir la instancia de Cloud SQL falla la prueba; una salida en null
   por un recurso deshabilitado (balanceador sin backend, `simulate_onprem = false`) solo omite
   su prueba y queda en el registro. Una instancia de Cloud SQL detenida por el apagado fuera de
   horario (`settings.activationPolicy = NEVER`, ADR 0028) falla la prueba con un mensaje que
   lo dice y cómo seguir; la detección se prueba sin GCP
   (`go test -run TestSQLStoppedError ./e2e/`).
6. **Destroy de dev** como `destroy.yml` (ADR 0029 §8): siempre `3-workloads/envs/dev`; el
   spoke `2-networks/envs/dev` solo con `TEST_E2E_DESTROY_NETWORK=true` (la conexión de PSA
   puede tardar en poder borrarse después de Cloud SQL).
7. **Huérfanos** como `destroy.yml`: `terraform state pull` de cada raíz aplicada,
   `gcloud asset search-all-resources --scope=projects/<project_id>` y
   `scripts/destroy-orphans.py --env dev` con esos estados. Huérfano es lo que tenga
   `labels.env=dev` o un nombre con `<prefix>-dev-` y no esté en ningún estado ni en la lista de
   lo que conserva `1-base` (llaves, llaveros, repositorios y secretos). Se reintenta durante 30
   minutos (el índice tarda). Necesita `python3` (o `PYTHON`) y
   `cloudasset.assets.searchAllResources` en el proyecto (VERIFICAR-EN-APPLY).

### Qué queda manual

- **SSH por IAP** (`gcloud compute ssh <vm> --tunnel-through-iap`): dev no despliega VM por defecto
  (`enable_mig = false`); con MIG activo, probarlo a mano desde una cuenta con
  `iap.tunnelInstances.accessViaIAP`.
- **HTTPS por el dominio**: el certificado administrado solo pasa a ACTIVE después de crear el
  registro DNS; luego `curl -I https://<dominio>/`.
- **Resolución DNS desde on-premises** (reenvío entrante y anuncio de 35.199.192.0/19, pendiente 7).
- **Simulacro de DR**: runbook `docs/runbooks/04-conmutacion-a-dr.md`; no se automatiza.
- **Desmontaje de lo compartido** (`0-bootstrap`, `1-base`, el hub y entornos distintos de dev):
  no se destruye. Lleva llaves con `prevent_destroy`, el bucket de estado y, si se bloqueó, la
  retención de logs. El proyecto no se borra (lo creó una persona).

## Prueba de humo de dev (`e2e/smoke_test.go`)

`TestDevSmoke`, compuerta `TEST_SMOKE=true` más `TEST_E2E_STATE_BUCKET`. No aplica ni destruye
nada:

1. `terraform init` con `-backend-config=bucket=…` en `stages/2-networks`,
   `stages/2-networks/envs/dev` y `stages/3-workloads/envs/dev`, y lectura de sus salidas
   (`onprem_sim_network_name` del hub; `network_self_link` y `subnets` del spoke;
   `sql_instance_connection_name` y `lb_ip_address` de las cargas).
2. Las Connectivity Tests de dev de la prueba de extremo a extremo (dev → Cloud SQL, Internet →
   balanceador de dev, dev → on-premises simulado), sin la de prod. Falla si no hay ninguna
   expresable o si alguna no da lo esperado.

La corre `apply.yml` (trabajo `dev / prueba de humo`) después de aplicar dev y antes de qa, con
la cuenta de lectura `GCP_AUDIT_SERVICE_ACCOUNT` (`tf-read`, con
`roles/networkmanagement.admin` en el proyecto, ADR 0029 §3); sus permisos están en
`docs/pipeline.md` §3. Las pruebas se crean en el proyecto único, que tiene la API
`networkmanagement.googleapis.com` habilitada por `0-bootstrap` (todas las APIs, una sola vez).
Local:

```bash
TEST_SMOKE=true TEST_E2E_STATE_BUCKET=<bucket> go test -count=1 -v -timeout 25m -run '^TestDevSmoke$' ./e2e
```

Estado: compilada; sin variables se omite (comprobado). Nunca ejecutada contra GCP.
