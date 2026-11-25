variable "project_id" {
  description = "ID del proyecto (único, ADR 0029) donde se crean el servicio y su NEG sin servidor."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id debe ser un ID de proyecto válido (6 a 30 caracteres, minúsculas, dígitos y guiones)."
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
  description = "Entorno: dev, qa o prod."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser dev, qa o prod."
  }
}

variable "name" {
  description = "Identificador corto del servicio dentro de los nombres (<prefix>-<environment>-app-<name>-<región>)."
  type        = string
  default     = "run"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,10}[a-z0-9]$", var.name))
    error_message = "name debe tener de 2 a 12 caracteres: minúsculas, dígitos y guiones, empezando con letra."
  }
}

variable "region" {
  description = "Región del servicio (primaria, o la de DR durante una conmutación)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region debe ser una región de GCP (por ejemplo, us-central1)."
  }
}

variable "region_codes" {
  description = "Mapa región → código corto que se agrega a los nombres (§4.2 del contrato)."
  type        = map(string)
  default = {
    "us-central1"         = "usc1"
    "us-east4"            = "use4"
    "northamerica-south1" = "nas1"
  }

  validation {
    condition     = alltrue([for v in values(var.region_codes) : can(regex("^[a-z0-9]{2,6}$", v))])
    error_message = "Cada código corto de región debe tener de 2 a 6 minúsculas o dígitos."
  }
}

variable "image" {
  description = "Imagen del contenedor (por ejemplo, <región>-docker.pkg.dev/<proyecto>/<repo>/<imagen>@sha256:<digest>). En prod no se admite la etiqueta latest."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9.-]+(:[0-9]+)?/[a-z0-9._/-]+(:[A-Za-z0-9._-]+|@sha256:[a-f0-9]{64})?$", var.image))
    error_message = "image debe ser una referencia de imagen con registro (registro/ruta[:etiqueta|@sha256:digest])."
  }
  validation {
    condition     = var.environment != "prod" || can(regex("(:[A-Za-z0-9._-]+|@sha256:[a-f0-9]{64})$", var.image)) && !endswith(var.image, ":latest")
    error_message = "En prod la imagen debe fijar una etiqueta distinta de latest o un digest."
  }
}

variable "network" {
  description = "Self link (o ruta projects/<proyecto>/global/networks/<red>) de la VPC del spoke del entorno, para la salida directa a la VPC."
  type        = string

  validation {
    condition     = can(regex("(^|/)projects/[^/]+/global/networks/[^/]+$", var.network))
    error_message = "network debe ser un self link o una ruta projects/<proyecto>/global/networks/<red>."
  }
}

variable "subnet" {
  description = "Self link (o ruta projects/<host>/regions/<región>/subnetworks/<subred>) de la subred compartida de Cloud Run (llave run de §5)."
  type        = string

  validation {
    condition     = can(regex("(^|/)projects/[^/]+/regions/[^/]+/subnetworks/[^/]+$", var.subnet))
    error_message = "subnet debe ser un self link o una ruta projects/<proyecto>/regions/<región>/subnetworks/<subred>."
  }
}

variable "vpc_egress" {
  description = "Tráfico de salida que pasa por la VPC: ALL_TRAFFIC (todo, controlado por firewall y Cloud NAT) o PRIVATE_RANGES_ONLY."
  type        = string
  default     = "ALL_TRAFFIC"

  validation {
    condition     = contains(["ALL_TRAFFIC", "PRIVATE_RANGES_ONLY"], var.vpc_egress)
    error_message = "vpc_egress debe ser ALL_TRAFFIC o PRIVATE_RANGES_ONLY."
  }
  validation {
    condition     = var.environment != "prod" || var.vpc_egress == "ALL_TRAFFIC"
    error_message = "En prod toda la salida pasa por la VPC (vpc_egress = ALL_TRAFFIC)."
  }
}

variable "network_tags" {
  description = "Etiquetas de red de la salida directa a la VPC (para reglas de firewall)."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for t in var.network_tags : can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", t))])
    error_message = "Cada etiqueta de red debe ser un nombre válido (minúsculas, dígitos y guiones)."
  }
}

variable "service_account" {
  description = "Correo de la cuenta de servicio propia del servicio (uso run, la crea 1-base). No se admite la cuenta de Compute por defecto."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]@[a-z][a-z0-9-]{4,28}[a-z0-9]\\.iam\\.gserviceaccount\\.com$", var.service_account))
    error_message = "service_account debe ser el correo de una cuenta de servicio administrada por el usuario (<id>@<proyecto>.iam.gserviceaccount.com)."
  }
}

