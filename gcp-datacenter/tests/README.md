# Pruebas de integración y de extremo a extremo (Terratest)

> **Estado al 21 nov 2026: estas pruebas solo se han compilado (`go build`, `go vet`,
> `go test -run XXX`) y se ha comprobado que sin variables de entorno todas se omiten. Nunca
> se han ejecutado contra GCP.** Nada de lo que comprueban está verificado; cuando corran por
> primera vez, cada fallo es un hallazgo del módulo o de la prueba, no una regresión.

Niveles del contrato (§9.2) que viven aquí:

| Nivel | Carpeta | Qué hace | Sin GCP |
|---|---|---|---|
| Integración | `integration/` | Un proyecto efímero por módulo: `init`/`apply` de `fixtures/<módulo>/`, comprobaciones en salidas y en la API de GCP, `destroy` | Solo se compila |
| Extremo a extremo | `e2e/` | Aplica 0 → 5, mide el tiempo, segundo plan sin cambios, conectividad, destroy de dev y búsqueda de huérfanos | Solo se compila |
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
  fixtures/firewall-hierarchical/   segunda variante del módulo firewall
  fixtures/support/       project (proyecto efímero), cmek (llave de apoyo), network (VPC de apoyo)
  integration/            pruebas de los 24 módulos
  e2e/                    prueba de extremo a extremo, config.example.json y la prueba de humo
                          de dev (smoke_test.go)
