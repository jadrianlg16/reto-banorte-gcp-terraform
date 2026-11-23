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
este documento no se corrieron checkov, Conftest ni `terraform`.

## 2. Estados

| Estado | Significado |
|---|---|
| **Política de org** | Restricción de `modules/org/main.tf` (`local.policies` → `google_org_policy_policy.this`), aplicada en la organización por la etapa 1. Cubre también lo que se cree fuera de Terraform. |
| **Código** | Un recurso o una validación de variable lo fija. |
| **Revisión en PR** | Solo lo detecta checkov o Conftest en el PR. |
| **Manual** | Fuera de Terraform y pedido por un runbook. |
| **No aplica** | El repositorio no usa el servicio. |
| **Hueco** | No se aborda, o es un paso manual que ningún documento pide. |

Cada fila tiene un solo estado. Si hay varios controles manda el más fuerte (Política de org >
Código > Revisión en PR) y los demás se nombran en la fila. "(parcial)" marca un control que no
cubre todo el alcance (§5).

## 3. Mapa por sección

### 1. Identity and Access Management

| 5.0 | 3.0 · categoría SCC | Recomendación | Cómo lo aborda el repositorio | Estado |
|---|---|---|---|---|
| 1.1.1 | — | Correo del superadministrador no ligado a una persona | Fuera de Terraform (Cloud Identity); ningún runbook lo pide. | **Hueco** |
| 1.1.2 | — | Superadministrador no usado para administrar Google Cloud | Fuera de Terraform. El runbook 01 lista los roles de la persona de la etapa 0, pero no exige ni prohíbe que sea superadministradora. | **Hueco** |
| 1.1.3 | — | Carpetas por entorno y sensibilidad | `modules/folders` desde `stages/0-bootstrap/main.tf` (`bootstrap`) y `stages/1-org/main.tf` (`module "folders"`: `common`, `dev`, `qa`, `prod`). | **Código** |
| 1.1.4 | — | Políticas de organización centralizadas | Nueve restricciones en la organización (`modules/org/main.tf`, `local.policies`; `policy_parent = null` = organización). | **Política de org** |
| 1.2 | 1.1 · `NON_ORG_IAM_MEMBER` | Credenciales corporativas | `iam.allowedPolicyMemberDomains` = `directory_customer_id`; `modules/iam/variables.tf` rechaza `user:`, `domain:`, `allUsers` y `allAuthenticatedUsers`; Conftest `policies/iam_user_principal.rego`. | **Política de org** |
| 1.3 | 1.2 · `MFA_NOT_ENFORCED` | MFA en cuentas que no son de servicio | Fuera de Terraform (Cloud Identity); ningún runbook lo pide. | **Hueco** |
| 1.4 | 1.3 · — | Llaves de seguridad para administradores | Igual que 1.3. | **Hueco** |
| 1.5 | 1.4 · `USER_MANAGED_SERVICE_ACCOUNT_KEY` | Solo llaves administradas por GCP | `iam.disableServiceAccountKeyCreation`; el pipeline entra por WIF (`stages/0-bootstrap/wif.tf`); ningún `google_service_account_key` en el repositorio. | **Política de org** |
| 1.6 | 1.5 · `ADMIN_SERVICE_ACCOUNT` | Cuentas de servicio sin privilegios de administrador | Las cuentas `<prefix>-tf-*` reciben roles cuyo ID contiene "admin" (`stages/0-bootstrap/service_accounts.tf`, `org_roles`; `stages/1-org/iam.tf`, `stage_grants`; `stages/4-projects/envs/*/iam.tf`, `workloads_project_roles`) y el diseño cuenta con que queden como `roles/owner` de los proyectos que crean (pendiente 30). `modules/iam/variables.tf` solo prohíbe asignar `roles/owner` y `roles/editor`. | **Hueco** |
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
| 1.17 | 1.16 · `ESSENTIAL_CONTACTS_NOT_CONFIGURED` | Essential Contacts en la organización | Ningún `google_essential_contacts_contact` ni paso manual. | **Hueco** |
| 1.18 | 1.17 · — | Secretos fuera de las variables de entorno de Cloud Functions | No hay Cloud Functions (Cloud Run toma secretos con `secret_key_ref`, `modules/cloud-run/main.tf`). | **No aplica** |

