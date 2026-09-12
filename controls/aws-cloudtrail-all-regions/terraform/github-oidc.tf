variable "github_repository" {
  description = "owner/repo of the evidence repo, e.g. seesaw-health/grc-controls"
  type        = string
}

variable "create_github_oidc_provider" {
  description = "AWS allows exactly one GitHub OIDC provider per account. Leave true the first time. Set false if the account already has one (the test harness does this) and the role will reuse it."
  type        = bool
  default     = true
}

# Tells AWS to trust ID tokens issued by GitHub Actions. Created once per account.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# If the provider already exists, look it up instead of creating a duplicate.
data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1

  url = "https://token.actions.githubusercontent.com"
}

locals {
  github_owner             = split("/", var.github_repository)[0]
  github_repo              = split("/", var.github_repository)[1]
  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# Only workflows running on the main branch of YOUR repo may assume this role.
data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only the main branch. Two patterns because GitHub's sub claim now carries
    # numeric ids ("repo:owner@123/name@456:ref:...") and older tokens do not.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repository}:ref:refs/heads/main",
        "repo:${local.github_owner}@*/${local.github_repo}@*:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "evidence_collector" {
  name               = "${var.name_prefix}-evidence-collector"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

# Read-only. The evidence job can look at trails; it can never change them.
data "aws_iam_policy_document" "evidence_read" {
  statement {
    effect = "Allow"
    actions = [
      "cloudtrail:DescribeTrails",
      "cloudtrail:GetTrailStatus",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "evidence_read" {
  name   = "cloudtrail-read-only"
  role   = aws_iam_role.evidence_collector.id
  policy = data.aws_iam_policy_document.evidence_read.json
}

output "evidence_role_arn" {
  description = "Save this as the AWS_EVIDENCE_ROLE_ARN secret in GitHub."
  value       = aws_iam_role.evidence_collector.arn
}
