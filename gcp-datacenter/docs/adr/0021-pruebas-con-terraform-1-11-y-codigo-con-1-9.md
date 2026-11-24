# ADR 0021: Las pruebas de Terraform exigen 1.11 o mayor; el código sigue en 1.9

## Estado

Aceptado, 2026-11-21. Modifica el ADR 0001 solo para los archivos `*.tftest.hcl`.

Enmendado el 2026-11-24: la decisión no cambia con el proyecto único
([ADR 0029](0029-un-solo-proyecto.md)). La evidencia de abajo se tomó con las raíces del diseño
de varios proyectos (etapas 1 a 5) y no se repitió. Al 2026-11-24, contados con la herramienta
de búsqueda del repositorio sobre `*.tftest.hcl` (patrón `override_during`, desde
`gcp-datacenter/`), hay 36 usos en 11 archivos: `modules/audit-alerts`, `modules/firewall`,
`modules/observability`, `stages/0-bootstrap`, `stages/2-networks` (hub y los tres spokes) y las
tres raíces de `stages/3-workloads/envs`. Esas raíces son las que necesitan
`-test-directory=.sin-pruebas` en un `terraform init` a mano con Terraform anterior a 1.11.

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
- Comprobado en local el 2026-11-21 con el binario oficial de Terraform 1.9.8 (windows_amd64,
  suma SHA-256 verificada): `bash scripts/check.sh --skip test,checkov` da PASS en los 61
  objetivos (fmt, validate y tflint). La primera corrida encontró un defecto real y se corrigió:
  1.9 evalúa los dos lados de `||` y `&&`, así que una validación de la forma
  `x == null || contains([...], x)` falla con `x` nulo (`modules/load-balancer`, `modules/vpc-sc`
  y la poscondición de `lb_backend_ports` de la etapa 5 usaban esa forma). Regla que queda: en el
  código `*.tf` no se apoya nada en que `||` o `&&` dejen de evaluar su lado derecho; se usa
  `coalesce`, `try` o el operador condicional.
- Evidencia adicional de la misma fecha: `terraform test` con 1.9.8 pasa en 22 de los 24 módulos
  y en `stages/2-security` y `stages/3-networks` (lo que ejercita sus validaciones con nulos en
  1.9). No pasa en `modules/firewall`, `stages/0-bootstrap` ni las raíces `envs` de las etapas
  3, 4 y 5 (usan `override_during`), ni en `modules/cloud-armor` y `stages/1-org`, cuyas
  aserciones dependen del comportamiento de versiones nuevas. En esas raíces el código solo está
  comprobado en 1.9.8 con `validate`, que no evalúa validaciones de variables sin valor.
- Sin comprobar: la versión mínima real de las pruebas. Solo se corrieron con 1.16.5 (todas
  pasan) y con 1.9.8; "1.11 o mayor" sale de `override_during`, y algunas aserciones además
  dependen de que `&&` no evalúe su lado derecho, que es de una versión posterior. Tampoco hay
  evidencia de `pr.yml` en GitHub: su primera ejecución lo demuestra o lo tumba.
- Primer apply (agregado el 2026-11-23): con Terraform anterior a 1.11, un `terraform init` a
  mano falla en las raíces cuyas pruebas usan `override_during` (`stages/0-bootstrap` y las
  raíces `envs` de las etapas 3, 4 y 5), porque `init` también lee `tests/*.tftest.hcl`.
  Comprobado sin GCP el 2026-11-23 con el binario 1.9.8 sobre una copia de
  `stages/0-bootstrap` (backend local, `terraform.tfvars.example`, token ficticio): `terraform
  init` termina con `Error: Unsupported argument … override_during`; `terraform init
  -test-directory=.sin-pruebas` (un directorio que no existe) termina bien y `terraform plan
  -refresh=false` da "Plan: 71 to add, 0 to change, 0 to destroy". Con 1.10 no se probó
  (HIPÓTESIS: falla igual, `override_during` es de 1.11.0). El pipeline no se ve afectado (usa
  1.16.5). Para quien aplica a mano (etapa 0, runbooks 01 y 04): usar la versión del pipeline
  o agregar `-test-directory=.sin-pruebas` a cada `terraform init`; queda dicho en el README y
  en esos runbooks.
