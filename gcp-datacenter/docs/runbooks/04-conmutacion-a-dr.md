# Runbook 04: conmutación de prod a la región de DR

## Objetivo

Llevar el servicio de prod de `us-central1` (`primary_region`) a `us-east4` (`dr_region`)
cuando la región primaria no está disponible: promover la réplica de Cloud SQL, crear el
cómputo en la región de DR con `dr_active = true` y apuntar los balanceadores a ella; después,
volver. Procedimiento diseñado y **sin ejecutar**: los objetivos RTO ≤ 4 h y RPO ≤ 15 min no se
han medido. El primer simulacro llena la tabla del final.

## Cuándo usarlo

Conmutar solo si se cumplen las tres:

1. Hay una falla regional confirmada en `us-central1` (Google Cloud Service Health o
   Personalized Service Health) que afecta a Cloud SQL o al cómputo de prod.
2. La recuperación estimada de la región no cabe en lo que queda del RTO de 4 h.
3. La persona responsable del incidente lo aprueba y queda registrado.

No conmutar ante:

- Corrupción lógica de datos: la réplica ya la copió. Usar PITR sobre la primaria:
  `gcloud sql instances clone <prefix>-prod-data-sql-usc1 <instancia-nueva> --point-in-time="<AAAA-MM-DDTHH:MM:SSZ>" --project=<service_project_id>`.
- Falla de una zona: Cloud SQL (`REGIONAL`), el MIG regional, GKE regional y Memorystore
  `STANDARD_HA` están diseñados para tolerarla dentro de la región.
- Un error de la aplicación.

## Prerrequisitos

- `enable_dr = true` en `stages/3-networks/envs/prod` (subredes `*_dr`, router y NAT de DR) y en
  `stages/5-workloads/envs/prod` (réplica `<prefix>-prod-data-sql-use4`, bucket de doble región
  `<prefix>-prod-data-<application>-usc1-use4`, plan de Backup for GKE en `us-east4`). Es el
  valor del ejemplo de prod.
- Lo que Terraform necesita durante la caída no depende de `us-central1` (ADR 0022): el bucket de
  estado y su llave están en la multirregión `US`/`us`; el hub tiene una segunda HA VPN en
  `us-east4` (`enable_vpn_dr = true`, valor por defecto); el balanceador interno es uno por región
  con acceso global; las imágenes de contenedor están en el repositorio multirregional de
  Artifact Registry de la aplicación (`us-docker.pkg.dev/...-images-us/...`, ADR 0024) y la
  imagen del MIG es global. Si alguna de estas no se cumple (por ejemplo, `enable_vpn_dr = false`
  o una imagen en un registro regional), este runbook no se puede ejecutar tal como está.
- Con `enable_internal_lb`, el certificado interno de `us-east4` ya está emitido: con `enable_dr`
  la etapa 5 crea su autorización DNS y su certificado desde el primer apply, sin el balanceador
  de DR (pendiente 54). Los registros de autorización de las dos regiones se crean al dar de alta
  el entorno, no en el incidente:

  ```bash
  terraform -chdir=stages/5-workloads/envs/prod output -json internal_lb_dns_authorization_records_by_region
  gcloud certificate-manager certificates describe <prefix>-prod-app-<application>-ilb-use4-cert-<sufijo> \
    --location=us-east4 --project=<service_project_id> --format="value(managed.state)"
  ```

  Esperado: `ACTIVE`. Si no lo está, el paso 7 suma la emisión del certificado al RTO.
- Identidad con los permisos de `<prefix>-tf-5-workloads` (los roles de `workloads_project_roles`
  sobre el proyecto de servicio, que da la etapa 4; incluyen `roles/cloudsql.admin`). Las personas
  solo tienen lectura y el pipeline no admite `-target`: hace falta el acceso de emergencia, que
  **no está construido** ([pendientes](../pendientes-apply.md), §5). Definirlo antes del primer
  simulacro. Para el paso 1 necesita además lo que la cuenta de la etapa 5 no tiene: leer el
  estado del hub (`roles/storage.objectViewer` sobre el prefijo `3-networks/hub/` del bucket de
  estado; la etapa 5 solo lee `2-security`, `3-networks/<env>` y `4-projects/<env>`) y ver los
  túneles y el router del hub (`roles/compute.viewer` en el proyecto `net-hub`; la etapa 5 solo
  tiene `networkViewer` en el host del spoke).
