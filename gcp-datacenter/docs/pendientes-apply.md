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
   puntos 19 a 30; y
   [3.5 Agregados por la ronda de correcciones del 21 nov 2026](#35-agregados-por-la-ronda-de-correcciones-del-21-nov-2026),
   puntos 31 a 54; y
   [3.6 Agregados por la revisión del 23 nov 2026](#36-agregados-por-la-revisión-del-23-nov-2026),
   punto 55; y
   [3.7 Agregados por los controles del CIS del 23 nov 2026](#37-agregados-por-los-controles-del-cis-del-23-nov-2026),
   puntos 56 a 62.
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
Dónde: `stages/0-bootstrap/service_accounts.tf` (`local.stages` y las condiciones, línea 92);
ADR 0010; contrato §6.2.
Si falla: pasar a carpetas administradas de Cloud Storage con IAM propio por prefijo; plan B, un
bucket por etapa (ADR 0010).

**2. Activación de Security Command Center.**
Qué: el proveedor 6.x no tiene recurso para activar SCC; se activa en la consola. Verificar que,
activado, la etapa 1 cree la notificación `<prefix>-common-ops-scc-findings` y que la cuenta de
SCC pueda publicar en el tema.
Dónde: `stages/1-org/main.tf` (líneas 139 y 182; el tema con `enforce_in_transit` es el
punto 34); runbook
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
Dónde: `modules/vpc-sc/main.tf:134`; `stages/2-security` (`ingress_identities`).
Si falla: volver a `vpc_sc_enforced = false` (aplicar 2-security y luego 4-projects de prod),
leer las violaciones registradas y ajustar la regla.

**6. Propagación de rutas.**
Qué: que las rutas aprendidas por BGP en el hub lleguen a los spokes por el peering (el hub
exporta rutas personalizadas, el spoke las importa) y que on-premises reciba y alcance los /16
de los spokes.
Dónde: `modules/network-spoke/main.tf:182`; anuncios en `stages/3-networks/vpn.tf` (las dos
VPN: punto 37); ADR 0003.
Si falla: revisar `bgp_advertised_ranges` (salida del hub) y la exportación del peering
`hub_to_spoke` (propuesta).

**7. Reenvío de DNS.**
Qué: que on-premises reciba el anuncio de `35.199.192.0/19` y responda a las consultas que el
hub le reenvía para `onprem_dns_domain`; y que on-premises resuelva las zonas de GCP por las IP
de `dns_inbound_forwarder_ips`.
Dónde: `stages/3-networks/dns.tf:13`, `modules/dns/main.tf:92`.
Si falla: en modo simulado ya hay camino: la política jerárquica delega `35.199.192.0/19` a
`onprem-sim` (`delegate-dns-onprem-sim`) y su política de red lo permite
(`module.firewall_onprem_sim`); falta crear a mano la VM DNS con la IP de `onprem_dns_servers`
(punto 36). Con on-premises real, revisar el anuncio y el firewall del lado on-premises
(propuesta).

**8. Rango del plano de control de GKE.**
Qué: si el clúster se crea con Private Service Connect, `gke_master` (`10.X.38.0/28`) queda
reservado sin uso.
Dónde: `modules/gke/main.tf:47`.
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
Dónde: todas las raíces; marcadores de `modules/gke/main.tf:144`, `modules/backup-dr/main.tf:21`,
`modules/network-spoke/main.tf:159`.
Si falla: cada diferencia perpetua se corrige en el módulo (no con `ignore_changes` a ciegas);
para el destroy, `deletion_policy = "DELETE"` y `deletion_protection = false` en dev.

**12. Protección de rama, comprobaciones obligatorias y revisores de `common` y `prod`.**
Qué: que el plan de GitHub del equipo permita proteger `main` con las seis comprobaciones
obligatorias de `pr.yml` (incluida `plan-gate`) y revisores obligatorios en los entornos
`common` y `prod`; y que la configuración se haga de verdad. Nada de esto está en el
repositorio: hasta que una persona lo configure, ni `plan-gate` ni los entornos bloquean nada.
Dónde: lista completa de lo que se configura en GitHub en [`pipeline.md`](pipeline.md) §2
(variables y entornos) y §4 (protección de rama, nombres exactos de las comprobaciones, revisores
y plan de GitHub); ADR 0025.
Si falla: sin revisores obligatorios, `common` y `prod` se aplicarían sin aprobación; no encender
`GCP_ENABLED` hasta resolverlo (propuesta).

---

## 2. Agregados por los ADR

Los ADR proponen estas entradas porque no tenían una propia en §12.

**13. Migración del estado local de la etapa 0 (ADR 0008).**
Qué: que `terraform init -migrate-state` copie el estado local al bucket y que el agente de Cloud
Storage del proyecto semilla tenga `cryptoKeyEncrypterDecrypter` sobre la llave `state` antes de
crear el bucket.
Dónde: `stages/0-bootstrap/main.tf:199`; runbook [01](runbooks/01-arranque-etapa-0.md).
La consulta del agente por número de proyecto es el punto 27.
Si falla: el permiso puede tardar en propagarse: repetir el apply (lo dice el código). La
migración se repite mientras exista el `terraform.tfstate` local.

**14. Banderas y roles condicionados de Cloud SQL (ADR 0015).**
Qué: que la API acepte `cloudsql.iam_authentication`, `pgaudit.log` con varias clases y los
roles `cloudsql.client`/`cloudsql.instanceUser` condicionados a la instancia, y que se entre con
un token de IAM.
Dónde: `modules/cloud-sql/main.tf:10` y `:366`. La cuenta de la etapa 5 asigna esos roles a
`workload`, `run` y `mig` (según el cómputo encendido) con el `projectIamAdmin` condicionado que
le da la etapa 4 sobre el proyecto de servicio (`stages/4-projects/envs/*/iam.tf`,
`workloads_iam_admin_condition`; ya no es una concesión de la etapa 1 en la carpeta).
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
Dónde: `modules/cloud-run/main.tf:34`.
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
`roles/compute.networkUser`, `roles/compute.networkViewer` y
`roles/container.hostServiceAgentUser`), además de `compute.xpnAdmin` y `projectCreator`
(`stages/1-org/iam.tf`, `stage_grants` y `stage_delegated_project_iam`). `roles/browser` ya no
se pide: el README de la etapa 4 supone que `xpnAdmin` basta para leer la carpeta y el host.
Lo que queda por verificar en GCP: puntos 28, 29 y 43.

**20. `roles/certificatemanager.editor` para `<prefix>-tf-5-workloads`. Resuelto en el código
(21 nov 2026).**
Era: el balanceador interno (`enable_internal_lb`) crea un certificado de Certificate Manager y
la etapa 1 no asignaba ese rol.
Ahora (corregido otra vez el mismo día): la etapa 1 ya no da a `5-workloads` ningún rol de
carpeta (las carpetas también contienen el host `net-spoke`). El rol está en
`workloads_project_roles` de `stages/4-projects/envs/*/iam.tf`, que la etapa 4 asigna sobre cada
proyecto de servicio que crea.

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
proyecto donde la persona tenga `serviceusage.services.use` (propuesta). En una organización
nueva puede no haber ninguno: si el apply ya creó el proyecto semilla y habilitó sus APIs,
sirve ese, y se repite el apply (runbook 01, paso 3).

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

**25. Imagen de Cloud Run en un registro regional. Resuelto en el código (21 nov 2026).**
Era: el ejemplo de prod usaba `us-central1-docker.pkg.dev/...`; con la región primaria caída, el
servicio de DR no podría descargarla.
Ahora: la etapa 4 crea un repositorio multirregional por aplicación
(`<prefix>-<env>-app-<app>-images-us`, ADR 0024) y el ejemplo de prod usa
`us-docker.pkg.dev/...-images-us/...` (`cloud_run_image`). Lo que queda por verificar en GCP:
puntos 41 y 42.

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
Dónde: `stages/0-bootstrap/main.tf:121` (proyecto semilla); `modules/log-export/main.tf:29`
(variable opcional `project_number`, que la etapa 1 pasa para el proyecto `logging`);
`stages/4-projects/envs/*/service_agents.tf:59`.
Si falla: sin indicación en el código. Propuesta: volver a consultar con el ID y crear el
proyecto en un apply previo con `-target` del módulo del proyecto.

**28. Concesiones delegadas de `projectIamAdmin` (HYPOTHESIS).**
Qué: dos concesiones con la condición
`api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([...])`:
- la etapa 1 da a `<prefix>-tf-4-projects` `roles/resourcemanager.projectIamAdmin` en las
  carpetas `dev`, `qa` y `prod`, limitado a `roles/compute.networkUser`,
  `roles/compute.networkViewer` y `roles/container.hostServiceAgentUser` (lo que la etapa 4
  asigna en el host `net-spoke`, que no crea);
- la etapa 4 da a `<prefix>-tf-5-workloads` el mismo rol sobre cada proyecto de servicio (no en
  la carpeta), limitado a `roles/cloudsql.client` y `roles/cloudsql.instanceUser` (módulo
  `cloud-sql`, recurso `login`).
Verificar que la condición se acepte en una carpeta y en un proyecto, que la de carpeta se
evalúe al cambiar el IAM de los proyectos de abajo, y que esas cuentas no puedan asignar otros
roles.
Dónde: `stages/1-org/iam.tf:115` (`stage_delegated_project_iam`);
`stages/4-projects/envs/*/iam.tf` (`workloads_iam_admin_condition`); README de las etapas 1 y 4.
Si falla: sin indicación en el código. Propuesta: para la etapa 4, asignar los roles en el host
desde la etapa 3 (dueña del proyecto), con PR revisado por seguridad.

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

## 3.5 Agregados por la ronda de correcciones del 21 nov 2026

Lo que dejaron por comprobar en GCP las correcciones de la revisión independiente (ADR 0021 a
0026).

**31. Bucket de estado en doble región (ADR 0022).**
Qué: si se usa `state_bucket_dual_regions`, que las dos regiones formen una doble región
configurable válida dentro de `state_bucket_location`, con `rpo = "ASYNC_TURBO"` y la llave del
llavero `us`. Con el valor por defecto (`US`, multirregión) no aplica.
Dónde: `stages/0-bootstrap/main.tf:196`.
Si falla: la API lo valida al crear; dejar `state_bucket_dual_regions = []` (multirregión). La
ubicación no se cambia después de crear el bucket.

**32. Política de denegación de la carpeta `bootstrap` (ADR 0023).**
Qué: que `google_iam_deny_policy.bootstrap_folder` niegue a la cuenta de `1-org` también
`folders.setIamPolicy` sobre la propia carpeta (la documentación solo dice que se hereda hacia
abajo); que la API de políticas de denegación (IAM v2) acepte las credenciales de usuario de
quien corre la etapa 0 sin proyecto de cuota explícito; y que esa persona tenga
`roles/iam.denyAdmin` en la organización (runbook 01).
Dónde: `stages/0-bootstrap/deny_policy.tf:22`.
Si falla: sin indicación en el código. Para la cuota, ver punto 22.

**33. Permisos de los roles personalizados de la etapa 0 (ADR 0015 y 0023).**
Qué: que todos los permisos de `<prefix>TfKmsSecretIamGranter` (`kms_secret_iam_granter`) y de
`<prefix>TfSecretContainerAdmin` (`secret_container_admin`) se admitan en roles personalizados
de organización, y que basten a las etapas 4 y 2.
Dónde: `stages/0-bootstrap/service_accounts.tf:212` y `:238`.
Si falla: sin indicación en el código; quitar el permiso rechazado y revisar si la etapa lo
necesita (propuesta).

**34. Tema de hallazgos de SCC con `enforce_in_transit` (ADR 0018).**
Qué: que SCC siga publicando en `<prefix>-common-ops-scc-findings` con
`allowed_persistence_regions = [primary_region]` y `enforce_in_transit = true` (publica por el
extremo global de Pub/Sub).
Dónde: `stages/1-org/main.tf:172`.
Si falla: sin indicación en el código. Propuesta: quitar `enforce_in_transit` y documentar que
un mensaje podría procesarse fuera de la región de su llave.

**35. Rol personalizado de organización asignado en un proyecto (HYPOTHESIS).**
Qué: que la etapa 1 pueda asignar en el proyecto `security` los roles personalizados de
organización de la etapa 0 (`kms_secret_iam_role_id` a `4-projects`, `secret_container_admin`
a `2-security`), referidos como `organizations/<org>/roles/<id>`.
Dónde: `stages/1-org/iam.tf` (`stage_grants`, línea 93 y 69); sin marcador en el código.
Si falla: sin indicación.

**36. Reenvío DNS en modo simulado con una VM DNS (ADR 0006).**
Qué: con una VM DNS creada a mano en `onprem-sim` en la IP de `onprem_dns_servers`, que una
consulta de un spoke para `onprem_dns_domain` siga zona de peering → zona de reenvío del hub →
VPN → `onprem-sim` y que la respuesta vuelva a `35.199.192.0/19` por la ruta anunciada por BGP;
y que la regla `delegate-dns-onprem-sim` y `module.firewall_onprem_sim` lo dejen pasar.
Dónde: `stages/3-networks/firewall.tf:90`, `stages/3-networks/dns.tf:13`; punto 7.
Si falla: revisar la delegación de la política jerárquica (punto 39) y los anuncios de BGP.

**37. Dos VPN y su preferencia (ADR 0022).**
Qué: que on-premises reciba los anuncios de las dos VPN y prefiera la primaria (prioridad 100
frente a `vpn_dr_route_priority`, 200), que al caer la primaria el tráfico pase a la de DR, y
que las cuatro sesiones BGP del hub queden activas (con on-premises simulado, también las del
router de `onprem-sim` en `dr_region`).
Dónde: `stages/3-networks/vpn.tf:127`.
Si falla: sin indicación en el código; revisar `vpn_dr_bgp_ranges` y la prioridad anunciada.

**38. Regreso asimétrico entre las dos VPN.**
Qué: con enrutamiento global, un flujo hacia la región de DR puede entrar por la VPN primaria y
volver por la de DR; un firewall con estado en on-premises debe admitirlo.
Dónde: `stages/3-networks/README.md`, "Enrutamiento con dos VPN" (el marcador está en el
README, no en un `.tf`).
Si falla: ajustar el firewall de on-premises (fuera del repositorio).

**39. URL de `target_resources` sin diferencia perpetua (HYPOTHESIS).**
Qué: la regla `delegate-dns-onprem-sim` usa como `target_resources` la URL
`https://www.googleapis.com/compute/v1/projects/<hub>/global/networks/<onprem-sim>`; que la API
la devuelva igual y el segundo plan no muestre cambios.
Dónde: `stages/3-networks/firewall.tf` (`onprem_sim_network_url`); sin marcador en el código.
Si falla: usar la forma que devuelva la API (propuesta); queda cubierto por el punto 11.

**40. Zonas `gcr.io`, `pkg.dev` y `run.app` por el VIP (ADR 0026).**
Qué: que un nodo de GKE descargue imágenes de `pkg.dev` y que una llamada a un servicio
`*.run.app` desde el spoke llegue por el VIP de `google_apis_vip` (en prod, dentro del
perímetro de VPC-SC).
Dónde: `stages/3-networks/envs/*/dns.tf:27`.
Si falla: sin indicación en el código; en dev y qa se puede probar `google_apis_vip = "private"`.

**41. CMEK del repositorio de Artifact Registry (ADR 0024).**
Qué: que el agente de Artifact Registry tenga `cryptoKeyEncrypterDecrypter` sobre la llave
`artifacts` antes de crear el repositorio y que una llave de la multirregión `us` se acepte para
un repositorio de esa multirregión.
Dónde: `stages/4-projects/envs/*/artifacts.tf:40`.
Si falla: repetir el apply si es propagación de IAM (propuesta).

**42. Binary Authorization con la imagen de la aplicación (ADR 0024).**
Qué: que un despliegue de Cloud Run y un pod de GKE con una imagen del repositorio de la
aplicación pasen, y que una imagen de otro registro se rechace con
`ENFORCED_BLOCK_AND_AUDIT_LOG`. En prod, además, que Binary Authorization funcione con el
perímetro forzado (`binaryauthorization.googleapis.com` no está en
`vpc_sc_restricted_services`). La prueba de extremo a extremo y los ayudantes de Terratest usan
por defecto la imagen pública `us-docker.pkg.dev/cloudrun/container/hello`, que esta política
rechaza (§5).
Dónde: `stages/4-projects/envs/*/artifacts.tf:88`.
Si falla: revisar `binary_authorization_allowlist_patterns`; para las pruebas, copiar la imagen
al repositorio de la aplicación con una identidad de `artifact_registry_publishers` (punto 53).

**43. `networkViewer` en el host basta a la etapa 5 (ADR 0023).**
Qué: que `compute.networkViewer` en el host más `networkUser` por subred basten para crear Cloud
SQL, Memorystore y Filestore con IP privada (PSA) desde el proyecto de servicio.
Dónde: `stages/4-projects/envs/*/iam.tf:213`.
Si falla: la alternativa documentada en el código es `networkUser` en el host (todas las
subredes), que se decide en revisión.

**44. On-premises llega al balanceador interno de DR (ADR 0005 y 0022).**
Qué: con `allow_global_access = true`, que on-premises alcance la IP del balanceador interno de
`dr_region` por la VPN de la región primaria y por la de DR.
Dónde: `modules/load-balancer/main.tf:463`.
Si falla: sin indicación en el código.

**45. Backup and DR frente a la configuración de respaldos de Cloud SQL.**
Qué: con `backup_plan_managed = true` (etapa 5 con `enable_backup`), que después de asociar el
plan un segundo plan no muestre cambios en `settings.backup_configuration`; y que la API acepte
`log_retention_days` (`sql_log_retention_days`, 7 por defecto) y la recuperación a un punto en el
tiempo cubra esos días.
Dónde: `modules/cloud-sql/main.tf:98`, `modules/backup-dr/main.tf:51`.
Si falla: el código indica agregar `ignore_changes` sobre ese bloque.

**46. Enlace de Workload Identity (ADR 0012).**
Qué: que `google_service_account_iam_member.workload_identity` se cree con el pool
`<proyecto>.svc.id.goog` del primer clúster y que un pod con la cuenta de Kubernetes
`<gke_workload_namespace>/<gke_workload_ksa_name>` (anotada con
`iam.gke.io/gcp-service-account`) obtenga la identidad de la cuenta `workload` y entre a Cloud
SQL por IAM. HYPOTHESIS: durante la conmutación con la región primaria caída, leer
`module.gke["primary"]` en el plan podría fallar.
Dónde: `stages/5-workloads/envs/*/compute.tf` (recurso `workload_identity`); sin marcador en el
código.
Si falla: sin indicación; en la conmutación, `-refresh=false` o `-target` (propuesta, runbook 04).

**47. Permisos de la etapa 4 para el repositorio y la política.**
Qué: que la cuenta de la etapa 4, como creadora del proyecto de servicio, pueda crear el
repositorio, su IAM y la política de Binary Authorization; y si el agente de GKE necesita
`roles/compute.securityAdmin` en el host para sus reglas de firewall.
Dónde: `stages/4-projects/envs/*/README.md`, sección `VERIFICAR-EN-APPLY` (el marcador está en el
README, no en un `.tf`).
Si falla: el README indica `roles/artifactregistry.admin` y
`roles/binaryauthorization.policyEditor` en el proyecto; para GKE, crear en la etapa 3 las reglas
que GKE reporte.

**48. Estabilidad de la huella del plan (ADR 0025).**
Qué: que un segundo plan sin cambios reales en el medio dé la misma huella
(`scripts/plan-fingerprint.py`) en cada raíz; un valor que el proveedor recalcule en cada plan
haría fallar el apply (nunca aplicar algo no revisado).
Dónde: [`pipeline.md`](pipeline.md) §1.2.
Si falla: excluir de la huella el atributo inestable, con revisión de seguridad (propuesta).

**49. Recursos no administrados: formatos de Cloud Asset y lista de permitidos.**
Qué: el formato de `name` que devuelve Cloud Asset para cada tipo y que
`scripts/unmanaged-allowlist.txt` cubra lo que crean GKE, los MIG y los servicios
administrados. El trabajo está construido y probado con datos de ejemplo, pero no se ha corrido
contra una carpeta real.
Dónde: [`pipeline.md`](pipeline.md) §1.3; `scripts/unmanaged-resources.py`.
Si falla: agregar reglas con su motivo, nunca un tipo completo sin razón.

**50. Cuenta de auditoría y prueba de humo de dev.**
Qué: que la cuenta `GCP_AUDIT_SERVICE_ACCOUNT` (creada a mano) tenga los roles de solo lectura
de [`pipeline.md`](pipeline.md) §3 y que `TestDevSmoke` pase después del apply de dev.
Dónde: [`pipeline.md`](pipeline.md) §1.2 y §3; `tests/e2e/smoke_test.go`.
Si falla: ajustar los roles de la cuenta; si la prueba falla, qa no se aplica.
Agregado el 23 nov 2026 (revisión sin GCP; todo HYPOTHESIS salvo lo que dice "comprobado"):
- Comprobado en el código: ninguna etapa habilitaba `networkmanagement.googleapis.com` y las
  Connectivity Tests se crean en el proyecto host de dev. Ahora la habilita
  `stages/3-networks/envs/*/main.tf` (lista `apis` del proyecto). Falta verificar que con la
  API en el host baste (y no haga falta también en el proyecto de la cuenta de auditoría).
- Comprobado en el código: los roles de la cuenta sobre carpetas, hub, host de dev y proyectos
  de servicio de dev no se pueden asignar antes de la primera ejecución, porque esos recursos
  los crea el pipeline. Orden en `pipeline.md` §3 y runbook 01, "Primera ejecución".
- La comprobación dev → on-premises exige un túnel VPN en cada traza y, después de él, solo
  admite el descarte `FIREWALL_RULE` (`routedThroughVPN`, `tests/e2e/connectivity_test.go`).
  `onprem-sim` no tiene ninguna VM en `192.168.0.10` (§5): si la API termina la traza con otra
  causa (por ejemplo, una de dirección interna desconocida), la prueba falla aunque la ruta
  exista. Si pasa: revisar la traza, seguir con `omitir_prueba_de_humo = true` y ajustar la
  lista de causas admitidas con un PR revisado por seguridad (`tests/e2e/` es suyo).
- Un paso `VIEWER_PERMISSION_MISSING` falla la prueba: indica que a la cuenta le falta lectura
  sobre el proyecto de ese paso. La comprobación Internet → balanceador recorre recursos del
  proyecto de servicio de dev, donde la lista de `pipeline.md` §3 solo da `cloudsql.viewer`;
  si aparece ese paso, agregar `roles/compute.viewer` ahí (propuesta).

**51. Primera corrida de `pr.yml` (ADR 0021 y 0025).**
Qué: que la pata `estático (terraform 1.9.8)` pase con `--skip test` y que `plan-gate` dé verde
sin GCP y rojo cuando falle un `plan <raíz>`. Esta documentación no tiene evidencia de una
corrida de los flujos corregidos en GitHub (no comprobado). En local, el 2026-11-21 y con el
binario 1.9.8, `bash scripts/check.sh --skip test,checkov` dio PASS en los 61 objetivos (detalle
en el ADR 0021); checkov no depende de la versión de Terraform.
Dónde: `.github/workflows/pr.yml`; [`pipeline.md`](pipeline.md) §1.1.
Si falla: corregir el flujo antes de marcar las comprobaciones como obligatorias (punto 12).

**52. Vuelta de DR con `dr_teardown` (runbook 04).**
Qué: que el apply con `dr_active = true` y `dr_teardown = true` cambie en el lugar
`deletion_protection` a `false` en `module.gke["dr"]` y `module.cloud_run["dr"]` (y solo en
ellos; en Cloud Run es un PATCH del servicio vivo), y que el apply siguiente con
`dr_active = false` y `dr_teardown = false` juntos destruya el cómputo y el balanceador interno
de DR sin el error de protección del proveedor. Que el proveedor lea la protección del estado
al borrar está comprobado en su fuente, no en GCP: la revisión del 22 nov 2026 encontró
`d.Get("deletion_protection")` en el Delete del clúster y del servicio de la versión 6.50.0
(`resource_container_cluster.go:4859`, `resource_cloud_run_v2_service.go:1773`), y el binario
trae los mensajes "Cannot destroy cluster because deletion_protection is set to true" y "cannot
destroy service without setting deletion_protection=false and running `terraform apply`"
(`grep`, 21 nov 2026). Ningún apply lo ha ejercido: las pruebas solo planean los dos pasos con
proveedores simulados. `dr_teardown` solo se admite con `dr_active = true` (validación), así
que no puede quedar encendido después de la vuelta.
Dónde: `stages/5-workloads/envs/*/compute.tf` (`teardown`), `modules/gke/main.tf:16`,
`modules/cloud-run/main.tf:18`; sin marcador en el código.
Si falla: sin indicación en el código; el clúster o el servicio de DR quedan en el estado y el
plan sigue proponiendo destruirlos hasta que se resuelva.

**53. Publicación de imágenes a través del perímetro (ADR 0024).**
Qué: que una identidad de `artifact_registry_publishers` haga `docker push` al repositorio de su
aplicación (writer sobre el repositorio) y, en prod, que la regla de entrada
`<prefix>-prod-<app>-artifact-push` (solo `artifactregistry.googleapis.com`, solo el proyecto de
servicio) lo deje pasar con el perímetro forzado y lo registre en dry-run; que un `group:` se
acepte en `identities` (VPC-SC documenta límites para grupos en reglas de entrada). El bloqueo
anterior está resuelto en el código: el perímetro del módulo `vpc-sc` ignora sus
`ingress_policies` (`status` y `spec`) y la regla de las cuentas de etapa es un recurso
`..._ingress_policy` / `..._dry_run_ingress_policy` aparte, así que el apply de 2-security ya
no quita la regla de los publicadores. Falta comprobar en el apply que las reglas de las dos
etapas convivan en el mismo perímetro (cada recurso modifica la lista con el etag del
perímetro).
Dónde: `stages/4-projects/envs/*/vpc_sc.tf:56`, `stages/4-projects/envs/*/artifacts.tf`
(`writer`).
Si falla: sin indicación en el código; con un grupo rechazado, usar cuentas de servicio.

**54. Certificado interno de DR emitido antes de un incidente (ADR 0022).**
Qué: que con `enable_dr = true` y `dr_active = false` el certificado regional de Certificate
Manager de `dr_region` quede `ACTIVE` sin un balanceador que lo use, después de crear los
registros de `internal_lb_dns_authorization_records_by_region`; y si los registros
`PER_PROJECT_RECORD` de las dos regiones coinciden para el mismo dominio y proyecto
(HYPOTHESIS: no comprobado).
Dónde: `stages/5-workloads/envs/*/load_balancing.tf:241`.
Si falla: crear los registros que falten; si el certificado no se emite sin balanceador, el
paso 7 del runbook 04 vuelve a contar su emisión dentro del RTO.

---

## 3.6 Agregados por la revisión del 23 nov 2026

**55. Primera ejecución de `apply.yml` con los valores de ejemplo (HYPOTHESIS).**
Qué: lo que no trae `GCP_TFVARS_JSON` se toma de los `terraform.tfvars.example`, y varios
marcadores de ejemplo nombran cosas que no existen. Se espera, sin haberlo visto en GCP, que:
- `5-workloads` falle al crear el servicio de Cloud Run (`enable_cloud_run = true` en los tres
  ejemplos) porque `cloud_run_image` apunta a un repositorio de ejemplo y, aun con el nombre
  real, el repositorio lo crea la etapa 4 en esa misma ejecución y está vacío; lo mismo la
  plantilla del MIG de qa y prod con `mig_image = projects/example-images/...`;
- `4-projects` falle al asignar `roles/artifactregistry.writer` al publicador de ejemplo
  (`bnt-ci-app@example-cicd…`, cuenta inexistente);
- `1-org` falle al asignar roles a los grupos `@example.com`, y que un
  `directory_customer_id` de ejemplo deje `iam.allowedPolicyMemberDomains` apuntando a otro
  cliente;
- el clúster de GKE de prod rechace un `gke_authenticator_security_group` que no existe.
Comprobado sin GCP (proveedores simulados, 23 nov 2026): con `enable_gke`, `enable_mig` y
`enable_cloud_run` en `false` (y `enable_internal_lb = false` en prod) la raíz de `5-workloads`
planea sin errores (`primera_ejecucion_sin_computo` y `prod_primera_ejecucion_sin_computo`).
Dónde: [`pipeline.md`](pipeline.md) §2, "Marcadores de los ejemplos" y "Primera ejecución";
runbook [01](runbooks/01-arranque-etapa-0.md), "Primera ejecución de `apply.yml`";
`stages/*/terraform.tfvars.example`.
Si falla: corregir el valor en `GCP_TFVARS_JSON` y lanzar `apply.yml` de nuevo (las raíces ya
aplicadas dan "sin cambios"). Un apply que falla a medias deja en el estado lo que sí creó.

---

## 3.7 Agregados por los controles del CIS del 23 nov 2026

Puntos que deja el cierre de los huecos del CIS que no dependen de GCP
([`cumplimiento-cis.md`](cumplimiento-cis.md), ADR 0027).

**56. Evaluación del CIS después del primer apply.**
Qué: el procedimiento de [`cumplimiento-cis.md`](cumplimiento-cis.md) §6. Con SCC activo
(punto 2): en Compliance, activar el marco "CIS GCP Foundations Benchmark v3.0" en la
organización y revisar la pestaña Monitor; en Findings, filtrar `state="ACTIVE" AND
(severity="HIGH" OR severity="CRITICAL")` y traducir cada control a la 5.0 con la columna "3.0"
del mapa. Para los controles que el marco no cubre, juntar la evidencia que lista §6 (salidas de
`gcloud` y capturas) y la de los controles manuales del runbook
[01](runbooks/01-arranque-etapa-0.md) ("Controles manuales del CIS"). El resultado se anota en el
mapa: cada fila "Código" o "Manual" que se confirme y cada hallazgo nuevo.
Dónde: [`cumplimiento-cis.md`](cumplimiento-cis.md) §6; runbook 01; criterio "Sin hallazgos
críticos ni altos en Security Command Center" del README.
Si falla: un hallazgo de un control que el mapa da por cubierto se corrige en el código; uno de
una desviación del ADR 0027 se documenta ahí (con una regla de silencio acotada si se decide,
propuesta).

**57. Contactos esenciales de la organización (CIS 1.17).**
Qué: que `1-org` cree un contacto por grupo de `essential_contacts` en la organización con
`roles/essentialcontacts.admin` y el proyecto semilla como proyecto de cuota (la API
`essentialcontacts` está en `seed_apis`); que la API acepte correos de grupo y el idioma
`essential_contacts_language` (`es`); y que el detector `ESSENTIAL_CONTACTS_NOT_CONFIGURED`
(Premium, sin escaneo en tiempo real) no marque la organización en el siguiente escaneo.
Dónde: `stages/1-org/essential_contacts.tf:8`; `stages/0-bootstrap/service_accounts.tf`
(`org_roles` de `1-org`); `stages/0-bootstrap/main.tf` (`seed_apis`).
Si falla: sin indicación en el código. Si la API rechaza un grupo, usar un buzón de rol por
categoría (propuesta); si rechaza el idioma, `essential_contacts_language = "en"`.

**58. Métricas de log y alertas de auditoría (CIS 2.5 a 2.12).**
Qué: en los 11 proyectos del diseño con una aplicación (semilla, cuatro de `common`, tres
`net-spoke` y tres de servicio):
- que los detectores `OWNER_NOT_MONITORED`, `AUDIT_CONFIG_NOT_MONITORED`,
  `CUSTOM_ROLE_NOT_MONITORED`, `FIREWALL_NOT_MONITORED`, `ROUTE_NOT_MONITORED`,
  `NETWORK_NOT_MONITORED`, `BUCKET_IAM_NOT_MONITORED` y `SQL_INSTANCE_NOT_MONITORED` no marquen
  ningún proyecto: los filtros reproducen el texto de la página de hallazgos de SHA, pero en una
  sola línea (la página los muestra en varias), y la coincidencia exacta es HYPOTHESIS;
- que cada serie llegue con el tipo de recurso de la condición (`global`, salvo `gcs_bucket` en
  `bucket_iam` y `cloudsql_database` en `sql_instance`), con un evento de prueba en dev (por
  ejemplo, crear y borrar con `gcloud` una política de firewall de red vacía y un rol
  personalizado de prueba) que dispare la alerta y llegue el correo;
- que la API acepte cada alerta justo después de crear su métrica;
- que el grupo de `security_alert_email` acepte correo de Cloud Monitoring;
- que los cambios a la política de firewall **jerárquica** (de la organización) no llegan a la
  métrica `firewall_policy` de ningún proyecto (HYPOTHESIS: su registro de auditoría es de la
  organización); el ADR 0027 lo deja como límite.
Dónde: `modules/audit-alerts/main.tf:11`, `:22`, `:150`, `:182`;
`stages/0-bootstrap/audit_alerts.tf:5`; `stages/1-org/audit_alerts.tf`;
`stages/3-networks/envs/*/audit_alerts.tf`; `stages/4-projects/envs/*/audit_alerts.tf`.
Si falla: filtro no reconocido: escribirlo con los saltos de línea de la página de SHA (el
módulo lo arma con `join(" ", …)`); tipo de recurso distinto: corregir `resource_type` en
`local.metrics`; alerta rechazada: repetir el apply (lo dice el código); correo rechazado:
permitir remitentes externos en el grupo (propuesta).

**59. OS Login en los metadatos del proyecto (CIS 4.4).**
Qué: que `OS_LOGIN_DISABLED` no marque los proyectos con Compute Engine (el metadato
`enable-oslogin = TRUE` lo pone `project-factory` donde la API `compute` está habilitada); que SSH
por IAP a una VM del MIG funcione con `roles/compute.osLogin` (hoy nadie lo tiene: es un acceso
de emergencia que se otorga y se retira a mano); y que los nodos de GKE Standard hereden el
metadato sin romper el clúster. HYPOTHESIS: un proyecto sin Compute Engine no se evalúa.
Dónde: `modules/project-factory/main.tf:93`; `gcloud compute project-info describe
--project=<proyecto>` (metadato `enable-oslogin`).
Si falla: si el detector sigue marcando, la alternativa documentada es la política
`compute.requireOsLogin` (serían diez políticas de organización; `modules/project-factory/README.md`).

**60. Cloud Asset para `drift.yml` (CIS 2.14).**
Qué: el trabajo de recursos no administrados de `drift.yml` corre `gcloud asset
search-all-resources` con la cuenta `GCP_AUDIT_SERVICE_ACCOUNT` y sin `--billing-project`. Para
una cuenta de servicio, el proyecto de cuota es el proyecto donde vive
([documentación de Google](https://docs.cloud.google.com/docs/quotas/quota-project)), y la API
tiene que estar habilitada ahí. Antes de este cambio ningún código habilitaba
`cloudasset.googleapis.com` (solo lo pedía a mano `pipeline.md` §3, paso 4): con la cuenta en el
proyecto semilla, ahora la habilita la etapa 0. Verificar en la primera ejecución diaria que el
listado de las cuatro carpetas termina sin "API not enabled", y que
`scripts/unmanaged-resources.py` reconoce como administradas las métricas de log de
`audit-alerts` (HYPOTHESIS: el `id` de `google_logging_metric` es solo el nombre y Cloud Asset
la nombra `projects/<proyecto>/metrics/<nombre>`; el script arma esa forma).
Dónde: `stages/0-bootstrap/main.tf:31`; `modules/project-factory/main.tf` (`baseline_apis`);
`.github/workflows/drift.yml`, trabajo `unmanaged`; `pipeline.md` §3, paso 4.
Si falla: si el error nombra otro proyecto, habilitar la API ahí o pasar
`--billing-project=<proyecto-semilla>` en `drift.yml` con `serviceusage.serviceUsageConsumer`
para la cuenta (propuesta); si las métricas salen como no administradas, ajustar la forma
construida en `build_managed` del script.

**61. Registro de Cloud DNS en `onprem-sim` (CIS 2.13).**
Qué: que `google_dns_policy.onprem_sim` se adjunte a la VPC `onprem-sim` del proyecto
`net-hub` sin chocar con la política del hub (cada red admite una sola), que
`DNS_LOGGING_DISABLED` no marque ninguna red (hub, spokes y `onprem-sim`) y que la VM DNS de
`onprem-sim` siga resolviendo igual (HYPOTHESIS: una política solo con registro no cambia la
resolución).
Dónde: `stages/3-networks/dns.tf:46`.
Si falla: sin indicación en el código; con `simulate_onprem = false` la política no existe.

**62. Flow logs al 100 % en prod, hub y `onprem-sim` (CIS 3.10).**
Qué: que `VPC_FLOW_LOGS_SETTINGS_NOT_RECOMMENDED` (hay que activarlo, es Premium) no marque las
subredes de prod, del hub ni de `onprem-sim` (muestreo 1.0, intervalo de 5 s, todos los
metadatos) y que sí marque las de dev y qa (0.5, desviación aceptada en el ADR 0027); y medir
durante una semana el volumen de flow logs de prod contra el supuesto de
[`estimacion-de-costos.md`](estimacion-de-costos.md) §1.
Dónde: `modules/network-hub/variables.tf:104` y `modules/network-spoke/variables.tf:115`
(`flow_log_sampling = 1` por defecto); `stages/3-networks/envs/*/terraform.tfvars.example`.
Si falla: si el costo de prod no se sostiene, bajar el muestreo y reabrir la decisión del ADR
0027.

---

## 4. Marcadores `VERIFICAR-EN-APPLY` del código

Conteo al 23 nov 2026 (después de los controles del CIS), desde `gcp-datacenter/`:

```bash
grep -rn "VERIFICAR-EN-APPLY" modules stages --include=*.tf | wc -l                       # 119
grep -rln "VERIFICAR-EN-APPLY" modules stages --include=*.tf | wc -l                      # 56 archivos
grep -rn "VERIFICAR-EN-APPLY" modules --include=*.tf | wc -l                              # 51
grep -rn "VERIFICAR-EN-APPLY" stages --include=*.tf | grep -v /envs/ | wc -l              # 23
grep -rn "VERIFICAR-EN-APPLY" stages --include=*.tf | grep /envs/ | wc -l                 # 45 (15 por entorno)
```

Las raíces de `envs/{dev,qa,prod}` tienen sus marcadores en las mismas líneas (comprobado el
21 nov 2026 comparando archivo y línea de los tres entornos: 15 líneas, cada una presente en los
tres), así que se listan una vez con `envs/*` y "(x3)": las 119 líneas son 89 marcadores
distintos (51 en módulos y 38 en etapas). Fuera de los `.tf`, los README de algunas raíces
tienen marcadores propios (al final de esta sección); `tests/` tiene otros cuatro en sus `.tf`,
fuera de este conteo. "Si falla" cita el código cuando lo dice; si no, la entrada dice "sin
indicación".

### Etapa 0 (`stages/0-bootstrap`)

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `deny_policy.tf:22` | Política de denegación de la carpeta `bootstrap`: también niega `folders.setIamPolicy` sobre la propia carpeta, y la API de IAM v2 acepta las credenciales de usuario sin proyecto de cuota (punto 32) | Ver punto 32 |
| `audit_alerts.tf:5` | Métricas y alertas de auditoría del semilla creadas con las credenciales de la persona de la etapa 0 (puntos 22 y 58) | Ver punto 58 |
| `main.tf:31` | `gcloud asset search-all-resources` de `drift.yml` con el semilla como proyecto de cuota (punto 60) | Ver punto 60 |
| `main.tf:121` | Que la API de Cloud Storage acepte el número del proyecto semilla al consultar su agente (punto 27) | Ver punto 27 |
| `main.tf:196` | Doble región válida en `state_bucket_dual_regions` (punto 31) | Ver punto 31 |
| `main.tf:199` | Permiso del agente de Cloud Storage sobre la llave al crear el bucket (punto 13) | Repetir el apply (propagación de IAM) |
| `service_accounts.tf:92` | `init`/`plan`/`apply` del backend con las condiciones de §6.2 (punto 1) | Carpetas administradas con IAM propio por prefijo |
| `service_accounts.tf:212` | Permisos del rol personalizado `<prefix>TfKmsSecretIamGranter` admitidos en roles personalizados (punto 33) | Ver punto 33 |
| `service_accounts.tf:238` | Permisos del rol personalizado `<prefix>TfSecretContainerAdmin` admitidos en roles personalizados (punto 33) | Ver punto 33 |
| `wif.tf:36` | Que el mapeo de `attribute.environment` no falle en trabajos sin entorno de GitHub | Sin indicación en el código. Se notaría en el primer trabajo `plan 1-org` (sin entorno): falla el paso de autenticación. Propuesta: quitar del mapeo `attribute.environment` (ningún `principalSet` ni condición lo usa hoy) y volver a aplicar la etapa 0 a mano (runbook 01, "Cambios posteriores") |

### Etapa 1 (`stages/1-org`)

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `essential_contacts.tf:8` | Contactos esenciales de la organización con grupos y `essential_contacts_language` (punto 57) | Ver punto 57 |
| `iam.tf:115` | Condición con `iam.googleapis.com/modifiedGrantsByRole` aceptada en una carpeta y evaluada al cambiar el IAM de los proyectos de abajo (punto 28) | Ver punto 28 |
| `main.tf:118` | Que `iam.allowedPolicyMemberDomains` no rechace los `principalSet://` de WIF en cambios futuros | Sin indicación |
| `main.tf:139` | Activación de SCC (punto 2) | Paso manual del runbook 01 |
| `main.tf:172` | SCC publica en el tema con `enforce_in_transit = true` (punto 34) | Ver punto 34 |
| `main.tf:182` | Que la cuenta de SCC pueda publicar en el tema de hallazgos | Sin indicación |
| `providers.tf:4` | Que todas las APIs acepten el proyecto semilla como proyecto de cuota | Sin indicación |

### Etapa 2 (`stages/2-security`)

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `providers.tf:4` | Que todas las APIs acepten el proyecto de cuota | Sin indicación |

### Etapa 3, hub (`stages/3-networks`)

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `dns.tf:13` | Resolución de `onprem_dns_domain` desde un spoke con la VM DNS de `onprem-sim` (puntos 7 y 36) | Ver punto 36 |
| `dns.tf:46` | Registro de Cloud DNS en la VPC `onprem-sim` y detector `DNS_LOGGING_DISABLED` (punto 61) | Ver punto 61 |
| `firewall.tf:73` | Que el tráfico delegado con `goto_next` llegue a la política del spoke, que las verificaciones de salud lleguen a los backends con `lb_backend` y que IAP solo entre a las VM con `iap_ssh` | Sin indicación |
| `firewall.tf:90` | Que la VM DNS de `onprem-sim` responda a una consulta de un spoke y la respuesta vuelva por la ruta anunciada (punto 36) | Ver punto 36 |
| `vpn.tf:127` | Anuncios de las dos VPN, preferencia por la primaria y paso a la de DR (punto 37) | Ver punto 37 |

### Etapa 3, spokes (`stages/3-networks/envs/*`)

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `dns.tf:27` (x3) | Imágenes de `pkg.dev` y llamadas a `*.run.app` por el VIP elegido (punto 40) | Ver punto 40 |
| `dns.tf:63` (x3) | Que la cuenta de la etapa pueda adjuntar la zona del entorno a la VPC hub (`dns.networks.bindPrivateDNSZone` en net-hub) y que on-premises la resuelva por el reenvío entrante | Sin indicación |

### Etapa 4 (`stages/4-projects/envs/*`)

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `artifacts.tf:40` (x3) | CMEK del repositorio de Artifact Registry (punto 41) | Ver punto 41 |
| `artifacts.tf:88` (x3) | Binary Authorization: la imagen del repositorio pasa y otra se rechaza (punto 42) | Ver punto 42 |
| `iam.tf:213` (x3) | `networkViewer` en el host más `networkUser` por subred bastan a la etapa 5 para PSA (punto 43) | `networkUser` en el host, decidido en revisión |
| `iam.tf:274` (x3) | Que `tagUser` sobre el valor baste al agente de GKE y a `<n>@cloudservices` para crear nodos y VM con etiquetas | Puede pedir además `tagUser` sobre la llave o `roles/resourcemanager.tagHoldAdmin` |
| `service_agents.tf:10` (x3) | Que `generateServiceIdentity` acepte `sqladmin`, `file`, `redis` y `gkebackup` | Quitar el servicio de la lista (su agente existe al habilitar la API) |
| `service_agents.tf:12` (x3) | Que los agentes de `container`, `compute` y `run` existan justo después de habilitar sus APIs | Agregar esos servicios a la lista |
| `service_agents.tf:59` (x3) | Que la API de Cloud Storage acepte el número del proyecto de servicio al consultar su agente (punto 27) | Ver punto 27 |
| `vpc_sc.tf:10` (x3) | CMEK de `security` con el perímetro forzado (punto 4) | Ver punto 4 |
| `vpc_sc.tf:56` (x3) | `docker push` de un publicador por la regla de entrada de Artifact Registry; grupos en `identities` (punto 53) | Ver punto 53 |

### Etapa 5 (`stages/5-workloads/envs/*`)

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `load_balancing.tf:98` (x3) | Que el mismo grupo de instancias y el mismo NEG sin servidor sirvan a la vez al balanceador externo y al interno | Sin indicación |
| `load_balancing.tf:193` (x3) | El certificado administrado se activa cuando los registros A de `domain_names` apuntan a `lb_ip_address` | Crear los registros en la zona pública (fuera del repositorio) |
| `load_balancing.tf:241` (x3) | Registros de `internal_lb_dns_authorization_records_by_region` (las dos regiones con `enable_dr`) y certificado interno de DR `ACTIVE` sin balanceador (punto 54) | Ver punto 54 |
| `operations.tf:54` (x3) | Formato del recurso de Cloud SQL en la asociación de Backup and DR y roles de la cuenta de la bóveda | Sin indicación |

### Módulos

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `audit-alerts/main.tf:11` | Que SHA reconozca los filtros de una sola línea y dé por buenas las alertas (punto 58) | Ver punto 58 |
| `audit-alerts/main.tf:22` | Tipo de recurso con que llegan las series de cada métrica (`global`, `gcs_bucket`, `cloudsql_database`) (punto 58) | Ver punto 58 |
| `audit-alerts/main.tf:150` | El grupo `security_admins` acepta correo de Cloud Monitoring (punto 58) | Ver punto 58 |
| `audit-alerts/main.tf:182` | Alerta aceptada justo después de crear la métrica (punto 58) | Repetir el apply (lo dice el código) |
| `backup-dr/main.tf:19` | API `backupdr` habilitada y bóveda en otra región que acepte respaldos de VM y Cloud SQL | Sin indicación |
| `backup-dr/main.tf:21` | El destroy de dev falla mientras la bóveda tenga respaldos dentro de la retención forzada | El procedimiento de destroy debe contemplarlo (esperar la retención o `enable_backup = false` en dev, propuesta) |
| `backup-dr/main.tf:35` | Plan de Cloud SQL (`sqladmin.googleapis.com/Instance`) en el proveedor 6.x y roles de la cuenta de la bóveda (salida `vault_service_account`) | Otorgar los roles en la etapa 4 o 5 |
| `backup-dr/main.tf:51` | `log_retention_days` aceptado y recuperación a un punto en el tiempo de esos días (punto 45) | Ver punto 45 |
| `backup-dr/main.tf:85` | Backup for GKE en otra región, complemento activo y permiso del agente de `gkebackup` sobre la llave | Sin indicación |
| `cloud-run/main.tf:9` | Salida directa a la VPC con red y subred del host como `projects/<host>/...` | Sin indicación |
| `cloud-run/main.tf:34` | `invoker_iam_disabled` frente a la política de organización (punto 16) | Ver punto 16 |
| `cloud-sql/main.tf:10` | `pgaudit.log` con varias clases; la réplica acepta las mismas banderas | Ver punto 14 |
| `cloud-sql/main.tf:98` | Segundo plan sin cambios en `backup_configuration` con el plan de Backup and DR asociado (punto 45) | `ignore_changes` sobre ese bloque (lo dice el código) |
| `cloud-sql/main.tf:201` | Agente de Cloud SQL con permiso sobre `kms_key` (lo da la etapa 4) | Sin indicación |
| `cloud-sql/main.tf:203` | Conexión de PSA de la red existente antes del create | Sin indicación |
| `cloud-sql/main.tf:330` | Réplica REGIONAL entre regiones con CMEK; retraso de replicación por debajo de 15 min | Si el retraso supera 15 min, el objetivo de RPO no se cumple (README del módulo) |
| `cloud-sql/main.tf:366` | Roles condicionados por `resource.name` y entrada con token IAM (punto 14) | Ver punto 14 |
| `compute-mig/main.tf:72` | Etiquetas seguras de la plantilla en las instancias y reglas `lb_backend` aplicadas | Sin indicación |
| `compute-mig/main.tf:164` | `max_surge_fixed` igual al número de zonas del MIG regional | Sin indicación |
| `dns/main.tf:92` | El filtro devuelve las IP de reenvío entrante (y solo esas) al terminar el apply | Sin indicación |
| `filestore/main.tf:48` | Permiso del agente sobre la llave, PSA desde el proyecto de servicio sobre la red del host, `deletion_protection_enabled` en el tier | Sin indicación |
| `firewall/main.tf:21` | Formato de `purpose_data` y etiquetas de organización en la política jerárquica | Sin indicación |
| `firewall/main.tf:26` | Si la API admite `enable_logging` en `goto_next` | Sin indicación |
| `gke/main.tf:47` | Plano de control con Private Service Connect (punto 8) | Ver punto 8 |
| `gke/main.tf:59` | Endpoint privado alcanzable desde la Shared VPC y los rangos autorizados | Bastión en el spoke o endpoint por DNS (no construido, README del módulo) |
| `gke/main.tf:144` | `node_config` del pool por defecto eliminado sin diferencias en el segundo plan | Ya se ignora en `lifecycle` |
| `gke/main.tf:231` | Nodos con etiquetas seguras del proyecto host | Ver `iam.tf:274` de la etapa 4 |
| `hybrid-connectivity/main.tf:143` | Interfaces y sesiones BGP de los attachments DEDICATED y PARTNER | Sin indicación |
| `load-balancer/main.tf:187` | Certificado administrado ACTIVE cuando los registros A apuntan a la IP; puede tardar hasta 60 min | Crear los registros A |
| `load-balancer/main.tf:357` | Certificado interno tras los registros de `dns_authorization_records`; una CA pública no emite para `*.internal` | Usar `certificate_manager_certificates` |
| `load-balancer/main.tf:463` | On-premises llega al balanceador interno de DR por las dos VPN (punto 44) | Ver punto 44 |
| `log-export/main.tf:29` | Que la API de Cloud Storage acepte el número de proyecto (`project_number`) al consultar el agente (punto 27) | Ver punto 27 |
| `log-export/main.tf:65` | Bloqueo sobre un bucket ya creado (punto 15) | Ver punto 15 |
| `log-export/main.tf:97` | Permiso del agente de Cloud Storage sobre la llave al crear el bucket | Repetir el apply |
| `memorystore/main.tf:65` | Permiso del agente sobre la llave y PSA sobre la red del host | Sin indicación |
| `network-hub/variables.tf:104` | Flow logs al 100 % sin hallazgo de `VPC_FLOW_LOGS_SETTINGS_NOT_RECOMMENDED` y volumen contra la estimación (punto 62) | Ver punto 62 |
| `network-spoke/variables.tf:115` | Lo mismo en los spokes; dev y qa con 0.5 sí se marcan (punto 62) | Ver punto 62 |
| `network-spoke/main.tf:159` | Destroy de la conexión de PSA después de borrar las instancias de la etapa 5 | Sin indicación; esperar a que servicenetworking libere el peering y repetir (propuesta) |
| `network-spoke/main.tf:182` | Dos spokes no crean su peering a la vez; las rutas BGP llegan al spoke (punto 6) | El pipeline aplica los entornos en serie |
| `observability/main.tf:55` | Los buzones de `notification_emails` existen y aceptan las alertas | Sin indicación |
| `observability/main.tf:203` | La alerta de memoria de VM necesita Ops Agent | Sin él la condición queda sin datos |
| `observability/main.tf:288` | SLI por solicitudes con los filtros del balanceador y `select_slo_burn_rate` con tráfico real | Sin indicación |
| `org/main.tf:20` | Ubicaciones permitidas (punto 3) | Ver punto 3 |
| `org/main.tf:50` | Agentes de servicio de Google siguen recibiendo roles con `iam.allowedPolicyMemberDomains` | Sin indicación |
| `project-factory/main.tf:37` | Proyecto sin red default y sin error al intentar borrarla | Sin indicación |
| `project-factory/main.tf:93` | OS Login en los metadatos del proyecto: el detector `OS_LOGIN_DISABLED` no lo marca y IAP + OS Login dan SSH con `roles/compute.osLogin` (punto 59) | Ver punto 59 |
| `secrets/main.tf:21` | Agente de Secret Manager con permiso sobre las llaves antes de crear los secretos | Lo da la etapa que llama al módulo (etapa 2) |
| `storage/main.tf:86` | Agente de Cloud Storage con permiso sobre la llave; llave de `us` para un bucket con `custom_placement_config` | Sin indicación |
| `storage/main.tf:89` | `gcp.resourceLocations` y la doble región (punto 3) | Ver punto 3 |
| `vpc-sc/main.tf:42` | Perímetro en dry-run sin bloque `status`; paso a forzado en un solo plan | Sin indicación |
| `vpc-sc/main.tf:134` | Regla de entrada del pipeline (punto 5), como recurso aparte en dry-run y forzado | Ver punto 5 |

### Marcadores solo en README

No entran en el conteo de los `.tf` de arriba.

| Archivo | Qué verificar | Si falla |
|---|---|---|
| `stages/3-networks/README.md`, "Enrutamiento con dos VPN" | Regreso asimétrico entre las dos VPN (punto 38) | Ver punto 38 |
| `stages/3-networks/envs/*/README.md` (x3), "Roles de la cuenta de servicio" | Que la cuenta que crea `net-spoke` quede como dueña del proyecto (punto 30) | Ver punto 30 |
| `stages/4-projects/envs/*/README.md` (x3), "Roles de la cuenta de servicio de la etapa" | Que `compute.xpnAdmin` incluya `folders.get` y `projects.get` y que `tagAdmin` en la carpeta se herede a las llaves de etiqueta de `net-spoke` (punto 29) | Ver punto 29 |
| `stages/4-projects/envs/*/README.md` (x3), sección `VERIFICAR-EN-APPLY` | Permisos de la etapa 4 para el repositorio y la política de Binary Authorization; `compute.securityAdmin` del agente de GKE en el host (punto 47). Las demás viñetas de esa sección repiten marcadores de los `.tf` de arriba | Ver punto 47 |

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
existe pero nadie responde hasta que se cree a mano una VM DNS en `onprem-sim` con la IP de
`onprem_dns_servers` (`stages/3-networks/dns.tf:13`). El camino de red ya está construido
(delegación `delegate-dns-onprem-sim` y `module.firewall_onprem_sim`); la prueba es el punto 36.

**WIF filtra solo por repositorio.** El proveedor confía en el ID numérico del repositorio y del
dueño (ya no en el nombre, ADR 0023), pero cualquier rama o flujo de ese repositorio puede tomar
la identidad de las cuentas de etapa (`stages/0-bootstrap/wif.tf`; [`pipeline.md`](pipeline.md)
§5). Mitigación no construida: condicionar por `attribute.ref` o `attribute.environment` y
separar cuentas de solo lectura para los `plan` de los PR.

**Riesgos residuales de la identidad del pipeline (ADR 0023).** La cuenta de `4-projects` tiene
`secretmanager.secrets.setIamPolicy` en `security` y podría darse `secretAccessor`; la de
`1-org` conserva roles de organización amplios fuera de la carpeta `bootstrap`. Los frena la
revisión del plan antes del apply (ADR 0025), no un control técnico.

**Una sola región en México.** Si se exigiera residencia de datos, `northamerica-south1` no
tiene región de DR en el país (ADR 0002): habría que aceptar DR entre zonas o una región de DR
fuera de México, y reabrir el ADR.

**Memorystore sin AUTH.** AUTH queda apagado para no guardar la cadena en el estado (ADR 0015,
`modules/memorystore`). La caché confía en la red: IP privada, firewall del spoke, TLS y el
perímetro en prod. Si se exige autenticación por cliente: Memorystore for Redis Cluster con IAM.

**El secreto compartido de la VPN vive en el estado cifrado.** En los dos modos el valor queda en
el estado de `3-networks/hub` (CMEK de la etapa 0, legible por la cuenta de `3-networks`;
ADR 0006). Rotarlo recrea el túnel (`shared_secret` fuerza el reemplazo); con on-premises real se
rota de a un túnel con `onprem_vpn_secret_version_overrides` mientras los otros tres mantienen
la conectividad (README de `stages/3-networks`).

**Nombres de objetos del bucket de estado visibles para todas las cuentas de etapa.** La
cláusula `resource.type == "storage.googleapis.com/Bucket"` que permite listar deja ver los
nombres (no el contenido) de todos los prefijos (contrato §6.2, ADR 0010). Si importa: carpetas
administradas.

**Planes de ejemplo de Conftest, parte escritos a mano.** `policies/fixtures/` tiene 27 planes;
13 son recortes de un `terraform show -json` real de un ejemplo sin GCP (`ls policies/fixtures
| grep -c _real_` → 13, 21 nov 2026) y los demás están escritos a mano. Ninguno sale de un plan
contra GCP: con GCP, regenerar al menos uno por regla desde un plan real.

**Recursos no administrados sin correr.** El trabajo de `drift.yml` que compara Cloud Asset
Inventory con los estados está construido y probado con datos de ejemplo
(`scripts/testdata/unmanaged/`), pero no se ha corrido contra una carpeta real (punto 49).

**Terratest nocturno en rojo hasta configurar sus compuertas.** Sin `TEST_ALLOW_EXPENSIVE`,
`TEST_ALLOW_ORG` y sus datos, las pruebas se omiten y `terratest.yml` falla porque el máximo de
omitidas es 0 (`TERRATEST_MAX_SKIPS`; [`pipeline.md`](pipeline.md) §1.4).

**Imagen de las pruebas rechazada por Binary Authorization.** `tests/e2e/config.example.json` y
`tests/helpers/env.go` usan por defecto `us-docker.pkg.dev/cloudrun/container/hello`, que la
política de la etapa 4 rechaza (solo admite el repositorio de la aplicación). Antes de correr la
prueba de extremo a extremo, copiar la imagen al repositorio y apuntar la configuración a él
(punto 42). La configuración de ejemplo de la prueba también deja `enable_vpn_dr` en su valor
por defecto: crea ocho túneles.

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
