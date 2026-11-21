# Políticas de Conftest

Políticas en Rego que se evalúan sobre el plan de Terraform en JSON (`terraform show -json`)
y rechazan la configuración que viola las reglas mínimas de §9.1 del contrato
(`docs/CONTRATO.md`). Se escriben en sintaxis Rego v1 (Conftest con OPA 1.x), en el paquete
`main`, con reglas `deny`.

## Qué revisan

Cada política recorre `resource_changes[*]` y mira el estado posterior (`change.after`).
Se omiten las fuentes de datos (`mode = "data"`) y las eliminaciones puras
(`actions = ["delete"]`); un reemplazo sí se revisa. Los recursos sin cambios (`no-op`) también
se revisan: una violación que ya existe en el estado bloquea igual.

Cada mensaje dice la regla entre corchetes y la dirección completa del recurso, con módulo
e índice: `[kms_rotation] module.kms.google_kms_crypto_key.this["sql"]: ...`.

| # | Archivo | Rechaza |
|---|---|---|
| 1 | `bucket_public_access.rego` | `google_storage_bucket` sin `public_access_prevention = "enforced"`; asignaciones de IAM de Cloud Storage (`google_storage_*_iam_member`, `_binding`, `_policy`) o ACL (`*_access_control`, `*_acl`) con `allUsers` o `allAuthenticatedUsers` |
| 2 | `shielded_vm.rego` | `google_compute_instance`, `google_compute_instance_template` y `google_compute_region_instance_template` sin `shielded_instance_config` con `enable_secure_boot`, `enable_vtpm` y `enable_integrity_monitoring` en `true`. Nodos de GKE: `google_container_node_pool` y `google_container_cluster` (su `node_config`, que es el del pool por defecto, y cada `node_pool[i]` en línea) sin `node_config[0].shielded_instance_config` con `enable_secure_boot` y `enable_integrity_monitoring` en `true`; clúster con `enable_shielded_nodes = false`. Un clúster Autopilot no tiene `node_config` y queda fuera de esa parte |
| 3 | `required_labels.rego` | Recurso etiquetable sin `env`, `app`, `owner`, `cost_center` o `managed_by`, o con `managed_by` distinto de `terraform` (§4.3) |
| 4 | `compute_public_ip.rego` | Instancia o plantilla con algún `network_interface[*].access_config` o `ipv6_access_config`, o con esas listas desconocidas en el plan (salvo las excepciones de IPv6 de abajo). `google_container_cluster` sin `private_cluster_config[0].enable_private_nodes = true`; pool (en línea o `google_container_node_pool`) con `network_config[0].enable_private_nodes = false` |
| 5 | `sql_public_ip.rego` | `google_sql_database_instance` sin `settings.ip_configuration.ipv4_enabled = false` o sin `private_network` |
| 6 | `kms_rotation.rego` | `google_kms_crypto_key` de propósito `ENCRYPT_DECRYPT` sin `rotation_period` o con más de 7 776 000 s (90 días) |
| 7 | `iam_user_principal.rego` | Cualquier `google_*_iam_member`, `_binding` o `_policy` (proyecto, carpeta, organización, bucket, cuenta de servicio, KMS, secreto...) con un principal `user:` |

`lib.rego` tiene las funciones comunes (recursos a revisar, valores desconocidos, lectura de
principales de IAM en sus tres formas y formato de mensajes).

### Etiquetas (regla 3)

Solo se exigen en una lista explícita de tipos que admiten etiquetas en el proveedor
`hashicorp/google`, con las rutas revisadas contra `terraform providers schema -json` de la
versión 6.50.0: buckets, instancias, plantillas, discos, imágenes, instantáneas, direcciones y
reglas de reenvío de Compute, gateways HA VPN y externos, túneles VPN, adjuntos de Interconnect,
clústeres y node pools de GKE, Cloud SQL, Memorystore (Redis), Filestore, Cloud Run v2 (servicio
y trabajo), llaves KMS, secretos, proyectos, zonas de Cloud DNS, Pub/Sub, BigQuery, bóvedas de
Backup and DR, planes de Backup for GKE, certificados y autorizaciones DNS de Certificate
Manager, y en Cloud Monitoring las políticas de alerta, servicios, SLO, verificaciones de tiempo
de actividad y canales de notificación. Los tipos sin etiquetas (redes, subredes, routers,
llaveros de KMS, políticas de organización, IAM...) no se revisan. Todos los tipos etiquetables
que aparecen en los módulos y en los planes reales de sus ejemplos están en la lista.

Dónde se leen:

- `labels` y `terraform_labels`, unidos. `terraform_labels` suma las `default_labels` del
  bloque `provider` y se conoce en el plan, así que una etiqueta puesta solo ahí cuenta.
