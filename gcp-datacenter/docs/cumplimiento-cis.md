# Cumplimiento del CIS Google Cloud Platform Foundation Benchmark

Mapa de cada recomendación del benchmark contra el código, al 24 nov 2026, para el diseño de un
solo proyecto de GCP (ADR 0029). **Nada se ha aplicado**: "Código" y "Solo con organización"
dicen que el control está escrito, no que GCP lo confirme. El cumplimiento solo lo prueba la
evaluación de Security Command Center (SCC) después del primer apply (§6). Rutas relativas a
`gcp-datacenter/`. El mapa del diseño anterior, de varios proyectos, está en la rama
`archivo/multiproyecto`.

## 1. Versión y fuentes

- **Versión mapeada: v5.0.0**, 93 recomendaciones (IAM 21, Logging y Monitoring 17, Redes 12,
  VM 12, Storage 2, Cloud SQL 24, BigQuery 4, Dataproc 1). Es la más nueva con lista pública de
  IDs: `cis_5.0_gcp.json` de Prowler (nombre interno "CIS Google Cloud Platform Foundation
  Benchmark v5.0.0"; último commit del archivo `4d1cd6a5ff`, 23 nov 2026). Conteos hechos con
  Python sobre ese archivo.
- El sitio de CIS muestra **5.0.1** como versión vigente (consultado el 23 nov 2026); no encontré
  su lista pública. HYPOTHESIS: una versión de parche no cambia los IDs. Confirmar con el PDF de
  CIS WorkBench antes de presentar esto al cliente.
- **SCC no evalúa la 5.0.** Los detectores de Security Health Analytics (SHA) llegan hasta "CIS
  GCP Foundation 3.0" y Compliance Manager trae el marco "CIS GCP Foundations Benchmark v3.0" (49
  controles). Por eso cada tabla trae la columna **3.0 · categoría SCC**: el ID equivalente en
  v3.0 (emparejado por título entre `cis_3.0_gcp.json` y `cis_5.0_gcp.json` de Prowler) y la
  categoría del detector de SHA. La 5.0 agrega nueve recomendaciones (1.1.1–1.1.4, 2.2, 3.8, 3.9,
  6.6, 6.9; "—" en esa columna) y renumera el resto de las secciones 1, 2, 3 y 6. La 4.0 usa los
  mismos IDs que la 3.0.
- Fuentes (se citan solo IDs, títulos cortos y categorías, sin texto del benchmark):
  - CIS: <https://www.cisecurity.org/benchmark/google_cloud_computing_platform>
  - Prowler, mapeos CIS de GCP: <https://github.com/prowler-cloud/prowler/tree/master/prowler/compliance/gcp>;
    severidades de sus revisiones en `prowler/providers/gcp/services/*/*/*.metadata.json` del
    mismo repositorio.
  - Google, hallazgos de SHA y su mapeo a CIS: <https://docs.cloud.google.com/security-command-center/docs/concepts-vulnerabilities-findings>
  - Google, SHA según el nivel de SCC: <https://docs.cloud.google.com/security-command-center/docs/concepts-security-health-analytics>
  - Google, marcos de Compliance Manager: <https://docs.cloud.google.com/security-command-center/docs/compliance-manager-frameworks>
  - Google, niveles de severidad: <https://docs.cloud.google.com/security-command-center/docs/finding-severity-classifications>
  - Google, rol Project Creator (quien crea el proyecto queda como owner): <https://docs.cloud.google.com/resource-manager/docs/access-control-proj>
  - Google, activación de SCC (también a nivel proyecto): <https://docs.cloud.google.com/security-command-center/docs/activate-scc-overview>
  - checkov, índice de políticas de Terraform: <https://www.checkov.io/5.Policy%20Index/terraform.html>

Método: cada fila sale de leer el código (búsqueda del recurso y el atributo). El mapa se armó
el 23 nov 2026 con el diseño de varios proyectos y se rehízo el 24 nov 2026 con el código del
proyecto único (commit `61b01b9`): cambian las rutas, lo que dependía de la organización y los
controles de auditoría. Para el mapa no se corrieron checkov, Conftest ni `terraform`. Lo que
solo se comprueba en GCP está en los pendientes de §5.6. Los conteos de §4 salen de un script
sobre las tablas de §3, no a mano.

## 2. Estados

| Estado | Significado |
|---|---|
| **Código** | Un recurso o una validación de variable lo fija, y funciona sin organización. |
| **Revisión en PR** | Solo lo detecta checkov o Conftest en el PR. |
| **Manual** | Fuera de Terraform y pedido por un runbook o un ADR. |
| **Solo con organización** | El control está escrito (código de `modules/org` o `modules/vpc-sc` que `stages/1-base/org.tf` crea con `org_id` o `access_policy_id`, o un paso de Cloud Identity del runbook 01), pero solo existe si el proyecto está dentro de una organización de GCP. Sin organización no se cumple. |
| **No aplica** | El repositorio no usa el servicio. |
| **Desviación** | No se cumple por una decisión documentada, con su riesgo y lo que la cerraría: [ADR 0027](adr/0027-desviaciones-aceptadas-del-cis.md) o, para lo que trae el proyecto único, el [ADR 0029](adr/0029-un-solo-proyecto.md). |
| **Hueco** | No se aborda, o es un paso manual que ningún documento pide, o no se cumple sin una decisión registrada. |

Cada fila tiene un solo estado: el control más fuerte que funciona **sin** organización
(Código > Revisión en PR > Manual). Las políticas de organización que se agregan con `org_id` se
nombran en la fila como refuerzo. Una fila queda en "Solo con organización" cuando sin
organización no hay ningún control. "(parcial)" marca un control que no cubre todo el alcance
(§5).

Por qué "Solo con organización" y no "No aplica (sin organización)", como propone el ADR 0029
§7: si habrá organización todavía no está decidido ([`backlog.md`](backlog.md) §1). "No aplica"
en este mapa quiere decir que el repositorio no usa el servicio; mezclar ahí controles escritos
que se encienden con `org_id` los sacaría de la cuenta de lo pendiente y escondería que, sin
organización, no se cumplen.

## 3. Mapa por sección

### 1. Identity and Access Management

