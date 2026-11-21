# Diagrama 3: aplicación y protección de datos

Camino de una solicitud hasta los datos de prod y los controles que encuentra, con lo que crean
las etapas 2, 4 y 5. Es diseño: nada se ha aplicado.

```mermaid
flowchart LR
  user(["Usuario de Internet"])
  xlb["1 · Balanceador HTTPS global<br/>certificado administrado · TLS 1.2 mínimo<br/>redirección de HTTP a HTTPS"]
  armor["2 · Cloud Armor<br/>reglas OWASP preconfiguradas · límite de tasa"]
  fw["3 · Firewall<br/>jerárquica: sin allow, delega con goto_next<br/>red del spoke: salud hacia lb_backend, IAP hacia iap_ssh"]
  user --> xlb --> armor --> fw

  subgraph APP["bnt-prod-app sobre la Shared VPC de bnt-prod-net-spoke"]
    subgraph COMP["4 · Cómputo sin IP pública (etapa 5)"]
      run["Cloud Run<br/>entrada interna y del balanceador<br/>sin allUsers (ADR 0020)"]
      mig["MIG regional<br/>Shielded VM · OS Login · imagen endurecida<br/>etiquetas lb_backend e iap_ssh"]
      gke["GKE regional, nodos privados<br/>Workload Identity: KSA app/app → cuenta workload<br/>Binary Authorization · endpoint privado"]
    end
    ilb["Balanceador interno, uno por región<br/>subred proxy-only · acceso global"]
    ar[("Artifact Registry bnt-prod-app-app-images-us<br/>multirregión us · CMEK artifacts<br/>lectura: gke-nodes, mig y agente de Cloud Run")]
    binauthz{{"Binary Authorization del proyecto<br/>solo imágenes de ese repositorio (ADR 0024)"}}
    subgraph DATA["7 · Datos solo por IP privada"]
      sql[("Cloud SQL PostgreSQL · PSA<br/>HA regional · PITR · TLS obligatorio<br/>autenticación IAM, sin contraseñas")]
      redis[("Memorystore · PSA<br/>TLS en el puerto 6378 · AUTH apagado")]
      nfs[("Filestore · PSA")]
      gcs[("Cloud Storage<br/>Private Google Access y VIP restringido<br/>versionado · sin acceso público")]
    end
  end

  fw --> COMP
  COMP --> DATA
  onprem(["On-premises, por el hub"]) --> ilb
  ilb --> run
  ilb --> mig
  ar -- "imágenes" --> run
  ar -- "imágenes" --> gke
  binauthz -. "admite o rechaza la imagen" .-> run
  binauthz -. "admite o rechaza la imagen" .-> gke

  support(["Soporte"]) --> iap["5 · IAP 35.235.240.0/20<br/>TCP 22 a VM con iap_ssh"] --> mig

  subgraph SEC["bnt-common-security (etapa 2)"]
    sm["6 · Secret Manager<br/>contenedores sin valores (ADR 0015)"]
    kms["8 · Cloud KMS · CMEK<br/>llave por entorno, ubicación y uso<br/>rotación de 90 días · prevent_destroy"]
  end

  sm -. "secretAccessor: cuentas workload y run" .-> COMP
  kms -. "CMEK de discos, secretos de GKE, Cloud Run, imágenes y datos" .-> APP

  perim{{"9 · Perímetro VPC-SC (dry-run por defecto)<br/>security · prod-app · prod-net-spoke<br/>restringe storage, sqladmin, compute, container, run, redis, artifactregistry…<br/>KMS y Secret Manager no restringidos (ADR 0019)"}}
  perim -.- APP
  perim -.- SEC
```

## Cómo se lee

- La solicitud pública entra por el balanceador externo (1) y Cloud Armor (2), los dos en el
  proyecto de servicio. El firewall (3) tiene dos niveles: la política jerárquica de la
  organización no permite nada, solo delega con `goto_next` (verificaciones de salud, IAP,
  tráfico interno y de on-premises) y deniega lo demás; la política de red del spoke es la que
  permite: verificaciones de salud y proxies solo hacia `lb_backend`, SSH por IAP solo hacia
  `iap_ssh`, y plano de control de GKE y tráfico interno de las cargas por rango.
- El cómputo (4) no tiene IP pública. Cloud Run solo acepta tráfico interno y del balanceador;
  con `public_via_load_balancer = true` desactiva la verificación de invocador en lugar de dar
  `allUsers`.
- On-premises llega por el hub al balanceador interno (subred proxy-only), no a las VM. Hay uno
  por región con cómputo y con acceso global: con `dr_active`, el de DR se agrega sin tocar el
  primario.
- Las imágenes de Cloud Run y GKE salen del repositorio multirregional de la aplicación, y la
  política de Binary Authorization del proyecto rechaza las de otro registro (ADR
  [0024](../adr/0024-artifact-registry-y-binary-authorization-por-proyecto.md)).
- Secret Manager (6) guarda contenedores; los valores se cargan fuera de Terraform. Cloud SQL no
  usa contraseñas: las cuentas `workload` (pods de GKE por Workload Identity), `run` y `mig`
  entran por IAM según el cómputo encendido (ADR
  [0015](../adr/0015-sin-contrasenas-ni-valores-de-secretos-en-terraform.md)).
- Cloud SQL, Memorystore y Filestore usan Private Service Access; Cloud Storage, Private Google
  Access con el VIP restringido (7).
- Las llaves (8) y los secretos viven en `security`, dentro del perímetro (9); KMS y Secret
  Manager no son servicios restringidos porque ese proyecto también sirve a dev y qa.

## Cambios respecto a la versión de la fase 3

- Cloud Storage se alcanza por Private Google Access y el VIP restringido
  (`restricted.googleapis.com`, 199.36.153.4/30), no por Private Service Access.
- Cloud KMS y Secret Manager quedan **dentro** del perímetro (el proyecto `security` es su
  primer miembro), no fuera; KMS y Secret Manager no se restringen (ADR 0019).
- Secret Manager ya no guarda "credenciales de BD": Cloud SQL usa autenticación IAM y los
  secretos son contenedores sin valores.
- El perímetro incluye también el proyecto host de prod y arranca en dry-run.
- Cloud IDS ya no aparece como opción: no se construye ([pendientes](../pendientes-apply.md), §5).
- El firewall no es "solo LB e IAP": la política del spoke también permite la subred proxy-only,
  el plano de control de GKE y el tráfico interno de las cargas. Las verificaciones de salud y el
  IAP los permite solo la política del spoke, por etiqueta segura; la jerárquica los delega.
- Se agregan el balanceador interno para on-premises, Cloud Run sin `allUsers` y Memorystore con
  TLS y sin AUTH.
- Ronda de correcciones del 21 nov 2026: Artifact Registry y Binary Authorization por proyecto,
  enlace de Workload Identity, balanceador interno por región con acceso global y
  `artifactregistry` entre los servicios restringidos.