- `effective_labels` no se usa: incluye etiquetas puestas fuera de Terraform.
- GKE: `resource_labels` del clúster; en `google_container_node_pool`,
  `node_config[0].resource_labels` (las `labels` de `node_config` son de Kubernetes y no
  cuentan; ninguna de las dos recibe `default_labels`).
- Cloud SQL: `settings[0].user_labels` (no recibe `default_labels`).
- Cloud Monitoring: `user_labels` (no recibe `default_labels`). En los canales de
  notificación, `labels` es la configuración del canal (por ejemplo, el correo) y no cuenta.

### Valores desconocidos en el plan

Lo que Terraform calcula en el apply no aparece en `after`, sino marcado en
`change.after_unknown`. Cada regla decide así:

| Regla | Valor desconocido | Decisión |
|---|---|---|
| 1 | `public_access_prevention` (calculado si no se declara) | Rechaza: debe ser una constante |
| 1, 7 | Principal de IAM (por ejemplo, el correo de una cuenta creada en el mismo plan) | No se puede leer; no rechaza. El módulo `iam` rechaza `user:` por validación (§8) |
| 2 | Indicador de Shielded VM o bloque omitido (VM, plantillas y nodos de GKE) | Rechaza |
| 3 | Valor de una etiqueta cuya llave existe | La llave cuenta como presente |
| 3 | `managed_by` | Rechaza: debe ser "terraform" conocido |
| 4 | Lista `access_config` o `network_interface` | Rechaza: no se puede probar que no haya IP pública |
| 4 | Lista `ipv6_access_config` | Acepta si el `stack_type` planeado de esa interfaz es `IPV4_ONLY`, o si la interfaz es un bloque escrito en la configuración que no declara `ipv6_access_config` ni `stack_type` y `stack_type` no tiene valor en el plan. Si no, rechaza |
| 4 | `enable_private_nodes` del clúster | Rechaza: debe ser `true` conocido |
| 4 | `enable_private_nodes` de un pool | Acepta: si el pool no lo declara, hereda el valor del clúster |

La excepción de IPv6 existe porque google 6.50.0 deja `ipv6_access_config` desconocido en
`google_compute_region_instance_template` aunque no se declare (en
`google_compute_instance_template` y `google_compute_instance` sale `[]`). Sin ella, la plantilla
conforme del MIG se rechazaba en un plan real. Los dos casos aceptados y uno rechazado
(`stack_type = "IPV4_IPV6"`) son planes de ejemplo recortados de planes reales
(`compute_public_ip_*_real_mig_*.json`). Para saber si la interfaz declara algo, la regla lee
la sección `configuration` del plan siguiendo `module_calls` con los nombres de
`module_address` sin índices.
| 5 | `ipv4_enabled` | Rechaza |
| 5 | `private_network` (VPC creada en el mismo plan) | Acepta |
| 6 | `rotation_period` | Rechaza: debe llegar por variable |

### Limitaciones conocidas

- `google_compute_instance_from_template` y `google_compute_instance_from_machine_image` no se
  revisan en las reglas 2 y 4 (la arquitectura usa plantillas y MIG).
- Regla 5: una instancia solo con Private Service Connect (sin `private_network`) se rechaza;
  el contrato pide IP privada por Private Service Access.
- Regla 7: un `policy_data` que no sea JSON válido no se revisa (Terraform siempre lo genera
  válido con `data "google_iam_policy"`). `deleted:user:...` no se considera `user:`.
- Regla 3: una llave en mayúsculas (`Owner`) no cuenta como `owner`. Si el mapa entero es
  desconocido, el mensaje lista todas las etiquetas como faltantes.
- Regla 4, IPv6: un bloque `dynamic "ipv6_access_config"` no aparece en la sección
  `configuration` del plan. Dentro de una interfaz sin `stack_type`, un `dynamic` sobre un valor
  desconocido produce el mismo plan que una interfaz sin el bloque, y se acepta (comprobado con
  un plan real de una sonda). Declarar `stack_type = "IPV4_ONLY"` cierra ese caso: la plantilla
  del módulo `compute-mig` lo declara.
- Regla 4, GKE: un pool sin `network_config` hereda los nodos privados del clúster; si el
  clúster está en otra raíz, la regla no lo ve.
- Los siete pares `<regla>_pass.json` y `<regla>_fail.json` se escribieron a mano con la forma
  de `terraform show -json`. Los `*_real_*.json` se recortaron de planes reales del proveedor
  google 6.50.0 hechos sin GCP (ver abajo). Ninguno salió del plan de una raíz de etapa: esas
  leen el estado remoto de las anteriores y necesitan GCP.

## Cómo se corre

Requisito: Conftest con OPA 1.x en el PATH, en `$HOME/go/bin` o en la variable `CONFTEST_CMD`.

