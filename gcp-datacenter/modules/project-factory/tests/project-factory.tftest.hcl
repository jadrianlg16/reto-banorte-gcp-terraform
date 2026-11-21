mock_provider "google" {}

variables {
  prefix          = "bnt"
  environment     = "dev"
  name            = "app"
  folder_id       = "folders/000000000000"
  billing_account = "000000-000000-000000"
  apis            = ["container.googleapis.com"]
  labels = {
    env         = "dev"
    app         = "example"
    owner       = "example-team"
    cost_center = "example-000"
    managed_by  = "terraform"
  }
}

run "proyecto_con_nombre_y_exigencias" {
  command = plan

  assert {
    condition     = google_project.this.project_id == "bnt-dev-app"
    error_message = "El ID debe seguir <prefix>-<environment>-<name>."
  }
  assert {
    condition     = google_project.this.auto_create_network == false
    error_message = "El proyecto no debe crear la red default."
  }
  assert {
    condition     = google_project.this.labels == var.labels
    error_message = "El proyecto debe llevar las etiquetas recibidas."
  }
  assert {
    condition     = google_project.this.billing_account == "000000-000000-000000" && google_project.this.folder_id == "folders/000000000000"
    error_message = "Facturación y carpeta deben ser las indicadas."
  }
  assert {
    condition     = google_project.this.deletion_policy == "PREVENT"
    error_message = "Por defecto el proyecto se protege contra borrado."
  }
  assert {
    condition     = toset(keys(google_project_service.this)) == toset(["container.googleapis.com"])
    error_message = "Cada API debe habilitarse con su nombre como llave."
  }
  assert {
    condition     = alltrue([for s in google_project_service.this : s.disable_on_destroy == false])
    error_message = "Por defecto las APIs no se deshabilitan al destruir."
  }
  assert {
    condition     = length(google_compute_shared_vpc_host_project.this) == 0 && length(google_compute_shared_vpc_service_project.this) == 0
    error_message = "Sin Shared VPC si no se pide."
  }
}

run "sufijo_en_el_id" {
  command = plan

  variables {
    environment    = "common"
    name           = "net-hub"
    project_suffix = "x7k2"
  }

  assert {
    condition     = google_project.this.project_id == "bnt-common-net-hub-x7k2"
    error_message = "El sufijo se agrega al final con guion."
  }
  assert {
    condition     = google_project.this.name == "bnt-common-net-hub-x7k2"
    error_message = "Sin display_name, el nombre visible es el ID."
  }
}

run "host_de_shared_vpc" {
  command = plan

  variables {
    name            = "net-spoke"
    apis            = []
    shared_vpc_host = true
  }

  assert {
    condition     = length(google_compute_shared_vpc_host_project.this) == 1
    error_message = "Debe habilitar el proyecto como host."
  }
  assert {
    condition     = contains(keys(google_project_service.this), "compute.googleapis.com")
    error_message = "Shared VPC necesita la API de Compute."
  }
}

run "servicio_de_shared_vpc" {
  command = plan

  variables {
    shared_vpc_host_project = "bnt-dev-net-spoke"
  }

  assert {
    condition     = google_compute_shared_vpc_service_project.this["this"].host_project == "bnt-dev-net-spoke"
    error_message = "Debe unirse al host indicado."
  }
  assert {
    condition     = google_compute_shared_vpc_service_project.this["this"].service_project == "bnt-dev-app"
    error_message = "El proyecto de servicio es el creado."
  }
  assert {
    condition     = contains(keys(google_project_service.this), "compute.googleapis.com")
    error_message = "El proyecto de servicio necesita la API de Compute."
  }
}

run "rechaza_id_demasiado_largo" {
  command = plan

  variables {
    name           = "aplicacion-muy-larga"
    project_suffix = "abcdefgh"
  }

  expect_failures = [google_project.this]
}

run "rechaza_borrado_en_prod" {
  command = plan

  variables {
    environment     = "prod"
    deletion_policy = "DELETE"
  }

  expect_failures = [google_project.this]
}

run "rechaza_host_y_servicio_a_la_vez" {
  command = plan

  variables {
    shared_vpc_host         = true
    shared_vpc_host_project = "bnt-dev-net-spoke"
  }

  expect_failures = [google_project.this]
}

run "rechaza_etiquetas_incompletas" {
  command = plan

  variables {
    labels = { env = "dev", managed_by = "terraform" }
  }

  expect_failures = [var.labels]
}

run "rechaza_managed_by_distinto" {
  command = plan

  variables {
    labels = {
      env         = "dev"
      app         = "example"
      owner       = "example-team"
      cost_center = "example-000"
      managed_by  = "manual"
    }
  }

  expect_failures = [var.labels]
}

run "rechaza_entorno_invalido" {
  command = plan

  variables {
    environment = "staging"
  }

  expect_failures = [var.environment]
}

run "rechaza_api_mal_formada" {
  command = plan

  variables {
    apis = ["container"]
  }

  expect_failures = [var.apis]
}
