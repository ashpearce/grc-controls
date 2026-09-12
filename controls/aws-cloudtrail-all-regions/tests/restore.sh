#!/usr/bin/env bash
# Undo break.sh: restart exactly the trails it stopped, and nothing else.
set -euo pipefail

state_dir="$(dirname "$TF_OUTPUTS")"
stopped_list="$state_dir/stopped-trails.txt"

if [[ ! -s "$stopped_list" ]]; then
  echo "restore: nothing was stopped, nothing to restore"
  exit 0
fi

while read -r arn home; do
  echo "restore: starting logging on $arn"
  aws cloudtrail start-logging --region "$home" --name "$arn"
done < "$stopped_list"
