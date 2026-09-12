#!/usr/bin/env bash
# Negative test hook: put the account into the exact failure the control must catch.
#
# The live policy passes if ANY trail in the account is healthy (that is the right
# rule for a real audit). So to simulate "someone switched logging off" we must stop
# EVERY trail that is currently logging, not just the one this control created,
# and remember which ones so restore.sh can put them back exactly as they were.
#
# Start/stop calls must go to a trail's home region, so we record that too.
set -euo pipefail

state_dir="$(dirname "$TF_OUTPUTS")"
stopped_list="$state_dir/stopped-trails.txt"
: > "$stopped_list"

aws cloudtrail describe-trails --include-shadow-trails \
  --query 'trailList[].[TrailARN,HomeRegion]' --output text \
| sort -u \
| while read -r arn home; do
  is_logging="$(aws cloudtrail get-trail-status --region "$home" --name "$arn" --query IsLogging --output text)"
  if [[ "$is_logging" == "True" ]]; then
    echo "break: stopping logging on $arn"
    aws cloudtrail stop-logging --region "$home" --name "$arn"
    echo "$arn $home" >> "$stopped_list"
  fi
done

echo "break: stopped $(wc -l < "$stopped_list" | tr -d ' ') trail(s)"
