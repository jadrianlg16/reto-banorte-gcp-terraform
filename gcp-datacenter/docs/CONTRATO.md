# Contrato de construcción: Datacenter en GCP con Terraform

Fuente única para quien construya o revise este repositorio (personas o agentes). Si algo de
aquí contradice la especificación de Banorte, gana la especificación, salvo las desviaciones
listadas en §2, que quedan registradas como ADR.

Estado al 21 nov 2026 (actualizado después de la ronda de correcciones de la revisión
independiente): todo se construye y se prueba **sin acceso a GCP**. Nada se ha aplicado.
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
| 0001 | Proveedores `hashicorp/google` y `google-beta` en `~> 6.0`; `required_version = ">= 1.9"` | Convención obligatoria de la especificación. La versión vigente del registry es mayor; se actualiza por PR cuando el cliente lo pida. Las pruebas exigen 1.11 (ADR 0021) | Conforme |
| 0002 | Regiones `us-central1` (primaria) y `us-east4` (DR), ambas como variables | Propuesta de la especificación; `northamerica-south1` si hubiera residencia de datos | Conforme |
| 0003 | Una VPC por entorno (spoke, host de Shared VPC) unida al hub por VPC Network Peering; sin peering entre spokes | La especificación se contradice: su diagrama dibuja una sola Shared VPC en el hub y su jerarquía pide un proyecto de red spoke por entorno. Se sigue la jerarquía: el aislamiento entre entornos lo da la red y no solo el firewall | Desviación del diagrama |
| 0004 | Cloud NAT en cada spoke y región, no en el hub | Un Cloud NAT no da salida a redes unidas por peering | Desviación del diagrama |
| 0005 | Balanceador HTTPS global y Cloud Armor en el proyecto de servicio de cada entorno | El balanceador global podría referenciar backends de otro proyecto, pero ponerlo en el hub crearía una dependencia inversa (la etapa 3 leería la 5), separaría al dueño de la aplicación de su política de Cloud Armor (que se asocia al servicio de backend) y mezclaría entornos en un proyecto común. El tráfico on-premises sí entra solo por el hub | Desviación del diagrama |
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
| 0018 | La etapa 1 crea, en el proyecto `logging`, la llave KMS del bucket de logs de auditoría | El bucket de logs exige CMEK y la etapa 2 (KMS) corre después; mismo criterio que el ADR 0008 | Aclaración |
| 0019 | `cloudkms.googleapis.com` y `secretmanager.googleapis.com` no entran en los servicios restringidos del perímetro por defecto | El proyecto `security` está dentro del perímetro de prod y también guarda llaves y secretos de dev y qa; restringirlos bloquearía a esos entornos al forzar el perímetro. Se restringen cuando dev y qa tengan su propio proyecto de llaves | Aclaración |
| 0020 | Cloud Run detrás del balanceador: entrada fija a "interno y balanceador" y verificación de invocador de IAM desactivada solo con `public_via_load_balancer = true`; nunca `allUsers` | `iam.allowedPolicyMemberDomains` impide `allUsers`; el control de acceso público queda en el balanceador y Cloud Armor | Aclaración |
| 0021 | El código sigue en `>= 1.9`; las pruebas (`*.tftest.hcl`) usan `override_during = plan` y exigen Terraform 1.11 o mayor. `pr.yml` comprueba el código con 1.9.8 sin `terraform test` y todo con 1.16.5 | Las pruebas necesitan valores conocidos en el plan para afirmar sobre atributos calculados; subir el mínimo del código contradiría la convención | Aclaración |
| 0022 | Bucket de estado y su llave en la multirregión `US`/`us` (o doble región), segunda HA VPN en la región de DR, balanceador interno uno por región con acceso global y GKE fuera del balanceador externo mientras no haya NEG de DR | La conmutación a DR corre Terraform con la región primaria caída: nada de lo que necesita puede vivir solo ahí | Aclaración |
| 0023 | WIF por IDs numéricos del repositorio y del dueño; política de denegación de IAM en la carpeta `bootstrap`; roles personalizados sin acceso a valores de secretos; los roles de la etapa 5 sobre cada proyecto de servicio, no en las carpetas | La revisión independiente encontró caminos para que una cuenta de etapa ampliara su acceso | Aclaración |
| 0024 | Un repositorio de Artifact Registry multirregional por aplicación y una política de Binary Authorization por proyecto de servicio que solo admite ese repositorio | GKE y Cloud Run ya exigían Binary Authorization sin política propia ni registro; la imagen debe sobrevivir a la región primaria | Aclaración |
| 0025 | Plan, aprobación y apply separados: plan sin entorno, apply en el entorno de GitHub con la misma huella del plan; `common` protegido como `prod`; `plan-gate` y prueba de humo de dev | La aprobación debe ver el plan que se aplica | Aclaración |
| 0026 | `googleapis.com`, `gcr.io`, `pkg.dev` y `run.app` resuelven al VIP de `google_apis_vip` (`restricted` por defecto en los tres entornos) | Imágenes y Cloud Run salían por IP públicas sin pasar por el VIP | Aclaración |

Los ADR 0001, 0002, 0005 a 0008, 0010, 0012, 0013, 0015 y 0018 se enmendaron el 21 nov 2026
(ver la línea de estado de cada uno).

