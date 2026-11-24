# Runbook 05: respuesta a drift

## Objetivo

Resolver una diferencia entre lo que describe Terraform y lo que existe en el proyecto: decidir
si se revierte el cambio manual o se codifica, importar recursos creados fuera de Terraform y
saber cuándo escalar. Procedimiento diseñado; `drift.yml` todavía no ha corrido contra GCP.

## Cuándo usarlo

- `drift.yml` abrió o actualizó una incidencia `Drift: <raíz>` con la etiqueta `drift`.
- El trabajo `recursos no administrados (proyecto)` de `drift.yml` falló con recursos que ningún
  estado describe.
- Un `plan` de un PR (`pr.yml`) muestra cambios que el PR no explica.
- Un trabajo `apply <raíz>` de `apply.yml` falló porque la huella del plan nuevo no coincide con
  la del plan revisado (algo cambió entre el plan y la aprobación).

## Qué reporta `drift.yml`

Corre a diario (12:17 UTC) y a mano, solo con `GCP_ENABLED = true`. Por cada raíz de `stages/`
salvo `0-bootstrap`: `terraform plan -detailed-exitcode -lock=false` con la cuenta de lectura
`<prefix>-tf-read` (`GCP_AUDIT_SERVICE_ACCOUNT`). Esa cuenta no puede escribir el candado, así
que el plan no bloquea ni espera a un apply en curso (ADR 0029 §3).

- Código 0: sin cambios, nada.
- Código 2: abre `Drift: <raíz>` o, si ya existe abierta, reemplaza su cuerpo y agrega un
  comentario. El cuerpo trae solo las direcciones de los recursos (`# <dirección> will be …`) y la
  línea `Plan:`; nunca valores, porque las incidencias las lee cualquiera con acceso al
  repositorio.
- Código 1: el trabajo falla. No es drift: es un error de permisos, de estado o de
  configuración, y se trata como falla del pipeline. Un permiso de lectura que le falte a
  `tf-read` aparece aquí (HYPOTHESIS del ADR 0029 §3: que `roles/viewer` alcance para refrescar
  todo).

La incidencia no se cierra sola. Con `-lock=false`, un apply en curso puede producir una
detección falsa: revisar si `apply.yml` corría a esa hora.

`0-bootstrap` no está cubierta: la persona dueña del proyecto corre su `plan` a mano (por
ejemplo, cada mes; propuesta).

**Recursos no administrados.** Un trabajo aparte lista con Cloud Asset Inventory todo el proyecto
(`gcloud asset search-all-resources --scope=projects/<ID>`) y lo compara con los estados de todas
las raíces (`scripts/unmanaged-resources.py`, con la misma cuenta de lectura). Un recurso creado
a mano no cambia ningún plan: este trabajo es el que lo encuentra. Como todo vive en un proyecto,
es un solo trabajo para los tres entornos; el resumen de la ejecución lista los que sobran y el
trabajo falla. Construido y probado con datos de ejemplo, nunca corrido contra un proyecto real
(punto 49 de los [pendientes](../pendientes-apply.md)).

## Prerrequisitos

- Lectura de la incidencia y de la ejecución de `drift.yml` enlazada.
- Lectura de los registros de auditoría: grupo `auditors` (`logging.privateLogViewer` y lectura
  del bucket de logs) o `security_admins` (`logging.viewer`), de `1-base`.
- Las personas no leen el estado (solo `tf-read` y las cuentas de cada raíz). El detalle del plan
  se ve en un PR con `pr.yml`; un plan local solo lo puede correr la persona dueña del proyecto.
- Variables de la sesión: `R=<raíz>` (por ejemplo `stages/2-networks/envs/prod`), desde
  `gcp-datacenter/`; `<ID>` es el proyecto único.

## Pasos

1. **Ubicar el cambio.** Tomar de la incidencia la raíz y las direcciones. Para ver más, abrir un
   PR de diagnóstico que cambie algo trivial de la raíz (un comentario): `pr.yml` planea las
   raíces afectadas y comenta el resumen. O, si lo corre la persona dueña:

   ```bash
   terraform -chdir="$R" init -backend-config="bucket=<state_bucket>"
   terraform -chdir="$R" plan -refresh-only -lock=false   # solo diferencias entre el estado y GCP
   terraform -chdir="$R" plan -lock=false                 # lo que Terraform haría para volver al código
   ```

2. **Encontrar quién lo hizo.** Registros de actividad administrativa del proyecto (el sink de
   `1-base` también los copia al bucket `<prefix>-common-ops-audit-logs`):

   ```bash
   gcloud logging read \
     'logName:"cloudaudit.googleapis.com%2Factivity" AND protoPayload.resourceName:"<nombre-del-recurso>"' \
     --project=<ID> --freshness=7d \
     --format="table(timestamp,protoPayload.authenticationInfo.principalEmail,protoPayload.methodName)"
   ```

   El nombre del recurso dice de qué entorno es (`<prefix>-<env>-…`, o la etiqueta `env`).

