# Plan de la presentación final y del video

**Estado:** propuesta del 24 nov 2026, ya con la revisión independiente del mismo día. Falta que
el equipo la confirme.

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
| 4 | La solución en una frase | Un proyecto con tres entornos separados por red, nombres e identidad, y un pipeline que despliega todo | Diagrama simple: GitHub → pipeline → proyecto |
| 5 | Arquitectura: red | Hub-and-spoke: una VPC por entorno, VPN a on-premises, dos regiones | Diagrama con íconos, regiones y zonas |
| 6 | Arquitectura: cómputo y datos | Cloud Run, GKE y MIG; Cloud SQL con réplica; todo por IP privada | Tarjetas de producto sobre las subredes |
| 7 | Arquitectura: seguridad y operación | KMS, Secret Manager, Cloud Armor, logs, alertas, SCC | Tarjetas por capa |
| 8–9 | Por qué estos componentes | Cada tarjeta: producto, para qué, por qué este y qué alternativa se descartó (ADR) | Cuadrícula de 6 tarjetas por lámina |
| 10 | Cómo se despliega | PR, plan, aprobación, apply y prueba de humo; destroy de dev | Flujo con íconos |
| 11 | Demo | Video editado de 4 a 6 min | Video incrustado |
| 12 | Resultados | Lo **medido** (tiempo de despliegue, pruebas, costo del despliegue de prueba) separado de lo **diseñado y sin medir** (99.9 %, RTO y RPO de DR, CIS completo) | Dos columnas: medido / diseñado |
| 13 | Seguridad y CIS | Qué cubre el código, qué es manual y qué se aceptó como desviación | Tarjetas de cifras |
| 14 | Lo que aprendimos y lo que sigue | Tres lecciones y el siguiente paso | Lista corta |
| 15 | El equipo | Una tarjeta de presentación por integrante: nombre, matrícula y rol en el proyecto | Cuatro tarjetas |
| 16 | El código | Árbol del repositorio, un fragmento de módulo y el enlace | Captura y fragmento |
| 17 | Preguntas | — | Fondo oscuro |

**Diagramas.** Hechos el 24 nov 2026: cinco diagramas con íconos oficiales y el estilo de la
referencia, en [`diagramas/img/`](diagramas/img/). Los genera
[`diagramas/fuente/generar.py`](diagramas/fuente/LEEME.md). El mismo día se regeneraron el 2,
el 4 y el 5 para que coincidan con el código final: VM DNS de prueba de `onprem-sim`, cuentas
de ejecución creadas por `1-base`, cuentas que escriben solo desde `main` y
`GCP_DISABLED_ENVS`.

- Contenedores de color: el recuadro de Google Cloud, el proyecto, las regiones `us-central1` y
  `us-east4`, las zonas, las VPC y las subredes.
- Dentro van las tarjetas de producto, unidas por flechas.
- Lo opcional, como la DR apagada o el on-premises simulado, va con línea punteada.

## 2. Guion del video (4 a 6 min ya editado)

El despliegue completo puede tardar hasta 90 minutos, así que se graba entero y se edita con
cortes y cámara rápida. Escenas:

| # | Escena | Qué se ve | Duración final |
|---|---|---|---|
| 0 | La terminal arranca todo | `terraform apply` de `0-bootstrap` en la terminal: el plan recortado y el resultado (bucket de estado, cuentas del pipeline, WIF). `0-bootstrap` se aplica una sola vez, así que esta escena **se graba en la primera ejecución** (R4), no en el ensayo | 40 s |
| 1 | El repositorio | Árbol de `gcp-datacenter/`, un módulo y `bash scripts/check.sh` en verde | 30 s |
| 2 | Un cambio por PR | PR con el plan en un comentario; un PR que viola una política y queda bloqueado | 45 s |
| 3 | Despliegue | `apply.yml` en GitHub Actions, etapa por etapa (cámara rápida) | 60 s |
| 4 | La consola | VPC y peerings, túneles de VPN arriba, Cloud Run respondiendo, Cloud SQL con IP privada, KMS, logs y alertas | 90 s |
| 5 | Conectividad | La prueba de humo, una Connectivity Test hacia on-premises o, con la VM DNS de prueba (`onprem_dns_vm = true`), `dig dns.<dominio>` desde una VM de un spoke | 30 s |
| 6 | Sin cambios | `drift.yml` en verde: el segundo plan no cambia nada | 20 s |
| 7 | Destroy de dev | `destroy.yml` y la búsqueda de huérfanos en verde; antes del siguiente merge, `dev` en `GCP_DISABLED_ENVS` para que `apply.yml` no lo vuelva a crear | 30 s |

**Antes de grabar:**