| 5.0 | 3.0 · categoría SCC | Recomendación | Cómo lo aborda el repositorio | Estado |
|---|---|---|---|---|
| 1.1.1 | — | Correo del superadministrador no ligado a una persona | Fuera de Terraform (Cloud Identity). Runbook 01, "Controles manuales del CIS", punto A: dos superadministradores con dirección de rol, llaves de seguridad guardadas, evidencia con captura. Sin organización no hay Cloud Identity ni superadministrador. | **Solo con organización** |
| 1.1.2 | — | Superadministrador no usado para administrar Google Cloud | Runbook 01, punto A: la persona de la etapa 0 no es superadministradora y el superadministrador no tiene roles de IAM en la organización. | **Solo con organización** |
| 1.1.3 | — | Carpetas por entorno y sensibilidad | Sin carpetas: todo vive en un proyecto (ADR 0029). Los entornos se separan por VPC, nombre `<prefix>-<env>-`, etiqueta `env`, cuenta del pipeline y condiciones de IAM (ADR 0029 §9). | **Desviación** |
| 1.1.4 | — | Políticas de organización centralizadas | Con `org_id`, `stages/1-base/org.tf` crea siete restricciones fijas, más `iam.allowedPolicyMemberDomains` con `directory_customer_id` (`modules/org/main.tf`, `local.policies`), con padre el proyecto, no la organización. | **Solo con organización** (parcial) |
| 1.2 | 1.1 · `NON_ORG_IAM_MEMBER` | Credenciales corporativas | Con organización, `iam.allowedPolicyMemberDomains` = `directory_customer_id`. Sin ella no hay dominio corporativo que exigir. Refuerzos que valen siempre: `modules/iam/variables.tf` rechaza `user:`, `domain:`, `allUsers` y `allAuthenticatedUsers`; Conftest `policies/iam_user_principal.rego`. | **Solo con organización** |
| 1.3 | 1.2 · `MFA_NOT_ENFORCED` | MFA en cuentas que no son de servicio | Fuera de Terraform (Cloud Identity). Runbook 01, punto B: 2SV obligatoria en la unidad organizativa raíz. | **Solo con organización** |
| 1.4 | 1.3 · — | Llaves de seguridad para administradores | Runbook 01, punto B: método "Only security key" para las cuentas administradoras. | **Solo con organización** |
| 1.5 | 1.4 · `USER_MANAGED_SERVICE_ACCOUNT_KEY` | Solo llaves administradas por GCP | El pipeline entra por WIF (`stages/0-bootstrap/wif.tf`); ningún `google_service_account_key` en el repositorio; la política de denegación del proyecto niega `serviceAccountKeys.create` a las nueve cuentas del pipeline (`stages/0-bootstrap/deny_policy.tf`, `untagged_denied_permissions`). Con organización, además `iam.disableServiceAccountKeyCreation`. Sin ella, la persona dueña del proyecto sí puede crear llaves. | **Código** (parcial) |
| 1.6 | 1.5 · `ADMIN_SERVICE_ACCOUNT` | Cuentas de servicio sin privilegios de administrador | Las cuentas `<prefix>-tf-*` reciben roles cuyo ID contiene "admin" (`stages/0-bootstrap/service_accounts.tf`, `base_roles`, `net_roles`, `net_env_roles` y `workloads_roles`), algunos con condición. Ya no quedan como owner de ningún proyecto: no crean proyectos. `modules/iam/variables.tf` prohíbe asignar `roles/owner` y `roles/editor`. Desviación aceptada en el ADR 0027. | **Desviación** |
| 1.7 | 1.6 · `OVER_PRIVILEGED_SERVICE_ACCOUNT_USER` | Sin Service Account User ni Token Creator en el proyecto | `tf-wl-<env>` recibe `roles/iam.serviceAccountUser` en el proyecto, sin condición, para adjuntar sus cuentas de ejecución (`stages/0-bootstrap/service_accounts.tf:202`; riesgo aceptado en el código y en el ADR 0029 §9, no en el ADR 0027). Los checks CKV_GCP_41 y CKV_GCP_49 revisan `google_project_iam_member`, pero aquí el rol llega como valor de una variable del módulo `iam`. | **Hueco** |
| 1.8 | 1.7 · `SERVICE_ACCOUNT_KEY_NOT_ROTATED` | Rotación de llaves de usuario ≤ 90 días | Igual que 1.5: las cuentas del pipeline no pueden crear llaves; con organización, ninguna cuenta. | **Código** (parcial) |
| 1.9 | 1.8 · `SERVICE_ACCOUNT_ROLE_SEPARATION` | Separación de funciones en roles de cuentas de servicio | Ninguna persona recibe `serviceAccountAdmin` ni `serviceAccountUser` (los grupos solo tienen lectura, `stages/1-base/iam.tf`). `tf-wl-<env>` junta en el proyecto `<prefix>TfServiceAccountManager` (crear y administrar el IAM de cuentas) y `serviceAccountUser` (1.7). | **Código** (parcial) |
| 1.10 | 1.9 · `KMS_PUBLIC_KEY` | Llaves KMS no públicas | Las validaciones de `modules/kms/variables.tf` (`encrypter_decrypters`) y `modules/iam/variables.tf` rechazan `allUsers` y `allAuthenticatedUsers`; checkov CKV_GCP_112. Con organización, además `iam.allowedPolicyMemberDomains`. | **Código** |
| 1.11 | 1.10 · `KMS_KEY_NOT_ROTATED` | Rotación de llaves KMS ≤ 90 días | Todas las llaves salen de `modules/kms` (`google_kms_crypto_key.this`, `rotation_period` validado entre 1 y 90 días en `modules/kms/variables.tf`; `key_rotation_period = "7776000s"` por defecto en `stages/1-base/variables.tf`); Conftest `policies/kms_rotation.rego`; checkov CKV_GCP_43. | **Código** |
| 1.12 | 1.11 · `KMS_ROLE_SEPARATION` | Separación de funciones en roles KMS | `roles/cloudkms.admin` solo para `tf-base`, condicionado a todo salvo el llavero del estado (`stages/0-bootstrap/service_accounts.tf`, `base_roles`); `cryptoKeyEncrypterDecrypter` solo para agentes de servicio (`stages/1-base/kms.tf`). | **Código** |
| 1.13 | 1.12 · `API_KEY_EXISTS` | Llaves de API solo para servicios activos | El repositorio no crea llaves de API (ningún `google_apikeys_key`). | **No aplica** |
| 1.14 | 1.13 · `API_KEY_APPS_UNRESTRICTED` | Llaves de API restringidas a hosts y apps | Igual que 1.13. | **No aplica** |
| 1.15 | 1.14 · `API_KEY_APIS_UNRESTRICTED` | Llaves de API restringidas a las APIs necesarias | Igual que 1.13. | **No aplica** |
| 1.16 | 1.15 · `API_KEY_NOT_ROTATED` | Rotación de llaves de API | Igual que 1.13. | **No aplica** |
| 1.17 | 1.16 · `ESSENTIAL_CONTACTS_NOT_CONFIGURED` | Essential Contacts en la organización | `google_essential_contacts_contact.this` en el proyecto (`stages/1-base/main.tf`): un contacto por correo de `essential_contacts`, que entre todos deben cubrir LEGAL, SECURITY, SUSPENSION y TECHNICAL (descripción y validación de `stages/1-base/variables.tf`). `roles/essentialcontacts.admin` para `tf-base` (`stages/0-bootstrap/service_accounts.tf`). En el proyecto, no en la organización. Pendiente 57. | **Código** (parcial) |
| 1.18 | 1.17 · — | Secretos fuera de las variables de entorno de Cloud Functions | No hay Cloud Functions (Cloud Run toma secretos con `secret_key_ref`, `modules/cloud-run/main.tf`). | **No aplica** |

