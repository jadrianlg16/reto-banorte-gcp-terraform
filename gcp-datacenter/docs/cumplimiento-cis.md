# Cumplimiento del CIS Google Cloud Platform Foundation Benchmark

Mapa de cada recomendación del benchmark contra el código, al 23 nov 2026. **Nada se ha
aplicado**: "Código" y "Política de org" dicen que el control está escrito, no que GCP lo
confirme. El cumplimiento solo lo prueba la evaluación de Security Command Center (SCC) después
del primer apply (§6). Rutas relativas a `gcp-datacenter/`.

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
  - checkov, índice de políticas de Terraform: <https://www.checkov.io/5.Policy%20Index/terraform.html>

Método: cada fila sale de leer el código (búsqueda del recurso y el atributo, 23 nov 2026). Para
el mapa no se corrieron checkov, Conftest ni `terraform`. Actualizado el mismo 23 nov 2026 al
cerrar los huecos que no dependían de GCP (1.17, 2.5 a 2.14, 3.10, 4.4 y los pasos manuales del
runbook 01) y registrar las desviaciones del ADR 0027; esos cambios sí pasaron por
`scripts/check.sh`, y lo que solo se comprueba en GCP quedó en los pendientes 56 a 62 (§5.4). Los
conteos de §4 salen de un script sobre las tablas de §3, no a mano.

## 2. Estados

| Estado | Significado |
|---|---|
| **Política de org** | Restricción de `modules/org/main.tf` (`local.policies` → `google_org_policy_policy.this`), aplicada en la organización por la etapa 1. Cubre también lo que se cree fuera de Terraform. |
| **Código** | Un recurso o una validación de variable lo fija. |
| **Revisión en PR** | Solo lo detecta checkov o Conftest en el PR. |
| **Manual** | Fuera de Terraform y pedido por un runbook. |
| **No aplica** | El repositorio no usa el servicio. |
| **Desviación** | No se cumple por una decisión documentada, con su riesgo y lo que la cerraría: [ADR 0027](adr/0027-desviaciones-aceptadas-del-cis.md). |
| **Hueco** | No se aborda, o es un paso manual que ningún documento pide. |

Cada fila tiene un solo estado. Si hay varios controles manda el más fuerte (Política de org >
Código > Revisión en PR) y los demás se nombran en la fila. "(parcial)" marca un control que no
cubre todo el alcance (§5).

## 3. Mapa por sección

### 1. Identity and Access Management

