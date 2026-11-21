# Diagrama 4: operación, continuidad y automatización

Cómo entra un cambio, cómo se detecta una falla y cómo se recupera prod en `us-east4`. Es
diseño: ningún flujo ha corrido contra GCP y los objetivos de RPO y RTO no se han medido.

```mermaid
flowchart TB
  subgraph CHG["Cambios (GitHub Actions)"]
    pr["Pull request · pr.yml<br/>check.sh: fmt, validate, tflint, checkov, terraform test<br/>policy-check.sh · docs.sh --check<br/>con GCP_ENABLED: plan por raíz, Conftest, Infracost"]
    merge["Merge a main<br/>protección de rama y aprobaciones"]
    apply["apply.yml → _terraform-root.yml por raíz<br/>plan → Conftest → apply del mismo plan<br/>1-org → 2-security → hub → dev → qa → prod"]
    prodenv["Entorno prod<br/>revisores obligatorios"]
    drift["drift.yml diario<br/>plan -detailed-exitcode<br/>incidencia con etiqueta drift"]
    tt["terratest.yml nocturno"]
  end
  pr --> merge --> apply
  apply -- "raíces de prod" --> prodenv

  wif["WIF + cuenta de servicio por etapa"]
  wif --> apply
  wif --> drift

  state[("Bucket de estado en el semilla<br/>un prefijo por etapa y entorno<br/>versionado · CMEK de la etapa 0 · bloqueo nativo")]
  apply <--> state
  drift --> state

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
    failover["Conmutación (runbook 04)<br/>promote-replica con gcloud · dr_active = true<br/>cómputo en us-east4 · backends del balanceador a us-east4<br/>objetivos RPO ≤ 15 min y RTO ≤ 4 h, sin medir"]
  end

  mon -- "alerta" --> failover
  replica --> failover
  dual --> failover
  backup --> failover
  drift -. "runbook 05" .-> merge
```

## Cómo se lee

- Todo cambio entra por PR. Sin GCP, `pr.yml` corre las revisiones estáticas, las pruebas con
  proveedores simulados, las políticas sobre los planes de ejemplo y terraform-docs; con
  `GCP_ENABLED = true` agrega el plan real, Conftest sobre él y el costo
  ([`pipeline.md`](../pipeline.md)).
- `apply.yml` aplica las raíces en serie (los spokes nunca a la vez) y cada raíz de prod espera
  la aprobación del entorno `prod`. La etapa 0 no está en el pipeline.
- `drift.yml` abre una incidencia por raíz con diferencias; la respuesta está en el
  [runbook 05](../runbooks/05-respuesta-a-drift.md).
- La recuperación de prod combina datos replicados (Cloud SQL y el bucket), respaldos en la
  región de DR y la conmutación manual del [runbook 04](../runbooks/04-conmutacion-a-dr.md).
  Memorystore y Filestore no tienen DR.

## Cambios respecto a la versión de la fase 3

- El pull request también corre `terraform test`, `policy-check.sh` y `docs.sh --check`; el plan,
  Conftest e Infracost dependen de `GCP_ENABLED`.
- El despliegue se dibuja con el encadenado real: comunes, luego dev, qa y prod, cada raíz con
  plan, Conftest y apply del mismo plan.
- El drift diario es `plan -detailed-exitcode` con incidencia en GitHub; Cloud Asset Inventory ya
  no aparece porque no se construyó.
- Las alertas van solo por correo (canales de `notification_emails`); se agregan la de retraso de
  réplica y las de consumo del SLO.
- Security Command Center se activa a mano y notifica hallazgos altos y críticos a Pub/Sub.
- La bóveda de Backup and DR vive en el proyecto de servicio, en `us-east4`, con un plan diario de
  Cloud SQL; las VM del MIG no se respaldan porque se recrean desde la plantilla.
- La conmutación ya no es "apply en us-east4": es promover la réplica con `gcloud` y aplicar la
  etapa 5 de prod con `dr_active = true`; RPO y RTO quedan como objetivos sin medir.
- Se agrega `terratest.yml`.