variable "kms_key" {
  description = "ID de la llave KMS (CMEK) que cifra la imagen y los datos del servicio. Debe estar en la misma región que el servicio."
  type        = string

  validation {
    condition     = can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key))
    error_message = "kms_key debe tener la forma projects/<p>/locations/<l>/keyRings/<k>/cryptoKeys/<c>."
  }
}

variable "container_port" {
  description = "Puerto en el que escucha el contenedor."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port debe estar entre 1 y 65535."
  }
}

variable "cpu" {
  description = "Límite de CPU del contenedor (por ejemplo, 1 o 2)."
  type        = string
  default     = "1"

  validation {
    condition     = can(regex("^([0-9]+|[0-9]+m)$", var.cpu))
    error_message = "cpu debe ser un número de vCPU (1, 2, 4...) o milésimas (500m)."
  }
}

variable "memory" {
  description = "Límite de memoria del contenedor (por ejemplo, 512Mi o 1Gi)."
  type        = string
  default     = "512Mi"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi)$", var.memory))
    error_message = "memory debe expresarse en Mi o Gi (por ejemplo, 512Mi)."
  }
}

variable "min_instances" {
  description = "Mínimo de instancias del servicio."
  type        = number
  default     = 0

  validation {
    condition     = var.min_instances >= 0 && floor(var.min_instances) == var.min_instances
    error_message = "min_instances debe ser un entero mayor o igual a 0."
  }
}

variable "max_instances" {
  description = "Máximo de instancias del servicio; no puede ser menor que min_instances."
  type        = number
  default     = 10

  validation {
    condition     = var.max_instances >= 1 && floor(var.max_instances) == var.max_instances && var.max_instances >= var.min_instances
    error_message = "max_instances debe ser un entero mayor o igual a 1 y a min_instances."
  }
}

variable "concurrency" {
  description = "Solicitudes simultáneas máximas por instancia."
  type        = number
  default     = 80

  validation {
    condition     = var.concurrency >= 1 && var.concurrency <= 1000
    error_message = "concurrency debe estar entre 1 y 1000."
  }
}

variable "request_timeout" {
  description = "Tiempo máximo de una solicitud, en segundos con sufijo s (por ejemplo, 300s)."
  type        = string
  default     = "300s"

  validation {
    condition     = can(regex("^[0-9]+s$", var.request_timeout))
    error_message = "request_timeout debe tener la forma <segundos>s (por ejemplo, 300s)."
  }
}

variable "health_check_path" {
  description = "Ruta HTTP de las sondas de arranque y de vida del contenedor. null: solo la sonda TCP de arranque por defecto de Cloud Run."
  type        = string
  default     = null

  validation {
    condition     = var.health_check_path == null || startswith(coalesce(var.health_check_path, "/"), "/")
    error_message = "health_check_path debe empezar con /."
  }
}

variable "env_vars" {
  description = "Variables de entorno sin secretos (nombre → valor). Los secretos van en secret_env."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "secret_env" {
  description = "Variables de entorno leídas de Secret Manager (nombre → { secret, version }). secret es el ID del secreto de la etapa 2; el valor nunca pasa por Terraform."
  type = map(object({
    secret  = string
    version = optional(string, "latest")
  }))
  default  = {}
  nullable = false

  validation {
    condition     = length(setintersection(keys(var.secret_env), keys(var.env_vars))) == 0
    error_message = "Un nombre no puede estar a la vez en env_vars y en secret_env."
  }
}

variable "invokers" {
  description = "Principales que reciben roles/run.invoker (serviceAccount:, group: o domain:). Nunca allUsers, allAuthenticatedUsers ni user:."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for m in var.invokers : can(regex("^(serviceAccount|group|domain):[^ ]+$", m))])
    error_message = "invokers solo admite serviceAccount:, group: o domain:; nunca allUsers, allAuthenticatedUsers ni user:."
  }
}

variable "public_via_load_balancer" {
  description = "Si es true, el servicio es backend del balanceador HTTPS externo y recibe tráfico público: se desactiva la verificación de IAM del invocador (invoker_iam_disabled = true). La entrada sigue fija en interno y balanceador y nunca se concede allUsers (ADR 0020); el control de acceso queda en el balanceador y Cloud Armor."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_binary_authorization" {
  description = "Aplica la política de Binary Authorization del proyecto a las revisiones del servicio."
  type        = bool
  default     = true
  nullable    = false
}

variable "deletion_protection" {
  description = "Protección contra borrado fuera de prod. En prod siempre es true, sin importar este valor (salvo teardown)."
  type        = bool
  default     = false
  nullable    = false
}

variable "teardown" {
  description = "Retiro deliberado del servicio: deletion_protection = false también en prod, para que un apply posterior lo pueda destruir. Solo para una instancia que se va a quitar (el servicio de DR en la vuelta a la región primaria, runbook 04); nunca en el que atiende el tráfico normal."
  type        = bool
  default     = false
  nullable    = false
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
