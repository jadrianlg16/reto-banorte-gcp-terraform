# Pruebas unitarias sin GCP: proveedor simulado y solo plan.

mock_provider "google" {}

variables {
  project_id      = "example-prod-app"
  prefix          = "bnt"
  environment     = "prod"
  region          = "us-central1"
  image           = "us-central1-docker.pkg.dev/example-prod-app/apps/api:1.0.0"
  network         = "https://www.googleapis.com/compute/v1/projects/example-prod-net-spoke/global/networks/bnt-prod-net-vpc"
  subnet          = "https://www.googleapis.com/compute/v1/projects/example-prod-net-spoke/regions/us-central1/subnetworks/bnt-prod-net-run-usc1"
  service_account = "bnt-prod-app-run@example-prod-app.iam.gserviceaccount.com"
  kms_key         = "projects/example-common-security/locations/us-central1/keyRings/bnt-prod-sec-kr-usc1/cryptoKeys/compute"
  invokers        = ["group:example-app-callers@example.com"]

  labels = {
    env         = "prod"
    app         = "app"
    owner       = "plataforma"
    cost_center = "ti-001"
    managed_by  = "terraform"
  }
}

run "nombres_siguen_la_convencion" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_service.this.name == "bnt-prod-app-run-usc1"
    error_message = "El nombre del servicio no sigue <prefix>-<env>-app-<name>-<región>."
  }
  assert {
    condition     = google_compute_region_network_endpoint_group.this.name == "bnt-prod-app-run-usc1-neg"
    error_message = "El nombre del NEG no sigue la convención."
  }
}

run "exige_configuracion_de_la_especificacion" {
  command = plan

  # Solo tráfico interno y del balanceador.
  assert {
    condition     = google_cloud_run_v2_service.this.ingress == "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
    error_message = "La entrada debe ser solo interna y del balanceador."
  }
  assert {
    condition     = google_cloud_run_v2_service.this.invoker_iam_disabled == false
    error_message = "La verificación de IAM del invocador debe quedar activa."
  }
  # Cuenta de servicio propia y CMEK.
  assert {
    condition     = google_cloud_run_v2_service.this.template[0].service_account == var.service_account
    error_message = "El servicio debe usar su cuenta de servicio propia."
  }
  assert {
    condition     = google_cloud_run_v2_service.this.template[0].encryption_key == var.kms_key
    error_message = "El servicio debe cifrarse con la llave CMEK."
  }
  # Salida directa a la VPC compartida, con rutas de recurso.
  assert {
    condition     = google_cloud_run_v2_service.this.template[0].vpc_access[0].network_interfaces[0].subnetwork == "projects/example-prod-net-spoke/regions/us-central1/subnetworks/bnt-prod-net-run-usc1"
    error_message = "La subred de la salida directa a la VPC no es la esperada."
  }
  assert {
    condition     = google_cloud_run_v2_service.this.template[0].vpc_access[0].network_interfaces[0].network == "projects/example-prod-net-spoke/global/networks/bnt-prod-net-vpc"
    error_message = "La red de la salida directa a la VPC no es la esperada."
  }
  assert {
    condition     = output.subnetwork == "projects/example-prod-net-spoke/regions/us-central1/subnetworks/bnt-prod-net-run-usc1" && output.kms_key == var.kms_key
    error_message = "subnetwork y kms_key deben publicar la subred y la llave del servicio."
  }
  assert {
    condition     = google_cloud_run_v2_service.this.template[0].vpc_access[0].egress == "ALL_TRAFFIC"
    error_message = "Por defecto toda la salida debe pasar por la VPC."
  }
  # Invocadores explícitos, nunca públicos.
  assert {
    condition     = alltrue([for m in google_cloud_run_v2_service_iam_member.invoker : m.member != "allUsers" && m.member != "allAuthenticatedUsers" && m.role == "roles/run.invoker"])
    error_message = "No debe haber invocadores públicos."
  }
  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.invoker) == 1
    error_message = "Debe existir un invocador por cada elemento de invokers."
  }
  # NEG sin servidor para el balanceador.
  assert {
    condition     = google_compute_region_network_endpoint_group.this.network_endpoint_type == "SERVERLESS" && google_compute_region_network_endpoint_group.this.cloud_run[0].service == "bnt-prod-app-run-usc1"
    error_message = "El NEG sin servidor debe apuntar al servicio."
  }
  # Etiquetas y protección contra borrado.
  assert {
    condition     = google_cloud_run_v2_service.this.labels["managed_by"] == "terraform" && google_cloud_run_v2_service.this.labels["env"] == "prod"
    error_message = "El servicio debe llevar las etiquetas."
  }
  assert {
    condition     = google_cloud_run_v2_service.this.deletion_protection == true
    error_message = "En prod la protección contra borrado debe estar activa."
  }
  assert {
    condition     = google_cloud_run_v2_service.this.binary_authorization[0].use_default == true
    error_message = "Binary Authorization debe estar activa por defecto."
  }
}

