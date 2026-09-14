# Preventive check: runs against `terraform show -json plan.out`
# BEFORE anything is applied. If this fails, the pipeline stops.
package playbook.aws.cloudtrail_all_regions.plan

import rego.v1

# Every CloudTrail trail the plan will create or update (deletes are ignored).
trails contains r if {
	some r in input.resource_changes
	r.type == "aws_cloudtrail"
	not "delete" in r.change.actions
}

deny contains msg if {
	count(trails) == 0
	msg := "PB-AWS-001: the plan contains no aws_cloudtrail resource."
}

deny contains msg if {
	some t in trails
	not t.change.after.is_multi_region_trail
	msg := sprintf("PB-AWS-001: %s is not multi-region (is_multi_region_trail must be true).", [t.address])
}

deny contains msg if {
	some t in trails
	not t.change.after.include_global_service_events
	msg := sprintf("PB-AWS-001: %s skips global services like IAM (include_global_service_events must be true).", [t.address])
}

deny contains msg if {
	some t in trails
	not t.change.after.enable_log_file_validation
	msg := sprintf("PB-AWS-001: %s does not validate log files (enable_log_file_validation must be true).", [t.address])
}

deny contains msg if {
	some t in trails
	t.change.after.enable_logging == false
	msg := sprintf("PB-AWS-001: %s exists but logging is switched off.", [t.address])
}

default allow := false

allow if count(deny) == 0
