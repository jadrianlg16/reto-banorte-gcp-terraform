# Diagrama 4: operación, continuidad y automatización

Cómo entra un cambio, cómo se detecta una falla y cómo se recupera prod en `us-east4`. Es
diseño: ningún flujo ha corrido contra GCP y los objetivos de RPO y RTO no se han medido.

```mermaid
flowchart TB
  subgraph CHG["Cambios (GitHub Actions)"]
    pr["Pull request · pr.yml<br/>check.sh con Terraform 1.9.8 sin pruebas y con 1.16.5 con terraform test<br/>policy-check.sh · selftest.sh · docs.sh --check<br/>con GCP_ENABLED: plan por raíz, Conftest, Infracost<br/>plan-gate: resultado de los planes con nombre fijo"]
    merge["Merge a main<br/>protección de rama con plan-gate obligatorio<br/>(configuración manual en GitHub, depende del plan)"]
    apply["apply.yml → _terraform-root.yml por raíz<br/>check-main-tip.sh: no planea ni aplica un commit viejo de main<br/>plan sin entorno: Conftest y huella del plan<br/>apply en el entorno: vuelve a planear y aplica si la huella coincide<br/>1-org → 2-security → hub → dev → dev-smoke → qa → prod"]
    commonenv["Entornos common y prod<br/>revisores obligatorios (ADR 0025)"]
    smoke["dev-smoke<br/>TestDevSmoke con GCP_AUDIT_SERVICE_ACCOUNT<br/>si falla, qa y prod no se aplican"]
    drift["drift.yml diario<br/>plan -detailed-exitcode<br/>incidencia con etiqueta drift"]
    unmanaged["drift.yml · recursos no administrados por carpeta<br/>common, dev, qa y prod<br/>Cloud Asset Inventory frente a los estados<br/>construido, sin correr contra GCP"]
    tt["terratest.yml nocturno, manual o por etiqueta de módulo"]
  end
  pr --> merge --> apply
  apply -- "raíces de common y prod" --> commonenv
  apply -- "después de dev" --> smoke

  wif["WIF por ID del repositorio + cuenta de servicio por etapa"]
  wif --> apply
  wif --> drift
  wif --> unmanaged

  state[("Bucket de estado en el semilla, multirregión US<br/>un prefijo por etapa y entorno<br/>versionado · CMEK de la etapa 0 en us · bloqueo nativo")]
  apply <--> state
  drift --> state
  unmanaged --> state

  subgraph DET["Detectar"]
    logs["Sink de la organización → bucket de logs<br/>retención · bloqueo opcional · CMEK de la etapa 1<br/>Data Access en la carpeta prod"]
    mon["Cloud Monitoring por entorno, alertas por correo<br/>disponibilidad · 5xx · saturación · retraso de réplica<br/>SLO 99.9 % con alertas de consumo"]
    scc["Security Command Center (activación manual)<br/>hallazgos HIGH y CRITICAL → Pub/Sub"]
    budget["Presupuesto de la organización"]
  end

  subgraph REC["Recuperar en us-east4 (prod con enable_dr = true)"]
    replica[("Réplica de Cloud SQL en us-east4<br/>PITR en la primaria")]
    dual[("Bucket de doble región<br/>turbo replication")]
    backup[("Bóveda de Backup and DR en us-east4<br/>plan diario de Cloud SQL, 30 días<br/>Backup for GKE en us-east4")]
    vpndr["HA VPN de DR en us-east4<br/>on-premises sigue conectado"]
    failover["Conmutación (runbook 04)<br/>promote-replica con gcloud · dr_active = true<br/>cómputo en us-east4 · backends del externo a us-east4<br/>balanceador interno de DR agregado, el primario intacto<br/>objetivos RPO ≤ 15 min y RTO ≤ 4 h, sin medir"]
    failback["Vuelta a us-central1 (runbook 04)<br/>apply 1: dr_active = true y dr_teardown = true<br/>apply 2: dr_active = false y dr_teardown = false<br/>retira el cómputo de DR; el primario sigue protegido"]
  end
  failover --> failback

  mon -- "alerta" --> failover
  replica --> failover
  dual --> failover
  backup --> failover
  vpndr --> failover
  state -- "disponible sin us-central1" --> failover
  drift -. "runbook 05" .-> merge
  unmanaged -. "runbook 05" .-> merge
```

