# Pendientes del primer apply

Todo lo que este repositorio no puede comprobar sin GCP. Nada se ha aplicado: cada entrada es
una expectativa de diseño hasta que el primer apply la confirme o la tumbe. Cuando una entrada
se verifique, se marca con la fecha, el comando y el resultado; cuando falle, se corrige el
código y se actualiza el ADR que corresponda.

Formato de cada entrada: **qué** se verifica, **dónde** está en el código y **si falla**, qué
hacer (lo que dice el código o su README; lo que es propuesta de esta lista se marca así).

Contenido:

1. [Lista inicial del contrato (§12)](#1-lista-inicial-del-contrato-12), puntos 1 a 12.
2. [Agregados por los ADR](#2-agregados-por-los-adr), puntos 13 a 18.
3. [Otros pendientes detectados al documentar](#3-otros-pendientes-detectados-al-documentar),
   puntos 19 a 30.
4. [Marcadores `VERIFICAR-EN-APPLY` del código](#4-marcadores-verificar-en-apply-del-código),
   por etapa y módulo.
5. [Alcance no cubierto y limitaciones conocidas](#5-alcance-no-cubierto-y-limitaciones-conocidas).

Los ADR, runbooks y README citan estos puntos por número ("punto 11"): no se renumeran. Un
punto que se corrige en el código sin necesitar GCP no se borra: queda con la marca
**Resuelto en el código** y la fecha, para que las referencias sigan apuntando a algo. Resuelto
en el código no es verificado: lo que el cambio deja por comprobar en GCP pasa a un punto
nuevo.

---

## 1. Lista inicial del contrato (§12)

**1. Listado del backend `gcs` con IAM condicionado por prefijo.**
Qué: que `terraform init`, `plan` y `apply` de cada raíz funcionen con `objectAdmin` sobre su
prefijo y `objectViewer` sobre los prefijos que lee, con la cláusula
`resource.type == "storage.googleapis.com/Bucket"` que permite listar.
Dónde: `stages/0-bootstrap/service_accounts.tf` (`local.stages` y las condiciones, línea 89);
ADR 0010; contrato §6.2.
Si falla: pasar a carpetas administradas de Cloud Storage con IAM propio por prefijo; plan B, un
bucket por etapa (ADR 0010).

**2. Activación de Security Command Center.**
Qué: el proveedor 6.x no tiene recurso para activar SCC; se activa en la consola. Verificar que,
activado, la etapa 1 cree la notificación `<prefix>-common-ops-scc-findings` y que la cuenta de
SCC pueda publicar en el tema.
Dónde: `stages/1-org/main.tf` (líneas 139 y 173); runbook
[01](runbooks/01-arranque-etapa-0.md), paso de SCC.
Si falla: la activación queda como paso manual del runbook 01 (ya es así). Si la notificación
falla con SCC activo, revisar el IAM del tema `scc_findings` (propuesta).

**3. `gcp.resourceLocations` frente a la doble región y los recursos globales.**
Qué: que los grupos `in:<región>-locations` más `additional_allowed_locations` (`us` por
defecto) admitan los llaveros de la multirregión `us`, el bucket de doble región, el
balanceador global, las zonas DNS y demás recursos globales.
Dónde: `modules/org/main.tf:20`, `modules/storage/main.tf:89`, `stages/1-org` (variable
`additional_allowed_locations`).
Si falla: agregar la ubicación que falte a `additional_allowed_locations` (propuesta) y repetir
el apply de la etapa que falló.

**4. CMEK del proyecto `security` desde prod con el perímetro forzado.**
Qué: que los agentes de servicio de los proyectos de prod sigan usando sus llaves de
`<prefix>-common-security` después de `vpc_sc_enforced = true`.
Dónde: `stages/4-projects/envs/*/vpc_sc.tf:10`; ADR 0009 y 0019.
Si falla: KMS no está restringido por defecto (ADR 0019); revisar en los registros de
VPC-SC del modo dry-run qué servicio se bloqueó y agregar la regla de entrada o salida en
`egress_policies`/`ingress_identities` del módulo `vpc-sc` (propuesta).

**5. Regla de entrada del perímetro para las cuentas del pipeline.**
Qué: que las cinco cuentas `<prefix>-tf-<etapa>` sigan operando dentro del perímetro forzado.
Dónde: `modules/vpc-sc/main.tf:46`; `stages/2-security` (`ingress_identities`).
Si falla: volver a `vpc_sc_enforced = false` (aplicar 2-security y luego 4-projects de prod),
leer las violaciones registradas y ajustar la regla.

**6. Propagación de rutas.**
Qué: que las rutas aprendidas por BGP en el hub lleguen a los spokes por el peering (el hub
exporta rutas personalizadas, el spoke las importa) y que on-premises reciba y alcance los /16
de los spokes.
Dónde: `modules/network-spoke/main.tf:181`; anuncios en `stages/3-networks/vpn.tf`; ADR 0003.
Si falla: revisar `bgp_advertised_ranges` (salida del hub) y la exportación del peering
`hub_to_spoke` (propuesta).

**7. Reenvío de DNS.**
Qué: que on-premises reciba el anuncio de `35.199.192.0/19` y responda a las consultas que el
hub le reenvía para `onprem_dns_domain`; y que on-premises resuelva las zonas de GCP por las IP
de `dns_inbound_forwarder_ips`.
Dónde: `stages/3-networks/dns.tf:8`, `modules/dns/main.tf:92`.
Si falla: en modo simulado es esperado (no hay servidor DNS, ver §5); con on-premises real,
revisar el anuncio y el firewall del lado on-premises (propuesta).

**8. Rango del plano de control de GKE.**
Qué: si el clúster se crea con Private Service Connect, `gke_master` (`10.X.38.0/28`) queda
reservado sin uso.
Dónde: `modules/gke/main.tf:46`.
Si falla: no es una falla; anotar que el rango queda libre y quitar la regla
`allow-gke-control-plane` del spoke si sobra (propuesta).

**9. Cuotas.**
Qué: CPU, direcciones IP, clústeres, instancias de Cloud SQL y demás cuotas de las dos regiones
frente a prod completo (`5-workloads/envs/prod` con todos los interruptores encendidos).
Dónde: `stages/5-workloads/envs/prod/terraform.tfvars.example`.
Si falla: pedir aumento de cuota antes del apply de prod.

**10. Tiempo del despliegue 0 → 5.**
Qué: duración total frente al objetivo de 90 minutos.
Dónde: `apply.yml` (las etapas 1 a 5) más la etapa 0 manual.
Si falla: medir por raíz y documentar cuál domina (propuesta).

**11. Segundo `plan` sin cambios y `destroy` de dev sin huérfanos.**
Qué: `terraform plan -detailed-exitcode` sale con 0 en todas las raíces después del primer
apply; `terraform destroy` de `5-workloads/envs/dev`, `4-projects/envs/dev` y
`3-networks/envs/dev` (en ese orden) no deja recursos.
Dónde: todas las raíces; marcadores de `modules/gke/main.tf:143`, `modules/backup-dr/main.tf:21`,
`modules/network-spoke/main.tf:158`.
Si falla: cada diferencia perpetua se corrige en el módulo (no con `ignore_changes` a ciegas);
para el destroy, `deletion_policy = "DELETE"` y `deletion_protection = false` en dev.

**12. Protección de rama y revisores del entorno `prod`.**
Qué: que el plan de GitHub del equipo permita exigir las comprobaciones de `pr.yml` en `main` y
dos revisores en el entorno `prod`.
Dónde: [`pipeline.md`](pipeline.md) §4.
Si falla: sin revisores obligatorios, prod se aplicaría sin aprobación; no encender
`GCP_ENABLED` hasta resolverlo (propuesta).

---

## 2. Agregados por los ADR

Los ADR proponen estas entradas porque no tenían una propia en §12.

**13. Migración del estado local de la etapa 0 (ADR 0008).**
Qué: que `terraform init -migrate-state` copie el estado local al bucket y que el agente de Cloud
Storage del proyecto semilla tenga `cryptoKeyEncrypterDecrypter` sobre la llave `state` antes de
crear el bucket.
Dónde: `stages/0-bootstrap/main.tf:166`; runbook [01](runbooks/01-arranque-etapa-0.md).
La consulta del agente por número de proyecto es el punto 27.
Si falla: el permiso puede tardar en propagarse: repetir el apply (lo dice el código). La
migración se repite mientras exista el `terraform.tfstate` local.

**14. Banderas y roles condicionados de Cloud SQL (ADR 0015).**
Qué: que la API acepte `cloudsql.iam_authentication`, `pgaudit.log` con varias clases y los
roles `cloudsql.client`/`cloudsql.instanceUser` condicionados a la instancia, y que se entre con
un token de IAM.
Dónde: `modules/cloud-sql/main.tf:10` y `:356`. La cuenta de la etapa 5 asigna esos roles con
una concesión delegada de la etapa 1 (punto 28).
Si falla: separar las clases de `pgaudit.log` o quitar la condición de los roles (propuesta).

**15. CMEK y bloqueo del bucket de logs (ADR 0018).**
Qué: permiso del agente de Cloud Storage del proyecto `logging` sobre la llave `logs` antes de
crear el bucket, y que `log_retention_locked = true` se aplique sobre un bucket ya creado sin
que un plan posterior intente desbloquearlo.
Dónde: `modules/log-export/main.tf:65` y `:97`.
Si falla: repetir el apply (propagación de IAM). El bloqueo es irreversible: probarlo primero
con `log_retention_locked = false`.

**16. Cloud Run público detrás del balanceador (ADR 0020).**
Qué: que `invoker_iam_disabled = true` no choque con `iam.allowedPolicyMemberDomains` y que la
URL `run.app` no sea alcanzable desde internet.
Dónde: `modules/cloud-run/main.tf:32`.
Si falla: dejar `public_via_load_balancer = false` y servir por IAP o con tokens de identidad
(alternativas del ADR 0020).

**17. dev y qa siguen usando sus llaves con el perímetro forzado (ADR 0019).**
Qué: la comprobación inversa del punto 4: los agentes de dev y qa (fuera del perímetro) cifran y
descifran con sus llaves del proyecto `security` (dentro) después de forzarlo.
Dónde: `stages/2-security/variables.tf` (`vpc_sc_restricted_services`).
Si falla: confirmar que `cloudkms.googleapis.com` no está en `vpc_sc_restricted_services`.

**18. Proyecto host de prod dentro del perímetro (ADR 0009).**
Qué: el ADR 0009 señaló que faltaba `<prefix>-prod-net-spoke`; la etapa 4 ya lo da de alta
(`data "google_project" "host"` y el recurso de alta). Verificar que el host y los proyectos de
servicio queden en el mismo perímetro antes de forzarlo.
Dónde: `stages/4-projects/envs/prod/vpc_sc.tf`.
Si falla: no forzar el perímetro hasta que ambos aparezcan como recursos del perímetro.

---

## 3. Otros pendientes detectados al documentar

**19. Permisos de la cuenta `<prefix>-tf-4-projects`. Resuelto en el código (21 nov 2026).**
Era: el README de la etapa 4 listaba roles que no otorgaba ninguna etapa (`tagAdmin` sobre los
valores de etiqueta del spoke, `projectIamAdmin` en el host para
`container.hostServiceAgentUser`, `roles/browser` en el host).
Ahora: la etapa 1 le da en las carpetas de entorno `roles/resourcemanager.tagAdmin` y
`roles/resourcemanager.projectIamAdmin` con condición (solo puede asignar
`roles/container.hostServiceAgentUser`), además de `compute.xpnAdmin` y `projectCreator`
(`stages/1-org/iam.tf`, `stage_grants` y `stage_delegated_project_iam`). `roles/browser` ya no
se pide: el README de la etapa 4 supone que `xpnAdmin` basta para leer la carpeta y el host.
Lo que queda por verificar en GCP: puntos 28 y 29.

**20. `roles/certificatemanager.editor` para `<prefix>-tf-5-workloads`. Resuelto en el código
(21 nov 2026).**
Era: el balanceador interno (`enable_internal_lb`) crea un certificado de Certificate Manager y
la etapa 1 no asignaba ese rol.
Ahora: está en `env_folder_roles` de `5-workloads` en `stages/1-org/iam.tf` y en el README de la
etapa 1 y de la etapa 5.

**21. Comando de migración del README de la etapa 0. Resuelto en el código (21 nov 2026).**
Era: el README de `stages/0-bootstrap` borraba `backend_override.tf` y después llamaba a
`terraform output -raw state_bucket` dentro de `init -migrate-state`. Comprobado sin GCP
(Terraform 1.16.5, configuración mínima con backend `gcs` y override local, 21 nov 2026): con el
override borrado, `terraform output` termina con `Error: Backend initialization required` y el
bucket llega vacío.
Ahora: el README de la etapa toma `STATE_BUCKET` antes de borrar el override, en el mismo orden
que el runbook [01](runbooks/01-arranque-etapa-0.md) (paso 4) y el README del repositorio. La
migración en sí sigue pendiente (punto 13).

**22. Proyecto de cuota de la etapa 0 (HYPOTHESIS).**
Qué: la etapa 0 usa las credenciales de aplicación de una persona sin proyecto de cuota
(`provider "google" {}`); algunas APIs (por ejemplo Cloud Billing o Resource Manager) pueden
rechazar llamadas con credenciales de usuario sin proyecto de cuota.
Dónde: `stages/0-bootstrap/providers.tf`.
Si falla: `gcloud auth application-default set-quota-project <proyecto-existente>` con un
proyecto donde la persona tenga `serviceusage.services.use` (propuesta).

**23. SCC activo antes de la etapa 1 (HYPOTHESIS).**
Qué: `google_scc_v2_organization_notification_config` probablemente falla si SCC no está
activado en la organización.
Dónde: `stages/1-org/main.tf:139`.
Si falla: activar SCC (runbook 01) y repetir el apply de la etapa 1.

**24. Reconciliar la réplica de Cloud SQL después de promoverla.**
Qué: después de `gcloud sql instances promote-replica`, el recurso
`module.cloud_sql.google_sql_database_instance.replica["dr"]` ya no es réplica; el plan
siguiente probablemente propone reemplazarlo (y `deletion_protection` lo impide en prod).
Dónde: `modules/cloud-sql/main.tf` (recurso `replica`, sin `lifecycle`);
`stages/5-workloads/envs/prod/README.md`, "DR".
Si falla: seguir el runbook [04](runbooks/04-conmutacion-a-dr.md) (apply con `-target` de
cómputo y balanceadores durante el incidente) y diseñar la reconciliación en el primer
simulacro.

**25. Imagen de Cloud Run en un registro regional.**
Qué: el ejemplo de prod usa `us-central1-docker.pkg.dev/...`; con la región primaria caída, el
servicio de DR no podría descargarla.
Dónde: `stages/5-workloads/envs/prod/terraform.tfvars.example` (`cloud_run_image`).
Si falla: usar un repositorio multirregional de Artifact Registry (`us-docker.pkg.dev`) o
replicar la imagen en `dr_region` (propuesta).

**26. Llave de aplicación con guion. Resuelto en el código (21 nov 2026).**
Era: la etapa 4 admitía llaves de `applications` con guiones (`^[a-z][a-z0-9-]*[a-z0-9]$`) y
`application` de la etapa 5 solo `^[a-z][a-z0-9]{1,9}$`: una aplicación con guion tenía proyecto
pero no podía tener cargas.
Ahora: las dos validan `^[a-z][a-z0-9]{1,7}$` (2 a 8 caracteres, sin guion;
`stages/4-projects/envs/*/variables.tf` y `stages/5-workloads/envs/*/variables.tf`). Regla de
nombres en el runbook [02](runbooks/02-alta-proyecto-aplicacion.md). En la misma corrección:
`prefix` valida `^[a-z][a-z0-9]{1,5}$` en todos los módulos y raíces, la etapa 4 exige que
`workloads_service_account` empiece con `<prefix>-tf-5-workloads@`, los
`terraform.tfvars.example` usan `bnt-bootstrap-ops-tfstate` como `state_bucket` (el nombre que
crea la etapa 0 sin sufijo) y `.gitignore` ignora `tfplan`, `*.tfplan` y `plan.json`.

**27. Agente de Cloud Storage consultado por número de proyecto.**
Qué: `google_storage_project_service_account` se consulta con el número del proyecto, no con
su ID, en las tres raíces que crean el proyecto en el mismo plan: el ID se conoce en el plan y
la lectura correría en el plan del primer apply contra un proyecto que todavía no existe; el
número solo se conoce al crearlo, así que la lectura se pospone al apply. Verificar que la API
de Cloud Storage acepte el número en `projects/<proyecto>/serviceAccount` y devuelva el mismo
agente.
Dónde: `stages/0-bootstrap/main.tf:106` (proyecto semilla); `modules/log-export/main.tf:29`
(variable opcional `project_number`, que la etapa 1 pasa para el proyecto `logging`);
`stages/4-projects/envs/*/service_agents.tf:55`.
Si falla: sin indicación en el código. Propuesta: volver a consultar con el ID y crear el
proyecto en un apply previo con `-target` del módulo del proyecto.

**28. Concesiones delegadas de `projectIamAdmin` en las carpetas de entorno (HYPOTHESIS).**
Qué: la etapa 1 da a `<prefix>-tf-4-projects` y a `<prefix>-tf-5-workloads`
`roles/resourcemanager.projectIamAdmin` en las carpetas `dev`, `qa` y `prod` con la condición
`api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([...])`: la de la
etapa 4 solo puede asignar `roles/container.hostServiceAgentUser` (agente de GKE en el host del
spoke) y la de la etapa 5 solo `roles/cloudsql.client` y `roles/cloudsql.instanceUser` (módulo
`cloud-sql`). Verificar que una condición de ese tipo se acepte en una carpeta, que se evalúe al
cambiar el IAM de los proyectos de abajo, y que las asignaciones de proyecto que esas etapas
hacen sobre proyectos que no crean (el host del spoke en la 4; el proyecto de servicio en la 5,
`modules/cloud-sql/main.tf`, recurso `login`) se limiten a esos roles.
Dónde: `stages/1-org/iam.tf:125` (`stage_delegated_project_iam`); README de la etapa 1.
Si falla: sin indicación en el código. Propuesta: asignar el rol en el proyecto (la etapa 3 en
el host; la etapa 4 en el proyecto de servicio) en lugar de la carpeta, con PR revisado por
seguridad.

**29. Permisos heredados de la cuenta `<prefix>-tf-4-projects` (HYPOTHESIS).**
Qué: que `roles/resourcemanager.tagAdmin` en la carpeta del entorno se herede a las llaves de
etiqueta cuyo padre es el proyecto `net-spoke` (y a sus valores), y que `roles/compute.xpnAdmin`
incluya `resourcemanager.folders.get` y `resourcemanager.projects.get` para las fuentes de datos
`google_folder` y `google_project` del host.
Dónde: `stages/4-projects/envs/*/README.md`, "Roles de la cuenta de servicio de la etapa" (el
marcador está en el README, no en un `.tf`).
Si falla: sin indicación. Propuesta: `roles/browser` en la carpeta para la lectura; para las
etiquetas, `tagAdmin` sobre las llaves desde la etapa 3, que es la dueña del proyecto.

**30. La cuenta de `3-networks` queda dueña de `net-spoke` (HYPOTHESIS).**
Qué: los spokes no reciben en las carpetas `networkAdmin`, `securityAdmin`, `tagAdmin`, `dns.admin`
ni `serviceUsageAdmin`: cuentan con que GCP haga dueña (`roles/owner`) del proyecto `net-spoke` a
la cuenta que lo crea. Verificar que así sea y que ninguna política de organización lo impida.
Dónde: `stages/3-networks/envs/*/README.md`, "Roles de la cuenta de servicio" (el marcador está
en el README, no en un `.tf`).
Si falla: sin indicación. Propuesta: asignar esos roles en el proyecto desde la propia raíz del
spoke o en las carpetas desde la etapa 1.

---

## 4. Marcadores `VERIFICAR-EN-APPLY` del código

Conteo al 21 nov 2026:

```bash
grep -rn "VERIFICAR-EN-APPLY" modules stages --include=*.tf | wc -l    # 84
grep -rln "VERIFICAR-EN-APPLY" modules stages --include=*.tf | wc -l   # 46 archivos
```

Fuera de los `.tf`, solo los README mencionan `VERIFICAR-EN-APPLY`; esta lista cuenta los
`.tf`, salvo dos marcadores que solo están en README (al final de esta sección). Las raíces de
`envs/{dev,qa,prod}` son idénticas, así que sus marcadores se listan una vez con `envs/*` y
"(x3)": las 84 líneas son 64 marcadores distintos (41 en módulos y 23 en etapas). "Si falla"
cita el código cuando lo dice; si no, la entrada dice "sin indicación".

### Etapa 0 (`stages/0-bootstrap`)

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `main.tf:106` | Que la API de Cloud Storage acepte el número del proyecto semilla al consultar su agente (punto 27) | Ver punto 27 |
| `main.tf:166` | Permiso del agente de Cloud Storage sobre la llave al crear el bucket | Repetir el apply (propagación de IAM) |
| `service_accounts.tf:89` | `init`/`plan`/`apply` del backend con las condiciones de §6.2 (punto 1) | Carpetas administradas con IAM propio por prefijo |
| `service_accounts.tf:208` | Que los permisos del rol personalizado `<prefix>TfKmsSecretIamGranter` se admitan en roles personalizados | Sin indicación; quitar el permiso rechazado y revisar si la etapa 4 lo necesita |
| `wif.tf:32` | Que el mapeo de `attribute.environment` no falle en trabajos sin entorno de GitHub | Sin indicación |

### Etapa 1 (`stages/1-org`)

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `iam.tf:125` | Condición con `iam.googleapis.com/modifiedGrantsByRole` aceptada en una carpeta y evaluada al cambiar el IAM de los proyectos de abajo (punto 28) | Ver punto 28 |
| `main.tf:118` | Que `iam.allowedPolicyMemberDomains` no rechace los `principalSet://` de WIF en cambios futuros | Sin indicación |
| `main.tf:139` | Activación de SCC (punto 2) | Paso manual del runbook 01 |
| `main.tf:173` | Que la cuenta de SCC pueda publicar en el tema de hallazgos | Sin indicación |
| `providers.tf:4` | Que todas las APIs acepten el proyecto semilla como proyecto de cuota | Sin indicación |

### Etapa 2 (`stages/2-security`)

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `providers.tf:4` | Que todas las APIs acepten el proyecto de cuota | Sin indicación |

### Etapa 3, hub (`stages/3-networks`)

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `dns.tf:8` | Con `simulate_onprem = true` no hay servidor DNS en `onprem_dns_servers` | Probar con un servidor real o una VM DNS creada a mano en `onprem-sim` |
| `firewall.tf:54` | Que el tráfico delegado con `goto_next` (la política de la organización no tiene reglas allow) llegue a la política del spoke, que las verificaciones de salud lleguen a los backends con `lb_backend` y que IAP solo entre a las VM con `iap_ssh` | Sin indicación |

### Etapa 3, spokes (`stages/3-networks/envs/*`)

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `dns.tf:30` (x3) | Que la cuenta de la etapa pueda adjuntar la zona del entorno a la VPC hub (`dns.networks.bindPrivateDNSZone` en net-hub) y que on-premises la resuelva por el reenvío entrante | Sin indicación |

### Etapa 4 (`stages/4-projects/envs/*`)

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `iam.tf:169` (x3) | Que `tagUser` sobre el valor baste al agente de GKE y a `<n>@cloudservices` para crear nodos y VM con etiquetas | Puede pedir además `tagUser` sobre la llave o `roles/resourcemanager.tagHoldAdmin` |
| `service_agents.tf:10` (x3) | Que `generateServiceIdentity` acepte `sqladmin`, `file`, `redis` y `gkebackup` | Quitar el servicio de la lista (su agente existe al habilitar la API) |
| `service_agents.tf:12` (x3) | Que los agentes de `container`, `compute` y `run` existan justo después de habilitar sus APIs | Agregar esos servicios a la lista |
| `service_agents.tf:55` (x3) | Que la API de Cloud Storage acepte el número del proyecto de servicio al consultar su agente (punto 27) | Ver punto 27 |
| `vpc_sc.tf:10` (x3) | CMEK de `security` con el perímetro forzado (punto 4) | Ver punto 4 |

### Etapa 5 (`stages/5-workloads/envs/*`)

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `load_balancing.tf:78` (x3) | Que el mismo grupo de instancias y el mismo NEG sin servidor sirvan a la vez al balanceador externo y al interno | Sin indicación |
| `load_balancing.tf:148` (x3) | El certificado administrado se activa cuando los registros A de `domain_names` apuntan a `lb_ip_address` | Crear los registros en la zona pública (fuera del repositorio) |
| `load_balancing.tf:176` (x3) | Registros de `dns_authorization_records` para emitir el certificado interno | Crearlos en la zona DNS pública del dominio |
| `operations.tf:51` (x3) | Formato del recurso de Cloud SQL en la asociación de Backup and DR y roles de la cuenta de la bóveda | Sin indicación |

### Módulos

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `backup-dr/main.tf:19` | API `backupdr` habilitada y bóveda en otra región que acepte respaldos de VM y Cloud SQL | Sin indicación |
| `backup-dr/main.tf:21` | El destroy de dev falla mientras la bóveda tenga respaldos dentro de la retención forzada | El procedimiento de destroy debe contemplarlo (esperar la retención o `enable_backup = false` en dev, propuesta) |
| `backup-dr/main.tf:35` | Plan de Cloud SQL (`sqladmin.googleapis.com/Instance`) en el proveedor 6.x y roles de la cuenta de la bóveda (salida `vault_service_account`) | Otorgar los roles en la etapa 4 o 5 |
| `backup-dr/main.tf:79` | Backup for GKE en otra región, complemento activo y permiso del agente de `gkebackup` sobre la llave | Sin indicación |
| `cloud-run/main.tf:9` | Salida directa a la VPC con red y subred del host como `projects/<host>/...` | Sin indicación |
| `cloud-run/main.tf:32` | `invoker_iam_disabled` frente a la política de organización (punto 16) | Ver punto 16 |
| `cloud-sql/main.tf:10` | `pgaudit.log` con varias clases; la réplica acepta las mismas banderas | Ver punto 14 |
| `cloud-sql/main.tf:190` | Agente de Cloud SQL con permiso sobre `kms_key` (lo da la etapa 4) | Sin indicación |
| `cloud-sql/main.tf:192` | Conexión de PSA de la red existente antes del create | Sin indicación |
| `cloud-sql/main.tf:320` | Réplica REGIONAL entre regiones con CMEK; retraso de replicación por debajo de 15 min | Si el retraso supera 15 min, el objetivo de RPO no se cumple (README del módulo) |
| `cloud-sql/main.tf:356` | Roles condicionados por `resource.name` y entrada con token IAM (punto 14) | Ver punto 14 |
| `compute-mig/main.tf:70` | Etiquetas seguras de la plantilla en las instancias y reglas `lb_backend` aplicadas | Sin indicación |
| `compute-mig/main.tf:162` | `max_surge_fixed` igual al número de zonas del MIG regional | Sin indicación |
| `dns/main.tf:92` | El filtro devuelve las IP de reenvío entrante (y solo esas) al terminar el apply | Sin indicación |
| `filestore/main.tf:48` | Permiso del agente sobre la llave, PSA desde el proyecto de servicio sobre la red del host, `deletion_protection_enabled` en el tier | Sin indicación |
| `firewall/main.tf:21` | Formato de `purpose_data` y etiquetas de organización en la política jerárquica | Sin indicación |
| `firewall/main.tf:26` | Si la API admite `enable_logging` en `goto_next` | Sin indicación |
| `gke/main.tf:46` | Plano de control con Private Service Connect (punto 8) | Ver punto 8 |
| `gke/main.tf:58` | Endpoint privado alcanzable desde la Shared VPC y los rangos autorizados | Bastión en el spoke o endpoint por DNS (no construido, README del módulo) |
| `gke/main.tf:143` | `node_config` del pool por defecto eliminado sin diferencias en el segundo plan | Ya se ignora en `lifecycle` |
| `gke/main.tf:230` | Nodos con etiquetas seguras del proyecto host | Ver `iam.tf:169` de la etapa 4 |
| `hybrid-connectivity/main.tf:141` | Interfaces y sesiones BGP de los attachments DEDICATED y PARTNER | Sin indicación |
| `load-balancer/main.tf:187` | Certificado administrado ACTIVE cuando los registros A apuntan a la IP; puede tardar hasta 60 min | Crear los registros A |
| `load-balancer/main.tf:357` | Certificado interno tras los registros de `dns_authorization_records`; una CA pública no emite para `*.internal` | Usar `certificate_manager_certificates` |
| `log-export/main.tf:29` | Que la API de Cloud Storage acepte el número de proyecto (`project_number`) al consultar el agente (punto 27) | Ver punto 27 |
| `log-export/main.tf:65` | Bloqueo sobre un bucket ya creado (punto 15) | Ver punto 15 |
| `log-export/main.tf:97` | Permiso del agente de Cloud Storage sobre la llave al crear el bucket | Repetir el apply |
| `memorystore/main.tf:65` | Permiso del agente sobre la llave y PSA sobre la red del host | Sin indicación |
| `network-spoke/main.tf:158` | Destroy de la conexión de PSA después de borrar las instancias de la etapa 5 | Sin indicación; esperar a que servicenetworking libere el peering y repetir (propuesta) |
| `network-spoke/main.tf:181` | Dos spokes no crean su peering a la vez; las rutas BGP llegan al spoke (punto 6) | El pipeline aplica los entornos en serie |
| `observability/main.tf:55` | Los buzones de `notification_emails` existen y aceptan las alertas | Sin indicación |
| `observability/main.tf:203` | La alerta de memoria de VM necesita Ops Agent | Sin él la condición queda sin datos |
| `observability/main.tf:288` | SLI por solicitudes con los filtros del balanceador y `select_slo_burn_rate` con tráfico real | Sin indicación |
| `org/main.tf:20` | Ubicaciones permitidas (punto 3) | Ver punto 3 |
| `org/main.tf:50` | Agentes de servicio de Google siguen recibiendo roles con `iam.allowedPolicyMemberDomains` | Sin indicación |
| `project-factory/main.tf:27` | Proyecto sin red default y sin error al intentar borrarla | Sin indicación |
| `secrets/main.tf:21` | Agente de Secret Manager con permiso sobre las llaves antes de crear los secretos | Lo da la etapa que llama al módulo (etapa 2) |
| `storage/main.tf:86` | Agente de Cloud Storage con permiso sobre la llave; llave de `us` para un bucket con `custom_placement_config` | Sin indicación |
| `storage/main.tf:89` | `gcp.resourceLocations` y la doble región (punto 3) | Ver punto 3 |
| `vpc-sc/main.tf:37` | Perímetro en dry-run sin bloque `status`; paso a forzado en un solo plan | Sin indicación |
| `vpc-sc/main.tf:46` | Regla de entrada del pipeline (punto 5) | Ver punto 5 |

### Marcadores solo en README

No entran en el conteo de los `.tf` de arriba.

| Archivo | Qué verificar | Si falla |
|---|---|---|
| `stages/3-networks/envs/*/README.md` (x3), "Roles de la cuenta de servicio" | Que la cuenta que crea `net-spoke` quede como dueña del proyecto (punto 30) | Ver punto 30 |
| `stages/4-projects/envs/*/README.md` (x3), "Roles de la cuenta de servicio de la etapa" | Que `compute.xpnAdmin` incluya `folders.get` y `projects.get` y que `tagAdmin` en la carpeta se herede a las llaves de etiqueta de `net-spoke` (punto 29) | Ver punto 29 |

---

## 5. Alcance no cubierto y limitaciones conocidas

No son fallas que el apply vaya a descubrir: son decisiones o huecos conocidos. Cada uno dice
qué, dónde y qué hacer si llega a importar.

**Cloud IDS y Private Service Connect no se construyen.** La especificación los menciona como
servicios, no como configuración mínima (contrato §8). Si se piden: módulo nuevo y ADR.

**Apagado de dev fuera de horario no construido.** Mitigación de costo opcional (contrato §8).
Si se pide: Cloud Scheduler con el cambio de tamaño del MIG y de los pools de GKE (propuesta).

**Servicios de PSA y plano de control de GKE no alcanzables desde on-premises.** Cloud SQL,
Memorystore y Filestore (rango `psa`, `10.X.176.0/20`) y el endpoint privado de GKE viven detrás
de otro peering dentro del spoke; el peering no es transitivo, así que el hub y on-premises no
llegan a ellos aunque el hub anuncie el /16 completo (ADR 0003 y 0012). Si on-premises los
necesita: proxy o bastión en el spoke, endpoint de GKE por DNS, o exportar las rutas del peering
de servicios (por verificar).

**On-premises simulado sin servidor DNS.** La VPC `onprem-sim` no tiene VM: la zona de reenvío
existe pero nadie responde, y el criterio "resuelve DNS de on-premises" no se puede probar en ese
modo (`stages/3-networks/dns.tf:8`). Para probarlo: una VM DNS creada a mano en `onprem-sim`, con
su IP en `onprem_dns_servers`.

**WIF filtra solo por repositorio.** Cualquier rama o flujo del repositorio puede tomar la
identidad de las cuentas de etapa (`stages/0-bootstrap/wif.tf`; [`pipeline.md`](pipeline.md) §5).
Mitigación no construida: condicionar por `attribute.ref` o `attribute.environment` y separar
cuentas de solo lectura para los `plan` de los PR.

**Una sola región en México.** Si se exigiera residencia de datos, `northamerica-south1` no
tiene región de DR en el país (ADR 0002): habría que aceptar DR entre zonas o una región de DR
fuera de México, y reabrir el ADR.

**Memorystore sin AUTH.** AUTH queda apagado para no guardar la cadena en el estado (ADR 0015,
`modules/memorystore`). La caché confía en la red: IP privada, firewall del spoke, TLS y el
perímetro en prod. Si se exige autenticación por cliente: Memorystore for Redis Cluster con IAM.

**El secreto compartido de la VPN vive en el estado cifrado.** En los dos modos el valor queda en
el estado de `3-networks/hub` (CMEK de la etapa 0, legible por la cuenta de `3-networks`;
ADR 0006). Rotarlo implica recrear los túneles.

**Nombres de objetos del bucket de estado visibles para todas las cuentas de etapa.** La
cláusula `resource.type == "storage.googleapis.com/Bucket"` que permite listar deja ver los
nombres (no el contenido) de todos los prefijos (contrato §6.2, ADR 0010). Si importa: carpetas
administradas.

**Planes de ejemplo de Conftest escritos a mano.** Los 14 archivos de `policies/fixtures/` no
salen de un `terraform show -json` real: demuestran las reglas, no que las reglas lean bien un
plan real del proveedor 6.x. Al tener GCP, regenerar al menos uno por regla desde un plan real.

**Sin acceso de emergencia.** Las personas solo tienen lectura (§7.1) y nadie tiene
`iam.serviceAccountTokenCreator` sobre las cuentas de etapa. Las operaciones manuales de los
runbooks (rotar o deshabilitar una llave, promover la réplica, un apply con `-target`) exigen
una identidad con los permisos de la cuenta de la etapa. Antes del primer simulacro hay que
definir cómo se obtiene (por ejemplo, una concesión temporal de la persona administradora de la
organización, auditada); no está construido.

**Nadie puede cargar valores de secretos.** Los contenedores se crean sin valores (ADR 0015) y
las versiones las carga "el equipo dueño fuera de Terraform", pero ningún grupo recibe
`roles/secretmanager.secretVersionAdder` (`stages/1-org`, `stages/2-security`). Definir el grupo y
otorgarlo en la etapa 2 por secreto (propuesta) antes de dar de alta aplicaciones con secretos.

**El grupo de soporte no tiene permiso de IAP.** La política de red del spoke permite el rango de
IAP hacia las VM con `iap_ssh` (la política jerárquica solo lo delega con `goto_next`), pero
ningún grupo recibe `roles/iap.tunnelResourceAccessor` ni OS Login. Si se
necesita acceso por IAP: asignarlo a un grupo en la etapa 4 (propuesta).

**Una aplicación con cargas por entorno.** La raíz `5-workloads/envs/<env>` tiene un solo
`application` y un solo prefijo de estado (`5-workloads/<env>`). La etapa 4 puede crear varios
proyectos de servicio, pero las cargas de una segunda aplicación necesitan otra raíz u otro
espacio de trabajo, que `apply.yml` y `drift.yml` no recorren (runbook 02).

**Proyecto `<prefix>-common-backup` sin recursos.** La etapa 1 lo crea, pero la bóveda de Backup
and DR vive en el proyecto de servicio de cada entorno (`stages/5-workloads/envs/*/operations.tf`).

**Memorystore y Filestore sin DR.** Solo existen en la región primaria
(`stages/5-workloads/envs/*/data.tf`); con la región caída no hay caché ni NFS hasta crearlos en
`dr_region`, y sus datos no se replican.

**Restauración de Backup for GKE no construida.** Hay plan de respaldo, no plan de restauración;
restaurar en el clúster de DR es un paso manual (runbook 04).

**Terratest y prueba de extremo a extremo sin ejecutar.** `tests/` (paquete 13) compila
(`go build`, `go vet`, `go test -run XXX`) y sus fixtures validan con `terraform validate`, pero
ninguna prueba se ha corrido contra GCP; ningún criterio de ejecución está demostrado.
