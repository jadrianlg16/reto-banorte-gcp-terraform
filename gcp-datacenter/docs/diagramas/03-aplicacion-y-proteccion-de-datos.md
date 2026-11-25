# Diagrama 3: aplicación y protección de datos

Camino de una solicitud hasta los datos de prod y los controles que encuentra. dev y qa tienen
la misma forma con menos piezas encendidas y sin DR. Es diseño: nada se ha aplicado.

![Aplicación y datos de prod: del usuario a la base de datos](img/03-aplicacion-y-datos.png)

El PNG sale de [`fuente/`](fuente/LEEME.md) y dibuja prod con lo que enciende
`stages/3-workloads/envs/prod/terraform.tfvars.example`. El diagrama de texto usa
`prefix = "bnt"` y la aplicación `app`.

```mermaid
flowchart LR
  user(["Usuario de Internet"])
  xlb["1 · Balanceador HTTPS global<br/>certificado administrado · TLS 1.2 mínimo<br/>redirección de HTTP a HTTPS"]
  armor["2 · Cloud Armor<br/>reglas OWASP preconfiguradas · límite de tasa"]
  fw["3 · Política de firewall de red del spoke prod<br/>salud y proxies → lb_backend · IAP → iap_ssh<br/>plano de control de GKE · tráfico interno"]
  user --> xlb --> armor --> fw

  subgraph APP["3-workloads/envs/prod en la VPC del spoke prod"]
    subgraph COMP["4 · Cómputo sin IP pública"]
      run["Cloud Run<br/>entrada interna y del balanceador<br/>sin allUsers (ADR 0020)"]
      mig["MIG regional<br/>Shielded VM · OS Login<br/>etiquetas lb_backend e iap_ssh"]
      gke["GKE regional bnt-prod-app-gke, nodos privados<br/>Workload Identity: pods del clúster → cuenta workload<br/>Binary Authorization"]
    end
    ilb["Balanceador interno, uno por región<br/>subred proxy-only · acceso global"]
    subgraph DATA["7 · Datos solo por IP privada"]
      sql[("Cloud SQL PostgreSQL · PSA<br/>HA regional · PITR<br/>autenticación IAM, sin contraseñas")]
      redis[("Memorystore · PSA · TLS")]
      nfs[("Filestore · PSA")]
      gcs[("Cloud Storage de doble región<br/>Private Google Access y VIP restringido<br/>versionado · sin acceso público")]
    end
  end

  fw --> COMP
  COMP --> DATA
  onprem(["On-premises, por el hub"]) --> ilb
  ilb --> run
  ilb --> mig

  subgraph BASE["1-base (una vez por proyecto)"]
    ar[("Artifact Registry bnt-prod-app<br/>multirregión us · CMEK artifacts · etiquetas inmutables")]
    binauthz{{"Binary Authorization del proyecto<br/>lista de permitidos: los repositorios del proyecto"}}
    sm["6 · Secret Manager<br/>contenedores sin valores (ADR 0015)"]
    kms["8 · Cloud KMS · CMEK<br/>llave por entorno, ubicación y uso<br/>rotación de 90 días · prevent_destroy"]
    rsa["Cuentas de ejecución bnt-prod-app-{uso}<br/>gke-nodes · workload · mig · run<br/>con sus permisos y Workload Identity"]
  end
  rsa -. "tf-wl-prod solo las adjunta" .-> COMP

  pub(["Publicadores de imágenes<br/>artifact_registry_publishers"]) -- "push" --> ar
  ar -- "imágenes" --> run
  ar -- "imágenes" --> gke
  binauthz -. "admite o rechaza la imagen" .-> run
  binauthz -. "admite o rechaza la imagen" .-> gke
  support(["Soporte"]) --> iap["5 · IAP 35.235.240.0/20<br/>TCP 22 a VM con iap_ssh"] --> mig
  sm -. "secretAccessor: cuentas workload y run" .-> COMP
  kms -. "CMEK de discos, secretos de GKE, Cloud Run y datos" .-> APP

  perim{{"9 · VPC-SC opcional, solo con organización<br/>rodea todo el proyecto · dry-run"}}
  perim -.- APP
  perim -.- BASE
```

## Cómo se lee

