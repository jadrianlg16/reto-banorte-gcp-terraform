locals {
  # §4.2: <empresa>-<entorno>-ops-<recurso>.
  name = "${var.prefix}-${var.environment}-ops"

  emails = { for e in var.notification_emails : lower(e) => lower(e) }

  # Canales creados aquí más los que ya existen (por ejemplo, los de 1-base en el proyecto único).
  channel_ids = concat([for c in google_monitoring_notification_channel.email : c.id], var.extra_notification_channel_ids)

  # Alcance del entorno. En el proyecto único (ADR 0029) varios entornos comparten el proyecto de
  # métricas: cada filtro se limita a los recursos del entorno, por nombre (<prefix>-<env>-, §4.2)
  # o por la etiqueta env (§4.3). Con un proyecto por entorno el alcance no cambia nada.
  # VERIFICAR-EN-APPLY: que Cloud Monitoring acepte starts_with() sobre url_map_name,
  # cluster_name y database_id, y metadata.user_labels.env en gce_instance, en alertas, SLO y
  # tablero, y que cada entorno vea solo sus series.
  env_prefix = "${var.prefix}-${var.environment}-"

  url_map_filter = (
    var.lb_url_map_name == null
    ? " AND resource.label.url_map_name=starts_with(\"${local.env_prefix}\")"
    : " AND resource.label.url_map_name=\"${var.lb_url_map_name}\""
  )
  vm_scope_filter  = " AND metadata.user_labels.env=\"${var.environment}\""
  gke_scope_filter = " AND resource.label.cluster_name=starts_with(\"${local.env_prefix}\")"
  sql_scope_filter = " AND resource.label.database_id=starts_with(\"${var.project_id}:${local.env_prefix}\")"
  uptime_hosts     = distinct([for c in values(var.uptime_checks) : c.host])

  lb_requests_filter = "resource.type=\"https_lb_rule\" AND metric.type=\"loadbalancing.googleapis.com/https/request_count\"${local.url_map_filter}"
  lb_5xx_filter      = "${local.lb_requests_filter} AND metric.label.response_code_class=500"
  lb_latency_filter  = "resource.type=\"https_lb_rule\" AND metric.type=\"loadbalancing.googleapis.com/https/total_latencies\"${local.url_map_filter}"

  vm_cpu_filter    = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\"${local.vm_scope_filter}"
  vm_memory_filter = "resource.type=\"gce_instance\" AND metric.type=\"agent.googleapis.com/memory/percent_used\" AND metric.label.state=\"used\"${local.vm_scope_filter}"
  gke_cpu_filter   = "resource.type=\"k8s_node\" AND metric.type=\"kubernetes.io/node/cpu/allocatable_utilization\"${local.gke_scope_filter}"
  gke_mem_filter   = "resource.type=\"k8s_node\" AND metric.type=\"kubernetes.io/node/memory/allocatable_utilization\" AND metric.label.memory_type=\"non-evictable\"${local.gke_scope_filter}"
  sql_lag_filter   = "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/replication/replica_lag\"${local.sql_scope_filter}"
  uptime_filter    = "resource.type=\"uptime_url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\""
  # Tablero: solo las verificaciones de este módulo (por dominio); sin verificaciones no hay
  # mosaico de disponibilidad.
  uptime_dashboard_filter = "${local.uptime_filter} AND resource.label.host=one_of(${join(",", [for h in local.uptime_hosts : "\"${h}\""])})"

  # Umbrales de tasa de consumo del presupuesto de errores (práctica estándar de SRE para una
  # ventana de ~30 días): rápido 14.4x en 1 h (2 % del presupuesto) y lento 6x en 6 h (5 %).
  burn_rate_fast = 14.4
  burn_rate_slow = 6

  saturation_conditions = {
    vm_cpu = {
      display_name = "CPU de VM sobre ${var.cpu_utilization_threshold * 100} %"
      filter       = local.vm_cpu_filter
      threshold    = var.cpu_utilization_threshold
    }
    vm_memory = {
      display_name = "Memoria de VM (Ops Agent) sobre ${var.memory_utilization_threshold * 100} %"
      filter       = local.vm_memory_filter
      threshold    = var.memory_utilization_threshold * 100
    }
    gke_cpu = {
      display_name = "CPU asignable de nodos de GKE sobre ${var.cpu_utilization_threshold * 100} %"
      filter       = local.gke_cpu_filter
      threshold    = var.cpu_utilization_threshold
    }
    gke_memory = {
      display_name = "Memoria asignable de nodos de GKE sobre ${var.memory_utilization_threshold * 100} %"
      filter       = local.gke_mem_filter
      threshold    = var.memory_utilization_threshold
    }
  }
}

# ---------------------------------------------------------------------------------------------
# Canales de notificación
# ---------------------------------------------------------------------------------------------

# VERIFICAR-EN-APPLY: los canales de correo no piden verificación, pero el buzón debe existir y
# aceptar correo de alertas de Cloud Monitoring.
resource "google_monitoring_notification_channel" "email" {
  for_each = local.emails

  project      = var.project_id
  display_name = "${local.name}-email-${each.key}"
  type         = "email"
  labels = {
    email_address = each.value
  }
  user_labels = var.labels
}

