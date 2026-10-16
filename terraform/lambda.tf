# ---------------------------------------------------------------------------
# Two Lambda functions:
#   log-generator   writes structured JSON logs (the "application")
#   error-processor receives ERROR events from a subscription filter
# ---------------------------------------------------------------------------

data "archive_file" "generator" {
  type        = "zip"
  source_dir  = "${path.module}/../src/log_generator"
  output_path = "${path.module}/build/log_generator.zip"
}

data "archive_file" "processor" {
  type        = "zip"
  source_dir  = "${path.module}/../src/error_processor"
  output_path = "${path.module}/build/error_processor.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# One role per function, each allowed to write only to its own log group
resource "aws_iam_role" "generator" {
  name               = "${local.generator_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role" "processor" {
  name               = "${local.processor_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "write_logs" {
  for_each = {
    generator = aws_cloudwatch_log_group.app.arn
    processor = aws_cloudwatch_log_group.processor.arn
  }
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${each.value}:*"]
  }
}

resource "aws_iam_role_policy" "generator_logs" {
  name   = "write-own-logs"
  role   = aws_iam_role.generator.id
  policy = data.aws_iam_policy_document.write_logs["generator"].json
}

resource "aws_iam_role_policy" "processor_logs" {
  name   = "write-own-logs"
  role   = aws_iam_role.processor.id
  policy = data.aws_iam_policy_document.write_logs["processor"].json
}

resource "aws_lambda_function" "generator" {
  function_name    = local.generator_name
  description      = "Simulates an orders API and writes structured JSON logs"
  role             = aws_iam_role.generator.arn
  runtime          = "python3.12"
  architectures    = ["arm64"]
  handler          = "app.lambda_handler"
  filename         = data.archive_file.generator.output_path
  source_code_hash = data.archive_file.generator.output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      SERVICE_NAME     = "orders-api"
      ERROR_RATE       = tostring(var.error_rate)
      REQUESTS_PER_RUN = "20"
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.app.name
  }

  # The log group must exist (with our retention) before Lambda writes to it
  depends_on = [aws_iam_role_policy.generator_logs]
}

resource "aws_lambda_function" "processor" {
  function_name    = local.processor_name
  description      = "Summarizes ERROR log events delivered by a subscription filter"
  role             = aws_iam_role.processor.arn
  runtime          = "python3.12"
  architectures    = ["arm64"]
  handler          = "app.lambda_handler"
  filename         = data.archive_file.processor.output_path
  source_code_hash = data.archive_file.processor.output_base64sha256
  timeout          = 10
  memory_size      = 128

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.processor.name
  }

  depends_on = [aws_iam_role_policy.processor_logs]
}

# ---------------- Run the generator every minute ----------------
resource "aws_cloudwatch_event_rule" "every_minute" {
  name                = "${var.project_name}-every-minute"
  description         = "Invoke the log generator every minute"
  schedule_expression = "rate(1 minute)"
  state               = var.schedule_enabled ? "ENABLED" : "DISABLED"
}

resource "aws_cloudwatch_event_target" "generator" {
  rule = aws_cloudwatch_event_rule.every_minute.name
  arn  = aws_lambda_function.generator.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.generator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_minute.arn
}
