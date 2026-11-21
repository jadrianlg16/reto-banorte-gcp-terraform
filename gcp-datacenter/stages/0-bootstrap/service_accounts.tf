# Cuentas de servicio de las etapas 1 a 5 (ADR 0017: <prefix>-tf-<etapa>), sus roles de
# organización, facturación y proyecto semilla, y los permisos condicionados sobre el bucket
# de estado (§6.2).
#
# Todo sale de local.stages, que codifica UNA sola vez la tabla de §6.1 (prefijos que escribe
# cada cuenta y prefijos que lee además) junto con los roles de nivel organización y
# facturación de cada etapa. Los roles sobre carpetas y proyectos que todavía no existen
# (carpetas de entorno, proyectos de common) los da la etapa que los crea: 1-org (ver su README).

locals {
  environments = ["dev", "qa", "prod"]

  stages = {
    "1-org" = {
      description = "Etapa 1: carpetas, proyectos de common, políticas de organización, IAM por grupos, sink, SCC y presupuesto."
      writes      = ["1-org"]
      reads       = ["0-bootstrap"]
      org_roles = [
        "roles/iam.securityAdmin",
        "roles/logging.configWriter",
        "roles/orgpolicy.policyAdmin",
        "roles/resourcemanager.folderAdmin",
        "roles/resourcemanager.organizationViewer",
        "roles/resourcemanager.projectCreator",
        "roles/securitycenter.notificationConfigEditor",
      ]
      billing_roles = ["roles/billing.costsManager", "roles/billing.user"]
    }
    "2-security" = {
      description = "Etapa 2: llaves KMS, contenedores de secretos y perímetro de VPC Service Controls."
      writes      = ["2-security"]
      reads       = ["0-bootstrap", "1-org"]
      org_roles = [
        "roles/accesscontextmanager.policyAdmin",
        "roles/resourcemanager.organizationViewer",
      ]
      billing_roles = []
    }
    "3-networks" = {
      description = "Etapa 3: VPC hub, spokes, conectividad híbrida, DNS y política de firewall jerárquica."
      # El hub escribe 3-networks/hub y cada spoke 3-networks/<env>; los spokes leen el hub,
      # que ya está dentro de los prefijos que escribe la misma cuenta.
      writes = concat(["3-networks/hub"], [for e in local.environments : "3-networks/${e}"])
      reads  = ["0-bootstrap", "1-org"]
      org_roles = [
        "roles/compute.orgFirewallPolicyAdmin",
        "roles/compute.orgSecurityResourceAdmin",
        "roles/resourcemanager.organizationViewer",
      ]
      billing_roles = ["roles/billing.user"]
    }
    "4-projects" = {
      description = "Etapa 4: proyectos de servicio, cuentas de ejecución y permisos de llaves y secretos."
      writes      = [for e in local.environments : "4-projects/${e}"]
      reads       = concat(["1-org", "2-security"], [for e in local.environments : "3-networks/${e}"])
      org_roles   = ["roles/resourcemanager.organizationViewer"]
      billing_roles = [
        "roles/billing.user",
      ]
    }
    "5-workloads" = {
      description = "Etapa 5: cargas de trabajo en los proyectos de servicio."
      writes      = [for e in local.environments : "5-workloads/${e}"]
      reads = concat(
        ["1-org", "2-security"],
        [for e in local.environments : "3-networks/${e}"],
        [for e in local.environments : "4-projects/${e}"],
      )
      org_roles     = []
      billing_roles = []
    }
  }

  # Recurso de IAM del bucket y de sus objetos, como los evalúa una condición de IAM.
  state_bucket_resource = "projects/_/buckets/${local.state_bucket_name}"

  # storage.objects.list se evalúa sobre el bucket, no sobre un objeto: cada condición empieza
  # con el tipo Bucket para que el backend pueda listar (§6.2). Consecuencia aceptada: toda
  # cuenta de etapa ve los nombres de los objetos del bucket, no su contenido.
  state_list_clause = "resource.type == \"storage.googleapis.com/Bucket\""

  # Cláusula por prefijo. La barra final da coincidencia exacta de prefijo: "3-networks/hub/"
  # no coincide con un hermano como "3-networks/hub2/", ni "1-org/" con "1-org-otro/".
  state_prefix_clause = {
    for p in distinct(flatten([for s in values(local.stages) : concat(s.writes, s.reads)])) :
    p => "resource.name.startsWith(\"${local.state_bucket_resource}/objects/${p}/\")"
  }

  # VERIFICAR-EN-APPLY (§6.2, pendiente 1): que init/plan/apply del backend gcs funcionen con
  # estas condiciones. Alternativa documentada: carpetas administradas de Cloud Storage con IAM
  # propio por prefijo.

  # objectAdmin: solo los objetos de los prefijos propios (columna Prefijo de §6.1).
  state_admin_expression = {
    for k, s in local.stages : k => join(" || ", concat(
      [local.state_list_clause],
      [for p in s.writes : local.state_prefix_clause[p]],
    ))
  }

  # objectViewer: los prefijos de la columna "Lee además" de §6.1.
  state_viewer_expression = {
    for k, s in local.stages : k => join(" || ", concat(
      [local.state_list_clause],
      [for p in s.reads : local.state_prefix_clause[p]],
    ))
  }

  # Principal de WIF: cualquier ejecución del repositorio autorizado (§6.3).
  github_principal_set = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"

  # Todas las llaves (key) son fijas en el plan: el miembro y algunos recursos (correo y
  # nombre de las cuentas) solo se conocen después del apply.
  stage_bindings = concat(
    flatten([
      for k, s in local.stages : [
        for r in s.org_roles : {
          key      = "org|${k}|${r}"
          scope    = "organization"
          resource = var.org_id
          role     = r
          member   = google_service_account.stage[k].member
        }
      ]
    ]),
    flatten([
      for k, s in local.stages : [
        for r in s.billing_roles : {
          key      = "billing|${k}|${r}"
          scope    = "billing_account"
          resource = var.billing_account
          role     = r
          member   = google_service_account.stage[k].member
        }
      ]
    ]),
    [
      # Proyecto de cuota de las llamadas de las etapas (billing_project en sus proveedores).
      for k, s in local.stages : {
        key      = "seed|${k}|roles/serviceusage.serviceUsageConsumer"
        scope    = "project"
        resource = module.seed_project.project_id
        role     = "roles/serviceusage.serviceUsageConsumer"
        member   = google_service_account.stage[k].member
      }
    ],
    [
      for k, s in local.stages : {
        key      = "state|${k}|roles/storage.objectAdmin"
        scope    = "storage_bucket"
        resource = google_storage_bucket.state.name
        role     = "roles/storage.objectAdmin"
        member   = google_service_account.stage[k].member
        condition = {
          title       = "tfstate-${k}-escritura"
          description = "Solo los objetos de los prefijos de estado de ${k} (§6.2)."
          expression  = local.state_admin_expression[k]
        }
      }
    ],
    [
      for k, s in local.stages : {
        key      = "state|${k}|roles/storage.objectViewer"
        scope    = "storage_bucket"
        resource = google_storage_bucket.state.name
        role     = "roles/storage.objectViewer"
        member   = google_service_account.stage[k].member
        condition = {
          title       = "tfstate-${k}-lectura"
          description = "Listado del bucket y lectura de los prefijos que ${k} lee además (§6.1)."
          expression  = local.state_viewer_expression[k]
        }
      }
    ],
    [
      # Solo el repositorio autorizado puede tomar la identidad de cada cuenta (§6.3).
      for k, s in local.stages : {
        key      = "wif|${k}|roles/iam.workloadIdentityUser"
        scope    = "service_account"
        resource = google_service_account.stage[k].name
        role     = "roles/iam.workloadIdentityUser"
        member   = local.github_principal_set
      }
    ],
  )
}

