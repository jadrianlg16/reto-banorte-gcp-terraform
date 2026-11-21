mock_provider "google" {
  mock_data "google_compute_addresses" {
    defaults = {
      addresses = [
        { address = "10.0.0.2", address_type = "INTERNAL", description = "", name = "example-forwarder", region = "us-central1", self_link = "example", status = "IN_USE" },
      ]
    }
  }
}

variables {
  project_id  = "example-dev-net-spoke"
  prefix      = "bnt"
  environment = "dev"
  networks    = ["projects/example-dev-net-spoke/global/networks/bnt-dev-net-spoke"]
  labels = {
    env         = "dev"
    app         = "network"
    owner       = "example-team"
    cost_center = "example-cc"
    managed_by  = "terraform"
  }
  zones = {
    internal = {
      type   = "private"
      domain = "dev.empresa.internal."
    }
    onprem = {
      type         = "peering"
      domain       = "corp.example.internal."
      peer_network = "projects/example-net-hub/global/networks/bnt-common-net-hub"
    }
    googleapis = {
      type   = "private"
      domain = "googleapis.com."
      records = {
        restricted = { name = "restricted", type = "A", rrdatas = ["199.36.153.4", "199.36.153.5", "199.36.153.6", "199.36.153.7"] }
        wildcard   = { name = "*", type = "CNAME", rrdatas = ["restricted.googleapis.com."] }
      }
    }
  }
}

run "zonas_del_spoke" {
  command = plan

  assert {
    condition     = google_dns_managed_zone.this["internal"].name == "bnt-dev-net-dns-internal" && google_dns_managed_zone.this["internal"].dns_name == "dev.empresa.internal."
    error_message = "La zona privada del entorno no sigue la convención."
  }

  assert {
    condition     = alltrue([for z in google_dns_managed_zone.this : z.visibility == "private" && z.labels["managed_by"] == "terraform"])
    error_message = "Todas las zonas deben ser privadas y llevar las etiquetas."
  }

  assert {
    condition     = length(google_dns_managed_zone.this["onprem"].peering_config) == 1 && google_dns_managed_zone.this["onprem"].peering_config[0].target_network[0].network_url == "projects/example-net-hub/global/networks/bnt-common-net-hub"
    error_message = "La zona de peering debe apuntar a la VPC hub."
  }

  assert {
    condition     = length(google_dns_managed_zone.this["internal"].forwarding_config) == 0 && length(google_dns_managed_zone.this["internal"].peering_config) == 0
    error_message = "Una zona private no lleva reenvío ni peering."
  }

  assert {
    condition     = google_dns_record_set.this["googleapis/restricted"].name == "restricted.googleapis.com." && google_dns_record_set.this["googleapis/restricted"].rrdatas == tolist(["199.36.153.4", "199.36.153.5", "199.36.153.6", "199.36.153.7"])
    error_message = "El registro A de restricted.googleapis.com debe apuntar al VIP restringido."
  }

  assert {
    condition     = google_dns_record_set.this["googleapis/wildcard"].name == "*.googleapis.com." && google_dns_record_set.this["googleapis/wildcard"].type == "CNAME"
    error_message = "*.googleapis.com debe ser un CNAME a restricted.googleapis.com."
  }

  assert {
    condition     = length(google_dns_policy.this) == 0 && length(output.inbound_forwarder_ips) == 0
    error_message = "Sin server_policy no se crea política ni hay IP de reenvío."
  }

  assert {
    condition = (
      output.zones["onprem"].peer_network == "projects/example-net-hub/global/networks/bnt-common-net-hub" &&
      output.zones["internal"].peer_network == null &&
      jsonencode(output.zones["internal"].networks) == jsonencode(["projects/example-dev-net-spoke/global/networks/bnt-dev-net-spoke"]) &&
      length(output.zones["internal"].forwarding_targets) == 0 &&
      jsonencode(output.records["googleapis/wildcard"].rrdatas) == jsonencode(["restricted.googleapis.com."])
    )
    error_message = "Las salidas zones y records deben reflejar las zonas y registros creados."
  }
}

run "hub_reenvio_y_politica" {
  command = plan

  variables {
    project_id  = "example-net-hub"
    environment = "common"
    networks    = ["projects/example-net-hub/global/networks/bnt-common-net-hub"]
    zones = {
      onprem = {
        type   = "forwarding"
        domain = "corp.example.internal."
        target_name_servers = [
          { ipv4_address = "192.168.0.10", forwarding_path = "private" },
        ]
      }
    }
    server_policy = {}
  }

  assert {
    condition     = length(google_dns_managed_zone.this["onprem"].forwarding_config) == 1 && google_dns_managed_zone.this["onprem"].name == "bnt-common-net-dns-onprem"
    error_message = "La zona de reenvío debe tener forwarding_config."
  }

  assert {
    condition     = google_dns_policy.this[0].enable_inbound_forwarding == true && google_dns_policy.this[0].enable_logging == true && google_dns_policy.this[0].name == "bnt-common-net-dns-policy"
    error_message = "La política de servidor debe tener reenvío entrante y registro."
  }

  assert {
    condition     = length(data.google_compute_addresses.inbound_forwarders) == 1
    error_message = "Con reenvío entrante se leen las IP de reenvío."
  }

  assert {
    condition     = jsonencode(output.zones["onprem"].forwarding_targets) == jsonencode(["192.168.0.10"]) && output.zones["onprem"].peer_network == null
    error_message = "La salida zones debe mostrar los servidores de reenvío de la zona."
  }
}

run "rechaza_dominio_sin_punto" {
  command = plan

  variables {
    zones = {
      internal = { type = "private", domain = "dev.empresa.internal" }
    }
  }

  expect_failures = [var.zones]
}

run "rechaza_reenvio_sin_servidores" {
  command = plan

  variables {
    zones = {
      onprem = { type = "forwarding", domain = "corp.example.internal." }
    }
  }

  expect_failures = [var.zones]
}

run "rechaza_peering_sin_red" {
  command = plan

  variables {
    zones = {
      onprem = { type = "peering", domain = "corp.example.internal." }
    }
  }

  expect_failures = [var.zones]
}

run "rechaza_registros_en_reenvio" {
  command = plan

  variables {
    zones = {
      onprem = {
        type                = "forwarding"
        domain              = "corp.example.internal."
        target_name_servers = [{ ipv4_address = "192.168.0.10" }]
        records             = { x = { name = "x", type = "A", rrdatas = ["192.168.0.1"] } }
      }
    }
  }

  expect_failures = [var.zones]
}

run "rechaza_tipo_desconocido" {
  command = plan

  variables {
    zones = {
      public = { type = "public", domain = "example.com." }
    }
  }

  expect_failures = [var.zones]
}
