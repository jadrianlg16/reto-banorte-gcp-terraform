# Contrato de construcción: Datacenter en GCP con Terraform

Fuente única para quien construya o revise este repositorio (personas o agentes). Si algo de
aquí contradice la especificación de Banorte, gana la especificación, salvo las desviaciones
listadas en §2, que quedan registradas como ADR.

Estado al 20 nov 2026: todo se construye y se prueba **sin acceso a GCP**. Nada se ha aplicado.
La organización de GCP será una propia del equipo y se conecta al final.

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

---

## 2. Decisiones cerradas

Cada fila se redacta como ADR en `docs/adr/NNNN-titulo.md` (formato: contexto, decisión,
alternativas, consecuencias). Las marcadas "desviación" se apartan de la especificación o de
su diagrama y deben decirlo.

| ADR | Decisión | Motivo | Tipo |
|---|---|---|---|
| 0001 | Proveedores `hashicorp/google` y `google-beta` en `~> 6.0`; `required_version = ">= 1.9"` | Convención obligatoria de la especificación. La versión vigente del registry es mayor; se actualiza por PR cuando el cliente lo pida | Conforme |
| 0002 | Regiones `us-central1` (primaria) y `us-east4` (DR), ambas como variables | Propuesta de la especificación; `northamerica-south1` si hubiera residencia de datos | Conforme |
| 0003 | Una VPC por entorno (spoke, host de Shared VPC) unida al hub por VPC Network Peering; sin peering entre spokes | La especificación se contradice: su diagrama dibuja una sola Shared VPC en el hub y su jerarquía pide un proyecto de red spoke por entorno. Se sigue la jerarquía: el aislamiento entre entornos lo da la red y no solo el firewall | Desviación del diagrama |
| 0004 | Cloud NAT en cada spoke y región, no en el hub | Un Cloud NAT no da salida a redes unidas por peering | Desviación del diagrama |
| 0005 | Balanceador HTTPS global y Cloud Armor en el proyecto de servicio de cada entorno | Con peering, los backends viven en el spoke; el balanceador global es un servicio de borde de Google, no un recurso de la VPC hub. El tráfico on-premises sí entra solo por el hub | Desviación del diagrama |
| 0006 | On-premises simulado con una VPC `onprem-sim` y HA VPN entre VPC, activable con `simulate_onprem` | No hay sitio on-premises real para el equipo. Con `simulate_onprem = false` el mismo módulo apunta a un gateway externo | Supuesto |
| 0007 | CI/CD con GitHub Actions | El equipo ya usa GitHub; la especificación lo deja a elección | Conforme |
| 0008 | La etapa 0 crea su propia llave KMS para cifrar el bucket de estado | La especificación pide CMEK en el bucket de estado (etapa 0) pero ubica KMS en la etapa 2. Sin llave propia habría una ventana sin CMEK | Aclaración |
| 0009 | La etapa 2 crea el perímetro de VPC-SC (con el proyecto de seguridad dentro) y la etapa 4 le agrega los proyectos de prod. Arranca en modo dry-run (`vpc_sc_enforced = false`) | Los proyectos de prod no existen cuando corre la etapa 2. El dry-run evita bloquear el pipeline en el primer despliegue | Aclaración |
| 0010 | Un solo bucket de estado con un prefijo por etapa y entorno. Cada cuenta de servicio escribe solo su prefijo y lee los prefijos de las etapas anteriores, con condiciones de IAM | La especificación pide a la vez "solo su prefijo" y leer las salidas de la etapa anterior; leer aguas arriba es la interpretación mínima que cumple ambas | Aclaración |
| 0011 | Los módulos y etapas se construyen en paralelo y sin GCP; se aplican en orden 0 → 5 cuando exista la organización | La regla "ningún sprint empieza sin cerrar el anterior" quedó bloqueada por la falta de organización. Se cambia el orden de construcción, no el de despliegue | Desviación del plan |
| 0012 | GKE para las cargas en contenedores y MIG para las que requieran VM; Cloud Run para servicios sin estado. Los tres módulos existen; cada entorno activa los que use | La especificación exige los tres y pide este ADR | Conforme |
| 0013 | Módulos propios escritos con recursos del proveedor, sin envolver módulos de terceros | Permite pruebas con `mock_provider` sin descargar dependencias y deja cada recurso a la vista del revisor. La especificación permite ambos caminos | Conforme |
| 0014 | La raíz del hub vive en `stages/3-networks/` y cada spoke en `stages/3-networks/envs/<env>/` | El árbol de la especificación solo muestra `envs/`; el hub necesita su propia raíz y su propio estado | Aclaración |
| 0015 | Sin contraseñas de base de datos: Cloud SQL usa autenticación IAM. El módulo `secrets` crea contenedores y permisos, nunca valores | "Secretos sin texto plano en Terraform": un valor generado por Terraform quedaría en el estado | Aclaración |
| 0016 | Los valores de etiquetas van en minúsculas (`ti-001`, no `TI-001`) | GCP rechaza mayúsculas en valores de etiquetas; el ejemplo de la especificación no sería válido | Desviación menor |
| 0017 | Las cuentas de servicio se nombran `<prefijo>-tf-<etapa>` y `<prefijo>-<env>-<app>-<uso>` | El límite de 30 caracteres del ID no deja espacio a la convención completa | Desviación menor |