```

Cada prueba de integración:

1. se marca `t.Parallel()` y se omite (`t.Skip`) si faltan variables o su compuerta;
2. crea un proyecto efímero `tt-<módulo>-<id>` (`fixtures/support/project`) o reutiliza uno;
3. copia `gcp-datacenter/` a una carpeta temporal (para no compartir `.terraform` ni estado entre
   pruebas en paralelo) y aplica `fixtures/<módulo>/`;
4. comprueba las exigencias del módulo (§8) en las salidas y con `gcloud ... --format=json` o el
   cliente de Cloud Storage de Go;
5. destruye el fixture (`defer`) y después el proyecto (`t.Cleanup`).

Los nombres son únicos por corrida: `prefix` = `t` + cinco caracteres de `random.UniqueID()` en
minúsculas, y todo recurso etiquetable lleva las cinco etiquetas obligatorias más
`terratest_run=<id>`.

## Variables de entorno

`.github/workflows/terratest.yml` exporta las `TERRATEST_*`, `GOOGLE_CLOUD_PROJECT` y las
`TEST_*` de esta tabla salvo `TEST_REUSE_PROJECT`, con los mismos nombres que las variables de
repositorio (`docs/pipeline.md` §2); las que no estén definidas llegan vacías. Ningún ID,
correo ni secreto vive en el código.

| Variable | Uso | Quién la necesita |
|---|---|---|
| `TERRATEST_BILLING_ACCOUNT` | Cuenta de facturación de los proyectos efímeros | Todas las que crean proyecto |
| `TERRATEST_FOLDER_ID` | Carpeta (`folders/<n>` o `<n>`) de proyectos y carpetas efímeros. Opcional: sin ella se usa la organización | Opcional; obligatoria para `TestProjectFactory` |
| `TERRATEST_ORG_ID` | Número de la organización | Padre por defecto; `TestOrg`, `TestVPCSC`, e2e |
| `TERRATEST_PROJECT_ID` | Proyecto de pruebas (cuota y llamadas sin proyecto propio); con `TEST_REUSE_PROJECT=true`, el proyecto donde corren todas | Opcional |
| `GOOGLE_CLOUD_PROJECT` | Proyecto por defecto de `gcloud` y del proveedor | Recomendado |
| `TEST_REUSE_PROJECT` | `true`: no crea proyectos efímeros, usa `TERRATEST_PROJECT_ID` (más rápido; las APIs quedan habilitadas) | Opcional, local |
| `TEST_REGION` / `TEST_DR_REGION` | Regiones (por defecto `us-central1` / `us-east4`). Deben estar en los mapas de códigos cortos de los módulos | Opcional |
| `TEST_DIRECTORY_CUSTOMER_ID` | Cliente de Cloud Identity (`C…`) | `TestOrg` |
| `TEST_ACCESS_POLICY_ID` | Política de Access Context Manager existente (una organización solo tiene una) | `TestVPCSC` |
| `TEST_NOTIFICATION_EMAIL` | Buzón real que recibe las alertas de prueba | `TestObservability` |
| `TEST_GKE_SECURITY_GROUP` | `gke-security-groups@<dominio>` | `TestGKE` |
| `TEST_MIG_IMAGE` | Imagen de la VM (por defecto `debian-cloud/debian-12`) | Opcional |
| `TEST_CLOUD_RUN_IMAGE` | Imagen del contenedor (por defecto la de muestra `cloudrun/container/hello`) | Opcional |
| `TEST_LB_DOMAIN` | Dominio del certificado (por defecto `<prefix>.terratest.example.com`; el certificado no llega a ACTIVE) | Opcional |

La identidad es la de Application Default Credentials (`gcloud auth application-default login`
en local; WIF con `TERRATEST_SERVICE_ACCOUNT` en CI). Necesita crear proyectos y asociarles
facturación en el padre, y para las pruebas de organización, los roles de cada recurso.

## Compuertas

| Compuerta | Pruebas | Motivo |
|---|---|---|
| `TEST_ALLOW_ORG=true` | `TestOrg`, `TestVPCSC`, `TestFirewallHierarchical` | Alcance de organización. Para acotar el efecto: las nueve políticas y la política jerárquica se aplican a una carpeta contenedora vacía creada por la prueba; el sink de `org` sí es de organización, con un filtro que no coincide con nada; el perímetro va en dry-run |
| `TEST_ALLOW_EXPENSIVE=true` | `TestGKE`, `TestCloudSQL`, `TestMemorystore`, `TestFilestore`, `TestHybridConnectivity`, `TestBackupDR` | Lentas (10–20 min) o con cobro por hora relevante |
| `TEST_E2E=true` | `TestEndToEnd` | Aplica la landing zone completa en una organización real |
| `TEST_SMOKE=true` (más `TEST_E2E_STATE_BUCKET`) | `TestDevSmoke` | Lee el estado real y crea Connectivity Tests en dev; la activa `apply.yml` |

Sin compuerta (proyecto efímero y recursos baratos o gratuitos): `storage`, `kms`, `secrets`,
`log-export`, `iam`, `folders`, `project-factory`, `network-hub`, `network-spoke`, `firewall` (de
red), `dns`, `cloud-armor`, `cloud-run`, `compute-mig`, `load-balancer` (externo),
`observability`.

## Advertencia de costo

Las pruebas crean recursos reales que se cobran a `TERRATEST_BILLING_ACCOUNT`. Una corrida de
integración completa con `TEST_ALLOW_EXPENSIVE=true` levanta a la vez un clúster regional de
GKE, Cloud SQL, Redis, 1 TiB de Filestore, cuatro túneles HA VPN y un balanceador global durante
decenas de minutos. La de extremo a extremo despliega toda la landing zone y deja sin destruir
lo compartido. **HIPÓTESIS sin medir**: no hay cifras de costo porque nunca se ha corrido.

Lo que puede quedar después de una corrida (revisar a mano):

- Llaveros y llaves de KMS: GCP no los borra nunca. Las pruebas programan la destrucción de las
  versiones; en un proyecto efímero desaparecen con el proyecto.
- Proyectos efímeros en `DELETE_REQUESTED` durante 30 días (cuentan contra la cuota de proyectos).
- Si un `destroy` falla, la prueba lo marca como error y los recursos siguen vivos.

## Cómo correr

Desde `gcp-datacenter/tests`. Las pruebas largas necesitan `-timeout` mayor que el de Go
(10 min por defecto).

```bash
# Compilar todo sin ejecutar ninguna prueba (lo que hace CI siempre).
go vet ./...
go test -count=1 -run XXX ./...

# Una sola prueba de integración.
export TERRATEST_BILLING_ACCOUNT=... TERRATEST_FOLDER_ID=...
go test -count=1 -v -timeout 60m -run '^TestStorage$' ./integration

