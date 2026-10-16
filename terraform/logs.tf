# ---------------------------------------------------------------------------
# Log groups, retention and data protection
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "app" {
  name              = local.app_log_group
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "processor" {
  name              = "/aws/lambda/${local.processor_name}"
  retention_in_days = var.log_retention_days
}

# Mask email addresses in the application logs. Anyone without the logs:Unmask
# permission sees "****" instead of the address in the console and in Logs Insights.
resource "aws_cloudwatch_log_data_protection_policy" "app" {
  log_group_name = aws_cloudwatch_log_group.app.name

  policy_document = jsonencode({
    Name    = "${var.project_name}-mask-emails"
    Version = "2021-06-01"
    Statement = [
      {
        Sid            = "Audit"
        DataIdentifier = ["arn:aws:dataprotection::aws:data-identifier/EmailAddress"]
        Operation      = { Audit = { FindingsDestination = {} } }
      },
      {
        Sid            = "Redact"
        DataIdentifier = ["arn:aws:dataprotection::aws:data-identifier/EmailAddress"]
        Operation      = { Deidentify = { MaskConfig = {} } }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Subscription filter: stream every ERROR event to the error-processor Lambda
# ---------------------------------------------------------------------------

resource "aws_lambda_permission" "allow_logs" {
  statement_id  = "AllowCloudWatchLogsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "${aws_cloudwatch_log_group.app.arn}:*"
}

resource "aws_cloudwatch_log_subscription_filter" "errors_to_processor" {
  name            = "${var.project_name}-errors-to-processor"
  log_group_name  = aws_cloudwatch_log_group.app.name
  filter_pattern  = "{ $.level = \"ERROR\" }"
  destination_arn = aws_lambda_function.processor.arn

  depends_on = [aws_lambda_permission.allow_logs]
}
