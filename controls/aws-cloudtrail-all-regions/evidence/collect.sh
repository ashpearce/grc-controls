#!/usr/bin/env bash
# Asks AWS two questions about every trail and merges the answers into one JSON
# document shaped the way live.rego expects. Read-only: nothing here changes AWS.
set -euo pipefail

account_id="$(aws sts get-caller-identity --query Account --output text)"

# Question 1: what trails exist and how are they configured?
trails_json="$(aws cloudtrail describe-trails --include-shadow-trails --output json)"

# Question 2: for each trail, is it actually logging right now?
merged="$(echo "$trails_json" | jq -c '.trailList[]' | while read -r trail; do
  arn="$(echo "$trail" | jq -r '.TrailARN')"
  is_logging="$(aws cloudtrail get-trail-status --name "$arn" --query IsLogging --output json)"
  echo "$trail" | jq --argjson logging "$is_logging" '{
    Name: .Name,
    TrailARN: .TrailARN,
    HomeRegion: .HomeRegion,
    IsMultiRegionTrail: .IsMultiRegionTrail,
    IncludeGlobalServiceEvents: .IncludeGlobalServiceEvents,
    LogFileValidationEnabled: .LogFileValidationEnabled,
    S3BucketName: .S3BucketName,
    IsLogging: $logging
  }'
done | jq -s '.')"

jq -n --arg account "$account_id" --argjson trails "$merged" \
  '{account_id: $account, trails: $trails}'
