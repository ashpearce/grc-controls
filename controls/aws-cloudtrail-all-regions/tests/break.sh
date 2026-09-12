#!/usr/bin/env bash
# Negative test hook: put the account into the exact failure the control must
# catch. The harness runs this after a successful apply, then expects the live
# policy to report compliant = false. TF_OUTPUTS points at `terraform output -json`.
set -euo pipefail
trail_arn="$(jq -r '.trail_arn.value' "$TF_OUTPUTS")"
echo "break: stopping logging on $trail_arn"
aws cloudtrail stop-logging --name "$trail_arn"