- `gcloud`, `gh`, `jq` y Terraform en la máquina de quien ejecuta, en la versión del pipeline
  (`TERRAFORM_VERSION` de los flujos, hoy 1.16.5) o mayor: el estado de estas raíces lo escribe
  el pipeline y Terraform no abre un estado escrito por una versión más nueva que la suya.
- Las variables de la raíz armadas igual que el pipeline (`_terraform-root.yml`): el ejemplo como
  `terraform.tfvars` y, encima, la llave `common` de `GCP_TFVARS_JSON` combinada con la llave
  `stages/5-workloads/envs/prod` (`common` trae, entre otros, `state_bucket`):

  ```bash
  cp stages/5-workloads/envs/prod/terraform.tfvars.example stages/5-workloads/envs/prod/terraform.tfvars
  gh variable get GCP_TFVARS_JSON |
    jq --arg r stages/5-workloads/envs/prod '(.common // {}) + (.[$r] // {})' \
    > stages/5-workloads/envs/prod/zz-ci.auto.tfvars.json
  ```

  Con `dr_active = false` y `dr_teardown = false`: los comandos de abajo pasan `-var`, que
  tiene precedencia sobre los dos archivos.
- Variables de la sesión, desde `gcp-datacenter/`:

  ```bash
  R=stages/5-workloads/envs/prod
  P=<service_project_id>               # salida service_project_ids["app"] de 4-projects/envs/prod
  HUB=<hub_project_id>                 # salida hub_project_id de stages/3-networks
  REPLICA=<prefix>-prod-data-sql-use4
  ```

## Pasos

Anotar la hora UTC de cada paso en la tabla del simulacro.

1. **Declarar el incidente y congelar el pipeline** (T0 detección, T1 decisión).

   ```bash
   gh workflow disable apply.yml
   ```

   Evita que un push a `main` aplique la configuración normal (`dr_active = false`) a mitad de
   la conmutación.

   Comprobar que on-premises sigue conectado por la VPN de DR (sesiones BGP de los túneles del
   router del hub en `us-east4`):

   ```bash
   terraform -chdir=stages/3-networks init -backend-config="bucket=<state_bucket>"
   ROUTER_DR="$(terraform -chdir=stages/3-networks output -json hub_routers | jq -r '.["us-east4"]')"
   # Solo los túneles del hub hacia on-premises (vpn_dr_tunnel_names): en modo simulado el
   # proyecto hub también tiene los túneles de onprem-sim en us-east4.
   for t in $(terraform -chdir=stages/3-networks output -json vpn_dr_tunnel_names | jq -r '.[]'); do
     gcloud compute vpn-tunnels describe "$t" --region=us-east4 --project="$HUB" \
       --format="value(name,status,detailedStatus)"
   done
   gcloud compute routers get-status "$ROUTER_DR" --region=us-east4 --project="$HUB" \
     --format="table(result.bgpPeerStatus[].name,result.bgpPeerStatus[].status)"
   ```

   Esperado: los dos túneles `ESTABLISHED` y las dos sesiones `UP`. Leer el estado de
   `stages/3-networks` también comprueba que el bucket de estado responde sin la región primaria.
   Si la VPN de DR no está arriba, on-premises no llega a nada en `us-east4`: resolverlo antes de
   seguir (punto 37 de los pendientes).

2. **Medir el retraso de la réplica** (estimación del RPO de la base).

   ```bash
   gcloud sql instances describe "$REPLICA" --project="$P" \
     --format="value(state,instanceType,masterInstanceName)"
   ```

   El retraso está en la métrica `cloudsql.googleapis.com/database/replication/replica_lag` (la
   vigila la alerta de retraso de réplica del módulo `observability`). Anotar el último valor:
   es la pérdida de datos esperada si se promueve ahora.

3. **Promover la réplica** (paso fuera de Terraform, README de la etapa 5).

   ```bash
   gcloud sql instances promote-replica "$REPLICA" --project="$P"
   gcloud sql instances describe "$REPLICA" --project="$P" --format="value(instanceType,state)"
   ```

   Esperado: `CLOUD_SQL_INSTANCE` y `RUNNABLE`. La promoción no se deshace: la instancia deja de
   replicar desde la primaria.

4. **Apuntar la aplicación a la base promovida.** Su nombre de conexión es la salida
   `sql_replica_connection_name` (`<proyecto>:us-east4:<prefix>-prod-data-sql-use4`). La
   configuración de conexión de la aplicación vive fuera de este repositorio.

