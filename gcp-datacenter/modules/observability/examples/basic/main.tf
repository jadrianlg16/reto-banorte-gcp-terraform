terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

# Ejemplo: observabilidad base del entorno prod con una verificación de disponibilidad sobre el
# dominio del balanceador externo. Valores de ejemplo únicamente.
module "observability" {
  source = "../.."

  project_id          = "example-prod-app"
  prefix              = "bnt"
  environment         = "prod"
  notification_emails = ["alertas-prod@example.com"]
  lb_url_map_name     = "bnt-prod-app-web-xlb-um"
  slo_target          = 0.999

  # Canales que ya existen (en el proyecto único, los de 1-base) y reciben también las alertas.
  extra_notification_channel_ids = ["projects/example-prod-app/notificationChannels/000000000000"]

  uptime_checks = {
    web = {
      host = "app.example.com"
      path = "/healthz"
    }
  }

  labels = {
    env         = "prod"
    app         = "web"
    owner       = "plataforma"
    cost_center = "cc-0000"
    managed_by  = "terraform"
  }
}

output "notification_channel_ids" {
  description = "Canales de notificación creados."
  value       = module.observability.notification_channel_ids
}

output "dashboard_ids" {
  description = "Tableros creados."
  value       = module.observability.dashboard_ids
}