| 5.0 | 3.0 · categoría SCC | Recomendación | Cómo lo aborda el repositorio | Estado |
|---|---|---|---|---|
| 1.1.1 | — | Correo del superadministrador no ligado a una persona | Fuera de Terraform (Cloud Identity). Runbook 01, "Controles manuales del CIS", punto A: dos superadministradores con dirección de rol, llaves de seguridad guardadas, evidencia con captura. | **Manual** |
| 1.1.2 | — | Superadministrador no usado para administrar Google Cloud | Runbook 01: la persona de la etapa 0 no es superadministradora (prerrequisitos) y el superadministrador no tiene roles de IAM en la organización (punto A, con `gcloud organizations get-iam-policy` vacío como evidencia). | **Manual** |
| 1.1.3 | — | Carpetas por entorno y sensibilidad | `modules/folders` desde `stages/0-bootstrap/main.tf` (`bootstrap`) y `stages/1-org/main.tf` (`module "folders"`: `common`, `dev`, `qa`, `prod`). | **Código** |
| 1.1.4 | — | Políticas de organización centralizadas | Nueve restricciones en la organización (`modules/org/main.tf`, `local.policies`; `policy_parent = null` = organización). | **Política de org** |
| 1.2 | 1.1 · `NON_ORG_IAM_MEMBER` | Credenciales corporativas | `iam.allowedPolicyMemberDomains` = `directory_customer_id`; `modules/iam/variables.tf` rechaza `user:`, `domain:`, `allUsers` y `allAuthenticatedUsers`; Conftest `policies/iam_user_principal.rego`. | **Política de org** |
| 1.3 | 1.2 · `MFA_NOT_ENFORCED` | MFA en cuentas que no son de servicio | Fuera de Terraform (Cloud Identity). Runbook 01, punto B: 2SV obligatoria en la unidad organizativa raíz. | **Manual** |
| 1.4 | 1.3 · — | Llaves de seguridad para administradores | Runbook 01, punto B: método "Only security key" para las cuentas administradoras. | **Manual** |
| 1.5 | 1.4 · `USER_MANAGED_SERVICE_ACCOUNT_KEY` | Solo llaves administradas por GCP | `iam.disableServiceAccountKeyCreation`; el pipeline entra por WIF (`stages/0-bootstrap/wif.tf`); ningún `google_service_account_key` en el repositorio. | **Política de org** |
| 1.6 | 1.5 · `ADMIN_SERVICE_ACCOUNT` | Cuentas de servicio sin privilegios de administrador | Las cuentas `<prefix>-tf-*` reciben roles cuyo ID contiene "admin" (`stages/0-bootstrap/service_accounts.tf`, `org_roles`; `stages/1-org/iam.tf`, `stage_grants`; `stages/4-projects/envs/*/iam.tf`, `workloads_project_roles`) y el diseño cuenta con que queden como `roles/owner` de los proyectos que crean (pendiente 30). `modules/iam/variables.tf` solo prohíbe asignar `roles/owner` y `roles/editor`. Desde el 23 nov 2026 `1-org` tiene también `roles/essentialcontacts.admin` (1.17). Desviación aceptada en el ADR 0027. | **Desviación** |
| 1.7 | 1.6 · `OVER_PRIVILEGED_SERVICE_ACCOUNT_USER` | Sin Service Account User ni Token Creator en el proyecto | Nadie los recibe a nivel proyecto: `serviceAccountUser` va sobre cada cuenta (`stages/4-projects/envs/*/iam.tf`, llaves `actas/<k>`, scope `service_account`). checkov CKV_GCP_41 y CKV_GCP_49 revisan `google_project_iam_member` (`modules/iam/main.tf`) en cada PR; `.checkov.yaml` no omite nada. | **Código** |
| 1.8 | 1.7 · `SERVICE_ACCOUNT_KEY_NOT_ROTATED` | Rotación de llaves de usuario ≤ 90 días | No puede haber llaves de usuario (`iam.disableServiceAccountKeyCreation`). | **Política de org** |
| 1.9 | 1.8 · `SERVICE_ACCOUNT_ROLE_SEPARATION` | Separación de funciones en roles de cuentas de servicio | Ninguna persona recibe `serviceAccountAdmin` ni `serviceAccountUser` (los grupos solo tienen lectura, `stages/1-org/iam.tf`). La cuenta `5-workloads` tiene los dos sobre la cuenta `workload`, no en el proyecto (`stages/4-projects/envs/*/iam.tf`, `actas/<k>` y `saadmin/<app>/workload`). | **Código** |
| 1.10 | 1.9 · `KMS_PUBLIC_KEY` | Llaves KMS no públicas | `iam.allowedPolicyMemberDomains` impide `allUsers` y `allAuthenticatedUsers`; las validaciones de `modules/kms/variables.tf` (`encrypter_decrypters`) y `modules/iam/variables.tf` los rechazan; checkov CKV_GCP_112. | **Política de org** |
| 1.11 | 1.10 · `KMS_KEY_NOT_ROTATED` | Rotación de llaves KMS ≤ 90 días | Todas las llaves salen de `modules/kms` (`google_kms_crypto_key.this`, `rotation_period` validado entre 1 y 90 días en `modules/kms/variables.tf`; `key_rotation_period = "7776000s"` en `stages/2-security/variables.tf`); Conftest `policies/kms_rotation.rego`; checkov CKV_GCP_43. | **Código** |
| 1.12 | 1.11 · `KMS_ROLE_SEPARATION` | Separación de funciones en roles KMS | `roles/cloudkms.admin` solo para la cuenta `2-security` en `security` (`stages/1-org/iam.tf`); `cryptoKeyEncrypterDecrypter` solo para agentes de servicio (`modules/kms/main.tf`, `stages/4-projects/envs/*/iam.tf`). | **Código** |
| 1.13 | 1.12 · `API_KEY_EXISTS` | Llaves de API solo para servicios activos | El repositorio no crea llaves de API (ningún `google_apikeys_key`). | **No aplica** |
| 1.14 | 1.13 · `API_KEY_APPS_UNRESTRICTED` | Llaves de API restringidas a hosts y apps | Igual que 1.13. | **No aplica** |
| 1.15 | 1.14 · `API_KEY_APIS_UNRESTRICTED` | Llaves de API restringidas a las APIs necesarias | Igual que 1.13. | **No aplica** |
| 1.16 | 1.15 · `API_KEY_NOT_ROTATED` | Rotación de llaves de API | Igual que 1.13. | **No aplica** |
| 1.17 | 1.16 · `ESSENTIAL_CONTACTS_NOT_CONFIGURED` | Essential Contacts en la organización | `google_essential_contacts_contact.org` en `stages/1-org/essential_contacts.tf`: un contacto por grupo de `essential_contacts` (por defecto `org_admins`: LEGAL, SUSPENSION, TECHNICAL; `security_admins`: SECURITY, TECHNICAL; `billing_admins`: BILLING); la validación de `stages/1-org/variables.tf` exige las cuatro categorías que revisa el detector. `roles/essentialcontacts.admin` para `1-org` (`stages/0-bootstrap/service_accounts.tf`) y la API en el semilla (proyecto de cuota). Pendiente 57. | **Código** |
| 1.18 | 1.17 · — | Secretos fuera de las variables de entorno de Cloud Functions | No hay Cloud Functions (Cloud Run toma secretos con `secret_key_ref`, `modules/cloud-run/main.tf`). | **No aplica** |

### 2. Logging and Monitoring