### 2. Logging and Monitoring

| 5.0 | 3.0 · categoría SCC | Recomendación | Cómo lo aborda el repositorio | Estado |
|---|---|---|---|---|
| 2.1 | 2.1 · `AUDIT_LOGGING_DISABLED` | Cloud Audit Logs bien configurado | Acceso a datos solo en la carpeta `prod` (`stages/1-org/main.tf`, `google_folder_iam_audit_config.prod`) y en el proyecto semilla (`stages/0-bootstrap/main.tf`, `google_project_iam_audit_config.seed`). `common`, `dev` y `qa` quedan sin ellos a propósito (`checkov:skip=CKV2_GCP_5` en `modules/project-factory/main.tf`). | **Hueco** (parcial) |
| 2.2 | — | Datos de Workspace/Cloud Identity compartidos con Google Cloud | Fuera de Terraform; ningún runbook lo pide. | **Hueco** |
| 2.3 | 2.2 · `LOG_NOT_EXPORTED` | Sink para todas las entradas de log | Sink agregado de la organización (`modules/org/main.tf`, `google_logging_organization_sink.this`, `include_children = true`) con el filtro `logName:"cloudaudit.googleapis.com"` (`modules/org/variables.tf`, `log_sink_filter`): solo auditoría. | **Hueco** |
| 2.4 | 2.3 · `LOCKED_RETENTION_POLICY_NOT_SET` | Bucket Lock en los buckets de logs | `modules/log-export/main.tf`: `retention_policy` siempre, `is_locked = var.retention_locked`; `log_retention_locked = false` por defecto (`stages/1-org/variables.tf`) y en el ejemplo (irreversible; pendiente 15). | **Hueco** |
| 2.5 | 2.4 · `OWNER_NOT_MONITORED` | Métrica y alerta: cambios de propietario | Ningún `google_logging_metric` en el repositorio; `modules/observability` solo alerta de disponibilidad, 5xx, saturación, retraso de réplica y SLO. | **Hueco** |
| 2.6 | 2.5 · `AUDIT_CONFIG_NOT_MONITORED` | Métrica y alerta: configuración de auditoría | Igual que 2.5. | **Hueco** |
| 2.7 | 2.6 · `CUSTOM_ROLE_NOT_MONITORED` | Métrica y alerta: roles personalizados | Igual que 2.5. | **Hueco** |
| 2.8 | 2.7 · `FIREWALL_NOT_MONITORED` | Métrica y alerta: reglas de firewall | Igual que 2.5. | **Hueco** |
| 2.9 | 2.8 · `ROUTE_NOT_MONITORED` | Métrica y alerta: rutas | Igual que 2.5. | **Hueco** |
| 2.10 | 2.9 · `NETWORK_NOT_MONITORED` | Métrica y alerta: redes VPC | Igual que 2.5. | **Hueco** |
| 2.11 | 2.10 · `BUCKET_IAM_NOT_MONITORED` | Métrica y alerta: IAM de Cloud Storage | Igual que 2.5. | **Hueco** |
| 2.12 | 2.11 · `SQL_INSTANCE_NOT_MONITORED` | Métrica y alerta: configuración de Cloud SQL | Igual que 2.5. | **Hueco** |
| 2.13 | 2.12 · `DNS_LOGGING_DISABLED` | Registro de Cloud DNS en todas las VPC | `google_dns_policy.this` (`modules/dns/main.tf`) con `enable_logging = true` en el hub (`stages/3-networks/dns.tf`) y en cada spoke (`stages/3-networks/envs/*/dns.tf`). La VPC `onprem-sim` (`stages/3-networks/vpn.tf`; `simulate_onprem = true` por defecto) no tiene política DNS. | **Código** (parcial) |
| 2.14 | 2.13 · `CLOUD_ASSET_API_DISABLED` | Cloud Asset Inventory habilitado | Ningún proyecto habilita `cloudasset.googleapis.com` (`modules/project-factory/main.tf`, `local.apis`; `stages/0-bootstrap/main.tf`, `seed_apis`), aunque `drift.yml` lo usa. | **Hueco** |
| 2.15 | 2.14 · `ACCESS_TRANSPARENCY_DISABLED` | Access Transparency | Fuera de Terraform; ningún runbook lo pide. | **Hueco** |
| 2.16 | 2.15 · — | Access Approval | Ningún `google_organization_access_approval_settings` ni paso manual. | **Hueco** |
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
| 3.8 | — | VPC Service Controls en los servicios admitidos | Perímetro de prod (`modules/vpc-sc`; `stages/2-security/main.tf`, `module "vpc_sc"`; altas en `stages/4-projects/envs/prod/vpc_sc.tf`) en dry-run por defecto (`vpc_sc_enforced = false`); dev y qa fuera (ADR 0009 y 0019). | **Código** (parcial) |
| 3.9 | — | Private Service Connect para las APIs de Google | Private Google Access con el VIP restringido (`private_ip_google_access = true`, ruta `restricted_vip`, zonas DNS hacia el VIP; ADR 0026). PSC no se construye (`docs/pendientes-apply.md` §5). | **Hueco** |
| 3.10 | 3.8 · `VPC_FLOW_LOGS_SETTINGS_NOT_RECOMMENDED` | Flow logs en cada subred | `log_config` en todas las subredes normales (`modules/network-hub/main.tf`, `modules/network-spoke/main.tf`) con intervalo de 5 s y todos los metadatos, pero `flow_sampling = var.flow_log_sampling` vale 0.5 por defecto y en los ejemplos; el detector de SCC pide 100 %. Las subredes proxy-only no admiten flow logs (omisión de CKV_GCP_26). | **Hueco** (parcial) |
| 3.11 | 3.9 · `WEAK_SSL_POLICY` | Sin cifrados débiles en políticas SSL | `google_compute_ssl_policy.this` y `google_compute_region_ssl_policy.this` con `profile` MODERN o RESTRICTED (validación) y `min_tls_version = "TLS_1_2"` (`modules/load-balancer/main.tf`); checkov CKV_GCP_4. | **Código** |
| 3.12 | 3.10 · — | IAP: solo tráfico desde IP de Google | La entrada a las cargas solo se permite desde los rangos del balanceador (`35.191.0.0/16`, `130.211.0.0/22`), desde IAP hacia etiquetas seguras y desde rangos internos (`stages/3-networks/envs/*/firewall.tf`). IAP no protege el HTTPS de la aplicación, que es pública detrás de Cloud Armor (ADR 0005 y 0020). | **Código** (parcial) |