## Cómo se lee

- Todo cambio entra por PR. Sin GCP, `pr.yml` corre las revisiones estáticas, las pruebas con
  proveedores simulados, las políticas sobre los planes de ejemplo y terraform-docs; con
  `GCP_ENABLED = true` agrega el plan real, Conftest sobre él y el costo
  ([`pipeline.md`](../pipeline.md)).
- `apply.yml` aplica las raíces en serie (los spokes nunca a la vez). Cada raíz con cambios de
  `common` o `prod` espera la aprobación de su entorno, con el resumen del plan a la vista, y el
  apply solo corre si la huella del plan nuevo es igual a la revisada
  (ADR [0025](../adr/0025-plan-aprobacion-y-apply-separados.md)). Después de dev corre la prueba
  de humo; si falla, qa y prod no se aplican. La etapa 0 no está en el pipeline.
- Ni `plan-gate` ni los revisores bloquean nada hasta que alguien configure la protección de
  `main` y los entornos en GitHub, y eso depende del plan de GitHub
  ([`pipeline.md`](../pipeline.md) §4).
- `drift.yml` abre una incidencia por raíz con diferencias y, aparte, compara con Cloud Asset
  Inventory los recursos de cada carpeta de entorno con los estados; la respuesta está en el
  [runbook 05](../runbooks/05-respuesta-a-drift.md).
- La recuperación de prod combina datos replicados (Cloud SQL y el bucket), respaldos en la
  región de DR, la VPN de DR, el estado multirregional y la conmutación manual del
  [runbook 04](../runbooks/04-conmutacion-a-dr.md). Memorystore y Filestore no tienen DR.

## Cambios respecto a la versión de la fase 3

- El pull request también corre `terraform test`, `policy-check.sh` y `docs.sh --check`; el plan,
  Conftest e Infracost dependen de `GCP_ENABLED`.
- El despliegue se dibuja con el encadenado real: comunes, luego dev, qa y prod, cada raíz con
  plan, Conftest y apply del mismo plan.
- El drift diario es `plan -detailed-exitcode` con incidencia en GitHub. (Ronda de correcciones
  del 21 nov 2026: vuelve Cloud Asset Inventory, ahora construido como trabajo de recursos no
  administrados, sin correr contra GCP.)
- Las alertas van solo por correo (canales de `notification_emails`); se agregan la de retraso de
  réplica y las de consumo del SLO.
- Security Command Center se activa a mano y notifica hallazgos altos y críticos a Pub/Sub.
- La bóveda de Backup and DR vive en el proyecto de servicio, en `us-east4`, con un plan diario de
  Cloud SQL; las VM del MIG no se respaldan porque se recrean desde la plantilla.
- La conmutación ya no es "apply en us-east4": es promover la réplica con `gcloud` y aplicar la
  etapa 5 de prod con `dr_active = true`; RPO y RTO quedan como objetivos sin medir.
- Se agrega `terratest.yml`.
- Ronda de correcciones del 21 nov 2026: plan y apply separados con huella del plan, `common`
  protegido como `prod`, `plan-gate`, prueba de humo de dev, estado multirregional y VPN de DR en
  la recuperación.
- Rondas del 22 y 23 nov 2026: `check-main-tip.sh` detiene la ejecución si un commit posterior
  de `main` cambia `gcp-datacenter/` o `.github/workflows/`; los recursos no administrados se
  revisan por carpeta (`common`, `dev`, `qa` y `prod`); la vuelta a la región primaria se hace
  con `dr_teardown` en dos applies.
