# ADR 0025: Plan, aprobación y apply separados, con huella del plan y `plan-gate`

## Estado

Aceptado, 2026-11-21. Completa el ADR 0007.

Tipo: Aclaración.

## Contexto

La especificación pide que ningún cambio llegue a prod sin un plan revisado y una aprobación
manual, que el pipeline bloquee un PR que viola una política y que qa se aplique después de
probar en dev. La revisión independiente encontró que el pipeline no lo garantizaba:

- En `apply.yml`, la aprobación del entorno `prod` ocurría **antes** del plan, así que quien
  aprobaba no veía lo que se aplicaba; `1-org`, `2-security` y el hub corrían en el entorno
  `common` sin reglas; y cada raíz pedía aprobación aunque su plan no tuviera cambios.
- En `pr.yml`, Conftest sobre el plan real corre en trabajos de matriz con nombre dinámico
  (`plan <raíz>`), que no se pueden marcar como comprobación obligatoria, y GitHub cuenta un
  trabajo omitido como aprobado: un PR con una violación en el plan real se podía integrar en
  verde.
- qa solo esperaba a que dev terminara de aplicar, sin ninguna prueba sobre dev.

## Decisión

- **Dos trabajos por raíz** en `_terraform-root.yml`:
  - `plan <raíz>`, sin entorno de GitHub: plan, huella del plan
    (`scripts/plan-fingerprint.py`: SHA-256 de dirección, acciones, `after`, `after_unknown` y
    `after_sensitive` de cada cambio y de las acciones de las salidas; sin el estado anterior ni
    la fecha), Conftest sobre el plan y un resumen en la página de la ejecución con la línea
    `Plan:`, la huella y los recursos con cambios.
  - `apply <raíz>`, en el entorno de la raíz y **solo si el plan tiene cambios** (sin cambios no
    hay pedido de aprobación): vuelve a planear el mismo commit, compara la huella con la
    revisada y, si difiere, falla sin aplicar; si es igual, corre Conftest y aplica ese `tfplan`.
- **Se vuelve a planear en lugar de pasar `tfplan` entre trabajos**: el archivo del plan y su
  JSON llevan valores sensibles en claro y un artefacto de Actions lo descarga cualquiera con
  lectura del repositorio. La huella es un hash, no expone valores, y garantiza que se aplica lo
  que se revisó.
- **`common` también es un entorno protegido**, como `prod` (revisores, "Prevent self-review",
  rama `main`).
- **`plan-gate`** en `pr.yml` (`if: always()`, necesita `raíces afectadas` y `plan <raíz>`): falla
  si alguno terminó en `failure` o `cancelled`, o si con `GCP_ENABLED = true` no corrió lo que
  debía; pasa cuando la omisión es legítima (`GCP_ENABLED` distinto de `true`, o ninguna raíz
  afectada). Es el nombre fijo que se marca como comprobación obligatoria.
- **Prueba de humo de dev** (`dev-smoke`, "dev / prueba de humo"): después de `dev-workloads` y
  antes de `qa-networks`, corre `TestDevSmoke` (`tests/e2e/smoke_test.go`) con
  `GCP_AUDIT_SERVICE_ACCOUNT`. Solo se omite con la entrada manual `omitir_prueba_de_humo`, que
  queda en el resumen con el nombre de quien la pidió.

Detalle de cada paso y de la configuración de GitHub en [`pipeline.md`](../pipeline.md) §1 a §4.

## Alternativas consideradas

- **Pasar `tfplan` como artefacto cifrado.** Rechazada: exige administrar una llave en el
  pipeline para obtener la misma garantía que da la huella.
- **Un solo trabajo con entorno que planea y aplica.** Rechazada: la aprobación ocurre antes del
  plan.
- **Marcar cada `plan <raíz>` como obligatorio.** Imposible: el nombre cambia con el PR.

## Consecuencias

- Positivas: quien aprueba ve el resumen del plan que se aplica; un plan que cambió entre la
  revisión y el apply no se aplica; una violación de política en el plan real bloquea el merge
  **si** `plan-gate` está marcado como comprobación obligatoria de `main`.
- Negativas: cada raíz con cambios en `common` o `prod` pide su propia aprobación (hasta tres por
  entorno); una ejecución que espera aprobación retiene el grupo de concurrencia
  `apply-gcp-datacenter`. Un valor que el proveedor recalcule en cada plan haría fallar el apply
  (nunca aplicaría algo no revisado).
- **Depende de configurar GitHub:** ni `plan-gate` ni las aprobaciones bloquean nada hasta que
  alguien marque las comprobaciones obligatorias en la protección de `main` y cree los entornos
  con revisores. Según la documentación de GitHub (no comprobado aquí), en un repositorio privado
  la protección de rama exige GitHub Pro, Team o Enterprise, y los revisores obligatorios de un
  entorno, GitHub Enterprise; sin ellos, `common` y `prod` se aplican sin aprobación y nada
  bloquea el merge.
- Esta documentación no tiene evidencia de que los flujos corregidos hayan corrido en GitHub, y
  nada ha corrido contra GCP. Comprobado sin GCP el 23 nov 2026: `actionlint
  .github/workflows/*.yml` sale con 0 y `bash scripts/selftest.sh` da 60 OK y 0 FALLA.
- Primer apply: protección de rama, entornos y plan de GitHub (punto 12), estabilidad de la
  huella entre plan y apply (punto 48), cuenta de auditoría y prueba de humo (punto 50) y la
  primera ejecución de `pr.yml` con `plan-gate` (punto 51) de
  [`docs/pendientes-apply.md`](../pendientes-apply.md).
