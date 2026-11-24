# Registros de decisiones de arquitectura (ADR)

Decisiones cerradas del diseño, una por archivo. La fuente de cada una es la tabla de §2 de
[`CONTRATO.md`](../CONTRATO.md); lo que solo se puede comprobar con un apply está en
[`pendientes-apply.md`](../pendientes-apply.md) (§12 del contrato). La especificación del cliente
se cita solo por nombre de sección.

## Índice

| ADR | Título | Tipo | Resumen |
|---|---|---|---|
| [0001](0001-versiones-de-terraform-y-proveedores.md) | Versiones de Terraform y proveedores | Conforme | `google`/`google-beta` `~> 6.0` y Terraform `>= 1.9` en todo `versions.tf`; sin atributos de solo escritura. Las pruebas exigen 1.11 o mayor (0021). |
| [0002](0002-regiones-primaria-y-de-dr.md) | Regiones primaria y de DR | Conforme | `us-central1` y `us-east4` por variable; México solo tiene una región, lo que limita el DR con residencia. Lo que la conmutación necesita no vive solo en la primaria (0022). |
| [0003](0003-vpc-por-entorno-unida-al-hub-por-peering.md) | VPC por entorno unida al hub por peering | Desviación del diagrama | Un spoke por entorno como host de Shared VPC, peering con el hub y sin peering entre spokes. |
| [0004](0004-cloud-nat-en-cada-spoke.md) | Cloud NAT en cada spoke | Desviación del diagrama | Un NAT no sirve a VPC unidas por peering; NAT por spoke y región, hub sin salida a internet. |
| [0005](0005-balanceador-y-cloud-armor-en-el-proyecto-de-servicio.md) | Balanceador y Cloud Armor en el proyecto de servicio | Desviación del diagrama | El balanceador externo y Cloud Armor viven con los backends de cada entorno, no en el hub; el interno es uno por región con acceso global. |
| [0006](0006-on-premises-simulado-con-ha-vpn-entre-vpc.md) | On-premises simulado con HA VPN entre VPC | Supuesto | VPC `onprem-sim` con `simulate_onprem` y VPN también en la región de DR; el secreto de la VPN queda en el estado cifrado del hub y se rota de a un túnel. |
| [0007](0007-ci-cd-con-github-actions.md) | CI/CD con GitHub Actions | Conforme | Cuatro flujos y Workload Identity Federation por ID del repositorio; plan y apply separados; sin llaves JSON. |
| [0008](0008-llave-kms-propia-de-la-etapa-0.md) | Llave KMS propia de la etapa 0 | Aclaración | La etapa 0 crea la llave del bucket de estado (multirregión `us`) para que haya CMEK desde el primer objeto. |
| [0009](0009-perimetro-vpc-sc-en-dos-etapas-y-dry-run.md) | Perímetro de VPC-SC en dos etapas y dry-run | Aclaración | La etapa 2 crea el perímetro, la 4 da de alta los proyectos de prod con recursos separados; dry-run por defecto. |
| [0010](0010-bucket-de-estado-unico-con-iam-por-prefijo.md) | Bucket de estado único con IAM por prefijo | Aclaración | Escritura en el prefijo propio y lectura mínima aguas arriba por condiciones de IAM, con listado del bucket; plan B con carpetas administradas. |
| [0011](0011-construccion-en-paralelo-y-despliegue-en-orden.md) | Construcción en paralelo, despliegue en orden | Desviación del plan | Se construye sin GCP y en paralelo; se aplica 0 → 5 cuando exista la organización. |
| [0012](0012-gke-mig-y-cloud-run.md) | GKE, MIG y Cloud Run | Conforme | Tres módulos de cómputo, cada uno con su caso de uso, activados por interruptores en la etapa 5; Workload Identity para los pods. |
| [0013](0013-modulos-propios-sin-modulos-de-terceros.md) | Módulos propios | Conforme | Recursos del proveedor sin envolver módulos de terceros, para probar con `mock_provider`; módulos por ruta relativa, sin versiones publicadas. |
| [0014](0014-raiz-del-hub-y-raices-de-spoke.md) | Raíz del hub y raíces de spoke | Aclaración | Hub en `stages/3-networks/` con estado propio; cada spoke en `envs/<env>/`. |
| [0015](0015-sin-contrasenas-ni-valores-de-secretos-en-terraform.md) | Sin contraseñas ni valores de secretos en Terraform | Aclaración | Cloud SQL con autenticación IAM, secretos sin versiones, pipeline sin acceso a valores y AUTH de Memorystore apagado. |
| [0016](0016-valores-de-etiquetas-en-minusculas.md) | Valores de etiquetas en minúsculas | Desviación menor | GCP rechaza mayúsculas en valores de etiquetas; validación común en todos los módulos. |
| [0017](0017-nombres-cortos-de-cuentas-de-servicio.md) | Nombres cortos de cuentas de servicio | Desviación menor | `<prefix>-tf-<etapa>` y `<prefix>-<env>-<app>-<uso>` por el límite de 30 caracteres. |
| [0018](0018-llave-kms-del-bucket-de-logs-en-la-etapa-1.md) | Llave KMS del bucket de logs en la etapa 1 | Aclaración | La etapa 1 crea en `logging` la llave del bucket de auditoría; mismo criterio que el 0008. El tema de SCC guarda mensajes solo en la región de su llave. |
| [0019](0019-kms-y-secret-manager-fuera-de-los-servicios-restringidos.md) | KMS y Secret Manager no restringidos | Aclaración | El proyecto `security` sirve también a dev y qa; restringirlos los bloquearía al forzar el perímetro. |
| [0020](0020-cloud-run-publico-detras-del-balanceador.md) | Cloud Run público detrás del balanceador | Aclaración | Entrada interna y balanceador; verificación de invocador apagada solo con `public_via_load_balancer`; nunca `allUsers`. |
| [0021](0021-pruebas-con-terraform-1-11-y-codigo-con-1-9.md) | Pruebas con Terraform 1.11, código con 1.9 | Aclaración | Las pruebas usan `override_during = plan` (1.11); `pr.yml` comprueba el código con 1.9.8 sin pruebas y todo con 1.16.5. |
| [0022](0022-estado-y-conmutacion-sin-depender-de-la-region-primaria.md) | Estado y conmutación sin la región primaria | Aclaración | Bucket de estado multirregional, VPN de DR, balanceador interno por región y GKE fuera del externo mientras no haya NEG de DR. |
| [0023](0023-endurecimiento-de-la-identidad-del-pipeline.md) | Endurecimiento de la identidad del pipeline | Aclaración | WIF por IDs numéricos, política de denegación en `bootstrap`, roles personalizados sin acceso a valores y permisos de la etapa 5 por proyecto; riesgos residuales. |
| [0024](0024-artifact-registry-y-binary-authorization-por-proyecto.md) | Artifact Registry y Binary Authorization por proyecto | Aclaración | Un repositorio multirregional por aplicación y una política que solo admite ese repositorio. |
| [0025](0025-plan-aprobacion-y-apply-separados.md) | Plan, aprobación y apply separados | Aclaración | Plan sin entorno, apply en el entorno con la misma huella; `common` protegido; `plan-gate` y prueba de humo de dev. |
| [0026](0026-api-de-google-por-el-vip-restringido-en-todos-los-entornos.md) | API de Google por el VIP restringido | Aclaración | Zonas de `googleapis.com`, `gcr.io`, `pkg.dev` y `run.app` hacia el VIP de `google_apis_vip` (`restricted` en los tres entornos). |
| [0027](0027-desviaciones-aceptadas-del-cis.md) | Desviaciones aceptadas del CIS | Desviación del CIS | Once recomendaciones del CIS v5.0 abiertas por decisión (1.6, 2.1, 2.3, 2.4, 3.8, 3.9, 3.10 en dev y qa, 4.7, 4.11, 4.12, 6.9), con su riesgo y lo que las cierra; novena métrica de firewall y límite de la política jerárquica. |
| [0028](0028-apagado-fuera-de-horario-de-dev-y-qa.md) | Apagado fuera de horario de dev y qa | Aclaración | `off_hours_shutdown` (rechazado en prod): Cloud SQL y pools de GKE con trabajos de Cloud Scheduler, MIG con programa de escalado; sin deriva por `ignore_changes` y `postcondition`; cuenta y rol mínimos creados por la etapa 4. |

