# ADR 0009: Perímetro de VPC-SC creado en la etapa 2, ampliado en la 4, en modo dry-run

## Estado

Aceptado, 2026-11-20.

Tipo: Aclaración.

## Contexto

La especificación pide un perímetro de VPC Service Controls para los proyectos de prod que
guardan datos y lo ubica en la etapa de seguridad (2). Los proyectos de servicio de prod los
crea la etapa 4, así que no existen cuando corre la etapa 2. Un perímetro forzado desde el
primer despliegue puede bloquear al propio pipeline (por ejemplo, la cuenta de la etapa 4
llamando a la API de Cloud Storage de un proyecto ya dentro) antes de que las reglas de entrada
estén probadas.

## Decisión

- La etapa 2 usa el módulo `vpc-sc` para crear (o recibir, con `access_policy_id`) la política
  de Access Context Manager y el perímetro regular `<prefix>_prod_sec_perimeter` (sin guiones,
  que los perímetros no admiten), con el proyecto `security` dentro, `restricted_services` con
  al menos `storage.googleapis.com` (validación) y una regla de entrada para las cuentas de
  servicio del pipeline (`ingress_identities`).
- `vpc_sc_enforced = false` por defecto. Con `false` la configuración va en `spec` con
  `use_explicit_dry_run_spec = true` (solo registra violaciones); con `true`, en `status`.
- El perímetro nunca declara `resources` y tiene
  `lifecycle { ignore_changes = [status[0].resources, spec[0].resources] }`. Toda membresía,
  también la del proyecto `security`, entra con recursos separados:
  `google_access_context_manager_service_perimeter_dry_run_resource` en dry-run y
  `google_access_context_manager_service_perimeter_resource` en forzado.
- La etapa 4 de prod lee `perimeter_name` y `vpc_sc_enforced` de la etapa 2 y da de alta sus
  proyectos con el recurso que corresponda.
- Las reglas de entrada siguen el mismo patrón: el perímetro no las declara y tiene también
  `status[0].ingress_policies` y `spec[0].ingress_policies` en `ignore_changes` (lo exige la
  documentación del proveedor de `google_access_context_manager_service_perimeter_ingress_policy`
  y de su variante de dry-run). La regla de las cuentas del pipeline la crea el módulo con
  `..._dry_run_ingress_policy` (dry-run) o `..._ingress_policy` (forzado), con
  `create_before_destroy`, y la etapa 4 agrega las suyas (publicadores de Artifact Registry,
  ADR 0024) sin que el apply de la etapa 2 las quite. Las altas de proyectos del módulo
  dependen de la regla del pipeline: el perímetro nace vacío (no restringe nada), luego entra
  la regla y después los proyectos, así que no hay ventana en que el pipeline quede fuera.
  Las reglas de salida siguen en línea: ninguna otra etapa las agrega.

## Alternativas consideradas

- **Crear el perímetro en la etapa 4.** Rechazada: saca un control de seguridad de la etapa de
  seguridad y de la revisión del equipo de seguridad (`CODEOWNERS`).
- **Lista `resources` en el perímetro, actualizada por la etapa 2 leyendo la 4.** Rechazada:
  invierte el orden de las etapas (la 2 leería a la 4) y la membresía tendría dos dueños.
- **Forzado desde el primer apply.** Rechazada: un error en la regla de entrada bloquearía el
  pipeline sin un modo de observación previo.

## Consecuencias

- Positivas: cada etapa es dueña solo de sus altas y no hay drift cruzado. El paso a forzado
  es un cambio de variable: primero se aplica la etapa 2 y luego la 4, que cambia sus altas de
  un recurso al otro (mientras tanto la etapa 4 muestra el cambio pendiente).
- Negativas: en dry-run el perímetro no protege nada; solo registra. Debe haber una fecha y un
  responsable para forzarlo.
- La documentación de VPC-SC (consultada el 2026-11-21) pide que, con Shared VPC, el proyecto
  host esté en el mismo perímetro que los proyectos de la Shared VPC. Por eso la etapa 4 de
  prod da de alta, además de cada proyecto de servicio, el proyecto host
  `<prefix>-prod-net-spoke` (contrato §7.5).
- Las llaves y secretos de dev y qa viven en el proyecto `security`, dentro del perímetro de
  prod; por eso KMS y Secret Manager no se restringen por defecto (ADR 0019).
- Primer apply: que la API acepte el perímetro en dry-run sin bloque `status`
  (`VERIFICAR-EN-APPLY` en `modules/vpc-sc/main.tf`), la regla de entrada del pipeline y el uso
  de CMEK del proyecto `security` desde prod con el perímetro forzado (puntos 4 y 5 de
  [`docs/pendientes-apply.md`](../pendientes-apply.md)).
