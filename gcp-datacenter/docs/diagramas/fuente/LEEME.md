# Generador de los diagramas

Esta carpeta genera los cinco PNG de [`../img/`](../img/), que usan los documentos de
[`docs/diagramas/`](../). Los diagramas muestran el **diseño** del proyecto único (ADR 0029). Nada
de esto se ha aplicado en GCP.

| Archivo | Qué hace |
|---|---|
| `generar.py` | Un diagrama por función (`d1` a `d5`), con coordenadas absolutas sobre un lienzo de 1920×1080. |
| `motor.py` | Paleta, búsqueda de íconos, plantilla HTML, exportación con Chrome y revisión automática. |

| PNG | Documento que lo usa |
|---|---|
| `01-vista-general.png` | [01-organizacion-gobierno-acceso.md](../01-organizacion-gobierno-acceso.md) |
| `02-red.png` | [02-red-y-conectividad.md](../02-red-y-conectividad.md) |
| `03-aplicacion-y-datos.png` | [03-aplicacion-y-proteccion-de-datos.md](../03-aplicacion-y-proteccion-de-datos.md) |
| `04-seguridad-y-operacion.png` | [04-operacion-continuidad-automatizacion.md](../04-operacion-continuidad-automatizacion.md) |
| `05-pipeline.png` | [05-pipeline.md](../05-pipeline.md) |

## Requisitos

- Python 3.9 o más reciente. Solo usa la biblioteca estándar.
- Chrome, Chromium o Edge. Se busca solo en Windows, macOS y el `PATH`. Si no aparece, define
  `CHROME_PATH` con la ruta del ejecutable. Corre sin cabeza con un perfil temporal y no toca el
  perfil del usuario.
- Los íconos oficiales de Google Cloud. **No se suben al repositorio.**

## Íconos

1. Descarga los zip de íconos desde <https://cloud.google.com/icons> (los de productos principales
   y los de categorías).
2. Descomprímelos en una carpeta fuera del repositorio. No hace falta reorganizarlos: se buscan por
   nombre de archivo en todas las subcarpetas.
3. Indica la carpeta con `--iconos RUTA` o con la variable `GCP_ICONS_DIR`. No hay valor por
   defecto; sin uno de los dos, el generador se detiene y lo dice.

Antes de entregar, confirma en esa misma página que los íconos se pueden usar en diagramas.

## Cómo regenerar

Desde esta carpeta:

```bash
python generar.py --iconos RUTA          # HTML, PNG 1920x1080, PNG @2x, íconos y revisión
python generar.py --iconos RUTA --img    # además copia los PNG 1x a ../img
python generar.py --solo 2 3             # solo esos diagramas (íconos por GCP_ICONS_DIR)
python generar.py --sin-png              # solo HTML y revisión automática
```

- **Salida:** por defecto, la subcarpeta `diagramas-gcp` de la carpeta temporal del sistema. Otra
  con `--salida RUTA` o con la variable `DIAGRAMAS_SALIDA`. Ahí quedan `html/` (autocontenido, con
  los íconos incrustados), `png/` (1x y `@2x` de 3840×2160), `iconos-png/` y `qa.txt`.
- **Al repositorio** solo van los PNG 1x de `../img/`, y solo con `--img`. Los `@2x` y el HTML se
  quedan en la salida.
- **Revisión automática:** cada página trae un script que busca textos que no caben, tarjetas
  encimadas o fuera de su contenedor, flechas que cruzan tarjetas o textos, flechas que se cruzan y
  rótulos encimados. El resultado queda en `qa.txt`. No sustituye mirar los PNG.
- **Última corrida de los cinco:** 0 hallazgos y 14.7 s (n = 1, 24 de noviembre de 2026, Windows,
  `time python generar.py --iconos ...`). Después, el mismo día, se regeneraron solo el 2, el 4 y
  el 5 con la conciliación de R3 (`python generar.py --iconos ... --solo 2 4 5 --img`): 0
  hallazgos en los tres y 4.3 s (n = 1).

**Para cambiar un diagrama:** edita su función en `generar.py`. `caja(...)` dibuja un contenedor,
`tarjeta(...)` una tarjeta, `flecha([...puntos])` una flecha (con `etiqueta`, `punteada` o
`doble`) y `chip(...)` una píldora. Vuelve a generar con `--img`, revisa `qa.txt` y mira cada PNG.

## De dónde sale el contenido

