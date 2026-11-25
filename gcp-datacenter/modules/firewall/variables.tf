variable "prefix" {
  description = "Prefijo de la empresa para los nombres (por ejemplo, bnt)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.prefix))
    error_message = "prefix debe tener de 2 a 6 caracteres: minúsculas y dígitos, empezando con letra."
  }
}

variable "environment" {
  description = "Entorno que se usa en los nombres: common (VPC hub y onprem-sim), dev, qa o prod."
  type        = string

  validation {
    condition     = contains(["common", "dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser common, dev, qa o prod."
  }
}

variable "name_suffix" {
  description = "Sufijo opcional del nombre de la política y de las llaves de etiqueta: <prefix>-<environment>-net-fw-<name_suffix>. Vacío (por defecto): <prefix>-<environment>-net-fw. Sirve cuando un mismo proyecto tiene políticas de varias VPC del mismo entorno (por ejemplo hub y onprem-sim, las dos de common)."
  type        = string
  default     = ""

  validation {
    condition     = var.name_suffix == "" || can(regex("^[a-z][a-z0-9-]{0,18}[a-z0-9]$", var.name_suffix))
    error_message = "name_suffix debe estar vacío o tener de 2 a 20 caracteres: minúsculas, dígitos y guiones."
  }
}

variable "parent" {
  description = "VPC a la que se asocia la política: self_link o ID (projects/<proyecto>/global/networks/<nombre>). La política, sus reglas y las llaves de etiqueta se crean en ese proyecto."
  type        = string

  validation {
    condition     = can(regex("projects/[a-z][a-z0-9-]{4,28}[a-z0-9]/global/networks/[a-z]([-a-z0-9]*[a-z0-9])?$", var.parent))
    error_message = "parent debe terminar en projects/<proyecto>/global/networks/<nombre> (la VPC de la política)."
  }
}

variable "secure_tags" {
  description = "Etiquetas seguras que pueden usar las reglas. Cada entrada crea su propia llave con propósito GCE_FIREWALL (<prefix>-<environment>-net-fw-<entrada>), con padre el proyecto de la VPC y ligada a ella, y un solo valor (enabled), para que un recurso pueda llevar varias a la vez. Llave = nombre lógico (por ejemplo lb_backend, iap_ssh)."
  type = map(object({
    description = optional(string, "")
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.secure_tags) : can(regex("^[a-z][a-z0-9_]{0,40}[a-z0-9]$", k))])
    error_message = "Las llaves de secure_tags deben ser minúsculas, dígitos o guion bajo (2 a 42 caracteres)."
  }
}

variable "rules" {
  description = "Reglas de la política. Llave = nombre de la regla. priority entre 0 y 64999 (65000 en adelante se reserva para la denegación por defecto que crea el módulo). action: allow o deny (la política de red es el último nivel: no hay a quién delegar). Las etiquetas seguras se refieren por su llave en secure_tags."
  type = map(object({
    description             = optional(string, "")
    priority                = number
    direction               = optional(string, "INGRESS")
    action                  = string
    src_ip_ranges           = optional(list(string), [])
    dest_ip_ranges          = optional(list(string), [])
    src_secure_tags         = optional(list(string), [])
    target_secure_tags      = optional(list(string), [])
    target_service_accounts = optional(list(string), [])
    enable_logging          = optional(bool, true)
    layer4_configs = optional(list(object({
      ip_protocol = string
      ports       = optional(list(string), [])
    })), [{ ip_protocol = "all" }])
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.rules) : can(regex("^[a-z][a-z0-9-]{0,40}[a-z0-9]$", k))])
    error_message = "Las llaves de rules deben ser minúsculas, dígitos o guiones (2 a 42 caracteres)."
  }
  validation {
    condition     = !contains(keys(var.rules), "default-deny-ingress") && !contains(keys(var.rules), "default-deny-egress")
    error_message = "default-deny-ingress y default-deny-egress son nombres reservados para las reglas que crea el módulo."
  }
  validation {
    condition     = alltrue([for r in values(var.rules) : r.priority >= 0 && r.priority <= 64999 && floor(r.priority) == r.priority])
    error_message = "priority debe ser un entero entre 0 y 64999; 65000 en adelante es de la denegación por defecto."
  }
  validation {
    condition     = length(distinct([for r in values(var.rules) : r.priority])) == length(var.rules)
    error_message = "Cada regla debe tener una prioridad distinta."
  }
  validation {
    condition     = alltrue([for r in values(var.rules) : contains(["INGRESS", "EGRESS"], r.direction)])
    error_message = "direction debe ser INGRESS o EGRESS."
  }
  validation {
    condition     = alltrue([for r in values(var.rules) : contains(["allow", "deny"], r.action)])
    error_message = "action debe ser allow o deny: sin política jerárquica (ADR 0029 §6), la política de red decide y goto_next solo pasaría a las reglas implícitas."
  }
  validation {
    condition     = alltrue([for r in values(var.rules) : r.direction == "EGRESS" || length(r.src_ip_ranges) + length(r.src_secure_tags) > 0])
    error_message = "Una regla INGRESS necesita src_ip_ranges o src_secure_tags."
  }
  validation {
    condition     = alltrue([for r in values(var.rules) : r.direction == "INGRESS" || (length(r.dest_ip_ranges) > 0 && length(r.src_secure_tags) == 0)])
    error_message = "Una regla EGRESS necesita dest_ip_ranges y no admite src_secure_tags."
  }
  validation {
    condition     = alltrue([for r in values(var.rules) : alltrue([for c in concat(r.src_ip_ranges, r.dest_ip_ranges) : can(cidrhost(c, 0))])])
    error_message = "src_ip_ranges y dest_ip_ranges deben ser CIDR válidos."
  }
  validation {
    condition = alltrue([
      for r in values(var.rules) : !(r.direction == "INGRESS" && r.action == "allow" && anytrue([for c in r.src_ip_ranges : try(tonumber(split("/", c)[1]) < 8, true)]))
    ])
    error_message = "No se permite una regla INGRESS allow con un origen más amplio que /8 (por ejemplo 0.0.0.0/0 o 0.0.0.0/1): el tráfico externo entra por el balanceador (35.191.0.0/16, 130.211.0.0/22)."
  }
  validation {
    condition     = alltrue([for r in values(var.rules) : alltrue([for t in concat(r.src_secure_tags, r.target_secure_tags) : contains(keys(var.secure_tags), t)])])
    error_message = "src_secure_tags y target_secure_tags deben ser llaves de secure_tags."
  }
  validation {
    condition     = alltrue([for r in values(var.rules) : alltrue([for l in r.layer4_configs : contains(["all", "tcp", "udp", "icmp", "esp", "ah", "sctp", "ipip"], l.ip_protocol) || can(regex("^[0-9]{1,3}$", l.ip_protocol))])])
    error_message = "layer4_configs[*].ip_protocol debe ser all, tcp, udp, icmp, esp, ah, sctp, ipip o un número de protocolo."
  }
}

variable "enable_egress_default_deny" {
  description = "Además de la denegación de entrada (siempre presente), agrega una regla de salida que deniega todo con prioridad 65001. Con true, la salida necesaria (Google APIs, NAT, on-premises) debe permitirse con reglas EGRESS explícitas."
  type        = bool
  default     = false
}