# Varias, reutilizando un proyecto ya existente.
export TERRATEST_PROJECT_ID=... TEST_REUSE_PROJECT=true
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
- **integration** (solo si la variable de repositorio `GCP_ENABLED` es `true`): autentica con WIF y
  corre `go test -count=1 -json -timeout 170m` sobre todos los paquetes salvo `e2e`; con una
  etiqueta `modules/<módulo>/vX.Y.Z`, solo las pruebas de ese módulo
  (`scripts/module-tests.sh`). Las compuertas y datos (`TEST_ALLOW_EXPENSIVE`, `TEST_ALLOW_ORG` y
  las `TEST_*` específicas) llegan de variables de repositorio; sin ellas, esas pruebas se
  omiten. `scripts/go-test-report.sh` lista en el resumen cada prueba omitida con su motivo y
  hace fallar el trabajo si hay más omitidas que `TERRATEST_MAX_SKIPS` (0 por defecto): una
  omisión no pasa en silencio.
- La prueba de extremo a extremo no corre en CI: se lanza a mano.
- `TestDevSmoke` corre en `apply.yml` (trabajo `dev / prueba de humo`), no aquí, con
  `TEST_SMOKE=true`, `TEST_E2E_STATE_BUCKET` y la cuenta `GCP_AUDIT_SERVICE_ACCOUNT`; una omisión
  también la hace fallar.

## Exigencias que comprueba cada prueba de integración

| Prueba | Módulo | Comprueba |
|---|---|---|
| `TestStorage` | storage | CMEK con la llave pedida, versionado, acceso uniforme, PAP `enforced`, reglas de ciclo de vida, etiquetas, sin `allUsers` |
| `TestKMS` | kms | Rotación ≤ 90 días y próxima rotación, `ENCRYPT_DECRYPT`, nombres §4.2, `encrypter_decrypters` |
| `TestSecrets` | secrets | Sin versiones (nunca valores), réplica con CMEK en la región, etiquetas, accessor |
| `TestLogExport` | log-export | CMEK, retención de 30 días sin bloquear, PAP, sink al bucket, `writer_identity` con `objectCreator` |
| `TestFolders` | folders | Carpetas por entorno bajo el padre, `folders/<n>`, ACTIVE |
| `TestProjectFactory` | project-factory | Sin red default, facturación, etiquetas, APIs, host de Shared VPC y proyecto de servicio asociado |
| `TestIAM` | iam | Rol de proyecto aditivo, rol condicionado en bucket |
| `TestOrg` | org | Exactamente las nueve políticas con su valor; sink agregado con hijos |
| `TestVPCSC` | vpc-sc | Dry-run explícito, proyecto en el perímetro, `storage` restringido, regla de entrada |
| `TestNetworkHub` | network-hub | VPC personalizada, PGA y flow logs 0.5 en cada subred, router por región con ASN 64514 |
| `TestNetworkSpoke` | network-spoke | PGA y flow logs 0.5, rangos secundarios, proxy-only, PSA, peering en ambos sentidos con rutas personalizadas, NAT |
| `TestFirewallNetwork` | firewall | Llave de etiqueta por etiqueta (`GCE_FIREWALL`), reglas por etiqueta, denegación por defecto, asociación a la VPC |
| `TestFirewallHierarchical` | firewall | Asociación al padre, ninguna regla allow, salud, IAP y tráfico interno delegados con `goto_next` (§7.3), deny por defecto |
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
| `TestBackupDR` | backup-dr | Bóveda en DR con retención mínima de 30 días, planes diarios de 30 días |

No cubierto por integración (sí por las pruebas unitarias o por la de extremo a extremo): las
validaciones que rechazan entradas (`user:`, prod sin HA, etc.), el balanceador interno, la réplica
de Cloud SQL en DR, Backup for GKE y el bucket de doble región.

## Prueba de extremo a extremo (`e2e/`)

Compuerta `TEST_E2E=true`. Variables:

