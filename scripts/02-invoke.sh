#!/usr/bin/env bash
# Invoke the log generator manually.
#   ./scripts/02-invoke.sh            # one normal batch (20 requests)
#   ./scripts/02-invoke.sh errors 5   # 5 batches of forced errors: trips the error alarm
set -euo pipefail
source "$(dirname "$0")/config.sh"

MODE="${1:-normal}"
TIMES="${2:-1}"
FN=$(tf_out generator_function)
PAYLOAD=$([[ "$MODE" == "errors" ]] && echo '{"mode":"errors","count":10}' || echo '{}')

for i in $(seq 1 "$TIMES"); do
  aws lambda invoke --function-name "$FN" --region "$AWS_REGION" \
    --cli-binary-format raw-in-base64-out --payload "$PAYLOAD" /dev/stdout --query 'StatusCode' --output text
done
