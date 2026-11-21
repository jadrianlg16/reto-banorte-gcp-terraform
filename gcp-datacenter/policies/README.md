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
| 2 | `shielded_vm.rego` | `google_compute_instance`, `google_compute_instance_template` y `google_compute_region_instance_template` sin `shielded_instance_config` con `enable_secure_boot`, `enable_vtpm` y `enable_integrity_monitoring` en `true` |
| 3 | `required_labels.rego` | Recurso etiquetable sin `env`, `app`, `owner`, `cost_center` o `managed_by`, o con `managed_by` distinto de `terraform` (§4.3) |
| 4 | `compute_public_ip.rego` | Instancia o plantilla con algún `network_interface[*].access_config` o `ipv6_access_config` |
| 5 | `sql_public_ip.rego` | `google_sql_database_instance` sin `settings.ip_configuration.ipv4_enabled = false` o sin `private_network` |
| 6 | `kms_rotation.rego` | `google_kms_crypto_key` de propósito `ENCRYPT_DECRYPT` sin `rotation_period` o con más de 7 776 000 s (90 días) |
| 7 | `iam_user_principal.rego` | Cualquier `google_*_iam_member`, `_binding` o `_policy` (proyecto, carpeta, organización, bucket, cuenta de servicio, KMS, secreto...) con un principal `user:` |

`lib.rego` tiene las funciones comunes (recursos a revisar, valores desconocidos, lectura de
principales de IAM en sus tres formas y formato de mensajes).

### Etiquetas (regla 3)

Solo se exigen en una lista explícita de tipos que admiten etiquetas en el proveedor
`hashicorp/google` 6.x, revisada contra la documentación de la versión v6.50.0: buckets,
instancias, plantillas, discos, imágenes, instantáneas, direcciones y reglas de reenvío de
Compute, clústeres de GKE, Cloud SQL, Memorystore (Redis), Filestore, Cloud Run v2 (servicio y
trabajo), llaves KMS, secretos, proyectos, zonas de Cloud DNS, Pub/Sub y BigQuery. Los tipos
sin etiquetas (redes, subredes, routers, llaveros de KMS, políticas de organización, IAM...)
no se revisan.

Dónde se leen:

- `labels` y `terraform_labels`, unidos. `terraform_labels` suma las `default_labels` del
  bloque `provider` y se conoce en el plan, así que una etiqueta puesta solo ahí cuenta.
- `effective_labels` no se usa: incluye etiquetas puestas fuera de Terraform.
- GKE: `resource_labels` (las `labels` de `node_config` son de Kubernetes y no cuentan).
- Cloud SQL: `settings[0].user_labels` (no recibe `default_labels`).

### Valores desconocidos en el plan

Lo que Terraform calcula en el apply no aparece en `after`, sino marcado en
`change.after_unknown`. Cada regla decide así:

| Regla | Valor desconocido | Decisión |
|---|---|---|
| 1 | `public_access_prevention` (calculado si no se declara) | Rechaza: debe ser una constante |
| 1, 7 | Principal de IAM (por ejemplo, el correo de una cuenta creada en el mismo plan) | No se puede leer; no rechaza. El módulo `iam` rechaza `user:` por validación (§8) |
| 2 | Indicador de Shielded VM o bloque omitido | Rechaza |
| 3 | Valor de una etiqueta cuya llave existe | La llave cuenta como presente |
| 3 | `managed_by` | Rechaza: debe ser "terraform" conocido |
| 4 | Lista `access_config` o `network_interface` | Rechaza: no se puede probar que no haya IP pública |
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
- Los planes de ejemplo de `fixtures/` se escribieron a mano con la forma de
  `terraform show -json`; no salieron de un `terraform plan` real (hace falta GCP).

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
- `fixtures/<regla>_pass.json` y `fixtures/<regla>_fail.json`: dos planes por regla. El de
  `pass` cumple las siete reglas; el de `fail` viola solo su regla. Usan valores de ejemplo
  (`example-project`, `@example.com`, `000000000000`), nunca IDs ni correos reales.

`scripts/policy-check.sh` corre `conftest verify` y luego cada plan de ejemplo: un `_pass` debe
pasar, y un `_fail` debe ser rechazado únicamente por mensajes de su regla. Un `_fail` que pasa,
o que rechaza otra regla, es un error y el script sale con código distinto de cero.

## Cómo demuestra el criterio de aceptación sin GCP

El criterio "el pipeline bloquea un PR que viola una política" se demuestra en dos partes:

1. El paso de políticas del pipeline (`pr.yml`, §9.3) corre `conftest verify`;
   `scripts/policy-check.sh` hace lo mismo y además evalúa los planes de ejemplo, así que
   puede ser el comando de ese paso. Los planes `_fail.json` tienen la misma forma que el JSON que
   produce `terraform show -json`, y Conftest sale con código 1 sobre cada uno: es el mismo
   código con el que fallaría el trabajo de Actions sobre el plan de un PR que viola la regla.
   El script verifica además que cada `_pass.json` sale con código 0, así que la política no
   bloquea configuraciones correctas.
2. Con `GCP_ENABLED = true`, el mismo `conftest test` corre sobre el plan real de cada raíz
   afectada; un plan que viole una regla hace fallar el trabajo y, con la protección de rama
   (§12, pendiente 12), impide el merge.

Lo que no se puede comprobar sin GCP: que los planes reales del proveedor tengan exactamente
la forma de los planes de ejemplo. Se revisa en el primer plan real.