Pendiente de decidir por el equipo (no bloquea la construcción): usuarios de GitHub para
`CODEOWNERS` (se usan marcadores `@PENDIENTE-red`, `@PENDIENTE-seguridad`,
`@PENDIENTE-plataforma`). `.github/`, `stages/0-bootstrap/` y `scripts/` son solo de
seguridad: deciden quién puede aplicar y qué se revisa.

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
No usar en el código (`*.tf`) funciones ni atributos que exijan Terraform posterior a 1.9 (por
ejemplo, atributos de solo escritura). Las pruebas (`*.tftest.hcl`) sí usan
`override_during = plan`, que exige Terraform 1.11 o mayor (ADR 0021): con 1.9 solo corre
`bash scripts/check.sh --skip test`.

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
| Sesiones BGP | VPN primaria 169.254.0.0/30 y 169.254.0.4/30 (`vpn_bgp_ranges`); VPN de DR 169.254.0.8/30 y 169.254.0.12/30 (`vpn_dr_bgp_ranges`, con `enable_vpn_dr`) |
| ASN | Hub 64514 (`hub_asn`); on-premises 65001 (`onprem_asn`) |
| DNS | Zonas privadas `<env>.empresa.internal.`; dominio on-premises `var.onprem_dns_domain` |

Validaciones obligatorias en las raíces de la etapa 3: ningún rango de `subnet_cidrs` ni del
hub se traslapa con `onprem_cidrs`, y los rangos de un spoke caben en su /16.

En dev y qa las llaves `*_dr` se reservan pero no se crean (`enable_dr = false`).

---

## 6. Estado remoto e identidad del pipeline

### 6.1 Bucket y prefijos

Un bucket en el proyecto semilla: versionado, acceso uniforme, sin acceso público, CMEK con
la llave de la etapa 0 (ADR 0008). El backend `gcs` bloquea el estado de forma nativa. El
bucket y su llave están en `state_bucket_location` (multirregión `US` y llavero `us` por
defecto) o en una doble región (`state_bucket_dual_regions`), no en `primary_region`: la
conmutación a DR necesita el estado con la región primaria caída (ADR 0022).

| Raíz | Prefijo | Cuenta de servicio | Lee además |
|---|---|---|---|
| `0-bootstrap` | `0-bootstrap` | un administrador, una sola vez | nada |
| `1-org` | `1-org` | `<prefix>-tf-1-org` | `0-bootstrap` |
| `2-security` | `2-security` | `<prefix>-tf-2-security` | `0-bootstrap`, `1-org` |
| `3-networks` (hub) | `3-networks/hub` | `<prefix>-tf-3-networks` | `1-org` |
| `3-networks/envs/<env>` | `3-networks/<env>` | `<prefix>-tf-3-networks` | `1-org`, `3-networks/hub` |
| `4-projects/envs/<env>` | `4-projects/<env>` | `<prefix>-tf-4-projects` | `1-org`, `2-security`, `3-networks/<env>` |
| `5-workloads/envs/<env>` | `5-workloads/<env>` | `<prefix>-tf-5-workloads` | `2-security`, `3-networks/<env>`, `4-projects/<env>` |

Las lecturas son las mínimas que usan las raíces (`reads` en
`stages/0-bootstrap/service_accounts.tf`): `3-networks` no lee `0-bootstrap` y `5-workloads` no
lee `1-org`. Los spokes leen `3-networks/hub` porque la misma cuenta lo escribe.

`backend.tf` de cada raíz fija solo el prefijo; el bucket llega por
`terraform init -backend-config="bucket=<bucket>"`. Las lecturas usan
`data "terraform_remote_state"` con `var.state_bucket` y se concentran en `remote_state.tf`,
que expone `locals` con los valores usados. Ninguna raíz lee un prefijo que no esté en su fila.

La etapa 0 arranca con estado local y lo migra al bucket con `terraform init -migrate-state`;
ese paso manual está permitido porque pertenece a la etapa 0 y se documenta en su runbook.

### 6.2 Permisos sobre el estado

Por cada cuenta de servicio: `roles/storage.objectAdmin` condicionado a los objetos de su
prefijo, y `roles/storage.objectViewer` condicionado a los prefijos de la columna "Lee además".
`storage.objects.list` se evalúa sobre el bucket, así que una condición solo por nombre de
objeto impediría listar: cada condición agrega
`resource.type == "storage.googleapis.com/Bucket" ||` para permitir el listado. Consecuencia
aceptada: toda cuenta de etapa ve los nombres de los objetos del bucket, no su contenido.
`# VERIFICAR-EN-APPLY`: que el backend funcione con la condición; alternativa documentada:
carpetas administradas de Cloud Storage con IAM propio.

### 6.3 Workload Identity Federation

La etapa 0 crea un pool y un proveedor OIDC de GitHub con `attribute_condition` que exige
`assertion.repository_id == var.github_repository_id` y
`assertion.repository_owner_id == var.github_repository_owner_id` (IDs numéricos, que no se
reutilizan como un nombre; ADR 0023), y mapea `repository_id`, `repository_owner_id`,
`repository`, `ref` y `environment`. Cada cuenta de servicio de etapa acepta
`roles/iam.workloadIdentityUser` solo del
`principalSet://iam.googleapis.com/<pool>/attribute.repository_id/<id>`. `github_repository`
queda como dato legible. Sin llaves JSON en ningún lado (además lo impide la política de
organización). Limitación conocida: no se filtra por rama ni por entorno
([`pipeline.md`](pipeline.md) §5).

