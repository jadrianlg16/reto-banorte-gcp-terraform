# ADR 0019: KMS y Secret Manager fuera de los servicios restringidos del perímetro por defecto

## Estado

Aceptado, 2026-11-21.

Reemplazado por [0029](0029-un-solo-proyecto.md) el 2026-11-24: ya no existe el proyecto
`security` que servía a entornos fuera del perímetro. Con el proyecto único, llaves, secretos y
cargas de los tres entornos están en el mismo proyecto y el perímetro opcional lo rodea entero
(ADR 0009, también reemplazado). Por eso el valor por defecto de `vpc_sc_restricted_services`,
ahora en `stages/1-base/variables.tf`, **sí** incluye `cloudkms.googleapis.com` y
`secretmanager.googleapis.com`, además de `storage.googleapis.com` (que sigue exigido por
validación) y los demás servicios de datos y cómputo. El ADR 0029 no lo dice de forma explícita;
la decisión la tomó el constructor de `1-base` y la registra el contrato (§7.1). Que las cargas
sigan usando KMS y Secret Manager con el perímetro forzado es el punto 4 de
[`docs/pendientes-apply.md`](../pendientes-apply.md) (hoy el perímetro siempre está en
dry-run). El resto del texto describe el diseño de varios proyectos, que vive en la rama
`archivo/multiproyecto`.

Tipo: Aclaración.

## Contexto

La etapa 2 crea en un solo proyecto, `<prefix>-common-security`, los llaveros y llaves de todos
los entornos (`kms_key_ids[entorno][ubicación][uso]`) y los contenedores de secretos de todos
los entornos (`secret_ids[entorno][nombre]`). El mismo proyecto está dentro del perímetro de
VPC-SC de prod (ADR 0009). Un servicio restringido de un perímetro forzado solo acepta llamadas
desde dentro del perímetro o permitidas por reglas de entrada. Si `cloudkms.googleapis.com`
estuviera restringido, los agentes de servicio de dev y qa (Cloud SQL, GKE, Compute, Cloud
Storage), que están fuera del perímetro, no podrían usar sus llaves CMEK del proyecto
`security`; lo mismo con `secretmanager.googleapis.com` para las cargas de dev y qa que leen
sus secretos.

## Decisión

El valor por defecto de `vpc_sc_restricted_services` de la etapa 2 no incluye
`cloudkms.googleapis.com` ni `secretmanager.googleapis.com`. Sí incluye
`storage.googleapis.com`, que el módulo `vpc-sc` exige por validación; los demás servicios de
datos los fija la etapa 2 en esa misma variable. Se restringirán cuando dev y qa tengan su propio proyecto de llaves
y secretos fuera del perímetro de prod.

## Alternativas consideradas

- **Restringir KMS y Secret Manager y abrir reglas de entrada para los agentes de servicio de
  dev y qa.** Rechazada: habría que enumerar en la etapa 2 agentes de proyectos que crea la
  etapa 4, invirtiendo el orden de las etapas, y la lista crecería con cada aplicación.
- **Un proyecto de seguridad por entorno desde ahora.** Es la solución de fondo, pero cambia la
  jerarquía de proyectos (§4.2 y diagramas) y la interfaz `kms_key_ids` de §7.2. Queda como
  evolución.
- **Sacar el proyecto `security` del perímetro.** Rechazada: las llaves de prod quedarían fuera
  del perímetro que protege los datos que cifran.

## Consecuencias

- Positivas: forzar el perímetro no rompe dev ni qa; prod usa CMEK y secretos desde dentro.
- Negativas: la API de KMS y la de Secret Manager del proyecto `security` aceptan llamadas desde
  fuera del perímetro de prod, siempre sujetas a IAM. Un actor con permisos de IAM sobre una
  llave o un secreto de prod podría usarlos desde fuera; el control queda solo en IAM y en los
  registros de auditoría de acceso a datos. El material de las llaves no se puede exportar de
  Cloud KMS, pero los valores de los secretos sí se pueden leer.
- El cliente debe confirmar que acepta este riesgo temporal y fijar cuándo se separan los
  proyectos de llaves de dev y qa.
- Primer apply: uso de las llaves CMEK del proyecto `security` desde prod con el perímetro
  forzado y regla de entrada del pipeline (puntos 4 y 5 de
  [`docs/pendientes-apply.md`](../pendientes-apply.md)); agregar la comprobación inversa, que dev
  y qa sigan usando sus llaves con el perímetro forzado.
