# Diagrama 1: organización, gobierno y acceso

Jerarquía de recursos con los nombres de §4.2 del contrato (ejemplo `prefix = "bnt"`), qué
etapa crea cada parte, las políticas y grupos de la etapa 1, el perímetro de VPC-SC y cómo
despliega el pipeline. Es diseño: nada se ha aplicado.

```mermaid
flowchart TB
  org["Organización (org_id)<br/>Cloud Identity · directory_customer_id"]

  subgraph F_BOOT["Carpeta bootstrap (etapa 0)"]
    seed["bnt-bootstrap-seed<br/>bucket de estado bnt-bootstrap-ops-tfstate (multirregión US)<br/>llave KMS bnt-bootstrap-sec-state en us (etapa 0, ADR 0008 y 0022)<br/>cuentas bnt-tf-1-org … bnt-tf-5-workloads<br/>pool y proveedor de WIF"]
    deny["Política de denegación bnt-bootstrap-sec-deny-1-org<br/>bnt-tf-1-org no cambia el IAM de la carpeta, el semilla,<br/>las cuentas ni el bucket, ni toma su identidad (ADR 0023)"]
  end

  role["Roles personalizados de organización (etapa 0)<br/>bntTfKmsSecretIamGranter: la etapa 1 lo asigna a bnt-tf-4-projects en security<br/>bntTfSecretContainerAdmin: la etapa 1 lo asigna a bnt-tf-2-security en security"]
  org --- role

  subgraph F_COMMON["Carpeta common (etapa 1)"]
    hubp["bnt-common-net-hub<br/>red hub (etapa 3)"]
    logp["bnt-common-logging<br/>bucket de logs bnt-common-ops-audit-logs<br/>llaves logs y pubsub (etapa 1, ADR 0018)<br/>tema de hallazgos de SCC, mensajes solo en us-central1"]
    secp["bnt-common-security<br/>llaves KMS de dev, qa y prod (etapa 2)<br/>contenedores de secretos sin valores<br/>el pipeline no lee valores (ADR 0015 y 0023)"]
    bkpp["bnt-common-backup<br/>sin recursos en el código actual"]
  end

  subgraph F_DEV["Carpeta dev"]
    devh["bnt-dev-net-spoke<br/>host de Shared VPC (etapa 3)"]
    deva["bnt-dev-app<br/>proyecto de servicio (etapa 4)<br/>Artifact Registry y Binary Authorization (ADR 0024)"]
  end

  subgraph F_QA["Carpeta qa"]
    qah["bnt-qa-net-spoke<br/>host de Shared VPC (etapa 3)"]
    qaa["bnt-qa-app<br/>proyecto de servicio (etapa 4)"]
  end

  subgraph F_PROD["Carpeta prod · Data Access activado"]
    prodh["bnt-prod-net-spoke<br/>host de Shared VPC (etapa 3)"]
    proda["bnt-prod-app<br/>proyecto de servicio (etapa 4)"]
  end

  org --> F_BOOT
  org --> F_COMMON
  org --> F_DEV
  org --> F_QA
  org --> F_PROD

  deva -- "usa la red" --> devh
  qaa -- "usa la red" --> qah
  proda -- "usa la red" --> prodh

  perim{{"Perímetro VPC-SC bnt_prod_sec_perimeter<br/>creado en la etapa 2 · dry-run por defecto"}}
  perim -. "alta: etapa 2" .- secp
  perim -. "alta: etapa 4" .- proda
  perim -. "alta: etapa 4" .- prodh

  subgraph GOV["Gobierno (etapa 1)"]
    pol["Nueve políticas de organización<br/>compute.vmExternalIpAccess · compute.requireShieldedVm<br/>compute.skipDefaultNetworkCreation · sql.restrictPublicIp<br/>iam.disableServiceAccountKeyCreation · iam.allowedPolicyMemberDomains<br/>storage.publicAccessPrevention · storage.uniformBucketLevelAccess<br/>gcp.resourceLocations: primary_region, dr_region y us"]
    grp["IAM solo por grupos y de solo lectura<br/>org_admins · billing_admins · security_admins<br/>network_admins · platform_devops · auditors<br/>developers solo en dev y qa · ningún rol a user:"]
    obs["Sink agregado de la organización → bucket de logs<br/>notificación de SCC (activación manual)<br/>presupuesto con alertas"]
  end
  GOV -. "se aplica a" .-> org

  subgraph PIPE["Quién despliega"]
    admin["Persona administradora<br/>etapa 0, una sola vez, a mano"]
    gh["GitHub Actions<br/>apply.yml"]
    wif["Proveedor de WIF<br/>attribute_condition: assertion.repository_id<br/>y assertion.repository_owner_id (IDs numéricos)"]
    sa["Cuenta de la etapa bnt-tf-{etapa}<br/>mínimo privilegio, sin llaves JSON<br/>roles de la etapa 5 por proyecto de servicio, no por carpeta"]
  end
  admin --> seed
  gh --> wif --> sa
  sa -- "etapas 1 a 5" --> org
  deny -. "niega a bnt-tf-1-org" .-> seed
```

