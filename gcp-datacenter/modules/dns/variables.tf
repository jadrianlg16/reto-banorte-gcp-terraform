variable "project_id" {
  description = "ID del proyecto donde se crean las zonas y la política de servidor (el de la VPC)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id debe ser un ID de proyecto válido de GCP (6 a 30 caracteres, minúsculas, dígitos y guiones)."
  }
}

variable "prefix" {
  description = "Prefijo de la empresa para los nombres (por ejemplo, bnt)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.prefix))
    error_message = "prefix debe tener de 2 a 6 caracteres: minúsculas y dígitos, empezando con letra."
  }
}

variable "environment" {
  description = "Entorno que se usa en los nombres: common (hub), dev, qa o prod."
  type        = string

  validation {
    condition     = contains(["common", "dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser common, dev, qa o prod."
  }
}

variable "networks" {
  description = "self_link (o ID) de las VPC a las que se adjuntan las zonas (y la política de servidor) cuando la zona no indica las suyas."
  type        = list(string)

  validation {
    condition     = length(var.networks) > 0
    error_message = "networks debe tener al menos una VPC."
  }
  validation {
    condition     = alltrue([for n in var.networks : can(regex("projects/[^/]+/global/networks/[^/]+$", n))])
    error_message = "Cada elemento de networks debe terminar en projects/<proyecto>/global/networks/<nombre>."
  }
}

variable "zones" {
  description = <<-EOT
    Zonas administradas. Llave = nombre lógico (forma parte del nombre de la zona). type:
    private (zona privada; admite records), forwarding (reenvío condicional a
    target_name_servers) o peering (resuelve con la VPC peer_network). domain termina en punto.
    records: llave libre → { name (relativo al dominio; "" es el ápice), type, ttl, rrdatas }.
  EOT
  type = map(object({
    type        = string
    domain      = string
    description = optional(string, "")
    networks    = optional(list(string))
    target_name_servers = optional(list(object({
      ipv4_address    = string
      forwarding_path = optional(string, "default")
    })), [])
    peer_network = optional(string)
    records = optional(map(object({
      name    = string
      type    = string
      ttl     = optional(number, 300)
      rrdatas = list(string)
    })), {})
  }))

  validation {
    condition     = alltrue([for k in keys(var.zones) : can(regex("^[a-z][a-z0-9-]{0,40}[a-z0-9]$", k))])
    error_message = "Las llaves de zones deben ser minúsculas, dígitos o guiones (2 a 42 caracteres)."
  }
  validation {
    condition     = alltrue([for z in values(var.zones) : contains(["private", "forwarding", "peering"], z.type)])
    error_message = "zones[*].type debe ser private, forwarding o peering."
  }
  validation {
    condition     = alltrue([for z in values(var.zones) : can(regex("^([a-z0-9]([-a-z0-9]*[a-z0-9])?\\.)+$", z.domain))])
    error_message = "zones[*].domain debe ser un nombre DNS en minúsculas que termine en punto (por ejemplo dev.empresa.internal.)."
  }
  validation {
    condition     = alltrue([for z in values(var.zones) : z.type != "forwarding" || length(z.target_name_servers) > 0])
    error_message = "Una zona forwarding necesita target_name_servers."
  }
  validation {
    condition = alltrue(flatten([for z in values(var.zones) : [
      for t in z.target_name_servers : can(cidrhost("${t.ipv4_address}/32", 0)) && contains(["default", "private"], t.forwarding_path)
    ]]))
    error_message = "target_name_servers[*] debe tener una ipv4_address válida y forwarding_path default o private."
  }
  validation {
    condition     = alltrue([for z in values(var.zones) : z.type != "peering" || can(regex("projects/[^/]+/global/networks/[^/]+$", coalesce(z.peer_network, "-")))])
    error_message = "Una zona peering necesita peer_network (self_link o ID de la VPC)."
  }
  validation {
    condition     = alltrue([for z in values(var.zones) : z.type == "private" || length(z.records) == 0])
    error_message = "Solo las zonas private admiten records."
  }
  validation {
    condition     = alltrue([for z in values(var.zones) : (z.type == "forwarding" || length(z.target_name_servers) == 0) && (z.type == "peering" || z.peer_network == null)])
    error_message = "target_name_servers solo aplica a forwarding y peer_network solo a peering."
  }
  validation {
    condition = alltrue(flatten([for z in values(var.zones) : [
      for r in values(z.records) : contains(["A", "AAAA", "CNAME", "TXT", "SRV", "MX", "PTR", "CAA"], r.type) && length(r.rrdatas) > 0 && can(regex("^(\\*|[a-z0-9_]([-a-z0-9_]*[a-z0-9])?)?(\\.[a-z0-9_]([-a-z0-9_]*[a-z0-9])?)*$", r.name))
    ]]))
    error_message = "records[*]: type debe ser A, AAAA, CNAME, TXT, SRV, MX, PTR o CAA; rrdatas no vacío; name relativo al dominio (\"\" para el ápice, \"*\" para comodín)."
  }
}

variable "server_policy" {
  description = "Política de servidor DNS opcional sobre networks: enable_inbound_forwarding crea direcciones de reenvío entrante (una por región con subred) para que on-premises resuelva las zonas de Cloud DNS; enable_logging registra las consultas."
  type = object({
    enable_inbound_forwarding = optional(bool, true)
    enable_logging            = optional(bool, true)
  })
  default = null
}

variable "labels" {
  description = "Etiquetas comunes. Obligatorias: env, app, owner, cost_center, managed_by."
  type        = map(string)

  validation {
    condition = alltrue([
      for k in ["env", "app", "owner", "cost_center", "managed_by"] : contains(keys(var.labels), k)
    ])
    error_message = "Faltan etiquetas obligatorias: env, app, owner, cost_center, managed_by."
  }
  validation {
    condition     = lookup(var.labels, "managed_by", "") == "terraform"
    error_message = "managed_by debe ser \"terraform\"."
  }
  validation {
    condition     = alltrue([for v in values(var.labels) : can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "Los valores de etiquetas van en minúsculas, dígitos, guion o guion bajo."
  }
}
