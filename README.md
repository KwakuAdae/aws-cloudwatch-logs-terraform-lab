# Lab: Amazon CloudWatch Logs with Terraform

A hands-on lab that builds a complete **logging and monitoring setup** on AWS with
**Terraform**. A small Lambda "orders API" writes structured JSON logs every minute. You turn
those logs into **metrics**, **alarms**, **email alerts**, **saved Logs Insights queries**, a
**real-time subscription**, **sensitive-data masking** and a **dashboard**, all defined as code.

```
                       EventBridge rule: rate(1 minute)
                                   │
                                   ▼
 ┌──────────────────────────────────────┐  JSON logs  ┌───────────────────────────────────────────────────┐
 │ Lambda: log-generator ("orders-api")  │ ──────────▶ │ Log group /aws/lambda/cwlogs-lab-log-generator    │
 │ INFO / WARN / ERROR, latency, orders  │             │  • retention 7 days                               │
 └──────────────────────────────────────┘             │  • data protection policy: masks email addresses  │
                                                       └───┬──────────────┬───────────────┬────────────────┘
                              ┌────────────────────────────┘              │               │
                              ▼                                            ▼               ▼
              6 metric filters → custom metrics          Subscription filter      Logs Insights
              ErrorCount · WarningCount · LatencyMs       { $.level = "ERROR" }    8 saved queries
              OrderValue · ErrorsByType · Duration                 │
                              │                                    ▼
                              ▼                          Lambda: error-processor
              4 alarms ──▶ SNS topic ──▶ 📧 email        (decodes + summarizes errors)
                              │
                              ▼
                     CloudWatch dashboard  (metrics + alarms + live Logs Insights widgets)
```

## What you will learn

**CloudWatch Logs**
- Log groups, log streams, log events and **retention**
- Writing **structured (JSON) logs** and why they matter
- **Metric filters**: JSON patterns, space-delimited patterns, extracting values, dimensions
- **Alarms** on log-based metrics, including **metric math** (error rate %)
- **Logs Insights**: `fields`, `filter`, `stats`, `bin()`, `pct()`, `parse`, `sort`, saved queries
- **Subscription filters**: streaming log events to Lambda in near real time
- **Data protection policies**: masking sensitive data such as email addresses
- **Live tail** with `aws logs tail --follow`
- Dashboards that mix metrics, alarms and log queries

**Terraform**
- Providers, variables with **validation**, locals, outputs
- `for_each` over files with `fileset()`, `count` for optional resources
- Data sources (`archive_file`, `aws_iam_policy_document`)
- `jsonencode()` for policies and dashboards
- The `init` → `plan` → `apply` → `destroy` workflow

## Project structure

```
aws-cloudwatch-logs-terraform-lab/
├── terraform/
│   ├── versions.tf          # Terraform + provider versions, default tags
│   ├── variables.tf         # inputs with validation
│   ├── locals.tf            # names and the metric namespace
│   ├── lambda.tf            # 2 Lambda functions, IAM roles, 1-minute schedule
│   ├── logs.tf              # log groups, retention, data protection, subscription filter
│   ├── metric_filters.tf    # 6 metric filters
│   ├── alarms.tf            # SNS topic, email subscription, 4 alarms
│   ├── insights.tf          # saved Logs Insights queries (one per file in queries/)
│   ├── dashboard.tf         # CloudWatch dashboard
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── src/
│   ├── log_generator/app.py     # writes structured JSON logs
│   └── error_processor/app.py   # receives ERROR events from the subscription filter
├── queries/                 # 8 Logs Insights queries (.logsinsights)
├── tests/test_lambdas.py    # unit tests for both functions
├── scripts/
│   ├── 01-deploy.sh         # terraform init + apply
│   ├── 02-invoke.sh         # invoke the generator (normal or forced errors)
│   ├── 03-run-query.sh      # run a Logs Insights query from the CLI
│   ├── 04-tail-logs.sh      # live tail, optionally filtered
│   └── 05-destroy.sh        # terraform destroy
└── docs/
    ├── 01-filter-pattern-cheatsheet.md
    ├── 02-logs-insights-cheatsheet.md
    └── 03-troubleshooting.md
```

## Prerequisites