La etapa 0 adjunta además a la carpeta `bootstrap` una política de denegación de IAM
(`google_iam_deny_policy.bootstrap_folder`) que impide a la cuenta de `1-org` cambiar el IAM de
la carpeta, del proyecto semilla, de las cuentas de etapa y del bucket de estado, o tomar la
identidad de esas cuentas (ADR 0023). Quien aplica la etapa 0 necesita `roles/iam.denyAdmin`
en la organización.

---

## 7. Contrato de cada etapa

Las salidas listadas son la interfaz entre etapas: sus nombres y tipos no se cambian sin
actualizar este documento. Cada raíz puede tener más variables internas, todas con descripción.

### 7.0 `0-bootstrap`

Crea: carpeta `bootstrap`; proyecto semilla; llavero (`<prefix>-bootstrap-sec-keyring-us` por
defecto) y llave KMS del estado (rotación 90 días); bucket de estado en
`state_bucket_location`; cuentas de servicio de las etapas 1 a 5 con sus roles de organización,
facturación y proyecto semilla, más su acceso condicionado al bucket de estado y su
suplantación por WIF (mínimo privilegio, listados en el README de la etapa; los roles de
carpeta y de proyecto de `common` los da la etapa 1); roles
personalizados de organización `<prefix>TfKmsSecretIamGranter` (IAM de llaves y secretos, para
la etapa 4) y `<prefix>TfSecretContainerAdmin` (contenedores de secretos sin acceso a valores,
para la etapa 2); política de denegación de la carpeta `bootstrap` (§6.3); pool y proveedor de
WIF; permisos de §6.2.

Entradas: `org_id`, `billing_account`, `prefix`, `project_suffix`, `primary_region`,
`location_short_codes`, `state_bucket_location`, `state_bucket_dual_regions`,
`github_repository` (informativa), `github_repository_id`, `github_repository_owner_id`,
`state_versions_to_keep`, `labels`.

| Salida | Tipo | Contenido |
|---|---|---|
| `seed_project_id` | string | proyecto semilla |
| `seed_project_number` | string | número del proyecto semilla |
| `bootstrap_folder_id` | string | `folders/…` |
| `state_bucket` | string | nombre del bucket |
| `state_kms_key_id` | string | llave del estado |
| `stage_service_accounts` | map(string) | llaves `1-org` … `5-workloads` → correo |
| `workload_identity_provider` | string | nombre completo del proveedor, para GitHub Actions |
| `workload_identity_pool` | string | nombre del pool |
| `kms_secret_iam_role_id` | string | rol personalizado que 1-org asigna a la etapa 4 en `security` |
| `secret_container_admin_role_id` | string | rol personalizado que 1-org asigna a la etapa 2 en `security` |
| `state_iam_conditions` | map(object) | etapa → `{ writes, reads }`: prefijos de estado que escribe y lee cada cuenta, para revisión |

### 7.1 `1-org`

Crea: carpetas `common`, `dev`, `qa`, `prod`; proyectos de `common` (`net-hub`, `logging`,
`security`, `backup`); políticas de organización; IAM por grupos; sink agregado de la
organización hacia un bucket de logs con retención (bloqueo controlado por
`log_retention_locked`, irreversible una vez aplicado); registros de Data Access en la carpeta
`prod`; configuración de Security Command Center (notificación hacia un tema de Pub/Sub con
CMEK regional, almacenamiento limitado a `primary_region` y `enforce_in_transit`, ADR 0018);
presupuesto con alertas; IAM de las cuentas de etapa sobre los proyectos de `common` y las
carpetas de entorno (en `security`: a 2-security `cloudkms.admin`, el rol personalizado
`secret_container_admin` y `serviceusage.serviceUsageAdmin`, sin `projectIamAdmin`; a 4-projects
el rol personalizado `kms_secret_iam_role_id`; a 5-workloads nada, sus roles los da la etapa 4
sobre cada proyecto de servicio).

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
`budget_amount`, `labels`, `state_bucket` (más `additional_allowed_locations`,
`location_short_codes`, `budget_alert_thresholds` y `scc_notification_filter`, con valor por
defecto).

| Salida | Tipo | Contenido |
|---|---|---|
| `folder_ids` | map(string) | llaves `common`, `dev`, `qa`, `prod` |
| `common_project_ids` | map(string) | llaves `net_hub`, `logging`, `security`, `backup` |
| `common_project_numbers` | map(string) | mismas llaves |
| `log_bucket` | string | bucket de logs de auditoría |

Salidas adicionales (no son interfaz de otra etapa): `log_sink_writer_identity`,
`org_policy_names`, `logging_kms_key_ids`, `scc_findings_topic`, `budget_name`.

### 7.2 `2-security`

Crea, en el proyecto `security`: por cada entorno y ubicación (`primary_region`, `dr_region`
y la multirregión `us` para buckets de doble región) un llavero, y en él una llave por uso;
contenedores de secretos por entorno (sin valores, ADR 0015); política de acceso y perímetro
de VPC-SC `prod` con el proyecto `security` dentro, regla de entrada para las cuentas de
servicio del pipeline (recurso de regla aparte; el perímetro ignora sus `ingress_policies`
para no quitar las que agrega la etapa 4) y modo dry-run por defecto (ADR 0009).

