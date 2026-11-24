# Pendientes del primer apply

Todo lo que este repositorio no puede comprobar sin GCP. Nada se ha aplicado: cada entrada es
una expectativa de diseño hasta que el primer apply la confirme o la tumbe. Cuando una entrada
se verifique, se marca con la fecha, el comando y el resultado ("Verificado el AAAA-MM-DD con
`<comando>`: <resultado>" o "Falló el ..."); cuando falle, se corrige el código y se actualiza el
ADR que corresponda.

Diseño que describe esta lista: un solo proyecto de GCP (ADR 0029), con las etapas
`0-bootstrap` (manual), `1-base`, `2-networks` (hub y spokes `envs/<env>`) y
`3-workloads/envs/<env>`. El diseño anterior, de varios proyectos, vive en la rama
`archivo/multiproyecto`, con el texto anterior de los puntos marcados como obsoletos.

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
   puntos 56 a 62; y
   [3.8 Apagado fuera de horario (ADR 0028)](#38-apagado-fuera-de-horario-adr-0028),
   puntos 70 a 81; y
   [3.9 Agregados por el flujo de destroy](#39-agregados-por-el-flujo-de-destroy),
   puntos 85 a 89; y
   [3.10 Agregados por el rediseño a un solo proyecto (24 nov 2026)](#310-agregados-por-el-rediseño-a-un-solo-proyecto-24-nov-2026),
   puntos 90 a 122; y
   [3.11 Agregados por los arreglos de R2 (24 nov 2026)](#311-agregados-por-los-arreglos-de-r2-24-nov-2026),
   puntos 123 a 151.
4. [Marcadores `VERIFICAR-EN-APPLY` del código](#4-marcadores-verificar-en-apply-del-código),
   por etapa y módulo.
5. [Alcance no cubierto y limitaciones conocidas](#5-alcance-no-cubierto-y-limitaciones-conocidas).

Los ADR, runbooks y README citan estos puntos por número ("punto 11"): no se renumeran. Un
punto que se corrige en el código sin necesitar GCP no se borra: queda con la marca
**Resuelto en el código** y la fecha, para que las referencias sigan apuntando a algo. Resuelto
en el código no es verificado: lo que el cambio deja por comprobar en GCP pasa a un punto
nuevo. Un punto que el rediseño a un solo proyecto deja sin objeto tampoco se borra: queda con
la marca **Obsoleto por el ADR 0029 (un solo proyecto)** y el motivo, y lo que todavía haya que
comprobar pasa a otro punto.

Conteo al 24 nov 2026 (código de `6d27623`), desde `gcp-datacenter/` (cada punto empieza con
`**<número>. `):

```bash
grep -cE '^\*\*[0-9]+\. ' docs/pendientes-apply.md                                    # 141 puntos
grep -E '^\*\*[0-9]+\. ' docs/pendientes-apply.md | grep -c 'Obsoleto por el ADR 0029'  # 15 obsoletos
grep -E '^\*\*[0-9]+\. ' docs/pendientes-apply.md | grep -c 'Resuelto en el código'     # 9 resueltos en el código
grep -E '^\*\*[0-9]+\. ' docs/pendientes-apply.md \
  | grep -vc -e 'Obsoleto por el ADR 0029' -e 'Resuelto en el código'                   # 117 abiertos
```

Los marcadores del código se cuentan en la §4.

---

## 1. Lista inicial del contrato (§12)

**1. Listado del backend `gcs` con IAM condicionado por prefijo.**
Qué: que `terraform init`, `plan` y `apply` de cada raíz funcionen con `objectAdmin` sobre su
prefijo y `objectViewer` sobre los prefijos que lee, con la cláusula
`resource.type == "storage.googleapis.com/Bucket"` que permite listar. Las ocho cuentas de raíz
escriben un prefijo cada una (`1-base`, `2-networks/hub`, `2-networks/<env>` y
`3-workloads/<env>`); la de lectura `tf-read` lee todo el bucket sin condición (punto 122).
Dónde: `stages/0-bootstrap/service_accounts.tf:258` (`local.stage_roots` y las expresiones de
estado); ADR 0010; ADR 0029 §3; contrato §6.2.
Si falla: pasar a managed folders de Cloud Storage con IAM propio por prefijo; plan B, un bucket
por etapa (ADR 0010).

**2. Activación de Security Command Center.**
Qué: el proveedor 6.x no tiene recurso para activar SCC; se activa a mano en el proyecto. Que
se pueda activar en un proyecto sin organización es HYPOTHESIS (ADR 0029 §7). Verificar que,
activado y con `enable_scc_notification = true` (por defecto `false`), `1-base` cree la
notificación de proyecto `<prefix>-common-ops-scc-findings` y que la cuenta de SCC pueda
publicar en el tema.
Dónde: `stages/1-base/main.tf:203` (notificación) y `:194` (tema con `enforce_in_transit`,
punto 34); runbook [01](runbooks/01-arranque-etapa-0.md), paso de SCC.
Si falla: con `enable_scc_notification = false`, `1-base` no crea el tema ni la notificación y
la activación queda como paso manual del runbook 01. Si la notificación falla con SCC activo,
revisar el IAM del tema `scc_findings` (propuesta).

**3. `gcp.resourceLocations` frente a la doble región y los recursos globales.**
Qué: solo con organización (`org_id` en `0-bootstrap`): que los grupos `in:<región>-locations`
más `additional_allowed_locations` admitan los llaveros de la multirregión `us`, el bucket de
doble región, el balanceador global, las zonas DNS y demás recursos globales. Sin organización
la política no existe y no hay nada que verificar. Desde el 24 nov 2026 la política la aplica la
persona de la etapa 0 (punto 125).
Dónde: `modules/org/main.tf:22`, `modules/storage/main.tf:89`, `stages/0-bootstrap/org.tf:12`
(variable `additional_allowed_locations` de `0-bootstrap`).
Si falla: agregar la ubicación que falte a `additional_allowed_locations` de `0-bootstrap`
(propuesta), que la persona vuelva a aplicar la etapa 0 y repetir el apply de la raíz que falló.

**4. CMEK de `security` desde prod con el perímetro forzado.** Obsoleto por el ADR 0029 (un solo proyecto).
Ya no hay proyecto de llaves aparte: las llaves de cada entorno están en el mismo proyecto que
sus recursos (`stages/1-base/kms.tf`) y el perímetro opcional rodea el proyecto entero y nunca
se fuerza en el código (punto 5).

**5. Regla de entrada del perímetro para las cuentas del pipeline.**
Qué: solo con organización y política de acceso (`access_policy_id`): que el perímetro opcional
de VPC-SC alrededor del proyecto, siempre en dry-run (`enforced = false` en el código), registre
violaciones sin bloquear y que la regla de entrada de las nueve cuentas del pipeline quede en
él. Desde el 24 nov 2026 lo crea la persona de la etapa 0, no una cuenta del pipeline (punto
126; el 101 quedó resuelto en el código).
Dónde: `modules/vpc-sc/main.tf:140`; `stages/0-bootstrap/org.tf:34`; ADR 0029 §1.
Si falla: el perímetro en dry-run no bloquea nada; leer las violaciones registradas y ajustar la
regla. Forzarlo no está construido.

**6. Propagación de rutas.**
Qué: que las rutas aprendidas por BGP en el hub lleguen a los spokes por el peering (el hub
exporta rutas personalizadas, el spoke las importa) y que on-premises reciba y alcance los /16
de los spokes.
Dónde: `modules/network-spoke/main.tf:186`; anuncios en `stages/2-networks/vpn.tf` (las dos
VPN: punto 37); ADR 0003.
Si falla: revisar `bgp_advertised_ranges` (salida del hub) y la exportación del peering
`hub_to_spoke` (propuesta).

**7. Reenvío de DNS.**
Qué: que on-premises reciba el anuncio de `35.199.192.0/19` y responda a las consultas que el
hub le reenvía para `onprem_dns_domain`; y que on-premises resuelva las zonas de GCP por las IP
de `dns_inbound_forwarder_ips`.
Dónde: `stages/2-networks/dns.tf:12`, `modules/dns/main.tf:92`.
Si falla: en modo simulado ya hay camino: la política de firewall de red de `onprem-sim` admite
el DNS que llega desde `35.199.192.0/19` (`stages/2-networks/firewall.tf:42`), y desde el 24 nov
2026 la VM DNS con la IP de `onprem_dns_servers` es código opcional (`onprem_dns_vm = true`,
`stages/2-networks/onprem_dns.tf`; puntos 36 y 129). Con on-premises real, revisar el anuncio y
el firewall del lado on-premises (propuesta). El DNS entrante en la VPC hub es el punto 112.

**8. Rango del plano de control de GKE.**
Qué: si el clúster se crea con Private Service Connect, `gke_master` (`10.X.38.0/28`) queda
reservado sin uso.
Dónde: `modules/gke/main.tf:47`.
Si falla: no es una falla; anotar que el rango queda libre y quitar la regla
`allow-gke-control-plane` del spoke si sobra (propuesta).

**9. Cuotas.**
Qué: CPU, direcciones IP, redes, peerings por red, routers, clústeres, instancias de Cloud SQL y
demás cuotas de las dos regiones, que ahora comparten en el mismo proyecto los tres entornos, el
hub y `onprem-sim` (ADR 0029 §10), frente a todo desplegado (prod completo más dev y qa). La
documentación no da los valores por defecto. Las pruebas de integración de Terratest corren en
otro proyecto (punto 119).
Dónde: `stages/3-workloads/envs/*/terraform.tfvars.example`; ADR 0029 §10; la guía del
colaborador pide revisarlas antes de `0-bootstrap`.
Si falla: pedir aumento de cuota antes del apply de prod; mientras tanto, dev y qa en modo
mínimo (propuesta).

**10. Tiempo del despliegue 0 → 3.**
Qué: duración total frente al objetivo de 90 minutos.
Dónde: `apply.yml` (`1-base`, el hub y, por entorno, el spoke y `3-workloads`) más la etapa 0
manual; la prueba de extremo a extremo lo mide (`tests/README.md`, `TEST_E2E_ENFORCE_DURATION`).
Si falla: medir por raíz y documentar cuál domina (propuesta).

**11. Segundo `plan` sin cambios y `destroy` de dev sin huérfanos.**
Qué: `terraform plan -detailed-exitcode` sale con 0 en todas las raíces después del primer
apply; el destroy de dev borra `3-workloads/envs/dev` y, con la entrada `incluir_red`, después
`2-networks/envs/dev`, sin dejar recursos del entorno. En el proyecto único no se borra ningún
proyecto, y lo del entorno que vive en `1-base` (llaves, repositorios y contenedores de
secretos) se queda a propósito (ADR 0029 §8).
**Destroy construido en el código** (sin correr): `.github/workflows/destroy.yml` lo hace con la
cuenta de cada raíz, el mismo plan, huella y aprobación que `apply.yml`, y termina buscando
huérfanos en el proyecto con Cloud Asset Inventory (`--scope=projects/<ID>`, por la etiqueta
`env` o el prefijo `<prefix>-<env>-`; [`pipeline.md`](pipeline.md) §1.5). Lo que queda por
comprobar en GCP está en los puntos 85, 86, 87, 89 y 118.
Dónde: todas las raíces; marcadores de `modules/gke/main.tf:145`, `modules/backup-dr/main.tf:21`,
`modules/network-spoke/main.tf:160`; `.github/workflows/destroy.yml`,
`scripts/destroy-guard.sh`, `scripts/destroy-plan-check.py`, `scripts/destroy-orphans.py`.
Si falla: cada diferencia perpetua se corrige en el módulo (no con `ignore_changes` a ciegas);
para el destroy, antes de lanzarlo, `deletion_protection = false` en `3-workloads/envs/<env>`
(en `GCP_TFVARS_JSON`) y un `apply.yml` para que llegue al estado (si no,
`destroy-plan-check.py` detiene la raíz antes de borrar); para lo que bloquea GCP, puntos 86, 87
y 89.

**12. Protección de rama, comprobaciones obligatorias y revisores de `common` y `prod`.**
Qué: que el plan de GitHub del equipo permita proteger `main` con las comprobaciones
obligatorias de `pr.yml` (incluida `plan-gate`) y revisores obligatorios en los entornos
`common` y `prod`; que la configuración se haga de verdad; y que existan los cuatro entornos de
GitHub con esos nombres exactos (`common`, `dev`, `qa` y `prod`): las cuentas de `1-base` y del
hub solo aceptan tokens del entorno `common`, y las de cada entorno solo del suyo
(`attribute.deploy`, que además exige `main` y un flujo de `.github/workflows/` de este
repositorio; ADR 0029 §3, punto 123), así que sin el entorno el trabajo `apply` no obtiene
credenciales. Nada de esto está en el repositorio: hasta que una persona lo configure, ni
`plan-gate` ni los entornos bloquean nada. Las ramas de despliegue de los entornos son el punto
121.
Dónde: lista de lo que se configura en GitHub en [`pipeline.md`](pipeline.md) (variables,
entornos, protección de rama, nombres exactos de las comprobaciones, revisores y plan de
GitHub); ADR 0025; ADR 0029 §3.
Si falla: sin revisores obligatorios, `common` y `prod` se aplicarían sin aprobación; no encender
`GCP_ENABLED` hasta resolverlo (propuesta).

---

## 2. Agregados por los ADR

Los ADR proponen estas entradas porque no tenían una propia en §12.

**13. Migración del estado local de la etapa 0 (ADR 0008).**
Qué: que `terraform init -migrate-state` copie el estado local al bucket y que el agente de Cloud
Storage del proyecto tenga `cryptoKeyEncrypterDecrypter` sobre la llave `state` antes de crear
el bucket. El agente se consulta con el ID del proyecto, que ya existe
(`stages/0-bootstrap/main.tf:190`).
Dónde: `stages/0-bootstrap/main.tf:266`; runbook [01](runbooks/01-arranque-etapa-0.md).
Si falla: el permiso puede tardar en propagarse: repetir el apply (lo dice el código). La
migración se repite mientras exista el `terraform.tfstate` local.

**14. Banderas y roles condicionados de Cloud SQL (ADR 0015).**
Qué: que la API acepte `cloudsql.iam_authentication`, `pgaudit.log` con varias clases y los
roles `cloudsql.client`/`cloudsql.instanceUser` condicionados, y que se entre con un token de
IAM. Desde el 24 nov 2026 esos roles los da `1-base` a `workload`, `run` y `mig`, limitados a
las instancias del entorno (punto 133); `3-workloads` pasa `grant_iam_login_roles = false` al
módulo y `tf-wl-<env>` ya no tiene `projectIamAdmin`. Ver también punto 132.
Dónde: `modules/cloud-sql/main.tf:10` y `:387` (la condición por instancia del módulo, que ya no
se usa desde las raíces); `stages/1-base/runtime_accounts.tf:104`;
`stages/3-workloads/envs/*/data.tf:34`.
Si falla: separar las clases de `pgaudit.log` o quitar la condición de los roles (propuesta).

**15. CMEK y bloqueo del bucket de logs (ADR 0018).**
Qué: permiso del agente de Cloud Storage del proyecto sobre la llave `logs` (llavero común de
`1-base`) antes de crear el bucket, y que `log_retention_locked = true` se aplique sobre un
bucket ya creado sin que un plan posterior intente desbloquearlo.
Dónde: `modules/log-export/main.tf:54` y `:86`; `stages/1-base/main.tf:113`.
Si falla: repetir el apply (propagación de IAM). El bloqueo es irreversible: probarlo primero
con `log_retention_locked = false`.

**16. Cloud Run público detrás del balanceador (ADR 0020).**
Qué: que la URL `run.app` no sea alcanzable desde internet con `invoker_iam_disabled = true`; con
organización y `directory_customer_id`, además, que `invoker_iam_disabled` no choque con
`iam.allowedPolicyMemberDomains`.
Dónde: `modules/cloud-run/main.tf:34`.
Si falla: dejar `public_via_load_balancer = false` y servir por IAP o con tokens de identidad
(alternativas del ADR 0020).

**17. dev y qa siguen usando sus llaves con el perímetro forzado (ADR 0019).** Obsoleto por el ADR 0029 (un solo proyecto).
Era la comprobación inversa del punto 4: con el proyecto único no hay llaves en otro proyecto ni
entornos fuera del perímetro, y el perímetro opcional nunca se fuerza en el código (punto 5).

**18. Proyecto de red de prod dentro del perímetro (ADR 0009).** Obsoleto por el ADR 0029 (un solo proyecto).
No hay proyecto de red aparte: el perímetro opcional tiene un solo recurso, el proyecto.

---

## 3. Otros pendientes detectados al documentar

**19. Permisos de la cuenta de la etapa de proyectos.** Obsoleto por el ADR 0029 (un solo proyecto).
La etapa que creaba los proyectos de aplicación y su cuenta ya no existen; los permisos de
proyecto de cada cuenta los da `0-bootstrap` (`stages/0-bootstrap/service_accounts.tf:11`,
punto 97). Estaba resuelto en el código desde el 21 nov 2026.

**20. `roles/certificatemanager.editor` para la cuenta de cargas.** Obsoleto por el ADR 0029 (un solo proyecto).
El punto trataba qué etapa asignaba el rol en qué proyecto. Ahora está en la lista de
`tf-wl-<env>` de `0-bootstrap` (`workloads_roles`, `stages/0-bootstrap/service_accounts.tf:205`);
que la lista alcance es el punto 97. Estaba resuelto en el código desde el 21 nov 2026.

**21. Comando de migración del README de la etapa 0. Resuelto en el código (21 nov 2026).**
Era: el README de `stages/0-bootstrap` borraba `backend_override.tf` y después llamaba a
`terraform output -raw state_bucket` dentro de `init -migrate-state`. Comprobado sin GCP
(Terraform 1.16.5, configuración mínima con backend `gcs` y override local, 21 nov 2026): con el
override borrado, `terraform output` termina con `Error: Backend initialization required` y el
bucket llega vacío.
Ahora: el README de la etapa toma `STATE_BUCKET` antes de borrar el override, en el mismo orden
que el runbook [01](runbooks/01-arranque-etapa-0.md) y el README del repositorio. La migración
en sí sigue pendiente (punto 13).

**22. Proyecto de cuota de la etapa 0 (HYPOTHESIS).**
Qué: la etapa 0 usa las credenciales de aplicación de una persona con el proyecto mismo como
proyecto de cuota (`billing_project = project_id`). Para el primer plan, `cloudresourcemanager`,
`serviceusage` y `storage` tienen que estar habilitadas en el proyecto; las demás las habilita la
etapa.
Dónde: `stages/0-bootstrap/providers.tf:5`.
Si falla: `gcloud services enable` de la API que falte antes del primer plan (lo dice el
código). Si una API rechaza las credenciales de usuario por el proyecto de cuota,
`gcloud auth application-default set-quota-project <proyecto>` (propuesta; runbook 01).

**23. SCC activo antes de la notificación de `1-base` (HYPOTHESIS).**
Qué: `google_scc_v2_project_notification_config` probablemente falla si SCC no está activado en
el proyecto. Solo se crea con `enable_scc_notification = true`.
Dónde: `stages/1-base/main.tf:203`.
Si falla: activar SCC (runbook 01) y repetir el apply de `1-base`, o dejar
`enable_scc_notification = false`.

**24. Reconciliar la réplica de Cloud SQL después de promoverla.**
Qué: después de `gcloud sql instances promote-replica`, el recurso
`module.cloud_sql.google_sql_database_instance.replica["dr"]` ya no es réplica; el plan
siguiente probablemente propone reemplazarlo (y `deletion_protection` lo impide en prod).
Dónde: `modules/cloud-sql/main.tf` (recurso `replica`, sin `lifecycle`);
`stages/3-workloads/envs/prod/README.md`, "DR".
Si falla: seguir el runbook [04](runbooks/04-conmutacion-a-dr.md) (apply con `-target` de
cómputo y balanceadores durante el incidente) y diseñar la reconciliación en el primer
simulacro.

**25. Imagen de Cloud Run en un registro regional. Resuelto en el código (21 nov 2026).**
Era: el ejemplo de prod usaba `us-central1-docker.pkg.dev/...`; con la región primaria caída, el
servicio de DR no podría descargarla.
Ahora (ADR 0029 §4): `1-base` crea un repositorio por entorno y aplicación
(`<prefix>-<env>-<app>`) en `artifact_registry_location` (`stages/1-base/artifacts.tf`), y el
ejemplo de prod usa la multirregión `us-docker.pkg.dev/<proyecto>/<prefix>-prod-<app>/...`
(`cloud_run_image`). Lo que queda por verificar en GCP: puntos 41 y 42.

**26. Llave de aplicación con guion. Resuelto en el código (21 nov 2026).**
Era: una aplicación con guion tenía proyecto pero no podía tener cargas.
Ahora: `application` de `3-workloads` valida `^[a-z][a-z0-9]{1,7}$` (2 a 8 caracteres, sin
guion; `stages/3-workloads/envs/*/variables.tf`). Con el rediseño, la lista `applications` pasó a
`1-base`, que validaba `^[a-z][a-z0-9]{0,7}$` (1 a 8 caracteres). Resuelto en el código el
2026-11-24 (r2/identidad, commit `90b7163`): `applications` de `1-base` valida la misma
expresión que `3-workloads` (`stages/1-base/variables.tf:114`), así que no queda aplicación con
cuentas en `1-base` que `3-workloads` rechace. Regla de nombres en el runbook
[02](runbooks/02-alta-proyecto-aplicacion.md).

**27. Agente de Cloud Storage consultado por número de proyecto.** Obsoleto por el ADR 0029 (un solo proyecto).
Ninguna raíz crea el proyecto en el mismo plan: `0-bootstrap` consulta el agente con el ID del
proyecto, que ya existe (`stages/0-bootstrap/main.tf:190`). Queda el marcador de
`modules/log-export/main.tf:18`, que solo importa si una raíz pasa la variable opcional
`project_number` (ninguna lo hace).

**28. Concesiones delegadas de `projectIamAdmin` (HYPOTHESIS).**
Qué: dos concesiones de `0-bootstrap` en el proyecto, las dos a `<prefix>-tf-base`, con la
condición `api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([...])`:
- limitada a `base_grantable_roles` (roles de lectura de personas, sin `tagUser`); con ella
  `1-base` escribe también la configuración de auditoría del proyecto, que según el código pasa
  la condición porque no cambia bindings;
- limitada a `runtime_grantable_roles` (roles de las cuentas de ejecución,
  `roles/cloudsql.client`, `roles/cloudsql.instanceUser` y el rol del apagado), que `1-base` da
  a las cuentas de ejecución que crea (puntos 131 a 134).
Desde el 24 nov 2026 (r2/identidad) `tf-wl-<env>` ya no tiene `projectIamAdmin`. Verificar que
la condición se acepte en el proyecto, que deje escribir la configuración de auditoría y que
`tf-base` no pueda asignar otros roles.
Dónde: `stages/0-bootstrap/service_accounts.tf:88` (`delegated_iam`; la lista de personas debe
coincidir con `stages/1-base/iam.tf` y la de ejecución con
`stages/1-base/runtime_accounts.tf`); `stages/1-base/main.tf:56`.
Si falla: sin indicación en el código. Propuesta: la configuración de auditoría pasa a
`0-bootstrap` (la aplica la persona).

**29. Permisos heredados de la cuenta de la etapa de proyectos (HYPOTHESIS).** Obsoleto por el ADR 0029 (un solo proyecto).
No hay jerarquía ni proyecto de red aparte de donde heredar: las cuentas de spoke tienen
`TfNetworkTagManager` en el proyecto y las de cargas `tagUser` solo sobre los valores de su spoke
(puntos 100 y 136).

**30. La cuenta de red quedaba dueña del proyecto del spoke (HYPOTHESIS).** Obsoleto por el ADR 0029 (un solo proyecto).
Ninguna raíz crea proyectos: las cuentas de spoke reciben sus roles de proyecto de
`0-bootstrap` (punto 100).

---

## 3.5 Agregados por la ronda de correcciones del 21 nov 2026

Lo que dejaron por comprobar en GCP las correcciones de la revisión independiente (ADR 0021 a
0026).

**31. Bucket de estado en doble región (ADR 0022).**
Qué: si se usa `state_bucket_dual_regions`, que las dos regiones formen una doble región
configurable válida dentro de `state_bucket_location`, con `rpo = "ASYNC_TURBO"` y la llave del
llavero `us`. Con el valor por defecto (`US`, multirregión) no aplica.
Dónde: `stages/0-bootstrap/main.tf:263`.
Si falla: la API lo valida al crear; dejar `state_bucket_dual_regions = []` (multirregión). La
ubicación no se cambia después de crear el bucket.

**32. Política de denegación de la etapa 0 (ADR 0023).** Obsoleto por el ADR 0029 (un solo proyecto).
Protegía la jerarquía que ya no existe. La reemplazan la etiqueta de protección y la política de
denegación del proyecto (puntos 90 a 93).

**33. Permisos de los roles personalizados de la etapa 0 (ADR 0015 y 0023).**
Qué: que todos los permisos de los cuatro roles personalizados de proyecto
(`<prefix>TfSecretContainerAdmin`, `<prefix>TfServiceAccountManager`,
`<prefix>TfNetworkTagManager` y `<prefix>OffHoursScheduler`) se admitan en roles personalizados
de proyecto y basten a quien los usa (`tf-base`, `tf-net-<env>` y la cuenta `sched` que crea
`1-base`). Desde el 24 nov 2026 (r2/identidad) ya no existen `TfKmsSecretIamGranter` ni
`TfRepositoryIamGranter`.
Dónde: `stages/0-bootstrap/custom_roles.tf:6`; el del apagado, puntos 73 y 134.
Si falla: sin indicación en el código; quitar el permiso rechazado y revisar si la raíz lo
necesita (propuesta).

**34. Tema de hallazgos de SCC con `enforce_in_transit` (ADR 0018).**
Qué: con `enable_scc_notification = true`, que SCC siga publicando en
`<prefix>-common-ops-scc-findings` con `allowed_persistence_regions = [primary_region]` y
`enforce_in_transit = true` (publica por el extremo global de Pub/Sub).
Dónde: `stages/1-base/main.tf:194`.
Si falla: sin indicación en el código. Propuesta: quitar `enforce_in_transit` y documentar que
un mensaje podría procesarse fuera de la región de su llave.

**35. Rol personalizado de organización asignado en un proyecto (HYPOTHESIS).** Obsoleto por el ADR 0029 (un solo proyecto).
Los roles personalizados ahora son de proyecto (`stages/0-bootstrap/custom_roles.tf`) y se
asignan en el mismo proyecto (punto 33).

**36. Reenvío DNS en modo simulado con una VM DNS (ADR 0006).**
Qué: con una VM DNS en `onprem-sim` en la IP de `onprem_dns_servers`, que una consulta de un
spoke para `onprem_dns_domain` siga zona de peering → zona de reenvío del hub → VPN →
`onprem-sim` y que la respuesta vuelva a `35.199.192.0/19` por la ruta anunciada por BGP; y que
la política de firewall de red de `onprem-sim` lo deje pasar. Desde el 24 nov 2026 la VM ya no se
crea a mano: es código opcional del hub (`onprem_dns_vm = true`). Ver también puntos 129 y 130.
Dónde: `stages/2-networks/firewall.tf:42`, `stages/2-networks/dns.tf:12`,
`stages/2-networks/onprem_dns.tf:18`; punto 7.
Si falla: revisar la regla de DNS de la política de `onprem-sim` y los anuncios de BGP.

**37. Dos VPN y su preferencia (ADR 0022).**
Qué: que on-premises reciba los anuncios de las dos VPN y prefiera la primaria (prioridad 100
frente a `vpn_dr_route_priority`, 200), que al caer la primaria el tráfico pase a la de DR, y
que las cuatro sesiones BGP del hub queden activas (con on-premises simulado, también las del
router de `onprem-sim` en `dr_region`).
Dónde: `stages/2-networks/vpn.tf:140`.
Si falla: sin indicación en el código; revisar `vpn_dr_bgp_ranges` y la prioridad anunciada.

**38. Regreso asimétrico entre las dos VPN.**
Qué: con enrutamiento global, un flujo hacia la región de DR puede entrar por la VPN primaria y
volver por la de DR; un firewall con estado en on-premises debe admitirlo.
Dónde: `stages/2-networks/README.md`, "Enrutamiento con dos VPN" (el marcador está en el
README, no en un `.tf`).
Si falla: ajustar el firewall de on-premises (fuera del repositorio).

**39. URL de `target_resources` sin diferencia perpetua (HYPOTHESIS).** Obsoleto por el ADR 0029 (un solo proyecto).
La regla que usaba esa URL era de la política de firewall jerárquica, que sin organización no
existe; `onprem-sim` tiene su propia política de firewall de red asociada a su VPC (ADR 0029 §6).

**40. Zonas `gcr.io`, `pkg.dev` y `run.app` por el VIP (ADR 0026).**
Qué: que un nodo de GKE descargue imágenes de `pkg.dev` y que una llamada a un servicio
`*.run.app` desde el spoke llegue por el VIP de `google_apis_vip` (con organización, dentro del
perímetro opcional de VPC-SC).
Dónde: `stages/2-networks/envs/*/dns.tf:27`.
Si falla: sin indicación en el código; en dev y qa se puede probar `google_apis_vip = "private"`.

**41. CMEK del repositorio de Artifact Registry (ADR 0024).**
Qué: que el agente de Artifact Registry (lo crea `0-bootstrap`, punto 94) tenga
`cryptoKeyEncrypterDecrypter` sobre la llave `artifacts` del entorno antes de crear el
repositorio y que una llave de la multirregión `us` se acepte para un repositorio de esa
multirregión.
Dónde: `stages/1-base/artifacts.tf:89`.
Si falla: repetir el apply si es propagación de IAM (propuesta).

**42. Binary Authorization con la imagen de la aplicación (ADR 0024).**
Qué: que un despliegue de Cloud Run y un pod de GKE con una imagen de un repositorio del
proyecto pasen, y que una imagen de otro registro se rechace con `ENFORCED_BLOCK_AND_AUDIT_LOG`.
La política es una sola para el proyecto (`1-base`). Sin atestadores por entorno (el valor por
defecto), su lista de permitidos tiene los repositorios de los tres entornos: como la lista es
global y una imagen que coincide se admite sin mirar las reglas, una imagen del repositorio de
dev también pasa en los clústeres de prod (desviación del ADR 0029 §4, documentada en el código;
§5). Desde el 24 nov 2026 (r2/identidad) hay un modo opcional con un atestador por entorno
(`binary_authorization_env_attestors`) que lo separa en GKE: punto 139. Las pruebas usan la
imagen pública `us-docker.pkg.dev/cloudrun/container/hello`, que solo pasa si
`binary_authorization_allowlist_patterns` la incluye (punto 120).
Dónde: `stages/1-base/artifacts.tf:163`.
Si falla: revisar `binary_authorization_allowlist_patterns`. Para separar prod: atestadores por
entorno (punto 139); los atestadores no los crea el repositorio.

**43. `networkViewer` en la red compartida basta a la cuenta de cargas (ADR 0023).** Obsoleto por el ADR 0029 (un solo proyecto).
No hay proyecto de red aparte: `tf-wl-<env>` tiene `compute.networkUser` en el proyecto
(`stages/0-bootstrap/service_accounts.tf:210`) y crea los servicios con PSA sobre la VPC del
spoke del mismo proyecto (punto 111).

**44. On-premises llega al balanceador interno de DR (ADR 0005 y 0022).**
Qué: con `allow_global_access = true`, que on-premises alcance la IP del balanceador interno de
`dr_region` por la VPN de la región primaria y por la de DR.
Dónde: `modules/load-balancer/main.tf:463`.
Si falla: sin indicación en el código.

**45. Backup and DR frente a la configuración de respaldos de Cloud SQL.**
Qué: con `backup_plan_managed = true` (`3-workloads` con `enable_backup`), que después de
asociar el plan un segundo plan no muestre cambios en `settings.backup_configuration`; y que la
API acepte `log_retention_days` (`sql_log_retention_days`, 7 por defecto) y la recuperación a un
punto en el tiempo cubra esos días.
Dónde: `modules/cloud-sql/main.tf:103`, `modules/backup-dr/main.tf:53`.
Si falla: el código indica agregar `ignore_changes` sobre ese bloque.

**46. Enlace de Workload Identity (ADR 0012).**
Qué: que `google_service_account_iam_member.workload_identity` se cree con el pool
`<proyecto>.svc.id.goog` y que un pod con la cuenta de Kubernetes
`<app>-<env>/<gke_workload_ksa_name>` (anotada con `iam.gke.io/gcp-service-account`) obtenga la
identidad de la cuenta `workload` y entre a Cloud SQL por IAM. El pool es el mismo para los tres
entornos (ADR 0029 §9). Desde el 24 nov 2026 (r2/identidad) el enlace lo crea `1-base` con
`gke_workload_identity_bindings = true`, el namespace es fijo (`<app>-<env>`) y `3-workloads` ya
no tiene `gke_workload_namespace` ni `gke_workload_ksa_name`; la HYPOTHESIS de leer
`module.gke["primary"]` con la región primaria caída ya no aplica a esta raíz. Ver también punto
135.
Dónde: `stages/1-base/runtime_accounts.tf:232`; `stages/3-workloads/envs/*/service_accounts.tf`
(aviso `workload_identity_enlazada`).
Si falla: sin indicación en el código; revisar el orden del punto 135.

**47. Permisos de la etapa de proyectos para el repositorio y la política.** Obsoleto por el ADR 0029 (un solo proyecto).
El repositorio y la política de Binary Authorization los crea `1-base` con
`roles/artifactregistry.admin` y `roles/binaryauthorization.policyEditor` que le da
`0-bootstrap` (`stages/0-bootstrap/service_accounts.tf:144` y `:145`); que alcancen es el punto
97.

**48. Estabilidad de la huella del plan (ADR 0025).**
Qué: que un segundo plan sin cambios reales en el medio dé la misma huella
(`scripts/plan-fingerprint.py`) en cada raíz; un valor que el proveedor recalcule en cada plan
haría fallar el apply (nunca aplicar algo no revisado). Que el plan de `tf-read` y el del apply
con la cuenta de la raíz coincidan es el punto 117.
Dónde: [`pipeline.md`](pipeline.md) §1.2.
Si falla: excluir de la huella el atributo inestable, con revisión de seguridad (propuesta).

**49. Recursos no administrados: formatos de Cloud Asset y lista de permitidos.**
Qué: el formato de `name` que devuelve Cloud Asset para cada tipo y que
`scripts/unmanaged-allowlist.txt` cubra lo que crean GKE, los MIG y los servicios
administrados. El trabajo está construido y probado con datos de ejemplo, pero no se ha corrido
contra el proyecto real. Que el listado traiga el proyecto mismo es el punto 118.
Dónde: [`pipeline.md`](pipeline.md) §1.3; `scripts/unmanaged-resources.py:54`;
`scripts/unmanaged-allowlist.txt:11`.
Si falla: agregar reglas con su motivo, nunca un tipo completo sin razón.

**50. Cuenta de lectura `tf-read` y prueba de humo de dev.**
Qué: `GCP_AUDIT_SERVICE_ACCOUNT` ya no es una cuenta creada a mano: es `<prefix>-tf-read`, la
salida `read_service_account` de `0-bootstrap`. Tiene en el proyecto `roles/viewer`,
`roles/iam.securityReviewer`, `roles/cloudasset.viewer`, `roles/networkmanagement.admin` y
`roles/serviceusage.serviceUsageConsumer`, y `objectViewer` sobre todo el bucket de estado
(punto 122). La usan el `plan` de `pr.yml` y de `apply.yml` (con `-lock=false`), `drift.yml`, la
prueba de humo y la búsqueda de huérfanos. Verificar que esos roles alcancen para refrescar
cada recurso de cada raíz (también secretos, llaves e IAM) y para las Connectivity Tests, y que
`TestDevSmoke` pase después del apply de dev.
Dónde: `stages/0-bootstrap/service_accounts.tf:233` (`read_roles`);
`.github/workflows/_terraform-root.yml:16`; `tests/e2e/smoke_test.go:37`;
[`pipeline.md`](pipeline.md).
Si falla: agregar a `read_roles` el rol de lectura más chico que falte y volver a aplicar la
etapa 0 a mano (un permiso que falte hace fallar el plan, no lo debilita); si la prueba falla, qa
no se aplica.
Detalle (todo HYPOTHESIS salvo lo que dice "comprobado"):
- Comprobado en el código: `networkmanagement.googleapis.com` la habilita `0-bootstrap`
  (`stages/0-bootstrap/main.tf:58`) y las Connectivity Tests se crean en el proyecto único.
- La comprobación dev → on-premises exige un túnel VPN en cada traza y, después de él, solo
  admite el descarte `FIREWALL_RULE` (`routedThroughVPN`, `tests/e2e/connectivity_test.go`).
  `onprem-sim` no tiene ninguna VM en `192.168.0.10` (§5): si la API termina la traza con otra
  causa (por ejemplo, una de dirección interna desconocida), la prueba falla aunque la ruta
  exista. Si pasa: revisar la traza, seguir con `omitir_prueba_de_humo = true` y ajustar la
  lista de causas admitidas con un PR revisado por seguridad (`tests/e2e/` es suyo).
- Un paso `VIEWER_PERMISSION_MISSING` falla la prueba. Con `roles/viewer` en el único proyecto
  se espera que no aparezca; si aparece, agregar el rol de lectura que nombre el paso
  (propuesta).

**51. Primera corrida de `pr.yml` (ADR 0021 y 0025).**
Qué: que la pata `estático (terraform 1.9.8)` pase con `--skip test` y que `plan-gate` dé verde
sin GCP y rojo cuando falle un `plan <raíz>`. Esta documentación no tiene evidencia de una
corrida de los flujos en GitHub (no comprobado); la corrida local del 21 nov 2026 citada en el
ADR 0021 es del diseño anterior.
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
Dónde: `stages/3-workloads/envs/*/compute.tf:37` y `:110` (`teardown`),
`modules/gke/main.tf:16`, `modules/cloud-run/main.tf:18`; sin marcador en el código.
Si falla: sin indicación en el código; el clúster o el servicio de DR quedan en el estado y el
plan sigue proponiendo destruirlos hasta que se resuelva.

**53. Publicación de imágenes en el repositorio de la aplicación (ADR 0024).**
Qué: que una identidad de `artifact_registry_publishers` haga `docker push` al repositorio de su
entorno y aplicación (`roles/artifactregistry.writer` solo sobre ese repositorio, `1-base`) y
que un `group:` se acepte como miembro. Ya no hay regla de entrada del perímetro para los
publicadores: con organización, el perímetro opcional en dry-run solo registraría un push desde
fuera como violación (punto 5).
Dónde: `stages/1-base/artifacts.tf:139` (`writer`).
Si falla: sin indicación en el código; con un grupo rechazado, usar cuentas de servicio.

**54. Certificado interno de DR emitido antes de un incidente (ADR 0022).**
Qué: que con `enable_dr = true` y `dr_active = false` el certificado regional de Certificate
Manager de `dr_region` quede `ACTIVE` sin un balanceador que lo use, después de crear los
registros de `internal_lb_dns_authorization_records_by_region`; y si los registros
`PER_PROJECT_RECORD` de las dos regiones coinciden para el mismo dominio y proyecto
(HYPOTHESIS: no comprobado).
Dónde: `stages/3-workloads/envs/*/load_balancing.tf:234`.
Si falla: crear los registros que falten; si el certificado no se emite sin balanceador, el
paso 7 del runbook 04 vuelve a contar su emisión dentro del RTO.

---

## 3.6 Agregados por la revisión del 23 nov 2026

**55. Primera ejecución de `apply.yml` con los valores de ejemplo (HYPOTHESIS).**
Qué: lo que no trae `GCP_TFVARS_JSON` se toma de los `terraform.tfvars.example`, y varios
valores de ejemplo nombran cosas que no existen. Se espera, sin haberlo visto en GCP, que:
- `3-workloads` falle al crear el servicio de Cloud Run (`enable_cloud_run = true` en los tres
  ejemplos) porque `cloud_run_image` apunta a un proyecto de ejemplo y, aun con el nombre real,
  el repositorio que crea `1-base` está vacío; lo mismo la plantilla del MIG de qa y prod con
  `mig_image = projects/example-images/...`;
- `1-base` falle al asignar roles a los grupos `@example.com` de `groups`, y que los contactos
  esenciales de ejemplo no lleguen a nadie (`directory_customer_id` ya no pasa por `apply.yml`:
  es de `0-bootstrap`, que aplica la persona);
- el clúster de GKE de prod rechace un `gke_authenticator_security_group` que no existe.
El plan sin cómputo (`enable_gke`, `enable_mig` y `enable_cloud_run` en `false`, y
`enable_internal_lb = false` en prod) lo cubren las pruebas `primera_ejecucion_sin_computo` y
`prod_primera_ejecucion_sin_computo` de `3-workloads`, con proveedores simulados. Desde el 24 nov
2026 (r2/pipeline) `scripts/root-tfvars.py` sale con 2 antes del plan si un valor resuelto lleva
un marcador de los ejemplos (`example.com`, `example-images`, `REEMPLAZAR` y otros): esos casos
ya no llegan a GCP. Queda por ver qué falla con valores reales que no existan (por ejemplo, un
grupo mal escrito).
Dónde: [`pipeline.md`](pipeline.md), "Marcadores de los ejemplos" y "Primera ejecución"; runbook
[01](runbooks/01-arranque-etapa-0.md), "Primera ejecución de `apply.yml`";
`stages/*/terraform.tfvars.example` y `stages/*/envs/*/terraform.tfvars.example`.
Si falla: corregir el valor en `GCP_TFVARS_JSON` y lanzar `apply.yml` de nuevo (las raíces ya
aplicadas dan "sin cambios"). Un apply que falla a medias deja en el estado lo que sí creó.

---

## 3.7 Agregados por los controles del CIS del 23 nov 2026

Puntos que deja el cierre de los huecos del CIS que no dependen de GCP
([`cumplimiento-cis.md`](cumplimiento-cis.md), ADR 0027).

**56. Evaluación del CIS después del primer apply.**
Qué: el procedimiento de [`cumplimiento-cis.md`](cumplimiento-cis.md) §6. Con SCC activo
(punto 2): en Compliance, activar el marco "CIS GCP Foundations Benchmark v3.0" y revisar la
pestaña Monitor (HYPOTHESIS: que el marco esté disponible para un proyecto sin organización);
en Findings, filtrar `state="ACTIVE" AND (severity="HIGH" OR severity="CRITICAL")` y traducir
cada control a la 5.0 con la columna "3.0" del mapa. Para los controles que el marco no cubre,
juntar la evidencia que lista §6 (salidas de `gcloud` y capturas) y la de los controles
manuales del runbook [01](runbooks/01-arranque-etapa-0.md) ("Controles manuales del CIS"). El
resultado se anota en el mapa: cada fila "Código" o "Manual" que se confirme y cada hallazgo
nuevo.
Dónde: [`cumplimiento-cis.md`](cumplimiento-cis.md) §6; runbook 01; criterio "Sin hallazgos
críticos ni altos en Security Command Center" del README.
Si falla: un hallazgo de un control que el mapa da por cubierto se corrige en el código; uno de
una desviación del ADR 0027 se documenta ahí (con una regla de silencio acotada si se decide,
propuesta).

**57. Contactos esenciales del proyecto (CIS 1.17).**
Qué: que `1-base` cree un contacto por correo de `essential_contacts` en el proyecto con
`roles/essentialcontacts.admin` (lo da `0-bootstrap`); que la API acepte correos de grupo y el
idioma `essential_contacts_language`; y que el detector `ESSENTIAL_CONTACTS_NOT_CONFIGURED` no
marque el proyecto. El CIS 1.17 pide los contactos en la organización: sin ella el control
queda parcial ([`cumplimiento-cis.md`](cumplimiento-cis.md)).
Dónde: `stages/1-base/main.tf:167`; `stages/0-bootstrap/service_accounts.tf:149`.
Si falla: sin indicación en el código. Si la API rechaza un grupo, usar un buzón de rol por
categoría (propuesta); si rechaza el idioma, `essential_contacts_language = "en"`.

**58. Métricas de log y alertas de auditoría (CIS 2.5 a 2.12).**
Qué: en el proyecto único (el módulo se llama una sola vez, desde `1-base`):
- que los detectores `OWNER_NOT_MONITORED`, `AUDIT_CONFIG_NOT_MONITORED`,
  `CUSTOM_ROLE_NOT_MONITORED`, `FIREWALL_NOT_MONITORED`, `ROUTE_NOT_MONITORED`,
  `NETWORK_NOT_MONITORED`, `BUCKET_IAM_NOT_MONITORED` y `SQL_INSTANCE_NOT_MONITORED` no marquen
  el proyecto: los filtros reproducen el texto de la página de hallazgos de SHA, pero en una
  sola línea (la página los muestra en varias), y la coincidencia exacta es HYPOTHESIS;
- que cada serie llegue con el tipo de recurso de la condición (`global`, salvo `gcs_bucket` en
  `bucket_iam` y `cloudsql_database` en `sql_instance`), con un evento de prueba en dev (por
  ejemplo, crear y borrar con `gcloud` una política de firewall de red vacía y un rol
  personalizado de prueba) que dispare la alerta y llegue el correo;
- que la API acepte cada alerta justo después de crear su métrica;
- que el buzón de `security_alert_email` acepte correo de Cloud Monitoring;
- que los cambios a las políticas de firewall de red de las VPC lleguen a la métrica
  `firewall_policy` (HYPOTHESIS: ahora son del proyecto; la política jerárquica que el ADR 0027
  dejaba fuera ya no existe).
Dónde: `modules/audit-alerts/main.tf:12`, `:23`, `:151`, `:183`; `stages/1-base/main.tf:139`.
Si falla: filtro no reconocido: escribirlo con los saltos de línea de la página de SHA (el
módulo lo arma con `join(" ", …)`); tipo de recurso distinto: corregir `resource_type` en
`local.metrics`; alerta rechazada: repetir el apply (lo dice el código); correo rechazado:
permitir remitentes externos en el grupo (propuesta).

**59. OS Login en los metadatos del proyecto (CIS 4.4).**
Qué: que `OS_LOGIN_DISABLED` no marque el proyecto (el metadato `enable-oslogin = TRUE` lo pone
`0-bootstrap` en todo el proyecto); que SSH por IAP a una VM del MIG funcione con
`roles/compute.osLogin` (hoy nadie lo tiene: es un acceso de emergencia que se otorga y se
retira a mano); y que los nodos de GKE Standard hereden el metadato sin romper el clúster.
Dónde: `stages/0-bootstrap/main.tf:122`; `gcloud compute project-info describe
--project=<proyecto>` (metadato `enable-oslogin`).
Si falla: si el detector sigue marcando, la alternativa es la política
`compute.requireOsLogin`, que solo existe con organización (propuesta).

**60. Cloud Asset para `drift.yml` (CIS 2.14).**
Qué: el trabajo de recursos no administrados de `drift.yml` corre `gcloud asset
search-all-resources --scope=projects/<ID>` con `tf-read`. Para una cuenta de servicio, el
proyecto de cuota es el proyecto donde vive
([documentación de Google](https://docs.cloud.google.com/docs/quotas/quota-project)), que aquí
es el proyecto único; `0-bootstrap` habilita ahí `cloudasset.googleapis.com` y `tf-read` tiene
`serviceusage.serviceUsageConsumer`. Verificar en la primera ejecución diaria que el listado
termina sin "API not enabled" ni error de cuota, y que `scripts/unmanaged-resources.py` reconoce
como administradas las métricas de log de `audit-alerts` (HYPOTHESIS: el `id` de
`google_logging_metric` es solo el nombre y Cloud Asset la nombra
`projects/<proyecto>/metrics/<nombre>`; el script arma esa forma).
Dónde: `stages/0-bootstrap/main.tf:45`; `.github/workflows/drift.yml:269`, trabajo `unmanaged`;
[`pipeline.md`](pipeline.md).
Si falla: si el error nombra otro proyecto, pasar `--billing-project=<proyecto>` en `drift.yml`
(propuesta); si las métricas salen como no administradas, ajustar la forma construida en
`build_managed` del script.

**61. Registro de Cloud DNS en `onprem-sim` (CIS 2.13).**
Qué: que `google_dns_policy.onprem_sim` se adjunte a la VPC `onprem-sim` sin chocar con la
política del hub (cada red admite una sola), que `DNS_LOGGING_DISABLED` no marque ninguna red
(hub, spokes y `onprem-sim`) y que la VM DNS de `onprem-sim` siga resolviendo igual
(HYPOTHESIS: una política solo con registro no cambia la resolución).
Dónde: `stages/2-networks/dns.tf:43`.
Si falla: sin indicación en el código; con `simulate_onprem = false` la política no existe.

**62. Flow logs al 100 % en prod, hub y `onprem-sim` (CIS 3.10).**
Qué: que `VPC_FLOW_LOGS_SETTINGS_NOT_RECOMMENDED` (hay que activarlo, es Premium) no marque las
subredes de prod, del hub ni de `onprem-sim` (muestreo 1.0, intervalo de 5 s, todos los
metadatos) y que sí marque las de dev y qa (0.5, desviación aceptada en el ADR 0027); y medir
durante una semana el volumen de flow logs de prod contra el supuesto de
[`estimacion-de-costos.md`](estimacion-de-costos.md) §1.
Dónde: `modules/network-hub/variables.tf:104` y `modules/network-spoke/variables.tf:115`
(`flow_log_sampling = 1` por defecto); `stages/2-networks/envs/*/terraform.tfvars.example`
(0.5 en dev y qa, 1 en prod).
Si falla: si el costo de prod no se sostiene, bajar el muestreo y reabrir la decisión del ADR
0027.

## 3.8 Apagado fuera de horario (ADR 0028)

Todo lo de esta sección se probó solo con proveedores simulados (`terraform test` del módulo
`off-hours-shutdown`, de `cloud-sql`, `compute-mig` y `gke` y de las raíces que lo usan).

**70. Trabajos de Cloud SQL de punta a punta.**
Qué: que `gcloud scheduler jobs run` de `sql-primary-stop` y `sql-primary-start` termine en 2xx
con el token de la cuenta `<prefix>-<env>-<app>-sched` (el agente de servicio de Cloud Scheduler
queda listo al habilitar la API, según la documentación de autenticación de destinos HTTP), que
la operación de Cloud SQL termine en `DONE` y que la instancia quede en `NEVER` y luego en
`ALWAYS` (`gcloud sql instances describe ... --format="value(settings.activationPolicy,state)"`).
Dónde: `modules/off-hours-shutdown/main.tf:97`.
Si falla: sin indicación en el código. Con 403, revisar el rol personalizado (punto 73) y el
actAs del agente de servicio. El trabajo solo ve la respuesta inicial: una operación que falla
después no se nota en Cloud Scheduler.

**71. Pools de GKE: apagado y encendido en dos pasos.**
Qué: que `setAutoscaling` con `enabled=false` y luego `setSize` con `nodeCount=0` dejen el pool
en 0 nodos; que el encendido devuelva el mínimo y reactive el autoescalado con sus límites; que
`setSize` de un pool regional cuente `nodeCount` por zona (HYPOTHESIS); que los 10 minutos de
`gke_step_minutes` alcancen para que termine la operación del primer paso (si no, los reintentos
cubren unos 7.5 minutos más); y que el plan de `3-workloads` no tenga cambios en los pools ni en
el clúster, ni con el pool en 0 ni después del encendido.
Dónde: `modules/off-hours-shutdown/main.tf:101`, `modules/gke/main.tf:279`.
Si falla: subir `gke_step_minutes` (variable del módulo, hoy fija en la raíz) o ajustar el
`ignore_changes` del recurso `scheduled`.

**72. MIG con el programa de escalado como única señal.**
Qué: que la API acepte una política sin `cpuUtilization` y no le agregue la señal de CPU por
defecto (HYPOTHESIS); que el MIG baje a 0 VM fuera del horario y suba a `mig_min_replicas` al
encender; que el cambio entre señales (encender o apagar `off_hours_shutdown`) reemplace el
autoescalador (se borra y se crea) sin dejar el MIG en un tamaño inesperado; y que el segundo
plan no muestre cambios en el autoescalador.
Dónde: `modules/compute-mig/main.tf:208`.
Si falla: si la API agrega la señal de CPU, el grupo no baja a 0 (la página de escalar a cero
lo exige sin señales); la alternativa es la rechazada en el ADR (trabajos de Cloud Scheduler
con el autoescalador en `OFF` y `resize`).

**73. Rol personalizado `<prefix>OffHoursScheduler`.**
Qué: que `0-bootstrap` cree el rol (lo aplica la persona dueña del proyecto); que
`cloudsql.instances.get`, `cloudsql.instances.update` y `container.clusters.update` se admitan
en roles personalizados de proyecto (HYPOTHESIS) y basten para `instances.patch`,
`setAutoscaling` y `setSize`. Desde el 24 nov 2026 (r2/identidad) el rol lo asigna `1-base` a
la cuenta `-sched` que crea en los entornos de `off_hours_environments`, en el proyecto y sin
condición, así que la cuenta del apagado de dev también podría actuar sobre la instancia o los
pools de otro entorno (§5). Ver también punto 134.
Dónde: `stages/0-bootstrap/custom_roles.tf:92`; `stages/1-base/runtime_accounts.tf:140`.
Si falla: sin indicación en el código. Si un permiso no se admite en roles personalizados, se
cambia por el rol predefinido más chico que lo tenga y se anota en el ADR.

**74. Apagar y volver a encender `enable_off_hours_shutdown`.** Obsoleto por el ADR 0029 (un solo proyecto).
El rol ya no se crea ni se borra con el interruptor: lo crea `0-bootstrap` una vez para todo el
proyecto (punto 73). Desde el 24 nov 2026 la cuenta `-sched` y su rol también son de `1-base`
(`off_hours_environments`, punto 134): apagar el horario en `3-workloads` solo borra sus
trabajos.

**75. `postcondition` de Cloud SQL detenida sin apagado permitido.**
Qué: que con una instancia detenida a mano (`gcloud sql instances patch <instancia>
--activation-policy=NEVER`) y `allow_scheduled_stop = false` el plan falle con el mensaje del
módulo; y que con `allow_scheduled_stop = true` el plan no muestre cambios en
`activation_policy`.
Dónde: `modules/cloud-sql/main.tf:217`.
Si falla: si el plan no falla, la deriva de `activation_policy` en prod deja de detectarse
(ADR 0028, "Qué deja de detectarse"); revisar que `self.settings[0].activation_policy` lea el
valor de la API.

**76. Respaldos de Cloud SQL con la ventana movida al horario encendido.**
Qué: que el respaldo diario de Backup and DR se tome dentro de la ventana que empieza en la
primera hora en punto desde el encendido; qué pasa los días sin horario encendido (fin de
semana): HYPOTHESIS sin confirmar (la página oficial que se encontró es de MySQL) que el
respaldo de una instancia detenida no se toma; y que cambiar la ventana no reemplace el plan de
respaldo ni su asociación (HYPOTHESIS).
Dónde: `stages/3-workloads/envs/*/operations.tf:58`.
Si falla: si los días apagados dejan huecos que el RPO de dev o qa no admite, encender
también el fin de semana (por ejemplo `1-6`) o aceptar el hueco en el ADR.

**77. Apply de `3-workloads` con Cloud SQL detenida.**
Qué: que el plan muestre solo la advertencia de `check "cloud_sql_encendida"`; que un apply
sin cambios en bases ni usuarios pase; y que uno que crea una base o un usuario IAM falle hasta
el encendido (HYPOTHESIS) con un error que se entienda.
Dónde: `stages/3-workloads/envs/*/off_hours.tf:76` (`check "cloud_sql_encendida"`); sin marcador.
Si falla: lanzar el trabajo de encendido (README de la raíz, "Apagado fuera de horario") y
repetir el apply.

**78. Prueba de humo de dev con Cloud SQL detenida.**
Qué: que `gcloud sql instances describe` de una instancia detenida dé
`settings.activationPolicy = NEVER` y `state = RUNNABLE`, como dice la referencia de la API, y
que `TestDevSmoke` falle con el mensaje de `sqlStoppedError` y no por otra causa.
Dónde: `tests/e2e/connectivity_test.go:96` (`sqlStoppedError`); sin marcador.
Si falla: ajustar la detección al campo que devuelva la API y su prueba
`tests/e2e/sql_stopped_test.go`.

**79. Alertas de noche en dev y qa.**
Qué: si la verificación de disponibilidad, la alerta de 5xx y la de consumo del SLO del
balanceador se disparan de noche con Cloud SQL detenida y el MIG en 0 (HYPOTHESIS: sí, si el
backend por defecto es el MIG o la aplicación depende de la base).
Dónde: `modules/observability` (llamado desde `stages/3-workloads/envs/*/operations.tf`); sin
marcador. Los filtros por entorno de esas alertas son el punto 115.
Si falla: propuesta (no construida): silenciar esas alertas en dev y qa fuera del horario, o
apuntar la verificación de disponibilidad a una ruta que no use la base.

**80. Sin deriva de día ni de noche en dev y qa.**
Qué: que `drift.yml` (06:17 en Monterrey, con todo apagado) y un plan de día den código 0 en
`3-workloads/envs/dev` y `qa` con `off_hours_shutdown`; que la salida raíz `off_hours_shutdown`
no cambie; y que el trabajo de recursos no administrados no encuentre nada nuevo por el apagado.
Dónde: `.github/workflows/drift.yml`; `stages/3-workloads/envs/*/outputs.tf`
(`off_hours_shutdown`); sin marcador.
Si falla: agregar a `ignore_changes` el atributo que aparezca y anotarlo en el ADR 0028.

**81. Prueba de integración del módulo `off-hours-shutdown`.**
Qué: correr `TestOffHoursShutdown` (`tests/integration/off_hours_shutdown_test.go`): seis
trabajos habilitados con su horario, zona horaria, método, URI, cuerpo y token; que Cloud
Scheduler no pida una app de App Engine en el proyecto de pruebas y que gcloud devuelva
`httpTarget.body` en base64.
Dónde: `tests/integration/off_hours_shutdown_test.go:20`, `tests/fixtures/off-hours-shutdown/`.
Si falla: corregir la prueba o el módulo según lo que devuelva la API.

## 3.9 Agregados por el flujo de destroy

Del 23 nov 2026, con `destroy.yml` ([`pipeline.md`](pipeline.md) §1.5), actualizados al
proyecto único el 24 nov 2026: el flujo destruye `3-workloads/envs/<env>` y, con `incluir_red`,
el spoke `2-networks/envs/<env>`; no borra proyectos.

**85. Primer destroy de dev con `destroy.yml` (HYPOTHESIS).**
Qué: que el flujo destruya `3-workloads/envs/dev` (y, con `incluir_red`, `2-networks/envs/dev`)
y el trabajo de huérfanos salga con 0; que Cloud Asset devuelva `labels` y, para las cuentas de
servicio, `additionalAttributes.email` (lo que usa `destroy-orphans.py` para reconocer lo del
entorno); cuánto tarda el índice en dejar de listar lo destruido (el trabajo lista hasta
`ORPHAN_ATTEMPTS` = 3 veces, con `ORPHAN_WAIT_SECONDS` = 300 entre una y otra); que el plan de
destrucción de cada raíz dé la misma huella en `plan` y en `destroy` (como el punto 48); y que
GitHub rechace por API un valor de `entorno` fuera de la lista (`gh workflow run destroy.yml
--ref main -f entorno=prod -f confirmacion=prod`; si GitHub lo acepta, lo rechaza el trabajo
`pedido de destrucción`). Que el listado traiga el proyecto mismo es el punto 118. Desde el
24 nov 2026 (r2/pipeline) el script también reconoce los restos de GKE por la regla "contiene
`<prefix>-<env>-`" y avisa de los que no puede atribuir: ver también puntos 140 y 141.
Dónde: `.github/workflows/destroy.yml:219`, `scripts/destroy-orphans.py:76`,
`scripts/destroy-plan-check.py`; `_terraform-root.yml` con `destroy: true`.
Si falla: un recurso que GCP deja a propósito y sale como huérfano: agregar la regla en
`scripts/destroy-orphans.py` con su motivo y su fuente, y su caso en `scripts/selftest.sh`. Si el
índice tarda más, subir `ORPHAN_ATTEMPTS` u `ORPHAN_WAIT_SECONDS` en `destroy.yml` o volver a
lanzar el flujo (las raíces vacías se saltan y solo corre la búsqueda).

**86. Bóveda de Backup and DR en el destroy.**
Qué: con `enable_backup = true` (ejemplos de dev y qa), la bóveda tiene retención forzada de 30
días. Según la
[documentación de la bóveda](https://docs.cloud.google.com/backup-disaster-recovery/docs/concepts/backup-vault),
ningún respaldo se borra antes y, desde el 1 nov 2026, Backup and DR pone un gravamen (lien) en el
proyecto que tenga respaldos retenidos. El destroy ya no borra el proyecto, así que el gravamen
no lo frena; lo que puede fallar es borrar la bóveda. Según el esquema de google 6.50.0,
`ignore_inactive_datasources` permite borrar una bóveda "sin respaldos, pero con fuentes de datos
vacías"; el módulo no lo fija, así que una bóveda que tuvo respaldos podría no borrarse aunque ya
estén vencidos (HYPOTHESIS). Comprobar: destroy de `3-workloads` con una bóveda sin respaldos
(pasa), con respaldos (falla en la bóveda, el resto se borra) y después de vencidos.
Dónde: `modules/backup-dr/main.tf:21` (marcador) y `:23`;
`stages/3-workloads/envs/*/operations.tf:51` (`retention_days = 30`); `destroy-plan-check.py` lo
avisa con `backup_count`.
Si falla: para la prueba de destroy, desplegar dev con `"enable_backup": false`. Propuesta no
construida: `ignore_inactive_datasources` por variable del módulo, en `true` fuera de prod,
aplicado antes del destroy.

**87. Conexión de Private Service Access en el destroy de `2-networks/envs/<env>`.**
Qué: según la
[documentación de PSA](https://docs.cloud.google.com/vpc/docs/configure-private-services-access),
después de borrar una instancia de Cloud SQL el servicio espera cuatro días antes de liberar sus
recursos, y la conexión no se borra mientras tanto. Por eso `destroy.yml` solo destruye el spoke
con `incluir_red` y sugiere hacerlo días después, en otra ejecución (HYPOTHESIS en el flujo).
Comprobar el mensaje de error, que volver a lanzar `destroy.yml` con `incluir_red` pasado el
plazo complete el destroy, y si Memorystore y Filestore tienen una espera parecida.
Dónde: `modules/network-spoke/main.tf:160`; `.github/workflows/destroy.yml:10`.
Si falla: volver a lanzar `destroy.yml` con `incluir_red` después del plazo (`3-workloads`, ya
vacía, se salta). Alternativa no construida: `deletion_policy = "ABANDON"` en
`google_service_networking_connection` (según el esquema de google 6.50.0, Terraform deja de
administrarla y la conexión sigue existiendo); dejaría el peering de servicios vivo y no se sabe
si la red se puede borrar con él (HYPOTHESIS).

**88. Recrear un entorno después del destroy.** Obsoleto por el ADR 0029 (un solo proyecto).
El destroy ya no borra proyectos: no hay ID de proyecto que reutilizar ni `project_suffix`. Lo
que podría no reutilizarse de inmediato es el nombre de una instancia de Cloud SQL borrada
(punto 116) y, sin comprobar, el de un bucket (punto 89).

**89. Bucket de la aplicación sin `force_destroy`.**
Qué: `module.storage` de `3-workloads` no pasa `force_destroy` (por defecto `false`); si el
bucket tiene objetos (también versiones no actuales), el destroy de `3-workloads` falla en él, y
nadie del equipo puede vaciarlo (las personas tienen solo lectura). Se espera, sin verlo en GCP,
que un entorno recién desplegado no tenga objetos (HYPOTHESIS).
Dónde: `stages/3-workloads/envs/*/data.tf:107`; `modules/storage/variables.tf:201`;
`destroy-plan-check.py` lo avisa.
Si falla: propuesta no construida: `force_destroy = var.environment != "prod"` en la raíz (el
módulo ya lo prohíbe en prod), aplicado antes del destroy.

## 3.10 Agregados por el rediseño a un solo proyecto (24 nov 2026)

Del 24 nov 2026, con el rediseño del ADR 0029. Salen de los reportes de construcción de los
cuatro bloques (base, redes, cargas y pipeline), de los marcadores nuevos del código y de la
revisión de la documentación. Todo es HYPOTHESIS hasta el primer apply. Lo que esos reportes
señalaron y ya tenía un punto se agregó a ese punto:

| Tema | Punto |
|---|---|
| Agente de Cloud Storage consultado con el ID del proyecto | 13 (y 27, obsoleto) |
| Notificación de SCC de proyecto, opcional | 2, 23 y 34 |
| Contactos esenciales en el proyecto | 57 |
| Política de firewall de red de `onprem-sim` en lugar de la jerárquica | 7 y 36 |
| Cuotas compartidas por los entornos | 9 |
| Destroy sin borrar proyectos; la red solo con `incluir_red` | 11, 85, 86, 87 y 88 |
| Cuenta `tf-read` en lugar de la cuenta de auditoría creada a mano | 50 |
| Rol del apagado creado en `0-bootstrap` | 73 y 74 |
| Lista de permitidos global de Binary Authorization | 42 |
| Namespace `<app>-<env>` de Workload Identity | 46 |
| Validación de `applications` en `1-base` distinta de la de `3-workloads` | 26 |

**90. Etiqueta de protección en un proyecto sin organización.**
Qué: que la llave de etiqueta `<prefix>-proteccion` con padre `projects/<id>` y su valor
`etapa-0` se creen en un proyecto sin organización (HYPOTHESIS del ADR 0029 §5) y que la persona
de la etapa 0 pueda ligarla (`tagUser` sobre el valor y `createTagBinding` sobre cada recurso).
Dónde: `stages/0-bootstrap/deny_policy.tf:111`; interruptor `enable_protection_tags`.
Si falla: `enable_protection_tags = false`: la protección queda en que ninguna cuenta tiene
`storage.admin` sin condición, `serviceAccountAdmin` ni `projectIamAdmin` sin condición (lo dice
el código, ADR 0029 §5); la regla sin etiqueta de la denegación sigue (punto 93).

**91. Etiqueta en el bucket y el llavero del estado, y herencia en la llave.**
Qué: que el bucket y el llavero del estado acepten el enlace de etiqueta con ubicación y que la
llave `state` herede la etiqueta de su llavero (las etiquetas no se admiten en llaves sueltas; la
herencia es HYPOTHESIS). Comprobar con `gcloud resource-manager tags bindings list --effective`.
Dónde: `stages/0-bootstrap/deny_policy.tf:133`.
Si falla: sin indicación en el código. Sin herencia, la llave queda fuera de la regla con
etiqueta y la protege solo que ninguna cuenta del pipeline tiene KMS sobre el llavero del estado
(`kms_not_bootstrap`, `stages/0-bootstrap/service_accounts.tf:68`).

**92. Formato del enlace de etiqueta de las cuentas del pipeline.**
Qué: que el enlace acepte `//iam.googleapis.com/projects/<id>/serviceAccounts/<id único>` para
las nueve cuentas (ocho de raíz y `tf-read`).
Dónde: `stages/0-bootstrap/deny_policy.tf:152`.
Si falla: sin indicación en el código; probar con el correo de la cuenta en lugar del ID único y
repetir el apply de la etapa 0 (propuesta).

**93. Política de denegación del proyecto.**
Qué: que la persona de la etapa 0 tenga `roles/iam.denyAdmin` en el proyecto (el rol `owner` no
lo incluye), que la API de denegación acepte el proyecto como padre y que las dos reglas
funcionen: con la etiqueta, `tf-wl-dev` recibe un rechazo al intentar `getIamPolicy` o
`setIamPolicy` sobre `tf-base` (prueba que propone el código); sin etiqueta, ninguna cuenta del
pipeline puede crear llaves de cuentas de servicio, cambiar el pool o el proveedor de WIF, crear
o cambiar roles personalizados ni borrar el proyecto y, desde el 24 nov 2026, tampoco pedir
tokens ni firmas de cuentas de servicio (punto 127). Reemplaza al punto 32.
Dónde: `stages/0-bootstrap/deny_policy.tf:168`; interruptor `enable_deny_policy`.
Si falla: sin indicación en el código. Sin `denyAdmin`, darlo a la persona en el proyecto y
repetir (runbook 01); si la API no acepta el proyecto, `enable_deny_policy = false` y la
protección queda como en el punto 90 (propuesta).

**94. Agentes de servicio creados en la etapa 0.**
Qué: que `generateServiceIdentity` acepte cada servicio de `service_identity_services`
(Artifact Registry, Filestore, Backup for GKE, Pub/Sub, Memorystore, Secret Manager y Cloud SQL)
y que los agentes de `container`, `compute` y `run` existan justo después de habilitar sus APIs,
antes de que `1-base` les dé permisos sobre las llaves.
Dónde: `stages/0-bootstrap/main.tf:77`.
Si falla: agregar a la lista el servicio cuyo agente falte (lo dice el código).

**95. Cuenta de Compute por defecto sin `roles/editor`.**
Qué: que `google_project_default_service_accounts` con `DEPRIVILEGE` le quite `roles/editor` sin
borrarla (`gcloud projects get-iam-policy`) y que ninguna carga la use. Va en `0-bootstrap` y no
en `1-base`, como decía el ADR 0029 §4: quitar un rol básico necesita `setIamPolicy` sin
condición, y ninguna cuenta del pipeline lo tiene.
Dónde: `stages/0-bootstrap/main.tf:136`.
Si falla: sin indicación en el código; quitar el rol a mano con la persona dueña del proyecto y
anotarlo (propuesta).

**96. Presupuesto filtrado al proyecto.**
Qué: que el filtro `projects/<número>` limite el presupuesto (`budget_amount`) al proyecto y que
los avisos lleguen por correo a los administradores de la cuenta de facturación. Lo aplica la
persona de la etapa 0, con `roles/billing.costsManager` en la cuenta de facturación.
Dónde: `stages/0-bootstrap/main.tf:275`.
Si falla: sin indicación en el código; crear el presupuesto en la consola de facturación con los
mismos umbrales (propuesta).

**97. Roles de proyecto de cada cuenta del pipeline.**
Qué: que cada raíz aplique con su cuenta y su lista de roles (`base_roles`, `hub_roles`,
`net_env_roles` y `workloads_roles`). Los roles de proyecto de las cuentas del pipeline solo los
da `0-bootstrap` (ADR 0029 §3) y su mínimo privilegio es HYPOTHESIS hasta el primer apply de
cada raíz. Desde el 24 nov 2026 (r2/identidad) `workloads_roles` ya no trae roles de cuentas de
servicio, de etiquetas ni de IAM de proyecto (puntos 131 y 136).
Dónde: `stages/0-bootstrap/service_accounts.tf:11` (listas en las líneas 141 a 224).
Si falla: agregar el permiso que falte con el rol predefinido más chico, en `0-bootstrap` y
nunca en la raíz (lo dice el código), y volver a aplicar la etapa 0 a mano.

**98. `storage.buckets.create` con la condición de prefijo.**
Qué: que `storage.admin` condicionado a `projects/_/buckets/<prefix>-<dominio>-` deje crear el
bucket nuevo, es decir, que el permiso se evalúe con el nombre del bucket y no sobre el
proyecto. Afecta al bucket de logs de `1-base` (`common`) y al de la aplicación de
`3-workloads` (`<env>`).
Dónde: `stages/0-bootstrap/service_accounts.tf:72`.
Si falla: agregar a la condición la cláusula
`resource.type == "cloudresourcemanager.googleapis.com/Project"` (lo dice el código).

**99. Condición de llaves y secretos por entorno.** Resuelto en el código el 2026-11-24 (r2/identidad): `tf-wl-<env>` ya no asigna IAM de secretos ni de llaves.
Era: que `tf-wl-dev` pudiera dar `secretAccessor` sobre un secreto `<prefix>-dev-` y no sobre uno
de prod, con un rol condicionado por nombre (`kms_secret_env`, rol `TfKmsSecretIamGranter`).
Ahora: el rol y la condición ya no existen. `1-base` da `secretAccessor` secreto por secreto a
las cuentas `workload` y `run` de cada entorno (`stages/1-base/runtime_accounts.tf`), así que no
queda condición por nombre que verificar. Lo que queda por comprobar de esas cuentas está en los
puntos 131 a 135.

**100. Roles de las cuentas de red.**
Qué: que el hub (`tf-net`: VPN, DNS, `onprem-sim` y sus políticas de firewall de red) y cada
spoke (`tf-net-<env>`: PSA, etiquetas seguras, política de firewall de red, la zona adjunta a la
VPC hub) apliquen con `net_roles` y `net_env_roles`; en particular, que `compute.securityAdmin`
alcance para crear, asociar y cambiar las políticas de firewall de red globales, que
`servicenetworking.networksAdmin` alcance para la conexión de PSA y que el rol personalizado
`TfNetworkTagManager` (en lugar de `tagAdmin` desde el 24 nov 2026) alcance para las etiquetas
seguras del spoke y su IAM en un proyecto sin organización. El hub, con `onprem_dns_vm = true`,
también tiene `compute.instanceAdmin.v1` (punto 128).
Dónde: `stages/0-bootstrap/service_accounts.tf:172`; tablas de roles de
`stages/2-networks/README.md` y `stages/2-networks/envs/*/README.md` (marcadores en los README).
Si falla: como el punto 97.

**101. `policyEditor` sobre la política de acceso.** Resuelto en el código el 2026-11-24 (r2/identidad): ninguna cuenta del pipeline recibe roles de la política de acceso.
Era: que la persona de la etapa 0 pudiera dar `roles/accesscontextmanager.policyEditor` a
`tf-base` sobre la política, para que `1-base` creara el perímetro.
Ahora: el perímetro lo crea la persona en `0-bootstrap` (`stages/0-bootstrap/org.tf`) y
`tf-base` no tiene roles de organización ni de la política de acceso. Lo que queda por comprobar
es el punto 126.

**102. `attribute.environment` en trabajos sin entorno de GitHub.** Resuelto en el código el 2026-11-24 (r2/identidad): el mapeo da `'none'` cuando falta la afirmación.
Era: que el mapeo de `attribute.environment` no fallara cuando el token no trae la afirmación
`environment` (trabajos `plan`, `drift.yml`) y que esos trabajos solo obtuvieran `tf-read`.
Ahora: `attribute.environment` y `attribute.deploy` leen `environment` y `job_workflow_ref` solo
después de comprobar que están (`'<afirmación>' in assertion`) y si no dan `'none'`; las cuentas
de escritura se toman por `attribute.deploy`, no por `attribute.environment`
(`stages/0-bootstrap/wif.tf`). Lo que queda por comprobar en GCP es el punto 124.

**103. Agentes de servicio antes del permiso sobre las llaves.**
Qué: que cada agente exista antes de recibir `cryptoKeyEncrypterDecrypter` en `1-base` (los
crea `0-bootstrap` o aparecen al habilitar la API) y pueda cifrar con su llave. Los agentes son
uno por proyecto: el de Cloud SQL, por ejemplo, recibe permiso sobre las llaves de los tres
entornos (riesgo aceptado, ADR 0029 §9).
Dónde: `stages/1-base/kms.tf:70`.
Si falla: ver punto 94; si es propagación de IAM, repetir el apply (propuesta).

**104. `tagUser` para nodos y VM.** Resuelto en el código el 2026-11-24 (r2/identidad): los permisos de etiquetas cambiaron de lugar.
Era: que `roles/resourcemanager.tagUser` en el proyecto, que daba `1-base` (`stages/1-base/iam.tf`)
al agente de GKE y a `<número>@cloudservices`, junto con el `tagUser` de proyecto de
`tf-wl-<env>`, bastaran para crear la plantilla del MIG y los pools de GKE con las etiquetas
seguras `lb_backend` e `iap_ssh` del spoke.
Ahora: el `tagUser` de proyecto del agente de GKE y de `<número>@cloudservices` lo da
`0-bootstrap` (punto 137); `tf-wl-<env>` ya no tiene `tagUser` de proyecto: el spoke le da
`tagUser` solo sobre sus valores y al agente de GKE `tagHoldAdmin` (punto 136).

**105. Proyecto de cuota de `1-base`.**
Qué: que todas las APIs que usa `1-base` acepten el proyecto como proyecto de cuota, con
`serviceusage.serviceUsageConsumer` de `0-bootstrap`.
Dónde: `stages/1-base/providers.tf:4`.
Si falla: sin indicación en el código.

**106. Dominios permitidos y agentes de servicio.**
Qué: solo con organización y `directory_customer_id`: que los agentes de servicio de Google
(Logging, Cloud Storage, GKE) sigan recibiendo roles con `iam.allowedPolicyMemberDomains` activa
y que la restricción no rechace los `principalSet://` de WIF. Desde el 24 nov 2026 la política la
aplica la persona en `0-bootstrap`: ver también punto 125.
Dónde: `modules/org/main.tf:56`.
Si falla: sin indicación en el código.

**107. Política de organización con padre proyecto.** Resuelto en el código el 2026-11-24 (r2/identidad): ninguna cuenta del pipeline tiene `orgpolicy.policyAdmin`.
Era: que `tf-base` creara las políticas con padre `projects/<id>` con
`roles/orgpolicy.policyAdmin`, que `0-bootstrap` le daba en la organización cuando había
`org_id` (alcanzaba a toda la organización).
Ahora: las políticas las aplica la persona de la etapa 0 (`stages/0-bootstrap/org.tf`) y
`tf-base` no tiene roles de organización. El marcador del módulo
(`modules/org/main.tf:67`) sigue: lo que queda por comprobar es el punto 125.

**108. Exclusión del sink y escritura con CMEK.**
Qué: que la exclusión `bucket-de-logs` descarte los registros de acceso a datos del propio
bucket de logs (sin ella, cada escritura del sink se volvería a exportar) y que la identidad del
sink de proyecto escriba en el bucket con CMEK. El sink exporta `logName:"cloudaudit.googleapis.com"`.
Dónde: `modules/log-export/main.tf:96`; `stages/1-base/main.tf:129`.
Si falla: sin indicación en el código.

**109. Perímetro en dry-run sin `status`.**
Qué: solo con `access_policy_id`: que la API acepte el perímetro solo con `spec` (dry-run) y que
el cambio a forzado se aplique en un solo plan (hoy no se usa: el código lo deja en dry-run).
Dónde: `modules/vpc-sc/main.tf:42`.
Si falla: sin indicación en el código.

**110. Etiquetas seguras con padre proyecto.**
Qué: que las llaves de etiqueta segura de cada spoke (`lb_backend`, `iap_ssh`), con padre el
proyecto y `purpose_data` `network = "<proyecto>/<red>"`, se creen y se puedan usar en las
reglas de la política de firewall de red en un proyecto sin organización (HYPOTHESIS del ADR
0029 §6).
Dónde: `modules/firewall/main.tf:25`.
Si falla: sin indicación en el código; alternativa: reglas por cuenta de servicio de destino en
lugar de etiquetas (propuesta).

**111. Una conexión de PSA por spoke.**
Qué: que cada VPC spoke del mismo proyecto tenga su propia conexión de `servicenetworking` con su
rango (la guía de PSA no lo dice para varias VPC de un proyecto) y que Cloud SQL, Memorystore y
Filestore de cada entorno se creen sobre la suya.
Dónde: `modules/network-spoke/main.tf:160` (el mismo marcador cubre el destroy, punto 87).
Si falla: sin indicación en el código.

**112. VPN, BGP y DNS entrante con la política del hub.**
Qué: que los túneles y las sesiones BGP suban con la política de firewall de red de la VPC hub
(denegación por defecto) y que esa denegación no corte las consultas de on-premises a
`dns_inbound_forwarder_ips`.
Dónde: `stages/2-networks/firewall.tf:22`; `stages/2-networks/README.md` (marcador en el README).
Si falla: agregar una regla `allow` desde `onprem_cidrs`, TCP y UDP 53 (lo dice el código).

**113. Zona del entorno adjunta a la VPC hub.**
Qué: que `tf-net-<env>` pueda adjuntar la zona del entorno a la VPC hub del mismo proyecto
(`dns.networks.bindPrivateDNSZone`, con `dns.admin` de proyecto) y que on-premises la resuelva
por el reenvío entrante del hub.
Dónde: `stages/2-networks/envs/*/dns.tf:63`.
Si falla: sin indicación en el código.

**114. Cuentas nuevas usables en el mismo apply.** Resuelto en el código el 2026-11-24 (r2/identidad): las cuentas de ejecución las crea `1-base`, en un apply anterior.
Era: que las cuentas de ejecución y la `-sched`, que creaba `3-workloads` en el mismo apply que
las usaba (nodos de GKE, plantilla del MIG, Cloud Run, usuarios IAM de Cloud SQL y trabajos de
Cloud Scheduler), se pudieran usar sin errores de propagación.
Ahora: las crea `1-base` (`stages/1-base/runtime_accounts.tf`) y `3-workloads` solo las lee de
`runtime_service_accounts`; la propuesta del bloque base quedó construida. Lo que queda por
comprobar es el punto 131.

**115. Filtros de Monitoring por entorno.**
Qué: que Cloud Monitoring acepte `starts_with()` sobre `url_map_name`, `cluster_name` y
`database_id`, y `metadata.user_labels.env` en `gce_instance`, en alertas, SLO y tablero, y que
cada entorno vea solo sus series (las de los tres entornos están en el mismo proyecto).
Dónde: `modules/observability/main.tf:13`.
Si falla: sin indicación en el código.

**116. Nombre de la instancia de Cloud SQL al recrear un entorno.**
Qué: el nombre de una instancia borrada no se puede reutilizar de inmediato (HYPOTHESIS del
código: hasta una semana); recrear un entorno después del destroy necesita otro
`sql_instance_name`. Comprobar el plazo y el error. Reemplaza al punto 88.
Dónde: `stages/3-workloads/envs/*/variables.tf:499`.
Si falla: cambiar `sql_instance_name` en `GCP_TFVARS_JSON` (por ejemplo `sql2`; lo dice el
código).

**117. Misma huella con `tf-read` y con la cuenta de la raíz.**
Qué: que el plan con la cuenta de lectura y el del apply con la cuenta de la raíz den la misma
huella; una fuente de datos que dependa de la identidad la cambiaría en cada ejecución.
Dónde: `.github/workflows/_terraform-root.yml:33`; punto 48.
Si falla: sin indicación en el código; buscar en `plan.json` el atributo que cambia y quitar o
fijar la fuente de datos (propuesta).

**118. Cloud Asset lista el proyecto mismo.**
Qué: que `gcloud asset search-all-resources --scope=projects/<ID>` traiga el propio proyecto (si
no, `unmanaged-resources.py` y `destroy-orphans.py` salen con 2 en cada corrida) y que la cuota
de la API alcance con `tf-read`.
Dónde: `.github/workflows/drift.yml:269`, `scripts/unmanaged-resources.py:54`,
`.github/workflows/destroy.yml:219`.
Si falla: sin indicación en el código; ajustar la comprobación de los scripts al resultado de la
API, con su caso en `scripts/selftest.sh` (propuesta).

**119. Cuotas del proyecto de pruebas.**
Qué: que las cuotas del proyecto de pruebas (redes, routers, IP por región) alcancen para las
pruebas de Terratest en paralelo (`go test -parallel`).
Desde el 24 nov 2026 (r2/pipeline) `scripts/terratest-project-check.py` impide usar el proyecto
de la landing zone como proyecto de pruebas, así que este consumo no se suma al del punto 9.
Dónde: `tests/helpers/project.go:70`; `tests/README.md` (marcador de las cuotas).
Si falla: bajar `-parallel` o pedir cuota (propuesta).

**120. Binary Authorization en las pruebas.**
Qué: que el patrón con `*` final (`us-docker.pkg.dev/cloudrun/container/hello*` en
`binary_authorization_allowlist_patterns` de `1-base`) admita la etiqueta `:latest` en la prueba
de extremo a extremo, y que la política del proyecto de pruebas no bloquee la imagen del fixture
de Cloud Run. Desde el 24 nov 2026 (r2/pipeline) Terratest no corre en el proyecto de la landing
zone (`scripts/terratest-project-check.py` y `RequireProjectEnv` de `tests/helpers`), así que
la política de `1-base` solo cuenta en la prueba de extremo a extremo.
Dónde: `tests/helpers/env.go:60`; `tests/README.md` (marcador del `*` final);
`tests/fixtures/cloud-run/main.tf:88`.
Si falla: publicar la imagen en un repositorio del proyecto y apuntar `cloud_run_image` a él
(propuesta).

**121. Ramas de despliegue de los entornos de GitHub.**
Qué: que los cuatro entornos (`common`, `dev`, `qa` y `prod`) tengan "Deployment branches:
main" y que eso funcione como segunda barrera: desde el 24 nov 2026 (r2/identidad) la primera
es `attribute.deploy`, que da `'none'` a un token con `ref` distinta de `refs/heads/main`
(punto 123). Un trabajo de una rama distinta de `main` que declare el entorno no debe obtener el
token de la cuenta (HYPOTHESIS: que GitHub no empiece ese trabajo). Comprobar con una rama de
prueba que declare `environment: dev`.
Dónde: configuración de los entornos en [`pipeline.md`](pipeline.md); principales de WIF en
`stages/0-bootstrap/service_accounts.tf:279` a `:282` (`wif_environment_principal`); ADR 0029 §3.
Si falla: con `attribute.deploy`, una rama distinta de `main` sigue sin obtener las cuentas de
escritura; sin la regla de GitHub queda una sola barrera. No encender `GCP_ENABLED` hasta
configurarla (propuesta).

**122. `tf-read` lee los estados de todas las raíces.**
Qué: `tf-read` tiene `objectViewer` sin condición sobre todo el bucket de estado, y la toma por
WIF cualquier trabajo del repositorio (`attribute.repository_id`, sin entorno ni rama). Los
estados pueden tener valores sensibles: el secreto compartido de la VPN en el estado del hub
(ADR 0006) y lo que los proveedores guarden en claro. Comprobar qué estados tienen valores
sensibles (`terraform show -json` de cada raíz) y decidir si se acepta. El alcance de `tf-read`
no cambió con los arreglos del 24 nov 2026: `attribute.deploy` solo limita las cuentas que
escriben.
Dónde: `stages/0-bootstrap/service_accounts.tf:363` (`state|read`) y `:371` (WIF por
repositorio); ADR 0029 §3.
Si no se acepta: propuestas no construidas: condicionar la lectura de `tf-read` por prefijo y
dejar fuera `2-networks/hub/` (el plan del hub lo haría su propia cuenta), o limitar quién toma
`tf-read` con un atributo de rama (por verificar).

## 3.11 Agregados por los arreglos de R2 (24 nov 2026)

Del 24 nov 2026, con los arreglos de R2 integrados en el código de `6d27623` (ramas
`r2/identidad`, `r2/pipeline`, `r2/politicas` y `r2/integracion`). Salen de los marcadores
nuevos del código y de los cambios de las cuentas, del pipeline, de las reglas de Conftest y de
las pruebas. Todo es HYPOTHESIS hasta el primer apply o la primera ejecución en GitHub. Cuando
un punto viejo cubre el mismo tema, el punto nuevo lo dice ("Ver también" o "Reemplaza al").

**123. WIF de escritura por `attribute.deploy`.**
Qué: que el trabajo `apply` de `_terraform-root.yml`, llamado desde `apply.yml` y `destroy.yml`
en `main`, traiga en su token `ref = refs/heads/main` y un `job_workflow_ref` que empiece con
`<dueño>/<repo>/.github/workflows/` (se espera
`<dueño>/<repo>/.github/workflows/_terraform-root.yml@refs/heads/main`), y que así
`attribute.deploy` valga su entorno (`common`, `dev`, `qa` o `prod`) y tome la cuenta de su
raíz. Las afirmaciones son las que documenta GitHub para flujos reutilizables (fuentes citadas
en `wif.tf`); su valor real es HYPOTHESIS hasta la primera ejecución. Ver también puntos 12 y
121.
Dónde: `stages/0-bootstrap/wif.tf:36` (`local.wif_deploy`); principales en
`stages/0-bootstrap/service_accounts.tf:279`.
Si falla: sin indicación en el código. Se nota en el primer `apply`: falla la autenticación
(falla cerrado). Comparar el `job_workflow_ref` del token con el prefijo de `wif.tf`, corregir la
expresión en `0-bootstrap` y que la persona la vuelva a aplicar (propuesta).

**124. Trabajo sin entorno o fuera de `main`: `tf-read` y `attribute.deploy = none`.**
Qué: que un trabajo sin entorno de GitHub (el `plan` de un PR, `drift.yml`) o de otra rama
obtenga su token sin que falle el mapeo, con `attribute.environment` y `attribute.deploy` en
`'none'`, y que solo pueda tomar `tf-read`; y que el `apply` de `main` obtenga
`attribute.deploy` igual a su entorno. Reemplaza al punto 102 (resuelto en el código).
Dónde: `stages/0-bootstrap/wif.tf:81`.
Si falla: sin indicación en el código. Una expresión de mapeo que falla deja sin token a todos
los trabajos, también a los de `tf-read` (lo dice el código): corregirla en `0-bootstrap` y que
la persona la vuelva a aplicar (propuesta).

**125. Políticas de organización que aplica la persona de la etapa 0.**
Qué: solo con `org_id`: que la persona que aplica `0-bootstrap` pueda crear las políticas con
padre `projects/<id>` (necesita `roles/orgpolicy.policyAdmin` en la organización) y que
`iam.allowedPolicyMemberDomains` (con `directory_customer_id`) no rechace los `principalSet://`
de WIF ni los agentes de servicio de Google en los cambios de IAM de `1-base` a `3-workloads`.
Ninguna cuenta del pipeline tiene ese rol. Reemplaza al punto 107 (resuelto en el código); ver
también puntos 3 y 106.
Dónde: `stages/0-bootstrap/org.tf:12`; `modules/org/main.tf:56` y `:67`.
Si falla: sin indicación en el código. Sin el rol, dejar `org_id` vacío: los controles quedan en
las reglas de Conftest y en los pasos manuales del runbook 01, como sin organización
(propuesta).

**126. Perímetro de VPC-SC en dry-run que crea la persona de la etapa 0.**
Qué: solo con `access_policy_id`: que la persona que aplica `0-bootstrap` cree el perímetro
(necesita `roles/accesscontextmanager.policyAdmin` en la organización o `policyEditor` sobre la
política), que quede en dry-run y registre violaciones sin bloquear, con la regla de entrada de
las nueve cuentas del pipeline. Reemplaza al punto 101 (resuelto en el código); ver también
puntos 5 y 109.
Dónde: `stages/0-bootstrap/org.tf:34`; `modules/vpc-sc/main.tf:42` y `:140`.
Si falla: el perímetro en dry-run no bloquea nada. Sin el rol, dejar `access_policy_id` vacío
(sin perímetro, propuesta).

**127. Regla sin etiqueta ampliada a tokens y firmas.**
Qué: la regla sin etiqueta de la política de denegación niega ahora a las nueve cuentas
`getAccessToken`, `getOpenIdToken`, `implicitDelegation`, `signBlob` y `signJwt` sobre las
cuentas de servicio. Verificar que crear un trabajo de Cloud Scheduler con `oauth_token` de la
cuenta `sched` y un clúster de GKE con la cuenta `gke-nodes` siga funcionando (según el código
solo piden actAs, que no se niega) y que la toma de las cuentas por WIF no cambie. Ver también
punto 93.
Dónde: `stages/0-bootstrap/deny_policy.tf:87`.
Si falla: sin indicación en el código. Quitar de la lista el permiso que nombre el error y
anotarlo como riesgo aceptado (propuesta).

**128. `compute.instanceAdmin.v1` del hub para la VM DNS.**
Qué: con `onprem_dns_vm = true` en `0-bootstrap`: que `tf-net` cree la VM DNS de `onprem-sim`
con este rol, más `networkAdmin` (subred y dirección interna) y `serviceAccountUser` sobre la
cuenta `<prefix>-common-net-dns` que crea `1-base`, y que sin el rol no pueda. El rol va sin
condición: riesgo aceptado mientras la opción esté activa, porque el hub podría cambiar o borrar
las VM de los entornos (§5). Ver también punto 100.
Dónde: `stages/0-bootstrap/service_accounts.tf:185`.
Si falla: como el punto 97.

**129. VM DNS de `onprem-sim`.**
Qué: con `onprem_dns_vm = true` (exige `simulate_onprem`): que la imagen `debian-12` traiga
`python3` y `systemd`, que el servicio `onprem-dns` arranque (`systemctl status onprem-dns` por
SSH con IAP) y que desde una VM de un spoke `dig dns.<onprem_dns_domain>` devuelva la IP de la VM
por zona de peering → zona de reenvío → VPN → `onprem-sim`. Orden: `0-bootstrap` → `1-base` →
hub. Ver también puntos 7 y 36.
Dónde: `stages/2-networks/onprem_dns.tf:18`; `stages/2-networks/dns.tf:12`;
`stages/2-networks/firewall.tf:42`.
Si falla: sin indicación en el código. Revisar el arranque en la salida del puerto serie (punto
130). Si falta un paso del orden, el apply del hub falla al crear la VM (falla cerrado, README
de `stages/2-networks`).

**130. Registros de la VM DNS.**
Qué: que los registros del arranque lleguen a Cloud Logging. `onprem-sim` no tiene ruta a las
API de Google, así que quizá solo queden en la salida del puerto serie 1
(`gcloud compute instances get-serial-port-output`).
Dónde: `stages/2-networks/onprem_dns.tf:22`.
Si falla: leer la salida del puerto serie 1 (lo sugiere el código).

**131. Cuentas de ejecución de `1-base` usables por `3-workloads`.**
Qué: que `3-workloads` use en el apply siguiente las cuentas que creó `1-base` (nodos de GKE,
plantilla del MIG, Cloud Run, usuarios IAM de Cloud SQL y trabajos de Cloud Scheduler) sin
errores de propagación, y que la postcondición de `remote_state.tf` las encuentre en
`runtime_service_accounts`. Reemplaza al punto 114 (resuelto en el código).
Dónde: `stages/1-base/runtime_accounts.tf:174`; `stages/3-workloads/envs/*/remote_state.tf:21`.
Si falla: sin indicación en el código; repetir el apply de `3-workloads` (propuesta). Si falla
la postcondición, `applications` de `1-base` no incluye la aplicación (lo dice el mensaje).

**132. Usuarios IAM de Cloud SQL sin actAs.**
Qué: que `tf-wl-<env>` cree los usuarios IAM de Cloud SQL de `workload`, `run` y `mig` sin
`serviceAccountUser` sobre `workload`: solo lo tiene sobre `gke_nodes`, `mig`, `run` y `sched`
de su entorno. Ver también punto 14.
Dónde: `stages/1-base/runtime_accounts.tf:64`.
Si falla: sin indicación en el código; agregar `workload` a `attached_uses` de `1-base`
(propuesta).

**133. Condición de Cloud SQL por instancias del entorno.**
Qué: que `cloudsql.client` y `cloudsql.instanceUser`, que `1-base` da a `workload`, `run` y
`mig` con la condición
`resource.name.startsWith("projects/<proyecto>/instances/<prefix>-<env>-data-")`, dejen entrar
con un token IAM a la instancia del entorno y nieguen la de otro entorno. El formato sale de la
documentación de condiciones de Cloud SQL que cita el código. Ver también punto 14.
Dónde: `stages/1-base/runtime_accounts.tf:104`.
Si falla: sin indicación en el código; corregir la expresión con el nombre que muestre el error
(propuesta).

**134. Rol del apagado que da `1-base`.**
Qué: que `<prefix>OffHoursScheduler`, que `1-base` da sin condición a la cuenta
`<prefix>-<env>-<app>-sched` de los entornos de `off_hours_environments` (nunca prod), baste
para las tres llamadas de los trabajos (`gcloud scheduler jobs run` de cada uno con respuesta
2xx). Ver también puntos 70 y 73.
Dónde: `stages/1-base/runtime_accounts.tf:140`.
Si falla: como el punto 73.

**135. Enlace de Workload Identity después del primer clúster.**
Qué: que con `gke_workload_identity_bindings = true` la asignación falle antes de que exista el
pool `<proyecto>.svc.id.goog` y funcione después del primer clúster (`gcloud iam
workload-identity-pools describe <proyecto>.svc.id.goog --location=global`), y que un pod de
`<app>-<env>` con la cuenta de Kubernetes anotada obtenga el token de la cuenta `workload`.
Orden: apply de `3-workloads` con `enable_gke`, `gke_workload_identity_bindings = true` en
`1-base` y apply de `1-base`. Ver también punto 46.
Dónde: `stages/1-base/runtime_accounts.tf:232`; aviso `workload_identity_enlazada` en
`stages/3-workloads/envs/*/service_accounts.tf:33`.
Si falla: dejar `gke_workload_identity_bindings = false` hasta el primer clúster (lo dice el
código).

**136. Etiquetas seguras sin `tagUser` de proyecto para `tf-wl-<env>`.**
Qué: que `tf-wl-<env>` cree la plantilla del MIG y los pools de GKE con `lb_backend` e
`iap_ssh` con el `tagUser` sobre esos valores que le da el spoke, sin `tagUser` de proyecto
(`gcloud resource-manager tags bindings list --parent=<recurso>` muestra el enlace); que el
agente de GKE, con `tagHoldAdmin` sobre `lb_backend` (spoke) y `tagUser` de proyecto (punto
137), ligue la etiqueta a los nodos; y que `tf-net-<env>` pueda asignar esos permisos con
`TfNetworkTagManager` (`tagValues.setIamPolicy`). Ver también puntos 100 y 104 (resuelto en el
código).
Dónde: `stages/2-networks/envs/*/firewall.tf:136`; `stages/3-workloads/envs/*/main.tf:59`;
`modules/gke/main.tf:242`.
Si falla: sin indicación en el código; dar el permiso que nombre el error sobre el valor, desde
el spoke (propuesta). No dar `tagUser` de proyecto a `tf-wl-<env>`: trae
`iam.serviceAccounts.deleteTagBinding`, que la denegación no puede negar (lo dice el código en
`stages/0-bootstrap/service_accounts.tf:218`).

**137. `tagUser` de proyecto de los agentes desde `0-bootstrap`.**
Qué: que el agente de GKE exista justo después de habilitar `container` y que `tagUser` de
proyecto, para él y para `<número>@cloudservices`, baste para crear nodos y VM con
`resource_manager_tags`. Va en `0-bootstrap` y no en `1-base` para que `tf-base` no pueda
asignar `tagUser`. Limitarlo a los valores no está documentado para etiquetas del mismo
proyecto (HYPOTHESIS del código): queda como riesgo aceptado de dos agentes de Google. Con esto
el punto 104 queda resuelto en el código.
Dónde: `stages/0-bootstrap/main.tf:153`.
Si falla: si el agente no existía, el binding falla y se repite el apply de la etapa 0 (lo dice
el código).

**138. Canal de operaciones.**
Qué: con `operations_alert_email` en `1-base`: que la API acepte el correo (como el de
`audit-alerts`), que `1-base` publique el canal en `notification_channel_ids["operations"]` y
que las alertas de los entornos (`3-workloads`) lleguen ahí y no al canal de seguridad. Sin la
variable el canal no se crea y cada entorno avisa solo a sus `notification_emails`. Ver también
punto 58.
Dónde: `stages/1-base/main.tf:152`; `stages/3-workloads/envs/*/remote_state.tf:122`.
Si falla: sin indicación en el código; permitir remitentes externos en la lista (propuesta, como
el punto 58).

**139. Binary Authorization con atestadores por entorno.**
Qué: con `binary_authorization_env_attestors` en `1-base`: que una imagen con solo la
atestación de dev se rechace en un clúster de prod; que el agente de Binary Authorization del
proyecto pueda leer cada atestador (si está en otro proyecto necesita
`roles/binaryauthorization.attestorsVerifier` allí; los atestadores no los crea el repositorio);
y que Cloud Run, que solo tiene la regla por defecto, exija el atestador del primer entorno de la
promoción que tenga uno (riesgo escrito en el código: Cloud Run de qa y prod solo exige ese). Sin
la variable sigue el modo de la lista global (punto 42).
Dónde: `stages/1-base/artifacts.tf:163`; los dos modos en `stages/1-base/artifacts.tf:30`.
Si falla: sin indicación en el código; volver al modo sin atestadores por entorno mientras se
corrige (propuesta).

**140. Restos de GKE en Cloud Asset.**
Qué: en el primer destroy de dev: qué trae Cloud Asset para discos, NEG y firewalls que deja GKE
(`description`, `labels`, `network` en `additionalAttributes`); que los nombres `gke-*` y
`k8s1-*` lleven el clúster y el namespace sin recortar; y que el controlador de PD escriba el
namespace en la descripción. Con eso `destroy-orphans.py` atribuye los restos al entorno; los
que no puede atribuir los avisa sin fallar. Los formatos de los datos de prueba
(`scripts/testdata/destroy/assets-gke.json`) son HYPOTHESIS. Ver también punto 85.
Dónde: `scripts/destroy-orphans.py:77`.
Si falla: corregir la regla con el formato real y agregar su caso en `scripts/selftest.sh`
(propuesta, como el punto 85).

**141. `versionedResources` en el listado de Cloud Asset.**
Qué: `destroy-orphans.py` busca la red de un resto de GKE también en
`versionedResources[].resource`, pero las llamadas a `gcloud asset search-all-resources` de
`destroy.yml` y `drift.yml` no pasan `--read-mask`. Que el listado traiga `versionedResources`
sin pedirlo es HYPOTHESIS (esta revisión no consultó la referencia de la API). Comprobar en el
primer destroy si el JSON trae el campo.
Dónde: `scripts/destroy-orphans.py:127` y `:204`; `.github/workflows/destroy.yml:221`;
`.github/workflows/drift.yml:271`.
Si falla: agregar `--read-mask` con ese campo a la llamada de `destroy.yml` y su caso en
`scripts/selftest.sh` (propuesta). Sin el campo, la regla por red solo usa
`additionalAttributes`.

**142. Nombre de los DockerImage en Cloud Asset.**
Qué: que Cloud Asset nombre las imágenes
`projects/<número>/locations/<ubicación>/repositories/<repositorio>/dockerImages/<imagen>`,
la forma que cubre la regla de `unmanaged-allowlist.txt` (el archivo dice que el formato está
sin comprobar en el proyecto real), y que un repositorio creado a mano siga saliendo como no
administrado. Ver también punto 49.
Dónde: `scripts/unmanaged-allowlist.txt:44` (regla); marcador en
`scripts/unmanaged-allowlist.txt:11`.
Si falla: corregir la regla con el nombre real, solo para la imagen y nunca para el repositorio
(propuesta, como el punto 49).

**143. `!cancelled()` y trabajos omitidos con `GCP_DISABLED_ENVS`.**
Qué: en la primera ejecución de `apply.yml` con `GCP_DISABLED_ENVS=dev`: que los trabajos de
dev se omitan y que qa empiece después del hub y prod después de qa, porque `!cancelled()` deja
evaluar la condición y un trabajo omitido solo cuenta como listo si su entorno está apagado; y
que con dev encendido y su prueba de humo fallida, qa y prod no corran. Con `prod` en la
variable, el trabajo `gate` falla. `scripts/disabled-envs.py` está probado en
`scripts/selftest.sh`; el orden de los trabajos en GitHub es HYPOTHESIS.
Dónde: `.github/workflows/apply.yml:268` (y el comentario de las líneas 10 a 21);
`scripts/disabled-envs.py`.
Si falla: dejar `GCP_DISABLED_ENVS` vacía (todos los entornos se despliegan) y corregir la
condición del trabajo que no corrió o que corrió de más (propuesta).

**144. Patrones `!` de `paths` en `apply.yml`.**
Qué: que un merge a `main` que solo cambia `gcp-datacenter/docs/**` o archivos `.md` de
`gcp-datacenter/` no dispare `apply.yml` (el último patrón que coincide decide, según el
comentario del flujo), y que uno que también cambia un `.tf` o un flujo sí lo dispare. `pr.yml`
corre siempre.
Dónde: `.github/workflows/apply.yml:63`.
Si falla: si un cambio de código no lo dispara, lanzar `apply.yml` a mano (`workflow_dispatch`)
y corregir la lista; si lo dispara un cambio de solo documentación, el apply da "sin cambios"
(propuesta).

**145. Omisiones `[sin-organizacion]` de Terratest.**
Qué: con `TERRATEST_ORG_ID` vacío: que `TestOrg` y `TestVPCSC` se omitan con la marca
`[sin-organizacion]` en el motivo, que `scripts/go-test-report.sh` las liste sin contarlas
contra `TERRATEST_MAX_SKIPS` y que cualquier otra omisión siga contando. El script está probado
en `scripts/selftest.sh` con salidas de ejemplo; que la corrida de GitHub las dé igual es
HYPOTHESIS.
Dónde: `scripts/go-test-report.sh:62`; `tests/helpers/env.go:128` (`OrgSkipMarker`) y
`tests/helpers/env.go:133` (`RequireOrganization`).
Si falla: corregir la marca o el filtro del script con su caso en `scripts/selftest.sh`
(propuesta); mientras tanto `terratest.yml` sigue en rojo (§5).

**146. Primer plan real de las raíces de entorno con las reglas 11 y 12.**
Qué: que el primer plan real de `2-networks/envs/<env>` y `3-workloads/envs/<env>` pase sin
rechazos de `env_root_scope` (recursos únicos del proyecto, tipos de `1-base`, permisos de
proyecto para principales ajenos y nombres sin `<prefix>-<env>-`) ni de `resource_locations`.
Las dos reglas se probaron con planes de ejemplo, no con un plan contra GCP (§5, "Planes de
ejemplo de Conftest").
Dónde: `policies/env_root_scope.rego:1`; `policies/resource_locations.rego:1`.
Si falla: un rechazo de algo que el diseño permite se corrige en la regla, con su prueba y
revisión de seguridad; uno real se corrige en la raíz (propuesta).

**147. Primer plan real de `0-bootstrap` y `1-base` con `resource_locations`.**
Qué: que la lista de ubicaciones permitidas (`us-central1`, `us-east4` y sus zonas, `us` y
`global`) admita los llaveros de `us`, la notificación de SCC en `global`, el bucket de estado
en `US` y cualquier otra ubicación de los planes reales de esas raíces. Es la misma lista que la
política de organización (punto 3), escrita aparte.
Dónde: `policies/resource_locations.rego:31`.
Si falla: agregar la ubicación a la regla y a `additional_allowed_locations` de `0-bootstrap`
juntas (propuesta).

**148. `TestOrg`: políticas con padre proyecto y su destroy.**
Qué: con organización (`TERRATEST_ORG_ID` y `TEST_ALLOW_ORG`): que la prueba cree las políticas
de `modules/org` con padre `projects/<id>` en el proyecto de pruebas (la cuenta necesita
`roles/orgpolicy.policyAdmin`, que solo se da en la organización), que las lea con su valor y
que el destroy las quite. No corre en paralelo: las políticas valen para todo el proyecto
mientras dura. Ver también puntos 125 y 145.
Dónde: `tests/integration/org_test.go:38`.
Si falla: corregir la prueba o el módulo según lo que devuelva la API (propuesta).

**149. `TestLogExport`: filtro de la exclusión.**
Qué: que `exclusions[].filter` de `gcloud logging sinks describe` sea idéntico a la salida
`exclusion_filter` del fixture; que la API no normalice el texto es HYPOTHESIS. Ver también
punto 108.
Dónde: `tests/integration/log_export_test.go:53`.
Si falla: comparar con la forma que devuelva la API (propuesta).

**150. Roles de la cuenta de la bóveda de Backup and DR.**
Qué: que la cuenta de servicio de la bóveda (salida `vault_service_account` de
`modules/backup-dr`) tenga los roles que pide Backup and DR sobre los recursos protegidos.
Ninguna raíz los da: la cuenta solo se conoce después de crear la bóveda (`3-workloads`) y
`tf-wl-<env>` no asigna roles de proyecto (lo dice el código). Se espera que el primer respaldo
falle sin ellos (HYPOTHESIS). Comprobar también el formato del recurso de Cloud SQL en la
asociación.
Dónde: `modules/backup-dr/main.tf:35`; `stages/3-workloads/envs/*/operations.tf:66`.
Si falla: sin indicación en el código. Propuesta no construida: que la persona dueña del
proyecto dé los roles después del primer apply de `3-workloads` y se anote, o definir qué raíz
los da.

**151. Plan del hub con `simulate_onprem = false`.**
Qué: con on-premises real, el hub lee el secreto de la VPN con una fuente de datos en cada plan,
también en los trabajos `plan` que usan `tf-read`. `tf-read` no tiene `secretAccessor` y la
denegación de `0-bootstrap` le niega `secretmanager.versions.access`, así que el plan del hub
debe fallar en el pipeline (falla cerrado: el secreto no sale). Verificar que falla por la
denegación y no por otra causa. Mientras siga así, el modo real no se puede aplicar desde el
pipeline: limitación conocida (§5).
Dónde: `stages/2-networks/vpn.tf:98`.
Si falla (el plan pasa): revisar qué identidad leyó el secreto; `tf-read` no debe leerlo
(propuesta). Las salidas propuestas para la limitación están en §5.

---

## 4. Marcadores `VERIFICAR-EN-APPLY` del código

Conteo al 24 nov 2026 (código de `6d27623`), desde `gcp-datacenter/`:

```bash
grep -rn "VERIFICAR-EN-APPLY" modules stages --include=*.tf | wc -l                       # 131
grep -rln "VERIFICAR-EN-APPLY" modules stages --include=*.tf | wc -l                      # 53 archivos
grep -rn "VERIFICAR-EN-APPLY" modules --include=*.tf | wc -l                              # 56
grep -rn "VERIFICAR-EN-APPLY" stages --include=*.tf | grep -v /envs/ | wc -l              # 48
grep -rn "VERIFICAR-EN-APPLY" stages --include=*.tf | grep /envs/ | wc -l                 # 27 (9 por entorno)
grep -rn "VERIFICAR-EN-APPLY" tests --include=*.tf | wc -l                                # 4 (fuera del conteo)
```

Las raíces de `envs/{dev,qa,prod}` tienen sus marcadores en las mismas líneas (3 en cada spoke
de `2-networks` y 6 en cada raíz de `3-workloads`), así que se listan una vez con `envs/*` y
"(x3)": las 131 líneas son 113 marcadores distintos (56 en módulos, 48 en etapas fuera de
`envs/` y 9 en `envs/*`). Cada fila de las tablas de abajo apunta a una línea con el marcador
y cada marcador tiene su fila: lo comprueba un script que lee las tablas y el código, y en los
`envs/*` exige el marcador en la misma línea de dev, qa y prod (resultado del 24 nov 2026:
"malas: 0; marcadores sin fila: 0"). Fuera de los `.tf`, los README, el pipeline, los scripts y
las pruebas tienen marcadores propios (al final de esta sección). "Si falla" cita el código
cuando lo dice; si no, la entrada dice "sin indicación".

### Etapa 0 (`stages/0-bootstrap`)

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `custom_roles.tf:6` | Permisos de los cuatro roles personalizados admitidos en roles de proyecto (punto 33) | Ver punto 33 |
| `custom_roles.tf:92` | Los tres permisos de `<prefix>OffHoursScheduler` bastan para las tres llamadas de los trabajos (puntos 73 y 134) | Ver punto 73 |
| `deny_policy.tf:87` | Con la regla sin etiqueta ampliada a tokens y firmas, Cloud Scheduler con `oauth_token` de `sched` y GKE con `gke-nodes` siguen funcionando (punto 127) | Ver punto 127 |
| `deny_policy.tf:111` | Llave de etiqueta con padre proyecto en un proyecto sin organización, y la persona puede ligarla (punto 90) | `enable_protection_tags = false` (punto 90) |
| `deny_policy.tf:133` | Bucket y llavero del estado aceptan la etiqueta; la llave la hereda (punto 91) | Ver punto 91 |
| `deny_policy.tf:152` | Formato del enlace de etiqueta de las cuentas por ID único (punto 92) | Ver punto 92 |
| `deny_policy.tf:168` | `iam.denyAdmin` de la persona, proyecto como padre y las dos reglas de la denegación (punto 93) | Ver punto 93 |
| `main.tf:77` | `generateServiceIdentity` de cada servicio y agentes de `container`, `compute` y `run` al habilitar sus APIs (punto 94) | Agregar el servicio a la lista (lo dice el código) |
| `main.tf:122` | OS Login en el proyecto: `OS_LOGIN_DISABLED` no lo marca y SSH por IAP con `roles/compute.osLogin` (punto 59) | Ver punto 59 |
| `main.tf:136` | `DEPRIVILEGE` deja la cuenta de Compute por defecto sin `roles/editor` (punto 95) | Ver punto 95 |
| `main.tf:153` | Agente de GKE disponible al habilitar `container`; `tagUser` de proyecto del agente y de `<número>@cloudservices` basta para nodos y VM con etiquetas (punto 137) | Repetir el apply (lo dice el código) |
| `main.tf:263` | Doble región válida en `state_bucket_dual_regions` (punto 31) | Ver punto 31 |
| `main.tf:266` | Permiso del agente de Cloud Storage sobre la llave al crear el bucket (punto 13) | Repetir el apply (propagación de IAM) |
| `main.tf:275` | Presupuesto limitado al proyecto por `projects/<número>` y avisos por correo (punto 96) | Ver punto 96 |
| `org.tf:12` | Con organización: la persona crea las políticas con padre proyecto y `iam.allowedPolicyMemberDomains` no rechaza WIF ni agentes (punto 125) | Ver punto 125 |
| `org.tf:34` | Con `access_policy_id`: la persona crea el perímetro en dry-run y registra violaciones sin bloquear (puntos 5 y 126) | Ver punto 126 |
| `providers.tf:5` | Primer plan con `cloudresourcemanager`, `serviceusage` y `storage` habilitadas (punto 22) | `gcloud services enable` antes del primer plan (lo dice el código) |
| `service_accounts.tf:11` | Cada raíz aplica con su cuenta y sus roles de proyecto (punto 97) | Agregar el rol más chico aquí, nunca en la raíz (lo dice el código) |
| `service_accounts.tf:72` | `storage.buckets.create` con la condición de prefijo (punto 98) | Cláusula `resource.type` de proyecto (lo dice el código) |
| `service_accounts.tf:88` | Condición `modifiedGrantsByRole` en el proyecto, configuración de auditoría de `1-base` y rechazo de otro rol (punto 28) | Ver punto 28 |
| `service_accounts.tf:172` | Hub y spokes aplican con los roles de red (punto 100) | Ver punto 100 |
| `service_accounts.tf:185` | Con `onprem_dns_vm`: el hub crea la VM DNS con `compute.instanceAdmin.v1`, y sin él no (punto 128) | Ver punto 128 |
| `service_accounts.tf:233` | `roles/viewer` alcanza para refrescar todo y `networkmanagement.admin` para las Connectivity Tests (punto 50) | Ver punto 50 |
| `service_accounts.tf:258` | `init`/`plan`/`apply` del backend con las condiciones de estado (punto 1) | Managed folders con IAM propio por prefijo |
| `wif.tf:36` | `job_workflow_ref` y `ref` del trabajo `apply` de `_terraform-root.yml` dan `attribute.deploy` igual a su entorno (punto 123) | Ver punto 123 |
| `wif.tf:81` | Trabajo sin entorno: obtiene `tf-read` con `attribute.environment` y `attribute.deploy` en `none` (punto 124) | Ver punto 124 |

### Etapa 1 (`stages/1-base`)

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `artifacts.tf:89` | CMEK del repositorio de Artifact Registry (punto 41) | Ver punto 41 |
| `artifacts.tf:163` | Binary Authorization: la imagen de un repositorio del proyecto pasa y otra se rechaza (punto 42); con atestadores por entorno, una imagen de dev no entra a prod (punto 139) | Ver puntos 42 y 139 |
| `kms.tf:70` | Cada agente existe antes de recibir el permiso sobre su llave y puede cifrar (punto 103) | Ver punto 103 |
| `main.tf:56` | `tf-base` escribe la configuración de auditoría con la condición y aparecen los registros de acceso a datos (punto 28) | Ver punto 28 |
| `main.tf:152` | Canal de operaciones: la lista acepta correo de Cloud Monitoring (punto 138) | Ver punto 138 |
| `main.tf:167` | Contactos esenciales en el proyecto e idioma (punto 57) | Ver punto 57 |
| `main.tf:194` | SCC publica en el tema con `enforce_in_transit = true` (punto 34) | Ver punto 34 |
| `main.tf:203` | Notificación de proyecto de SCC y permiso de publicación de la cuenta de SCC (puntos 2 y 23) | Ver punto 2 |
| `providers.tf:4` | Todas las APIs aceptan el proyecto de cuota (punto 105) | Sin indicación |
| `runtime_accounts.tf:64` | Usuarios IAM de Cloud SQL de `workload`, `run` y `mig` sin actAs (punto 132) | Ver punto 132 |
| `runtime_accounts.tf:104` | Condición de Cloud SQL por instancias del entorno: entra al suyo, no al de otro entorno (punto 133) | Ver punto 133 |
| `runtime_accounts.tf:140` | El rol del apagado basta para las tres llamadas; concesión sin condición (puntos 73 y 134) | Ver punto 73 |
| `runtime_accounts.tf:174` | Cuentas de ejecución usables por `3-workloads` en el apply siguiente (punto 131) | Ver punto 131 |
| `runtime_accounts.tf:232` | Enlace de Workload Identity: falla sin el pool y funciona después del primer clúster (puntos 46 y 135) | `gke_workload_identity_bindings = false` hasta el primer clúster (lo dice el código) |

### Etapa 2, hub (`stages/2-networks`)

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `dns.tf:12` | Resolución de `onprem_dns_domain` desde un spoke con la VM DNS de `onprem-sim` (puntos 7, 36 y 129) | Ver punto 36 |
| `dns.tf:43` | Registro de Cloud DNS en la VPC `onprem-sim` y detector `DNS_LOGGING_DISABLED` (punto 61) | Ver punto 61 |
| `firewall.tf:22` | VPN, BGP y DNS entrante con la denegación de la política de la VPC hub (punto 112) | Regla `allow` desde `onprem_cidrs`, TCP y UDP 53 (lo dice el código) |
| `firewall.tf:42` | La VM DNS de `onprem-sim` responde a un spoke y la respuesta vuelve por la ruta anunciada (puntos 36 y 129) | Ver punto 36 |
| `onprem_dns.tf:18` | VM DNS: `python3` y `systemd` en `debian-12`, servicio `onprem-dns` y `dig` desde un spoke (punto 129) | Ver punto 129 |
| `onprem_dns.tf:22` | Registros del arranque en Cloud Logging o solo en el puerto serie (punto 130) | Leer el puerto serie 1 (lo sugiere el código) |
| `vpn.tf:98` | Con `simulate_onprem = false`, el plan con `tf-read` falla por la denegación (punto 151) | Limitación conocida (§5) |
| `vpn.tf:140` | Anuncios de las dos VPN, preferencia por la primaria y paso a la de DR (punto 37) | Ver punto 37 |

### Etapa 2, spokes (`stages/2-networks/envs/*`)

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `dns.tf:27` (x3) | Imágenes de `pkg.dev` y llamadas a `*.run.app` por el VIP elegido (punto 40) | Ver punto 40 |
| `dns.tf:63` (x3) | `tf-net-<env>` adjunta la zona a la VPC hub y on-premises la resuelve (punto 113) | Sin indicación |
| `firewall.tf:136` (x3) | `tf-wl-<env>` crea la plantilla del MIG y los pools con `tagUser` sobre los valores y sin `tagUser` de proyecto; `tf-net-<env>` lo asigna con `TfNetworkTagManager` (punto 136) | Ver punto 136 |

### Etapa 3 (`stages/3-workloads/envs/*`)

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `load_balancing.tf:98` (x3) | Que el mismo grupo de instancias y el mismo NEG sin servidor sirvan a la vez al balanceador externo y al interno | Sin indicación |
| `load_balancing.tf:193` (x3) | El certificado administrado se activa cuando los registros A de `domain_names` apuntan a `lb_ip_address` | Crear los registros en la zona pública (fuera del repositorio) |
| `load_balancing.tf:234` (x3) | Registros de `internal_lb_dns_authorization_records_by_region` y certificado interno de DR `ACTIVE` sin balanceador (punto 54) | Ver punto 54 |
| `main.tf:59` (x3) | El `tagUser` sobre los valores basta para la plantilla del MIG y los pools con etiquetas (punto 136; el 104 quedó resuelto en el código) | Ver punto 136 |
| `operations.tf:58` (x3) | Con `off_hours_shutdown`: respaldo diario de Cloud SQL dentro de la ventana movida y qué pasa los días apagados (punto 76) | Ver punto 76 |
| `operations.tf:66` (x3) | Formato del recurso de Cloud SQL en la asociación de Backup and DR y roles de la cuenta de la bóveda (punto 150) | Ver punto 150 |

### Módulos

| Archivo:línea | Qué verificar | Si falla |
|---|---|---|
| `audit-alerts/main.tf:12` | Que SHA reconozca los filtros de una sola línea y dé por buenas las alertas (punto 58) | Ver punto 58 |
| `audit-alerts/main.tf:23` | Tipo de recurso con que llegan las series de cada métrica (`global`, `gcs_bucket`, `cloudsql_database`) (punto 58) | Ver punto 58 |
| `audit-alerts/main.tf:151` | El buzón acepta correo de Cloud Monitoring (punto 58) | Ver punto 58 |
| `audit-alerts/main.tf:183` | Alerta aceptada justo después de crear la métrica (punto 58) | Repetir el apply (lo dice el código) |
| `backup-dr/main.tf:19` | API `backupdr` habilitada en el proyecto (la habilita `0-bootstrap`) y bóveda en otra región que acepte respaldos de VM y Cloud SQL | Sin indicación |
| `backup-dr/main.tf:21` | El destroy de dev falla mientras la bóveda tenga respaldos dentro de la retención forzada | Ver punto 86 (`destroy.yml` lo avisa en el plan; para la prueba, `enable_backup = false` en dev) |
| `backup-dr/main.tf:35` | Plan de Cloud SQL (`sqladmin.googleapis.com/Instance`) en el proveedor 6.x y roles de la cuenta de la bóveda (salida `vault_service_account`), que ninguna raíz da (punto 150) | Ver punto 150 |
| `backup-dr/main.tf:53` | `log_retention_days` aceptado y recuperación a un punto en el tiempo de esos días (punto 45) | Ver punto 45 |
| `backup-dr/main.tf:87` | Backup for GKE en otra región, complemento activo y permiso del agente de `gkebackup` sobre la llave | Sin indicación |
| `cloud-run/main.tf:10` | Salida directa a la VPC con la red y la subred del spoke como `projects/<proyecto>/...` | Sin indicación |
| `cloud-run/main.tf:35` | `invoker_iam_disabled` y `run.app` no alcanzable desde internet (punto 16) | Ver punto 16 |
| `cloud-sql/main.tf:10` | `pgaudit.log` con varias clases; la réplica acepta las mismas banderas | Ver punto 14 |
| `cloud-sql/main.tf:103` | Segundo plan sin cambios en `backup_configuration` con el plan de Backup and DR asociado (punto 45) | `ignore_changes` sobre ese bloque (lo dice el código) |
| `cloud-sql/main.tf:206` | Agente de Cloud SQL con permiso sobre `kms_key` (lo da `1-base`, punto 103) | Sin indicación |
| `cloud-sql/main.tf:208` | Conexión de PSA de la red existente antes del create (punto 111) | Sin indicación |
| `cloud-sql/main.tf:217` | Con la instancia detenida a mano y `allow_scheduled_stop = false`, el plan falla con el mensaje de la `postcondition`; con `true`, sin cambios en `activation_policy` (punto 75) | Ver punto 75 |
| `cloud-sql/main.tf:351` | Réplica REGIONAL entre regiones con CMEK; retraso de replicación por debajo de 15 min | Si el retraso supera 15 min, el objetivo de RPO no se cumple (README del módulo) |
| `cloud-sql/main.tf:387` | Roles condicionados por `resource.name` y entrada con token IAM, solo con `grant_iam_login_roles = true`: las raíces pasan `false` y los da `1-base` (puntos 14 y 133) | Ver punto 14 |
| `compute-mig/main.tf:72` | Etiquetas seguras de la plantilla en las instancias y reglas `lb_backend` aplicadas | Sin indicación |
| `compute-mig/main.tf:164` | `max_surge_fixed` igual al número de zonas del MIG regional | Sin indicación |
| `compute-mig/main.tf:208` | Con `business_hours`: política sin señal de CPU, 0 VM fuera del horario y `min_replicas` dentro (punto 72) | Ver punto 72 |
| `dns/main.tf:92` | El filtro devuelve las IP de reenvío entrante (y solo esas) al terminar el apply | Sin indicación |
| `filestore/main.tf:48` | Permiso del agente sobre la llave (lo da `1-base`), PSA sobre la VPC del spoke y `deletion_protection_enabled` en el tier | Sin indicación |
| `firewall/main.tf:25` | Etiquetas seguras con padre proyecto sin organización y formato de `purpose_data` (punto 110) | Ver punto 110 |
| `gke/main.tf:47` | Plano de control con Private Service Connect (punto 8) | Ver punto 8 |
| `gke/main.tf:59` | Endpoint privado alcanzable desde la VPC del spoke y los rangos autorizados (el peering del plano de control no es transitivo) | Bastión en el spoke o endpoint por DNS (no construido, README del módulo) |
| `gke/main.tf:145` | `node_config` del pool por defecto eliminado sin diferencias en el segundo plan | Ya se ignora en `lifecycle` |
| `gke/main.tf:242` | Nodos con las etiquetas seguras del spoke: `tagUser` de proyecto del agente (0-bootstrap), `tagHoldAdmin` y `tagUser` sobre el valor (spoke) (puntos 136 y 137) | Ver punto 136 |
| `gke/main.tf:279` | Con `scheduled_scaling`: plan sin cambios en los pools y el clúster después de un apagado y un encendido (punto 71) | Ver punto 71 |
| `hybrid-connectivity/main.tf:143` | Interfaces y sesiones BGP de los attachments DEDICATED y PARTNER | Sin indicación |
| `load-balancer/main.tf:187` | Certificado administrado ACTIVE cuando los registros A apuntan a la IP; puede tardar hasta 60 min | Crear los registros A |
| `load-balancer/main.tf:357` | Certificado interno tras los registros de `dns_authorization_records`; una CA pública no emite para `*.internal` | Usar `certificate_manager_certificates` |
| `load-balancer/main.tf:463` | On-premises llega al balanceador interno de DR por las dos VPN (punto 44) | Ver punto 44 |
| `log-export/main.tf:18` | Que la API de Cloud Storage acepte el número de proyecto (`project_number`); ninguna raíz lo pasa (punto 27, obsoleto) | Sin indicación |
| `log-export/main.tf:54` | Bloqueo sobre un bucket ya creado (punto 15) | Ver punto 15 |
| `log-export/main.tf:86` | Permiso del agente de Cloud Storage sobre la llave al crear el bucket (punto 15) | Repetir el apply |
| `log-export/main.tf:96` | Exclusiones del sink y escritura de su identidad en el bucket con CMEK (puntos 108 y 149) | Sin indicación |
| `memorystore/main.tf:65` | Permiso del agente sobre la llave (lo da `1-base`) y PSA sobre la VPC del spoke | Sin indicación |
| `network-hub/variables.tf:104` | Flow logs al 100 % sin hallazgo de `VPC_FLOW_LOGS_SETTINGS_NOT_RECOMMENDED` y volumen contra la estimación (punto 62) | Ver punto 62 |
| `network-spoke/main.tf:160` | Una conexión de PSA por VPC spoke del proyecto y su destroy después de borrar las instancias de `3-workloads` (puntos 87 y 111) | Ver punto 87 (volver a lanzar `destroy.yml` pasado el plazo que documenta PSA) |
| `network-spoke/main.tf:186` | Dos spokes no crean su peering a la vez; las rutas BGP llegan al spoke (punto 6) | El pipeline aplica los entornos en serie |
| `network-spoke/variables.tf:115` | Lo mismo en los spokes; dev y qa con 0.5 sí se marcan (punto 62) | Ver punto 62 |
| `observability/main.tf:13` | `starts_with()` y `metadata.user_labels.env` aceptados en alertas, SLO y tablero; cada entorno ve solo sus series (punto 115) | Sin indicación |
| `observability/main.tf:75` | Los buzones de `notification_emails` existen y aceptan las alertas | Sin indicación |
| `observability/main.tf:223` | La alerta de memoria de VM necesita Ops Agent | Sin él la condición queda sin datos |
| `observability/main.tf:308` | SLI por solicitudes con los filtros del balanceador y `select_slo_burn_rate` con tráfico real | Sin indicación |
| `off-hours-shutdown/main.tf:97` | Trabajos de Cloud Scheduler en 2xx con el token de la cuenta `-sched` y operación de la API en `DONE` (puntos 70 y 71) | Ver punto 70 |
| `off-hours-shutdown/main.tf:101` | `setSize` de un pool regional cuenta `nodeCount` por zona; la operación del primer paso termina antes del segundo (punto 71) | Ver punto 71 |
| `org/main.tf:22` | Con organización: ubicaciones permitidas (punto 3) | Ver punto 3 |
| `org/main.tf:56` | Con organización: agentes de servicio y WIF con `iam.allowedPolicyMemberDomains` (puntos 106 y 125) | Sin indicación |
| `org/main.tf:67` | Con organización: política con padre proyecto y `orgpolicy.policyAdmin` de la persona que aplica `0-bootstrap` (punto 125; el 107 quedó resuelto en el código) | Ver punto 125 |
| `secrets/main.tf:21` | Agente de Secret Manager con permiso sobre las llaves antes de crear los secretos | Lo da la raíz que llama al módulo (`1-base`) |
| `storage/main.tf:86` | Agente de Cloud Storage con permiso sobre la llave (lo da `1-base`); llave de `us` para un bucket con `custom_placement_config` | Sin indicación |
| `storage/main.tf:89` | Con organización: `gcp.resourceLocations` y la doble región (punto 3) | Ver punto 3 |
| `vpc-sc/main.tf:42` | Con `access_policy_id`: perímetro en dry-run sin bloque `status` (puntos 109 y 126) | Sin indicación |
| `vpc-sc/main.tf:140` | Con `access_policy_id`: regla de entrada de las cuentas del pipeline (puntos 5 y 126) | Ver punto 5 |

### Marcadores fuera de los `.tf`

No entran en el conteo de arriba. Líneas al 24 nov 2026 (código de `6d27623`); los README que
se están editando en esta misma revisión (`tests/README.md`) se citan sin línea.

| Archivo y línea | Qué verificar | Punto |
|---|---|---|
| `stages/2-networks/README.md`, línea 84 | La VPN y el reenvío DNS entrante con la denegación de la política del hub | 112 |
| `stages/2-networks/README.md`, línea 92 | VM DNS de `onprem-sim`: `python3`, el servicio y `dig` desde un spoke | 129 |
| `stages/2-networks/README.md`, línea 108, "Enrutamiento con dos VPN" | Regreso asimétrico entre las dos VPN | 38 |
| `stages/2-networks/README.md`, línea 144 | `compute.securityAdmin` alcanza para las políticas de firewall de red globales | 100 |
| `stages/2-networks/envs/*/README.md` (x3), línea 126 | Los roles del spoke alcanzan, en especial `servicenetworking.networksAdmin` y el rol de etiquetas sin organización | 100 y 136 |
| `.github/workflows/_terraform-root.yml`, líneas 16 y 33 | `tf-read` refresca cada recurso; misma huella que el apply | 50 y 117 |
| `.github/workflows/drift.yml`, línea 269 | Cuota de `cloudasset` con `tf-read` y el proyecto mismo en el listado | 60 y 118 |
| `.github/workflows/destroy.yml`, línea 219 (y la HYPOTHESIS de la línea 10) | Tiempo del índice de Cloud Asset y el proyecto mismo en el listado; destroy de la red días después | 85, 87 y 118 |
| `scripts/unmanaged-resources.py`, línea 54 | Proyecto mismo en el listado, formato de `name` y lista de permitidos | 49 y 118 |
| `scripts/unmanaged-allowlist.txt`, línea 11 | Reglas escritas con la documentación de Google, no con el proyecto real (también la de DockerImage) | 49 y 142 |
| `scripts/destroy-orphans.py`, líneas 76 y 77 (y su mención en `scripts/selftest.sh`) | `labels`, `additionalAttributes.email` y el proyecto mismo en el listado; restos de GKE | 85 y 140 |
| `tests/README.md`, cuatro marcadores | Cuotas de las pruebas en paralelo; patrón `*` y `:latest`; trazas de la VPN hacia `onprem-sim`; `cloudasset.assets.searchAllResources` de quien corre la prueba | 119, 120, 50 y 85 |
| `tests/helpers/project.go`, línea 70 | Cuotas de las pruebas en paralelo | 119 |
| `tests/helpers/env.go`, línea 60 | El patrón con `*` final admite `:latest` | 120 |
| `tests/e2e/smoke_test.go`, línea 37 | Permisos de `tf-read` y resultado de cada prueba | 50 |
| `tests/e2e/config_example_test.go`, línea 28 | El patrón del ejemplo con `*` final | 120 |
| `tests/e2e/e2e_test.go`, línea 143 | `cloudasset.assets.searchAllResources` de quien corre la prueba | 85 |
| `tests/e2e/stages_test.go`, línea 92 | Quien opera la prueba con suplantación necesita `iam.serviceAccountTokenCreator` sobre las cuentas (la etapa 0 no lo da) | §5, "Sin acceso de emergencia" |
| `tests/integration/compute_mig_test.go`, línea 55 | El JSON de `managed list` trae el autoescalador asociado | 72 |
| `tests/integration/off_hours_shutdown_test.go`, línea 20 | Cloud Scheduler sin app de App Engine en el proyecto de pruebas | 81 |
| `tests/fixtures/cloud-run/main.tf`, líneas 54 y 88; `tests/fixtures/compute-mig/main.tf`, línea 53; `tests/fixtures/support/cmek/main.tf`, línea 47 | CMEK y agentes de servicio en los fixtures; la política de Binary Authorization del proyecto de pruebas no bloquea la imagen | 94 y 120 |

---

## 5. Alcance no cubierto y limitaciones conocidas

No son fallas que el apply vaya a descubrir: son decisiones o huecos conocidos. Cada uno dice
qué, dónde y qué hacer si llega a importar.

**Cloud IDS y Private Service Connect no se construyen.** La especificación los menciona como
servicios, no como configuración mínima (contrato §8). Si se piden: módulo nuevo y ADR.

**Cuotas compartidas por todo el proyecto.** Los tres entornos, el hub y `onprem-sim`
comparten las cuotas de redes, peerings, CPU e IP por región e instancias de Cloud SQL (ADR 0029
§10; punto 9). Un entorno que crece puede dejar sin cuota a otro. Si importa: aumentos de cuota
antes de desplegar prod completo. Desde el 24 nov 2026 las pruebas de integración de Terratest no
pueden correr en el proyecto de la landing zone (`scripts/terratest-project-check.py`, punto
119).

**Lo que ya no separa a los entornos (riesgo aceptado del ADR 0029 §9).** Dentro del proyecto
único:
- las cuentas `tf-wl-<env>` tienen sin condición los roles de Compute, GKE, Cloud Run, Cloud SQL,
  Memorystore y Filestore en el proyecto: la cuenta de dev podría cambiar recursos de prod
  (`stages/0-bootstrap/service_accounts.tf:202`). Lo frena la revisión del plan antes del apply
  (ADR 0025), no un control técnico. Desde el 24 nov 2026 (r2/identidad) ya no puede adjuntar una
  cuenta de prod a una VM: las cuentas de ejecución las crea `1-base` y `tf-wl-<env>` solo tiene
  `serviceAccountUser` sobre las de su entorno (puntos 131 a 135);
- con `onprem_dns_vm = true`, la cuenta del hub tiene `compute.instanceAdmin.v1` sin condición y
  podría cambiar o borrar las VM de los entornos (punto 128);
- los agentes de servicio son uno por proyecto y tienen permiso sobre las llaves de los tres
  entornos (punto 103); el de Cloud Run lee los repositorios de los tres entornos
  (`stages/1-base/artifacts.tf:121`);
- Binary Authorization tiene una sola política. Sin atestadores por entorno su lista de
  permitidos es global: una imagen del repositorio de dev pasa en prod (punto 42; desviación del
  ADR 0029 §4). Con `binary_authorization_env_attestors` los clústeres de GKE exigen la
  atestación de su entorno, pero Cloud Run solo tiene la regla por defecto (punto 139);
- la cuenta del apagado de dev o qa puede detener Cloud SQL o cambiar los pools de otro entorno
  (rol sin condición, puntos 73 y 134);
- el pool de Workload Identity es uno por proyecto: un namespace `<app>-prod` en el clúster de
  dev obtendría la identidad de la cuenta `workload` de prod. El namespace fijo `<app>-<env>` del
  enlace que crea `1-base` lo evita en lo que crea Terraform, no en lo que alguien cree dentro
  del clúster (puntos 46 y 135).

**Protección de la etapa 0 si las etiquetas fallan.** Si la etiqueta de protección no funciona
sin organización (punto 90), la denegación por etiqueta desaparece. Desde el 24 nov 2026
(r2/identidad) `tf-wl-<env>` ya no tiene `iam.serviceAccountUser` ni
`<prefix>TfServiceAccountManager` en el proyecto, así que ya no tiene el camino para cambiar el
IAM de `tf-base` y tomar su identidad. Queda `tf-base`, con `<prefix>TfServiceAccountManager`
sin condición (`stages/0-bootstrap/service_accounts.tf:157`): sin la etiqueta podría cambiar el
IAM de las otras cuentas del pipeline. La regla sin etiqueta le niega pedir sus tokens o firmas
(punto 127); que eso baste para impedir la toma de identidad es HYPOTHESIS, porque actAs sigue
permitido. Las cuentas de spoke tienen `<prefix>TfNetworkTagManager`
(`stages/0-bootstrap/service_accounts.tf:193`), que alcanza el IAM del valor de protección pero
no liga ni quita etiquetas de recursos (lo dice `stages/0-bootstrap/custom_roles.tf`).

**`tf-read` lee todos los estados y la toma cualquier trabajo del repositorio.** Incluido el
estado del hub con el secreto de la VPN (punto 122). No cambió con `attribute.deploy`.

**Las políticas de organización y el perímetro los aplica una persona.** Desde el 24 nov 2026
(r2/identidad) ninguna cuenta del pipeline tiene `orgpolicy.policyAdmin` ni roles de la política
de acceso: los aplica la persona de `0-bootstrap` (`stages/0-bootstrap/org.tf`) con esos roles en
la organización (puntos 125 y 126). Un cambio a esas políticas no pasa por el plan revisado de
`apply.yml`: lo aplica la persona a mano, como el resto de la etapa 0 (runbook
[01](runbooks/01-arranque-etapa-0.md)).

**VPC-SC y políticas de organización solo con organización.** Sin `org_id` en `0-bootstrap` no
hay políticas de organización (ubicaciones, dominios, IP externas y las demás de `modules/org`),
y sin `access_policy_id` no hay perímetro; con ellos, el perímetro queda siempre en dry-run
(HYPOTHESIS que todo eso funcione sobre el proyecto: puntos 3, 5, 106, 109, 125 y 126). Los
controles del CIS que dependen de eso quedan como "Solo con organización" en
[`cumplimiento-cis.md`](cumplimiento-cis.md).

**El acceso de emergencia es la persona dueña del proyecto.** Quien crea el proyecto queda como
`owner` y es quien aplica la etapa 0; nadie más tiene `iam.serviceAccountTokenCreator` sobre las
cuentas de raíz. Las operaciones manuales de los runbooks (rotar o deshabilitar una llave,
promover la réplica, un apply con `-target`) exigen esa persona o una concesión temporal suya,
auditada; el procedimiento no está escrito.

**Límites del apagado fuera de horario (ADR 0028).** Construido para dev y qa
(`off_hours_shutdown`); estos huecos quedan a propósito:
- Sin alerta si un trabajo de Cloud Scheduler falla, y el trabajo solo ve la respuesta inicial
  de la API, no el final de la operación. Si se necesita: una alerta de Cloud Monitoring sobre
  los registros de Cloud Scheduler (propuesta).
- Memorystore, Filestore, la cuota del clúster de GKE, los balanceadores, Cloud Armor, Cloud
  NAT, la VPN y el almacenamiento y la IP de Cloud SQL se siguen cobrando de noche.
- Durante el horario, el MIG con el apagado tiene `mig_min_replicas` VM fijas, sin autoescalado
  por CPU (el programa de escalado es la única señal).
- No hay flujo para lanzar a mano el trabajo de encendido: las personas tienen solo lectura, así
  que encender antes de hora necesita una identidad con `cloudscheduler.jobs.run` (por ejemplo,
  un flujo nuevo con la cuenta `tf-wl-<env>`, no construido).
- Las alertas de dev y qa pueden dispararse de noche (punto 79).

**`destroy.yml` solo destruye las cargas de dev y qa y, si se pide, su spoke.** prod, el hub,
`1-base` y la etapa 0 no tienen flujo de destroy; se desmontan a mano con la guía
[`guia-colaborador-gcp.md`](guia-colaborador-gcp.md). Lo del entorno que vive en `1-base`
(llaves, repositorios y contenedores de secretos) se queda a propósito (ADR 0029 §8). Además,
los entornos de GitHub dev y qa no piden revisores: la barrera humana del destroy es la
confirmación escrita, y cualquiera con permiso de lanzar flujos en el repositorio puede pedirlo
([`pipeline.md`](pipeline.md) §1.5, "Aprobación"). Si importa: revisores obligatorios en esos
entornos (también frenan los apply).

**Servicios de PSA y plano de control de GKE no alcanzables desde on-premises.** Cloud SQL,
Memorystore y Filestore (rango `psa`, `10.X.176.0/20`) y el endpoint privado de GKE viven detrás
de otro peering dentro del spoke; el peering no es transitivo, así que el hub y on-premises no
llegan a ellos aunque el hub anuncie el /16 completo (ADR 0003 y 0012). Si on-premises los
necesita: proxy o bastión en el spoke, endpoint de GKE por DNS, o exportar las rutas del peering
de servicios (por verificar).

**On-premises simulado: VM DNS opcional.** Por defecto la VPC `onprem-sim` no tiene VM: la zona
de reenvío existe pero nadie responde. Desde el 24 nov 2026 hay una VM DNS de prueba como código,
opcional (`onprem_dns_vm = true` en `0-bootstrap` y en `2-networks`, que exige
`simulate_onprem`; `stages/2-networks/onprem_dns.tf`). Mientras esté activa, el hub tiene
`compute.instanceAdmin.v1` sin condición (punto 128). El camino de red ya está construido (la
política de firewall de red de `onprem-sim`); las pruebas son los puntos 36 y 129.

**El modo on-premises real no se puede aplicar desde el pipeline.** Con `simulate_onprem =
false`, el hub lee el secreto de la VPN con una fuente de datos en cada plan, también en los
trabajos `plan` con `tf-read`, que no puede leerlo (la denegación se lo niega): el plan del hub
falla en el pipeline, cerrado, sin que el secreto salga (`stages/2-networks/vpn.tf:98`, punto
151). Salidas propuestas en el código, no construidas: que el plan del hub corra con `tf-net` en
el entorno `common`; que el valor nunca entre al plan, con un atributo de solo escritura
(Terraform 1.11 o posterior; el repositorio admite 1.9); o leerlo solo en el apply con `tf-net`,
lo que exige que el plan revisado y el del apply tengan la misma huella. Las tres cambian el
pipeline o la versión mínima. Con `simulate_onprem = true` (por defecto) no se lee ningún secreto.

**WIF: las cuentas de escritura solo desde `main` y desde los flujos del repositorio.** El
proveedor confía en el ID numérico del repositorio y del dueño (ADR 0023). Desde el 24 nov 2026
(r2/identidad) las cuentas de raíz solo aceptan tokens con `attribute.deploy` igual a su
entorno: entorno de GitHub, `ref = refs/heads/main` y un flujo reutilizable de
`.github/workflows/` del mismo repositorio (ADR 0029 §3, puntos 123 y 124). La configuración de
los entornos de GitHub queda como segunda barrera: revisores (punto 12) y ramas de despliegue
(punto 121). `tf-read` la toma cualquier trabajo del repositorio (punto 122).

**Riesgos residuales de la identidad del pipeline (ADR 0023).** `tf-base` administra el IAM de
los contenedores de secretos (`<prefix>TfSecretContainerAdmin`; la denegación le niega leer
valores), el IAM de las cuentas de ejecución, el IAM de personas de solo lectura y la
configuración de auditoría. Desde el 24 nov 2026 `tf-wl-<env>` ya no asigna IAM de secretos, de
llaves ni de proyecto. Los frena la revisión del plan antes del apply (ADR 0025), no un control
técnico.

**Una sola región en México.** Si se exigiera residencia de datos, `northamerica-south1` no
tiene región de DR en el país (ADR 0002): habría que aceptar DR entre zonas o una región de DR
fuera de México, y reabrir el ADR.

**Memorystore sin AUTH.** AUTH queda apagado para no guardar la cadena en el estado (ADR 0015,
`modules/memorystore`). La caché confía en la red: IP privada, firewall del spoke y TLS (y, con
organización, el perímetro opcional en dry-run). Si se exige autenticación por cliente:
Memorystore for Redis Cluster con IAM.

**El secreto compartido de la VPN vive en el estado cifrado.** En los dos modos el valor queda en
el estado de `2-networks/hub` (CMEK de la etapa 0; ADR 0006), que leen `tf-net` y `tf-read`
(punto 122). Rotarlo recrea el túnel (`shared_secret` fuerza el reemplazo); con on-premises real
se rota de a un túnel con `onprem_vpn_secret_version_overrides` mientras los otros tres mantienen
la conectividad (README de `stages/2-networks`).

**Nombres de objetos del bucket de estado visibles para todas las cuentas de raíz.** La
cláusula `resource.type == "storage.googleapis.com/Bucket"` que permite listar deja ver los
nombres (no el contenido) de todos los prefijos (contrato §6.2, ADR 0010). Si importa: managed
folders.

**Planes de ejemplo de Conftest, parte escritos a mano.** `policies/fixtures/` tiene 42 planes
(`ls policies/fixtures | wc -l` → 42); 18 son recortes de un `terraform show -json` real de un
ejemplo sin GCP (`ls policies/fixtures | grep -c _real_` → 18, 24 nov 2026, código de
`6d27623`) y los demás están escritos a mano. Ninguno sale de un plan contra GCP: con GCP,
regenerar al menos uno por regla desde un plan real (puntos 146 y 147).

**Recursos no administrados sin correr.** El trabajo de `drift.yml` que compara Cloud Asset
Inventory con los estados está construido y probado con datos de ejemplo
(`scripts/testdata/unmanaged/`), pero no se ha corrido contra el proyecto real (puntos 49 y 118).

**Terratest nocturno en rojo hasta configurar sus compuertas.** Sin `TEST_ALLOW_EXPENSIVE` y
sus datos, las pruebas se omiten y `terratest.yml` falla porque el máximo de omitidas es 0
(`TERRATEST_MAX_SKIPS`; [`pipeline.md`](pipeline.md) §1.4). Desde el 24 nov 2026
(r2/pipeline), con `TERRATEST_ORG_ID` vacío las pruebas que solo valen con organización
(`TestOrg` y `TestVPCSC`) se omiten con la marca `[sin-organizacion]` y no cuentan contra ese
máximo (punto 145).

**Imagen de las pruebas y Binary Authorization.** `tests/e2e/config.example.json` y
`tests/helpers/env.go` usan por defecto `us-docker.pkg.dev/cloudrun/container/hello`, que la
política de `1-base` solo admite si `binary_authorization_allowlist_patterns` la incluye (el
ejemplo de la prueba lo hace; punto 120). Con la lista global (sin atestadores por entorno),
ese patrón también vale para prod mientras esté puesto. La configuración de ejemplo de la prueba deja `enable_vpn_dr = true`:
crea ocho túneles.

**Nadie puede cargar valores de secretos.** Los contenedores se crean sin valores (ADR 0015) y
las versiones las carga "el equipo dueño fuera de Terraform", pero ningún grupo recibe
`roles/secretmanager.secretVersionAdder` (`stages/1-base`). Definir el grupo y otorgarlo en
`1-base` por secreto (propuesta) antes de dar de alta aplicaciones con secretos.

**El grupo de soporte no tiene permiso de IAP.** La política de firewall de red del spoke
permite el rango de IAP hacia las VM con `iap_ssh`, pero ningún grupo recibe
`roles/iap.tunnelResourceAccessor` ni OS Login. Si se necesita acceso por IAP: asignarlo a un
grupo en `1-base` (propuesta).

**Una aplicación con cargas por entorno.** La raíz `3-workloads/envs/<env>` tiene un solo
`application` y un solo prefijo de estado (`3-workloads/<env>`). `1-base` puede crear
repositorios y secretos para varias aplicaciones, pero las cargas de una segunda aplicación
necesitan otra raíz u otro espacio de trabajo, que `apply.yml` y `drift.yml` no recorren
(runbook 02).

**Memorystore y Filestore sin DR.** Solo existen en la región primaria
(`stages/3-workloads/envs/*/data.tf`); con la región caída no hay caché ni NFS hasta crearlos en
`dr_region`, y sus datos no se replican.

**Restauración de Backup for GKE no construida.** Hay plan de respaldo, no plan de restauración;
restaurar en el clúster de DR es un paso manual (runbook 04).

**Terratest y prueba de extremo a extremo sin ejecutar.** `tests/` compila y sus fixtures
validan con `terraform validate`, pero ninguna prueba se ha corrido contra GCP; ningún criterio
de ejecución está demostrado.