| Tool | Check | Install |
|------|-------|---------|
| AWS account | — | See [Cost](#cost) |
| AWS CLI v2 | `aws --version` | then `aws configure` |
| Terraform ≥ 1.5 | `terraform version` | `brew install terraform` or [developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install) |
| Python 3.9+ | `python3 --version` | for the unit tests and CLI helpers |

Your IAM identity needs permissions for CloudWatch, CloudWatch Logs, Lambda, IAM, EventBridge and SNS.

---

## Quick start (automated)

```bash
git clone https://github.com/KwakuAdae/aws-cloudwatch-logs-terraform-lab.git
cd aws-cloudwatch-logs-terraform-lab

./scripts/01-deploy.sh -var alert_email=you@example.com   # confirm the email AWS sends you
./scripts/04-tail-logs.sh                                 # watch logs arrive (Ctrl+C to stop)
./scripts/02-invoke.sh errors 3                           # cause an error spike: the alarm fires
./scripts/03-run-query.sh queries/02-errors-by-type.logsinsights
./scripts/05-destroy.sh                                   # delete everything
```

The rest of this guide goes step by step and explains each piece.

---

## Step 1: Run the unit tests

```bash
pip install pytest
pytest -v
```

The 7 tests check that the generator writes valid JSON with the expected fields and a realistic
mix of levels, and that the processor decodes CloudWatch's gzip + base64 subscription payload.

## Step 2: Look at the logs you're going to work with

The generator ([`src/log_generator/app.py`](src/log_generator/app.py)) prints one JSON object
per simulated request:

```json
{"level": "ERROR", "service": "orders-api", "event": "order_placed", "method": "POST",
 "path": "/orders", "status": 500, "latency_ms": 3120, "error_type": "PaymentGatewayTimeout",
 "message": "Payment provider did not respond within 3000 ms",
 "customer_email": "ama.mensah@example.com", "request_id": "6b1f…", "timestamp": 1760000000000}
```

Anything a Lambda function prints goes to CloudWatch Logs. Because each line is **JSON**,
CloudWatch can filter and query on individual fields like `level`, `latency_ms` or `error_type`
instead of searching free text.

## Step 3: Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set alert_email to your address
```

| Variable | Default | Purpose |
|----------|---------|---------|
| `aws_region` | `us-east-1` | Where to deploy |
| `project_name` | `cwlogs-lab` | Prefix for every resource name |
| `alert_email` | `""` | Email for alarm notifications (empty = no subscription) |
| `log_retention_days` | `7` | How long logs are kept (validated against allowed values) |
| `schedule_enabled` | `true` | Run the generator every minute |
| `error_rate` | `0.05` | Share of simulated requests that fail |
| `error_alarm_threshold` | `10` | Errors per 5 minutes before alarming |
| `latency_alarm_threshold_ms` | `500` | Average latency before alarming |

## Step 4: Deploy

```bash
terraform init      # downloads the aws and archive providers
terraform plan      # preview: 35 resources to add
terraform apply     # type "yes"
```

Then:
1. **Check your inbox** and click **Confirm subscription** in the email from AWS Notifications.
2. Note the outputs (run `terraform output` again any time):

```
app_log_group      = "/aws/lambda/cwlogs-lab-log-generator"
dashboard_url      = "https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards/dashboard/cwlogs-lab-orders-api"
generator_function = "cwlogs-lab-log-generator"
metric_namespace   = "CWLogsLab/OrdersApi"
saved_queries      = ["cwlogs-lab/01-recent-errors", ...]
```

> **Why does Terraform create the log group?** If Lambda creates it automatically, it has
> **no retention**: logs are kept forever and you pay for them forever. Creating
> `aws_cloudwatch_log_group` in Terraform lets us set `retention_in_days` and attach filters
> and policies to it. The function's `logging_config` points at it.

## Step 5: Watch logs arrive (log groups, streams, live tail)

Within a minute the EventBridge rule invokes the generator.

```bash
cd ..
./scripts/04-tail-logs.sh                          # everything
./scripts/04-tail-logs.sh '{ $.level = "ERROR" }'  # only errors
```

In the console: **CloudWatch → Log groups → /aws/lambda/cwlogs-lab-log-generator**.
- Each **log stream** is one Lambda execution environment.
- Open a stream to see the **log events**. Notice Lambda's own `START`, `END` and `REPORT` lines.
- Click **Start tailing** (Live Tail) for a real-time view in the console.

## Step 6: Data protection (masking sensitive data)

Open any log event. `customer_email` shows as **`****`**. The
[`aws_cloudwatch_log_data_protection_policy`](terraform/logs.tf) detects email addresses and
masks them for anyone without the `logs:Unmask` permission.

- **Log group → Data protection** tab shows the policy and how many emails were found.
- To see the original value (if your IAM identity is allowed), choose **Display → Unmask** in the
  console, or use `unmask(@message)` in Logs Insights.

## Step 7: Metric filters (logs → metrics)

[`metric_filters.tf`](terraform/metric_filters.tf) defines six filters:

| Metric | Filter pattern | Value | Teaches |
|--------|----------------|-------|---------|
| `ErrorCount` | `{ $.level = "ERROR" }` | `1` | Counting matches, `default_value = 0` |
| `WarningCount` | `{ $.level = "WARN" }` | `1` | Same, for warnings |
| `LatencyMs` | `{ $.latency_ms > 0 }` | `$.latency_ms` | Using a **field from the log** as the value |
| `OrderValue` | `{ $.event = "order_placed" && $.order_value > 0 }` | `$.order_value` | Combining conditions |
| `ErrorsByType` | `{ $.level = "ERROR" }` | `1`, dimension `ErrorType = $.error_type` | **Dimensions**: one series per error type |
| `GeneratorDurationMs` | `[type="REPORT", request_id_label, request_id, duration_label, duration, ...]` | `$duration` | **Space-delimited** patterns on plain-text lines |

Test a pattern before using it: **Log group → Metric filters → Create metric filter →** paste a
pattern → **Test pattern**. Or from the CLI:

```bash
aws logs test-metric-filter --filter-pattern '{ $.status >= 500 }' \
  --log-event-messages '{"status": 503}' '{"status": 200}'
```

See [docs/01-filter-pattern-cheatsheet.md](docs/01-filter-pattern-cheatsheet.md) for the full syntax.

✅ **Checkpoint:** after ~5 minutes, **CloudWatch → Metrics → All metrics → Custom namespaces →
CWLogsLab/OrdersApi** shows your metrics.

## Step 8: Alarms and email alerts

[`alarms.tf`](terraform/alarms.tf) creates four alarms that notify the SNS topic:

| Alarm | Condition |
|-------|-----------|
| `cwlogs-lab-high-error-count` | `ErrorCount` sum > 10 in 5 minutes |
| `cwlogs-lab-high-latency` | `LatencyMs` average > 500 ms for 2 × 5 minutes |
| `cwlogs-lab-error-rate` | **Metric math**: `100 * errors / requests` > 20% |
| `cwlogs-lab-error-processor-failures` | The processor Lambda's built-in `Errors` metric > 0 |

Trigger the error alarm on purpose:

```bash
./scripts/02-invoke.sh errors 3      # 3 × 10 forced errors (each takes ~3 s of "latency")
```

Within ~5 minutes the alarm goes to **In alarm** and you get an email. Later it returns to
**OK** and you get a second email (that's what `ok_actions` does). The forced errors have high
latency, so the latency alarm may fire as well.

```bash
aws cloudwatch describe-alarms --alarm-name-prefix cwlogs-lab \
  --query 'MetricAlarms[].[AlarmName,StateValue]' --output table
```

## Step 9: Logs Insights

Open **CloudWatch → Logs Insights → Saved queries**. Terraform saved all eight queries from
[`queries/`](queries) under `cwlogs-lab/`:

| Query | What it shows |
|-------|---------------|
| `01-recent-errors` | Last 20 errors with type, path and request id |
| `02-errors-by-type` | Error counts by type |
| `03-latency-by-path` | avg / p50 / p95 / max latency per route |
| `04-requests-per-minute` | Requests per minute by level (try the **Visualization** tab) |
| `05-slowest-requests` | 10 slowest requests |
| `06-revenue-per-5-minutes` | Orders and revenue over time |
| `07-lambda-cold-starts` | Parses Lambda `REPORT` lines for cold starts and memory |
| `08-status-codes` | Requests per HTTP status code |

Example (`03-latency-by-path`):

```
filter ispresent(latency_ms)
| stats count(*) as requests, avg(latency_ms) as avg_ms,
        pct(latency_ms, 50) as p50_ms, pct(latency_ms, 95) as p95_ms, max(latency_ms) as max_ms
  by method, path
| sort p95_ms desc
```

Run any query from the terminal:

```bash
./scripts/03-run-query.sh queries/03-latency-by-path.logsinsights 30    # last 30 minutes
```

Logs Insights charges per GB scanned, so the script prints how much data each query scanned.
See [docs/02-logs-insights-cheatsheet.md](docs/02-logs-insights-cheatsheet.md) for more commands.

## Step 10: Subscription filter (real-time processing)

Metric filters count things. A **subscription filter** delivers the matching log events
themselves to another service: Lambda, Kinesis, Firehose or OpenSearch.

Here every `ERROR` event is sent to the **error-processor** Lambda, which decodes CloudWatch's
compressed payload and logs a summary:

```bash
aws logs tail /aws/lambda/cwlogs-lab-error-processor --since 15m --format short
```

```json
{"level": "INFO", "event": "errors_received", "error_count": 2,
 "by_type": {"PaymentGatewayTimeout": 1, "DatabaseConnectionError": 1}, ...}
```

The `aws_lambda_permission` with principal `logs.amazonaws.com` is what allows CloudWatch Logs to
invoke the function.

## Step 11: Dashboard

Open the `dashboard_url` output. The dashboard shows:
- errors and warnings per minute, latency (with the alarm threshold line), and order revenue
- errors by type, using a `SEARCH()` expression so new error types appear automatically
- the status of all four alarms
- two **live Logs Insights widgets**: recent errors and p95 latency by route

It's all built from a Terraform `jsonencode()` block in [`dashboard.tf`](terraform/dashboard.tf).

## Step 12: Change something with Terraform

Try a few changes, running `terraform plan` before each `apply` so you can see what Terraform will do:

```bash
cd terraform
terraform apply -var error_rate=0.30          # more errors: watch the error-rate alarm
terraform apply -var log_retention_days=14    # in-place update of the log groups
terraform apply -var schedule_enabled=false   # stop generating logs
```

Or add your own query: create `queries/09-my-query.logsinsights`, run `terraform apply`, and it
appears in **Saved queries** (thanks to `for_each = fileset(...)`).

## Step 13: Clean up

```bash
./scripts/05-destroy.sh       # = terraform -chdir=terraform destroy
```

This deletes all 35 resources, including both log groups and their data. If you skipped the
email subscription confirmation, nothing is left behind there either.

---

## Cost

| Item | Approx. cost |
|------|--------------|
| Log ingestion | $0.50/GB. This lab writes ~5 MB/day |
| Log storage | $0.03/GB-month, kept for 7 days |
| Custom metrics (from filters) | ~6–9 metrics × $0.30/month, prorated hourly |
| Alarms | $0.10/alarm/month (4 alarms; the metric-math alarm counts as 2 metrics) |
| Dashboard | First 3 dashboards free |
| Logs Insights | $0.005/GB scanned |
| Lambda, EventBridge, SNS email | Free tier |

Running the lab for a day costs **a few cents**. Destroy it when you're done.

## Going further

- Store Terraform state remotely in **S3** with state locking
- Add a **Firehose** subscription to archive logs to S3, then query them with Athena
- Use a **log anomaly detector** (`aws_cloudwatch_log_anomaly_detector`)
- Add **contributor insights** rules for the top error-producing routes
- Send logs from **EC2** using the CloudWatch agent
- Encrypt the log groups with a customer-managed **KMS** key
- Sister labs: [ECS Fargate](https://github.com/KwakuAdae/aws-ecr-ecs-fargate-lab) ·
  [EKS](https://github.com/KwakuAdae/kwakuadae-aws-eks-website-lab) ·
  [API Gateway](https://github.com/KwakuAdae/aws-api-gateway-lab) ·
  [SQL with CloudFormation](https://github.com/KwakuAdae/aws-cloudformation-sql-lab)

## Troubleshooting

See [docs/03-troubleshooting.md](docs/03-troubleshooting.md).

## Author

**Kwaku Adae**: [github.com/KwakuAdae](https://github.com/KwakuAdae)

Feedback and reviews are welcome. Open an issue or a pull request!
