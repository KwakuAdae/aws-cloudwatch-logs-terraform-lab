#!/usr/bin/env bash
# Step 1: terraform init + apply. Pass extra Terraform flags through, e.g.:
#   ./scripts/01-deploy.sh -var alert_email=you@example.com
set -euo pipefail
source "$(dirname "$0")/config.sh"

terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" apply -input=false "$@"

echo ""
echo "✅ Deployed. Logs start arriving within a minute."
echo "   Dashboard: $(tf_out dashboard_url)"
