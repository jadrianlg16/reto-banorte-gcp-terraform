# Registros de decisiones de arquitectura (ADR)

Decisiones cerradas del diseño, una por archivo. La fuente de cada una es la tabla de §2 de
[`CONTRATO.md`](../CONTRATO.md); lo que solo se puede comprobar con un apply está en
[`pendientes-apply.md`](../pendientes-apply.md) (§12 del contrato). La especificación del cliente
se cita solo por nombre de sección.

## Índice

La columna "Estado" dice si el ADR sigue como se aceptó, si se enmendó para el proyecto único
(24 nov 2026) o si lo reemplazó el ADR 0029. "Enmendado 24 nov (2)" marca los que se enmendaron
otra vez ese día con el código final de las revisiones de seguridad e integración, y "Enmendado
24 nov (3)" los que se enmendaron una tercera vez con el arreglo de la re-revisión de seguridad
(rama `r2/seg2`). El diseño de varios proyectos vive en la rama `archivo/multiproyecto`.

| ADR | Título | Tipo | Estado | Resumen |
|---|---|---|---|---|
| [0001](0001-versiones-de-terraform-y-proveedores.md) | Versiones de Terraform y proveedores | Conforme | Vigente | `google`/`google-beta` `~> 6.0` y Terraform `>= 1.9` en todo `versions.tf`; sin atributos de solo escritura. Las pruebas exigen 1.11 o mayor (0021). |
| [0002](0002-regiones-primaria-y-de-dr.md) | Regiones primaria y de DR | Conforme | Enmendado 24 nov (2) | `us-central1` y `us-east4` por variable; México solo tiene una región, lo que limita el DR con residencia. Lo que la conmutación necesita no vive solo en la primaria (0022). Llaveros por ubicación en `1-base`; llaves de DR solo en `dr_environments`. |
| [0003](0003-vpc-por-entorno-unida-al-hub-por-peering.md) | VPC por entorno unida al hub por peering | Desviación del diagrama | Enmendado 24 nov | Un spoke por entorno en el proyecto único, sin Shared VPC, peering con el hub y sin peering entre spokes. |
| [0004](0004-cloud-nat-en-cada-spoke.md) | Cloud NAT en cada spoke | Desviación del diagrama | Vigente | Un NAT no sirve a VPC unidas por peering; NAT por spoke y región, hub sin salida a internet. |
| [0005](0005-balanceador-y-cloud-armor-en-el-proyecto-de-servicio.md) | Balanceador y Cloud Armor en el proyecto de servicio | Desviación del diagrama | Enmendado 24 nov | El balanceador externo y Cloud Armor viven con los backends de cada entorno, en `3-workloads/envs/<env>`, no en el hub; el interno es uno por región con acceso global. |
| [0006](0006-on-premises-simulado-con-ha-vpn-entre-vpc.md) | On-premises simulado con HA VPN entre VPC | Supuesto | Enmendado 24 nov (2) | VPC `onprem-sim` con `simulate_onprem`, su propia política de firewall de red, VM DNS opcional (`onprem_dns_vm`) y VPN también en la región de DR; el secreto de la VPN queda en el estado cifrado del hub y se rota de a un túnel; con on-premises real el plan del hub falla en el pipeline (punto 151). |
| [0007](0007-ci-cd-con-github-actions.md) | CI/CD con GitHub Actions | Conforme | Enmendado 24 nov (3) | Cinco flujos y uno reutilizable; WIF por ID del repositorio y, para escribir, solo desde `_terraform-root.yml` en `main` con `push` o `workflow_dispatch` (`attribute.deploy`); plan con `tf-read` y apply separados; Go sin GCP en `pr.yml`; `GCP_DISABLED_ENVS`; sin llaves JSON. |
| [0008](0008-llave-kms-propia-de-la-etapa-0.md) | Llave KMS propia de la etapa 0 | Aclaración | Enmendado 24 nov | `0-bootstrap` crea la llave del bucket de estado (multirregión `us`) para que haya CMEK desde el primer objeto; separada de las demás por IAM y la etiqueta de protección. |
| [0009](0009-perimetro-vpc-sc-en-dos-etapas-y-dry-run.md) | Perímetro de VPC-SC en dos etapas y dry-run | Aclaración | Reemplazado por 0029 | Ahora el perímetro es opcional: solo con organización y `access_policy_id`, lo crea la persona de `0-bootstrap` alrededor de todo el proyecto y queda en dry-run. Sigue vigente la mecánica del módulo `vpc-sc`. |
| [0010](0010-bucket-de-estado-unico-con-iam-por-prefijo.md) | Bucket de estado único con IAM por prefijo | Aclaración | Enmendado 24 nov | Escritura en el prefijo propio y lectura mínima aguas arriba por condiciones de IAM, con listado del bucket; `tf-read` lee todo; plan B con carpetas administradas. |
| [0011](0011-construccion-en-paralelo-y-despliegue-en-orden.md) | Construcción en paralelo, despliegue en orden | Desviación del plan | Enmendado 24 nov | Se construye sin GCP y en paralelo; se aplica 0 → 1 → 2 → 3 cuando exista el proyecto. |
| [0012](0012-gke-mig-y-cloud-run.md) | GKE, MIG y Cloud Run | Conforme | Enmendado 24 nov (3) | Tres módulos de cómputo, cada uno con su caso de uso, activados por interruptores en `3-workloads`; cuentas de ejecución y Workload Identity por clúster (`principalSet` de todos los pods de `<prefix>-<env>-<app>-gke[-dr]`) desde `1-base`; `container.clusterAdmin` condicionado. |
| [0013](0013-modulos-propios-sin-modulos-de-terceros.md) | Módulos propios | Conforme | Vigente | Recursos del proveedor sin envolver módulos de terceros, para probar con `mock_provider`; módulos por ruta relativa, sin versiones publicadas. |
| [0014](0014-raiz-del-hub-y-raices-de-spoke.md) | Raíz del hub y raíces de spoke | Aclaración | Enmendado 24 nov | Hub en `stages/2-networks/` con estado propio y sin leer otros estados; cada spoke en `envs/<env>/` con su cuenta. |
| [0015](0015-sin-contrasenas-ni-valores-de-secretos-en-terraform.md) | Sin contraseñas ni valores de secretos en Terraform | Aclaración | Enmendado 24 nov (2) | Cloud SQL con autenticación IAM, secretos sin versiones, pipeline sin acceso a valores (denegación) y AUTH de Memorystore apagado; la lectura de secretos y los roles de Cloud SQL de las cuentas de ejecución los da `1-base`. |
| [0016](0016-valores-de-etiquetas-en-minusculas.md) | Valores de etiquetas en minúsculas | Desviación menor | Vigente | GCP rechaza mayúsculas en valores de etiquetas; validación común en todos los módulos. |
| [0017](0017-nombres-cortos-de-cuentas-de-servicio.md) | Nombres cortos de cuentas de servicio | Desviación menor | Enmendado 24 nov (2) | `<prefix>-tf-{base,net,net-<env>,wl-<env>,read}` y `<prefix>-<env>-<app>-<uso>` (creadas por `1-base`) por el límite de 30 caracteres. |
| [0018](0018-llave-kms-del-bucket-de-logs-en-la-etapa-1.md) | Llave KMS del bucket de logs en la etapa 1 | Aclaración | Enmendado 24 nov | `1-base` crea en el llavero común la llave del bucket de auditoría y la del tema de SCC; sink de proyecto. Mismo criterio que el 0008. |
| [0019](0019-kms-y-secret-manager-fuera-de-los-servicios-restringidos.md) | KMS y Secret Manager no restringidos | Aclaración | Reemplazado por 0029 | Sin proyecto `security`, KMS y Secret Manager sí están en `vpc_sc_restricted_services` por defecto. |
| [0020](0020-cloud-run-publico-detras-del-balanceador.md) | Cloud Run público detrás del balanceador | Aclaración | Enmendado 24 nov | Entrada interna y balanceador; verificación de invocador apagada solo con `public_via_load_balancer`; nunca `allUsers` (con o sin organización). |
| [0021](0021-pruebas-con-terraform-1-11-y-codigo-con-1-9.md) | Pruebas con Terraform 1.11, código con 1.9 | Aclaración | Enmendado 24 nov | Las pruebas usan `override_during = plan` (1.11); `pr.yml` comprueba el código con 1.9.8 sin pruebas y todo con 1.16.5. |
| [0022](0022-estado-y-conmutacion-sin-depender-de-la-region-primaria.md) | Estado y conmutación sin la región primaria | Aclaración | Enmendado 24 nov (2) | Bucket de estado multirregional, VPN de DR, balanceador interno por región y GKE fuera del externo mientras no haya NEG de DR; llaves de DR solo en `dr_environments`. |
| [0023](0023-endurecimiento-de-la-identidad-del-pipeline.md) | Endurecimiento de la identidad del pipeline | Aclaración | Enmendado 24 nov (3) | WIF por IDs numéricos y, para escribir, solo desde `_terraform-root.yml` en `main` con su evento (`attribute.deploy`); política de denegación del proyecto con etiqueta y cuatro reglas, la cuarta contra la creación de llaves por cualquier principal; sin `serviceAccountAdmin` ni `tagUser` de proyecto; cuatro roles personalizados; roles de proyecto condicionados desde `0-bootstrap`; riesgos residuales. |
| [0024](0024-artifact-registry-y-binary-authorization-por-proyecto.md) | Artifact Registry y Binary Authorization por proyecto | Aclaración | Enmendado 24 nov (2) | Un repositorio multirregional por entorno y aplicación y una política para el proyecto, en `1-base`, con dos modos: lista de permitidos global (riesgo aceptado) o un atestador por entorno (`binary_authorization_env_attestors`). |
| [0025](0025-plan-aprobacion-y-apply-separados.md) | Plan, aprobación y apply separados | Aclaración | Enmendado 24 nov | Plan sin entorno con `tf-read` y `-lock=false`, apply en el entorno con la misma huella; `common` protegido; `plan-gate` y prueba de humo de dev. |
| [0026](0026-api-de-google-por-el-vip-restringido-en-todos-los-entornos.md) | API de Google por el VIP restringido | Aclaración | Enmendado 24 nov | Zonas de `googleapis.com`, `gcr.io`, `pkg.dev` y `run.app` hacia el VIP de `google_apis_vip` (`restricted` en los tres entornos). |
| [0027](0027-desviaciones-aceptadas-del-cis.md) | Desviaciones aceptadas del CIS | Desviación del CIS | Enmendado 24 nov (3) | Doce recomendaciones del CIS v5.0 abiertas por decisión (1.1.3, 1.6, 2.1, 2.3, 2.4, 3.8, 3.9, 3.10 en dev y qa, 4.7, 4.11, 4.12, 6.9), con su riesgo y lo que las cierra; 1.7 cerrada por las cuentas de ejecución de `1-base`; novena métrica para políticas de firewall de red. |
| [0028](0028-apagado-fuera-de-horario-de-dev-y-qa.md) | Apagado fuera de horario de dev y qa | Aclaración | Enmendado 24 nov (3) | `off_hours_shutdown` (rechazado en prod): Cloud SQL y pools de GKE con trabajos de Cloud Scheduler, MIG con programa de escalado; sin deriva por `ignore_changes` y `postcondition`; rol en `0-bootstrap`, cuenta `-sched` en `1-base` (`off_hours_environments`) con el rol condicionado a su entorno. |
| [0029](0029-un-solo-proyecto.md) | Toda la landing zone en un solo proyecto de GCP | Desviación (pedido del cliente) | Enmendado 24 nov (3) | Cuatro etapas (`0-bootstrap`, `1-base`, `2-networks`, `3-workloads`); hub y tres spokes como VPC del mismo proyecto; organización opcional, aplicada por la persona de `0-bootstrap`; una cuenta del pipeline por raíz y entorno, que para escribir solo se toma desde `_terraform-root.yml` en `main` (`attribute.deploy`), más `tf-read`; Cloud SQL, GKE y Backup and DR condicionados por entorno; cuentas de ejecución en `1-base`; regla de recursos únicos; destroy sin borrar proyectos; cuatro riesgos residuales de la re-revisión y la lista exacta de roles sin condición (§9). Manda sobre §2, §3, §6 y §7 del contrato. |

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
2026-11-23 otra vez el 0009). El 2026-11-24, para el proyecto único (ADR 0029), se enmendaron
los ADR 0002, 0003, 0005 a 0008, 0010 a 0012, 0014, 0015, 0017, 0018 y 0020 a 0028, y los ADR
0009 y 0019 quedaron `Reemplazado por 0029`: su línea de estado dice qué rige ahora y el resto
del texto describe el diseño de varios proyectos. Los ADR 0001, 0004, 0013 y 0016 no cambiaron.
Ese mismo día, con el código final de las revisiones de seguridad e integración (ramas
`r2/*`), se enmendaron otra vez los ADR 0002, 0006, 0007, 0012, 0015, 0017, 0022 a 0024 y 0027 a
0029, y se corrigió la línea de estado del 0009 (el perímetro lo crea `0-bootstrap`). Con el
arreglo de la re-revisión de seguridad (rama `r2/seg2`), el mismo día se enmendaron una tercera
vez los ADR 0007, 0012, 0023, 0027, 0028 y 0029.
