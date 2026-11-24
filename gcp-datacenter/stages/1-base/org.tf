# Controles que solo existen si el proyecto está dentro de una organización (ADR 0029 §1). Sin
# organización los cubren las reglas de Conftest en cada PR y los pasos manuales del runbook 01.
# Que las políticas de organización y VPC-SC no se puedan usar sin organización es HYPOTHESIS.

# Políticas de organización aplicadas al proyecto (padre projects/<id>). La cuenta de 1-base
# recibe roles/orgpolicy.policyAdmin en la organización desde 0-bootstrap cuando llega org_id.
module "org_policies" {
  source = "../../modules/org"
  count  = var.org_id == null ? 0 : 1

  project_id                   = local.project_id
  allowed_regions              = [var.primary_region, var.dr_region]
  additional_allowed_locations = var.additional_allowed_locations
  directory_customer_id        = var.directory_customer_id
}

# Perímetro de VPC-SC opcional alrededor de todo el proyecto, siempre en dry-run: no separa
# entornos (ADR 0029 §1). Entran las nueve cuentas del pipeline por la regla de entrada.
# VERIFICAR-EN-APPLY: que el perímetro en dry-run registre violaciones sin bloquear y que la
# cuenta de 1-base lo cree con policyEditor sobre la política de acceso.
module "vpc_sc" {
  source = "../../modules/vpc-sc"
  count  = var.access_policy_id == null ? 0 : 1

  prefix              = var.prefix
  environment         = local.environment
  access_policy_id    = var.access_policy_id
  resources           = ["projects/${local.project_number}"]
  restricted_services = var.vpc_sc_restricted_services
  ingress_identities = concat(
    [for k in sort(keys(local.stage_service_accounts)) : "serviceAccount:${local.stage_service_accounts[k]}"],
    ["serviceAccount:${local.read_service_account}"],
  )
  enforced = false
}