3. **Clasificar y decidir.**

   | Origen del cambio | Decisión |
   |---|---|
   | Persona en la consola o con `gcloud`, sin justificación | Revertir (paso 4) y escalar (paso 7): las personas solo tienen lectura, así que alguien tiene más permisos de los diseñados |
   | Cuenta de un entorno que cambió un recurso de otro (por ejemplo `tf-wl-dev` sobre Cloud SQL de prod) | Revertir y escalar como incidente de seguridad: es el riesgo aceptado del ADR 0029 §9 |
   | Arreglo de emergencia que debe quedarse | Codificar (paso 5) |
   | GCP o el proveedor cambiaron un valor (por ejemplo, actualización automática de versión de GKE, valores por defecto nuevos de la API) | Codificar el valor, o `ignore_changes` en el módulo con el motivo escrito, por PR |
   | Recurso creado a mano que debe administrarse | Importar (paso 6) |
   | Recurso creado a mano que no debe existir | Borrarlo con una identidad con permisos (la persona dueña; el acceso de emergencia no está construido) tras confirmar con su dueño; Terraform no lo ve |
   | Recurso que lista el trabajo de recursos no administrados y que crea Google o un servicio administrado de forma legítima | Agregar una regla a `scripts/unmanaged-allowlist.txt` con su motivo, por PR (nunca un tipo completo sin razón) |
   | Diferencia que reaparece en cada plan sin cambio externo (diferencia perpetua) | Error del módulo: PR al módulo con prueba en `tests/` (pendiente 11) |

4. **Revertir.** Volver a aplicar el código tal como está en `main`:

   ```bash
   gh workflow run apply.yml --ref main
   ```

   Recorre todas las raíces en orden; cada una tiene un trabajo `plan <raíz>` (sin entorno) y,
   solo si hay cambios, un trabajo `apply <raíz>` en su entorno de GitHub. En `common` (`1-base` y
   el hub) y en `prod` el apply espera la aprobación del entorno, si el plan de GitHub permite
   revisores (pendiente 12): quien aprueba revisa en el resumen del trabajo `plan <raíz>` la
   línea `Plan:`, la huella y la lista de recursos, y confirma que coincide con la incidencia y
   nada más. El apply vuelve a planear y solo aplica si la huella es la misma; si no, falla sin
   aplicar nada (alguien cambió algo entre el plan y la aprobación: volver al paso 1).

5. **Codificar.** PR que cambie el código o los valores de la raíz (o `GCP_TFVARS_JSON`) para que
   el plan quede sin cambios. El plan de `pr.yml` (con `GCP_ENABLED`) debe decir `No changes`; al
   integrar, `apply.yml` no aplica nada en esa raíz.

6. **Importar.** PR con un bloque `import` (Terraform 1.5 o mayor; el repositorio exige 1.9) en la
   raíz, apuntando a la dirección que el recurso tendría en el código:

   ```hcl
   import {
     to = <dirección>          # por ejemplo module.firewall.google_compute_network_firewall_policy_rule.this["<regla>"]
     id = "<id-de-importación>" # formato de la página del recurso en el registro del proveedor
   }
   ```

   El código del recurso tiene que existir en el mismo PR (en un módulo, la entrada de la
   variable que lo crea) y su nombre debe llevar `<prefix>-<env>-` (regla de recursos únicos,
   ADR 0029 §4): si el recurso es único por proyecto, se importa en `1-base` o `0-bootstrap`, no
   en una raíz de entorno. El plan debe decir `1 to import, 0 to add, 0 to change, 0 to destroy`.
   Después del apply, otro PR quita el bloque `import`.

7. **Escalar** de inmediato a `security_admins` (y tratarlo como incidente de seguridad) si el
   drift toca IAM, la política de denegación o su etiqueta, firewall, WIF, políticas de
   organización, el perímetro de VPC-SC, llaves KMS o secretos, o si fue hecho por una identidad
   que no es una cuenta del pipeline. Escalar al equipo de plataforma si el drift reaparece
   después de revertirlo o si viene de un cambio de la API que obliga a cambiar un módulo.
   Escalar a la persona dueña del proyecto si el drift está en `0-bootstrap`.

## Verificación

```bash
gh workflow run drift.yml --ref main
```

La ejecución no actualiza la incidencia de esa raíz (plan con código 0) y el trabajo de recursos
no administrados termina en verde. Entonces cerrarla:

```bash
gh issue close <número> --comment "Resuelto: <revertido|codificado en #PR|importado en #PR>."
```

## Reversión

- Si revertir rompió algo (el cambio manual era necesario): codificarlo por PR (paso 5) en lugar
  de rehacerlo a mano.
- Si un PR de codificación o importación causó el problema: `git revert` del PR, nuevo PR y
  `apply.yml`.
- Si un import quedó mal (dirección equivocada): PR con un bloque `removed` (Terraform 1.7 o
  mayor) con `lifecycle { destroy = false }` para sacar el recurso del estado sin borrarlo, y
  repetir el paso 6.

La respuesta anterior, con un trabajo de recursos no administrados por carpeta, está en la rama
`archivo/multiproyecto`.