Pendiente de decidir por el equipo (no bloquea la construcción): usuarios de GitHub para
`CODEOWNERS` (se usan marcadores `@PENDIENTE-red`, `@PENDIENTE-seguridad`,
`@PENDIENTE-plataforma`).

---

## 3. Estructura del repositorio

El proyecto vive en `gcp-datacenter/` dentro del repositorio del equipo. `.github/` va en la
raíz del repositorio porque GitHub solo lee flujos de ahí; todos los flujos usan
`working-directory: gcp-datacenter`.

```
.github/
  workflows/{pr.yml, apply.yml, drift.yml, terratest.yml}
  CODEOWNERS
gcp-datacenter/
  README.md
  modules/<modulo>/
    main.tf  variables.tf  outputs.tf  versions.tf  README.md
    examples/basic/main.tf
    tests/<modulo>.tftest.hcl
  stages/
    0-bootstrap/
    1-org/
    2-security/
    3-networks/            # raíz del hub
      envs/{dev,qa,prod}/  # una raíz por spoke
    4-projects/envs/{dev,qa,prod}/
    5-workloads/envs/{dev,qa,prod}/
  policies/                # Rego para Conftest + sus pruebas y planes de ejemplo
  tests/                   # Terratest (Go) y prueba de extremo a extremo
  scripts/                 # check.sh y utilidades del pipeline
  docs/{adr/, runbooks/, diagramas/, CONTRATO.md, pendientes-apply.md}
```