run "secretos_por_referencia" {
  command = plan

  variables {
    secret_env        = { DB_CONFIG = { secret = "projects/example-common-security/secrets/bnt-prod-sec-db-config" } }
    health_check_path = "/healthz"
  }

  assert {
    condition = anytrue([
      for e in google_cloud_run_v2_service.this.template[0].containers[0].env : e.name == "DB_CONFIG" && e.value_source[0].secret_key_ref[0].version == "latest"
    ])
    error_message = "El secreto debe llegar por referencia a Secret Manager."
  }
  assert {
    condition     = google_cloud_run_v2_service.this.template[0].containers[0].liveness_probe[0].http_get[0].path == "/healthz"
    error_message = "La sonda de vida debe usar health_check_path."
  }
}

run "publico_via_balanceador_sin_allusers" {
  command = plan

  variables {
    public_via_load_balancer = true
    invokers                 = []
  }

  # ADR 0020: la entrada no cambia; solo se desactiva la verificación de IAM del invocador.
  assert {
    condition     = google_cloud_run_v2_service.this.ingress == "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
    error_message = "Con public_via_load_balancer la entrada debe seguir siendo interna y del balanceador."
  }
  assert {
    condition     = google_cloud_run_v2_service.this.invoker_iam_disabled == true
    error_message = "Con public_via_load_balancer la verificación de IAM del invocador debe desactivarse."
  }
  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.invoker) == 0
    error_message = "public_via_load_balancer no debe conceder run.invoker a nadie (nunca allUsers)."
  }
}

run "rechaza_invocador_publico" {
  command = plan

  variables {
    invokers = ["allUsers"]
  }

  expect_failures = [var.invokers]
}

run "rechaza_invocador_user" {
  command = plan

  variables {
    invokers = ["user:alguien@example.com"]
  }

  expect_failures = [var.invokers]
}

run "rechaza_salida_parcial_en_prod" {
  command = plan

  variables {
    vpc_egress = "PRIVATE_RANGES_ONLY"
  }

  expect_failures = [var.vpc_egress]
}

run "rechaza_latest_en_prod" {
  command = plan

  variables {
    image = "us-central1-docker.pkg.dev/example-prod-app/apps/api:latest"
  }

  expect_failures = [var.image]
}

run "rechaza_minimo_mayor_al_maximo" {
  command = plan

  variables {
    min_instances = 5
    max_instances = 2
  }

  expect_failures = [var.max_instances]
}

run "rechaza_subred_en_otra_region" {
  command = plan

  variables {
    subnet = "projects/example-prod-net-spoke/regions/us-east4/subnetworks/bnt-prod-net-run-use4"
  }

  expect_failures = [google_cloud_run_v2_service.this]
}

run "rechaza_cuenta_de_compute_por_defecto" {
  command = plan

  variables {
    service_account = "123456789012-compute@developer.gserviceaccount.com"
  }

  expect_failures = [var.service_account]
}

run "rechaza_etiquetas_incompletas" {
  command = plan

  variables {
    labels = {
      env        = "prod"
      managed_by = "terraform"
    }
  }

  expect_failures = [var.labels]
}
