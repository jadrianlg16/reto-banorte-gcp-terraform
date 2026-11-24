# Controles que solo existen si el proyecto está dentro de una organización (ADR 0029 §1). Los
# aplica la persona de la etapa 0 y no el pipeline (hallazgo de R1): roles/orgpolicy.policyAdmin
# solo se puede dar en la organización y alcanza a toda ella, y un editor de la política de acceso
# puede cambiar cualquier perímetro de la organización. Ninguna cuenta del pipeline recibe esos
# roles. Sin organización los cubren las reglas de Conftest en cada PR y los pasos manuales del
# runbook 01. Que las políticas de organización y VPC-SC no se puedan usar sin organización es
# HYPOTHESIS.

# Políticas de organización aplicadas al proyecto (padre projects/<id>). Van después de las
# cuentas, sus roles y el bucket de estado: así una política nueva (dominios admitidos,
# ubicaciones) no impide crear lo que esta misma etapa necesita en el primer apply.
# VERIFICAR-EN-APPLY: que la persona que aplica pueda crearlas (roles/orgpolicy.policyAdmin en la
# organización) y que iam.allowedPolicyMemberDomains no rechace los principalSet:// de WIF ni
# los agentes de servicio de Google en los cambios de IAM posteriores de 1-base a 3-workloads.
module "org_policies" {
  source = "../../modules/org"
  count  = var.org_id == null ? 0 : 1

  project_id                   = var.project_id
  allowed_regions              = [var.primary_region, var.dr_region]
  additional_allowed_locations = var.additional_allowed_locations
  directory_customer_id        = var.directory_customer_id

  depends_on = [
    google_project_service.this,
    google_storage_bucket.state,
    module.stage_iam,
  ]
}

# Perímetro de VPC-SC opcional alrededor de todo el proyecto, siempre en dry-run: no separa
# entornos (ADR 0029 §1). Entran las nueve cuentas del pipeline por la regla de entrada. El
# nombre conserva el entorno common (<prefix>_common_sec_perimeter) que tenía en 1-base.
# VERIFICAR-EN-APPLY: que el perímetro en dry-run registre violaciones sin bloquear y que la
# persona que aplica lo cree (roles/accesscontextmanager.policyAdmin en la organización o
# policyEditor sobre la política).
module "vpc_sc" {
  source = "../../modules/vpc-sc"
  count  = var.access_policy_id == null ? 0 : 1

  prefix              = var.prefix
  environment         = "common"
  access_policy_id    = var.access_policy_id
  resources           = ["projects/${local.project_number}"]
  restricted_services = var.vpc_sc_restricted_services
  ingress_identities = concat(
    [for k in sort(keys(google_service_account.stage)) : google_service_account.stage[k].member],
    [google_service_account.read.member],
  )
  enforced = false

  depends_on = [google_project_service.this]
}
