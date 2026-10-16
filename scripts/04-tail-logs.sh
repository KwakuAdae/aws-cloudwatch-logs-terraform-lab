#!/usr/bin/env bash
# Stream the application logs live in your terminal (Ctrl+C to stop).
#   ./scripts/04-tail-logs.sh                 # everything
#   ./scripts/04-tail-logs.sh '{ $.level = "ERROR" }'   # only errors (filter pattern)
set -euo pipefail
source "$(dirname "$0")/config.sh"

ARGS=(--follow --format short --since 5m --region "$AWS_REGION")
[[ $# -gt 0 ]] && ARGS+=(--filter-pattern "$1")
aws logs tail "$(tf_out app_log_group)" "${ARGS[@]}"
