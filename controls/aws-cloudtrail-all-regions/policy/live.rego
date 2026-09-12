# Detective check: runs against what AWS says is true RIGHT NOW.
# Input is produced by evidence/collect.sh. This is the file that becomes evidence.
package handbook.aws.cloudtrail_all_regions.live

import rego.v1

control_id := "HB-AWS-001"

# A trail only counts if all four things are true at the same time.
compliant_trails contains t.Name if {
	some t in input.trails
	t.IsMultiRegionTrail == true
	t.IncludeGlobalServiceEvents == true
	t.LogFileValidationEnabled == true
	t.IsLogging == true
}

default compliant := false

compliant if count(compliant_trails) > 0

findings contains msg if {
	count(input.trails) == 0
	msg := "No CloudTrail trails exist in this account."
}

findings contains msg if {
	count(input.trails) > 0
	count(compliant_trails) == 0
	msg := "Trails exist, but none is multi-region, logging, validating, and covering global services."
}

findings contains msg if {
	some t in input.trails
	t.IsLogging == false
	msg := sprintf("Trail %s is switched off (IsLogging = false).", [t.Name])
}

# The single object the pipeline writes to the evidence folder.
result := {
	"control_id": control_id,
	"control": "CloudTrail enabled in all regions",
	"compliant": compliant,
	"compliant_trails": compliant_trails,
	"trails_evaluated": count(input.trails),
	"findings": findings,
	"account_id": input.account_id,
}
