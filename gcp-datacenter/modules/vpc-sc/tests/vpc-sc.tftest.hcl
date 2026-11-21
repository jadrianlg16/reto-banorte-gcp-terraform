# Pruebas unitarias sin GCP: proveedor simulado y solo plan. Casi todas pasan
# access_policy_id para que el nombre completo del perímetro se conozca en el plan.

mock_provider "google" {}

variables {
  org_id           = "000000000000"
  prefix           = "bnt"
  environment      = "prod"
  access_policy_id = "123456789"
  resources        = ["projects/111111111111"]
  restricted_services = [
    "storage.googleapis.com",
    "sqladmin.googleapis.com",
  ]
  ingress_identities = ["serviceAccount:bnt-tf-4-projects@example-seed-project.iam.gserviceaccount.com"]
}

run "dry_run_por_defecto" {
  command = plan

  assert {
    condition     = google_access_context_manager_service_perimeter.this.name == "accessPolicies/123456789/servicePerimeters/bnt_prod_sec_perimeter"
    error_message = "El perímetro no sigue <prefix>_<env>_sec_perimeter dentro de la política."
  }
  assert {
    condition     = google_access_context_manager_service_perimeter.this.use_explicit_dry_run_spec == true
    error_message = "Por defecto el perímetro debe estar en dry-run (ADR 0009)."
  }
  assert {
    condition     = length(google_access_context_manager_service_perimeter.this.status) == 0 && length(google_access_context_manager_service_perimeter.this.spec) == 1
    error_message = "En dry-run la configuración va solo en spec."
  }
  assert {
    condition     = contains(google_access_context_manager_service_perimeter.this.spec[0].restricted_services, "storage.googleapis.com")
    error_message = "Falta storage.googleapis.com en los servicios restringidos."
  }
  assert {
    condition     = google_access_context_manager_service_perimeter.this.perimeter_type == "PERIMETER_TYPE_REGULAR"
    error_message = "El perímetro debe ser regular."
  }
  assert {
    condition     = contains(google_access_context_manager_service_perimeter.this.spec[0].ingress_policies[0].ingress_from[0].identities, "serviceAccount:bnt-tf-4-projects@example-seed-project.iam.gserviceaccount.com")
    error_message = "Falta la regla de entrada para las cuentas del pipeline."
  }
  assert {
    condition     = length(google_access_context_manager_service_perimeter_dry_run_resource.this) == 1 && length(google_access_context_manager_service_perimeter_resource.this) == 0
    error_message = "En dry-run los proyectos entran con el recurso de dry-run."
  }
  assert {
    condition     = google_access_context_manager_service_perimeter_dry_run_resource.this["projects/111111111111"].perimeter_name == "accessPolicies/123456789/servicePerimeters/bnt_prod_sec_perimeter"
    error_message = "El alta del proyecto debe apuntar al perímetro."
  }
  assert {
    condition     = length(google_access_context_manager_access_policy.this) == 0
    error_message = "Con access_policy_id no se crea política."
  }
  assert {
    condition     = output.perimeter_name == "accessPolicies/123456789/servicePerimeters/bnt_prod_sec_perimeter" && output.access_policy_id == "123456789"
    error_message = "Las salidas no coinciden con el perímetro y la política."
  }
}

run "forzado" {
  command = plan

  variables {
    enforced = true
    egress_policies = [{
      identity_type = "ANY_SERVICE_ACCOUNT"
      resources     = ["projects/222222222222"]
      operations = {
        "storage.googleapis.com" = ["google.storage.objects.get"]
        "*"                      = []
      }
    }]
  }

  assert {
    condition     = google_access_context_manager_service_perimeter.this.use_explicit_dry_run_spec == false
    error_message = "Forzado no usa spec explícito."
  }
  assert {
    condition     = length(google_access_context_manager_service_perimeter.this.status) == 1 && length(google_access_context_manager_service_perimeter.this.spec) == 0
    error_message = "Forzado: la configuración va solo en status."
  }
  assert {
    condition     = length(google_access_context_manager_service_perimeter.this.status[0].egress_policies) == 1
    error_message = "Falta la regla de salida."
  }
  assert {
    condition     = length(google_access_context_manager_service_perimeter_resource.this) == 1 && length(google_access_context_manager_service_perimeter_dry_run_resource.this) == 0
    error_message = "Forzado: los proyectos entran con el recurso normal."
  }
  assert {
    condition     = output.enforced == true
    error_message = "La salida enforced debe reflejar el modo."
  }
}

run "crea_politica_si_no_hay" {
  command = plan

  variables {
    access_policy_id = null
  }

  assert {
    condition     = length(google_access_context_manager_access_policy.this) == 1
    error_message = "Sin access_policy_id se debe crear la política."
  }
  assert {
    condition     = google_access_context_manager_access_policy.this[0].parent == "organizations/000000000000" && google_access_context_manager_access_policy.this[0].title == "bnt-org-access-policy"
    error_message = "La política debe colgar de la organización con el título por defecto."
  }
}

run "nombre_explicito" {
  command = plan

  variables {
    perimeter_name = "bnt_prod_data"
  }

  assert {
    condition     = google_access_context_manager_service_perimeter.this.title == "bnt_prod_data"
    error_message = "No se respetó perimeter_name."
  }
}

run "rechaza_sin_storage" {
  command = plan

  variables {
    restricted_services = ["bigquery.googleapis.com"]
  }

  expect_failures = [var.restricted_services]
}

run "rechaza_recurso_con_id_de_proyecto" {
  command = plan

  variables {
    resources = ["projects/example-project"]
  }

  expect_failures = [var.resources]
}

run "rechaza_identidad_user" {
  command = plan

  variables {
    ingress_identities = ["user:alguien@example.com"]
  }

  expect_failures = [var.ingress_identities]
}

run "rechaza_nombre_con_guion" {
  command = plan

  variables {
    perimeter_name = "bnt-prod-perimeter"
  }

  expect_failures = [var.perimeter_name]
}

run "rechaza_salida_sin_identidad" {
  command = plan

  variables {
    egress_policies = [{
      resources  = ["*"]
      operations = { "storage.googleapis.com" = [] }
    }]
  }

  expect_failures = [var.egress_policies]
}
