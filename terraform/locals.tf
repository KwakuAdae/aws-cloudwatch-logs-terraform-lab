locals {
  generator_name = "${var.project_name}-log-generator"
  processor_name = "${var.project_name}-error-processor"
  app_log_group  = "/aws/lambda/${local.generator_name}"

  # Custom metrics created by the metric filters live in this namespace
  metric_namespace = "CWLogsLab/OrdersApi"
}
