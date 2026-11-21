# ADR 0021: Las pruebas de Terraform exigen 1.11 o mayor; el código sigue en 1.9

## Estado

Aceptado, 2026-11-21. Modifica el ADR 0001 solo para los archivos `*.tftest.hcl`.

Tipo: Aclaración.

## Contexto

El ADR 0001 fija `required_version = ">= 1.9"` (convención de la especificación) y decía que no
se usan funciones ni atributos posteriores a 1.9. La revisión independiente encontró que eso no
se cumplía en las pruebas: varias usan `override_during = plan` en `override_resource`,
`override_data` y `mock_provider`, un atributo que apareció en Terraform 1.11.0. Terraform 1.9.8
rechaza esos archivos como argumento no admitido, y además `terraform init` y
`terraform validate` leen `tests/*.tftest.hcl` aunque no se corra `terraform test`.

`override_during = plan` es lo que permite que una prueba con `command = plan` compare atributos
que el proveedor solo conoce después del apply (por ejemplo, IDs de valores de etiqueta, grupos
de instancias o el pool de Workload Identity) contra valores fijos. Sin él, esas pruebas solo
podrían comparar salidas que copian `locals`, que es justo lo que la revisión marcó como prueba
débil. Al 2026-11-21 hay 54 usos en 11 archivos de prueba
(`grep -rn "override_during" --include=*.tftest.hcl . | wc -l` desde `gcp-datacenter/`):
`modules/firewall`, `stages/0-bootstrap` y las raíces de `envs/{dev,qa,prod}` de las etapas 3, 4
y 5.

## Decisión

- El código de módulos y raíces (`*.tf`) sigue declarando `required_version = ">= 1.9"` y no usa
  nada posterior a 1.9: es lo que la especificación exige a quien aplica.
- Las pruebas (`*.tftest.hcl`) pueden exigir Terraform 1.11 o mayor. Para correrlas hace falta
  esa versión; el equipo usa 1.16.5.
- `pr.yml` comprueba las dos cosas por separado: el trabajo `estático (terraform 1.9.8)` corre
  `scripts/check.sh --skip test` (fmt, validate, tflint y checkov; con `--skip test`, `init` usa
  un `-test-directory` inexistente y `validate` corre con `-no-tests`, así que 1.9.8 no lee las
  pruebas), y `estático (terraform 1.16.5)` corre `scripts/check.sh` completo, con
  `terraform test` ([`pipeline.md`](../pipeline.md) §1.1).

## Alternativas consideradas

- **Reescribir las pruebas sin `override_during`.** Rechazada: las aserciones volverían a
  comparar salidas armadas con `locals` en lugar de los recursos planeados, y varias pruebas que
  hoy fallan sin su corrección dejarían de hacerlo.
- **Subir `required_version` a `>= 1.11` en todo el código.** Rechazada: contradice la
  convención de la especificación para algo que solo necesitan las pruebas.
- **Dejar la pata 1.9.8 corriendo `terraform test`.** Rechazada: fallaría siempre, y si se marca
  como comprobación obligatoria ningún PR se podría integrar.

## Consecuencias

- Positivas: las pruebas comparan recursos y no copias de `locals`; la compatibilidad del código
  con 1.9 sigue comprobada en cada PR.
- Negativas: quien corra `terraform test` en su máquina necesita 1.11 o mayor; con 1.9 solo puede
  correr `bash scripts/check.sh --skip test`. El repositorio **no** es compatible con Terraform
  1.9 para correr las pruebas.
- Sin comprobar: la pata 1.9.8 nunca corrió (no hay binario 1.9.8 en la máquina de construcción);
  que `init -test-directory` y `validate -no-tests` existan en 1.9.8 se confirmó en su código
  fuente, no ejecutándolo. La primera ejecución de `pr.yml` en GitHub lo demuestra o lo tumba.
- Primer apply: nada específico.