Usos de llave (llaves del mapa): `gke`, `compute`, `sql`, `storage`, `filestore`, `redis`,
`secrets`, `backup`, `run`, `artifacts`. En la multirregión `us` solo se crean `storage`,
`backup` y `artifacts` (esta última para los repositorios multirregionales de Artifact
Registry, ADR 0024). Rotación: 7 776 000 s (90 días), por variable. Los contenedores de
secretos los administra la cuenta de la etapa con un rol personalizado sin permisos de versiones
(ADR 0015 y 0023). `vpc_sc_restricted_services` incluye `artifactregistry.googleapis.com` por
defecto.

Entradas: `org_id`, `prefix`, `primary_region`, `dr_region`, `environments`, `secret_names`
(map entorno → lista), `key_rotation_period`, `access_policy_id` (opcional: si la organización
ya tiene política), `vpc_sc_enforced`, `vpc_sc_restricted_services`, `labels`, `state_bucket`
(más `location_short_codes`, ubicación → código corto de los nombres de llaveros, con valor por
defecto).

| Salida | Tipo | Contenido |
|---|---|---|
| `kms_key_ids` | map(map(map(string))) | `[entorno][ubicación][uso]` → ID de llave |
| `keyring_ids` | map(map(string)) | `[entorno][ubicación]` → ID del llavero |
| `secret_ids` | map(map(string)) | `[entorno][nombre]` → ID del secreto |
| `access_policy_id` | string | política de Access Context Manager |
| `perimeter_name` | string | nombre completo del perímetro de prod |
| `vpc_sc_enforced` | bool | para que la etapa 4 use el recurso correcto |

### 7.3 `3-networks` (hub)

Crea, en `net-hub`: VPC hub y sus dos subredes; Cloud Router por región; HA VPN con dos
túneles y BGP hacia on-premises (SLA 99.99 %) en la región primaria y, con `enable_vpn_dr = true`
(por defecto), otra HA VPN en el router de `dr_region` con prioridad de anuncio
`vpn_dr_route_priority` (200; on-premises prefiere la primaria, ADR 0022); anuncios BGP
personalizados con el /16 del hub, los /16 de los spokes y 35.199.192.0/19 (reenvío de Cloud
DNS); política de firewall
jerárquica en la organización (denegar por defecto; delegar con `goto_next` a la política de
cada red el tráfico interno, el de on-premises, las verificaciones de salud y IAP, para que
decidan las reglas por etiqueta segura del spoke: un `allow` en la organización sería final y
dejaría sin efecto la etiqueta `iap_ssh`);
DNS: zona de reenvío hacia on-premises y política de servidor entrante; con
`simulate_onprem = true`, la VPC `onprem-sim` con su gateway y router (y un router más en
`dr_region` para la VPN de DR), la delegación `delegate-dns-onprem-sim` de 35.199.192.0/19 hacia
esa VPC y su propia política de red (`module.firewall_onprem_sim`: DNS desde el reenvío de Cloud
DNS y SSH por IAP) (ADR 0006); Interconnect solo si `enable_interconnect = true`.

Entradas: `org_id`, `prefix`, `primary_region`, `dr_region`, `hub_supernet` (/16 del hub que
se anuncia por BGP; contiene `hub_cidrs`), `hub_cidrs`, `spoke_supernets`
(map entorno → /16), `onprem_cidrs`, `hub_asn`, `onprem_asn` (privado en modo simulado; en modo
real admite un ASN público de 2 o 4 bytes), `vpn_bgp_ranges`, `enable_vpn_dr`,
`vpn_dr_bgp_ranges`, `vpn_dr_route_priority`, `simulate_onprem`, `onprem_vpn_gateway_ips`,
`onprem_vpn_secret_id`, `onprem_vpn_secret_version`, `onprem_vpn_secret_version_overrides`,
`onprem_dns_domain`, `onprem_dns_servers`, `enable_interconnect`, `labels`, `state_bucket`
(más `onprem_sim_cidr`, `interconnect_attachments` y `region_short_names`, con valor por
defecto).

El secreto compartido de la VPN nunca va en variables: con on-premises real se lee de Secret
Manager en una versión numérica (`onprem_vpn_secret_version`, sin `latest`; por túnel con
`onprem_vpn_secret_version_overrides`, llaves `primary-if0`, `primary-if1`, `dr-if0`, `dr-if1`,
para rotar de a un túnel); en modo simulado se genera y solo existe en el estado cifrado
(ADR 0006).

| Salida | Tipo | Contenido |
|---|---|---|
| `hub_project_id` | string | |
| `hub_network_name` | string | |
| `hub_network_self_link` | string | para peering y zonas de peering DNS |
| `firewall_policy_id` | string | política jerárquica |

Salidas adicionales: `spoke_supernets`, `firewall_policy_rules`, `hub_routers`,
`bgp_advertised_ranges`, `vpn_tunnel_names`, `vpn_gateway_ip_addresses`, `vpn_dr_tunnel_names`,
`vpn_dr_gateway_ip_addresses`, `dns_inbound_forwarder_ips`, `onprem_sim_network_name`,
`onprem_sim_firewall_policy_id`.

### 7.4 `3-networks/envs/<env>` (spoke)