Cada raíz de `stages/` contiene: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`,
`providers.tf`, `backend.tf`, `remote_state.tf` (si lee etapas anteriores),
`terraform.tfvars.example`, `README.md` y `.terraform.lock.hcl`.

Las raíces de `envs/{dev,qa,prod}` de una misma etapa son idénticas salvo `backend.tf` (prefijo)
y `terraform.tfvars.example`. La lógica común va en los módulos, no copiada tres veces.

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
No usar funciones ni atributos que exijan Terraform posterior a 1.9 (por ejemplo, atributos
de solo escritura).

### 4.2 Nombres

`<empresa>-<entorno>-<dominio>-<recurso>`. `empresa` es `var.prefix` (ejemplo: `bnt`).
`entorno` es `bootstrap`, `common`, `dev`, `qa` o `prod`. Dominios:

| Dominio | Uso |
|---|---|
| `net` | VPC, subredes, routers, NAT, VPN, DNS, firewall |
| `sec` | KMS, secretos, VPC-SC |
| `app` | Cómputo: GKE, MIG, Cloud Run, balanceadores |
| `data` | Cloud SQL, Memorystore, Storage, Filestore |
| `ops` | Logs, monitoreo, alertas |
| `bkp` | Respaldo y DR |

Proyectos (deben coincidir con los diagramas entregados): `bnt-bootstrap-seed`,
`bnt-common-net-hub`, `bnt-common-logging`, `bnt-common-security`, `bnt-common-backup`,
`bnt-<env>-net-spoke`, `bnt-<env>-app`. Los IDs de proyecto son únicos a nivel mundial: toda
raíz que cree proyectos acepta `project_suffix` (string, por defecto `""`) que se agrega al final.

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
- Variables comunes y sus nombres exactos (los de la especificación): `org_id`,
  `billing_account`, `environment`, `primary_region`, `dr_region`, `subnet_cidrs`,
  `onprem_cidrs`, `gke_node_pools`, `sql_tier`, `labels`. Además: `prefix`, `project_suffix`,
  `state_bucket`.
- Toda salida lleva `description`. Ninguna salida es sensible; si lo fuera, el diseño está mal.
- Sin `count` para colecciones con identidad: usar `for_each` con llaves estables.

### 4.5 Cada módulo entrega

`README.md` con los marcadores `<!-- BEGIN_TF_DOCS -->` / `<!-- END_TF_DOCS -->` (lo llena
terraform-docs) y un párrafo que diga qué crea y qué exige la especificación; un ejemplo que
valida en `examples/basic/`; y al menos una prueba en `tests/` (§9.2).

---

## 5. Plan de direccionamiento

Propuesta del equipo (coincide con los diagramas entregados). `X` = 10 (dev), 20 (qa), 30 (prod).
Estos valores van en los `terraform.tfvars.example`, nunca dentro de los módulos.

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
| Sesiones BGP | 169.254.0.0/30, 169.254.0.4/30, 169.254.0.8/30, 169.254.0.12/30 |
| ASN | Hub 64514 (`hub_asn`); on-premises 65001 (`onprem_asn`) |
| DNS | Zonas privadas `<env>.empresa.internal.`; dominio on-premises `var.onprem_dns_domain` |

Validaciones obligatorias en las raíces de la etapa 3: ningún rango de `subnet_cidrs` ni del
hub se traslapa con `onprem_cidrs`, y los rangos de un spoke caben en su /16.

En dev y qa las llaves `*_dr` se reservan pero no se crean (`enable_dr = false`).

---

## 6. Estado remoto e identidad del pipeline

### 6.1 Bucket y prefijos

Un bucket en el proyecto semilla: versionado, acceso uniforme, sin acceso público, CMEK con
la llave de la etapa 0 (ADR 0008). El backend `gcs` bloquea el estado de forma nativa.

| Raíz | Prefijo | Cuenta de servicio | Lee además |
|---|---|---|---|
| `0-bootstrap` | `0-bootstrap` | un administrador, una sola vez | nada |
| `1-org` | `1-org` | `<prefix>-tf-1-org` | `0-bootstrap` |
| `2-security` | `2-security` | `<prefix>-tf-2-security` | `0-bootstrap`, `1-org` |
| `3-networks` (hub) | `3-networks/hub` | `<prefix>-tf-3-networks` | `0-bootstrap`, `1-org` |
| `3-networks/envs/<env>` | `3-networks/<env>` | `<prefix>-tf-3-networks` | `0-bootstrap`, `1-org`, `3-networks/hub` |
| `4-projects/envs/<env>` | `4-projects/<env>` | `<prefix>-tf-4-projects` | `1-org`, `2-security`, `3-networks/<env>` |
| `5-workloads/envs/<env>` | `5-workloads/<env>` | `<prefix>-tf-5-workloads` | `1-org`, `2-security`, `3-networks/<env>`, `4-projects/<env>` |

`backend.tf` de cada raíz fija solo el prefijo; el bucket llega por
`terraform init -backend-config="bucket=<bucket>"`. Las lecturas usan
`data "terraform_remote_state"` con `var.state_bucket` y se concentran en `remote_state.tf`,
que expone `locals` con los valores usados. Ninguna raíz lee un prefijo que no esté en su fila.

La etapa 0 arranca con estado local y lo migra al bucket con `terraform init -migrate-state`;
ese paso manual está permitido porque pertenece a la etapa 0 y se documenta en su runbook.

### 6.2 Permisos sobre el estado

Por cada cuenta de servicio: `roles/storage.objectAdmin` condicionado a los objetos de su
prefijo, y `roles/storage.objectViewer` condicionado a los prefijos de la columna "Lee además".
`# VERIFICAR-EN-APPLY`: que el listado de objetos que hace el backend funcione con la
condición; alternativa documentada: carpetas administradas de Cloud Storage con IAM propio.

### 6.3 Workload Identity Federation

La etapa 0 crea un pool y un proveedor OIDC de GitHub con
`attribute_condition` que exige `assertion.repository == var.github_repository`, y mapea
`repository`, `ref` y `environment`. Cada cuenta de servicio de etapa acepta
`roles/iam.workloadIdentityUser` solo desde ese repositorio. Sin llaves JSON en ningún lado
(además lo impide la política de organización).

---

## 7. Contrato de cada etapa

Las salidas listadas son la interfaz entre etapas: sus nombres y tipos no se cambian sin
actualizar este documento. Cada raíz puede tener más variables internas, todas con descripción.

### 7.0 `0-bootstrap`

Crea: carpeta `bootstrap`; proyecto semilla; llavero y llave KMS del estado (rotación 90 días);
bucket de estado; cuentas de servicio de las etapas 1 a 5 con sus roles de organización,
facturación y carpeta (mínimo privilegio, listados en el README de la etapa); pool y proveedor
de WIF; permisos de §6.2.

Entradas: `org_id`, `billing_account`, `prefix`, `project_suffix`, `primary_region`,
`github_repository`, `labels`.

| Salida | Tipo | Contenido |
|---|---|---|
| `seed_project_id` | string | proyecto semilla |
| `bootstrap_folder_id` | string | `folders/…` |
| `state_bucket` | string | nombre del bucket |
| `state_kms_key_id` | string | llave del estado |
| `stage_service_accounts` | map(string) | llaves `1-org` … `5-workloads` → correo |
| `workload_identity_provider` | string | nombre completo del proveedor, para GitHub Actions |

