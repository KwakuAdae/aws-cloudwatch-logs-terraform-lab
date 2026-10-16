# Troubleshooting

## Terraform

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `No valid credential sources found` | AWS CLI not configured | `aws configure` (or `export AWS_PROFILE=...`), then retry |
| `ResourceAlreadyExistsException: The specified log group already exists` | Lambda auto-created the log group before Terraform did, or a previous run left it behind | Import it: `terraform import aws_cloudwatch_log_group.app /aws/lambda/cwlogs-lab-log-generator`, or delete it in the console and apply again |
| `EntityAlreadyExists: Role with name ... already exists` | Leftovers from an earlier deployment with the same `project_name` | Use another name: `-var project_name=cwlogs-lab2`, or delete the old roles |
| `Error: Invalid value for variable` | A validation rule failed (e.g. `log_retention_days = 10`) | Use one of the allowed values shown in the message |
| `InvalidParameterException ... data protection policy` | Policy document format problem | Compare with `terraform/logs.tf`. `Version` must be `2021-06-01` and there must be one Audit and one Deidentify statement |
| Plan shows the dashboard changing every time | AWS reformats dashboard JSON | Harmless. Apply once and it settles |

## Logs and metrics

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| No logs in the log group | Schedule disabled, or the function is failing | Check `schedule_enabled`. Run `./scripts/02-invoke.sh` and look at its output |
| Metrics don't appear under `CWLogsLab/OrdersApi` | Metric filters only process **new** events, and metrics take a few minutes | Wait 5 minutes after the first logs. Check **Log group → Metric filters** |
| `ErrorsByType` missing for some types | Dimension metrics appear only once a value has been seen | Run `./scripts/02-invoke.sh errors 2` |
| Logs Insights returns nothing | Time range too short, or logs not ingested yet | Widen the range (e.g. last 1 hour). Make sure the right log group is selected |
| Email addresses show as `****` | The data protection policy is working | To view them: **Display → Unmask** (needs `logs:Unmask`) |

## Alarms and alerts

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Alarm in `INSUFFICIENT_DATA` | No data points yet | Wait for a few periods. `treat_missing_data = notBreaching` treats gaps as OK |
| Alarm fires but no email | Subscription not confirmed | Check your inbox and spam for "AWS Notification - Subscription Confirmation". `aws sns list-subscriptions-by-topic --topic-arn $(terraform -chdir=terraform output -raw sns_topic_arn)` shows `PendingConfirmation` until then |
| Error alarm never fires | Not enough errors to cross the threshold | `./scripts/02-invoke.sh errors 3` sends 30 errors |

## Subscription filter

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Error-processor log group is empty | No ERROR events yet, or the permission is missing | Generate errors. Check the `aws_lambda_permission.allow_logs` resource exists |
| `InvalidParameterException: Could not execute the lambda function` on create | The permission wasn't ready yet | Run `terraform apply` again (the filter has `depends_on` the permission) |
