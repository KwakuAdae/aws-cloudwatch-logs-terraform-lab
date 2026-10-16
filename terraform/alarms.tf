# ---------------------------------------------------------------------------
# SNS topic + alarms on the metrics created by the metric filters
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

# You must click the confirmation link AWS emails you before alerts are delivered
resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "high_errors" {
  alarm_name          = "${var.project_name}-high-error-count"
  alarm_description   = "More than ${var.error_alarm_threshold} ERROR log events in 5 minutes"
  namespace           = local.metric_namespace
  metric_name         = aws_cloudwatch_log_metric_filter.errors.metric_transformation[0].name
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.error_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "high_latency" {
  alarm_name          = "${var.project_name}-high-latency"
  alarm_description   = "Average request latency above ${var.latency_alarm_threshold_ms} ms for 10 minutes"
  namespace           = local.metric_namespace
  metric_name         = aws_cloudwatch_log_metric_filter.latency.metric_transformation[0].name
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.latency_alarm_threshold_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# Metric math: alarm on the error RATE rather than the raw count
resource "aws_cloudwatch_metric_alarm" "error_rate" {
  alarm_name          = "${var.project_name}-error-rate"
  alarm_description   = "Errors are more than 20% of logged requests over 5 minutes"
  evaluation_periods  = 1
  threshold           = 20
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  metric_query {
    id = "errors"
    metric {
      namespace   = local.metric_namespace
      metric_name = "ErrorCount"
      period      = 300
      stat        = "Sum"
    }
  }

  metric_query {
    id = "requests"
    metric {
      namespace   = local.metric_namespace
      metric_name = "LatencyMs" # one data point per request, so SampleCount = requests
      period      = 300
      stat        = "SampleCount"
    }
  }

  metric_query {
    id          = "error_pct"
    expression  = "IF(requests > 0, 100 * errors / requests, 0)"
    label       = "Error rate (%)"
    return_data = true
  }
}

# Alarm on a problem with the pipeline itself: the processor Lambda failing
resource "aws_cloudwatch_metric_alarm" "processor_errors" {
  alarm_name          = "${var.project_name}-error-processor-failures"
  alarm_description   = "The error-processor Lambda is failing"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.processor.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