## Formato

Cada ADR se llama `NNNN-titulo-en-kebab-case.md` y tiene estas secciones:

- **Estado**: `Aceptado` y la fecha de aceptación, más una línea `Tipo:` (Conforme,
  Aclaración, Supuesto o Desviación). Las desviaciones nombran de qué se apartan (la
  especificación, su diagrama o su plan de trabajo) y dicen qué tiene que confirmar el cliente.
- **Contexto**: el problema y las restricciones, con los módulos, etapas y variables que toca.
- **Decisión**: lo que se construye, con los nombres reales de recursos y variables.
- **Alternativas consideradas**: opciones reales y por qué se rechazaron.
- **Consecuencias**: positivas, negativas y lo que hay que comprobar en el primer apply, con la
  referencia al punto de `pendientes-apply.md` cuando existe.

Lo que depende del comportamiento de GCP se escribe como expectativa de diseño y se remite a la
lista de pendientes; lo que no se pudo confirmar en la documentación oficial se marca "por
verificar". Un ADR aceptado no se edita para cambiar la decisión de fondo: se escribe uno nuevo
que lo reemplace y se cambia el estado del anterior a `Reemplazado por NNNN`. Sí se enmienda
cuando el código cambia un detalle sin revertir la decisión: la línea de `Estado` agrega
`Enmendado el <fecha>` con un resumen del cambio y, si aplica, el ADR que lo explica (así se
enmendaron el 2026-11-21 los ADR 0001, 0002, 0005 a 0010, 0012, 0013, 0015 y 0018, y el
2026-11-23 otra vez el 0009).
