# Plan de la presentación final y del video

**Estado:** propuesta del 24 nov 2026. Falta que el equipo la confirme.

**Pedidos de Banorte (junta del 23 nov 2026):**

- Un video de la ejecución: la terminal y, de ser posible, la consola de Google Cloud.
- Una presentación con más storytelling: de qué va el proyecto, qué resuelve, sus componentes y
  por qué se eligieron.
- Íconos oficiales de Google Cloud, con los productos y servicios en formato de tarjeta y las
  zonas visibles.
- Una lámina con los integrantes en formato de tarjeta de presentación, y el código al final.

**Referencias que mostró el socio** (fotos del 23 nov):

- Un diagrama de arquitectura de ejemplo de Google: tarjetas blancas con el ícono, un título en
  negritas, el producto debajo y, a veces, una nota como "Autoscaling". Las tarjetas se unen con
  flechas azules dentro de un recuadro "Google Cloud", y los usuarios quedan fuera, a la izquierda.
- La lámina de la biblioteca oficial de íconos. Dice que los íconos están en
  <https://cloud.google.com/icons> y que se pueden diseñar diagramas con la herramienta
  <https://googlecloudcheatsheet.withgoogle.com/architecture>.
- La leyenda de colores de zonas: proyecto o proveedor de nube, agrupación lógica de servicios,
  región, zona, subred, firewall, clúster de Kubernetes, pod, grupo de instancias, cuenta, y
  componentes opcionales con línea punteada. Los códigos de color no se leen en la foto; se toman
  del deck oficial de íconos.

Depende del [plan de rediseño a un solo proyecto](plan-rediseno-un-proyecto.md): los diagramas y
el video muestran el diseño nuevo.

## 1. Historia de la presentación (15 a 20 min, por confirmar)

| # | Lámina | Mensaje | Visual |
|---|---|---|---|
| 1 | Portada | Datacenter de Banorte en Google Cloud, 100 % como código | Fondo oscuro, título |
| 2 | El problema | Infraestructura hecha a mano: errores, cambios sin rastro y recuperación lenta | Tres tarjetas de dolor |
| 3 | Qué pidió Banorte | Menos de 90 min desde cero, cero recursos a mano, 99.9 %, CIS | Cuatro cifras grandes |
| 4 | La solución en una frase | Un proyecto, tres entornos aislados y un pipeline que despliega todo | Diagrama simple: GitHub → pipeline → proyecto |
| 5 | Arquitectura: red | Hub-and-spoke: una VPC por entorno, VPN a on-premises, dos regiones | Diagrama con íconos, regiones y zonas |
| 6 | Arquitectura: cómputo y datos | Cloud Run, GKE y MIG; Cloud SQL con réplica; todo por IP privada | Tarjetas de producto sobre las subredes |
| 7 | Arquitectura: seguridad y operación | KMS, Secret Manager, Cloud Armor, logs, alertas, SCC | Tarjetas por capa |
| 8–9 | Por qué estos componentes | Cada tarjeta: producto, para qué, por qué este y qué alternativa se descartó (ADR) | Cuadrícula de 6 tarjetas por lámina |
| 10 | Cómo se despliega | PR, plan, aprobación, apply y prueba de humo; destroy de dev | Flujo con íconos |
| 11 | Demo | Video editado de 4 a 6 min | Video incrustado |
| 12 | Resultados | Tiempo medido, pruebas, costos reales y estado de los criterios | Cifras y tabla corta |
| 13 | Seguridad y CIS | Qué cubre el código, qué es manual y qué se aceptó como desviación | Tarjetas de cifras |
| 14 | Lo que aprendimos y lo que sigue | Tres lecciones y el siguiente paso | Lista corta |
| 15 | El equipo | Una tarjeta de presentación por integrante: nombre, matrícula y rol en el proyecto | Cuatro tarjetas |
| 16 | El código | Árbol del repositorio, un fragmento de módulo y el enlace | Captura y fragmento |
| 17 | Preguntas | — | Fondo oscuro |

**Diagramas.** Se rehacen los cuatro con íconos oficiales y el estilo de la referencia.