### 4. Virtual Machines

| 5.0 | 3.0 · categoría SCC | Recomendación | Cómo lo aborda el repositorio | Estado |
|---|---|---|---|---|
| 4.1 | 4.1 · `DEFAULT_SERVICE_ACCOUNT_USED` | Sin cuenta de servicio por defecto | `service_account` del MIG y `node_service_account` de GKE se validan como `<id>@<proyecto>.iam.gserviceaccount.com`, lo que excluye `<n>-compute@developer.gserviceaccount.com` (`modules/compute-mig/variables.tf`, `modules/gke/variables.tf`). | **Código** |
| 4.2 | 4.2 · `FULL_API_ACCESS` | Sin cuenta por defecto con acceso a todas las APIs | Igual que 4.1: el alcance `cloud-platform` va con cuentas dedicadas. | **Código** |
| 4.3 | 4.3 · `COMPUTE_PROJECT_WIDE_SSH_KEYS_ALLOWED` | Bloquear llaves SSH del proyecto | `block-project-ssh-keys = "TRUE"` fijo en `local.metadata` de `modules/compute-mig/main.tf`; la validación de `metadata` impide cambiarlo. Los nodos de GKE no lo llevan; SHA los excluye. | **Código** |
| 4.4 | 4.4 · `OS_LOGIN_DISABLED` | OS Login en el proyecto | Solo por instancia (`enable-oslogin = "TRUE"` en `modules/compute-mig/main.tf`). Ningún metadato de proyecto (`google_compute_project_metadata*`) ni `compute.requireOsLogin`; el detector lee el metadato del proyecto. | **Hueco** (parcial) |
| 4.5 | 4.5 · `COMPUTE_SERIAL_PORTS_ENABLED` | Puerto serie apagado | `serial-port-enable = "FALSE"` fijo en `modules/compute-mig/main.tf`. | **Código** |
| 4.6 | 4.6 · `IP_FORWARDING_ENABLED` | Sin reenvío de IP | `can_ip_forward = false` en `google_compute_region_instance_template.this` (`modules/compute-mig/main.tf`). Los nodos de GKE lo necesitan; SHA los excluye. | **Código** |
| 4.7 | 4.7 · `DISK_CSEK_DISABLED` | CSEK en discos de VM críticas | Discos con CMEK, no CSEK (`disk_encryption_key.kms_key_self_link` en `modules/compute-mig/main.tf`; `boot_disk_kms_key` en `modules/gke/main.tf`). | **Hueco** |
| 4.8 | 4.8 · `SHIELDED_VM_DISABLED` | Shielded VM | `compute.requireShieldedVm`; `shielded_instance_config` con arranque seguro, vTPM e integridad en el MIG; `enable_shielded_nodes = true` y arranque seguro en GKE; Conftest `policies/shielded_vm.rego`. | **Política de org** |
| 4.9 | 4.9 · `PUBLIC_IP_ADDRESS` | Sin IP pública | `compute.vmExternalIpAccess` (`deny_all`); MIG sin `access_config` y con `stack_type = "IPV4_ONLY"`; GKE con `enable_private_nodes = true`; Conftest `policies/compute_public_ip.rego`. | **Política de org** |
| 4.10 | 4.10 · — | App Engine solo con HTTPS | No hay App Engine. | **No aplica** |
| 4.11 | 4.11 · `CONFIDENTIAL_COMPUTING_DISABLED` | Confidential Computing | Ningún `confidential_instance_config` (MIG) ni `confidential_nodes` (GKE); los ejemplos usan `e2-*`. | **Hueco** |
| 4.12 | 4.12 · — | Actualizaciones de SO al día | GKE: `auto_upgrade = true` e imagen COS (`modules/gke/main.tf`). MIG: sin VM Manager ni `google_os_config_patch_deployment`; depende de la imagen `mig_image`. | **Hueco** (parcial) |

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
| 6.9 | — | Protección contra borrado | `deletion_protection` y `deletion_protection_enabled` = `var.deletion_protection` (por defecto `true`; obligatorio en prod por validación). Los ejemplos de dev y qa lo ponen en `false` para el `destroy` (pendiente 11). | **Código** (parcial) |