### 2. Logging and Monitoring

| 5.0 | 3.0 · categoría SCC | Recomendación | Cómo lo aborda el repositorio | Estado |
|---|---|---|---|---|
| 2.1 | 2.1 · `AUDIT_LOGGING_DISABLED` | Cloud Audit Logs bien configurado | Configuración de auditoría única del proyecto (`stages/1-base/main.tf`): `ADMIN_READ` para `allServices` y `DATA_READ` y `DATA_WRITE` para cinco servicios (`cloudkms`, `iam`, `secretmanager`, `sqladmin` y `storage`) en los tres entornos (ADR 0029 §7). El resto de los servicios queda sin registros de acceso a datos. Desviación del ADR 0027, que cambia de alcance con el rediseño. | **Desviación** (parcial) |
| 2.2 | — | Datos de Workspace/Cloud Identity compartidos con Google Cloud | Fuera de Terraform. Runbook 01, punto C: "Sharing options" en **Enabled** en la consola de administración de Cloud Identity. | **Solo con organización** |
| 2.3 | 2.2 · `LOG_NOT_EXPORTED` | Sink para todas las entradas de log | Sink de proyecto de `1-base` (`stages/1-base/main.tf`, `module "audit_logs"`) con el filtro por defecto `logName:"cloudaudit.googleapis.com"` (`modules/log-export/variables.tf`): solo auditoría, con una exclusión para los registros del propio bucket. Desviación del ADR 0027 (antes era un sink agregado de la organización). | **Desviación** |
| 2.4 | 2.3 · `LOCKED_RETENTION_POLICY_NOT_SET` | Bucket Lock en los buckets de logs | `modules/log-export/main.tf`: `retention_policy` siempre, `is_locked = var.retention_locked`; `log_retention_locked = false` por defecto (`stages/1-base/variables.tf`) y en el ejemplo (irreversible; pendiente 15). Desviación aceptada en el ADR 0027. | **Desviación** |
| 2.5 | 2.4 · `OWNER_NOT_MONITORED` | Métrica y alerta: cambios de propietario | `modules/audit-alerts` (`google_logging_metric.this` con el filtro de la página de SHA, `google_monitoring_alert_policy.this`, canal de correo hacia `security_alert_email`), una sola vez para todo el proyecto (`stages/1-base/main.tf`, `module "audit_alerts"`). Pendiente 58. | **Código** |
| 2.6 | 2.5 · `AUDIT_CONFIG_NOT_MONITORED` | Métrica y alerta: configuración de auditoría | Igual que 2.5 (métrica `audit_config`). | **Código** |
| 2.7 | 2.6 · `CUSTOM_ROLE_NOT_MONITORED` | Métrica y alerta: roles personalizados | Igual que 2.5 (métrica `custom_role`). | **Código** |
| 2.8 | 2.7 · `FIREWALL_NOT_MONITORED` | Métrica y alerta: reglas de firewall | Igual que 2.5 (métrica `firewall`, reglas de VPC). Los cambios de políticas de firewall de red van en una novena métrica, `firewall_policy`; sin política jerárquica, todas las políticas del diseño son de red y del proyecto (HYPOTHESIS que lleguen a la métrica, pendiente 58). | **Código** |
| 2.9 | 2.8 · `ROUTE_NOT_MONITORED` | Métrica y alerta: rutas | Igual que 2.5 (métrica `route`). | **Código** |
| 2.10 | 2.9 · `NETWORK_NOT_MONITORED` | Métrica y alerta: redes VPC | Igual que 2.5 (métrica `network`). | **Código** |
| 2.11 | 2.10 · `BUCKET_IAM_NOT_MONITORED` | Métrica y alerta: IAM de Cloud Storage | Igual que 2.5 (métrica `bucket_iam`). | **Código** |
| 2.12 | 2.11 · `SQL_INSTANCE_NOT_MONITORED` | Métrica y alerta: configuración de Cloud SQL | Igual que 2.5 (métrica `sql_instance`). | **Código** |
| 2.13 | 2.12 · `DNS_LOGGING_DISABLED` | Registro de Cloud DNS en todas las VPC | `google_dns_policy.this` (`modules/dns/main.tf`) con `enable_logging = true` en el hub (`stages/2-networks/dns.tf`) y en cada spoke (`stages/2-networks/envs/*/dns.tf`); `google_dns_policy.onprem_sim` (`stages/2-networks/dns.tf`) con registro en la VPC `onprem-sim` cuando `simulate_onprem = true`. Pendiente 61. | **Código** |
| 2.14 | 2.13 · `CLOUD_ASSET_API_DISABLED` | Cloud Asset Inventory habilitado | `cloudasset.googleapis.com` en `local.apis` de `stages/0-bootstrap/main.tf`, en el proyecto único. `drift.yml` y la búsqueda de huérfanos la usan con `tf-read` (pendiente 60). | **Código** |
| 2.15 | 2.14 · `ACCESS_TRANSPARENCY_DISABLED` | Access Transparency | Fuera de Terraform; se configura en la organización. Runbook 01, punto D: comprobarla en IAM & Admin > IAM > Settings y guardar la captura. | **Solo con organización** |
| 2.16 | 2.15 · — | Access Approval | Runbook 01, punto E: inscribir la organización en la consola (requiere 2.15), avisos al grupo `security_admins`. | **Solo con organización** |
| 2.17 | 2.16 · `LOAD_BALANCER_LOGGING_DISABLED` | Registro del balanceador HTTP(S) | `log_config { enable = true }` en `google_compute_backend_service.this` y `google_compute_region_backend_service.this` (`modules/load-balancer/main.tf`); `log_sample_rate` debe ser mayor que 0 (validación en `variables.tf`). | **Código** |

### 3. Networking

