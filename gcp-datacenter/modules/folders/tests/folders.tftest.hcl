mock_provider "google" {}

variables {
  parent = "organizations/000000000000"
  names  = ["common", "dev", "qa", "prod"]
}

run "crea_una_carpeta_por_entorno" {
  command = plan

  assert {
    condition     = toset(keys(google_folder.this)) == toset(["common", "dev", "qa", "prod"])
    error_message = "Debe haber una carpeta por entorno, con el nombre como llave."
  }
  assert {
    condition     = alltrue([for k, f in google_folder.this : f.display_name == k && f.parent == "organizations/000000000000"])
    error_message = "El nombre visible debe ser el del entorno y el padre el indicado."
  }
  assert {
    condition     = alltrue([for f in google_folder.this : f.deletion_protection])
    error_message = "La protección contra borrado debe estar activa por defecto."
  }
}

run "acepta_carpeta_como_padre" {
  command = plan

  variables {
    parent = "folders/111111111111"
    names  = ["bootstrap"]
  }

  assert {
    condition     = google_folder.this["bootstrap"].parent == "folders/111111111111"
    error_message = "Debe aceptar una carpeta como padre."
  }
}

run "rechaza_nombre_fuera_de_entornos" {
  command = plan

  variables {
    names = ["dev", "sandbox"]
  }

  expect_failures = [var.names]
}

run "rechaza_padre_mal_formado" {
  command = plan

  variables {
    parent = "000000000000"
  }

  expect_failures = [var.parent]
}