## Cómo se lee

- Cada caja de proyecto dice qué etapa lo crea o lo llena. Las carpetas de entorno tienen el
  mismo par de proyectos: el host de su Shared VPC (`net-spoke`) y un proyecto de servicio por
  aplicación (por defecto `app`).
- El perímetro de prod lo crea la etapa 2 con el proyecto `security` dentro; la etapa 4 de prod
  agrega el proyecto de servicio y el host, que VPC-SC exige en el mismo perímetro
  (ADR [0009](../adr/0009-perimetro-vpc-sc-en-dos-etapas-y-dry-run.md)).
- Hay tres llaveros fuera de la etapa 2: el del estado en el semilla (etapa 0) y el de logs y
  Pub/Sub en `logging` (etapa 1), para que haya CMEK desde el primer objeto.
- Las personas solo leen. Cambia la infraestructura el pipeline, con una cuenta por etapa y WIF
  filtrado por el ID numérico del repositorio y de su dueño (limitación: cualquier rama del
  repositorio puede usarla, ver [`pipeline.md`](../pipeline.md) §5).
- La cuenta de `1-org` tiene roles amplios de organización; la política de denegación de la
  carpeta `bootstrap` le impide usarlos sobre la base del pipeline
  (ADR [0023](../adr/0023-endurecimiento-de-la-identidad-del-pipeline.md)).

## Cambios respecto a la versión de la fase 3

- El perímetro de VPC-SC ya no rodea solo al proyecto de aplicación de prod: incluye
  `bnt-common-security` (etapa 2), `bnt-prod-app` y `bnt-prod-net-spoke` (etapa 4), y arranca en
  dry-run.
- La llave del bucket de estado se crea en la etapa 0 dentro del proyecto semilla, y la del
  bucket de logs en la etapa 1 dentro de `bnt-common-logging`; antes todo KMS aparecía en
  `bnt-common-security`.
- Security Command Center ya no aparece en `bnt-common-security`: su notificación publica en un
  tema del proyecto `bnt-common-logging`, y la activación de SCC es un paso manual.
- `bnt-common-backup` existe pero no tiene recursos: la bóveda de Backup and DR vive en el
  proyecto de servicio de cada entorno.
- Las políticas de organización son las nueve, no cuatro, y `gcp.resourceLocations` admite
  además la multirregión `us` (llaveros y bucket de doble región).
- Los grupos son siete (se agrega `billing_admins`); sus correos llegan por la variable `groups`
  en lugar de nombres fijos.
- Se quita "salvo emergencia e IAP": no hay acceso de emergencia construido y ningún grupo
  recibe permiso de IAP ([pendientes](../pendientes-apply.md), §5).
- Se agregan el rol personalizado de organización que crea la etapa 0 para la cuenta de la etapa
  4, el sink agregado, el Data Access de la carpeta prod y el presupuesto.
- Ronda de correcciones del 21 nov 2026: el rol de la etapa 4 sobre `security` lo asigna la
  etapa 1 (no la 2); se agrega el rol personalizado de contenedores de secretos de la etapa 2, la
  política de denegación de la carpeta `bootstrap`, el estado en la multirregión `US`, WIF por
  `assertion.repository_id`, y Artifact Registry con Binary Authorization en los proyectos de
  servicio.
