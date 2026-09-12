data "aws_caller_identity" "current" {}

# ------------------------------------------------------------
# 1. The filing cabinet: an S3 bucket that only CloudTrail writes to
# ------------------------------------------------------------
resource "aws_s3_bucket" "trail_logs" {
  bucket        = "${var.name_prefix}-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.allow_bucket_destroy
}

resource "aws_s3_bucket_public_access_block" "trail_logs" {
  bucket = aws_s3_bucket.trail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "trail_logs" {
  bucket = aws_s3_bucket.trail_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail_logs" {
  bucket = aws_s3_bucket.trail_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.log_retention_days
    }
  }
}

# CloudTrail needs written permission to drop files in the bucket.
# Without this policy, `terraform apply` fails with InsufficientS3BucketPolicyException.
data "aws_iam_policy_document" "trail_logs" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail_logs.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.home_region}:${data.aws_caller_identity.current.account_id}:trail/${var.name_prefix}-org-trail"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.home_region}:${data.aws_caller_identity.current.account_id}:trail/${var.name_prefix}-org-trail"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail_logs" {
  bucket = aws_s3_bucket.trail_logs.id
  policy = data.aws_iam_policy_document.trail_logs.json
}

# ------------------------------------------------------------
# 2. The control itself: one trail that records every region
# ------------------------------------------------------------
resource "aws_cloudtrail" "org_trail" {
  name           = "${var.name_prefix}-org-trail"
  s3_bucket_name = aws_s3_bucket.trail_logs.id

  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  enable_logging                = true

  # The bucket policy must exist before the trail tries to write.
  depends_on = [aws_s3_bucket_policy.trail_logs]
}
