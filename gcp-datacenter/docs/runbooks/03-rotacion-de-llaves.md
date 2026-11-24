# Runbook 03: rotación de llaves KMS

## Objetivo

Mantener la rotación de las llaves CMEK, rotar a mano cuando haga falta, entender qué datos
quedan cifrados con versiones viejas y deshabilitar una versión comprometida sin perder datos.
Procedimiento diseñado, sin ejecutar en GCP; lo que depende del comportamiento de cada servicio
se marca "pendiente de verificar".

## Cuándo usarlo

- Revisión periódica de que la rotación automática ocurre.
- Rotación manual: cambio de personal con acceso a llaves, sospecha de mal uso, auditoría.
- Una versión de llave pudo usarse por una identidad que no debía.

## Prerrequisitos

- **Inventario.** Todas las llaves son `ENCRYPT_DECRYPT`, rotan cada `7776000s` (90 días) y
  tienen `prevent_destroy` (módulo `kms`). Todas viven en el proyecto único:

  | Raíz | Llavero | Llaves |
  |---|---|---|
  | `0-bootstrap` | `<prefix>-bootstrap-sec-keyring-us` (ubicación de `state_bucket_location`, `us` por defecto) | `<prefix>-bootstrap-sec-state` (bucket de estado) |
  | `1-base`, común | `<prefix>-common-sec-keyring-usc1` (`primary_region`) | `<prefix>-common-sec-logs` (bucket de logs), `<prefix>-common-sec-pubsub` (tema de SCC) |
  | `1-base`, por entorno | `<prefix>-<env>-sec-keyring-usc1` (`primary_region`) | `<prefix>-<env>-sec-<uso>` con los usos `gke`, `compute`, `run`, `sql`, `storage`, `redis`, `filestore` y `secrets` |
  | `1-base`, solo entornos de `dr_environments` (prod por defecto) | `<prefix>-<env>-sec-keyring-use4` (`dr_region`) | `gke`, `compute`, `run`, `sql` (réplica), `backup` (Backup for GKE) y `secrets` (segunda réplica de los secretos) |
  | `1-base`, por entorno | `<prefix>-<env>-sec-keyring-us` | `storage` (bucket de doble región, solo en `dr_environments`) y `artifacts` (repositorios, si `artifact_registry_location` es `us`, el valor por defecto) |

  Solo existen las llaves que alguien usa (`stages/1-base/kms.tf`): no hay `redis`, `filestore`
  ni `storage` en la región de DR, ni `backup` en `us`, y un llavero sin llaves no se crea. Con
  los valores por defecto, dev y qa no tienen llavero en `us-east4`, y su llavero `us` solo trae
  `artifacts`. Los llaveros de entorno existen para cada entorno de `environments` de `1-base`
  (`dev`, `qa` y `prod` por defecto), aunque el entorno no tenga cargas. Un entorno de
  `3-workloads` con `enable_dr` que no esté en `dr_environments` falla en su plan por falta de
  llaves. `3-workloads` lee los IDs de la salida `kms_key_ids` de `1-base`: entorno → `<uso>`
  (región primaria), `<uso>_dr` o `<uso>_us` → ID.

- **Quién puede rotar.** Hace falta `roles/cloudkms.admin` sobre la llave:

  | Identidad | Alcance |
  |---|---|
  | `<prefix>-tf-base` | Todo KMS del proyecto salvo el llavero del estado (condición en `0-bootstrap`). El pipeline no tiene un trabajo de rotación manual |
  | `<prefix>-tf-wl-<env>` | Nada de KMS: no rota llaves ni cambia su IAM. Los permisos de los agentes sobre las llaves los da `1-base` |
  | Grupo `security_admins` | Solo `roles/cloudkms.viewer` |
  | Persona dueña del proyecto (`owner`) | Todo, incluida la llave del estado |

  La operación manual la hace hoy la persona dueña. La política de denegación de `0-bootstrap`
  impide a las nueve cuentas del pipeline cambiar la llave del estado o destruir sus versiones,
  no a las personas. El acceso de emergencia sigue sin construirse
  ([pendientes](../pendientes-apply.md), §5).