Crea: proyecto `net-spoke` como host de Shared VPC; VPC; subredes de §5 con Private Google
Access y flow logs al 50 %; subredes proxy-only; rango y conexión de Private Service Access;
peering con el hub en ambos sentidos (el hub exporta rutas personalizadas, el spoke las
importa); Cloud NAT por región (ADR 0004); zona privada `<env>.empresa.internal.`; zona de
peering DNS hacia el hub para el dominio on-premises; zonas privadas de `googleapis.com`,
`gcr.io`, `pkg.dev` y `run.app` hacia el VIP de `google_apis_vip` (`restricted`,
199.36.153.4/30, por defecto en los tres entornos; o `private`, 199.36.153.8/30) y la ruta al
VIP restringido (ADR 0026); reglas de firewall de la VPC con etiquetas seguras (solo rangos del
balanceador 35.191.0.0/16 y 130.211.0.0/22, e IAP 35.235.240.0/20) y, con
`enable_filestore_nfs_lock_callbacks`, la regla `allow-filestore-nfs-callbacks` desde el rango
`psa` hacia los puertos de `filestore_nfs_lock_ports`.

Entradas: `billing_account`, `prefix`, `project_suffix`, `environment`,
`primary_region`, `dr_region`, `enable_dr`, `spoke_supernet` (/16 del entorno; contiene
`subnet_cidrs` y coincide con `spoke_supernets[environment]` del hub), `subnet_cidrs`,
`onprem_cidrs`, `onprem_dns_domain`, `flow_log_sampling` (por defecto 0.5), `lb_backend_ports`,
`enable_filestore_nfs_lock_callbacks`, `filestore_nfs_lock_ports`, `google_apis_vip`, `labels`,
`state_bucket` (más `dns_domain_base`, `project_deletion_policy` y `region_short_names`, con
valor por defecto).

| Salida | Tipo | Contenido |
|---|---|---|
| `host_project_id` | string | |
| `network_name` | string | |
| `network_self_link` | string | |
| `subnets` | map(object) | llave de §5 → `{ self_link, name, region, cidr, secondary_ranges }` (`secondary_ranges`: map nombre → CIDR, llaves `pods` y `services`) |
| `psa_range_name` | string | |
| `secure_tags` | map(string) | llaves `lb_backend`, `iap_ssh` → ID del valor de etiqueta (`tagValues/…`) |
| `secure_tag_keys` | map(string) | mismas llaves → ID de la llave de etiqueta (`tagKeys/…`) |
| `reserved_cidrs` | map(string) | rangos sin subred (`gke_master` y, con `enable_dr`, `gke_master_dr`); la etapa 5 los toma de aquí |
| `lb_backend_ports` | list(string) | puertos que la política del spoke abre hacia `lb_backend`; la etapa 5 comprueba sus backends contra ellos |
| `dns_zone_names` | map(string) | llaves `env`, `onprem`, `googleapis`, `gcr`, `pkg`, `run` → nombre de la zona |

Salidas adicionales: `host_project_number`, `network_id`, `routers`, `nat_names`,
`firewall_policy_id`, `firewall_policy_rules`, `private_dns_domain`.

Cada etiqueta segura es una llave propia con un solo valor: un recurso solo admite un valor por
llave, y una VM puede necesitar `lb_backend` e `iap_ssh` a la vez. La etapa 4 otorga
`roles/resourcemanager.tagUser` sobre esos valores a quien crea las instancias.

### 7.5 `4-projects/envs/<env>`

Crea: un proyecto de servicio por aplicación (`applications`, por defecto una llamada `app`)
unido al host; permisos de uso de subred para los agentes de servicio; cuentas de servicio de
ejecución; permisos de las llaves KMS a los agentes de servicio; permisos de lectura de
secretos; en prod, alta en el perímetro de cada proyecto de servicio **y del proyecto host de
la Shared VPC** (VPC-SC exige que el host esté en el mismo perímetro que sus proyectos de
servicio), con el recurso normal o el de dry-run según `vpc_sc_enforced` de la etapa 2; por
aplicación, un repositorio Docker de Artifact Registry
`<prefix>-<env>-app-<app>-images-<ubicación>` en `artifact_registry_location` (`us` por
defecto) con CMEK, lectura para `gke_nodes`, `mig` y el agente de Cloud Run y escritura para
los publicadores de `artifact_registry_publishers` (solo `serviceAccount:` y `group:`), y una
política de Binary Authorization del proyecto que solo admite ese repositorio (ADR 0024); en
prod, una regla de entrada del perímetro por aplicación con publicadores, limitada a
`artifactregistry.googleapis.com` en su proyecto de servicio (normal o de dry-run según
`vpc_sc_enforced`; el perímetro de la etapa 2 ignora sus `ingress_policies`, así que no las quita); los permisos de la
cuenta de la etapa 5 sobre cada proyecto de servicio (`workloads_project_roles` y
`projectIamAdmin` condicionado a `roles/cloudsql.client` y `roles/cloudsql.instanceUser`),
`serviceAccountAdmin` solo sobre la cuenta `workload` (enlace de Workload Identity) y
`compute.networkViewer` en el host (ADR 0023).

Entradas: `org_id`, `billing_account`, `prefix`, `project_suffix`, `environment`,
`primary_region`, `dr_region`, `applications` (map nombre → `{ apis, secrets }`),
`workloads_service_account`, `artifact_registry_location`,
`binary_authorization_allowlist_patterns`, `binary_authorization_attestors`,
`artifact_registry_publishers` (map aplicación → miembros), `deletion_policy`, `labels`,
`state_bucket`.

