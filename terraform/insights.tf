# ---------------------------------------------------------------------------
# Saved Logs Insights queries: one per file in ../queries
# They appear under CloudWatch → Logs Insights → Saved queries → "<project>/..."
# ---------------------------------------------------------------------------

locals {
  query_files = fileset("${path.module}/../queries", "*.logsinsights")
}

resource "aws_cloudwatch_query_definition" "saved" {
  for_each = local.query_files

  name            = "${var.project_name}/${trimsuffix(each.value, ".logsinsights")}"
  log_group_names = [aws_cloudwatch_log_group.app.name]

  # Drop the leading "# description" comment lines; keep the query itself
  query_string = join("\n", [
    for line in split("\n", file("${path.module}/../queries/${each.value}")) :
    line if !startswith(trimspace(line), "#") && trimspace(line) != ""
  ])
}