5. **Cómputo y balanceadores en DR** (`dr_active = true`).

   ```bash
   terraform -chdir="$R" init -backend-config="bucket=<state_bucket>"
   terraform -chdir="$R" plan -var="dr_active=true" -out=tfplan
   ```

   Revisar el plan (ADR 0022). Debe:
   - crear `module.gke["dr"]`, `module.mig["dr"]` y `module.cloud_run["dr"]` (los habilitados);
   - agregar `module.internal_lb["dr"]` (`<prefix>-prod-app-<application>-ilb-use4`, con su IP)
     **sin tocar** `module.internal_lb["primary"]`; el certificado de `us-east4`
     (`google_certificate_manager_certificate.internal["dr"]`) ya existe y no cambia;
   - cambiar los servicios de backend de `module.external_lb["external"]` a los grupos de DR de
     Cloud Run y del MIG. Mientras `gke_lb_negs.dr` esté vacío, el backend `gke` sale del
     balanceador externo y el backend por defecto pasa al primero habilitado (`run`, `mig`);
     solo si GKE es el único backend el externo conserva los NEG primarios (no destruye el
     balanceador ni su IP).

   No debe destruir nada en `us-central1`: ni el cómputo primario ni el balanceador interno
   primario. Si propone destruir algo de la región primaria, **no aplicar** y revisar.

   Si el plan también cambia o reemplaza `module.cloud_sql.google_sql_database_instance.replica["dr"]`
   (esperado después de la promoción, pendiente 24), **no aplicar ese plan**. Aplicar solo
   cómputo, balanceadores y el enlace de Workload Identity:

   ```bash
   terraform -chdir="$R" plan -var="dr_active=true" \
     -target=module.gke -target=module.mig -target=module.cloud_run \
     -target=module.external_lb -target=module.internal_lb \
     -target=google_service_account_iam_member.workload_identity -out=tfplan
   terraform -chdir="$R" apply tfplan
   ```

   Si el plan no termina porque no puede leer recursos de la región caída, repetirlo con
   `-refresh=false` (pendiente de verificar en el simulacro). HIPÓTESIS sin comprobar: el enlace
   de Workload Identity toma el pool de `module.gke["primary"]`; si leer ese clúster falla, es uno
   de los casos que `-refresh=false` debería cubrir (punto 46).

6. **GKE** (si `enable_gke`). El clúster `<prefix>-prod-app-gke-use4` nace vacío. Desplegar la
   carga con el proceso de la aplicación (fuera de este repositorio), con la misma cuenta de
   Kubernetes anotada para Workload Identity (runbook 02, paso 4) y la imagen del repositorio de
   la aplicación; si hace falta estado del clúster, restaurar el último respaldo de Backup for
   GKE (el plan existe; la restauración no está construida en Terraform). Después, poner los NEG
   zonales del clúster de DR en `gke_lb_negs.dr` y aplicar otra vez el balanceador externo:

   ```bash
   gcloud compute network-endpoint-groups list --project="$P" --filter="zone~us-east4"
   # <negs-dr.tfvars.json>: {"gke_lb_negs": {"primary": [...los actuales...], "dr": ["<self_link>", ...]}}
   terraform -chdir="$R" plan -var="dr_active=true" -var-file=<negs-dr.tfvars.json> \
     -target=module.external_lb -out=tfplan
   terraform -chdir="$R" apply tfplan
   ```

   El plan debe volver a agregar el backend `gke` al balanceador externo con los NEG de DR.

7. **DNS y certificados.**
   - Balanceador externo: su IP global (`lb_ip_address`) y su certificado administrado no
     cambian; los registros DNS públicos de `domain_names` no se tocan.
   - Balanceador interno: el de `us-east4` es otro recurso, con otra IP; su certificado ya está
     emitido (prerrequisitos). El único paso manual es el registro DNS interno, que ninguna etapa
     administra (la zona no está en este repositorio y la cuenta de la etapa 5 no tiene
     `dns.admin`). Con `dr_active = true` aplicado, la salida `internal_lb_dns_records` ya da los
     registros de `us-east4`:

     ```bash
     terraform -chdir="$R" output -json internal_lb_dns_records
     # {"<dominio>": {"type": "A", "rrdatas": ["<IP del interno de us-east4>"]}, ...}
     ```

     En el DNS interno (fuera de este repositorio), cambiar el registro A de cada dominio a esa
     IP. El tiempo de propagación depende del TTL de esos registros: bajarlo de antemano acorta el
     RTO (propuesta). Las dos reglas de reenvío tienen acceso global: on-premises llega a la IP de
     DR por cualquiera de las dos VPN (punto 44).