| 5.0 | 3.0 · categoría SCC | Recomendación | Cómo lo aborda el repositorio | Estado |
|---|---|---|---|---|
| 3.1 | 3.1 · `DEFAULT_NETWORK` | Sin red `default` | El proyecto ya existe y trae la red `default`: se borra a mano antes de `0-bootstrap` (ADR 0029 §6; el runbook 01 todavía no tiene el paso). `compute.skipDefaultNetworkCreation` ya no está en `modules/org` (solo actúa al crear un proyecto). Todas las VPC del repositorio son propias (3.2). | **Manual** |
| 3.2 | 3.2 · `LEGACY_NETWORK` | Sin redes heredadas | Todas las VPC en modo personalizado: `auto_create_subnetworks = false` en `modules/network-hub/main.tf` y `modules/network-spoke/main.tf`. | **Código** |
| 3.3 | 3.3 · `DNSSEC_DISABLED` | DNSSEC en Cloud DNS | Solo zonas privadas (`visibility = "private"` fijo en `modules/dns/main.tf`); la zona pública del dominio queda fuera del repositorio. | **No aplica** |
| 3.4 | 3.4 · `RSASHA1_FOR_SIGNING` | Sin RSASHA1 en la llave de firma de llaves | Igual que 3.3. | **No aplica** |
| 3.5 | 3.5 · `RSASHA1_FOR_SIGNING` | Sin RSASHA1 en la llave de firma de zona | Igual que 3.3. | **No aplica** |
| 3.6 | 3.6 · `OPEN_SSH_PORT` | SSH restringido desde internet | Sin reglas de VPC (`google_compute_firewall`): una política de firewall de red por VPC con denegación de entrada por defecto (`modules/firewall/main.tf`); `modules/firewall/variables.tf` rechaza un `allow` de entrada con origen más amplio que /8; SSH solo desde IAP (`35.235.240.0/20`) hacia `iap_ssh` (`stages/2-networks/envs/*/firewall.tf`) y hacia `onprem-sim` (`stages/2-networks/firewall.tf`). | **Código** |
| 3.7 | 3.7 · `OPEN_RDP_PORT` | RDP restringido desde internet | Ninguna política permite 3389 (`stages/2-networks/firewall.tf` y `stages/2-networks/envs/*/firewall.tf`): lo corta la denegación por defecto; misma validación que 3.6. | **Código** |
| 3.8 | — | VPC Service Controls en los servicios admitidos | Con `access_policy_id` (solo existe con organización), `stages/1-base/org.tf` crea un perímetro alrededor del proyecto entero (`modules/vpc-sc`), siempre en dry-run: registra, no bloquea. Sin organización no hay perímetro (ADR 0029 §1). | **Solo con organización** (parcial) |
| 3.9 | — | Private Service Connect para las APIs de Google | Private Google Access con el VIP restringido (`private_ip_google_access = true`, ruta `restricted_vip`, zonas DNS hacia el VIP; ADR 0026). PSC no se construye (`docs/pendientes-apply.md` §5). Desviación aceptada en el ADR 0027. | **Desviación** |
| 3.10 | 3.8 · `VPC_FLOW_LOGS_SETTINGS_NOT_RECOMMENDED` | Flow logs en cada subred | `log_config` en todas las subredes normales (`modules/network-hub/main.tf`, `modules/network-spoke/main.tf`) con intervalo de 5 s, todos los metadatos y `flow_sampling = var.flow_log_sampling`, que vale 1.0 por defecto en los dos módulos: el hub, `onprem-sim` y prod (`stages/2-networks/envs/prod/terraform.tfvars.example`) quedan al 100 %. Los ejemplos de dev y qa lo bajan a 0.5 por costo (desviación del ADR 0027). Las subredes proxy-only no admiten flow logs (omisión de CKV_GCP_26; el detector las excluye). Pendiente 62. | **Código** (parcial) |
| 3.11 | 3.9 · `WEAK_SSL_POLICY` | Sin cifrados débiles en políticas SSL | `google_compute_ssl_policy.this` y `google_compute_region_ssl_policy.this` con `profile` MODERN o RESTRICTED (validación) y `min_tls_version = "TLS_1_2"` (`modules/load-balancer/main.tf`); checkov CKV_GCP_4. | **Código** |
| 3.12 | 3.10 · — | IAP: solo tráfico desde IP de Google | La entrada a las cargas solo se permite desde los rangos del balanceador (`35.191.0.0/16`, `130.211.0.0/22`), desde IAP hacia etiquetas seguras y desde rangos internos (`stages/2-networks/envs/*/firewall.tf`). IAP no protege el HTTPS de la aplicación, que es pública detrás de Cloud Armor (ADR 0005 y 0020). | **Código** (parcial) |

### 4. Virtual Machines

| 5.0 | 3.0 · categoría SCC | Recomendación | Cómo lo aborda el repositorio | Estado |
|---|---|---|---|---|
| 4.1 | 4.1 · `DEFAULT_SERVICE_ACCOUNT_USED` | Sin cuenta de servicio por defecto | `service_account` del MIG y `node_service_account` de GKE se validan como `<id>@<proyecto>.iam.gserviceaccount.com`, lo que excluye `<n>-compute@developer.gserviceaccount.com` (`modules/compute-mig/variables.tf`, `modules/gke/variables.tf`). Además, `0-bootstrap` quita `roles/editor` a la cuenta de Compute por defecto (`DEPRIVILEGE`, pendiente 95). | **Código** |
| 4.2 | 4.2 · `FULL_API_ACCESS` | Sin cuenta por defecto con acceso a todas las APIs | Igual que 4.1: el alcance `cloud-platform` va con cuentas dedicadas. | **Código** |
| 4.3 | 4.3 · `COMPUTE_PROJECT_WIDE_SSH_KEYS_ALLOWED` | Bloquear llaves SSH del proyecto | `block-project-ssh-keys = "TRUE"` fijo en `local.metadata` de `modules/compute-mig/main.tf`; la validación de `metadata` impide cambiarlo. Los nodos de GKE no lo llevan; SHA los excluye. | **Código** |
| 4.4 | 4.4 · `OS_LOGIN_DISABLED` | OS Login en el proyecto | `google_compute_project_metadata_item.os_login` (`enable-oslogin = "TRUE"`) en `stages/0-bootstrap/main.tf`, en todo el proyecto, que es lo que lee el detector; además por instancia en `modules/compute-mig/main.tf`. Los nodos de GKE Standard heredan el metadato del proyecto (SHA los excluye). Pendiente 59. | **Código** |
| 4.5 | 4.5 · `COMPUTE_SERIAL_PORTS_ENABLED` | Puerto serie apagado | `serial-port-enable = "FALSE"` fijo en `modules/compute-mig/main.tf`. | **Código** |
| 4.6 | 4.6 · `IP_FORWARDING_ENABLED` | Sin reenvío de IP | `can_ip_forward = false` en `google_compute_region_instance_template.this` (`modules/compute-mig/main.tf`). Los nodos de GKE lo necesitan; SHA los excluye. | **Código** |
| 4.7 | 4.7 · `DISK_CSEK_DISABLED` | CSEK en discos de VM críticas | Discos con CMEK, no CSEK (`disk_encryption_key.kms_key_self_link` en `modules/compute-mig/main.tf`; `boot_disk_kms_key` en `modules/gke/main.tf`). Desviación aceptada en el ADR 0027. | **Desviación** |
| 4.8 | 4.8 · `SHIELDED_VM_DISABLED` | Shielded VM | `shielded_instance_config` con arranque seguro, vTPM e integridad en el MIG; `enable_shielded_nodes = true` y arranque seguro en GKE; Conftest `policies/shielded_vm.rego`. Con organización, además `compute.requireShieldedVm`. | **Código** |
| 4.9 | 4.9 · `PUBLIC_IP_ADDRESS` | Sin IP pública | MIG sin `access_config` y con `stack_type = "IPV4_ONLY"`; GKE con `enable_private_nodes = true`; Conftest `policies/compute_public_ip.rego`. Con organización, además `compute.vmExternalIpAccess` (`deny_all`). | **Código** |
| 4.10 | 4.10 · — | App Engine solo con HTTPS | No hay App Engine. | **No aplica** |
| 4.11 | 4.11 · `CONFIDENTIAL_COMPUTING_DISABLED` | Confidential Computing | Ningún `confidential_instance_config` (MIG) ni `confidential_nodes` (GKE); los ejemplos usan `e2-*`. Desviación aceptada en el ADR 0027. | **Desviación** |
| 4.12 | 4.12 · — | Actualizaciones de SO al día | GKE: `auto_upgrade = true` e imagen COS (`modules/gke/main.tf`). MIG: sin VM Manager ni `google_os_config_patch_deployment`; depende de la imagen `mig_image`. Desviación aceptada en el ADR 0027. | **Desviación** (parcial) |