| Variable | Uso |
|---|---|
| `TEST_E2E_CONFIG` | Ruta a un JSON con las variables de cada raíz (copiar `e2e/config.example.json`; los `*.json` de `e2e/` salvo el ejemplo están en `.gitignore`) |
| `TERRATEST_ORG_ID` | Organización para la búsqueda de huérfanos |
| `TEST_E2E_ENVS` | Entornos, separados por coma (por defecto `dev`; dev siempre va). Por ejemplo `dev,prod` |
| `TEST_E2E_STATE_BUCKET` | La etapa 0 ya está arrancada: se salta el procedimiento de estado local |
| `TEST_E2E_IMPERSONATE` | `true`: las etapas 1 a 5 corren suplantando su cuenta de servicio (el operador necesita `iam.serviceAccountTokenCreator` sobre ellas) |
| `TEST_E2E_ENFORCE_DURATION` | `true`: falla si 0 → 5 tarda más de 90 minutos (si no, solo lo registra) |
| `TEST_E2E_CONNECTIVITY` | `false` omite las pruebas de conectividad |
| `TEST_E2E_ONPREM_IP` | IP de destino en on-premises (por defecto `192.168.0.10`) |
| `TEST_E2E_SKIP_DESTROY` | `true`: no destruye dev |
| `TEST_E2E_RUN_ID` | ID de la corrida (etiqueta `e2e_run`); por defecto aleatorio |

### Decisiones de `config.example.json`

- **Imagen de Cloud Run y Binary Authorization.** La etapa 4 crea en el proyecto de la
  aplicación una política ALWAYS_DENY que solo admite su repositorio de Artifact Registry y
  `binary_authorization_allowlist_patterns`. La imagen de muestra
  (`us-docker.pkg.dev/cloudrun/container/hello:latest`) no está en ese repositorio, así que el
  ejemplo la admite con `binary_authorization_allowlist_patterns =
  ["us-docker.pkg.dev/cloudrun/container/hello*"]` en `4-projects/envs/dev`. Se eligió el
  patrón y no publicar la imagen en el repositorio porque solo depende de esa variable (sin
  `docker` ni una identidad publicadora en la prueba). Si se cambia `cloud_run_image`, hay que
  cambiar el patrón; `TestConfigExampleBinaryAuthorization` (sin GCP) lo comprueba contra la
  validación de la variable. **VERIFICAR-EN-APPLY**: que el `*` final admita la etiqueta
  `:latest`. Las pruebas de integración no cambian: corren en proyectos efímeros sin política
  de Binary Authorization propia (la de Google por defecto admite todo).
- **VPN de DR del hub.** `enable_vpn_dr = true` explícito, como en el diseño: el hub crea 8
  túneles (2 HA VPN de 2 túneles en el hub y sus puntas en `onprem-sim`). Se mantiene para que
  0 → 5 mida el tiempo y el costo del diseño real; con un tiempo acotado se puede poner `false`
  (4 túneles), y entonces la prueba no cubre la ruta de DR a on-premises.
  `TestConfigExampleVPNDR` exige que el valor esté escrito.

### Qué automatiza

1. **Etapa 0** según `stages/0-bootstrap/README.md`: copia `backend_override.tf.example` a
   `backend_override.tf`, aplica con estado local, borra el override, migra con
   `terraform init -migrate-state -backend-config=bucket=<state_bucket>`, comprueba que el estado
   remoto no está vacío y mueve `terraform.tfstate*` a la carpeta temporal de la prueba. Si ya
   existe un `terraform.tfstate` o un `backend_override.tf` en la raíz, falla sin tocar nada. Con
   `TEST_E2E_STATE_BUCKET`, solo inicializa contra ese bucket y aplica.
2. **Etapas 1 → 5** en el orden del contrato (`1-org`, `2-security`, `3-networks`,
   `3-networks/envs/<env>`, `4-projects/envs/<env>`, `5-workloads/envs/<env>`), usadas en su lugar
   con `-backend-config=bucket=…` y `-reconfigure`. Por raíz escribe un `.tfvars.json` (fuera del
   repositorio) con `common` + la sección de la raíz + lo que la prueba conoce: `state_bucket`,
   `workloads_service_account` (salida de la etapa 0) y, solo en dev, `project_deletion_policy`,
   `deletion_policy = "DELETE"` y `deletion_protection = false` para poder destruir. Todas las
   etiquetas llevan `e2e_run=<id>`.