Desde `gcp-datacenter/`:

```bash
# Pruebas de Rego (*_test.rego)
conftest verify --policy policies

# Un plan contra las políticas
conftest test policies/fixtures/kms_rotation_fail.json --policy policies

# Todo: pruebas de Rego y cada plan de ejemplo con su resultado esperado
scripts/policy-check.sh
```

Con un plan real (cuando exista GCP):

```bash
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json
conftest test tfplan.json --policy policies
```

## Pruebas y planes de ejemplo

- `*_test.rego`: pruebas unitarias por regla, con casos que pasan, que violan y casos
  difíciles (valores desconocidos, eliminaciones, reemplazos, etiquetas solo en
  `terraform_labels`, direcciones dentro de módulos). `helpers_test.rego` arma los planes.
- `fixtures/<regla>_pass.json` y `fixtures/<regla>_fail.json`: dos planes por regla, escritos
  a mano. El de `pass` cumple las siete reglas; el de `fail` viola solo su regla.
- `fixtures/<regla>_pass_real_<caso>.json` y `fixtures/<regla>_fail_real_<caso>.json`:
  recortados de planes reales del proveedor google 6.50.0 (ejemplos de módulo y una sonda con
  recursos sueltos). Cubren la plantilla regional del MIG con y sin `stack_type`, la plantilla
  de doble pila, los nodos públicos y sin arranque seguro de GKE, el ejemplo de GKE completo,
  los tipos de etiquetas agregados (sin etiquetas y con ellas: Backup and DR, Certificate
  Manager, Monitoring, VPN).
- Todos usan valores de ejemplo (`example-project`, `@example.com`, `000000000000`), nunca IDs
  ni correos reales; los valores sensibles de los planes reales salen como `REDACTADO`.

`scripts/policy-check.sh` corre `conftest verify` y luego cada plan de ejemplo: un `_pass` debe
pasar, y un `_fail` debe ser rechazado únicamente por mensajes de su regla. Un `_fail` que pasa,
o que rechaza otra regla, es un error y el script sale con código distinto de cero. Hoy: 83
pruebas de Rego y 25 planes de ejemplo.

### Sacar un plan de ejemplo de un plan real

Sin GCP, desde `gcp-datacenter/` (Terraform y Python 3):

```bash
# 1. Plan real sin llamar a las API: copia el árbol a una carpeta temporal, backend local,
#    GOOGLE_OAUTH_ACCESS_TOKEN=dummy y plan -refresh=false. Sirve para ejemplos de módulo,
#    0-bootstrap o una carpeta propia con recursos sueltos (ruta absoluta); no para raíces que
#    leen el estado remoto de otra etapa.
bash scripts/plan-offline.sh modules/compute-mig/examples/basic /tmp/mig.json

# 2. Recortar a los recursos que interesan (expresiones regulares sobre la dirección
#    completa). Conserva su parte de `configuration` y reemplaza los valores sensibles.
python3 scripts/cut-plan.py /tmp/mig.json 'module\.mig\.google_compute_region_instance_template\.this' \
  > policies/fixtures/compute_public_ip_pass_real_mig_sin_stack_type.json

# 3. Comprobar que da lo esperado.
bash scripts/policy-check.sh
```

## Cómo se demuestra el criterio de aceptación

El criterio "el pipeline bloquea un PR que viola una política" tiene tres partes:

1. Sin GCP: `scripts/policy-check.sh` (trabajo `conftest (pruebas y planes de ejemplo)` de
   `pr.yml`) corre las pruebas de Rego y comprueba que Conftest sale con código 1 sobre cada
   `_fail` y con 0 sobre cada `_pass`. Los `_real_` tienen la forma exacta de un plan del
   proveedor; los escritos a mano, la forma documentada de `terraform show -json`.
2. Con `GCP_ENABLED = true`: el mismo `conftest test` corre sobre el plan real de cada raíz
   afectada en un trabajo `plan <raíz>` de `pr.yml`; un plan que viole una regla hace fallar
   ese trabajo y, con él, el trabajo `plan-gate`.
3. El merge queda bloqueado solo si la protección de `main` exige `plan-gate` y las demás
   comprobaciones (`docs/pipeline.md` §4). Esa protección se configura en GitHub, depende del
   plan de GitHub del repositorio (pendiente 12 del primer apply) y no se ha comprobado.

Después del merge, `apply.yml` vuelve a correr Conftest sobre el plan de cada raíz antes de
pedir aprobación y otra vez sobre el plan que aplica.

Lo que no se puede comprobar sin GCP: el plan de las raíces de etapa (leen el estado remoto) y
de los ejemplos que leen fuentes de datos con la API. Se revisa en el primer plan real.
