# ADR 0020: Cloud Run detrás del balanceador sin `allUsers`

## Estado

Aceptado, 2026-11-21.

Tipo: Aclaración.

## Contexto

La especificación pide que los servicios sin estado acepten solo tráfico interno y del
balanceador, con cuenta de servicio propia. El módulo `cloud-run` fija
`ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"` y la verificación de IAM del invocador
activa, así que todo llamador necesita `roles/run.invoker`. Para servir tráfico público por el
balanceador HTTPS externo (ADR 0005) la forma habitual es dar `roles/run.invoker` a `allUsers`,
pero la política `iam.allowedPolicyMemberDomains` del módulo `org` solo admite identidades del
`directory_customer_id` de la organización y rechaza `allUsers`. El balanceador no presenta un
token de identidad propio al invocar el NEG sin servidor.

## Decisión

El módulo `cloud-run` recibe `public_via_load_balancer` (por defecto `false`):

- Con `false`, `invoker_iam_disabled = false`: solo llaman los principales de `invokers`
  (cuentas de servicio, grupos o dominios; nunca `allUsers`, `allAuthenticatedUsers` ni
  `user:`, por validación).
- Con `true`, `invoker_iam_disabled = true`: Cloud Run no comprueba IAM en la invocación. La
  entrada sigue fija en interno y balanceador; el control de acceso público queda en el
  balanceador externo y en Cloud Armor (reglas OWASP y límite de tasa del módulo
  `cloud-armor`).

En ningún caso se concede `allUsers`.

## Alternativas consideradas

- **Excepción de `iam.allowedPolicyMemberDomains` en el proyecto de servicio para permitir
  `allUsers`.** Rechazada: debilita una de las nueve políticas de la línea base, y la excepción
  serviría para cualquier recurso del proyecto, no solo para el servicio.
- **IAP en el servicio de backend, con `roles/run.invoker` al agente de servicio de IAP.**
  Correcta para aplicaciones internas con usuarios de la organización, pero no sirve para
  tráfico público anónimo. Se mantiene como opción con `public_via_load_balancer = false`.
- **Clientes que envían un token de identidad.** Válida para llamadas entre servicios; no para
  navegadores públicos.

## Consecuencias

- Positivas: la política de organización queda intacta y el servicio no es alcanzable desde
  internet por su URL `run.app`, solo por el balanceador.
- Negativas: con `true`, cualquier origen interno que la entrada admita (por ejemplo, una VM de la
  VPC del spoke) puede invocar el servicio sin identidad; Cloud Armor no ve ese
  camino. La autenticación de usuarios, si se necesita, pasa a la aplicación.
- Primer apply: que `invoker_iam_disabled = true` no choque con la política de organización y
  que `run.app` siga sin ser alcanzable desde internet (`VERIFICAR-EN-APPLY` en
  `modules/cloud-run/main.tf`); está registrado en
  [`docs/pendientes-apply.md`](../pendientes-apply.md).