3. **Tiempo** total de 0 → 5 frente al objetivo de 90 minutos (§12, pendiente 10): se registra
   siempre y falla solo con `TEST_E2E_ENFORCE_DURATION=true`.
4. **Segundo plan** `plan -detailed-exitcode` en cada raíz aplicada: exige exit 0 (pendiente 11).
5. **Conectividad** con Connectivity Tests (análisis de configuración, sin tráfico ni VM):
   - dev → IP privada de Cloud SQL:5432: REACHABLE;
   - Internet → IP del balanceador de dev:443: REACHABLE;
   - dev → on-premises simulado (192.168.0.10:22 en `onprem-sim`): sin descarte por ruta (el
     firewall puede descartar; lo exigido es la propagación de rutas, pendiente 6);
   - dev → prod (si se aplicó prod): UNREACHABLE (sin peering entre spokes, ADR 0003).

   Solo cuentan resultados definidos: UNDETERMINED, AMBIGUOUS o un paso `abort` en una traza
   fallan siempre, y "sin descarte por ruta" exige al menos una traza y, si el resultado es
   UNREACHABLE, un paso `drop` cuya causa no sea de ruta. La evaluación
   (`evaluateConnectivity`) se prueba sin GCP con respuestas de la API escritas a mano en
   `e2e/testdata/connectivity/` (`go test -run TestEvaluateConnectivity ./e2e/`). Un error al
   leer una salida o al describir la instancia de Cloud SQL falla la prueba; una salida en null
   por un recurso deshabilitado (balanceador sin backend, `simulate_onprem = false`) solo omite
   su prueba y queda en el registro.
6. **Destroy de dev** en orden inverso (5 → 4 → 3) y búsqueda de huérfanos con
   `gcloud asset search-all-resources --query="labels.e2e_run=<id> AND labels.env=dev"` en la
   organización, con reintentos durante 30 minutos (el índice tarda). Los proyectos en
   `DELETE_REQUESTED` no cuentan.

### Qué queda manual

- **SSH por IAP** (`gcloud compute ssh <vm> --tunnel-through-iap`): dev no despliega VM por defecto
  (`enable_mig = false`); con MIG activo, probarlo a mano desde una cuenta con
  `iap.tunnelInstances.accessViaIAP`.
- **HTTPS por el dominio**: el certificado administrado solo pasa a ACTIVE después de crear el
  registro DNS; luego `curl -I https://<dominio>/`.
- **Resolución DNS desde on-premises** (reenvío entrante y anuncio de 35.199.192.0/19, pendiente 7).
- **Simulacro de DR**: runbook `docs/runbooks/04-conmutacion-a-dr.md`; no se automatiza.
- **Desmontaje de lo compartido** (etapas 0, 1, 2, hub y entornos distintos de dev): no se
  destruye. Lleva llaves con `prevent_destroy`, el bucket de estado y, si se bloqueó, la retención
  de logs.

## Prueba de humo de dev (`e2e/smoke_test.go`)

`TestDevSmoke`, compuerta `TEST_SMOKE=true` más `TEST_E2E_STATE_BUCKET`. No aplica ni destruye
nada:

1. `terraform init` con `-backend-config=bucket=…` en `stages/3-networks`,
   `stages/3-networks/envs/dev` y `stages/5-workloads/envs/dev`, y lectura de sus salidas.
2. Las Connectivity Tests de dev de la prueba de extremo a extremo (dev → Cloud SQL, Internet →
   balanceador de dev, dev → on-premises simulado), sin la de prod. Falla si no hay ninguna
   expresable o si alguna no da lo esperado.

La corre `apply.yml` (trabajo `dev / prueba de humo`) después de aplicar dev y antes de qa, con
la cuenta `GCP_AUDIT_SERVICE_ACCOUNT`; sus permisos están en `docs/pipeline.md` §3. Local:

```bash
TEST_SMOKE=true TEST_E2E_STATE_BUCKET=<bucket> go test -count=1 -v -timeout 25m -run '^TestDevSmoke$' ./e2e
```

Estado: compilada; sin variables se omite (comprobado). Nunca ejecutada contra GCP.
