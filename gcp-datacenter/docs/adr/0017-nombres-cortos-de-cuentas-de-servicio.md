# ADR 0017: Nombres cortos para las cuentas de servicio

## Estado

Aceptado, 2026-11-20. Enmendado el 2026-11-24: con el proyecto único
([ADR 0029](0029-un-solo-proyecto.md) §3) las cuentas del pipeline son nueve y se nombran por
raíz y entorno (`<prefix>-tf-base`, `-tf-net`, `-tf-net-<env>`, `-tf-wl-<env>` y `-tf-read`);
las cuentas de ejecución las crea `stages/3-workloads/envs/<env>`, todas en el mismo proyecto.

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
- Cuentas de ejecución (`stages/3-workloads/envs/<env>`): `<prefix>-<env>-<app>-<uso>`, con `uso`
  en `gke_nodes`, `workload`, `mig` y `run` (los guiones bajos del uso se escriben con guion en
  el ID), más `<prefix>-<env>-<app>-sched` con el apagado fuera de horario (ADR 0028). Se omite
  el dominio: el entorno y la aplicación ya están en el nombre.
- La raíz de cargas valida la longitud del ID resultante con una precondición.

## Alternativas consideradas

- **Convención completa truncada a 30 caracteres.** Rechazada: el truncado corta justo la parte
  que distingue a una cuenta de otra y puede producir colisiones.
- **Sufijos aleatorios o códigos hash.** Rechazada: nombres ilegibles en auditoría y en las
  políticas de IAM.
- **Usar `display_name` para la convención completa e ID libre.** Se usa como complemento: el
  `display_name` puede llevar la descripción completa, pero el ID sigue la forma corta.

## Consecuencias

- Positivas: los ID caben y siguen siendo legibles; el prefijo de la empresa se conserva.
- Negativas: el nombre `<app>` queda limitado en longitud. `3-workloads` (`application`) lo fija
  en 2 a 8 minúsculas o dígitos, sin guion (`^[a-z][a-z0-9]{1,7}$`): con el `<prefix>` más largo
  (6 caracteres), `prod` y el uso más largo, `gke-nodes`, el ID llega justo a 30. `1-base`
  (`applications`) admite de 1 a 8 (`^[a-z][a-z0-9]{0,7}$`): una aplicación de un carácter tendría
  repositorio pero `3-workloads` la rechazaría. La raíz de cargas valida además la longitud del
  ID resultante.
- El cliente debe confirmar que acepta la forma corta para cuentas de servicio.
- Primer apply: sin pendiente propio; la longitud se valida en `plan`.
