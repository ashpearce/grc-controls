#!/usr/bin/env bash
# Undo break.sh. The harness runs this next and expects compliant = true again.
set -euo pipefail
trail_arn="$(jq -r '.trail_arn.value' "$TF_OUTPUTS")"
echo "restore: starting logging on $trail_arn"
aws cloudtrail start-logging --name "$trail_arn"
