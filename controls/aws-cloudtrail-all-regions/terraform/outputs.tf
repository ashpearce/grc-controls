output "trail_arn" {
  description = "ARN of the multi-region trail. Paste this into evidence requests."
  value       = aws_cloudtrail.org_trail.arn
}

output "log_bucket" {
  description = "Bucket where CloudTrail log files land."
  value       = aws_s3_bucket.trail_logs.id
}