| Salida | Tipo | Contenido |
|---|---|---|
| `service_project_ids` | map(string) | aplicación → ID de proyecto |
| `service_project_numbers` | map(string) | |
| `service_accounts` | map(map(string)) | `[aplicación][uso]` → correo; usos `gke_nodes`, `workload`, `mig`, `run` |
| `artifact_registry_repositories` | map(string) | aplicación → URL del repositorio (`<ubicación>-docker.pkg.dev/<proyecto>/<repositorio>`) |
| `service_agents` | map(map(string)) | `[aplicación][agente]` → miembro de IAM de los agentes de servicio con permisos (incluye `artifactregistry`) |

### 7.6 `5-workloads/envs/<env>`

Crea, en el proyecto de servicio y con interruptores por carga (`enable_gke`, `enable_mig`,
`enable_cloud_run`, `enable_filestore`, `enable_memorystore`): GKE, MIG, Cloud Run, Cloud SQL,
Memorystore, Cloud Storage, Filestore, balanceador HTTPS global con Cloud Armor y certificado
administrado, balanceador interno, observabilidad y respaldo. En prod con `enable_dr = true`:
réplica de Cloud SQL en la región de DR, bucket de doble región con turbo replication, plan de
Backup for GKE. Con `dr_active = true` (conmutación): cómputo en la región de DR, backends del
balanceador externo hacia ella (GKE sale del externo mientras `gke_lb_negs.dr` esté vacío) y un
segundo balanceador interno en DR (`module.internal_lb` es uno por región, con
`allow_global_access`; ADR 0022). El certificado del balanceador interno y sus autorizaciones
DNS los crea la raíz por región: con `enable_dr`, también el de la región de DR aunque
`dr_active` sea false, para que esté emitido antes de un incidente. El registro DNS interno no
lo administra ninguna etapa: la salida `internal_lb_dns_records` da los registros A de la región
activa. `dr_teardown = true` (exige `enable_dr`) quita la protección contra borrado solo del
clúster de GKE y del servicio de Cloud Run de DR, para que la vuelta (`dr_active = false`) los
pueda destruir en prod. Con GKE, la cuenta de Kubernetes
`<gke_workload_namespace>/<gke_workload_ksa_name>` se enlaza a la cuenta `workload` por Workload
Identity. Las subredes y los rangos reservados salen del estado de la etapa 3 (`subnets`,
`reserved_cidrs`); la raíz no tiene `subnet_cidrs`.

Entradas: `prefix`, `environment`, `primary_region`, `dr_region`, `enable_dr`, `dr_active`,
`dr_teardown`, `application`, los interruptores, `gke_node_pools`, `gke_workload_namespace`,
`gke_workload_ksa_name`, `gke_lb_negs`, `cloud_run_image`, `sql_tier`, `sql_database_version`,
`domain_names` (certificado), `internal_domain_names`, `notification_emails`, `labels`,
`state_bucket` (más los ajustes de cada carga, con valor por defecto; lista completa en el README
de la raíz).

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
| `gke_workload_identity_member` | string | miembro de Workload Identity enlazado a la cuenta `workload` |

