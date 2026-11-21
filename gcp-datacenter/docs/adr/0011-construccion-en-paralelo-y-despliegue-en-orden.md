# ADR 0011: Construcción en paralelo y sin GCP; despliegue en orden 0 → 5

## Estado

Aceptado, 2026-11-20.

Tipo: Desviación del plan de trabajo de la especificación.

## Contexto

El plan de trabajo de la especificación encadena los sprints: ninguno empieza sin cerrar el
anterior, y cerrar un sprint supone haber desplegado su etapa. El equipo aún no tiene la
organización de GCP (será una propia y se conecta al final), así que esa regla bloquearía todo
el trabajo desde el primer sprint.

## Decisión

Se cambia el orden de construcción, no el de despliegue. Los módulos y las etapas se construyen
en paralelo por paquetes de trabajo (§11; los paquetes 1 a 6 y el 10 son independientes) y sin
GCP. "Terminado" sin GCP significa que, para la pieza, pasan `terraform fmt -check -recursive`,
`terraform validate` (con `init -backend=false`), `tflint`, `checkov` y `terraform test` con
`mock_provider` y `command = plan` (§1, regla 2). Las interfaces entre etapas son las salidas de
§7, fijas en el contrato, de modo que una etapa se puede escribir antes de que exista la
anterior. Lo que solo se comprueba con un apply se marca `# VERIFICAR-EN-APPLY` y se lista en
`docs/pendientes-apply.md`. Cuando exista la organización, las etapas se aplican en orden 0 → 5.

## Alternativas consideradas

- **Esperar a tener la organización.** Rechazada: el calendario no lo permite y el trabajo de
  diseño y pruebas estáticas no depende de GCP.
- **Usar una cuenta de prueba sin organización.** Rechazada: la mayoría de las piezas (políticas
  de organización, carpetas, firewall jerárquico, VPC-SC) exigen una organización, y probar sin
  ellas daría una falsa sensación de verificación.

## Consecuencias

- Positivas: el trabajo avanza; las interfaces quedan fijadas antes de que se escriba el código
  que las consume. Las políticas de Conftest se demuestran con planes de ejemplo (§9.1).
- Negativas: las pruebas con `mock_provider` no detectan errores de la API (formatos de ID,
  permisos, orden de creación, cuotas). El riesgo se concentra en el primer apply, y la lista de
  pendientes es la medida de ese riesgo.
- La auditoría entre etapas (paquete 14) compensa en parte: comprueba que cada salida leída
  existe aguas arriba con el tipo esperado.
- El cliente debe confirmar que acepta que los sprints se cierren con evidencia estática y que
  la demostración en GCP ocurra al final.
- Primer apply: todos los puntos de [`docs/pendientes-apply.md`](../pendientes-apply.md); en
  particular el tiempo total 0 → 5 frente al objetivo de 90 minutos (punto 10) y el segundo plan
  sin cambios con destroy de dev sin huérfanos (punto 11).