| 5.0 | 3.0 · categoría SCC | Recomendación | Cómo lo aborda el repositorio | Estado |
|---|---|---|---|---|
| 2.1 | 2.1 · `AUDIT_LOGGING_DISABLED` | Cloud Audit Logs bien configurado | Acceso a datos solo en la carpeta `prod` (`stages/1-org/main.tf`, `google_folder_iam_audit_config.prod`) y en el proyecto semilla (`stages/0-bootstrap/main.tf`, `google_project_iam_audit_config.seed`). `common`, `dev` y `qa` quedan sin ellos a propósito (`checkov:skip=CKV2_GCP_5` en `modules/project-factory/main.tf`). Desviación aceptada en el ADR 0027. | **Desviación** (parcial) |
| 2.2 | — | Datos de Workspace/Cloud Identity compartidos con Google Cloud | Fuera de Terraform. Runbook 01, punto C: "Sharing options" en **Enabled** en la consola de administración. | **Manual** |
| 2.3 | 2.2 · `LOG_NOT_EXPORTED` | Sink para todas las entradas de log | Sink agregado de la organización (`modules/org/main.tf`, `google_logging_organization_sink.this`, `include_children = true`) con el filtro `logName:"cloudaudit.googleapis.com"` (`modules/org/variables.tf`, `log_sink_filter`): solo auditoría. Desviación aceptada en el ADR 0027. | **Desviación** |
| 2.4 | 2.3 · `LOCKED_RETENTION_POLICY_NOT_SET` | Bucket Lock en los buckets de logs | `modules/log-export/main.tf`: `retention_policy` siempre, `is_locked = var.retention_locked`; `log_retention_locked = false` por defecto (`stages/1-org/variables.tf`) y en el ejemplo (irreversible; pendiente 15). Desviación aceptada en el ADR 0027. | **Desviación** |
| 2.5 | 2.4 · `OWNER_NOT_MONITORED` | Métrica y alerta: cambios de propietario | `modules/audit-alerts` (`google_logging_metric.this` con el filtro de la página de SHA, `google_monitoring_alert_policy.this`, canal de correo hacia `security_admins`) en todos los proyectos que crea el repositorio: semilla (`stages/0-bootstrap/audit_alerts.tf`), `common` (`stages/1-org/audit_alerts.tf`), `net-spoke` (`stages/3-networks/envs/*/audit_alerts.tf`) y servicio (`stages/4-projects/envs/*/audit_alerts.tf`). Pendiente 58. | **Código** |
| 2.6 | 2.5 · `AUDIT_CONFIG_NOT_MONITORED` | Métrica y alerta: configuración de auditoría | Igual que 2.5 (métrica `audit_config`). | **Código** |
| 2.7 | 2.6 · `CUSTOM_ROLE_NOT_MONITORED` | Métrica y alerta: roles personalizados | Igual que 2.5 (métrica `custom_role`). | **Código** |
| 2.8 | 2.7 · `FIREWALL_NOT_MONITORED` | Métrica y alerta: reglas de firewall | Igual que 2.5 (métrica `firewall`, reglas de VPC). Los cambios de políticas de firewall de red van en una novena métrica, `firewall_policy`; los de la política jerárquica de la organización no llegan a ningún proyecto (ADR 0027). | **Código** |
| 2.9 | 2.8 · `ROUTE_NOT_MONITORED` | Métrica y alerta: rutas | Igual que 2.5 (métrica `route`). | **Código** |
| 2.10 | 2.9 · `NETWORK_NOT_MONITORED` | Métrica y alerta: redes VPC | Igual que 2.5 (métrica `network`). | **Código** |
| 2.11 | 2.10 · `BUCKET_IAM_NOT_MONITORED` | Métrica y alerta: IAM de Cloud Storage | Igual que 2.5 (métrica `bucket_iam`). | **Código** |
| 2.12 | 2.11 · `SQL_INSTANCE_NOT_MONITORED` | Métrica y alerta: configuración de Cloud SQL | Igual que 2.5 (métrica `sql_instance`). | **Código** |
| 2.13 | 2.12 · `DNS_LOGGING_DISABLED` | Registro de Cloud DNS en todas las VPC | `google_dns_policy.this` (`modules/dns/main.tf`) con `enable_logging = true` en el hub (`stages/3-networks/dns.tf`) y en cada spoke (`stages/3-networks/envs/*/dns.tf`); `google_dns_policy.onprem_sim` (`stages/3-networks/dns.tf`) con registro en la VPC `onprem-sim` cuando `simulate_onprem = true`. Pendiente 61. | **Código** |
| 2.14 | 2.13 · `CLOUD_ASSET_API_DISABLED` | Cloud Asset Inventory habilitado | `cloudasset.googleapis.com` en `local.baseline_apis` de `modules/project-factory/main.tf`: todo proyecto del repositorio (semilla, `common`, `net-spoke` y servicio) la habilita. `drift.yml` la usa con el semilla como proyecto de cuota (pendiente 60). | **Código** |
| 2.15 | 2.14 · `ACCESS_TRANSPARENCY_DISABLED` | Access Transparency | Fuera de Terraform; Google la activa por defecto en toda organización. Runbook 01, punto D: comprobarla en IAM & Admin > IAM > Settings y guardar la captura. | **Manual** |
| 2.16 | 2.15 · — | Access Approval | Runbook 01, punto E: inscribir la organización en la consola (requiere 2.15), avisos al grupo `security_admins`. No va en Terraform para no dar a `1-org` otro rol de administración (1.6). | **Manual** |
| 2.17 | 2.16 · `LOAD_BALANCER_LOGGING_DISABLED` | Registro del balanceador HTTP(S) | `log_config { enable = true }` en `google_compute_backend_service.this` y `google_compute_region_backend_service.this` (`modules/load-balancer/main.tf`); `log_sample_rate` debe ser mayor que 0 (validación en `variables.tf`). | **Código** |