### 7.1 `1-org`

Crea: carpetas `common`, `dev`, `qa`, `prod`; proyectos de `common` (`net-hub`, `logging`,
`security`, `backup`); políticas de organización; IAM por grupos; sink agregado de la
organización hacia un bucket de logs con retención (bloqueo controlado por
`log_retention_locked`, irreversible una vez aplicado); registros de Data Access en la carpeta
`prod`; configuración de Security Command Center; presupuesto con alertas.

Políticas de organización (las nueve del diagrama 1): `compute.vmExternalIpAccess`,
`iam.disableServiceAccountKeyCreation`, `gcp.resourceLocations`, `compute.requireShieldedVm`,
`storage.publicAccessPrevention`, `storage.uniformBucketLevelAccess`,
`compute.skipDefaultNetworkCreation`, `iam.allowedPolicyMemberDomains`, `sql.restrictPublicIp`.

Grupos (variable `groups`, map con estas llaves → correo del grupo): `org_admins`,
`billing_admins`, `security_admins`, `network_admins`, `platform_devops`, `developers`,
`auditors`. Ningún rol se asigna a `user:`. Las personas solo tienen lectura; `developers`
solo en dev y qa.

Entradas: `org_id`, `billing_account`, `prefix`, `project_suffix`, `primary_region`,
`dr_region`, `directory_customer_id`, `groups`, `log_retention_days`, `log_retention_locked`,
`budget_amount`, `labels`, `state_bucket`.

| Salida | Tipo | Contenido |
|---|---|---|
| `folder_ids` | map(string) | llaves `common`, `dev`, `qa`, `prod` |
| `common_project_ids` | map(string) | llaves `net_hub`, `logging`, `security`, `backup` |
| `common_project_numbers` | map(string) | mismas llaves |
| `log_bucket` | string | bucket de logs de auditoría |

### 7.2 `2-security`

Crea, en el proyecto `security`: por cada entorno y ubicación (`primary_region`, `dr_region`
y la multirregión `us` para buckets de doble región) un llavero, y en él una llave por uso;
contenedores de secretos por entorno (sin valores, ADR 0015); política de acceso y perímetro
de VPC-SC `prod` con el proyecto `security` dentro, regla de entrada para las cuentas de
servicio del pipeline y modo dry-run por defecto (ADR 0009).

Usos de llave (llaves del mapa): `gke`, `compute`, `sql`, `storage`, `filestore`, `redis`,
`secrets`, `backup`. Rotación: 7 776 000 s (90 días), por variable.

Entradas: `org_id`, `prefix`, `primary_region`, `dr_region`, `environments`, `secret_names`
(map entorno → lista), `key_rotation_period`, `access_policy_id` (opcional: si la organización
ya tiene política), `vpc_sc_enforced`, `vpc_sc_restricted_services`, `labels`, `state_bucket`.

| Salida | Tipo | Contenido |
|---|---|---|
| `kms_key_ids` | map(map(map(string))) | `[entorno][ubicación][uso]` → ID de llave |
| `secret_ids` | map(map(string)) | `[entorno][nombre]` → ID del secreto |
| `access_policy_id` | string | política de Access Context Manager |
| `perimeter_name` | string | nombre completo del perímetro de prod |
| `vpc_sc_enforced` | bool | para que la etapa 4 use el recurso correcto |

### 7.3 `3-networks` (hub)

Crea, en `net-hub`: VPC hub y sus dos subredes; Cloud Router por región; HA VPN con dos
túneles y BGP hacia on-premises (SLA 99.99 %); anuncios BGP personalizados con el /16 del
hub, los /16 de los spokes y 35.199.192.0/19 (reenvío de Cloud DNS); política de firewall
jerárquica en la organización (denegar por defecto; permitir verificaciones de salud e IAP);
DNS: zona de reenvío hacia on-premises y política de servidor entrante; con
`simulate_onprem = true`, la VPC `onprem-sim` con su gateway y router (ADR 0006);
Interconnect solo si `enable_interconnect = true`.

Entradas: `org_id`, `prefix`, `primary_region`, `dr_region`, `hub_cidrs`, `spoke_supernets`
(map entorno → /16), `onprem_cidrs`, `hub_asn`, `onprem_asn`, `simulate_onprem`,
`onprem_vpn_gateway_ips`, `onprem_dns_domain`, `onprem_dns_servers`, `enable_interconnect`,
`labels`, `state_bucket`.

El secreto compartido de la VPN nunca va en variables: con on-premises real se lee de Secret
Manager; en modo simulado se genera y solo existe en el estado cifrado (documentarlo en el ADR 0006).