### 7. BigQuery y 8. Dataproc

| 5.0 | 3.0 · categoría SCC | Recomendación | Cómo lo aborda el repositorio | Estado |
|---|---|---|---|---|
| 7.1 | 7.1 · `PUBLIC_DATASET` | Datasets no públicos | Ningún recurso `google_bigquery_*`; el sink de auditoría escribe en Cloud Storage. | **No aplica** |
| 7.2 | 7.2 · `BIGQUERY_TABLE_CMEK_DISABLED` | Tablas con CMEK | Igual que 7.1. | **No aplica** |
| 7.3 | 7.3 · `DATASET_CMEK_DISABLED` | CMEK por defecto en datasets | Igual que 7.1. | **No aplica** |
| 7.4 | 7.4 · — | Datos de BigQuery clasificados | Igual que 7.1. | **No aplica** |
| 8.1 | 8.1 · `DATAPROC_CMEK_DISABLED` | Clústeres de Dataproc con CMEK | Ningún recurso `google_dataproc_*`. | **No aplica** |

## 4. Resumen

| Sección | Código | Política de org | Revisión en PR | Manual | No aplica | Hueco | Total |
|---|---|---|---|---|---|---|---|
| 1 IAM | 5 | 5 | 0 | 0 | 5 | 6 | 21 |
| 2 Logging and Monitoring | 2 | 0 | 0 | 0 | 0 | 15 | 17 |
| 3 Networking | 6 | 1 | 0 | 0 | 3 | 2 | 12 |
| 4 Virtual Machines | 5 | 2 | 0 | 0 | 1 | 4 | 12 |
| 5 Storage | 0 | 2 | 0 | 0 | 0 | 0 | 2 |
| 6 Cloud SQL | 12 | 2 | 0 | 0 | 10 | 0 | 24 |
| 7 BigQuery | 0 | 0 | 0 | 0 | 4 | 0 | 4 |
| 8 Dataproc | 0 | 0 | 0 | 0 | 1 | 0 | 1 |
| **Total** | **30** | **12** | **0** | **0** | **24** | **27** | **93** |

