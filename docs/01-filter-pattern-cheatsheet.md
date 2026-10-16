# CloudWatch Logs Filter Pattern Cheat Sheet

Filter patterns are used by **metric filters**, **subscription filters**, `aws logs tail
--filter-pattern`, `aws logs filter-log-events` and the console's search box.

Test any pattern without creating anything:

```bash
aws logs test-metric-filter --filter-pattern '<pattern>' \
  --log-event-messages '<event 1>' '<event 2>'
```

## 1. Plain text terms

| Pattern | Matches events that… |
|---------|---------------------|
| `ERROR` | contain `ERROR` (case-sensitive) |
| `ERROR Timeout` | contain **both** `ERROR` and `Timeout` |
| `?ERROR ?WARN` | contain `ERROR` **or** `WARN` |
| `ERROR -Retry` | contain `ERROR` but **not** `Retry` |
| `"Payment provider"` | contain the exact phrase |
| `%ERR[0-9]+%` | match a regular expression (limited regex support) |
| *(empty)* | every event |

## 2. JSON patterns (structured logs)

Wrap in `{ }` and reference fields with `$.`:

| Pattern | Meaning |
|---------|---------|
| `{ $.level = "ERROR" }` | string equality |
| `{ $.level != "INFO" }` | not equal |
| `{ $.status >= 500 }` | numeric comparison (`=`, `!=`, `<`, `<=`, `>`, `>=`) |
| `{ $.latency_ms > 1000 && $.path = "/orders" }` | AND |
| `{ $.level = "ERROR" \|\| $.level = "WARN" }` | OR |
| `{ ($.status = 500 \|\| $.status = 503) && $.method = "POST" }` | grouping |
| `{ $.error_type = "Payment*" }` | wildcard at the end of a string |
| `{ $.order_value IS NULL }` / `{ $.error_type NOT EXISTS }` | null / missing field |
| `{ $.user.id = 42 }` | nested field |
| `{ $.items[0].sku = "A1" }` | array element |

## 3. Space-delimited patterns (plain-text lines)

For lines like web-server access logs or Lambda's `REPORT` line:

```
127.0.0.1 - frank [10/Oct/2026:13:55:36] "GET /orders HTTP/1.1" 500 2326
```

| Pattern | Meaning |
|---------|---------|
| `[ip, user, username, timestamp, request, status_code, bytes]` | name every field |
| `[ip, user, username, timestamp, request, status_code=5*, bytes]` | status starts with 5 |
| `[..., status_code=404, bytes]` | `...` skips any number of leading fields |
| `[ip, ..., bytes > 1000]` | numeric comparison on a field |

Use a named field as a metric value with `$fieldname`, for example `value = "$bytes"`.

## 4. Metric filter values

| `value` | Publishes |
|---------|-----------|
| `"1"` | 1 per matching event (a counter) |
| `"$.latency_ms"` | the number in that JSON field |
| `"$bytes"` | the number in that space-delimited field |

- `default_value = "0"` publishes 0 when nothing matched in a period. That's useful for counters, but **not** allowed together with dimensions.
- `dimensions = { ErrorType = "$.error_type" }` splits the metric into one series per value (max 3 dimensions; avoid high-cardinality fields like request IDs).
