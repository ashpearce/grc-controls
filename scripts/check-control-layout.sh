#!/usr/bin/env bash
# The "definition of done" for a control, enforced by a script.
# A control folder that is missing any of these files is not finished, and CI says so.
set -euo pipefail

required=(
  "control.json"
  "terraform/versions.tf"
  "terraform/main.tf"
  "policy/plan.rego"
  "policy/live.rego"
  "evidence/collect.sh"
  "tests/plan_test.rego"
  "tests/live_test.rego"
  "tests/break.sh"
  "tests/restore.sh"
)

status=0
for dir in controls/*/; do
  slug="$(basename "$dir")"
  for f in "${required[@]}"; do
    if [[ ! -f "$dir$f" ]]; then
      echo "MISSING  $slug/$f"
      status=1
    fi
  done

  # The manifest must name the same slug as the folder, and both queries must be present.
  if [[ -f "$dir/control.json" ]]; then
    manifest_slug="$(jq -r '.slug' "$dir/control.json")"
    if [[ "$manifest_slug" != "$slug" ]]; then
      echo "MISMATCH $slug/control.json says slug=$manifest_slug"
      status=1
    fi
    for key in id plan_query live_query verify_terraform_vars; do
      if [[ "$(jq -r "has(\"$key\")" "$dir/control.json")" != "true" ]]; then
        echo "MISSING  $slug/control.json key: $key"
        status=1
      fi
    done
  fi

  # The evidence workflow for this control must exist at the top of the repo.
  id_lower="$(jq -r '.id' "$dir/control.json" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
  if [[ -n "$id_lower" ]] && ! ls .github/workflows/"$id_lower"-*.yml >/dev/null 2>&1; then
    echo "MISSING  .github/workflows/$id_lower-<name>.yml (daily evidence workflow)"
    status=1
  fi

  [[ $status -eq 0 ]] && echo "OK       $slug"
done

exit $status
