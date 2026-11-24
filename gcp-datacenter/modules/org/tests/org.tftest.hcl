mock_provider "google" {}

variables {
  project_id            = "example-project-id"
  allowed_regions       = ["us-central1", "us-east4"]
  directory_customer_id = "C00000000"
}

run "ocho_politicas_en_el_proyecto" {
  command = plan

  assert {
    condition = toset(keys(google_org_policy_policy.this)) == toset([
      "compute.vmExternalIpAccess",
      "iam.disableServiceAccountKeyCreation",
      "gcp.resourceLocations",
      "compute.requireShieldedVm",
      "storage.publicAccessPrevention",
      "storage.uniformBucketLevelAccess",
      "iam.allowedPolicyMemberDomains",
      "sql.restrictPublicIp",
    ])
    error_message = "Con cliente de directorio deben existir exactamente ocho políticas (sin compute.skipDefaultNetworkCreation)."
  }
  assert {
    condition = alltrue([for k, p in google_org_policy_policy.this : (
      p.parent == "projects/example-project-id" && p.name == "projects/example-project-id/policies/${k}"
    )])
    error_message = "Las políticas van en el proyecto, con nombre projects/<id>/policies/<restricción>."
  }
  assert {
    condition     = output.policy_parent == "projects/example-project-id"
    error_message = "policy_parent debe ser projects/<id>."
  }
  assert {
    condition = alltrue([for k in [
      "iam.disableServiceAccountKeyCreation", "compute.requireShieldedVm",
      "storage.publicAccessPrevention", "storage.uniformBucketLevelAccess",
      "sql.restrictPublicIp",
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
}

run "sin_cliente_de_directorio_siete_politicas" {
  command = plan

  variables {
    directory_customer_id        = null
    additional_allowed_locations = ["us"]
  }

  assert {
    condition     = length(google_org_policy_policy.this) == 7 && !contains(keys(google_org_policy_policy.this), "iam.allowedPolicyMemberDomains")
    error_message = "Sin directory_customer_id no se crea iam.allowedPolicyMemberDomains."
  }
  assert {
    condition     = contains(google_org_policy_policy.this["gcp.resourceLocations"].spec[0].rules[0].values[0].allowed_values, "us")
    error_message = "Las ubicaciones extra se agregan a gcp.resourceLocations."
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

run "rechaza_proyecto_mal_formado" {
  command = plan

  variables {
    project_id = "projects/example"
  }

  expect_failures = [var.project_id]
}
