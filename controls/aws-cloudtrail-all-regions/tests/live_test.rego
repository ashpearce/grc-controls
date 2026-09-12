# Unit tests for live.rego. No AWS needed; runs in about a second.
# Run with:  opa test controls -v
package handbook.aws.cloudtrail_all_regions.live_test

import rego.v1

import data.handbook.aws.cloudtrail_all_regions.live

# Shaped exactly like the output of evidence/collect.sh.
healthy := {"account_id": "123456789012", "trails": [{
	"Name": "seesaw-org-trail",
	"TrailARN": "arn:aws:cloudtrail:us-east-1:123456789012:trail/seesaw-org-trail",
	"HomeRegion": "us-east-1",
	"IsMultiRegionTrail": true,
	"IncludeGlobalServiceEvents": true,
	"LogFileValidationEnabled": true,
	"S3BucketName": "seesaw-cloudtrail-logs-123456789012",
	"IsLogging": true,
}]}

test_healthy_account_is_compliant if {
	live.compliant with input as healthy
	live.result.compliant == true with input as healthy
	live.result.compliant_trails == {"seesaw-org-trail"} with input as healthy
	count(live.result.findings) == 0 with input as healthy
}

test_result_carries_control_identity if {
	live.result.control_id == "HB-AWS-001" with input as healthy
	live.result.account_id == "123456789012" with input as healthy
	live.result.trails_evaluated == 1 with input as healthy
}

test_no_trails_is_not_compliant if {
	empty := {"account_id": "123456789012", "trails": []}
	not live.compliant with input as empty
	"No CloudTrail trails exist in this account." in live.result.findings with input as empty
}

test_stopped_trail_is_not_compliant if {
	# The scenario from the handbook: trail exists, someone clicked Stop logging.
	stopped := json.patch(healthy, [{"op": "replace", "path": "/trails/0/IsLogging", "value": false}])
	not live.compliant with input as stopped
	some msg in live.result.findings with input as stopped
	contains(msg, "switched off")
}

test_single_region_trail_is_not_compliant if {
	single := json.patch(healthy, [{"op": "replace", "path": "/trails/0/IsMultiRegionTrail", "value": false}])
	not live.compliant with input as single
}

test_one_good_trail_among_bad_ones_is_compliant if {
	bad_extra := {
		"Name": "old-contractor-trail",
		"IsMultiRegionTrail": false,
		"IncludeGlobalServiceEvents": false,
		"LogFileValidationEnabled": false,
		"IsLogging": false,
	}
	mixed := {"account_id": "123456789012", "trails": array.concat(healthy.trails, [bad_extra])}
	live.compliant with input as mixed
	live.result.compliant_trails == {"seesaw-org-trail"} with input as mixed

	# The dead trail is still reported so someone cleans it up.
	some msg in live.result.findings with input as mixed
	contains(msg, "old-contractor-trail")
}