- Contenedores de color: el recuadro de Google Cloud, el proyecto, las regiones `us-central1` y
  `us-east4`, las zonas, las VPC y las subredes.
- Dentro van las tarjetas de producto, unidas por flechas.
- Lo opcional, como la DR apagada o el on-premises simulado, va con línea punteada.

## 2. Guion del video (4 a 6 min ya editado)

El despliegue completo puede tardar hasta 90 minutos, así que se graba entero y se edita con
cortes y cámara rápida. Escenas:

| # | Escena | Qué se ve | Duración final |
|---|---|---|---|
| 1 | El repositorio | Árbol de `gcp-datacenter/`, un módulo y `bash scripts/check.sh` en verde | 30 s |
| 2 | Un cambio por PR | PR con el plan en un comentario; un PR que viola una política y queda bloqueado | 45 s |
| 3 | Despliegue | `apply.yml` en GitHub Actions, etapa por etapa (cámara rápida) | 60 s |
| 4 | La consola | VPC y peerings, túneles de VPN arriba, Cloud Run respondiendo, Cloud SQL con IP privada, KMS, logs y alertas | 90 s |
| 5 | Conectividad | La prueba de humo, o una Connectivity Test hacia on-premises | 30 s |
| 6 | Sin cambios | `drift.yml` en verde: el segundo plan no cambia nada | 20 s |
| 7 | Destroy de dev | `destroy.yml` y la búsqueda de huérfanos en verde | 30 s |

**Antes de grabar:**

- OBS Studio a 1920×1080 y 30 fps, terminal con letra de 18 pt o más, navegador al 125 %.
- Voz en una pista aparte o grabada después sobre el video.
- **No mostrar** el ID de la cuenta de facturación, correos personales, tokens, `terraform.tfvars`
  ni el JSON de `GCP_TFVARS_JSON`. Revisar cada cuadro antes de publicar y difuminar lo que haga
  falta.
- Grabar la escena 3 desde el primer `apply.yml` sobre el proyecto vacío; si falla, se graba la
  ejecución que pase.
- Subtítulos en español.

## 3. Íconos y herramientas

| Necesidad | Propuesta |
|---|---|
| Íconos | Los oficiales de <https://cloud.google.com/icons> (SVG y PNG). Descargar el ZIP es un paso que se confirma antes de hacerlo |
| Diagramas | En la misma presentación, con los SVG oficiales, para que todo quede en un archivo editable. Alternativa: la herramienta oficial de diagramas, exportando imágenes |
| Presentación | Generar el `.pptx` con código, como en la Fase 4, y subirlo a Google Slides si el equipo quiere editarlo junto |
| Video | OBS Studio para grabar; Clipchamp o DaVinci Resolve para editar |

Uso de los íconos: la nota al pie de la referencia dice que los íconos de productos se pueden usar
libremente para referirse a la tecnología de Google en diagramas. Hay que confirmarlo en la
página oficial antes de usarlos.

## 4. Reparto y calendario

| Cuándo | Qué | Quién (el equipo lo confirma) |
|---|---|---|
| 25 a 27 nov | Rediseño en código ([plan](plan-rediseno-un-proyecto.md), R1 y R2) | Claude y quien revise |
| 27 nov | Descargar íconos; borrador de diagramas y guion | Claude; el equipo revisa |
| 28 a 29 nov | Despliegue y grabación (escenas 1 a 7) | Quien tenga la cuenta |
| 30 nov | Edición del video y voz | [[integrante]] |
| 30 nov a 1 dic | Presentación con datos reales | Claude genera; el equipo corrige |
| 2 dic | Ensayo con tiempos | Todo el equipo |
| 3 dic | Entrega (confirmar en Canvas) | [[integrante]] |

## 5. Pendiente de decidir

1. Duración de la presentación y del video, y si el video va dentro de la presentación o aparte.
2. Quién narra cada parte y quién edita.
3. Rol de cada integrante para su tarjeta, y si llevan foto.
4. Google Slides o PowerPoint como archivo final.
