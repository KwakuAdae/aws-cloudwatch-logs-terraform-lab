#!/usr/bin/env bash
# Run a Logs Insights query from the queries/ folder via the CLI and print the results.
#   ./scripts/03-run-query.sh queries/02-errors-by-type.logsinsights [minutes-back]
set -euo pipefail
source "$(dirname "$0")/config.sh"

FILE="${1:?usage: $0 <query-file> [minutes-back]}"
MINUTES="${2:-60}"
LOG_GROUP=$(tf_out app_log_group)
QUERY=$(grep -v '^\s*#' "$FILE")

QUERY_ID=$(aws logs start-query --region "$AWS_REGION" \
  --log-group-name "$LOG_GROUP" \
  --start-time $(( $(date +%s) - MINUTES * 60 )) --end-time "$(date +%s)" \
  --query-string "$QUERY" --query queryId --output text)

echo ">> Query $QUERY_ID running over the last ${MINUTES} minutes..."
while true; do
  RESULT=$(aws logs get-query-results --region "$AWS_REGION" --query-id "$QUERY_ID")
  STATUS=$(echo "$RESULT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')
  [[ "$STATUS" == "Running" || "$STATUS" == "Scheduled" ]] || break
  sleep 1
done

echo "$RESULT" | python3 -c '
import json, sys
r = json.load(sys.stdin)
rows = [{f["field"]: f["value"] for f in row if f["field"] != "@ptr"} for row in r["results"]]
cols = list(dict.fromkeys(k for row in rows for k in row))
if not rows:
    print("(no results - wait a few minutes for logs to arrive, or widen the time range)")
    sys.exit()
w = {c: max(len(c), *(len(row.get(c, "")) for row in rows)) for c in cols}
print(" | ".join(c.ljust(w[c]) for c in cols))
print("-+-".join("-" * w[c] for c in cols))
for row in rows:
    print(" | ".join(row.get(c, "").ljust(w[c]) for c in cols))
s = r["statistics"]
print("\n(%d rows, %d records scanned, %.1f KB)" % (len(rows), s["recordsScanned"], s["bytesScanned"] / 1024))
'