### 3. Networking

| 5.0 | 3.0 · categoría SCC | Recomendación | Cómo lo aborda el repositorio | Estado |
|---|---|---|---|---|
| 3.1 | 3.1 · `DEFAULT_NETWORK` | Sin red `default` | `compute.skipDefaultNetworkCreation`; `auto_create_network = false` en `modules/project-factory/main.tf`; checkov CKV_GCP_27. | **Política de org** |
| 3.2 | 3.2 · `LEGACY_NETWORK` | Sin redes heredadas | Todas las VPC en modo personalizado: `auto_create_subnetworks = false` en `modules/network-hub/main.tf` y `modules/network-spoke/main.tf`. | **Código** |
| 3.3 | 3.3 · `DNSSEC_DISABLED` | DNSSEC en Cloud DNS | Solo zonas privadas (`visibility = "private"` fijo en `modules/dns/main.tf`); la zona pública del dominio queda fuera del repositorio (README, pasos después de la etapa 5). | **No aplica** |
| 3.4 | 3.4 · `RSASHA1_FOR_SIGNING` | Sin RSASHA1 en la llave de firma de llaves | Igual que 3.3. | **No aplica** |
| 3.5 | 3.5 · `RSASHA1_FOR_SIGNING` | Sin RSASHA1 en la llave de firma de zona | Igual que 3.3. | **No aplica** |
| 3.6 | 3.6 · `OPEN_SSH_PORT` | SSH restringido desde internet | Sin reglas de VPC (`google_compute_firewall`): políticas de firewall con denegación de entrada por defecto (`modules/firewall/main.tf`); `modules/firewall/variables.tf` rechaza un `allow` de entrada con origen más amplio que /8; SSH solo desde IAP (`35.235.240.0/20`) hacia `iap_ssh` (`stages/3-networks/envs/*/firewall.tf`). | **Código** |
| 3.7 | 3.7 · `OPEN_RDP_PORT` | RDP restringido desde internet | La organización solo delega 3389 desde IAP (`stages/3-networks/firewall.tf`, `delegate-iap`) y ningún spoke lo permite; misma validación que 3.6. | **Código** |
| 3.8 | — | VPC Service Controls en los servicios admitidos | Perímetro de prod (`modules/vpc-sc`; `stages/2-security/main.tf`, `module "vpc_sc"`; altas en `stages/4-projects/envs/prod/vpc_sc.tf`) en dry-run por defecto (`vpc_sc_enforced = false`); dev y qa fuera (ADR 0009, 0019 y 0027). | **Código** (parcial) |
| 3.9 | — | Private Service Connect para las APIs de Google | Private Google Access con el VIP restringido (`private_ip_google_access = true`, ruta `restricted_vip`, zonas DNS hacia el VIP; ADR 0026). PSC no se construye (`docs/pendientes-apply.md` §5). Desviación aceptada en el ADR 0027. | **Desviación** |
| 3.10 | 3.8 · `VPC_FLOW_LOGS_SETTINGS_NOT_RECOMMENDED` | Flow logs en cada subred | `log_config` en todas las subredes normales (`modules/network-hub/main.tf`, `modules/network-spoke/main.tf`) con intervalo de 5 s, todos los metadatos y `flow_sampling = var.flow_log_sampling`, que vale 1.0 por defecto en los dos módulos y en `stages/3-networks/envs/*/variables.tf`: el hub, `onprem-sim` y prod (`terraform.tfvars.example`) quedan al 100 %. Los ejemplos de dev y qa lo bajan a 0.5 por costo (desviación del ADR 0027). Las subredes proxy-only no admiten flow logs (omisión de CKV_GCP_26; el detector las excluye). Pendiente 62. | **Código** (parcial) |
| 3.11 | 3.9 · `WEAK_SSL_POLICY` | Sin cifrados débiles en políticas SSL | `google_compute_ssl_policy.this` y `google_compute_region_ssl_policy.this` con `profile` MODERN o RESTRICTED (validación) y `min_tls_version = "TLS_1_2"` (`modules/load-balancer/main.tf`); checkov CKV_GCP_4. | **Código** |
| 3.12 | 3.10 · — | IAP: solo tráfico desde IP de Google | La entrada a las cargas solo se permite desde los rangos del balanceador (`35.191.0.0/16`, `130.211.0.0/22`), desde IAP hacia etiquetas seguras y desde rangos internos (`stages/3-networks/envs/*/firewall.tf`). IAP no protege el HTTPS de la aplicación, que es pública detrás de Cloud Armor (ADR 0005 y 0020). | **Código** (parcial) |

### 4. Virtual Machines

