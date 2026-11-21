# Lecturas de etapas anteriores (§6.1): solo 1-org, 2-security y 3-networks/<environment>.
# Los nombres y tipos de cada salida son los de las tablas de §7.1, §7.2 y §7.4.

data "terraform_remote_state" "org" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "1-org"
  }

  lifecycle {
    postcondition {
      condition     = can(regex("^folders/[0-9]+$", self.outputs.folder_ids[var.environment]))
      error_message = "El estado de 1-org no tiene folder_ids[environment] con la forma folders/<número>."
    }
  }
}

data "terraform_remote_state" "security" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "2-security"
  }

  lifecycle {
    postcondition {
      condition = alltrue([
        for use in keys(local.kms_consumers) :
        can(self.outputs.kms_key_ids[var.environment][var.primary_region][use]) if use != "artifacts"
      ])
      error_message = "El estado de 2-security no tiene en kms_key_ids[environment][primary_region] todas las llaves que usan los agentes (backup, compute, filestore, gke, redis, run, sql, storage)."
    }
    postcondition {
      condition     = can(self.outputs.kms_key_ids[var.environment][var.artifact_registry_location]["artifacts"])
      error_message = "El estado de 2-security no tiene kms_key_ids[environment][artifact_registry_location][\"artifacts\"] (llave del repositorio de imágenes)."
    }
    postcondition {
      condition = alltrue(flatten([
        for a in values(var.applications) : [
          for name in a.secrets : can(self.outputs.secret_ids[var.environment][name])
        ]
      ]))
      error_message = "Algún secreto de applications[*].secrets no existe en secret_ids[environment] del estado de 2-security."
    }
  }
}

data "terraform_remote_state" "network" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "3-networks/${var.environment}"
  }

  lifecycle {
    postcondition {
      condition     = alltrue([for k in ["app", "run"] : contains(keys(self.outputs.subnets), k)])
      error_message = "El estado de 3-networks/<environment> no tiene las subredes app y run."
    }
    postcondition {
      condition     = alltrue([for k in ["lb_backend", "iap_ssh"] : can(regex("^tagValues/[0-9]+$", self.outputs.secure_tags[k]))])
      error_message = "El estado de 3-networks/<environment> no tiene secure_tags lb_backend e iap_ssh como tagValues/<id>."
    }
  }
}

locals {
  # 1-org: folder_ids (map(string), llaves common, dev, qa, prod → folders/…).
  folder_id = data.terraform_remote_state.org.outputs.folder_ids[var.environment]

  # 2-security: kms_key_ids (map(map(map(string))) [entorno][ubicación][uso]),
  # secret_ids (map(map(string)) [entorno][nombre]), perimeter_name (string),
  # vpc_sc_enforced (bool).
  kms_key_ids     = data.terraform_remote_state.security.outputs.kms_key_ids[var.environment]
  secret_ids      = lookup(data.terraform_remote_state.security.outputs.secret_ids, var.environment, {})
  perimeter_name  = data.terraform_remote_state.security.outputs.perimeter_name
  vpc_sc_enforced = data.terraform_remote_state.security.outputs.vpc_sc_enforced

  # 3-networks/<environment>: host_project_id (string), subnets (map(object) llave de §5 →
  # { self_link, name, region, cidr, secondary_ranges }), secure_tags (map(string) llaves
  # lb_backend, iap_ssh → tagValues/…).
  host_project_id = data.terraform_remote_state.network.outputs.host_project_id
  subnets         = data.terraform_remote_state.network.outputs.subnets
  secure_tags     = data.terraform_remote_state.network.outputs.secure_tags
}