- **Variables de la sesión:**

  ```bash
  PROJECT=<ID>; KEY=<nombre-de-la-llave>; KEYRING=<llavero>; LOC=<ubicación>
  gcloud kms keyrings list --location="$LOC" --project="$PROJECT"
  gcloud kms keys list --keyring="$KEYRING" --location="$LOC" --project="$PROJECT"
  ```

## Pasos

### A. Rotación automática (revisión)

1. Confirmar periodo y próxima rotación:

   ```bash
   gcloud kms keys describe "$KEY" --keyring="$KEYRING" --location="$LOC" --project="$PROJECT" \
     --format="value(rotationPeriod,nextRotationTime,primary.name)"
   ```

   `rotationPeriod` debe ser `7776000s` o menos. En `1-base` sale de `key_rotation_period` (la
   validación rechaza más de 90 días y menos de un día; la política `kms_rotation` de Conftest
   también) y vale para las llaves comunes y las de los tres entornos. La llave del estado usa el
   valor por defecto del módulo. Para cambiarlo: PR a `key_rotation_period` y `apply.yml`.

### B. Rotación manual

2. Crear una versión nueva y hacerla primaria:

   ```bash
   gcloud kms keys versions create --key="$KEY" --keyring="$KEYRING" --location="$LOC" \
     --project="$PROJECT" --primary
   ```

   Terraform no administra versiones (solo `rotation_period`), así que esto no debería aparecer
   como drift; pendiente de verificar en el primer `drift.yml` posterior.

3. Decidir si hay que re-cifrar (tabla de abajo). La rotación **no re-cifra nada**: los datos
   escritos antes siguen con la versión con que se cifraron, que debe seguir habilitada.

### Qué se re-cifra y qué no

| Servicio (llave) | Al rotar | Para re-cifrar |
|---|---|---|
| Cloud Storage: estado (`state`), bucket de la aplicación (`storage`) | Los objetos nuevos usan la versión primaria; los existentes conservan la suya. Cada apply escribe un estado nuevo; las versiones viejas del estado (`state_versions_to_keep`, 20) conservan la anterior | Reescribir los objetos: `gcloud storage objects update "gs://<bucket>/**" --encryption-key=<id-de-la-llave>` (pendiente de verificar con versionado: la generación vieja sigue con la versión vieja hasta que el ciclo de vida la borre) |
| Bucket de logs (`logs`) | Igual que Cloud Storage | Con política de retención, los objetos no se reemplazan hasta vencer: no se re-cifran. La versión vieja queda habilitada al menos `log_retention_days` (365 en el ejemplo) |
| Cloud SQL (`sql`) | Los datos existentes siguen con la versión vieja | Sin re-cifrado automático; revisar la documentación vigente de CMEK de Cloud SQL antes de deshabilitar una versión (pendiente de verificar) |
| Discos de VM del MIG (`compute`) y de nodos de GKE (`gke`) | Un disco conserva la versión con que se creó | Recrear: `gcloud compute instance-groups managed rolling-action replace <mig> --region=<región> --project="$PROJECT"`; en GKE, recrear o actualizar el pool de nodos |
| Secretos de Kubernetes (`gke`, cifrado de la capa de aplicación) | Siguen con la versión vieja | Reescribirlos: `kubectl get secrets --all-namespaces -o json \| kubectl replace -f -` (pendiente de verificar) |
| Secret Manager (`secrets`) | Cada versión del secreto conserva la versión de llave con que se creó | Quien carga los valores agrega una versión nueva con el mismo valor y deshabilita la vieja |
| Memorystore (`redis`), Filestore (`filestore`) | Sin re-cifrado automático (pendiente de verificar) | Recrear la instancia si hay que retirar la versión |
| Backup for GKE (`backup`) | Los respaldos existentes conservan la versión | Vencen con su retención: mantener la versión vieja al menos ese tiempo |
| Cloud Run (`run`), Pub/Sub de SCC (`pubsub`) | Pendiente de verificar | Nueva revisión de Cloud Run; los mensajes de Pub/Sub tienen retención corta |
| Artifact Registry (`artifacts`) | Las capas de las imágenes existentes conservan la versión (pendiente de verificar) | Volver a subir las imágenes en uso; mantener la versión vieja mientras haya imágenes desplegadas con ella (un nodo o una revisión que no puede descargar su imagen no arranca) |

