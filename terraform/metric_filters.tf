# ---------------------------------------------------------------------------
# Metric filters turn matching log events into CloudWatch metrics
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_metric_filter" "errors" {
  name           = "${var.project_name}-error-count"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "{ $.level = \"ERROR\" }"

  metric_transformation {
    name          = "ErrorCount"
    namespace     = local.metric_namespace
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "warnings" {
  name           = "${var.project_name}-warning-count"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "{ $.level = \"WARN\" }"

  metric_transformation {
    name          = "WarningCount"
    namespace     = local.metric_namespace
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

# Uses a value FROM the log event as the metric value
resource "aws_cloudwatch_log_metric_filter" "latency" {
  name           = "${var.project_name}-latency"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "{ $.latency_ms > 0 }"

  metric_transformation {
    name      = "LatencyMs"
    namespace = local.metric_namespace
    value     = "$.latency_ms"
    unit      = "Milliseconds"
  }
}

resource "aws_cloudwatch_log_metric_filter" "order_value" {
  name           = "${var.project_name}-order-value"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "{ $.event = \"order_placed\" && $.order_value > 0 }"

  metric_transformation {
    name      = "OrderValue"
    namespace = local.metric_namespace
    value     = "$.order_value"
    unit      = "None"
  }
}

# Dimensions split one metric by a field in the log, here one series per error type
resource "aws_cloudwatch_log_metric_filter" "errors_by_type" {
  name           = "${var.project_name}-errors-by-type"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "{ $.level = \"ERROR\" }"

  metric_transformation {
    name       = "ErrorsByType"
    namespace  = local.metric_namespace
    value      = "1"
    unit       = "Count"
    dimensions = { ErrorType = "$.error_type" }
  }
}

# Space-delimited pattern: match Lambda's own REPORT lines and extract the duration.
# A REPORT line looks like:  REPORT RequestId: 8f5c... Duration: 12.34 ms Billed Duration: 13 ms ...
resource "aws_cloudwatch_log_metric_filter" "lambda_duration" {
  name           = "${var.project_name}-lambda-duration"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "[type=\"REPORT\", request_id_label, request_id, duration_label, duration, duration_unit, ...]"

  metric_transformation {
    name      = "GeneratorDurationMs"
    namespace = local.metric_namespace
    value     = "$duration"
    unit      = "Milliseconds"
  }
}