resource "google_service_account" "stage" {
  for_each = local.stages

  project      = module.seed_project.project_id
  account_id   = "${var.prefix}-tf-${each.key}"
  display_name = "Terraform ${each.key}"
  description  = each.value.description
}

module "stage_iam" {
  source = "../../modules/iam"

  bindings = local.stage_bindings
}

# Rol personalizado para la etapa 4: solo leer y cambiar el IAM de llaves KMS y secretos del
# proyecto security (§7.5: permisos de llaves a los agentes de servicio y de lectura de
# secretos), sin poder administrar, usar ni destruir llaves o secretos. Lo crea esta etapa
# porque crear roles de organización exige roles/iam.organizationRoleAdmin, que ninguna
# cuenta de etapa tiene; la etapa 2 lo asigna sobre el proyecto security.
# VERIFICAR-EN-APPLY: que todos los permisos estén admitidos en roles personalizados.
resource "google_organization_iam_custom_role" "kms_secret_iam_granter" {
  org_id      = var.org_id
  role_id     = "${var.prefix}TfKmsSecretIamGranter"
  title       = "Terraform: IAM de llaves KMS y secretos"
  description = "Leer y asignar IAM de llaves KMS y secretos (etapa 4). Sin administrar ni usar las llaves."
  stage       = "GA"
  permissions = [
    "cloudkms.cryptoKeys.get",
    "cloudkms.cryptoKeys.getIamPolicy",
    "cloudkms.cryptoKeys.list",
    "cloudkms.cryptoKeys.setIamPolicy",
    "cloudkms.keyRings.get",
    "cloudkms.keyRings.list",
    "secretmanager.secrets.get",
    "secretmanager.secrets.getIamPolicy",
    "secretmanager.secrets.list",
    "secretmanager.secrets.setIamPolicy",
  ]
}