| Salida | Tipo | Contenido |
|---|---|---|
| `hub_project_id` | string | |
| `hub_network_name` | string | |
| `hub_network_self_link` | string | para peering y zonas de peering DNS |
| `firewall_policy_id` | string | política jerárquica |

### 7.4 `3-networks/envs/<env>` (spoke)

Crea: proyecto `net-spoke` como host de Shared VPC; VPC; subredes de §5 con Private Google
Access y flow logs al 50 %; subredes proxy-only; rango y conexión de Private Service Access;
peering con el hub en ambos sentidos (el hub exporta rutas personalizadas, el spoke las
importa); Cloud NAT por región (ADR 0004); zona privada `<env>.empresa.internal.`; zona de
peering DNS hacia el hub para el dominio on-premises; zona privada de `googleapis.com` hacia
el VIP restringido (199.36.153.4/30) y su ruta; reglas de firewall de la VPC con etiquetas
seguras (solo rangos del balanceador 35.191.0.0/16 y 130.211.0.0/22, e IAP 35.235.240.0/20).

Entradas: `org_id`, `billing_account`, `prefix`, `project_suffix`, `environment`,
`primary_region`, `dr_region`, `enable_dr`, `subnet_cidrs`, `onprem_cidrs`,
`onprem_dns_domain`, `flow_log_sampling` (por defecto 0.5), `labels`, `state_bucket`.

| Salida | Tipo | Contenido |
|---|---|---|
| `host_project_id` | string | |
| `network_name` | string | |
| `network_self_link` | string | |
| `subnets` | map(object) | llave de §5 → `{ self_link, name, region, cidr, secondary_ranges }` (`secondary_ranges`: map nombre → CIDR, llaves `pods` y `services`) |
| `psa_range_name` | string | |
| `secure_tags` | map(string) | llaves `lb_backend`, `iap_ssh` → ID del valor de etiqueta |

### 7.5 `4-projects/envs/<env>`

Crea: un proyecto de servicio por aplicación (`applications`, por defecto una llamada `app`)
unido al host; permisos de uso de subred para los agentes de servicio; cuentas de servicio de
ejecución; permisos de las llaves KMS a los agentes de servicio; permisos de lectura de
secretos; en prod, alta del proyecto en el perímetro (recurso normal o de dry-run según
`vpc_sc_enforced` de la etapa 2).

Entradas: `org_id`, `billing_account`, `prefix`, `project_suffix`, `environment`,
`primary_region`, `dr_region`, `applications` (map nombre → `{ apis, secrets }`), `labels`,
`state_bucket`.

| Salida | Tipo | Contenido |
|---|---|---|
| `service_project_ids` | map(string) | aplicación → ID de proyecto |
| `service_project_numbers` | map(string) | |
| `service_accounts` | map(map(string)) | `[aplicación][uso]` → correo; usos `gke_nodes`, `workload`, `mig`, `run` |

### 7.6 `5-workloads/envs/<env>`

Crea, en el proyecto de servicio y con interruptores por carga (`enable_gke`, `enable_mig`,
`enable_cloud_run`, `enable_filestore`, `enable_memorystore`): GKE, MIG, Cloud Run, Cloud SQL,
Memorystore, Cloud Storage, Filestore, balanceador HTTPS global con Cloud Armor y certificado
administrado, balanceador interno, observabilidad y respaldo. En prod con `enable_dr = true`:
réplica de Cloud SQL en la región de DR, bucket de doble región con turbo replication, plan de
Backup for GKE. Con `dr_active = true` (conmutación): cómputo en la región de DR y backends del
balanceador hacia ella.

Entradas: `prefix`, `environment`, `primary_region`, `dr_region`, `enable_dr`, `dr_active`,
`application`, los interruptores, `gke_node_pools`, `sql_tier`, `sql_database_version`,
`domain_names` (certificado), `notification_emails`, `labels`, `state_bucket`.

| Salida | Tipo | Contenido |
|---|---|---|
| `lb_ip_address` | string | IP del balanceador externo |
| `gke_cluster_names` | map(string) | región → nombre |
| `sql_instance_connection_name` | string | |
| `bucket_names` | map(string) | |

---

## 8. Catálogo de módulos

Todos reciben `labels` (§4.3) si crean recursos etiquetables, y `prefix` y `environment` para
armar nombres (§4.2). "Exige" resume la configuración mínima de la especificación (sección
"Componentes del datacenter"): debe quedar como valor fijo o como validación, no como opción
que se pueda apagar en prod.

