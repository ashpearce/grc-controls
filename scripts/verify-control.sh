#!/usr/bin/env bash
# End-to-end proof that a control works, run against a throwaway sandbox AWS account.
#
#   1. terraform apply the control
#   2. collect live state, evaluate live.rego, expect compliant = true
#   3. run tests/break.sh to create the failure, expect compliant = false
#   4. run tests/restore.sh, expect compliant = true again
#   5. terraform destroy (always, even if a step failed)
#   6. write verification/<slug>.json with the outcome
#
# Usage:  scripts/verify-control.sh aws-cloudtrail-all-regions
# Needs:  terraform, opa, aws (signed in to the SANDBOX account), jq
set -euo pipefail

slug="${1:?usage: verify-control.sh <control-slug>}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
control_dir="$repo_root/controls/$slug"
manifest="$control_dir/control.json"
[[ -f "$manifest" ]] || { echo "No control.json at $control_dir"; exit 2; }

control_id="$(jq -r '.id' "$manifest")"
live_query="$(jq -r '.live_query' "$manifest")"
plan_query="$(jq -r '.plan_query' "$manifest")"
tf_dir="$control_dir/terraform"
work="$(mktemp -d)"
export TF_OUTPUTS="$work/outputs.json"

# Refuse to run anywhere that is not clearly a sandbox.
account_id="$(aws sts get-caller-identity --query Account --output text)"
if [[ -z "${HB_SANDBOX_ACCOUNT_ID:-}" || "$account_id" != "$HB_SANDBOX_ACCOUNT_ID" ]]; then
  echo "Refusing to run: signed-in account $account_id is not HB_SANDBOX_ACCOUNT_ID (${HB_SANDBOX_ACCOUNT_ID:-unset})."
  echo "This script creates and destroys real resources. Point it at a throwaway account on purpose."
  exit 2
fi

# Turn verify_terraform_vars from the manifest into -var flags.
# (a plain loop rather than mapfile, because macOS ships bash 3.2 which lacks it)
tf_vars=()
while IFS= read -r line; do
  tf_vars+=("$line")
done < <(jq -r '.verify_terraform_vars | to_entries[] | "-var=\(.key)=\(.value)"' "$manifest")

steps=()
record() { steps+=("{\"step\":\"$1\",\"ok\":$2}"); echo "[$control_id] $1 -> $([[ $2 == true ]] && echo PASS || echo FAIL)"; }

collect_and_eval() {
  bash "$control_dir/evidence/collect.sh" > "$work/live.json"
  opa eval --format json --input "$work/live.json" --data "$control_dir/policy/live.rego" "$live_query" \
    | jq '.result[0].expressions[0].value'
}

expect_compliant() {
  local want="$1" label="$2"
  local got
  got="$(collect_and_eval | jq -r '.compliant')"
  if [[ "$got" == "$want" ]]; then record "$label" true; else record "$label" false; echo "  expected compliant=$want, got $got"; overall=false; fi
}

overall=true
cleanup() {
  set +e
  echo "[$control_id] destroy"
  (cd "$tf_dir" && terraform destroy -auto-approve -input=false "${tf_vars[@]}" >/dev/null) \
    && record "terraform destroy" true || { record "terraform destroy" false; overall=false; }
  mkdir -p "$repo_root/verification"
  jq -n --arg id "$control_id" --arg slug "$slug" --argjson ok "$overall" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg acct "$account_id" \
        --argjson steps "[$(IFS=,; echo "${steps[*]}")]" \
        '{control_id:$id, slug:$slug, verified:$ok, verified_at:$ts, sandbox_account:$acct, steps:$steps}' \
        > "$repo_root/verification/$slug.json"
  echo "[$control_id] wrote verification/$slug.json (verified=$overall)"
  rm -rf "$work"
  [[ "$overall" == true ]]
}
trap cleanup EXIT

cd "$tf_dir"
terraform init -input=false >/dev/null && record "terraform init" true
terraform plan -input=false -out="$work/plan.out" "${tf_vars[@]}" >/dev/null && record "terraform plan" true
terraform show -json "$work/plan.out" > "$work/plan.json"

denies="$(opa eval --format json --input "$work/plan.json" --data "$control_dir/policy/plan.rego" "$plan_query" | jq '.result[0].expressions[0].value | length')"
if [[ "$denies" == "0" ]]; then record "plan policy allows the plan" true; else record "plan policy allows the plan" false; overall=false; exit 1; fi

terraform apply -input=false -auto-approve "$work/plan.out" >/dev/null && record "terraform apply" true
terraform output -json > "$TF_OUTPUTS"

# CloudTrail needs a moment before get-trail-status is consistent.
sleep 20
expect_compliant true  "live policy passes after apply"
bash "$control_dir/tests/break.sh"   && sleep 10
expect_compliant false "live policy catches the break"
bash "$control_dir/tests/restore.sh" && sleep 10
expect_compliant true  "live policy passes after restore"