### 5. Storage

| 5.0 | 3.0 · categoría SCC | Recomendación | Cómo lo aborda el repositorio | Estado |
|---|---|---|---|---|
| 5.1 | 5.1 · `PUBLIC_BUCKET_ACL` | Buckets no públicos | `public_access_prevention = "enforced"` en los tres recursos de bucket (`modules/storage/main.tf`, `modules/log-export/main.tf`, `stages/0-bootstrap/main.tf`); Conftest `policies/bucket_public_access.rego`. Con organización, además `storage.publicAccessPrevention` (cubre también lo que se cree fuera de Terraform). | **Código** |
| 5.2 | 5.2 · `BUCKET_POLICY_ONLY_DISABLED` | Acceso uniforme a nivel de bucket | `uniform_bucket_level_access = true` en los mismos tres recursos; checkov CKV_GCP_29. Con organización, además `storage.uniformBucketLevelAccess`. | **Código** |

### 6. Cloud SQL Database Services

Las banderas están en bloques `database_flags` fijos de la primaria y la réplica
(`modules/cloud-sql/main.tf`); una bandera adicional con el mismo nombre se descarta
(`local.additional_flags`). El módulo solo admite PostgreSQL: `database_version` se valida con
`^POSTGRES_[0-9]+$` (`modules/cloud-sql/variables.tf`).

| 5.0 | 3.0 · categoría SCC | Recomendación | Cómo lo aborda el repositorio | Estado |
|---|---|---|---|---|
| 6.1.1 | 6.1.1 · `SQL_NO_ROOT_PASSWORD` | MySQL: sin acceso administrativo para cualquiera | Solo PostgreSQL. | **No aplica** |
| 6.1.2 | 6.1.2 · `SQL_SKIP_SHOW_DATABASE_DISABLED` | MySQL: `skip_show_database` en `on` | Solo PostgreSQL. | **No aplica** |
| 6.1.3 | 6.1.3 · `SQL_LOCAL_INFILE` | MySQL: `local_infile` en `off` | Solo PostgreSQL. | **No aplica** |
| 6.2.1 | 6.2.1 · `SQL_LOG_ERROR_VERBOSITY` | `log_error_verbosity` en `default` o más estricto | `log_error_verbosity = "default"`. | **Código** |
| 6.2.2 | 6.2.2 · `SQL_LOG_CONNECTIONS_DISABLED` | `log_connections` en `on` | `log_connections = "on"`; checkov CKV_GCP_52. | **Código** |
| 6.2.3 | 6.2.3 · `SQL_LOG_DISCONNECTIONS_DISABLED` | `log_disconnections` en `on` | `log_disconnections = "on"`; checkov CKV_GCP_53. | **Código** |
| 6.2.4 | 6.2.4 · `SQL_LOG_STATEMENT` | `log_statement` adecuado | `log_statement = "ddl"`. | **Código** |
| 6.2.5 | 6.2.5 · `SQL_LOG_MIN_MESSAGES` | `log_min_messages` al menos `warning` | `log_min_messages = "warning"`; checkov CKV_GCP_55. | **Código** |
| 6.2.6 | 6.2.6 · `SQL_LOG_MIN_ERROR_STATEMENT_SEVERITY` | `log_min_error_statement` en `error` o más estricto | `log_min_error_statement = "error"`. | **Código** |
| 6.2.7 | 6.2.7 · `SQL_LOG_MIN_DURATION_STATEMENT_ENABLED` | `log_min_duration_statement` en `-1` | `log_min_duration_statement = "-1"`; checkov CKV_GCP_57. | **Código** |
| 6.2.8 | 6.2.8 · — | `cloudsql.enable_pgaudit` en `on` | `cloudsql.enable_pgaudit = "on"` y `pgaudit.log = var.pgaudit_log` (`ddl,role,write`); checkov CKV_GCP_110. `CREATE EXTENSION pgaudit;` en cada base es manual (runbook 02, verificación). | **Código** |
| 6.3.1 | 6.3.1 · `SQL_EXTERNAL_SCRIPTS_ENABLED` | SQL Server: `external scripts enabled` en `off` | Solo PostgreSQL. | **No aplica** |
| 6.3.2 | 6.3.2 · `SQL_CROSS_DB_OWNERSHIP_CHAINING` | SQL Server: `cross db ownership chaining` en `off` | Solo PostgreSQL. | **No aplica** |
| 6.3.3 | 6.3.3 · `SQL_USER_CONNECTIONS_CONFIGURED` | SQL Server: `user connections` sin límite | Solo PostgreSQL. | **No aplica** |
| 6.3.4 | 6.3.4 · `SQL_USER_OPTIONS_CONFIGURED` | SQL Server: `user options` sin configurar | Solo PostgreSQL. | **No aplica** |
| 6.3.5 | 6.3.5 · `SQL_REMOTE_ACCESS_ENABLED` | SQL Server: `remote access` en `off` | Solo PostgreSQL. | **No aplica** |
| 6.3.6 | 6.3.6 · `SQL_TRACE_FLAG_3625` | SQL Server: bandera 3625 en `on` | Solo PostgreSQL. | **No aplica** |
| 6.3.7 | 6.3.7 · `SQL_CONTAINED_DATABASE_AUTHENTICATION` | SQL Server: `contained database authentication` en `off` | Solo PostgreSQL. | **No aplica** |
| 6.4 | 6.4 · `SSL_NOT_ENFORCED` | Conexiones entrantes solo con SSL | `ssl_mode` = `TRUSTED_CLIENT_CERTIFICATE_REQUIRED` por defecto; la validación solo admite ese o `ENCRYPTED_ONLY` (`modules/cloud-sql/variables.tf`). | **Código** |
| 6.5 | 6.5 · `PUBLIC_SQL_INSTANCE` | Sin todas las IP públicas autorizadas | `ipv4_enabled = false` y ningún `authorized_networks`. Con organización, además `sql.restrictPublicIp`. | **Código** |
| 6.6 | — | Autenticación IAM de base de datos | `cloudsql.iam_authentication = "on"`; usuarios `google_sql_user.iam` sin contraseña (ADR 0015). | **Código** |
| 6.7 | 6.6 · `SQL_PUBLIC_IP` | Sin IP pública | `ipv4_enabled = false` y `private_network` en primaria y réplica; Conftest `policies/sql_public_ip.rego`; checkov CKV_GCP_60. Con organización, además `sql.restrictPublicIp`. | **Código** |
| 6.8 | 6.7 · `AUTO_BACKUP_DISABLED` | Respaldos automáticos | `backup_configuration` con `enabled = true` y `point_in_time_recovery_enabled = true` en la primaria; la réplica no admite respaldos (omisión de CKV_GCP_14 justificada) y SHA excluye réplicas. | **Código** |
| 6.9 | — | Protección contra borrado | `deletion_protection` y `deletion_protection_enabled` = `var.deletion_protection` (por defecto `true`; obligatorio en prod por validación). Los ejemplos de dev y qa lo ponen en `false` para el `destroy` (pendiente 11; desviación del ADR 0027). | **Código** (parcial) |