8. **Datos que no conmutan.**
   - Bucket de la aplicación: es de doble región (`us-central1` + `us-east4`) con turbo
     replication; está diseñado para seguir disponible sin acción. Según la documentación de
     Google, turbo replication tiene un objetivo de 15 minutos para replicar objetos nuevos.
   - Memorystore y Filestore solo existen en la región primaria: no hay caché ni NFS en DR y sus
     datos no se replican (limitación conocida).

9. **Validar** (sección siguiente) y comunicar el fin de la conmutación (T fin = RTO medido).

## Verificación

```bash
curl -sS -o /dev/null -w "%{http_code}\n" https://<dominio>/<ruta-de-salud>
# Solo mig y gke: los backends sin servidor (run) no admiten verificaciones de salud.
gcloud compute backend-services get-health <prefix>-prod-app-<application>-xlb-be-<mig|gke> \
  --global --project="$P"
gcloud run services describe <prefix>-prod-app-run-use4 --region=us-east4 --project="$P" \
  --format="value(status.conditions[0].type,status.conditions[0].status)"
terraform -chdir="$R" output active_region            # us-east4
terraform -chdir="$R" output -json gke_cluster_names  # incluye us-east4 si enable_gke
terraform -chdir="$R" output internal_lb_ip_address    # la IP del interno de us-east4
gcloud storage buckets describe "gs://<prefix>-prod-data-<application>-usc1-use4" \
  --format="value(location,rpo)"
```

- Los backends `mig` y `gke` de la región de DR están `HEALTHY`. El balanceador no verifica la
  salud de Cloud Run (NEG sin servidor, según la documentación de Google): su servicio de DR
  debe estar `Ready True` y la ruta de Cloud Run debe responder por el `curl`. La verificación
  de disponibilidad del módulo `observability` vuelve a verde.
- Desde on-premises, el nombre de `internal_domain_names` resuelve a la IP de `us-east4` y
  responde por HTTPS.
- La aplicación escribe y lee en la base promovida.
- Anotar RPO observado (retraso del paso 2 y, si se puede, la última transacción perdida) y RTO
  (T0 a fin del paso 9).

## Reversión (vuelta a la región primaria)

Esbozo; se detalla después del primer simulacro.

1. Con `us-central1` de vuelta, crear una réplica de la instancia promovida en `us-central1`
   (fuera de Terraform) y esperar a que alcance a la primaria actual.
2. En una ventana acordada: detener escrituras, promover esa réplica, apuntar la aplicación a
   ella.
3. Reconciliar el estado de `cloud_sql` en la etapa 5: los nombres de las instancias ya no
   coinciden con lo que espera el módulo (`<prefix>-prod-data-sql-usc1` como primaria,
   `-use4` como réplica), y un nombre borrado de Cloud SQL no se puede reusar de inmediato.
   Diseñar con `terraform state rm`/`import` en un PR revisado; no improvisarlo en el incidente.
4. Mover el registro DNS interno de vuelta a la IP del balanceador interno de `us-central1`
   (que nunca se destruyó): `terraform -chdir="$R" output -json internal_lb_ip_addresses`,
   clave `us-central1`.
5. **Quitar la protección del cómputo de DR** (`dr_teardown`). En prod el clúster de GKE y el
   servicio de Cloud Run tienen la protección contra borrado fija y el proveedor 6.50.0 se niega
   a destruirlos mientras el estado la tenga en `true` (lee la del estado al borrar; pendiente
   52). Primer apply, todavía con `dr_active = true` y con el mismo archivo de NEG de DR del paso
   6 de la conmutación (si `enable_gke`; sin él, `gke_lb_negs.dr` queda vacío y el plan quita el
   backend `gke` del externo):

   ```bash
   terraform -chdir="$R" plan -var="dr_active=true" -var="dr_teardown=true" \
     -var-file=<negs-dr.tfvars.json> -out=tfplan
   terraform -chdir="$R" apply tfplan
   ```

   El plan solo debe cambiar en el lugar `deletion_protection` a `false` en
   `module.gke["dr"]` y `module.cloud_run["dr"]` (los habilitados). En Cloud Run el cambio es un
   PATCH del servicio de DR vivo: en este apply no se cambia ninguna otra variable (imagen,
   escalado). Si toca algo de `us-central1`, destruye algo o cambia otra cosa, **no aplicar**.
   `dr_teardown = true` solo se admite con `dr_active = true` (validación).
