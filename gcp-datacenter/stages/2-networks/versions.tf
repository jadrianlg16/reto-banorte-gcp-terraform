terraform {
  required_version = ">= 1.9"
  required_providers {
    google      = { source = "hashicorp/google", version = "~> 6.0" }
    google-beta = { source = "hashicorp/google-beta", version = "~> 6.0" }
    # Solo para el secreto de la VPN con on-premises simulado (ADR 0006).
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}