Los agentes de servicio son uno por proyecto y cifran con las llaves de los tres entornos (riesgo
aceptado, ADR 0029 §4): deshabilitar una versión de una llave de dev no afecta a prod, porque
cada entorno tiene sus propias llaves, pero quitarle el permiso a un agente sí afecta a todos.

### C. Versión comprometida

El material de una llave no se puede exportar de Cloud KMS; "comprometida" significa que una
identidad no autorizada pudo usarla.

4. Cortar el acceso primero: quitar el rol de la identidad (PR a la raíz que lo otorgó:
   `0-bootstrap` para las cuentas del pipeline; `1-base` para agentes, grupos y cuentas de
   ejecución) y revisar los registros de acceso a datos de Cloud KMS en el bucket de logs
   (ADR 0029 §7 los activa).
5. Identificar las versiones y crear una primaria nueva (paso 2):

   ```bash
   gcloud kms keys versions list --key="$KEY" --keyring="$KEYRING" --location="$LOC" \
     --project="$PROJECT" --format="table(name,state,createTime)"
   ```

6. Re-cifrar con la versión nueva lo que se pueda (tabla anterior).
7. Deshabilitar la versión:

   ```bash
   gcloud kms keys versions disable <n> --key="$KEY" --keyring="$KEYRING" --location="$LOC" --project="$PROJECT"
   ```

   Todo dato aún cifrado con ella deja de poder leerse: instancias de Cloud SQL, discos, objetos
   o estados viejos. Si es la llave del estado, las versiones viejas del estado quedan
   ilegibles; si es la de logs con retención bloqueada, los logs retenidos también.
8. Vigilar errores de descifrado durante un ciclo completo de uso (respaldos, despliegues,
   consultas). Solo entonces, programar la destrucción:

   ```bash
   gcloud kms keys versions destroy <n> --key="$KEY" --keyring="$KEYRING" --location="$LOC" --project="$PROJECT"
   ```

   La destrucción ocurre después de `destroy_scheduled_duration` (`2592000s`, 30 días, valor por
   defecto del módulo). La llave misma no se destruye desde Terraform (`prevent_destroy`), y los
   llaveros no se pueden borrar en GCP.

## Verificación

```bash
gcloud kms keys describe "$KEY" --keyring="$KEYRING" --location="$LOC" --project="$PROJECT" \
  --format="value(primary.name,primary.state)"
gcloud storage objects describe "gs://<bucket>/<objeto>" --format="value(kms_key)"
```

La primaria es la versión nueva y está `ENABLED`; un objeto reescrito muestra la versión nueva en
su llave. `drift.yml` no abre incidencia de la raíz dueña de la llave.

## Reversión

- Versión deshabilitada por error: `gcloud kms keys versions enable <n> …` (mismos parámetros).
- Destrucción programada por error, dentro de los 30 días:
  `gcloud kms keys versions restore <n> …` y después `enable`.
- Primaria equivocada:
  `gcloud kms keys set-primary-version "$KEY" --version=<n> --keyring="$KEYRING" --location="$LOC" --project="$PROJECT"`.

El inventario anterior, con llaves repartidas en varios proyectos, está en la rama
`archivo/multiproyecto`.