6. **Retirar el cómputo de DR.** Segundo apply, con `dr_active = false` y `dr_teardown = false`
   juntos (los valores de los archivos de variables), sin el archivo de NEG de DR:

   ```bash
   terraform -chdir="$R" plan -var="dr_active=false" -var="dr_teardown=false" -out=tfplan
   terraform -chdir="$R" apply tfplan
   ```

   El plan vuelve los backends del externo a la región primaria (con GKE si
   `gke_lb_negs.primary` tiene NEG) y destruye el cómputo de DR (`module.gke["dr"]`,
   `module.mig["dr"]`, `module.cloud_run["dr"]`) y solo `module.internal_lb["dr"]`; el borrado
   usa la protección `false` que dejó el paso 5 en el estado. No destruye la réplica de Cloud
   SQL, el certificado interno de DR ni los planes de respaldo: dependen de `enable_dr` y
   `enable_backup`, no de `dr_active`. Si el plan cambia o reemplaza recursos de `cloud_sql`, la
   reconciliación del punto 3 no está hecha: **no aplicar**. Las pruebas de la etapa planean
   estos dos pasos con proveedores simulados (`prod_vuelta_paso_1_retiro_del_computo_de_dr`,
   `prod_vuelta_paso_2_sin_dr_active`) y que `dr_teardown` sin `dr_active` se rechace
   (`rechaza_dr_teardown_sin_dr_active`).
7. Reactivar el pipeline (`gh workflow enable apply.yml`) y confirmar un `plan` sin cambios.

## Objetivos y lo que aporta cada paso

| Objetivo | Mecanismo | Pasos | Medido |
|---|---|---|---|
| RPO ≤ 15 min, base | Réplica asíncrona entre regiones; alerta de retraso de réplica | 2 y 3 | No |
| RPO ≤ 15 min, objetos | Bucket de doble región con turbo replication | 8 | No |
| RPO, caché y NFS | Ninguno: Memorystore y Filestore sin DR | 8 | No aplica |
| RPO, configuración de GKE | Backup for GKE diario en `us-east4` (pérdida de hasta un día de configuración) | 6 | No |
| RTO ≤ 4 h | Suma de detección y decisión, promoción, apply con `dr_active`, despliegue en GKE, registro DNS interno (el certificado de DR ya está emitido), validación | 1 a 9 | No |
| Conectividad con on-premises | Segunda HA VPN en `us-east4`, balanceador interno con acceso global | 1 y 7 | No |

## Simulacro: lista y registro de tiempos

Un simulacro en prod promueve la réplica de verdad y obliga a hacer la vuelta. Alternativa
(propuesta): un entorno con `enable_dr = true` creado para el simulacro. Antes de empezar:

- [ ] Ventana aprobada y comunicada; responsable del incidente nombrado.
- [ ] Acceso de emergencia definido y probado.
- [ ] `terraform plan -detailed-exitcode` de `5-workloads/envs/prod` en 0 antes de empezar.
- [ ] Alerta de retraso de réplica sin disparar; último valor anotado.
- [ ] Imágenes de Cloud Run y GKE en el repositorio multirregional de la aplicación (Binary
      Authorization rechaza otras).
- [ ] VPN de DR con sus dos sesiones BGP `UP` (paso 1).
- [ ] Certificado interno de `us-east4` en `ACTIVE` (prerrequisitos) y acceso al DNS interno
      para cambiar los registros A de `internal_domain_names`.
- [ ] Procedimiento de despliegue de la carga en el clúster de DR a mano.
- [ ] Plan de vuelta revisado.

| # | Paso | Inicio (UTC) | Fin (UTC) | Duración | Responsable | Resultado y notas |
|---|---|---|---|---|---|---|
| 0 | Detección (T0) |  |  |  |  |  |
| 1 | Decisión, congelamiento del pipeline y VPN de DR comprobada (T1) |  |  |  |  |  |
| 2 | Retraso de réplica medido (RPO estimado) |  |  |  |  | lag = |
| 3 | Promoción de la réplica |  |  |  |  |  |
| 4 | Aplicación apuntando a la base promovida |  |  |  |  |  |
| 5 | Plan y apply con `dr_active = true` |  |  |  |  | ¿con `-target`? |
| 6 | GKE: despliegue, restauración y NEG |  |  |  |  |  |
| 7 | Registro DNS interno (certificado de DR ya emitido) |  |  |  |  |  |
| 8 | Comprobación de bucket, caché y NFS |  |  |  |  |  |
| 9 | Validación y fin (RTO = fin − T0) |  |  |  |  | RTO = |
| 10 | Vuelta a la región primaria |  |  |  |  |  |

Al terminar: anotar el resultado en [`pendientes-apply.md`](../pendientes-apply.md) (fecha,
RTO y RPO medidos) y corregir este runbook con lo aprendido.
