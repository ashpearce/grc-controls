# Unit tests for plan.rego. No AWS needed; runs in about a second.
# Run with:  opa test controls -v
package handbook.aws.cloudtrail_all_regions.plan_test

import rego.v1

import data.handbook.aws.cloudtrail_all_regions.plan

# A minimal slice of what `terraform show -json plan.out` produces.
good_trail := {"resource_changes": [{
	"address": "aws_cloudtrail.org_trail",
	"type": "aws_cloudtrail",
	"change": {
		"actions": ["create"],
		"after": {
			"is_multi_region_trail": true,
			"include_global_service_events": true,
			"enable_log_file_validation": true,
			"enable_logging": true,
		},
	},
}]}

test_good_trail_is_allowed if {
	plan.allow with input as good_trail
}

test_good_trail_has_no_denies if {
	count(plan.deny) == 0 with input as good_trail
}

test_missing_trail_is_denied if {
	no_trail := {"resource_changes": [{
		"address": "aws_s3_bucket.trail_logs",
		"type": "aws_s3_bucket",
		"change": {"actions": ["create"], "after": {}},
	}]}
	not plan.allow with input as no_trail
	"HB-AWS-001: the plan contains no aws_cloudtrail resource." in plan.deny with input as no_trail
}

test_single_region_trail_is_denied if {
	single := json.patch(good_trail, [{"op": "replace", "path": "/resource_changes/0/change/after/is_multi_region_trail", "value": false}])
	not plan.allow with input as single
	some msg in plan.deny with input as single
	contains(msg, "not multi-region")
}

test_missing_setting_counts_as_failure if {
	# The setting is absent entirely, not false. Still a failure.
	absent := json.remove(good_trail, ["/resource_changes/0/change/after/include_global_service_events"])
	not plan.allow with input as absent
}

test_logging_off_is_denied if {
	off := json.patch(good_trail, [{"op": "replace", "path": "/resource_changes/0/change/after/enable_logging", "value": false}])
	some msg in plan.deny with input as off
	contains(msg, "logging is switched off")
}

test_deleting_the_trail_is_denied if {
	deleting := json.patch(good_trail, [{"op": "replace", "path": "/resource_changes/0/change/actions", "value": ["delete"]}])
	not plan.allow with input as deleting
}