# ---------------------------------------------------------------------------------------------
# Verificaciones de disponibilidad y sus alertas
# ---------------------------------------------------------------------------------------------

resource "google_monitoring_uptime_check_config" "this" {
  for_each = var.uptime_checks

  project            = var.project_id
  display_name       = "${local.name}-uptime-${each.key}"
  period             = each.value.period
  timeout            = each.value.timeout
  selected_regions   = each.value.selected_regions
  log_check_failures = true
  user_labels        = var.labels

  http_check {
    path           = each.value.path
    port           = each.value.port
    use_ssl        = each.value.use_ssl
    validate_ssl   = each.value.validate_ssl
    request_method = "GET"
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = each.value.host
    }
  }

  dynamic "content_matchers" {
    for_each = each.value.content_match == null ? [] : [each.value.content_match]
    content {
      content = content_matchers.value
      matcher = "CONTAINS_STRING"
    }
  }
}

resource "google_monitoring_alert_policy" "uptime" {
  for_each = var.uptime_checks

  project               = var.project_id
  display_name          = "${local.name}-alert-uptime-${each.key}"
  combiner              = "OR"
  severity              = "CRITICAL"
  notification_channels = local.channel_ids
  user_labels           = var.labels

  conditions {
    display_name = "Falla la verificación de disponibilidad ${each.key} (${each.value.host})"

    condition_threshold {
      filter          = "${local.uptime_filter} AND metric.label.check_id=\"${google_monitoring_uptime_check_config.this[each.key].uptime_check_id}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "60s"

      aggregations {
        alignment_period     = "1200s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.*"]
      }

      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    mime_type = "text/markdown"
    content   = "La verificación ${each.key} falla desde más de una región. Revisar el balanceador, los backends y el certificado de ${each.value.host}."
  }
}

# ---------------------------------------------------------------------------------------------
# Alertas base
# ---------------------------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "lb_5xx_ratio" {
  project               = var.project_id
  display_name          = "${local.name}-alert-lb-5xx"
  combiner              = "OR"
  severity              = "ERROR"
  notification_channels = local.channel_ids
  user_labels           = var.labels

  conditions {
    display_name = "Respuestas 5xx del balanceador sobre ${var.lb_5xx_ratio_threshold * 100} %"

    condition_threshold {
      filter             = local.lb_5xx_filter
      denominator_filter = local.lb_requests_filter
      comparison         = "COMPARISON_GT"
      threshold_value    = var.lb_5xx_ratio_threshold
      duration           = "300s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.url_map_name"]
      }

      denominator_aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.url_map_name"]
      }

      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    mime_type = "text/markdown"
    content   = "La proporción de respuestas 5xx del balanceador supera el umbral durante 5 minutos. Revisar la salud de los backends y los registros del balanceador."
  }
}

