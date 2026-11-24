# ADR 0013: Módulos propios escritos con recursos del proveedor

## Estado

Aceptado, 2026-11-20. Enmendado el 2026-11-21: las etiquetas Git de módulo solo disparan las
pruebas de integración de ese módulo; no hay versiones publicadas ni fijadas.

Tipo: Conforme.

## Contexto

La especificación permite escribir los módulos desde cero o envolver módulos públicos; los más
conocidos para GCP son los de Cloud Foundation Toolkit y Cloud Foundation Fabric. El repositorio se construye
y se prueba sin GCP (ADR 0011): las pruebas unitarias son `terraform test` con `mock_provider`
y `command = plan`, y deben comprobar validaciones, nombres (§4.2) y la configuración que la
especificación exige a cada módulo (columna "Exige" de §8).

## Decisión

Los módulos de `modules/` se escriben con recursos de `hashicorp/google` y
`hashicorp/google-beta` directamente, sin bloques `module` que apunten a terceros. Cada módulo
fija como valor o como validación lo que la especificación exige (por ejemplo,
`prevent_destroy` en `kms`, `ipv4_enabled = false` en `cloud-sql`, la denegación por defecto en
`firewall`), entrega `README.md` con terraform-docs, un ejemplo en `examples/basic/` y pruebas
en `tests/`. Las raíces consumen los módulos por ruta relativa (`../../modules/<módulo>`), no
por versión. Una etiqueta Git `modules/<módulo>/vX.Y.Z` solo dispara en `terratest.yml` las
pruebas de integración de ese módulo; a la fecha no hay etiquetas creadas ni versiones
publicadas, y ninguna raíz fija una versión.

## Alternativas consideradas

- **Envolver módulos de Cloud Foundation Toolkit.** Ahorra código, pero cada módulo trae
  submódulos y a veces otros proveedores (`random`, `null`, `external`) y scripts locales, que
  complican `mock_provider`, el archivo de bloqueo multiplataforma y la regla de no depender de
  la máquina. Sus valores por defecto no siempre coinciden con lo que exige la especificación, y
  cerrarlos obliga a envolver cada opción. Rechazada.
- **Cloud Foundation Fabric como base.** Mismo argumento; además su estilo de interfaces
  (objetos grandes) no coincide con las variables comunes que nombra la especificación
  (`subnet_cidrs`, `gke_node_pools`, `sql_tier`).
- **Mezcla: propios para lo crítico, terceros para lo demás.** Rechazada por coherencia de
  pruebas y de revisión.

## Consecuencias

- Positivas: cada recurso queda a la vista del revisor; `terraform test` corre sin descargar
  módulos; las políticas de Conftest ven exactamente lo que el módulo crea.
- Negativas: el equipo mantiene más código y debe seguir los cambios del proveedor por su
  cuenta; los errores que un módulo público ya resolvió (orden de creación, condiciones de
  carrera de la API) pueden aparecer en el primer apply.
- Primer apply: segundo `plan` sin cambios en todas las raíces y `destroy` de dev sin huérfanos
  (punto 11 de [`docs/pendientes-apply.md`](../pendientes-apply.md)), que es donde suelen
  aparecer las diferencias perpetuas de los recursos escritos a mano.