| Módulo | Crea | Exige | Entradas principales | Salidas principales |
|---|---|---|---|---|
| `org` | Políticas de organización, sink agregado | Las nueve políticas de §7.1 | `org_id`, `allowed_regions`, `directory_customer_id`, `log_sink_destination` | `policy_names`, `sink_writer_identity` |
| `folders` | Carpetas | Una por entorno | `parent`, `names` | `ids` (map) |
| `project-factory` | Proyecto, APIs, facturación, alta como host o servicio de Shared VPC | Sin red default; etiquetas | `name`, `folder_id`, `billing_account`, `apis`, `shared_vpc_host`, `shared_vpc_host_project` | `project_id`, `project_number` |
| `iam` | Asignaciones aditivas de roles a grupos y cuentas de servicio | Rechaza miembros `user:` por validación | `bindings` (lista de `{ scope, resource, role, member }`) | `members` |
| `network-hub` | VPC hub, subredes, routers | Subredes privadas, PGA, flow logs 0.5 | `project_id`, `subnets`, `router_asn` | `network_self_link`, `network_name`, `routers` (map región → nombre) |
| `network-spoke` | VPC spoke, subredes y rangos secundarios, proxy-only, PSA, peering, NAT | PGA; flow logs 0.5; NAT por región; sin IP públicas | `project_id`, `subnet_cidrs`, `regions`, `hub_network_self_link`, `enable_dr` | las de §7.4 |
| `firewall` | Política jerárquica o política de red con reglas y etiquetas seguras | Denegar todo por defecto; reglas por etiqueta segura | `parent` (organización o red), `rules`, `secure_tags` | `policy_id`, `secure_tag_ids` |
| `cloud-armor` | Política de seguridad | Reglas OWASP preconfiguradas (SQLi, XSS como mínimo) y límite de tasa | `project_id`, `owasp_rules`, `rate_limit` | `policy_self_link` |
| `load-balancer` | Balanceador HTTPS global externo, o interno regional (`type`) | HTTPS con certificado administrado; redirección de HTTP; política de Cloud Armor obligatoria en el externo | `project_id`, `type`, `backends`, `domain_names`, `security_policy`, `network`, `subnet` | `ip_address`, `backend_service_ids` |
| `dns` | Zonas privadas, de reenvío y de peering; política de servidor entrante | Zonas privadas por entorno; reenvío condicional a on-premises | `project_id`, `zones` (map con `type`: `private`, `forwarding`, `peering`), `networks` | `zone_names`, `inbound_forwarder_ips` |
| `hybrid-connectivity` | HA VPN, túneles, sesiones BGP; opcional Interconnect | 2 túneles y BGP; Interconnect opcional | `project_id`, `network`, `router`, `peer` (gateway externo o de otra VPC), `advertised_ranges`, `bgp_sessions` | `gateway_self_link`, `tunnel_names` |
| `compute-mig` | Plantilla, MIG regional, autoescalador, verificación de salud | Shielded VM; imagen por variable (endurecida); autoescalado y autocuración; sin IP pública | `project_id`, `subnet`, `image`, `machine_type`, `min_replicas`, `max_replicas`, `service_account`, `kms_key` | `instance_group`, `health_check_id` |
| `gke` | Clúster y pools de nodos | Nodos privados; Workload Identity; Binary Authorization; regional si `environment = "prod"` (validación) | `project_id`, `network`, `subnet`, `pods_range`, `services_range`, `master_cidr`, `gke_node_pools`, `node_service_account`, `kms_key` | `cluster_name`, `cluster_id`, `workload_pool` |
| `cloud-run` | Servicio v2 con salida directa a la VPC | Solo tráfico interno y del balanceador; cuenta de servicio propia | `project_id`, `region`, `image`, `subnet`, `service_account`, `kms_key` | `service_name`, `service_uri` |
| `storage` | Bucket | CMEK; versionado; reglas de ciclo de vida; acceso uniforme; sin acceso público | `project_id`, `location`, `kms_key`, `lifecycle_rules`, `dual_region` (objeto opcional con turbo replication) | `bucket_name` |
| `filestore` | Instancia | CMEK; red por PSA | `project_id`, `location`, `tier`, `capacity_gb`, `network`, `kms_key` | `instance_name`, `ip_address` |
| `cloud-sql` | Instancia, bases, usuarios IAM, réplica | IP privada únicamente; HA regional si prod (validación); PITR; réplica en DR si `enable_dr`; SSL obligatorio; CMEK; autenticación IAM | `project_id`, `region`, `dr_region`, `enable_dr`, `sql_tier`, `database_version`, `network`, `kms_key`, `dr_kms_key`, `iam_users` | `instance_name`, `connection_name`, `private_ip`, `replica_name` |
| `memorystore` | Instancia de Redis | IP privada; CMEK; HA si prod | `project_id`, `region`, `tier`, `memory_gb`, `network`, `kms_key` | `host`, `port` |
| `kms` | Llavero y llaves | Rotación de 90 días; `prevent_destroy` en las llaves | `project_id`, `location`, `keys` (map uso → opciones), `rotation_period` | `key_ids` (map), `keyring_id` |
| `secrets` | Contenedores de secretos e IAM | Nunca recibe valores; CMEK | `project_id`, `names`, `kms_keys`, `accessors` | `secret_ids` (map) |
| `vpc-sc` | Política de acceso (opcional), perímetro, reglas de entrada y salida | Perímetro para proyectos de prod con datos | `org_id`, `access_policy_id`, `perimeter_name`, `resources`, `restricted_services`, `ingress_identities`, `enforced` | `perimeter_name`, `access_policy_id` |
| `observability` | Canales de notificación, verificaciones de disponibilidad, alertas, tableros, SLO | Alertas y tableros base; SLO 99.9 % | `project_id`, `notification_emails`, `uptime_checks`, `slo_target` | `notification_channel_ids`, `dashboard_ids` |
| `log-export` | Bucket de logs y sink | Retención bloqueada (por variable) | `project_id`, `parent` (organización, carpeta o proyecto), `filter`, `retention_days`, `retention_locked`, `kms_key` | `bucket_name`, `writer_identity` |
| `backup-dr` | Bóveda y plan de Backup and DR; plan de Backup for GKE | Política diaria; retención de 30 días; región secundaria | `project_id`, `region`, `dr_region`, `retention_days`, `gke_cluster_id` (opcional) | `vault_id`, `plan_ids` |