| 5.0 | 3.0 · categoría SCC | Recomendación | Cómo lo aborda el repositorio | Estado |
|---|---|---|---|---|
| 4.1 | 4.1 · `DEFAULT_SERVICE_ACCOUNT_USED` | Sin cuenta de servicio por defecto | `service_account` del MIG y `node_service_account` de GKE se validan como `<id>@<proyecto>.iam.gserviceaccount.com`, lo que excluye `<n>-compute@developer.gserviceaccount.com` (`modules/compute-mig/variables.tf`, `modules/gke/variables.tf`). | **Código** |
| 4.2 | 4.2 · `FULL_API_ACCESS` | Sin cuenta por defecto con acceso a todas las APIs | Igual que 4.1: el alcance `cloud-platform` va con cuentas dedicadas. | **Código** |
| 4.3 | 4.3 · `COMPUTE_PROJECT_WIDE_SSH_KEYS_ALLOWED` | Bloquear llaves SSH del proyecto | `block-project-ssh-keys = "TRUE"` fijo en `local.metadata` de `modules/compute-mig/main.tf`; la validación de `metadata` impide cambiarlo. Los nodos de GKE no lo llevan; SHA los excluye. | **Código** |
| 4.4 | 4.4 · `OS_LOGIN_DISABLED` | OS Login en el proyecto | `google_compute_project_metadata_item.os_login` (`enable-oslogin = "TRUE"`) en `modules/project-factory/main.tf` en todo proyecto con la API de Compute (semilla, `net-hub`, `net-spoke` y servicio), que es lo que lee el detector; además por instancia en `modules/compute-mig/main.tf`. Los nodos de GKE Standard heredan el metadato del proyecto (SHA los excluye). Se prefirió al metadato antes que `compute.requireOsLogin` porque la política solo escribe el metadato en proyectos nuevos (README de `project-factory`). Pendiente 59. | **Código** |
| 4.5 | 4.5 · `COMPUTE_SERIAL_PORTS_ENABLED` | Puerto serie apagado | `serial-port-enable = "FALSE"` fijo en `modules/compute-mig/main.tf`. | **Código** |
| 4.6 | 4.6 · `IP_FORWARDING_ENABLED` | Sin reenvío de IP | `can_ip_forward = false` en `google_compute_region_instance_template.this` (`modules/compute-mig/main.tf`). Los nodos de GKE lo necesitan; SHA los excluye. | **Código** |
| 4.7 | 4.7 · `DISK_CSEK_DISABLED` | CSEK en discos de VM críticas | Discos con CMEK, no CSEK (`disk_encryption_key.kms_key_self_link` en `modules/compute-mig/main.tf`; `boot_disk_kms_key` en `modules/gke/main.tf`). Desviación aceptada en el ADR 0027. | **Desviación** |
| 4.8 | 4.8 · `SHIELDED_VM_DISABLED` | Shielded VM | `compute.requireShieldedVm`; `shielded_instance_config` con arranque seguro, vTPM e integridad en el MIG; `enable_shielded_nodes = true` y arranque seguro en GKE; Conftest `policies/shielded_vm.rego`. | **Política de org** |
| 4.9 | 4.9 · `PUBLIC_IP_ADDRESS` | Sin IP pública | `compute.vmExternalIpAccess` (`deny_all`); MIG sin `access_config` y con `stack_type = "IPV4_ONLY"`; GKE con `enable_private_nodes = true`; Conftest `policies/compute_public_ip.rego`. | **Política de org** |
| 4.10 | 4.10 · — | App Engine solo con HTTPS | No hay App Engine. | **No aplica** |
| 4.11 | 4.11 · `CONFIDENTIAL_COMPUTING_DISABLED` | Confidential Computing | Ningún `confidential_instance_config` (MIG) ni `confidential_nodes` (GKE); los ejemplos usan `e2-*`. Desviación aceptada en el ADR 0027. | **Desviación** |
| 4.12 | 4.12 · — | Actualizaciones de SO al día | GKE: `auto_upgrade = true` e imagen COS (`modules/gke/main.tf`). MIG: sin VM Manager ni `google_os_config_patch_deployment`; depende de la imagen `mig_image`. Desviación aceptada en el ADR 0027. | **Desviación** (parcial) |

### 5. Storage

| 5.0 | 3.0 · categoría SCC | Recomendación | Cómo lo aborda el repositorio | Estado |
|---|---|---|---|---|
| 5.1 | 5.1 · `PUBLIC_BUCKET_ACL` | Buckets no públicos | `storage.publicAccessPrevention` e `iam.allowedPolicyMemberDomains`; `public_access_prevention = "enforced"` en los tres recursos de bucket (`modules/storage/main.tf`, `modules/log-export/main.tf`, `stages/0-bootstrap/main.tf`); Conftest `policies/bucket_public_access.rego`. | **Política de org** |
| 5.2 | 5.2 · `BUCKET_POLICY_ONLY_DISABLED` | Acceso uniforme a nivel de bucket | `storage.uniformBucketLevelAccess`; `uniform_bucket_level_access = true` en los mismos tres recursos; checkov CKV_GCP_29. | **Política de org** |

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
| 6.5 | 6.5 · `PUBLIC_SQL_INSTANCE` | Sin todas las IP públicas autorizadas | `sql.restrictPublicIp`; `ipv4_enabled = false` y ningún `authorized_networks`. | **Política de org** |
| 6.6 | — | Autenticación IAM de base de datos | `cloudsql.iam_authentication = "on"`; usuarios `google_sql_user.iam` sin contraseña (ADR 0015). | **Código** |
| 6.7 | 6.6 · `SQL_PUBLIC_IP` | Sin IP pública | `sql.restrictPublicIp`; `ipv4_enabled = false` y `private_network` en primaria y réplica; Conftest `policies/sql_public_ip.rego`; checkov CKV_GCP_60. | **Política de org** |
| 6.8 | 6.7 · `AUTO_BACKUP_DISABLED` | Respaldos automáticos | `backup_configuration` con `enabled = true` y `point_in_time_recovery_enabled = true` en la primaria; la réplica no admite respaldos (omisión de CKV_GCP_14 justificada) y SHA excluye réplicas. | **Código** |
| 6.9 | — | Protección contra borrado | `deletion_protection` y `deletion_protection_enabled` = `var.deletion_protection` (por defecto `true`; obligatorio en prod por validación). Los ejemplos de dev y qa lo ponen en `false` para el `destroy` (pendiente 11; desviación del ADR 0027). | **Código** (parcial) |

