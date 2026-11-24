# ADR 0017: Nombres cortos para las cuentas de servicio

## Estado

Aceptado, 2026-11-20. Enmendado el 2026-11-24: con el proyecto único
([ADR 0029](0029-un-solo-proyecto.md) §3) las cuentas del pipeline son nueve y se nombran por
raíz y entorno (`<prefix>-tf-base`, `-tf-net`, `-tf-net-<env>`, `-tf-wl-<env>` y `-tf-read`),
todas en el mismo proyecto.

Enmendado otra vez el 2026-11-24, con los arreglos de la revisión de seguridad del código: las
cuentas de ejecución de los entornos ya no las crea `stages/3-workloads/envs/<env>`, sino `1-base`
(`stages/1-base/runtime_accounts.tf`), con la misma forma de nombre. `1-base` crea también la
cuenta `<prefix>-common-net-dns` de la VM DNS opcional de `onprem-sim` (ADR 0006).

Tipo: Desviación menor de la convención de nombres de la especificación.

## Contexto

La convención de nombres de la especificación es `<empresa>-<entorno>-<dominio>-<recurso>`
(§4.2). El ID de una cuenta de servicio de GCP admite de 6 a 30 caracteres (minúsculas, dígitos
y guiones). Con la convención completa, nombres como la cuenta de la etapa de cargas en el
entorno `bootstrap` o la de los nodos de GKE de una aplicación con nombre largo superan los 30
caracteres antes de llegar a la parte que la distingue.

## Decisión

- Cuentas del pipeline (`0-bootstrap`, en el proyecto único): `<prefix>-tf-base` (`1-base`),
  `<prefix>-tf-net` (hub), `<prefix>-tf-net-<env>` (spoke de cada entorno),
  `<prefix>-tf-wl-<env>` (cargas de cada entorno) y `<prefix>-tf-read` (solo lectura). La salida
  `stage_service_accounts` las publica con la raíz como llave (`1-base`, `2-networks`,
  `2-networks/<env>`, `3-workloads/<env>`) y `read_service_account` publica la de lectura; las
  usan §6 del contrato y el ADR 0007.
- Cuentas de ejecución (`1-base`, por cada entorno de `environments` y aplicación de
  `applications`): `<prefix>-<env>-<app>-<uso>`, con `uso` en `gke_nodes`, `workload`, `mig` y
  `run` (los guiones bajos del uso se escriben con guion en el ID), más
  `<prefix>-<env>-<app>-sched` en los entornos de `off_hours_environments` (ADR 0028). Se omite el
  dominio: el entorno y la aplicación ya están en el nombre. La salida
  `runtime_service_accounts` las publica por entorno, aplicación y uso (`scheduler` para la
  cuenta `-sched`), y `3-workloads` las lee de ahí.
- Cuenta de la VM DNS (`1-base`, solo con `onprem_dns_vm` en `0-bootstrap`):
  `<prefix>-common-net-dns`, salida `onprem_dns_service_account`.
- `1-base` valida la longitud de cada ID con una precondición, y `3-workloads` comprueba con una
  postcondición que las cuentas de su entorno y aplicación existan.

## Alternativas consideradas

- **Convención completa truncada a 30 caracteres.** Rechazada: el truncado corta justo la parte
  que distingue a una cuenta de otra y puede producir colisiones.
- **Sufijos aleatorios o códigos hash.** Rechazada: nombres ilegibles en auditoría y en las
  políticas de IAM.
- **Usar `display_name` para la convención completa e ID libre.** Se usa como complemento: el
  `display_name` puede llevar la descripción completa, pero el ID sigue la forma corta.

## Consecuencias

- Positivas: los ID caben y siguen siendo legibles; el prefijo de la empresa se conserva.
- Negativas: el nombre `<app>` queda limitado en longitud. `applications` de `1-base` y
  `application` de `3-workloads` lo fijan en 2 a 8 minúsculas o dígitos, sin guion
  (`^[a-z][a-z0-9]{1,7}$`): con el `<prefix>` más largo (6 caracteres), `prod` y el uso más
  largo, `gke-nodes`, el ID llega justo a 30. La precondición de `1-base` valida además la
  longitud del ID resultante.
- El cliente debe confirmar que acepta la forma corta para cuentas de servicio.
- Primer apply: sin pendiente propio; la longitud se valida en `plan`.