Salidas adicionales: `sql_replica_connection_name`, `cloud_run_service_names`,
`mig_instance_groups`, `internal_lb_dns_authorization_records`, `internal_lb_certificate_ids`,
`redis_host`,
`filestore_ip_address`, `backup_vault_id`, `backup_plan_ids`, `active_region`.

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
| `iam` | Asignaciones aditivas de roles a grupos y cuentas de servicio | Rechaza miembros `user:` por validación | `bindings` (lista de `{ scope, resource, role, member }`) | `members`, `conditions` |
| `network-hub` | VPC hub, subredes, routers | Subredes privadas, PGA, flow logs 0.5 | `project_id`, `subnets`, `router_asn`, `extra_router_regions` (routers sin subred, p. ej. el de DR de `onprem-sim`) | `network_self_link`, `network_name`, `routers` (map región → nombre) |
| `network-spoke` | VPC spoke, subredes y rangos secundarios, proxy-only, PSA, peering, NAT | PGA; flow logs 0.5; NAT por región; sin IP públicas | `project_id`, `subnet_cidrs`, `regions`, `hub_network_self_link`, `enable_dr` | las de §7.4, `peerings` |
| `firewall` | Política jerárquica o política de red con reglas y etiquetas seguras | Denegar todo por defecto; reglas por etiqueta segura | `parent` (organización o red), `rules`, `secure_tags`, `name_suffix` (más de una política por red) | `policy_id`, `secure_tag_ids`, `rules` |
| `cloud-armor` | Política de seguridad | Reglas OWASP preconfiguradas (SQLi, XSS como mínimo) y límite de tasa | `project_id`, `owasp_rules`, `rate_limit` | `policy_self_link` |
| `load-balancer` | Balanceador HTTPS global externo, o interno regional (`type`) | HTTPS con certificado administrado; redirección de HTTP; política de Cloud Armor obligatoria en el externo | `project_id`, `type`, `backends`, `domain_names`, `security_policy`, `network`, `subnet` | `ip_address`, `backend_service_ids`, `backend_groups` |
| `dns` | Zonas privadas, de reenvío y de peering; política de servidor entrante | Zonas privadas por entorno; reenvío condicional a on-premises | `project_id`, `zones` (map con `type`: `private`, `forwarding`, `peering`), `networks` | `zone_names`, `inbound_forwarder_ips`, `zones`, `records` |
| `hybrid-connectivity` | HA VPN, túneles, sesiones BGP; opcional Interconnect | 2 túneles y BGP; Interconnect opcional | `project_id`, `network`, `router`, `peer` (gateway externo o de otra VPC), `advertised_ranges`, `bgp_sessions`, `shared_secret_overrides` (secreto por túnel, para rotar de a uno) | `gateway_self_link`, `tunnel_names`, `bgp_peers` |
| `compute-mig` | Plantilla, MIG regional, autoescalador, verificación de salud | Shielded VM; imagen por variable (endurecida); autoescalado y autocuración; sin IP pública (`stack_type = "IPV4_ONLY"`) | `project_id`, `subnet`, `image`, `machine_type`, `min_replicas`, `max_replicas`, `service_account`, `kms_key` | `instance_group`, `health_check_id`, `subnetwork`, `kms_key` |
| `gke` | Clúster y pools de nodos | Nodos privados; Workload Identity; Binary Authorization; regional si `environment = "prod"` (validación); protección contra borrado fija en prod salvo `teardown` | `project_id`, `network`, `subnet`, `pods_range`, `services_range`, `master_cidr`, `gke_node_pools`, `node_service_account`, `kms_key`, `teardown` | `cluster_name`, `cluster_id`, `workload_pool`, `subnetwork`, `kms_key`, `master_cidr`, `deletion_protection` |
| `cloud-run` | Servicio v2 con salida directa a la VPC | Solo tráfico interno y del balanceador; cuenta de servicio propia; protección contra borrado fija en prod salvo `teardown` | `project_id`, `region`, `image`, `subnet`, `service_account`, `kms_key`, `teardown` | `service_name`, `service_uri`, `subnetwork`, `kms_key`, `deletion_protection` |
| `storage` | Bucket | CMEK; versionado; reglas de ciclo de vida; acceso uniforme; sin acceso público | `project_id`, `location`, `kms_key`, `lifecycle_rules`, `dual_region` (objeto opcional con turbo replication) | `bucket_name` |
| `filestore` | Instancia | CMEK; red por PSA | `project_id`, `location`, `tier`, `capacity_gb`, `network`, `kms_key` | `instance_name`, `ip_address` |
| `cloud-sql` | Instancia, bases, usuarios IAM, réplica | IP privada únicamente; HA regional si prod (validación); PITR; réplica en DR si `enable_dr`; SSL obligatorio; CMEK; autenticación IAM | `project_id`, `region`, `dr_region`, `enable_dr`, `sql_tier`, `database_version`, `network`, `kms_key`, `dr_kms_key`, `iam_users`, `backup_plan_managed` (Backup and DR es dueño del horario y la retención) | `instance_name`, `connection_name`, `private_ip`, `replica_name` |
| `memorystore` | Instancia de Redis | IP privada; CMEK; HA si prod | `project_id`, `region`, `tier`, `memory_gb`, `network`, `kms_key` | `host`, `port` |
| `kms` | Llavero y llaves | Rotación de 90 días; `prevent_destroy` en las llaves | `project_id`, `location`, `keys` (map uso → opciones), `rotation_period` | `key_ids` (map), `keyring_id` |
| `secrets` | Contenedores de secretos e IAM | Nunca recibe valores; CMEK | `project_id`, `names`, `kms_keys`, `accessors` | `secret_ids` (map) |
| `vpc-sc` | Política de acceso (opcional), perímetro (ignora sus proyectos y reglas de entrada, que entran por recursos aparte), regla de entrada del pipeline como recurso aparte, reglas de salida | Perímetro para proyectos de prod con datos | `org_id`, `access_policy_id`, `perimeter_name`, `resources`, `restricted_services`, `ingress_identities`, `enforced` | `perimeter_name`, `access_policy_id`, `status_ingress_policies`, `spec_ingress_policies` |
| `observability` | Canales de notificación, verificaciones de disponibilidad, alertas, tableros, SLO | Alertas y tableros base; SLO 99.9 % | `project_id`, `notification_emails`, `uptime_checks`, `slo_target` | `notification_channel_ids`, `dashboard_ids` |
| `log-export` | Bucket de logs y sink | Retención bloqueada (por variable) | `project_id`, `parent` (organización, carpeta o proyecto), `filter`, `retention_days`, `retention_locked`, `kms_key` | `bucket_name`, `writer_identity` |
| `backup-dr` | Bóveda y plan de Backup and DR; plan de Backup for GKE | Política diaria; retención de 30 días; región secundaria | `project_id`, `region`, `dr_region`, `retention_days`, `gke_cluster_id` (opcional), `sql_log_retention_days` (7 por defecto) | `vault_id`, `plan_ids` |

Sin módulo propio, a propósito: Persistent Disk (lo crean `compute-mig` y `gke`), Cloud
Interconnect (interruptor dentro de `hybrid-connectivity`), Cloud IDS y Private Service
Connect (aparecen en la especificación como servicios, no como configuración mínima exigida;
no se construyen y se anota en `docs/pendientes-apply.md` como alcance no cubierto), y el
apagado de dev fuera de horario (mitigación de costo opcional, no construida).