- OBS Studio a 1920×1080 y 30 fps, terminal con letra de 18 pt o más, navegador al 125 %.
- Voz en una pista aparte o grabada después sobre el video.
- **No mostrar:**
  - el ID de la cuenta de facturación;
  - tokens, `terraform.tfvars` ni el JSON de `GCP_TFVARS_JSON`;
  - el correo de la cuenta: en la barra de la consola, en `gcloud auth list` y en
    `gcloud config list`;
  - los miembros `user:` y `group:`, y la cuenta de facturación en la salida de `terraform plan`
    y en el resumen de GitHub Actions;
  - la página de variables del repositorio;
  - otras pestañas, marcadores y notificaciones del escritorio.

  Para eso se graba con un perfil de navegador limpio y una cuenta dedicada al proyecto. Una
  segunda persona revisa el video cuadro por cuadro antes de entregarlo y difumina lo que haga
  falta.
- **Se graba una ejecución ensayada, no la primera.** La primera ejecución del repositorio es la
  rebanada vertical del [plan de rediseño](plan-rediseno-un-proyecto.md) (R4). Se graba cuando
  ya pasó al menos una vez. La excepción es la escena 0: `0-bootstrap` solo se aplica una vez,
  así que se graba la terminal desde la primera ejecución. Si sale mal, se usa el plan y las
  salidas sin el apply.
- **Plan B si el apply falla el día de la grabación:** usar lo grabado en el ensayo y mostrar el
  plan y las pruebas en la terminal. La lámina de resultados dice qué se midió y qué no.
- Los costos reales tardan en aparecer en Facturación (HYPOTHESIS: hasta un día). La lámina de
  costos usa la estimación y, si llega a tiempo, el costo real del ensayo.
- Subtítulos en español.

## 3. Íconos y herramientas

| Necesidad | Propuesta |
|---|---|
| Íconos | Los oficiales de <https://cloud.google.com/icons>. Descargados el 24 nov 2026, con permiso: `core-products-icons.zip` (19 productos principales: Cloud Run, Cloud SQL, Cloud Storage, Compute Engine, GKE, SCC, …) y `category-icons.zip` (26 categorías: Networking, Security & Identity, Databases, Storage, DevOps, Observability, …). Desde 2025, Google solo publica ícono propio para los productos principales. VPC, VPN, NAT, DNS, Cloud Armor, KMS, Secret Manager, Memorystore, Filestore y Artifact Registry van con el ícono de su categoría y el nombre del producto en la tarjeta. Que eso sea lo que Google recomienda es HYPOTHESIS; su guía en PDF no se descargó. Los íconos se insertan como PNG rasterizados: no se probó que el generador del `.pptx` inserte SVG |
| Diagramas | Los cinco PNG de [`diagramas/img/`](diagramas/img/), que `generar.py` arma con los íconos oficiales rasterizados; para editarlos se cambia `generar.py` y se regeneran. Alternativa: la herramienta oficial de diagramas, exportando imágenes |
| Presentación | Generar el `.pptx` con código, como en la Fase 4, y subirlo a Google Slides si el equipo quiere editarlo junto |
| Video | OBS Studio para grabar; Clipchamp o DaVinci Resolve para editar |

Uso de los íconos: la nota al pie de la referencia dice que los íconos de productos se pueden usar
libremente para referirse a la tecnología de Google en diagramas. Hay que confirmarlo en la
página oficial antes de usarlos.

## 4. Reparto y calendario

| Cuándo | Qué | Quién (el equipo lo confirma) |
|---|---|---|
| 24 nov (hecho) | Rediseño en código ([plan](plan-rediseno-un-proyecto.md), R1 y R2) y documentación y diagramas conciliados con él (R3), todo sin GCP | Claude y constructores |
| Antes de R5 | Guion final y borrador de la presentación | Claude; el equipo revisa |
| Cuando haya proyecto (ideal 27 a 28 nov) | Rebanada vertical real (R4) | Quien tenga la cuenta, con Claude Code |
| 28 a 29 nov | Despliegue mínimo, ensayo y grabación de las escenas 0 a 7 (R5) | Quien tenga la cuenta, más la persona que revisa el video |
| 30 nov | Edición del video y voz | [[integrante]] |
| 30 nov a 1 dic | Presentación con datos reales | Claude genera; el equipo corrige |
| 2 dic | Ensayo con tiempos | Todo el equipo |
| 3 dic | Entrega (confirmar en Canvas) | [[integrante]] |

## 5. Pendiente de decidir

1. Duración de la presentación y del video, y si el video va dentro de la presentación o aparte.
   17 láminas más 4 a 6 min de video en 15 a 20 min queda justo: si el tiempo es de 15 min, se
   juntan las láminas 2 y 3 y las 8 y 9.
2. Quién narra cada parte y quién edita.
3. Rol de cada integrante para su tarjeta, y si llevan foto.
4. Google Slides o PowerPoint como archivo final.
