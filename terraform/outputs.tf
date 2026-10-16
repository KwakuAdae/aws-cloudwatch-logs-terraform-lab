output "app_log_group" {
  description = "Log group the generator writes to"
  value       = aws_cloudwatch_log_group.app.name
}

output "processor_log_group" {
  description = "Log group of the error processor"
  value       = aws_cloudwatch_log_group.processor.name
}

output "generator_function" {
  description = "Invoke manually with: aws lambda invoke --function-name <this> ..."
  value       = aws_lambda_function.generator.function_name
}

output "metric_namespace" {
  description = "CloudWatch namespace of the custom metrics"
  value       = local.metric_namespace
}

output "sns_topic_arn" {
  description = "Topic that receives alarm notifications"
  value       = aws_sns_topic.alerts.arn
}

output "dashboard_url" {
  description = "Open the lab dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "logs_insights_url" {
  description = "Open Logs Insights"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:logs-insights"
}

output "saved_queries" {
  description = "Saved Logs Insights queries"
  value       = sort([for q in aws_cloudwatch_query_definition.saved : q.name])
}