| Diagrama | Fuente en el código |
|---|---|
| 1 | `stages/0-bootstrap`, `stages/1-base`, `stages/2-networks` y los `terraform.tfvars.example` de `stages/3-workloads/envs/<env>` (qué pieza enciende cada entorno) |
| 2 | `stages/2-networks/terraform.tfvars.example` y `stages/2-networks/envs/<env>/terraform.tfvars.example` (rangos y subredes), `stages/2-networks/onprem_dns.tf` (VM DNS de prueba), módulos de VPN, NAT, DNS y firewall |
| 3 | `stages/3-workloads/envs/prod` y los módulos de cómputo y datos |
| 4 | `stages/0-bootstrap` (WIF con `attribute.deploy`, las nueve cuentas, IAM Deny), `stages/1-base` (auditoría, logs, alertas, SCC y cuentas de ejecución de `runtime_accounts.tf`) y el apagado fuera de horario de `3-workloads` |
| 5 | `.github/workflows/pr.yml`, `apply.yml`, `drift.yml` y `destroy.yml` (con `GCP_DISABLED_ENVS`) |

Si cambia alguno de esos archivos, revisa que el diagrama siga diciendo lo mismo.

## Íconos usados

Los oficiales se usan tal cual. Google publica ícono propio solo de los productos principales; los
demás llevan el ícono de su categoría y el nombre del producto en la tarjeta.

| Ícono | Representa a |
|---|---|
| Cloud Run, Cloud SQL, Cloud Storage, Compute Engine, GKE, Security Command Center | El producto del mismo nombre |
| Categoría Networking | VPC, Cloud VPN (HA), Cloud Router, Cloud NAT, Cloud DNS, Cloud Load Balancing, Private Service Access |
| Categoría Security & Identity | Cloud Armor, Cloud KMS, Secret Manager, IAM, Workload Identity Federation, cuentas de servicio, IAM Deny, Binary Authorization, política de firewall de red |
| Categoría Databases | Memorystore |
| Categoría Storage | Filestore, Backup and DR |
| Categoría Developer Tools | Artifact Registry |
| Categoría Observability | Cloud Logging, Cloud Audit Logs, Cloud Monitoring |
| Categoría Integration Services | Cloud Scheduler |
| Categoría Management Tools | Cloud Asset Inventory |
| Dibujados en `motor.py` (sin logotipos) | Usuarios y equipo, repositorio, GitHub Actions y publicadores, on-premises, revisiones, plan, aprobación, correo, incidencia, destroy |

## Paleta

Paleta pastel propia. Contraste WCAG de la etiqueta de cada contenedor sobre su fondo: de 5.8:1 a
10.5:1; etiquetas de flechas sobre blanco: 5.4:1 (calculado el 24 de noviembre de 2026 a partir de
`PALETA` y `AZUL_TEXTO` de `motor.py`).

| Contenedor | Fondo | Borde | Texto de la etiqueta |
|---|---|---|---|
| Google Cloud | `#FFFFFF` | `#9AA0A6` | `#3C4043` |
| Proyecto | `#F1F3F4` | `#C9CDD2` | `#3C4043` |
| Agrupación lógica | `#E4F7FB` | `#93D5E3` | `#00687A` |
| Región | `#E8F0FE` | `#A8C7FA` | `#1859B8` |
| Zona | `#FEF7E0` | `#F2CF63` | `#7A5000` |
| VPC | `#E6F4EA` | `#7CC48F` | `#0F6A2E` |
| Subred | `#F3E8FD` | `#CFA3F7` | `#7B2CBF` |
| Clúster de Kubernetes | `#FCE4EC` | `#F08CB0` | `#A8124A` |
| Grupo de instancias | `#FFEBD9` | `#F6AE6E` | `#954400` |
| Fuera de Google Cloud | `#FFFFFF` | `#BDC1C6` | `#3C4043` |

Flechas `#1A73E8` y sus etiquetas `#1967D2`. Lo opcional o apagado lleva borde punteado gris; lo
que no existe (peering entre spokes), línea gris punteada. Tipografía Arial, para que Windows y
macOS den el mismo resultado sin descargar fuentes.

## Limitaciones y supuestos

- **HYPOTHESIS:** la categoría elegida para cada producto sin ícono propio no se comprobó contra la
  guía de Google.
- **HYPOTHESIS:** las letras de zona (a, b, c) del diagrama 3 son ilustrativas. El código no fija
  zonas: GKE regional y el MIG regional usan las que elige GCP en la región.
- Simplificaciones de dibujo: Cloud Armor aparece antes del balanceador (en realidad es una
  política del servicio de backend); Memorystore, Filestore y Cloud SQL aparecen dentro de la
  región, aunque viven en la red del productor detrás de PSA.
- La protección del estado con etiqueta e IAM Deny es diseño; sin organización, el ADR 0029 la
  marca como HYPOTHESIS.
- No se dibujó: el perímetro de VPC-SC y las políticas de organización (solo existen con
  organización), el balanceador interno de prod para on-premises, las zonas privadas de DNS, el
  presupuesto, la notificación de SCC a Pub/Sub, Infracost y `terratest.yml`.