### 7. BigQuery y 8. Dataproc

| 5.0 | 3.0 · categoría SCC | Recomendación | Cómo lo aborda el repositorio | Estado |
|---|---|---|---|---|
| 7.1 | 7.1 · `PUBLIC_DATASET` | Datasets no públicos | Ningún recurso `google_bigquery_*`; el sink de auditoría escribe en Cloud Storage. | **No aplica** |
| 7.2 | 7.2 · `BIGQUERY_TABLE_CMEK_DISABLED` | Tablas con CMEK | Igual que 7.1. | **No aplica** |
| 7.3 | 7.3 · `DATASET_CMEK_DISABLED` | CMEK por defecto en datasets | Igual que 7.1. | **No aplica** |
| 7.4 | 7.4 · — | Datos de BigQuery clasificados | Igual que 7.1. | **No aplica** |
| 8.1 | 8.1 · `DATAPROC_CMEK_DISABLED` | Clústeres de Dataproc con CMEK | Ningún recurso `google_dataproc_*`. | **No aplica** |

## 4. Resumen

| Sección | Código | Política de org | Revisión en PR | Manual | No aplica | Desviación | Hueco | Total |
|---|---|---|---|---|---|---|---|---|
| 1 IAM | 6 | 5 | 0 | 4 | 5 | 1 | 0 | 21 |
| 2 Logging and Monitoring | 11 | 0 | 0 | 3 | 0 | 3 | 0 | 17 |
| 3 Networking | 7 | 1 | 0 | 0 | 3 | 1 | 0 | 12 |
| 4 Virtual Machines | 6 | 2 | 0 | 0 | 1 | 3 | 0 | 12 |
| 5 Storage | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 2 |
| 6 Cloud SQL | 12 | 2 | 0 | 0 | 10 | 0 | 0 | 24 |
| 7 BigQuery | 0 | 0 | 0 | 0 | 4 | 0 | 0 | 4 |
| 8 Dataproc | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 1 |
| **Total** | **42** | **12** | **0** | **7** | **24** | **8** | **0** | **93** |

Conteo del 23 nov 2026 con un script de Python (fuera del repositorio) que toma la última columna
de cada fila de §3 cuyo primer campo es un ID, le quita `**` y "(parcial)" y suma por sección; no
se contó a mano.

- De las 69 recomendaciones que aplican, 61 tienen un control escrito (42 Código, 12 Política de
  org, 7 Manual) y 8 son desviaciones aceptadas en el
  [ADR 0027](adr/0027-desviaciones-aceptadas-del-cis.md). No queda ningún hueco: lo que no se
  cumple está decidido y documentado.
- Seis filas son parciales: cuatro con estado Código (3.8, 3.10, 3.12, 6.9) y dos con estado
  Desviación (2.1, 4.12). §5 dice qué falta en cada una.
- "Revisión en PR" no es el control principal de ninguna fila: checkov y Conftest refuerzan
  controles que ya están en el código o en una política de organización.
- "Código" y "Política de org" están escritos y pasan `scripts/check.sh` (plan con proveedor
  simulado), no aplicados. "Manual" son los pasos A a E de "Controles manuales del CIS" del
  runbook 01: escritos, no hechos. Nada de esto cuenta como cumplido hasta la evaluación del
  pendiente 56.

## 5. Lo que queda abierto

La documentación de Google consultada no publica la severidad por categoría (la página de
severidad solo define los niveles); el nivel real se verá en el primer escaneo. La columna
"Severidad" da la de la revisión equivalente de Prowler como referencia, **no la de SCC**. "CM"
dice si el marco CIS v3.0 de Compliance Manager tiene un control para esa recomendación (lista de
49 controles publicada, 23 nov 2026).

### 5.1 Desviaciones aceptadas

Las ocho filas con estado Desviación y la parte que no cubren tres filas Código (parcial). El
porqué, el riesgo y la corrección completa están en el
[ADR 0027](adr/0027-desviaciones-aceptadas-del-cis.md); el cliente tiene que aceptarlas o pedir
que se construya la corrección.

