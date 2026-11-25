variable "project_id" {
  description = "ID del proyecto donde se crea la política de seguridad (el proyecto único, ADR 0029)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id debe ser un ID de proyecto válido de GCP (6 a 30 caracteres, minúsculas, dígitos y guiones)."
  }
}

variable "prefix" {
  description = "Prefijo de la empresa para los nombres (§4.2), por ejemplo \"bnt\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.prefix))
    error_message = "prefix debe tener de 2 a 6 caracteres: minúsculas y dígitos, empezando con letra."
  }
}

variable "environment" {
  description = "Entorno: dev, qa o prod."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser dev, qa o prod."
  }
}

variable "name" {
  description = "Nombre corto de la aplicación o del balanceador que protege la política; forma parte del nombre del recurso."
  type        = string
  default     = "web"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,19}$", var.name))
    error_message = "name debe tener de 1 a 20 caracteres: minúsculas, dígitos o guion, empezando con letra."
  }
}

variable "owasp_rules" {
  description = <<-EOT
    Reglas WAF preconfiguradas de Cloud Armor (conjuntos OWASP ModSecurity CRS). Llave: nombre del
    conjunto tal como lo acepta evaluatePreconfiguredWaf (por ejemplo "sqli-v33-stable").
    Valor: prioridad, sensibilidad (1 a 4; 0 desactiva todas las firmas y no se permite), acción de
    denegación y firmas excluidas. Deben estar siempre un conjunto sqli-* y uno xss-*.
  EOT
  type = map(object({
    priority         = number
    sensitivity      = optional(number, 1)
    action           = optional(string, "deny(403)")
    opt_out_rule_ids = optional(list(string), [])
    description      = optional(string)
  }))
  default = {
    "sqli-v33-stable"              = { priority = 1000, description = "Inyección SQL" }
    "xss-v33-stable"               = { priority = 1010, description = "Cross-site scripting" }
    "lfi-v33-stable"               = { priority = 1020, description = "Inclusión de archivos locales" }
    "rfi-v33-stable"               = { priority = 1030, description = "Inclusión de archivos remotos" }
    "rce-v33-stable"               = { priority = 1040, description = "Ejecución remota de código" }
    "methodenforcement-v33-stable" = { priority = 1050, description = "Métodos HTTP no permitidos" }
    "scannerdetection-v33-stable"  = { priority = 1060, description = "Escáneres automatizados" }
    "protocolattack-v33-stable"    = { priority = 1070, description = "Ataques al protocolo HTTP" }
    "sessionfixation-v33-stable"   = { priority = 1080, description = "Fijación de sesión" }
  }

  validation {
    condition     = !contains(keys(var.owasp_rules), "cve-canary")
    error_message = "cve-canary ya es una regla fija del módulo (cve_canary_priority); no va en owasp_rules."
  }
  validation {
    condition     = anytrue([for k in keys(var.owasp_rules) : startswith(k, "sqli-")])
    error_message = "owasp_rules debe incluir un conjunto de inyección SQL (sqli-*); la especificación lo exige."
  }
  validation {
    condition     = anytrue([for k in keys(var.owasp_rules) : startswith(k, "xss-")])
    error_message = "owasp_rules debe incluir un conjunto de cross-site scripting (xss-*); la especificación lo exige."
  }
  validation {
    condition     = alltrue([for k in keys(var.owasp_rules) : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", k))])
    error_message = "Las llaves de owasp_rules son nombres de conjuntos preconfigurados (minúsculas, dígitos y guiones)."
  }
  validation {
    condition     = alltrue([for r in values(var.owasp_rules) : r.sensitivity >= 1 && r.sensitivity <= 4 && floor(r.sensitivity) == r.sensitivity])
    error_message = "sensitivity debe ser un entero de 1 a 4 (0 apagaría el conjunto)."
  }
  validation {
    condition     = alltrue([for r in values(var.owasp_rules) : can(regex("^deny\\((403|404|502)\\)$", r.action))])
    error_message = "La acción de una regla OWASP debe ser deny(403), deny(404) o deny(502)."
  }
  validation {
    condition     = alltrue([for r in values(var.owasp_rules) : r.priority >= 0 && r.priority < 2147483647 && floor(r.priority) == r.priority])
    error_message = "Las prioridades deben ser enteros entre 0 y 2147483646 (2147483647 es la regla por defecto)."
  }
  validation {
    condition     = length(distinct([for r in values(var.owasp_rules) : r.priority])) == length(var.owasp_rules)
    error_message = "Cada regla OWASP necesita una prioridad distinta."
  }
}

variable "cve_canary_priority" {
  description = "Prioridad de la regla fija cve-canary (CVE críticas, incluida Log4Shell)."
  type        = number
  default     = 1090

  validation {
    condition     = var.cve_canary_priority >= 0 && var.cve_canary_priority < 2147483647 && floor(var.cve_canary_priority) == var.cve_canary_priority
    error_message = "cve_canary_priority debe ser un entero entre 0 y 2147483646."
  }
}

variable "rate_limit" {
  description = <<-EOT
    Límite de tasa por cliente. action: "throttle" (limita y responde exceed_action) o
    "rate_based_ban" (además bloquea al cliente ban_duration_sec segundos). count e interval_sec
    definen el umbral; enforce_on_key define la llave de conteo (por defecto, la IP del cliente).
  EOT
  type = object({
    action           = optional(string, "rate_based_ban")
    priority         = optional(number, 900)
    count            = optional(number, 500)
    interval_sec     = optional(number, 60)
    ban_duration_sec = optional(number, 600)
    exceed_action    = optional(string, "deny(429)")
    enforce_on_key   = optional(string, "IP")
  })
  default = {}

  validation {
    condition     = contains(["throttle", "rate_based_ban"], var.rate_limit.action)
    error_message = "rate_limit.action debe ser \"throttle\" o \"rate_based_ban\"."
  }
  validation {
    condition     = var.rate_limit.count >= 1 && floor(var.rate_limit.count) == var.rate_limit.count
    error_message = "rate_limit.count debe ser un entero mayor o igual a 1."
  }
  validation {
    condition     = contains([10, 30, 60, 120, 180, 240, 300, 600, 900, 1200, 1800, 2700, 3600], var.rate_limit.interval_sec)
    error_message = "rate_limit.interval_sec debe ser uno de los valores que acepta Cloud Armor: 10, 30, 60, 120, 180, 240, 300, 600, 900, 1200, 1800, 2700 o 3600."
  }
  validation {
    condition     = var.rate_limit.action == "throttle" || (var.rate_limit.ban_duration_sec >= 1 && var.rate_limit.ban_duration_sec <= 86400)
    error_message = "rate_limit.ban_duration_sec debe estar entre 1 y 86400 segundos con rate_based_ban."
  }
  validation {
    condition     = can(regex("^deny\\((403|404|429|502)\\)$", var.rate_limit.exceed_action))
    error_message = "rate_limit.exceed_action debe ser deny(403), deny(404), deny(429) o deny(502)."
  }
  validation {
    condition     = contains(["ALL", "IP", "XFF_IP", "REGION_CODE", "TLS_JA3_FINGERPRINT", "USER_IP"], var.rate_limit.enforce_on_key)
    error_message = "rate_limit.enforce_on_key debe ser ALL, IP, XFF_IP, REGION_CODE, TLS_JA3_FINGERPRINT o USER_IP."
  }
  validation {
    condition     = var.rate_limit.priority >= 0 && var.rate_limit.priority < 2147483647 && floor(var.rate_limit.priority) == var.rate_limit.priority
    error_message = "rate_limit.priority debe ser un entero entre 0 y 2147483646."
  }
}

variable "default_rule_action" {
  description = "Acción de la regla por defecto (prioridad 2147483647) para el tráfico que no coincide con otra regla."
  type        = string
  default     = "allow"

  validation {
    condition     = contains(["allow", "deny(403)", "deny(404)", "deny(502)"], var.default_rule_action)
    error_message = "default_rule_action debe ser allow, deny(403), deny(404) o deny(502)."
  }
}

variable "enable_adaptive_protection" {
  description = "Activa Adaptive Protection (detección de DDoS de capa 7). Recomendado en prod."
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Nivel de detalle de los registros de Cloud Armor en los logs del balanceador: NORMAL o VERBOSE."
  type        = string
  default     = "VERBOSE"

  validation {
    condition     = contains(["NORMAL", "VERBOSE"], var.log_level)
    error_message = "log_level debe ser NORMAL o VERBOSE."
  }
}

variable "user_ip_request_headers" {
  description = "Encabezados de los que Cloud Armor toma la IP del cliente (por ejemplo, cuando hay una CDN delante). Vacío: la IP de la conexión."
  type        = list(string)
  default     = []
}