# VERIFICAR-EN-APPLY: la condición de memoria de VM solo recibe datos si las VM tienen Ops Agent
# (agent.googleapis.com/memory/percent_used); sin él, esa condición queda sin datos.
resource "google_monitoring_alert_policy" "saturation" {
  project               = var.project_id
  display_name          = "${local.name}-alert-saturation"
  combiner              = "OR"
  severity              = "WARNING"
  notification_channels = local.channel_ids
  user_labels           = var.labels

  dynamic "conditions" {
    for_each = local.saturation_conditions
    content {
      display_name = conditions.value.display_name

      condition_threshold {
        filter          = conditions.value.filter
        comparison      = "COMPARISON_GT"
        threshold_value = conditions.value.threshold
        duration        = "300s"

        aggregations {
          alignment_period   = "60s"
          per_series_aligner = "ALIGN_MEAN"
        }

        trigger {
          count = 1
        }
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    mime_type = "text/markdown"
    content   = "Saturación de CPU o memoria sostenida 5 minutos en VM o nodos de GKE. Revisar el autoescalado (MIG o pools de nodos) y los límites de recursos. La memoria de VM requiere Ops Agent."
  }
}

resource "google_monitoring_alert_policy" "sql_replica_lag" {
  project               = var.project_id
  display_name          = "${local.name}-alert-sql-replica-lag"
  combiner              = "OR"
  severity              = "CRITICAL"
  notification_channels = local.channel_ids
  user_labels           = var.labels

  conditions {
    display_name = "Retraso de réplica de Cloud SQL sobre ${var.sql_replica_lag_threshold_seconds} s (RPO 15 min)"

    condition_threshold {
      filter          = local.sql_lag_filter
      comparison      = "COMPARISON_GT"
      threshold_value = var.sql_replica_lag_threshold_seconds
      duration        = "120s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }

      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    mime_type = "text/markdown"
    content   = "La réplica de Cloud SQL en la región de DR se retrasa. Si el retraso se acerca a 15 minutos, el RPO comprometido está en riesgo: revisar la carga del primario y la red entre regiones."
  }
}

# ---------------------------------------------------------------------------------------------
# Servicio, SLO de disponibilidad y alerta de consumo del presupuesto de errores
# ---------------------------------------------------------------------------------------------

# VERIFICAR-EN-APPLY: que la API acepte el SLI por solicitudes con los filtros del balanceador
# (response_code_class es INT64, sin comillas) y que select_slo_burn_rate devuelva datos con
# tráfico real en las ventanas de 60m y 360m.
resource "google_monitoring_custom_service" "this" {
  project      = var.project_id
  service_id   = "${local.name}-lb"
  display_name = "${local.name}-lb (balanceador externo)"
  user_labels  = var.labels
}

resource "google_monitoring_slo" "availability" {
  project             = var.project_id
  service             = google_monitoring_custom_service.this.service_id
  slo_id              = "${local.name}-lb-availability"
  display_name        = "Disponibilidad del balanceador ${var.slo_target * 100} % (${var.slo_rolling_period_days} días)"
  goal                = var.slo_target
  rolling_period_days = var.slo_rolling_period_days
  user_labels         = var.labels

  request_based_sli {
    good_total_ratio {
      bad_service_filter   = local.lb_5xx_filter
      total_service_filter = local.lb_requests_filter
    }
  }
}

resource "google_monitoring_alert_policy" "slo_burn_rate" {
  project               = var.project_id
  display_name          = "${local.name}-alert-slo-burn-rate"
  combiner              = "OR"
  severity              = "CRITICAL"
  notification_channels = local.channel_ids
  user_labels           = var.labels

  conditions {
    display_name = "Consumo rápido del presupuesto de errores (${local.burn_rate_fast}x en 1 h)"

    condition_threshold {
      filter          = "select_slo_burn_rate(\"${google_monitoring_slo.availability.name}\", \"60m\")"
      comparison      = "COMPARISON_GT"
      threshold_value = local.burn_rate_fast
      duration        = "0s"

      trigger {
        count = 1
      }
    }
  }

  conditions {
    display_name = "Consumo lento del presupuesto de errores (${local.burn_rate_slow}x en 6 h)"

    condition_threshold {
      filter          = "select_slo_burn_rate(\"${google_monitoring_slo.availability.name}\", \"360m\")"
      comparison      = "COMPARISON_GT"
      threshold_value = local.burn_rate_slow
      duration        = "0s"

      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "3600s"
  }

  documentation {
    mime_type = "text/markdown"
    content   = "El SLO de disponibilidad (${var.slo_target * 100} %) consume su presupuesto de errores más rápido de lo sostenible. Revisar 5xx del balanceador y el estado de los backends; valorar la conmutación a DR."
  }
}

# ---------------------------------------------------------------------------------------------
# Tablero base
# ---------------------------------------------------------------------------------------------

resource "google_monitoring_dashboard" "baseline" {
  project = var.project_id
  dashboard_json = jsonencode({
    displayName = "${local.name}-dashboard-baseline"
    mosaicLayout = {
      columns = 48
      tiles = concat([
        {
          xPos = 0, yPos = 0, width = 24, height = 16
          widget = {
            title = "Solicitudes del balanceador por clase de respuesta"
            xyChart = {
              dataSets = [{
                plotType = "STACKED_BAR"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = local.lb_requests_filter
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["metric.label.response_code_class"]
                    }
                  }
                }
              }]
            }
          }
        },
        {
          xPos = 24, yPos = 0, width = 24, height = 16
          widget = {
            title = "Latencia total del balanceador (p95)"
            xyChart = {
              dataSets = [{
                plotType = "LINE"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = local.lb_latency_filter
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_DELTA"
                      crossSeriesReducer = "REDUCE_PERCENTILE_95"
                      groupByFields      = ["resource.label.url_map_name"]
                    }
                  }
                }
              }]
            }
          }
        },
        {
          xPos = 0, yPos = 16, width = 24, height = 16
          widget = {
            title = "CPU de VM"
            xyChart = {
              dataSets = [{
                plotType = "LINE"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = local.vm_cpu_filter
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          xPos = 24, yPos = 16, width = 24, height = 16
          widget = {
            title = "CPU asignable de nodos de GKE"
            xyChart = {
              dataSets = [{
                plotType = "LINE"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = local.gke_cpu_filter
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          xPos = 0, yPos = 32, width = 24, height = 16
          widget = {
            title = "Retraso de réplica de Cloud SQL (s)"
            xyChart = {
              dataSets = [{
                plotType = "LINE"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = local.sql_lag_filter
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MAX"
                    }
                  }
                }
              }]
              thresholds = [{ value = var.sql_replica_lag_threshold_seconds, label = "Umbral de alerta" }]
            }
          }
        },
        ], length(local.uptime_hosts) == 0 ? [] : [
        {
          xPos = 24, yPos = 32, width = 24, height = 16
          widget = {
            title = "Verificaciones de disponibilidad fallidas"
            xyChart = {
              dataSets = [{
                plotType = "LINE"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = local.uptime_dashboard_filter
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_NEXT_OLDER"
                      crossSeriesReducer = "REDUCE_COUNT_FALSE"
                      groupByFields      = ["metric.label.check_id"]
                    }
                  }
                }
              }]
            }
          }
        },
      ])
    }
  })
}
