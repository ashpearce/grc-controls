variable "home_region" {
  description = "The region the trail is created in. The trail still records every region."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Short company prefix used in resource names."
  type        = string
  default     = "seesaw"
}

variable "log_retention_days" {
  description = "How long CloudTrail log files stay in the bucket before expiring."
  type        = number
  default     = 365
}

variable "allow_bucket_destroy" {
  description = "Only the test harness sets this to true. Lets terraform destroy remove a bucket that already has log files in it. Keep false in a real account: audit logs should never be one command away from deletion."
  type        = bool
  default     = false
}