### 7. BigQuery y 8. Dataproc

| 5.0 | 3.0 · categoría SCC | Recomendación | Cómo lo aborda el repositorio | Estado |
|---|---|---|---|---|
| 7.1 | 7.1 · `PUBLIC_DATASET` | Datasets no públicos | Ningún recurso `google_bigquery_*`; el sink de auditoría escribe en un bucket de Cloud Storage (`modules/log-export/main.tf:33`). | **No aplica** |
| 7.2 | 7.2 · `BIGQUERY_TABLE_CMEK_DISABLED` | Tablas con CMEK | Igual que 7.1. | **No aplica** |
| 7.3 | 7.3 · `DATASET_CMEK_DISABLED` | CMEK por defecto en datasets | Igual que 7.1. | **No aplica** |
| 7.4 | 7.4 · — | Datos de BigQuery clasificados | Igual que 7.1. | **No aplica** |
| 8.1 | 8.1 · `DATAPROC_CMEK_DISABLED` | Clústeres de Dataproc con CMEK | Ningún recurso `google_dataproc_*`. | **No aplica** |

## 4. Resumen

| Sección | Código | Revisión en PR | Manual | Solo con organización | No aplica | Desviación | Hueco | Total |
|---|---|---|---|---|---|---|---|---|
| 1 IAM | 7 | 0 | 0 | 6 | 5 | 2 | 1 | 21 |
| 2 Logging and Monitoring | 11 | 0 | 0 | 3 | 0 | 3 | 0 | 17 |
| 3 Networking | 6 | 0 | 1 | 1 | 3 | 1 | 0 | 12 |
| 4 Virtual Machines | 8 | 0 | 0 | 0 | 1 | 3 | 0 | 12 |
| 5 Storage | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 2 |
| 6 Cloud SQL | 14 | 0 | 0 | 0 | 10 | 0 | 0 | 24 |
| 7 BigQuery | 0 | 0 | 0 | 0 | 4 | 0 | 0 | 4 |
| 8 Dataproc | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 1 |
| **Total** | **48** | **0** | **1** | **10** | **24** | **9** | **1** | **93** |

Conteo del 24 nov 2026 con un script de Python (fuera del repositorio) que toma la última columna
de cada fila de §3 cuyo primer campo es un ID, le quita `**` y "(parcial)" y suma por sección; no
se contó a mano.

- De las 69 recomendaciones que aplican, sin organización 49 tienen un control escrito (48
  Código y 1 Manual); 10 solo se cumplen si el proyecto entra a una organización; 9 son
  desviaciones (ocho del ADR 0027 y 1.1.3, que trae el ADR 0029); y queda **un hueco**: 1.7,
  `serviceAccountUser` de `tf-wl-<env>` en el proyecto (§5.4).
- Once filas son parciales (lista del mismo script): siete con estado Código (1.5, 1.8, 1.9,
  1.17, 3.10, 3.12 y 6.9), dos Solo con organización (1.1.4 y 3.8) y dos Desviación (2.1 y
  4.12). §5 dice qué falta en cada una.
- "Revisión en PR" no es el control principal de ninguna fila: checkov y Conftest refuerzan
  controles que ya están en el código.
- "Código" está escrito y pasa `scripts/check.sh` (plan con proveedor simulado), no aplicado.
  "Manual" es borrar la red `default`: escrito en el ADR 0029, no hecho. Nada de esto cuenta como
  cumplido hasta la evaluación del pendiente 56.

## 5. Lo que queda abierto

La documentación de Google consultada no publica la severidad por categoría (la página de
severidad solo define los niveles); el nivel real se verá en el primer escaneo. La columna
"Severidad" da la de la revisión equivalente de Prowler como referencia, **no la de SCC**. "CM"
dice si el marco CIS v3.0 de Compliance Manager tiene un control para esa recomendación (lista de
49 controles publicada, 23 nov 2026).

### 5.1 Desviaciones aceptadas

Las nueve filas con estado Desviación y la parte que no cubren dos filas Código (parcial). El
porqué, el riesgo y la corrección completa están en el
[ADR 0027](adr/0027-desviaciones-aceptadas-del-cis.md) (y, para 1.1.3, en el ADR 0029); el
cliente tiene que aceptarlas o pedir que se construya la corrección. El ADR 0027 se escribió para
el diseño de varios proyectos: las filas 1.1.3, 1.6, 2.1 y 2.3 cambian con el rediseño y hay que
revisarlas ahí.