Sin módulo propio, a propósito: Persistent Disk (lo crean `compute-mig` y `gke`), Cloud
Interconnect (interruptor dentro de `hybrid-connectivity`), Cloud IDS y Private Service
Connect (aparecen en la especificación como servicios, no como configuración mínima exigida;
no se construyen y se anota en `docs/pendientes-apply.md` como alcance no cubierto), y el
apagado de dev fuera de horario (mitigación de costo opcional, no construida).

Si un recurso no existe en el proveedor 6.x con el nombre que esperas, no lo inventes:
consulta el registro, y si la función no existe en 6.x, repórtalo.

---

## 9. Políticas, pruebas y pipeline

### 9.1 Políticas (Conftest, `policies/`)

Se evalúan sobre el plan en JSON (`terraform show -json`). Mínimas:

1. Bucket sin `public_access_prevention = "enforced"` o con miembros `allUsers` /
   `allAuthenticatedUsers`: rechazado.
2. Instancia o plantilla sin Shielded VM: rechazada.
3. Recurso etiquetable sin las cinco etiquetas o con `managed_by` distinto de `terraform`: rechazado.
4. Instancia con IP pública (`access_config`): rechazada.
5. Cloud SQL con IP pública: rechazado.
6. Llave KMS sin rotación o con rotación mayor a 90 días: rechazada.
7. Asignación de IAM a `user:`: rechazada.

Cada regla tiene pruebas en Rego (`conftest verify`) y dos planes de ejemplo en
`policies/fixtures/` (uno que pasa y uno que viola). Así el criterio "el pipeline bloquea un PR
que viola una política" se demuestra sin GCP.

### 9.2 Pruebas

| Nivel | Dónde | Sin GCP |
|---|---|---|
| Estático | `scripts/check.sh`: fmt, validate, tflint, checkov sobre módulos, ejemplos y raíces | Sí |
| Políticas | `conftest verify` y `conftest test` sobre los planes de ejemplo | Sí |
| Unitario | `modules/<m>/tests/*.tftest.hcl` con `mock_provider` y `command = plan` | Sí |
| Integración | `tests/` con Terratest, un proyecto efímero por módulo | Solo se escribe y compila |
| Extremo a extremo | `tests/e2e/`: aplica 0 → 5, segundo plan sin cambios, conectividad, destroy de dev | Solo se escribe |

Cada prueba unitaria comprueba al menos: que las validaciones rechazan una entrada mala
(`expect_failures`), que los nombres siguen §4.2 y que la configuración "Exige" del módulo
está en el plan.

### 9.3 Flujos de GitHub Actions

| Flujo | Disparo | Qué hace |
|---|---|---|
| `pr.yml` | Pull request | fmt, validate, tflint, checkov, `terraform test`, `conftest verify`; si la variable de repositorio `GCP_ENABLED` es `true`: plan por raíz afectada, Conftest sobre el plan, comentario con el resumen y el costo (Infracost) |
| `apply.yml` | Merge a `main` | Aplica etapas 1 → 5: dev automático; qa tras dev; prod en un entorno protegido con dos revisores |
| `drift.yml` | Diario | `plan -detailed-exitcode` por raíz; si hay cambios, abre una incidencia |
| `terratest.yml` | Nocturno y antes de cada versión | Terratest |

