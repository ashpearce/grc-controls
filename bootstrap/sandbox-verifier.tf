# Run ONCE, by hand, in the throwaway SANDBOX account only.
# Creates the identity the verify workflow uses to build and destroy controls.
# It is deliberately powerful (AdministratorAccess) because it has to create
# whatever each control needs; that is why it lives in an account with nothing in it.
#
#   cd bootstrap
#   terraform init
#   terraform apply -var="github_repository=your-org/grc-controls"
#
# If the account already has a GitHub OIDC provider (AWS allows one per account), add:
#   -var="create_github_oidc_provider=false"
#
# Then save the two outputs as GitHub secrets:
#   HB_SANDBOX_VERIFIER_ROLE_ARN  and  HB_SANDBOX_ACCOUNT_ID

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "github_repository" {
  description = "owner/repo of the grc-controls repo"
  type        = string
}

variable "create_github_oidc_provider" {
  description = "false if this account already has the GitHub OIDC provider; it will be looked up instead."
  type        = bool
  default     = true
}

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1

  url = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

data "aws_iam_policy_document" "trust" {
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

    # Any branch of the repo may verify (so a pull request can prove a new control works).
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:*"]
    }
  }
}

resource "aws_iam_role" "sandbox_verifier" {
  name                 = "hb-sandbox-verifier"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.sandbox_verifier.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "HB_SANDBOX_VERIFIER_ROLE_ARN" {
  value = aws_iam_role.sandbox_verifier.arn
}

output "HB_SANDBOX_ACCOUNT_ID" {
  value = data.aws_caller_identity.current.account_id
}
