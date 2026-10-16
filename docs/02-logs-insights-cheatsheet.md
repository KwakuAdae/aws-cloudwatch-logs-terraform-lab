# Logs Insights Cheat Sheet

Queries are a pipeline of commands separated by `|`. Fields in JSON logs are discovered
automatically. Built-in fields start with `@`: `@timestamp`, `@message`, `@logStream`,
`@log`, and for Lambda `@type`, `@duration`, `@billedDuration`, `@maxMemoryUsed`, `@initDuration`.

## Commands

| Command | Example |
|---------|---------|
| `fields` | `fields @timestamp, level, path, latency_ms` |
| `filter` | `filter level = "ERROR" and status >= 500` |
| `stats` | `stats count(*) as n, avg(latency_ms) by path` |
| `sort` | `sort @timestamp desc` |
| `limit` | `limit 50` |
| `parse` | `parse @message /Init Duration: (?<init_ms>[\d.]+) ms/` |
| `display` | `display @timestamp, message` (choose which fields to show) |
| `dedup` | `dedup request_id` |
| `unmask` | `fields unmask(@message)` (needs the `logs:Unmask` permission) |

## Filter operators

`=`, `!=`, `<`, `<=`, `>`, `>=`, `and`, `or`, `not`, `in ["a", "b"]`, `like "Pay%"`,
`like /regex/`, `=~ /regex/`, `ispresent(field)`, `isempty(field)`

## Aggregation functions (in `stats`)

`count(*)`, `count(field)`, `count_distinct(field)`, `sum()`, `avg()`, `min()`, `max()`,
`pct(field, 95)`, `stddev()`, `earliest()`, `latest()`

Group by time with `bin()`: `stats count(*) by bin(5m)`. Use the **Visualization** tab to chart it.

## Useful functions

| Kind | Functions |
|------|-----------|
| String | `strlen`, `toupper`, `tolower`, `concat`, `substr`, `replace`, `trim` |
| Number | `abs`, `ceil`, `floor`, `round`, `log`, `sqrt` |
| Time | `datefloor(@timestamp, 1h)`, `dateceil`, `fromMillis`, `toMillis` |
| IP | `isValidIp`, `isIpInSubnet(ip, "10.0.0.0/8")` |

## Recipes

```
# Errors per hour for the last day
filter level = "ERROR" | stats count(*) by bin(1h)

# Which requests failed, and what did the same request log before failing?
filter request_id = "6b1f..." | sort @timestamp asc

# Top 5 slowest routes by p99
stats pct(latency_ms, 99) as p99 by path | sort p99 desc | limit 5

# Search several log groups at once: select them all in the console, or
aws logs start-query --log-group-names g1 g2 --query-string "..." ...
```

## Cost tip

Logs Insights charges **per GB scanned**. Narrow the time range and filter early to scan less.
`./scripts/03-run-query.sh` prints the bytes scanned for every query.
