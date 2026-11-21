mock_provider "google" {
  mock_resource "google_logging_organization_sink" {
    defaults = {
      writer_identity = "serviceAccount:o000000000000-000000@gcp-sa-logging.iam.gserviceaccount.com"
    }
  }
}

variables {
  org_id                = "000000000000"
  prefix                = "bnt"
  allowed_regions       = ["us-central1", "us-east4"]
  directory_customer_id = "C00000000"
  log_sink_destination  = "storage.googleapis.com/bnt-common-ops-audit-logs"
}

run "nueve_politicas_y_sink_agregado" {
  command = plan

  assert {
    condition = toset(keys(google_org_policy_policy.this)) == toset([
      "compute.vmExternalIpAccess",
      "iam.disableServiceAccountKeyCreation",
      "gcp.resourceLocations",
      "compute.requireShieldedVm",
      "storage.publicAccessPrevention",
      "storage.uniformBucketLevelAccess",
      "compute.skipDefaultNetworkCreation",
      "iam.allowedPolicyMemberDomains",
      "sql.restrictPublicIp",
    ])
    error_message = "Deben existir exactamente las nueve políticas de organización."
  }
  assert {
    condition = alltrue([for k, p in google_org_policy_policy.this : (
      p.parent == "organizations/000000000000" && p.name == "organizations/000000000000/policies/${k}"
    )])
    error_message = "Por defecto las políticas van en la organización, con nombre <padre>/policies/<restricción>."
  }
  assert {
    condition = alltrue([for k in [
      "iam.disableServiceAccountKeyCreation", "compute.requireShieldedVm",
      "storage.publicAccessPrevention", "storage.uniformBucketLevelAccess",
      "compute.skipDefaultNetworkCreation", "sql.restrictPublicIp",
    ] : google_org_policy_policy.this[k].spec[0].rules[0].enforce == "TRUE"])
    error_message = "Las políticas booleanas deben quedar forzadas."
  }
  assert {
    condition     = google_org_policy_policy.this["compute.vmExternalIpAccess"].spec[0].rules[0].deny_all == "TRUE"
    error_message = "compute.vmExternalIpAccess debe denegar todas las IP externas."
  }
  assert {
    condition = google_org_policy_policy.this["gcp.resourceLocations"].spec[0].rules[0].values[0].allowed_values == tolist([
      "in:us-central1-locations", "in:us-east4-locations",
    ])
    error_message = "gcp.resourceLocations debe salir de allowed_regions."
  }
  assert {
    condition     = google_org_policy_policy.this["iam.allowedPolicyMemberDomains"].spec[0].rules[0].values[0].allowed_values == tolist(["C00000000"])
    error_message = "iam.allowedPolicyMemberDomains debe admitir solo el cliente de directorio."
  }
  assert {
    condition = alltrue([
      google_logging_organization_sink.this.name == "bnt-common-ops-audit-sink",
      google_logging_organization_sink.this.include_children == true,
      google_logging_organization_sink.this.org_id == "000000000000",
      google_logging_organization_sink.this.destination == var.log_sink_destination,
    ])
    error_message = "El sink debe ser agregado (include_children) y apuntar al destino."
  }
  assert {
    condition = (
      google_storage_bucket_iam_member.sink_writer["this"].bucket == "bnt-common-ops-audit-logs" &&
      google_storage_bucket_iam_member.sink_writer["this"].role == "roles/storage.objectCreator"
    )
    error_message = "La identidad del sink debe poder crear objetos en el bucket de destino."
  }
}

run "ubicaciones_extra_y_padre_de_carpeta" {
  command = plan

  variables {
    policy_parent                = "folders/111111111111"
    additional_allowed_locations = ["us"]
  }

  assert {
    condition     = alltrue([for p in google_org_policy_policy.this : p.parent == "folders/111111111111"])
    error_message = "policy_parent cambia dónde se aplican las políticas."
  }
  assert {
    condition     = contains(google_org_policy_policy.this["gcp.resourceLocations"].spec[0].rules[0].values[0].allowed_values, "us")
    error_message = "Las ubicaciones extra se agregan a gcp.resourceLocations."
  }
}

run "destino_que_no_es_bucket" {
  command = plan

  variables {
    log_sink_destination = "logging.googleapis.com/projects/bnt-common-logging/locations/global/buckets/example"
  }

  assert {
    condition     = length(google_storage_bucket_iam_member.sink_writer) == 0
    error_message = "Para destinos que no son buckets, el permiso lo asigna la etapa."
  }
}

run "rechaza_region_mal_formada" {
  command = plan

  variables {
    allowed_regions = ["US-CENTRAL1"]
  }

  expect_failures = [var.allowed_regions]
}

run "rechaza_sin_regiones" {
  command = plan

  variables {
    allowed_regions = []
  }

  expect_failures = [var.allowed_regions]
}

run "rechaza_cliente_de_directorio_mal_formado" {
  command = plan

  variables {
    directory_customer_id = "example.com"
  }

  expect_failures = [var.directory_customer_id]
}

run "rechaza_destino_mal_formado" {
  command = plan

  variables {
    log_sink_destination = "gs://bucket"
  }

  expect_failures = [var.log_sink_destination]
}
