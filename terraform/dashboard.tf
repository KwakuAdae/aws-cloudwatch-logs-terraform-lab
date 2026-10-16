# ---------------------------------------------------------------------------
# Dashboard: metrics from the metric filters + live Logs Insights widgets
# ---------------------------------------------------------------------------

locals {
  ns = local.metric_namespace

  metric_widget = {
    type   = "metric"
    width  = 8
    height = 6
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-orders-api"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "## Orders API: CloudWatch Logs lab\nAll metrics below come from **metric filters** on `${local.app_log_group}`. Bottom row: live **Logs Insights** queries."
        }
      },
      merge(local.metric_widget, {
        x = 0
        y = 2
        properties = {
          title   = "Errors and warnings per minute"
          region  = var.aws_region
          view    = "timeSeries"
          stat    = "Sum"
          period  = 60
          metrics = [[local.ns, "ErrorCount", { color = "#d62728" }], [local.ns, "WarningCount", { color = "#ff7f0e" }]]
        }
      }),
      merge(local.metric_widget, {
        x = 8
        y = 2
        properties = {
          title   = "Latency (ms)"
          region  = var.aws_region
          view    = "timeSeries"
          period  = 60
          metrics = [[local.ns, "LatencyMs", { stat = "Average", label = "average" }], [local.ns, "LatencyMs", { stat = "Maximum", label = "max" }]]
          annotations = {
            horizontal = [{ label = "alarm threshold", value = var.latency_alarm_threshold_ms }]
          }
        }
      }),
      merge(local.metric_widget, {
        x = 16
        y = 2
        properties = {
          title   = "Order revenue per 5 min"
          region  = var.aws_region
          view    = "timeSeries"
          stat    = "Sum"
          period  = 300
          metrics = [[local.ns, "OrderValue", { label = "revenue" }]]
        }
      }),
      merge(local.metric_widget, {
        x = 0
        y = 8
        properties = {
          title   = "Errors by type"
          region  = var.aws_region
          view    = "bar"
          stat    = "Sum"
          period  = 3600
          metrics = [[{ expression = "SEARCH('{${local.ns},ErrorType} MetricName=\"ErrorsByType\"', 'Sum', 3600)", id = "e1" }]]
        }
      }),
      {
        type   = "alarm"
        x      = 8
        y      = 8
        width  = 16
        height = 6
        properties = {
          title = "Alarms"
          alarms = [
            aws_cloudwatch_metric_alarm.high_errors.arn,
            aws_cloudwatch_metric_alarm.high_latency.arn,
            aws_cloudwatch_metric_alarm.error_rate.arn,
            aws_cloudwatch_metric_alarm.processor_errors.arn,
          ]
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 14
        width  = 12
        height = 6
        properties = {
          title  = "Recent errors (Logs Insights)"
          region = var.aws_region
          view   = "table"
          query  = "SOURCE '${local.app_log_group}' | fields @timestamp, error_type, path, request_id | filter level = \"ERROR\" | sort @timestamp desc | limit 20"
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 14
        width  = 12
        height = 6
        properties = {
          title  = "p95 latency by route (Logs Insights)"
          region = var.aws_region
          view   = "bar"
          query  = "SOURCE '${local.app_log_group}' | filter ispresent(latency_ms) | stats pct(latency_ms, 95) as p95_ms by path"
        }
      },
    ]
  })
}
