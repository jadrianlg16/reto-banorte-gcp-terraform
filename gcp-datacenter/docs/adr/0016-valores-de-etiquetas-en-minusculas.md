# ADR 0016: Valores de etiquetas en minúsculas

## Estado

Aceptado, 2026-11-20.

Tipo: Desviación menor de la convención de etiquetas de la especificación.

## Contexto

La especificación, en su convención de etiquetas, pide las etiquetas `env`, `app`, `owner`,
`cost_center` y `managed_by`, y su ejemplo de centro de costo usa mayúsculas. Las etiquetas
(labels) de GCP solo admiten en el valor letras minúsculas, dígitos, guion y guion bajo, con un
máximo de 63 caracteres; un valor con mayúsculas hace fallar la creación del recurso.

## Decisión

Los valores van en minúsculas (`ti-001`, no la forma en mayúsculas del ejemplo). Todo módulo que
crea recursos etiquetables copia la validación de §4.3, que exige las cinco llaves, que
`managed_by` sea `terraform` y que cada valor cumpla `^[a-z0-9_-]{0,63}$`. Las raíces arman
`local.labels` agregando `env` y `managed_by`. La política de Conftest de etiquetas (regla 3 de
§9.1) las exige solo en los tipos de recurso que las admiten; los recursos sin etiquetas (por
ejemplo políticas de organización, llaveros de KMS) no las llevan.

## Alternativas consideradas

- **Conservar mayúsculas y convertir con `lower()` dentro de los módulos.** Rechazada: el valor
  guardado no sería el que escribió quien llama, y los reportes de facturación por
  `cost_center` no coincidirían con los sistemas del cliente sin avisar.
- **Usar etiquetas seguras (tags de Resource Manager) para el centro de costo.** Tienen otras
  reglas de formato y requieren llaves y valores creados de antemano en la organización, y la
  especificación pide etiquetas comunes (labels) en cada recurso. Rechazada para este uso.

## Consecuencias

- Positivas: ningún apply falla por formato de etiqueta; el error aparece en `plan` (y en
  `terraform test`) con un mensaje claro.
- Negativas: si los sistemas financieros del cliente usan los códigos en mayúsculas, el cruce
  con la facturación de GCP debe normalizar a minúsculas.
- El cliente debe confirmar que acepta los códigos de centro de costo en minúsculas.
- Primer apply: sin pendiente propio; los valores ya se validan sin GCP.