| 5.0 | Qué no se cumple | SCC | Severidad (Prowler) | Para cumplir | Esfuerzo |
|---|---|---|---|---|---|
| 1.6 | Cuentas del pipeline con roles `*admin*` y owner de los proyectos que crean | `ADMIN_SERVICE_ACCOUNT`; CM no | alta | Roles personalizados mínimos por etapa y quitar el owner que GCP da al creador (rehace el pendiente 30). Una regla de silencio acotada a `<prefix>-tf-*` documenta el hallazgo pero no cumple. | L |
| 2.1 (parcial) | Acceso a datos solo en la carpeta `prod` y en el semilla | `AUDIT_LOGGING_DISABLED`; CM no | media | `google_organization_iam_audit_config` en `stages/1-org` y quitar `checkov:skip=CKV2_GCP_5` de `modules/project-factory/main.tf`. Sube el costo de logs. | S (código), M (costo) |
| 2.3 | Sink agregado solo de auditoría | `LOG_NOT_EXPORTED`; CM no. HYPOTHESIS: el detector pide un sink sin filtro | — | `log_sink_filter = ""` en `stages/1-org/main.tf` o un segundo sink sin filtro hacia un bucket de Logging. Sube volumen y costo. | S |
| 2.4 | Bucket Lock apagado (`log_retention_locked = false`) | `LOCKED_RETENTION_POLICY_NOT_SET`; CM sí | alta | `log_retention_locked = true` en el `terraform.tfvars` real de `stages/1-org` después de probar el pendiente 15. Irreversible. | S |
| 3.8 (parcial) | Perímetro de prod en dry-run; dev y qa sin perímetro | Sin mapeo CIS 3.0; CM no | — | Forzar el perímetro después de revisar el dry-run (pendientes 4, 5, 17, 18 y 53); dev y qa necesitan llaves propias (ADR 0019). | M |
| 3.9 | API de Google por el VIP restringido, no por PSC | Sin detector; CM no | — | Endpoint PSC global en `modules/network-hub` y `modules/network-spoke`, zonas DNS hacia esa IP y un ADR que reemplace al 0026. | M |
| 3.10 (parcial) | Flow logs de dev y qa al 50 % en sus `terraform.tfvars.example` | `VPC_FLOW_LOGS_SETTINGS_NOT_RECOMMENDED` (hay que activar el detector); CM sí | media | `flow_log_sampling = 1` en el `terraform.tfvars` de dev y qa (el valor por defecto ya es 1). | S |
| 4.7 | CMEK en lugar de CSEK | `DISK_CSEK_DISABLED`, solo en discos con la marca `enforce_customer_supplied_disk_encryption_keys`; CM no | alta | VM sueltas con CSEK y llaves fuera de GCP; no compatible con el MIG ni con GKE (HYPOTHESIS). | L |
| 4.11 | Sin Confidential Computing | `CONFIDENTIAL_COMPUTING_DISABLED` (solo escanea N2D); CM sí | media | `confidential_instance_config`, tipo N2D y `on_host_maintenance = "TERMINATE"` en `modules/compute-mig/main.tf`; `confidential_nodes { enabled = true }` en `modules/gke/main.tf`. Cambia tipos de máquina y costo. | M |
| 4.12 (parcial) | VM del MIG sin VM Manager (GKE sí se actualiza) | Sin detector (VM Manager reporta vulnerabilidades si está activo); CM no | — | `osconfig.googleapis.com`, `enable-osconfig = "TRUE"` en `local.metadata` de `modules/compute-mig/main.tf` y `google_os_config_patch_deployment` en `stages/5-workloads/envs/*/compute.tf`. | M |
| 6.9 (parcial) | Cloud SQL de dev y qa sin protección contra borrado en los ejemplos | Sin mapeo CIS 3.0; CM no | — | `deletion_protection = true` en dev y qa, y apagarla en el procedimiento de destroy (pendiente 11). | S |

### 5.2 Otros límites de filas cubiertas

- **3.12** (Código, parcial): IAP en el servicio de backend volvería privada la aplicación, que es
  pública detrás de Cloud Armor (ADR 0005 y 0020); se deja así por diseño.
- **2.8** (Código): los cambios de la política de firewall jerárquica de la organización no llegan
  a ninguna métrica de proyecto (HYPOTHESIS, ADR 0027); quedan en el sink agregado y en
  `drift.yml`.
- **4.4** (Código): el metadato `enable-oslogin` solo se escribe en los proyectos que habilitan la
  API de Compute (`local.enable_os_login` de `modules/project-factory/main.tf`); en los demás no
  hay VM. Que el detector no marque un proyecto sin esa API es HYPOTHESIS (pendiente 59).

### 5.3 Pasos manuales por hacer

Los pasos A a E de "Controles manuales del CIS" del
[runbook 01](runbooks/01-arranque-etapa-0.md) (1.1.1, 1.1.2, 1.3, 1.4, 2.2, 2.15, 2.16) los hace
un superadministrador de Cloud Identity antes de la etapa 0 o justo después; su evidencia va a la
revisión del pendiente 56. Quedan como HYPOTHESIS en el runbook la ruta de los roles de
administración, la 2SV por grupo de configuración, el filtro de `gcloud logging read`, cómo se
vuelve a activar Access Transparency, `roles/accessapproval.configEditor` a nivel organización,
el costo de Access Approval y la sintaxis de `gcloud access-approval settings get`.

### 5.4 Pendientes del primer apply

En [`pendientes-apply.md`](pendientes-apply.md), §3.7:

