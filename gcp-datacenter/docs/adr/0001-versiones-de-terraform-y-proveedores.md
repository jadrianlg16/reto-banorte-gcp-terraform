# ADR 0001: Versiones de Terraform y de los proveedores de Google

## Estado

Aceptado, 2026-11-20. Enmendado el 2026-11-21: las pruebas (`*.tftest.hcl`) exigen
Terraform 1.11 o mayor (ADR [0021](0021-pruebas-con-terraform-1-11-y-codigo-con-1-9.md)); el
código sigue en `>= 1.9`.

Tipo: Conforme.

## Contexto

La especificación, en su sección de convenciones de Terraform, fija la restricción de versión
de los proveedores `hashicorp/google` y `hashicorp/google-beta` y la versión mínima de
Terraform. El registro público ya publica una versión mayor del proveedor que la que pide la
especificación. Todas las raíces de `stages/` y todos los módulos de `modules/` deben declarar
lo mismo para que un solo `.terraform.lock.hcl` por raíz sea reproducible en Windows, macOS y
Linux (CI).

## Decisión

Todo `versions.tf` declara `required_version = ">= 1.9"` y los proveedores `google` y
`google-beta` con `version = "~> 6.0"` (§4.1 del contrato). Los módulos declaran solo los
proveedores que usan y no contienen bloques `provider`. Las raíces versionan el archivo de
bloqueo generado con `terraform providers lock` para `windows_amd64`, `linux_amd64` y
`darwin_arm64`. El código de módulos y raíces (`*.tf`) no usa funciones ni atributos que
exijan Terraform posterior a 1.9. Las pruebas sí pueden: usan `override_during = plan`, que
apareció en 1.11, y para correr `terraform test` hace falta 1.11 o mayor (ADR 0021). `pr.yml`
comprueba el código con 1.9.8 sin `terraform test` y todo con 1.16.5.

La actualización a una versión mayor del proveedor se hace por PR cuando el cliente lo pida.

## Alternativas consideradas

- **Usar la versión mayor vigente del proveedor.** Rechazada: contradice una convención
  obligatoria de la especificación, y una versión mayor puede traer cambios incompatibles
  (argumentos retirados o valores por defecto distintos) que obligarían a revisar los 24 módulos sin poder probar contra GCP.
- **Restricción abierta (`>= 6.0`).** Rechazada: un `terraform init -upgrade` podría saltar a
  la versión mayor siguiente sin revisión, y el archivo de bloqueo dejaría de ser la única
  fuente de la versión efectiva.
- **Exigir Terraform >= 1.11 para usar atributos de solo escritura.** Rechazada por ahora: la
  especificación pide 1.9 como mínimo, y el equipo no puede asumir una versión mayor en las
  máquinas del cliente.

## Consecuencias

- Positivas: versiones de proveedor idénticas en todas las raíces y en CI.
- Las pruebas con `mock_provider` y `command = plan` necesitan Terraform 1.11 o mayor
  (ADR 0021): con 1.9 solo se puede correr `bash scripts/check.sh --skip test`. El repositorio
  no es compatible con 1.9 para correr las pruebas.
- Negativas: sin atributos de solo escritura, los valores sensibles que Terraform tenga que
  pasar a un recurso quedan en el estado. Esto afecta al secreto compartido de la VPN
  (ADR 0006) y es la razón de fondo del ADR 0015 y de que AUTH de Memorystore quede apagado.
  Las funciones del proveedor que solo existen en 7.x no están disponibles: si un recurso no
  existe en 6.x, se reporta en lugar de inventarlo (§8 del contrato).
- Revisión futura: al subir de versión mayor, revisar en particular los recursos de VPC-SC,
  Cloud Run v2 (`invoker_iam_disabled`) y Backup and DR, que cambian con frecuencia entre
  versiones (por verificar en las notas de versión del proveedor).
- Primer apply: nada específico de este ADR; el segundo `plan` sin cambios (punto 11 de
  [`docs/pendientes-apply.md`](../pendientes-apply.md)) confirma que la versión bloqueada no
  produce diferencias perpetuas.