| 5.0 | Qué no se cumple | SCC | Severidad (Prowler) | Para cumplir | Esfuerzo |
|---|---|---|---|---|---|
| 1.1.3 | Sin carpetas: los entornos viven en un solo proyecto | Sin detector; CM no | — | Una organización con carpetas por entorno, que es el diseño de la rama `archivo/multiproyecto` (requisito del cliente: un solo proyecto, ADR 0029). | L |
| 1.6 | Cuentas del pipeline con roles `*admin*` | `ADMIN_SERVICE_ACCOUNT`; CM no | alta | Roles personalizados mínimos por raíz en `0-bootstrap`. Una regla de silencio acotada a `<prefix>-tf-*` documenta el hallazgo pero no cumple. | L |
| 2.1 (parcial) | Acceso a datos solo en cinco servicios (en los tres entornos) | `AUDIT_LOGGING_DISABLED`; CM no | media | `DATA_READ` y `DATA_WRITE` para `allServices` en `stages/1-base/main.tf`. Sube el costo de logs de los tres entornos ([`estimacion-de-costos.md`](estimacion-de-costos.md)). | S (código), M (costo) |
| 2.3 | Sink de proyecto solo de auditoría | `LOG_NOT_EXPORTED`; CM no. HYPOTHESIS: el detector pide un sink sin filtro | — | `filter = ""` en `module "audit_logs"` de `stages/1-base/main.tf` o un segundo sink sin filtro hacia un bucket de Logging. Sube volumen y costo. | S |
| 2.4 | Bucket Lock apagado (`log_retention_locked = false`) | `LOCKED_RETENTION_POLICY_NOT_SET`; CM sí | alta | `log_retention_locked = true` en el `terraform.tfvars` real de `stages/1-base` después de probar el pendiente 15. Irreversible. | S |
| 3.9 | API de Google por el VIP restringido, no por PSC | Sin detector; CM no | — | Endpoint PSC global en `modules/network-hub` y `modules/network-spoke`, zonas DNS hacia esa IP y un ADR que reemplace al 0026. | M |
| 3.10 (parcial) | Flow logs de dev y qa al 50 % en sus `terraform.tfvars.example` | `VPC_FLOW_LOGS_SETTINGS_NOT_RECOMMENDED` (hay que activar el detector); CM sí | media | `flow_log_sampling = 1` en el `terraform.tfvars` de dev y qa (el valor por defecto ya es 1). | S |
| 4.7 | CMEK en lugar de CSEK | `DISK_CSEK_DISABLED`, solo en discos con la marca `enforce_customer_supplied_disk_encryption_keys`; CM no | alta | VM sueltas con CSEK y llaves fuera de GCP; no compatible con el MIG ni con GKE (HYPOTHESIS). | L |
| 4.11 | Sin Confidential Computing | `CONFIDENTIAL_COMPUTING_DISABLED` (solo escanea N2D); CM sí | media | `confidential_instance_config`, tipo N2D y `on_host_maintenance = "TERMINATE"` en `modules/compute-mig/main.tf`; `confidential_nodes { enabled = true }` en `modules/gke/main.tf`. Cambia tipos de máquina y costo. | M |
| 4.12 (parcial) | VM del MIG sin VM Manager (GKE sí se actualiza) | Sin detector (VM Manager reporta vulnerabilidades si está activo); CM no | — | `osconfig.googleapis.com`, `enable-osconfig = "TRUE"` en `local.metadata` de `modules/compute-mig/main.tf` y `google_os_config_patch_deployment` en `stages/3-workloads/envs/*/compute.tf`. | M |
| 6.9 (parcial) | Cloud SQL de dev y qa sin protección contra borrado en los ejemplos | Sin mapeo CIS 3.0; CM no | — | `deletion_protection = true` en dev y qa, y apagarla en el procedimiento de destroy (pendiente 11). | S |

### 5.2 Solo con organización

Diez filas: 1.1.1, 1.1.2, 1.1.4, 1.2, 1.3, 1.4, 2.2, 2.15, 2.16 y 3.8. Con el proyecto dentro de
una organización (decisión abierta, [`backlog.md`](backlog.md) §1):

- **Cloud Identity** (1.1.1, 1.1.2, 1.3, 1.4, 2.2) y **Access Transparency y Access Approval**
  (2.15, 2.16): los pasos A a E de "Controles manuales del CIS" del
  [runbook 01](runbooks/01-arranque-etapa-0.md), que hace un superadministrador; pasarían a
  "Manual".
- **Políticas de organización** (1.1.4, 1.2): `org_id` y `directory_customer_id` en `1-base` y
  `org_id` en `0-bootstrap` (que le da a `tf-base` `orgpolicy.policyAdmin` en toda la
  organización; pendiente 107). 1.1.4 seguiría parcial: las políticas tienen padre el proyecto,
  no la organización.
- **VPC Service Controls** (3.8): `access_policy_id` en `0-bootstrap` y `1-base`; el perímetro
  queda en dry-run y forzarlo no está construido (pendiente 5).

Las mismas políticas refuerzan filas que ya tienen control en el código (1.5, 1.8, 1.10, 4.8,
4.9, 5.1, 5.2, 6.5 y 6.7): con organización cubren también lo que se cree fuera de Terraform.

### 5.3 Otros límites de filas cubiertas

- **1.5 y 1.8** (Código, parcial): la denegación de `serviceAccountKeys.create` solo alcanza a
  las nueve cuentas del pipeline; la persona dueña del proyecto puede crear llaves. Con
  organización lo cierra `iam.disableServiceAccountKeyCreation`.
- **1.9** (Código, parcial): `tf-wl-<env>` junta administración y uso de cuentas de servicio en el
  proyecto (ver 1.7).
- **1.17** (Código, parcial): los contactos están en el proyecto; el CIS los pide en la
  organización.
- **3.12** (Código, parcial): IAP en el servicio de backend volvería privada la aplicación, que es
  pública detrás de Cloud Armor (ADR 0005 y 0020); se deja así por diseño.
- **2.8** (Código): sin política jerárquica, el límite que el ADR 0027 registraba (cambios de la
  política de la organización fuera de las métricas) ya no aplica; que los cambios de las
  políticas de red lleguen a la métrica `firewall_policy` es el pendiente 58.

### 5.4 Hueco

- **1.7**: `roles/iam.serviceAccountUser` de `tf-wl-<env>` en el proyecto, sin condición
  (`stages/0-bootstrap/service_accounts.tf:202`). Con él, la cuenta de cargas de un entorno puede
  adjuntar cualquier cuenta de servicio del proyecto a una VM, un pod o un servicio, salvo las del
  pipeline, que protege la denegación por etiqueta (pendientes 90 y 93). El ADR 0029 §9 lo cuenta
  como riesgo aceptado del proyecto único, pero el ADR 0027 no lo registra como desviación del
  CIS. Dos salidas: registrarlo en el ADR 0027 (pasa a Desviación) o que `1-base` cree las
  cuentas de ejecución y `tf-wl-<env>` reciba `serviceAccountUser` solo sobre las de su entorno
  (mejora propuesta en [`backlog.md`](backlog.md)).

### 5.5 Pasos manuales por hacer

- **3.1**: borrar la red `default` del proyecto antes de `0-bootstrap` (ADR 0029 §6). El runbook
  01 todavía no tiene el paso ni su evidencia (`gcloud compute networks list --project=<proyecto>`
  sin `default`).
- Con organización, los pasos A a E de "Controles manuales del CIS" del runbook 01 (§5.2). Quedan
  como HYPOTHESIS en el runbook la ruta de los roles de administración, la 2SV por grupo de
  configuración, el filtro de `gcloud logging read`, cómo se vuelve a activar Access
  Transparency, `roles/accessapproval.configEditor` a nivel organización, el costo de Access
  Approval y la sintaxis de `gcloud access-approval settings get`.

### 5.6 Pendientes del primer apply

En [`pendientes-apply.md`](pendientes-apply.md):

