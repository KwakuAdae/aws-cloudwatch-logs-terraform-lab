#!/usr/bin/env bash
# Final step: delete everything Terraform created (log groups and their data included).
set -euo pipefail
source "$(dirname "$0")/config.sh"

terraform -chdir="$TF_DIR" destroy -input=false "$@"
echo "✅ All lab resources destroyed."