- 56: evaluación del CIS después del primer apply (procedimiento de §6).
- 57: contactos esenciales de la organización (1.17).
- 58: métricas de log y alertas de auditoría (2.5 a 2.12).
- 59: OS Login en los metadatos del proyecto (4.4).
- 60: Cloud Asset para `drift.yml` (2.14).
- 61: registro de Cloud DNS en `onprem-sim` (2.13).
- 62: flow logs al 100 % en prod, hub y `onprem-sim` (3.10).

Hallazgos probables de SHA fuera del marco CIS v3.0 (HYPOTHESIS):

- `KMS_PROJECT_HAS_OWNER`: la persona de la etapa 0 queda como owner del proyecto semilla, que
  tiene la llave del estado, y la cuenta `1-org` de `logging` y `security`. Google lo mapea a CIS
  1.11 solo hasta la versión 2.0.
- `SERVICE_ACCOUNT_ROLE_SEPARATION`: la cuenta `5-workloads` tiene `serviceAccountAdmin` y
  `serviceAccountUser` sobre la cuenta `workload` (1.9). Depende de si SHA revisa el IAM de la
  cuenta de servicio además del de proyecto y organización.

## 6. Verificación después del primer apply

1. **Activar SCC** a mano antes de la etapa 1: pendiente 2 (runbook 01, paso 7) y pendiente 23.
   La etapa 1 ya envía los hallazgos activos HIGH y CRITICAL a Pub/Sub
   (`google_scc_v2_organization_notification_config.findings` con `scc_notification_filter`; el
   tema es el pendiente 34).
2. **Qué evalúa SCC** (documentación de Google, 23 nov 2026): en una organización que activa
   Standard o Premium por primera vez, SHA no está disponible y la evaluación pasa a Compliance
   Manager, cuyo marco integrado es "CIS GCP Foundations Benchmark v3.0". Casi todos los
   detectores de SHA con mapeo CIS dicen "Pricing tier: Premium" (excepciones: `OPEN_SSH_PORT`,
   `OPEN_RDP_PORT`, `PUBLIC_IP_ADDRESS`, `PUBLIC_BUCKET_ACL`, entre otras). El runbook 01 deja el
   nivel abierto ("Standard o Premium"): si el criterio es CIS, decidir con eso a la vista. Qué
   marcos ofrece Standard: por verificar en la consola.
3. **Procedimiento**: en Compliance, activar el marco CIS v3.0 en la organización y revisar la
   pestaña Monitor; en Findings, filtrar `state="ACTIVE" AND (severity="HIGH" OR
   severity="CRITICAL")`. Cada control se traduce a la 5.0 con la columna "3.0" de §3.
4. **Lo que SCC no prueba**: de las once filas de §5.1, solo 2.4, 3.10 y 4.11 tienen control en
   el marco CIS v3.0 de Compliance Manager; de los huecos cerrados el 23 nov 2026, solo 1.17 y
   2.14. "Sin hallazgos críticos ni altos" puede cumplirse con desviaciones abiertas, y SCC puede
   reportar desviaciones ya aceptadas (1.6, 2.1, 2.4, 3.10 en dev y qa): la revisión las separa de
   los hallazgos inesperados con el ADR 0027. Evidencia aparte:
   - IAM (1.6, 1.9, 1.12): `gcloud organizations get-iam-policy <org>` y
     `gcloud projects get-iam-policy <proyecto>` por proyecto.
   - 1.17: `gcloud essential-contacts list --organization=<org>` (sintaxis HYPOTHESIS): un
     contacto por grupo con sus categorías.
   - 2.1: `auditConfigs` en la salida de `gcloud organizations get-iam-policy <org> --format=json`.
   - 2.3: `gcloud logging sinks list --organization=<org>`.
   - 2.5–2.12: `gcloud logging metrics list --project=<proyecto>` y las políticas de alerta de
     Cloud Monitoring de cada proyecto (pendiente 58).
   - 2.14: `gcloud services list --enabled --project=<proyecto>` muestra
     `cloudasset.googleapis.com` en cada proyecto.
   - 4.4: `gcloud compute project-info describe --project=<proyecto>` (metadato `enable-oslogin`).
   - 1.1.1, 1.1.2, 1.3, 1.4, 2.2, 2.15, 2.16: la evidencia que pide cada punto de "Controles
     manuales del CIS" del runbook 01.
5. **Pendientes**: este procedimiento es el punto 56 de `docs/pendientes-apply.md`, que completa
   la fila "Sin hallazgos críticos ni altos en Security Command Center" de los criterios de
   aceptación del README (activación de SCC: punto 2). Relacionados: 15 (bloqueo del bucket de
   logs), 30 (owner implícito), 4, 5, 17 y 18 (perímetro) y 57 a 62 (controles agregados el
   23 nov 2026).

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
  (`compute.googleapis.com/Firewall`); el repositorio usa políticas de firewall, así que el
  control efectivo es la validación del módulo `firewall`, no SCC.
- Owner implícito: la documentación de Google dice que el usuario que crea un proyecto queda como
  owner; que pase igual con una cuenta de servicio es HYPOTHESIS (pendiente 30).
- Los nodos de GKE quedan fuera de varios detectores de VM; su referencia es el CIS GKE
  Benchmark, que este documento no mapea.