Los trabajos que tocan GCP se autentican con WIF y la cuenta de servicio de la etapa; nunca
con llaves. Mientras `GCP_ENABLED` no sea `true`, esos trabajos se omiten y los demás deben pasar.
`CODEOWNERS` por etapa: red (`3-networks`, módulos de red), seguridad (`1-org`, `2-security`,
`policies/`), plataforma (el resto).

Versionado de módulos: etiquetas Git `modules/<modulo>/vX.Y.Z`.

---

## 10. Documentación entregable

- `gcp-datacenter/README.md`: requisitos previos, orden de despliegue y comandos por etapa.
- `docs/adr/`: los 17 de §2.
- `docs/runbooks/`: arranque de la etapa 0; alta de un nuevo proyecto de aplicación; rotación
  de llaves; conmutación a DR; respuesta a drift.
- `docs/diagramas/`: los cuatro diagramas, corregidos donde este contrato cambió el diseño
  (Cloud Storage se alcanza por Private Google Access, no por Private Service Access).
- `docs/pendientes-apply.md` (§12).

---

## 11. Paquetes de trabajo

Cada paquete es una rama y un PR. "Nivel" indica la dificultad: A = riesgo de diseño alto,
B = directo.

| # | Paquete | Nivel | Depende de |
|---|---|---|---|
| 0 | Andamiaje: carpetas, `scripts/check.sh`, `.tflint.hcl`, configuración de checkov y terraform-docs, `pr.yml` sin GCP | B | nada |
| 1 | Módulos `folders`, `project-factory`, `iam`, `org`, `log-export` | A | 0 |
| 2 | Módulos `kms`, `secrets`, `vpc-sc` | A | 0 |
| 3 | Módulos `network-hub`, `network-spoke`, `firewall`, `dns`, `hybrid-connectivity` | A | 0 |
| 4 | Módulos `gke`, `compute-mig`, `cloud-run` | A | 0 |
| 5 | Módulos `cloud-sql`, `memorystore`, `storage`, `filestore` | B | 0 |
| 6 | Módulos `load-balancer`, `cloud-armor`, `observability`, `backup-dr` | B | 0 |
| 7 | Etapas `0-bootstrap`, `1-org`, `2-security` | A | 1, 2 |
| 8 | Etapa `3-networks` (hub y spokes) | A | 3, 7 |
| 9 | Etapas `4-projects` y `5-workloads` | A | 4, 5, 6, 8 |
| 10 | Políticas de Conftest con pruebas y planes de ejemplo | B | 0 |
| 11 | Flujos `apply.yml`, `drift.yml`, `terratest.yml`, `CODEOWNERS` | B | 7 |
| 12 | ADR, runbooks, README raíz, diagramas corregidos | B | 7, 8, 9 |
| 13 | Terratest y prueba de extremo a extremo (escritas, sin ejecutar) | B | 9 |
| 14 | Auditoría final entre etapas: cada salida leída existe aguas arriba con el tipo esperado | A | todo |

Los paquetes 1 a 6 y el 10 son independientes entre sí y se construyen en paralelo.

---

## 12. Pendientes del primer apply

Lista inicial de `docs/pendientes-apply.md`. Cada entrada: qué verificar, dónde está en el
código y qué hacer si falla.

1. Listado de objetos del backend `gcs` con IAM condicionado por prefijo (§6.2).
2. Activación de Security Command Center por Terraform: si la organización exige activarlo en
   consola, pasa al runbook de la etapa 0 como paso manual permitido.
3. `gcp.resourceLocations` frente al bucket de doble región y los recursos globales.
4. Uso de llaves CMEK del proyecto `security` desde los proyectos de prod con el perímetro en
   modo forzado.
5. Regla de entrada del perímetro para las cuentas de servicio del pipeline.
6. Propagación de rutas: las aprendidas por BGP en el hub llegan a los spokes por el peering,
   y on-premises alcanza los /16 de los spokes.
7. Reenvío de DNS: on-premises recibe el anuncio de 35.199.192.0/19 y responde.
8. Rango del plano de control de GKE: si el clúster usa Private Service Connect, `gke_master`
   queda reservado sin uso.
9. Cuotas de la cuenta (CPU, IP, clústeres) frente a prod completo.
10. Tiempo total del despliegue 0 → 5 frente al objetivo de 90 minutos.
11. Segundo `plan` sin cambios en todas las raíces, y `destroy` de dev sin huérfanos.
12. Reglas de protección de rama y revisores obligatorios del entorno `prod` en un
    repositorio privado, según el plan de GitHub del equipo.