- De las 69 recomendaciones que aplican, 42 están cubiertas y 27 son huecos. Ocho filas son
  parciales: cuatro con estado Código (2.13, 3.8, 3.12, 6.9) y cuatro con estado Hueco (2.1, 3.10,
  4.4, 4.12).
- "Revisión en PR" no es el control principal de ninguna fila: checkov y Conftest refuerzan
  controles que ya están en el código o en una política de organización.
- "Manual" queda en cero porque ningún runbook pide los pasos de Cloud Identity ni de la consola
  (1.1.1, 1.1.2, 1.3, 1.4, 2.2, 2.15): son huecos hasta que se documenten.

## 5. Huecos

La documentación de Google consultada no publica la severidad por categoría (la página de
severidad solo define los niveles); el nivel real se verá en el primer escaneo. La columna
"Severidad" da la de la revisión equivalente de Prowler como referencia, **no la de SCC**. "CM"
dice si el marco CIS v3.0 de Compliance Manager tiene un control para esa recomendación (lista de
49 controles publicada, 23 nov 2026).

| 5.0 | Qué falta | SCC | Severidad (Prowler) | Corrección | Esfuerzo |
|---|---|---|---|---|---|
| 1.1.1, 1.1.2 | Superadministrador con correo de rol y fuera del trabajo diario en GCP | Sin detector; CM no | — | Requisito en el runbook 01 y en el README (Google Cloud): superadministrador con dirección de rol y de respaldo, distinto de la persona que corre la etapa 0. | S |
| 1.3, 1.4 | 2SV obligatoria y llaves de seguridad para administradores | `MFA_NOT_ENFORCED` (detector heredado); CM no | — | Consola de administración de Cloud Identity: forzar 2SV para todos y llaves de seguridad para los grupos `org_admins` y `security_admins`; documentarlo en el runbook 01. | S |
| 1.6 | Cuentas del pipeline con roles `*admin*` y owner de los proyectos que crean | `ADMIN_SERVICE_ACCOUNT`; CM no | alta | No se cierra sin rediseño. Para cumplir: roles personalizados mínimos por etapa en `stages/0-bootstrap/service_accounts.tf` en lugar de los `*Admin` predefinidos, y retirar el `roles/owner` que GCP da al creador (rehace el pendiente 30). Si se acepta el riesgo: ADR que amplíe el 0023 y, si SCC lo reporta, una regla de silencio acotada a `<prefix>-tf-*` (`google_scc_v2_organization_mute_config` en `stages/1-org/main.tf`), que documenta el hallazgo pero no cumple CIS. | L (cumplir) / S (aceptar) |
| 1.17 | Essential Contacts | `ESSENTIAL_CONTACTS_NOT_CONFIGURED`; CM sí | media | `google_essential_contacts_contact` con `parent = "organizations/<org_id>"` y las categorías SECURITY, TECHNICAL, LEGAL y SUSPENSION (las que revisa el detector) hacia grupos de `var.groups`, en `stages/1-org/main.tf`; la cuenta `1-org` necesita `roles/essentialcontacts.admin` en la organización (`stages/0-bootstrap/service_accounts.tf`), otro rol "admin" para 1.6. | S |
| 2.1 | Registros de acceso a datos fuera de prod | `AUDIT_LOGGING_DISABLED`; CM no | media | `google_organization_iam_audit_config` (`allServices`: `ADMIN_READ`, `DATA_READ`, `DATA_WRITE`) en `stages/1-org/main.tf` en lugar de `google_folder_iam_audit_config.prod`, y quitar `checkov:skip=CKV2_GCP_5` de `modules/project-factory/main.tf`. Reabre una decisión de costo. | S (código), M (costo) |
| 2.2 | Datos de Cloud Identity compartidos con Google Cloud | Sin detector; CM no | — | Activarlo en la consola de administración y documentarlo en el runbook 01. | S |
| 2.3 | Sink sin filtro | `LOG_NOT_EXPORTED`; CM no. HYPOTHESIS: el detector pide un filtro presente, así que quizá no lo marque | — | `log_sink_filter = ""` en `module "org"` de `stages/1-org/main.tf`, o un segundo `google_logging_organization_sink` sin filtro hacia un bucket de Logging. Sube volumen y costo. | S |
| 2.4 | Bucket Lock del bucket de logs | `LOCKED_RETENTION_POLICY_NOT_SET`; CM sí | alta | `log_retention_locked = true` en el `terraform.tfvars` real de `stages/1-org` (y como valor por defecto), después de probar el pendiente 15. Irreversible. | S |
| 2.5–2.12 | Ocho métricas de log con alerta | `OWNER_NOT_MONITORED`, `AUDIT_CONFIG_NOT_MONITORED`, `CUSTOM_ROLE_NOT_MONITORED`, `FIREWALL_NOT_MONITORED`, `ROUTE_NOT_MONITORED`, `NETWORK_NOT_MONITORED`, `BUCKET_IAM_NOT_MONITORED`, `SQL_INSTANCE_NOT_MONITORED` (por proyecto); CM no | media | Módulo nuevo (por ejemplo `modules/audit-alerts`): ocho `google_logging_metric` con los filtros de CIS, sus `google_monitoring_alert_policy` y un canal hacia `security_admins`, instanciado en cada proyecto (los detectores revisan proyectos). En 2.8 incluir también los cambios de políticas de firewall: el repositorio no usa reglas de VPC. | M |
| 2.14 | API de Cloud Asset | `CLOUD_ASSET_API_DISABLED`; CM sí | alta | Agregar `cloudasset.googleapis.com` a `local.apis` de `modules/project-factory/main.tf` (cubre semilla, common, spokes y servicio). | S |
| 2.15 | Access Transparency | `ACCESS_TRANSPARENCY_DISABLED`; CM no | — | Activarlo en la consola a nivel organización (requisitos por verificar) y documentarlo en el runbook 01. | S |
| 2.16 | Access Approval | Sin categoría con mapeo CIS 3.0 en la página de SHA; CM no | alta | `google_organization_access_approval_settings` en `stages/1-org/main.tf` con aviso a `security_admins`. HYPOTHESIS: requiere 2.15 antes. | S |
| 3.9 | PSC para las APIs de Google | Sin detector; CM no | — | Endpoint PSC global (`google_compute_global_address` con `purpose = "PRIVATE_SERVICE_CONNECT"` y `google_compute_global_forwarding_rule` con `target = "vpc-sc"`) en `modules/network-hub` y `modules/network-spoke`, con las zonas de `stages/3-networks/envs/*/dns.tf` hacia esa IP; ADR que reemplace al 0026. | M |
| 3.10 | Muestreo de flow logs al 100 % | `VPC_FLOW_LOGS_SETTINGS_NOT_RECOMMENDED` (hay que activar el detector); CM sí | media | `flow_log_sampling = 1` por defecto en `modules/network-hub/variables.tf`, `modules/network-spoke/variables.tf`, `stages/3-networks/envs/*/variables.tf` y sus `terraform.tfvars.example` (el hub y `onprem-sim` usan el valor del módulo). Sube el costo de logs. | S |
| 4.4 | OS Login a nivel proyecto | `OS_LOGIN_DISABLED`; CM no | baja | `"compute.requireOsLogin"` con `enforce = "TRUE"` en `local.policies` de `modules/org/main.tf` (serían diez políticas: actualizar contrato y README), o `google_compute_project_metadata_item` `enable-oslogin` en `modules/project-factory/main.tf`. | S |
| 4.7 | CSEK | `DISK_CSEK_DISABLED`, solo en discos con la marca `enforce_customer_supplied_disk_encryption_keys`; CM no | alta | Registrar en un ADR la desviación (CMEK en lugar de CSEK). HYPOTHESIS: CSEK no sirve en un MIG que recrea discos solo, porque Google no guarda la llave. | S |
| 4.11 | Confidential Computing | `CONFIDENTIAL_COMPUTING_DISABLED` (solo escanea N2D); CM sí | media | `confidential_instance_config { enable_confidential_compute = true }`, tipo N2D y `on_host_maintenance = "TERMINATE"` en `modules/compute-mig/main.tf`; `confidential_nodes { enabled = true }` en `modules/gke/main.tf`. Cambia tipos de máquina y costo. | M |
| 4.12 | Parches de las VM del MIG | Sin detector (VM Manager reporta vulnerabilidades si está activo); CM no | — | VM Manager: `osconfig.googleapis.com` en las APIs, `enable-osconfig = "TRUE"` en `local.metadata` de `modules/compute-mig/main.tf` y `google_os_config_patch_deployment` en `stages/5-workloads/envs/*/compute.tf`. | M |