El repositorio de Artifact Registry y la política de Binary Authorization no tienen módulo: los
crea la raíz de la etapa 4 (`artifacts.tf`), un recurso de cada uno por aplicación (ADR 0024).
El balanceador interno (`load-balancer` con `type = "internal"`) pone `allow_global_access` en
sus reglas de reenvío. La etapa 5 le pasa su certificado por `certificate_manager_certificates`
(lo crea la raíz por región, ver §7.6); el módulo solo lo crea si no recibe ninguno.

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

Cada regla tiene pruebas en Rego (`conftest verify`) y al menos dos planes de ejemplo en
`policies/fixtures/` (uno que pasa y uno que viola). Hay 27 planes; 13 son recortes de un
`terraform show -json` real de ejemplos sin GCP (nombre con `_real_`; por ejemplo, la regla de IP
pública sobre un MIG de doble pila y sobre nodos de GKE públicos). Comprobado el 21 nov 2026
desde `gcp-datacenter/` con `PATH="$HOME/go/bin:$PATH" bash scripts/policy-check.sh`: "83 tests,
83 passed" y "RESULTADO: 27 planes con el resultado esperado". Así el criterio "el pipeline
bloquea un PR que viola una política" se demuestra sin GCP en las pruebas; que bloquee un PR de
verdad depende de configurar `plan-gate` y las comprobaciones de §9.3 como obligatorias en
GitHub.

### 9.2 Pruebas

| Nivel | Dónde | Sin GCP |
|---|---|---|
| Estático | `scripts/check.sh`: fmt, validate, tflint, checkov sobre módulos, ejemplos y raíces | Sí |
| Políticas | `conftest verify` y `conftest test` sobre los planes de ejemplo | Sí |
| Unitario | `modules/<m>/tests/*.tftest.hcl` con `mock_provider`, `command = plan` y `override_during = plan` (Terraform 1.11 o mayor, ADR 0021) | Sí |
| Scripts del pipeline | `scripts/selftest.sh`: huella del plan, raíces afectadas, recursos no administrados, informe de Go | Sí |
| Integración | `tests/` con Terratest, un proyecto efímero por módulo | Solo se escribe y compila |
| Extremo a extremo | `tests/e2e/`: aplica 0 → 5, segundo plan sin cambios, conectividad, destroy de dev | Solo se escribe |

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
| `pr.yml` | Pull request | fmt, validate, tflint y checkov con Terraform 1.9.8 (`check.sh --skip test`) y con 1.16.5 (con `terraform test`); `conftest verify` y los planes de ejemplo; autopruebas de los scripts; terraform-docs al día; si la variable de repositorio `GCP_ENABLED` es `true`: plan por raíz afectada, Conftest sobre el plan, comentario con el resumen y el costo (Infracost). `plan-gate` resume los planes en un nombre fijo para marcarlo como obligatorio |
| `apply.yml` | Merge a `main` | Por cada raíz de las etapas 1 → 5, un trabajo `plan` sin entorno y un trabajo `apply` en el entorno de GitHub que vuelve a planear y solo aplica si la huella coincide con la revisada (ADR 0025). `common` y `prod` con revisores; dev automático y luego `dev-smoke` (prueba de humo); qa tras ella |
| `drift.yml` | Diario | `plan -detailed-exitcode` por raíz; si hay cambios, abre una incidencia. Además, por entorno, recursos no administrados con Cloud Asset Inventory |
| `terratest.yml` | Nocturno, manual y con una etiqueta `modules/<módulo>/vX.Y.Z` | Terratest (con una etiqueta, solo las pruebas de ese módulo) |

Los trabajos que tocan GCP se autentican con WIF y la cuenta de servicio de la etapa (la prueba
de humo y los recursos no administrados, con `GCP_AUDIT_SERVICE_ACCOUNT`, creada a mano); nunca
con llaves. Mientras `GCP_ENABLED` no sea `true`, esos trabajos se omiten y los demás deben pasar.
La protección de `main`, las comprobaciones obligatorias y los revisores de los entornos se
configuran a mano en GitHub y dependen del plan de GitHub ([`pipeline.md`](pipeline.md) §4):
sin esa configuración, nada de lo anterior bloquea un merge ni un apply.
`CODEOWNERS` por etapa: red (`3-networks`, módulos de red), seguridad (`1-org`, `2-security`,
`policies/`, módulos de seguridad y, solo seguridad, `.github/`, `0-bootstrap` y `scripts/`),
plataforma (el resto). Las acciones de los flujos van fijadas por SHA.

Versionado de módulos: las raíces consumen los módulos por ruta relativa. Una etiqueta Git
`modules/<modulo>/vX.Y.Z` solo dispara sus pruebas de integración; no hay etiquetas creadas ni
versiones publicadas (ADR 0013).

---

## 10. Documentación entregable

- `gcp-datacenter/README.md`: requisitos previos, orden de despliegue y comandos por etapa.
- `docs/adr/`: los 26 de §2.
- `docs/pipeline.md`: flujos, variables, entornos y configuración manual de GitHub.
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
12. Reglas de protección de rama, comprobaciones obligatorias (incluida `plan-gate`) y revisores
    obligatorios de los entornos `common` y `prod` en un repositorio privado, según el plan de
    GitHub del equipo.

La lista completa y vigente (51 puntos al 21 nov 2026, más los marcadores del código y el alcance
no cubierto) está en [`pendientes-apply.md`](pendientes-apply.md).
