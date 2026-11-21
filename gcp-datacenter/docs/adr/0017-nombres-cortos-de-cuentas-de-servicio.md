# ADR 0017: Nombres cortos para las cuentas de servicio

## Estado

Aceptado, 2026-11-20.

Tipo: Desviación menor de la convención de nombres de la especificación.

## Contexto

La convención de nombres de la especificación es `<empresa>-<entorno>-<dominio>-<recurso>`
(§4.2). El ID de una cuenta de servicio de GCP admite de 6 a 30 caracteres (minúsculas, dígitos
y guiones). Con la convención completa, nombres como la cuenta de la etapa de cargas en el
entorno `bootstrap` o la de los nodos de GKE de una aplicación con nombre largo superan los 30
caracteres antes de llegar a la parte que la distingue.

## Decisión

- Cuentas del pipeline (etapa 0, en el proyecto semilla): `<prefix>-tf-<etapa>`, por ejemplo
  `<prefix>-tf-1-org` o `<prefix>-tf-5-workloads`. Son las llaves de la salida
  `stage_service_accounts` y las que usan §6.1 y el ADR 0007.
- Cuentas de ejecución (etapa 4, en cada proyecto de servicio): `<prefix>-<env>-<app>-<uso>`,
  con `uso` en `gke_nodes`, `workload`, `mig` y `run` (los guiones bajos del uso se escriben con
  guion en el ID, por verificar en la implementación de la etapa 4). Se omite el dominio porque
  el proyecto ya es el de la aplicación.
- La etapa 4 valida la longitud del ID resultante, igual que `project-factory` valida los 30
  caracteres del ID de proyecto.

## Alternativas consideradas

- **Convención completa truncada a 30 caracteres.** Rechazada: el truncado corta justo la parte
  que distingue a una cuenta de otra y puede producir colisiones.
- **Sufijos aleatorios o códigos hash.** Rechazada: nombres ilegibles en auditoría y en las
  políticas de IAM.
- **Usar `display_name` para la convención completa e ID libre.** Se usa como complemento: el
  `display_name` puede llevar la descripción completa, pero el ID sigue la forma corta.

## Consecuencias

- Positivas: los ID caben y siguen siendo legibles; el prefijo de la empresa se conserva.
- Negativas: el nombre `<app>` queda limitado en longitud (con `<prefix>` de 3 caracteres,
  `prod` y el uso más largo, `gke-nodes`, quedan 11 caracteres para la aplicación); la etapa 4 debe
  documentarlo en `applications`.
- El cliente debe confirmar que acepta la forma corta para cuentas de servicio.
- Primer apply: sin pendiente propio; la longitud se valida en `plan`.
