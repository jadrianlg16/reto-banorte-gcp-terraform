variable "prefix" {
  description = "Prefijo de la empresa para los nombres (por ejemplo, bnt)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.prefix))
    error_message = "prefix debe tener de 2 a 10 caracteres: minúsculas y dígitos, empezando con letra."
  }
}

variable "environment" {
  description = "Entorno que se usa en los nombres: common (política jerárquica del hub), dev, qa o prod."
  type        = string

  validation {
    condition     = contains(["common", "dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser common, dev, qa o prod."
  }
}

variable "policy_type" {
  description = "Tipo de política: hierarchical (parent = organizations/<id> o folders/<id>) o network (política de firewall de red global; parent = la VPC). Se pide aparte de parent porque la VPC suele crearse en el mismo plan y su self_link no se conoce hasta el apply."
  type        = string

  validation {
    condition     = contains(["hierarchical", "network"], var.policy_type)
    error_message = "policy_type debe ser hierarchical o network."
  }
}

variable "parent" {
  description = "Dónde vive y a qué se asocia la política. hierarchical: organizations/<id> o folders/<id>. network: self_link o ID de la VPC (projects/<proyecto>/global/networks/<nombre>); la política se crea en ese proyecto."
  type        = string

  validation {
    condition = (
      var.policy_type == "hierarchical"
      ? can(regex("^(organizations|folders)/[0-9]+$", var.parent))
      : can(regex("projects/[a-z][a-z0-9-]{4,28}[a-z0-9]/global/networks/[a-z]([-a-z0-9]*[a-z0-9])?$", var.parent))
    )
    error_message = "parent debe ser organizations/<id> o folders/<id> (hierarchical) o projects/<proyecto>/global/networks/<nombre> (network)."
  }
}

variable "secure_tags" {
  description = "Etiquetas seguras que pueden usar las reglas. Cada entrada crea su propia llave con propósito GCE_FIREWALL (<prefix>-<environment>-net-fw-<entrada>) y un solo valor (enabled), para que un recurso pueda llevar varias a la vez. Llave = nombre lógico (por ejemplo lb_backend, iap_ssh). En network las llaves quedan ligadas a la VPC; en hierarchical quedan en la organización (purpose_data organization = auto) y exigen secure_tag_parent."
  type = map(object({
    description = optional(string, "")
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.secure_tags) : can(regex("^[a-z][a-z0-9_]{0,40}[a-z0-9]$", k))])
    error_message = "Las llaves de secure_tags deben ser minúsculas, dígitos o guion bajo (2 a 42 caracteres)."
  }
}

variable "secure_tag_parent" {
  description = "Padre de las llaves de etiquetas seguras. Por defecto: projects/<proyecto de la VPC> en network. En hierarchical es obligatorio si hay secure_tags y debe ser organizations/<id> (una carpeta no puede ser padre de una llave de etiqueta)."
  type        = string
  default     = null

  validation {
    condition     = var.secure_tag_parent == null || can(regex("^(organizations/[0-9]+|projects/[a-z][a-z0-9-]{4,28}[a-z0-9])$", var.secure_tag_parent))
    error_message = "secure_tag_parent debe ser organizations/<id> o projects/<proyecto>."
  }
  validation {
    condition     = var.policy_type != "hierarchical" || length(var.secure_tags) == 0 || can(regex("^organizations/[0-9]+$", coalesce(var.secure_tag_parent, "-")))
    error_message = "En una política jerárquica, las etiquetas seguras exigen secure_tag_parent = organizations/<id>."
  }
}

variable "rules" {
  description = "Reglas de la política. Llave = nombre de la regla. priority entre 0 y 64999 (65000 en adelante se reserva para la denegación por defecto que crea el módulo). Las etiquetas seguras se refieren por su llave en secure_tags. target_resources (VPC) solo aplica a hierarchical."
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
    target_resources        = optional(list(string), [])
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
    condition     = alltrue([for r in values(var.rules) : contains(["allow", "deny", "goto_next"], r.action)])
    error_message = "action debe ser allow, deny o goto_next."
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
    condition     = var.policy_type == "hierarchical" || alltrue([for r in values(var.rules) : length(r.target_resources) == 0])
    error_message = "target_resources solo aplica a políticas hierarchical."
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
