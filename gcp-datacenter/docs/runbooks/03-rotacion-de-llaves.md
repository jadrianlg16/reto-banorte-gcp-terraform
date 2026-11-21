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

- Inventario de llaves (todas `ENCRYPT_DECRYPT`, rotación `7776000s` = 90 días,
  `prevent_destroy`, módulo `kms`):

  | Etapa | Proyecto | Llavero | Llaves |
  |---|---|---|---|
  | 0 | `<prefix>-bootstrap-seed` | `<prefix>-bootstrap-sec-keyring-<código>` | `<prefix>-bootstrap-sec-state` (bucket de estado) |
  | 1 | `<prefix>-common-logging` | `<prefix>-common-sec-keyring-<código>` | `<prefix>-common-sec-logs` (bucket de logs), `<prefix>-common-sec-pubsub` (tema de SCC) |
  | 2 | `<prefix>-common-security` | `<prefix>-<env>-sec-keyring-{usc1,use4,us}` | `<prefix>-<env>-sec-<uso>`; usos `gke`, `compute`, `sql`, `storage`, `filestore`, `redis`, `secrets`, `backup`, `run` en las regiones; `storage` y `backup` en `us` |

  (`<código>` sale del mapa de códigos cortos: `usc1` para `us-central1`.)
- Identidad con `roles/cloudkms.admin` sobre el proyecto de la llave. En este diseño la tienen
  la cuenta `<prefix>-tf-2-security` (proyecto `security`), la `<prefix>-tf-1-org` (dueña de
  `logging`) y la persona administradora de la etapa 0 (dueña del semilla). El grupo
  `security_admins` solo tiene `roles/cloudkms.viewer`: la operación manual requiere el acceso
  de emergencia, que no está construido ([pendientes](../pendientes-apply.md), §5).
- Variables de la sesión:

  ```bash
  KEY=<nombre-de-la-llave>; KEYRING=<llavero>; LOC=<ubicación>; PROJECT=<proyecto>
  ```

## Pasos

### A. Rotación automática (revisión)

1. Confirmar periodo y próxima rotación:

   ```bash
   gcloud kms keys describe "$KEY" --keyring="$KEYRING" --location="$LOC" --project="$PROJECT" \
     --format="value(rotationPeriod,nextRotationTime,primary.name)"
   ```

   `rotationPeriod` debe ser `7776000s` o menos. El periodo de las llaves de la etapa 2 sale de
   `key_rotation_period` (la validación rechaza más de 90 días y menos de un día; la política
   `kms_rotation` de Conftest también); las de las etapas 0 y 1 usan el valor por defecto del
   módulo. Para cambiarlo: PR a `key_rotation_period` y apply de la etapa 2.

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
| Cloud Storage: estado (`state`), bucket de la aplicación (`storage`) | Los objetos nuevos usan la versión primaria; los existentes conservan la suya. Cada apply escribe un estado nuevo; las `state_versions_to_keep` (20) versiones viejas del estado conservan la versión anterior | Reescribir los objetos: `gcloud storage objects update "gs://<bucket>/**" --encryption-key=<id-de-la-llave>` (pendiente de verificar en buckets con versionado: la generación vieja sigue con la versión vieja hasta que el ciclo de vida la borre) |
| Bucket de logs (`logs`) | Igual que Cloud Storage | Con política de retención, los objetos no se pueden reemplazar hasta vencer: no se re-cifran. La versión vieja queda habilitada al menos `log_retention_days` (365 por defecto) |
| Cloud SQL (`sql`) | Los datos existentes siguen con la versión vieja | Sin re-cifrado automático; revisar la documentación vigente de CMEK de Cloud SQL antes de deshabilitar una versión (pendiente de verificar) |
| Discos de VM del MIG (`compute`) y de nodos de GKE (`compute`, `gke`) | Un disco conserva la versión con que se creó | Recrear: `gcloud compute instance-groups managed rolling-action replace <mig> --region=<región> --project=<proyecto-de-servicio>`; para GKE, recrear o actualizar el pool de nodos |
| Secretos de Kubernetes (`gke`, cifrado de la capa de aplicación) | Siguen con la versión vieja | Reescribirlos: `kubectl get secrets --all-namespaces -o json \| kubectl replace -f -` (pendiente de verificar) |
| Secret Manager (`secrets`) | Cada versión del secreto conserva la versión de llave con que se creó | El equipo dueño agrega una versión nueva con el mismo valor y deshabilita la vieja |
| Memorystore (`redis`), Filestore (`filestore`) | Sin re-cifrado automático (pendiente de verificar) | Recrear la instancia si hay que retirar la versión |
| Backup for GKE y Backup and DR (`backup`) | Los respaldos existentes conservan la versión | Vencen a los 30 días de retención: mantener la versión vieja al menos ese tiempo |
| Cloud Run (`run`), Pub/Sub de SCC (`pubsub`) | Pendiente de verificar | Nueva revisión de Cloud Run; los mensajes de Pub/Sub tienen retención corta |

### C. Versión comprometida

El material de una llave no se puede exportar de Cloud KMS; "comprometida" significa que una
identidad no autorizada pudo usarla.

4. Cortar el acceso primero: quitar el rol de la identidad (PR al IAM de la etapa que lo
   otorgó) y revisar los registros de auditoría de Cloud KMS en el bucket de logs.
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

   Todo dato aún cifrado con ella deja de poder leerse: instancias de Cloud SQL, discos,
   objetos o estados viejos. Si la llave es la del estado (`state`), las versiones viejas del
   estado quedan ilegibles; si es la de logs con retención bloqueada, los logs retenidos
   también.
8. Vigilar errores de descifrado durante un ciclo completo de uso (respaldos, despliegues,
   consultas). Solo entonces, programar la destrucción:

   ```bash
   gcloud kms keys versions destroy <n> --key="$KEY" --keyring="$KEYRING" --location="$LOC" --project="$PROJECT"
   ```

   La destrucción ocurre después de `destroy_scheduled_duration` (`2592000s`, 30 días, por
   defecto en el módulo). La llave misma no se puede destruir desde Terraform
   (`prevent_destroy`): retirarla exige un PR que quite ese bloque, revisado por seguridad.

## Verificación

```bash
gcloud kms keys describe "$KEY" --keyring="$KEYRING" --location="$LOC" --project="$PROJECT" \
  --format="value(primary.name,primary.state)"
gcloud storage objects describe "gs://<bucket>/<objeto>" --format="value(kms_key)"
```

La primaria es la versión nueva y está `ENABLED`; un objeto reescrito muestra la versión nueva
en su llave. `terraform plan -detailed-exitcode` de la etapa dueña de la llave sale con 0.

## Reversión

- Versión deshabilitada por error: `gcloud kms keys versions enable <n> …` (mismos parámetros).
- Destrucción programada por error, dentro de los 30 días:
  `gcloud kms keys versions restore <n> …` y después `enable`.
- Primaria equivocada: `gcloud kms keys set-primary-version "$KEY" --version=<n> --keyring="$KEYRING" --location="$LOC" --project="$PROJECT"`.