- 56: evaluación del CIS después del primer apply (procedimiento de §6).
- 57: contactos esenciales del proyecto (1.17).
- 58: métricas de log y alertas de auditoría (2.5 a 2.12).
- 59: OS Login en los metadatos del proyecto (4.4).
- 60: Cloud Asset para `drift.yml` (2.14).
- 61: registro de Cloud DNS en `onprem-sim` (2.13).
- 62: flow logs al 100 % en prod, hub y `onprem-sim` (3.10).
- 28: la configuración de auditoría la escribe `tf-base` con su `projectIamAdmin` condicionado
  (2.1).
- 90 a 93: etiqueta de protección y política de denegación del proyecto (1.5 y 1.8).
- 95: cuenta de Compute por defecto sin `roles/editor` (4.1).
- 108: exclusión del sink y escritura con CMEK (2.3).
- 3, 5, 106, 107 y 109: con organización, políticas y perímetro (§5.2).

Hallazgos probables de SHA fuera del marco CIS v3.0 (HYPOTHESIS):

- `KMS_PROJECT_HAS_OWNER`: la persona que creó el proyecto es owner del único proyecto, que
  tiene todas las llaves, incluida la del estado. Google lo mapea a CIS 1.11 solo hasta la
  versión 2.0.
- `SERVICE_ACCOUNT_ROLE_SEPARATION`: `tf-wl-<env>` tiene `<prefix>TfServiceAccountManager` y
  `serviceAccountUser` en el proyecto (1.9). Depende de si SHA cuenta un rol personalizado como
  `serviceAccountAdmin`.

## 6. Verificación después del primer apply

1. **Activar SCC** a mano en el proyecto antes de `1-base`: pendiente 2 (runbook 01) y pendiente
   23. Que se pueda activar en un proyecto sin organización es HYPOTHESIS (ADR 0029 §7). Con
   `enable_scc_notification = true`, `1-base` envía los hallazgos activos HIGH y CRITICAL a
   Pub/Sub (`google_scc_v2_project_notification_config.findings` con `scc_notification_filter`;
   el tema es el pendiente 34).
2. **Qué evalúa SCC** (documentación de Google, 23 nov 2026, para organizaciones): en una
   organización que activa Standard o Premium por primera vez, SHA no está disponible y la
   evaluación pasa a Compliance Manager, cuyo marco integrado es "CIS GCP Foundations Benchmark
   v3.0". La activación a nivel proyecto existe y su vista de cumplimiento solo cubre ese
   proyecto (ADR 0029 §7); qué marcos ofrece así: por verificar en la consola. Casi todos los
   detectores de SHA con mapeo CIS dicen "Pricing tier: Premium" (excepciones: `OPEN_SSH_PORT`,
   `OPEN_RDP_PORT`, `PUBLIC_IP_ADDRESS`, `PUBLIC_BUCKET_ACL`, entre otras). Si el criterio es
   CIS, decidir el nivel con eso a la vista.
3. **Procedimiento**: en Compliance, activar el marco CIS v3.0 y revisar la pestaña Monitor; en
   Findings, filtrar `state="ACTIVE" AND (severity="HIGH" OR severity="CRITICAL")`. Cada control
   se traduce a la 5.0 con la columna "3.0" de §3.
4. **Lo que SCC no prueba**: de las filas de §5.1, solo 2.4, 3.10 y 4.11 tienen control en el
   marco CIS v3.0 de Compliance Manager; de los controles agregados el 23 nov 2026, solo 1.17 y
   2.14. "Sin hallazgos críticos ni altos" puede cumplirse con desviaciones abiertas, y SCC puede
   reportar desviaciones ya aceptadas (1.6, 2.1, 2.4, 3.10 en dev y qa) y el hueco 1.7: la
   revisión los separa de los hallazgos inesperados con el ADR 0027. Evidencia aparte:
   - IAM (1.6, 1.7, 1.9, 1.12): `gcloud projects get-iam-policy <proyecto>`.
   - 1.17: `gcloud essential-contacts list --project=<proyecto>` (sintaxis HYPOTHESIS): los
     contactos con sus categorías.
   - 2.1: `auditConfigs` en la salida de `gcloud projects get-iam-policy <proyecto> --format=json`.
   - 2.3: `gcloud logging sinks list --project=<proyecto>`.
   - 2.5–2.12: `gcloud logging metrics list --project=<proyecto>` y las políticas de alerta de
     Cloud Monitoring del proyecto (pendiente 58).
   - 2.14: `gcloud services list --enabled --project=<proyecto>` muestra
     `cloudasset.googleapis.com`.
   - 3.1: `gcloud compute networks list --project=<proyecto>` sin la red `default`.
   - 4.4: `gcloud compute project-info describe --project=<proyecto>` (metadato `enable-oslogin`).
   - Con organización, 1.1.1, 1.1.2, 1.3, 1.4, 2.2, 2.15 y 2.16: la evidencia que pide cada punto
     de "Controles manuales del CIS" del runbook 01.
5. **Pendientes**: este procedimiento es el punto 56 de `docs/pendientes-apply.md`, que completa
   la fila "Sin hallazgos críticos ni altos en Security Command Center" de los criterios de
   aceptación del README (activación de SCC: punto 2). Relacionados: 15 (bloqueo del bucket de
   logs), 57 a 62 (controles agregados el 23 nov 2026), 90 a 93 (protección de la etapa 0) y, con
   organización, 3, 5 y 106 a 109.

## 7. Límites de este mapa

- Versión: Prowler nombra la lista "v5.0.0"; CIS publica 5.0.1. La equivalencia con 3.0 se armó
  por títulos de Prowler, no con el PDF de CIS.
- Severidades de SCC no publicadas por categoría; las de Prowler son solo referencia.
- checkov: los IDs de las filas salen del índice público, no de la salida de una corrida, y
  pueden diferir de checkov 3.4.6 del CI. Ese índice lista las revisiones de VM (CKV_GCP_30 a CKV_GCP_40) para
  `google_compute_instance`, `google_compute_instance_template` y
  `google_compute_instance_from_template`, no para `google_compute_region_instance_template`,
  que es lo que usa `modules/compute-mig`. Para el MIG, la revisión en PR la hacen Conftest
  (Shielded VM e IP pública) y las validaciones del módulo.
- Los detectores `OPEN_SSH_PORT` y `OPEN_RDP_PORT` revisan reglas de firewall de VPC
  (`compute.googleapis.com/Firewall`); el repositorio usa políticas de firewall de red, así que el
  control efectivo es la validación del módulo `firewall`, no SCC.
- Owner: la documentación de Google dice que el usuario que crea un proyecto queda como owner.
  En el proyecto único es la persona de la etapa 0, que además es el acceso de emergencia
  ([`pendientes-apply.md`](pendientes-apply.md) §5).
- Los nodos de GKE quedan fuera de varios detectores de VM; su referencia es el CIS GKE
  Benchmark, que este documento no mapea.
