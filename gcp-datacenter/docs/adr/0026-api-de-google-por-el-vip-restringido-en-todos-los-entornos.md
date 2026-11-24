# ADR 0026: API de Google por el VIP restringido en todos los entornos

## Estado

Aceptado, 2026-11-21. Enmendado el 2026-11-24: con el proyecto único
([ADR 0029](0029-un-solo-proyecto.md)) los spokes están en `stages/2-networks/envs/<env>` y el
perímetro de VPC-SC es opcional (solo con organización), rodea todo el proyecto y queda en
dry-run. Se mantiene `restricted` por defecto en los tres entornos; sin perímetro, la razón que
queda es que el mismo VIP en todos los entornos hace fallar en dev lo que fallaría en prod si se
activa el perímetro.

Tipo: Aclaración.

## Contexto

Cada spoke (`stages/2-networks/envs/<env>`; antes `stages/3-networks/envs/<env>`) tenía una
zona privada de `googleapis.com` hacia el VIP restringido (`199.36.153.4/30`) y su ruta. La revisión independiente señaló dos huecos:
`gcr.io`, `pkg.dev` y `run.app` resolvían a IP públicas de Google y salían por la ruta de
internet sin pasar por el VIP (inconsistente con el perímetro de prod, ADR 0009), y el VIP
restringido se usaba también en dev y qa, que no están dentro de ningún perímetro. La guía de
Private Google Access de Google recomienda el VIP `private` (`199.36.153.8/30`) cuando no se
usa VPC Service Controls, y la página de VPC Service Controls de Cloud Run pide resolver
`*.run.app` hacia `restricted.googleapis.com`.

## Decisión

- Variable `google_apis_vip` en las raíces de spoke (`restricted` o `private`, por defecto
  `restricted`); los tres `terraform.tfvars.example` usan `restricted`.
- Zonas privadas `googleapis.com.`, `gcr.io.`, `pkg.dev.` y `run.app.` en cada spoke: registro A
  hacia las cuatro IP del VIP elegido y comodín CNAME (en `googleapis.com.`, hacia
  `<vip>.googleapis.com.`; en las otras, hacia el propio dominio). `dns_zone_names` publica las
  llaves `gcr`, `pkg` y `run`.
- La ruta al VIP restringido la crea `network-spoke`; el VIP privado lo cubre la ruta
  `0.0.0.0/0` del spoke.
- Se mantiene `restricted` en dev y qa: con organización el proyecto puede tener el perímetro
  opcional (ADR 0029 §1), y con el mismo VIP en todos los entornos una aplicación que dependa de
  una API no admitida por VPC-SC falla en dev y no por primera vez en prod.

## Alternativas consideradas

- **`private` en dev y qa, `restricted` en prod.** Es lo que recomienda Google sin VPC-SC; la
  variable lo permite, pero se rechaza como valor por defecto por la razón anterior.
- **Solo `googleapis.com` (diseño anterior).** Rechazada: las imágenes y las llamadas a Cloud
  Run no pasaban por el VIP.

## Consecuencias

- Positivas: Artifact Registry, Container Registry y Cloud Run se alcanzan por el VIP
  restringido, dentro del perímetro cuando existe.
- Negativas: en dev y qa, una API que VPC-SC no admite tampoco se alcanza por el VIP restringido
  (por verificar si alguna carga la usa); se resuelve con `google_apis_vip = "private"` en ese
  entorno.
- Primer apply: un nodo de GKE descarga imágenes de `pkg.dev` y una llamada a `*.run.app` sale
  por el VIP elegido (punto 40 de [`docs/pendientes-apply.md`](../pendientes-apply.md)).
