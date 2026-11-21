# Runbook 05: respuesta a drift

## Objetivo

Resolver una diferencia entre lo que describe Terraform y lo que existe en GCP: decidir si se
revierte el cambio manual o se codifica, importar recursos creados fuera de Terraform y saber
cuándo escalar. Procedimiento diseñado; `drift.yml` todavía no ha corrido contra GCP.

## Cuándo usarlo

- `drift.yml` abrió o actualizó una incidencia `Drift: <raíz>` con la etiqueta `drift`.
- Un `plan` de un PR (`pr.yml`) muestra cambios que el PR no explica.

## Qué reporta `drift.yml`

Corre a diario (12:17 UTC) y a mano, solo con `GCP_ENABLED = true`
([`pipeline.md`](../pipeline.md) §1.2). Por cada raíz de `stages/` salvo `0-bootstrap`:
`terraform plan -detailed-exitcode -lock=false` con la cuenta de la etapa.

- Código 0: sin cambios, nada.
- Código 2: abre `Drift: <raíz>` o, si ya existe abierta, reemplaza su cuerpo y agrega un
  comentario. El cuerpo trae solo las direcciones de los recursos (`# <dirección> will be …`) y
  la línea `Plan:`; nunca valores, porque el repositorio es público.
- Código 1: el trabajo falla. No es drift: es un error de permisos, de estado o de
  configuración, y se trata como falla del pipeline.

La incidencia no se cierra sola. `-lock=false` significa que un apply en curso puede producir
una detección falsa: revisar si `apply.yml` corría a esa hora.

`0-bootstrap` no está cubierta: la persona administradora corre su `plan` a mano (por ejemplo,
cada mes; propuesta).

## Prerrequisitos

- Lectura de la incidencia y de la ejecución de `drift.yml` enlazada.
- Lectura de los registros de auditoría (grupos `auditors` o `security_admins`: tienen
  `logging.privateLogViewer`/`logging.viewer` en la organización y el bucket de logs).
- Para planes locales, una identidad con los permisos de la cuenta de la etapa (las personas no
  leen el estado); si no, todo se hace con PR y el plan de `pr.yml`.
- Variables de la sesión: `R=<raíz>` (por ejemplo `stages/3-networks/envs/prod`), desde
  `gcp-datacenter/`.

## Pasos

1. **Ubicar el cambio.** Tomar de la incidencia la raíz y las direcciones. Con permisos, ver el
   detalle y qué cambió fuera de Terraform:

   ```bash
   terraform -chdir="$R" init -backend-config="bucket=<state_bucket>"
   terraform -chdir="$R" plan -refresh-only      # solo diferencias entre el estado y GCP
   terraform -chdir="$R" plan                    # lo que Terraform haría para volver al código
   ```

2. **Encontrar quién lo hizo.** Registros de actividad administrativa del proyecto (el sink de
   la organización también los copia al bucket `<prefix>-common-ops-audit-logs`):

   ```bash
   gcloud logging read \
     'logName:"cloudaudit.googleapis.com%2Factivity" AND protoPayload.resourceName:"<nombre-del-recurso>"' \
     --project=<proyecto> --freshness=7d \
     --format="table(timestamp,protoPayload.authenticationInfo.principalEmail,protoPayload.methodName)"
   ```

3. **Clasificar y decidir.**

   | Origen del cambio | Decisión |
   |---|---|
   | Persona en la consola o con `gcloud`, sin justificación | Revertir (paso 4) y escalar (paso 7): las personas solo tienen lectura, así que alguien tiene más permisos de los diseñados |
   | Arreglo de emergencia que debe quedarse | Codificar (paso 5) |
   | GCP o el proveedor cambiaron un valor (por ejemplo, actualización automática de versión de GKE, valores por defecto nuevos de la API) | Codificar el valor, o `ignore_changes` en el módulo con el motivo escrito, por PR |
   | Recurso creado a mano que debe administrarse | Importar (paso 6) |
   | Recurso creado a mano que no debe existir | Borrarlo con una identidad con permisos (acceso de emergencia, no construido) tras confirmar con su dueño; Terraform no lo ve |
   | Diferencia que reaparece en cada plan sin cambio externo (diferencia perpetua) | Error del módulo: PR al módulo con prueba en `tests/` (pendiente 11) |

4. **Revertir.** Volver a aplicar el código tal como está en `main`:

   ```bash
   gh workflow run apply.yml --ref main
   ```

   Recorre todas las raíces en orden; solo la raíz con drift aplica cambios. En prod requiere
   la aprobación del entorno `prod`. Revisar en la ejecución que el plan aplicado sea el que
   mostró la incidencia y nada más.

5. **Codificar.** PR que cambie el código o los valores de la raíz (o `GCP_TFVARS_JSON`) para que
   el plan quede sin cambios. El plan de `pr.yml` (con `GCP_ENABLED`) debe decir
   `No changes`; al integrar, `apply.yml` no aplica nada en esa raíz.

6. **Importar.** PR con un bloque `import` (Terraform `>= 1.5`; el repositorio exige 1.9) en la
   raíz, apuntando a la dirección que el recurso tendría en el código:

   ```hcl
   import {
     to = <dirección>          # por ejemplo module.firewall.google_compute_network_firewall_policy_rule.this["<regla>"]
     id = "<id-de-importación>" # formato de la página del recurso en el registro del proveedor
   }
   ```

   El código del recurso tiene que existir en el mismo PR (en un módulo, la entrada de la
   variable que lo crea). El plan debe decir `1 to import, 0 to add, 0 to change, 0 to destroy`.
   Después del apply, otro PR quita el bloque `import`. Para un recurso de la propia raíz (no de
   un módulo), `terraform -chdir="$R" plan -generate-config-out=importado.tf` genera un borrador
   del código que hay que revisar y ajustar a las convenciones (§4 del contrato).

7. **Escalar** de inmediato a `security_admins` (y tratarlo como incidente de seguridad) si el
   drift toca IAM, políticas de organización, firewall, el perímetro de VPC-SC, llaves KMS o
   secretos, o si fue hecho por una identidad que no es una cuenta de etapa. Escalar a
   `platform_devops` si el drift reaparece después de revertirlo o si viene de un cambio de la
   API que obliga a cambiar un módulo. Escalar a la persona administradora si el drift está en
   `0-bootstrap`.

## Verificación

```bash
gh workflow run drift.yml --ref main
```

La ejecución no actualiza la incidencia de esa raíz (plan con código 0). Entonces cerrarla:

```bash
gh issue close <número> --comment "Resuelto: <revertido|codificado en #PR|importado en #PR>."
```

## Reversión

- Si revertir rompió algo (el cambio manual era necesario): codificarlo por PR (paso 5) en
  lugar de rehacerlo a mano.
- Si un PR de codificación o importación causó el problema: `git revert` del PR, nuevo PR y
  `apply.yml`.
- Si un import quedó mal (dirección equivocada): PR con un bloque `removed` (Terraform 1.7 o
  mayor) con `lifecycle { destroy = false }` para sacar el recurso del estado sin borrarlo, y
  repetir el paso 6.
