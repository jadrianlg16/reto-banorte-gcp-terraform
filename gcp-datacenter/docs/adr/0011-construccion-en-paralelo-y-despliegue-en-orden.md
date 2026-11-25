# ADR 0011: Construcción en paralelo y sin GCP; despliegue en orden 0 → 3

## Estado

Aceptado, 2026-11-20. Enmendado el 2026-11-24: con el proyecto único
([ADR 0029](0029-un-solo-proyecto.md)) hay cuatro etapas y el orden de despliegue es
0 → 1 → 2 → 3 (`0-bootstrap`, `1-base`, `2-networks` y `3-workloads`). Ya no hace falta una
organización: basta un proyecto con facturación que crea una persona. Los paquetes de trabajo
del rediseño son R0 a R4 (contrato §11). El título decía "0 → 5"; el nombre del archivo se
conserva.

Tipo: Desviación del plan de trabajo de la especificación.

## Contexto

El plan de trabajo de la especificación encadena los sprints: ninguno empieza sin cerrar el
anterior, y cerrar un sprint supone haber desplegado su etapa. El equipo aún no tiene la
organización de GCP (será una propia y se conecta al final), así que esa regla bloquearía todo
el trabajo desde el primer sprint.

## Decisión

Se cambia el orden de construcción, no el de despliegue. Los módulos y las etapas se construyen
en paralelo por paquetes de trabajo (§11; en el rediseño, los bloques R1-a a R1-d) y sin
GCP. "Terminado" sin GCP significa que, para la pieza, pasan `terraform fmt -check -recursive`,
`terraform validate` (con `init -backend=false`), `tflint`, `checkov` y `terraform test` con
`mock_provider` y `command = plan` (§1, regla 2). Las interfaces entre etapas son las salidas de
§7, fijas en el contrato, de modo que una etapa se puede escribir antes de que exista la
anterior. Lo que solo se comprueba con un apply se marca `# VERIFICAR-EN-APPLY` y se lista en
`docs/pendientes-apply.md`. Cuando exista el proyecto, las etapas se aplican en orden
0 → 1 → 2 → 3.

## Alternativas consideradas

- **Esperar a tener la organización.** Rechazada: el calendario no lo permite y el trabajo de
  diseño y pruebas estáticas no depende de GCP.
- **Usar una cuenta de prueba sin organización.** Rechazada en el diseño de varios proyectos: la
  mayoría de las piezas (políticas de organización, carpetas, firewall jerárquico, VPC-SC)
  exigían una organización. Con el ADR 0029 el diseño funciona sin organización, así que un
  proyecto suelto ya sirve para el primer apply (paquete R4); las políticas de organización y el
  perímetro solo se prueban si hay organización.

## Consecuencias

- Positivas: el trabajo avanza; las interfaces quedan fijadas antes de que se escriba el código
  que las consume. Las políticas de Conftest se demuestran con planes de ejemplo (§9.1).
- Negativas: las pruebas con `mock_provider` no detectan errores de la API (formatos de ID,
  permisos, orden de creación, cuotas). El riesgo se concentra en el primer apply, y la lista de
  pendientes es la medida de ese riesgo.
- La auditoría entre etapas (paquete 14, y en el rediseño la integración R2) compensa en parte:
  comprueba que cada salida leída existe aguas arriba con el tipo esperado.
- El cliente debe confirmar que acepta que los sprints se cierren con evidencia estática y que
  la demostración en GCP ocurra al final.
- Primer apply: todos los puntos de [`docs/pendientes-apply.md`](../pendientes-apply.md); en
  particular el tiempo total 0 → 3 frente al objetivo de 90 minutos (punto 10) y el segundo plan
  sin cambios con destroy de dev sin huérfanos (punto 11).