- **Entrada pública (1 y 2).** El balanceador externo y Cloud Armor viven en la raíz de cargas
  del entorno (ADR [0005](../adr/0005-balanceador-y-cloud-armor-en-el-proyecto-de-servicio.md),
  ajustado por el ADR 0029). Cloud Armor es una política del servicio de backend; el dibujo la
  pone antes del balanceador para leerlo de izquierda a derecha.
- **Firewall (3).** Una sola política, la de red del spoke. Permite solo hacia donde hace falta,
  por etiqueta segura o por rango, y niega lo demás ([diagrama 2](02-red-y-conectividad.md)).
- **Cómputo (4).** Sin IP pública. Cloud Run acepta tráfico interno y del balanceador; con
  `public_via_load_balancer = true` desactiva la verificación de invocador en lugar de dar
  `allUsers`. On-premises llega por el hub al balanceador interno, no a las VM.
- **Cuentas de ejecución.** Las crea `1-base` (`stages/1-base/runtime_accounts.tf`) con sus
  roles de proyecto, la lectura de los secretos del entorno (`workload` y `run`) y del
  repositorio de la aplicación, y Cloud SQL por IAM limitado a las instancias del entorno.
  `3-workloads` solo las lee de `runtime_service_accounts`; `tf-wl-<env>` solo tiene
  `serviceAccountUser` sobre las que adjunta (pendientes 131 a 133).
- **Workload Identity.** El pool `<proyecto>.svc.id.goog` es el mismo para los tres entornos, y
  el principal de un namespace vale desde cualquier clúster del proyecto. Por eso `1-base` enlaza
  la cuenta `workload` a todos los pods del clúster `<prefix>-<env>-<app>-gke[-dr]`
  (`principalSet` `…/kubernetes.cluster/…`), no a un namespace (ADR 0029 §9): la frontera es el
  clúster. El namespace `<app>-<env>` queda como convención. El enlace se crea con
  `gke_workload_identity_bindings = true` después del primer clúster, porque GKE crea el pool
  con él (pendientes 135 y 158).
- **Imágenes.** Un repositorio por entorno y aplicación (`<prefix>-<env>-<app>`, multirregión
  `us`) y una sola política de Binary Authorization, las dos en `1-base`. Solo escriben los
  `artifact_registry_publishers` (`serviceAccount:`, `group:` o `principal…`, nunca `user:`).
- **Secretos (6) y datos (7).** Secret Manager guarda contenedores; los valores se cargan fuera
  de Terraform. Cloud SQL no usa contraseñas: las cuentas `workload` (GKE), `run` y `mig` entran
  por IAM según el cómputo encendido
  (ADR [0015](../adr/0015-sin-contrasenas-ni-valores-de-secretos-en-terraform.md)). Cloud SQL,
  Memorystore y Filestore usan el Private Service Access del spoke; Cloud Storage, Private Google
  Access con el VIP restringido.
- **Llaves (8).** Llaveros `<prefix>-<env>-sec-keyring-{usc1,use4,us}` en `1-base`, solo con las
  llaves que se usan (las de DR, solo en `dr_environments`). El IAM sobre llaves y secretos lo
  da `1-base`; la cuenta de cargas del entorno no tiene IAM de KMS ni de secretos. Los agentes de
  servicio son uno por proyecto y tienen permiso sobre las llaves de los tres entornos (riesgo
  aceptado, ADR 0029 §4).
- **VPC-SC (9).** Solo con `org_id` y `access_policy_id`. Rodea todo el proyecto y queda en
  dry-run: no separa entornos (ADR 0029 §1).

## Lo que cambió del primer texto del ADR 0029 al código

- **Binary Authorization.** El primer texto del ADR pedía que cada clúster de prod solo
  admitiera el repositorio de prod. En el código la lista de permitidos es global, y una imagen
  que coincide con ella se admite sin importar las reglas por clúster (comentario de
  `stages/1-base/artifacts.tf`). Sin atestadores, los clústeres de prod admiten las imágenes de
  cualquier repositorio del proyecto (riesgo aceptado). Con `binary_authorization_env_attestors`,
  cada clúster exige el atestador de su entorno; los atestadores no los crea ninguna raíz.
  HYPOTHESIS hasta el primer apply (pendientes 42 y 139).
- **Cuentas de ejecución.** Las crea `1-base`, no la raíz de cargas del entorno.

El diseño anterior, con proyectos de servicio y Shared VPC, está en la rama
`archivo/multiproyecto`.
