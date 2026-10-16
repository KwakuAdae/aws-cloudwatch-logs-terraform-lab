#!/usr/bin/env bash
# Shared helpers: read values from Terraform outputs.
TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)"
tf_out() { terraform -chdir="$TF_DIR" output -raw "$1"; }
export AWS_REGION="${AWS_REGION:-$(terraform -chdir="$TF_DIR" output -raw dashboard_url 2>/dev/null | sed -E 's#https://([a-z0-9-]+)\..*#\1#')}"
export AWS_REGION="${AWS_REGION:-us-east-1}"