Parciales con estado Código (no son huecos, pero no cubren todo):

- **2.13**: `google_dns_policy` con `enable_logging = true` para la VPC `onprem-sim` en
  `stages/3-networks/dns.tf` (S). Con `simulate_onprem = true` es probable un
  `DNS_LOGGING_DISABLED` en esa red (HYPOTHESIS).
- **3.8**: forzar el perímetro (`vpc_sc_enforced = true`) después de revisar el dry-run
  (pendientes 4, 5, 17, 18 y 53); dev y qa quedan fuera hasta tener llaves propias (ADR 0019).
- **3.12**: IAP en el servicio de backend volvería privada la aplicación; se deja así por diseño.
- **6.9**: dev y qa sin protección contra borrado por decisión (destroy limpio, pendiente 11).

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
4. **Lo que SCC no prueba**: 22 de los 27 huecos no tienen control en el marco CIS v3.0 de
   Compliance Manager (todos salvo 1.17, 2.4, 2.14, 3.10 y 4.11). "Sin hallazgos críticos ni
   altos" puede cumplirse con esos huecos abiertos. Evidencia aparte:
   - IAM (1.6, 1.9, 1.12): `gcloud organizations get-iam-policy <org>` y
     `gcloud projects get-iam-policy <proyecto>` por proyecto.
   - 2.1: `auditConfigs` en la salida de `gcloud organizations get-iam-policy <org> --format=json`.
   - 2.3: `gcloud logging sinks list --organization=<org>`.
   - 2.5–2.12: `gcloud logging metrics list --project=<proyecto>` y las políticas de alerta de
     Cloud Monitoring de cada proyecto.
   - 4.4: `gcloud compute project-info describe --project=<proyecto>` (metadato `enable-oslogin`).
   - 1.1.1, 1.1.2, 1.3, 1.4, 2.2, 2.15, 2.16: captura de la configuración en la consola.
5. **Pendientes**: no hay un punto de `docs/pendientes-apply.md` para la evaluación CIS; el más
   cercano es el 2, al que remite la fila "Sin hallazgos críticos ni altos en Security Command
   Center" de los criterios de aceptación del README. Relacionados: 15 (bloqueo del bucket de
   logs), 30 (owner implícito), 4, 5, 17 y 18 (perímetro). Propuesta, no aplicada: un punto nuevo
   con este procedimiento.

## 7. Límites de este mapa

- Versión: Prowler nombra la lista "v5.0.0"; CIS publica 5.0.1. La equivalencia con 3.0 se armó
  por títulos de Prowler, no con el PDF de CIS.
- Severidades de SCC no publicadas por categoría; las de Prowler son solo referencia.
- checkov: no se corrió. Los IDs salen del índice público, que puede diferir de checkov 3.4.6 del
  CI. Ese índice lista las revisiones de VM (CKV_GCP_30 a CKV_GCP_40) para
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
