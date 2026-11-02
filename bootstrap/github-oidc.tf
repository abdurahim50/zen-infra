# -----------------------------------------------------------------------------
# GitHub Actions OIDC for zen-infra
#
# One OIDC provider per AWS account, plus two roles GitHub Actions can assume
# with a short-lived token, so no AWS keys are stored in GitHub:
#   zen-infra-plan   pull requests only; read-only plus state read and lock
#   zen-infra-apply  only jobs in the approved "dev" GitHub environment
#
# Applied by a human from a laptop, never by the pipeline: if the apply role
# could change this file it could raise its own permissions.
# Design: docs/adr/0002-github-oidc.md
# -----------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  oidc_host = "token.actions.githubusercontent.com"

  # GitHub sends immutable owner and repo IDs in the subject
  # (repo:OWNER@OWNER_ID/REPO@REPO_ID:...), so a re-created repo or a
  # re-registered username cannot assume these roles. The IDs come from
  # git-ignored terraform.tfvars (see terraform.tfvars.example).
  github_subject_prefix = "repo:abdurahim50@${var.github_owner_id}/zen-infra@${var.github_repository_id}"
}

# -----------------------------------------------------------------------------
# Plan role: pull requests only, read-only
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "plan_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Exact match: pull requests in this repo only. Fork pull requests
    # receive no OIDC token, so outsiders cannot assume the role.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["${local.github_subject_prefix}:pull_request"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "zen-infra-plan"
  description          = "GitHub Actions: terraform plan on zen-infra pull requests (read-only)"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

# Plan refreshes every resource it manages, so it needs broad read access.
# Accepted risk (ADR-002): narrow this after Sprint 3, once the resource
# set is stable.
resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Plan reads state and takes the lock, so it may write .tflock objects and
# nothing else. Pipeline stacks only: bootstrap state is out of reach.
data "aws_iam_policy_document" "plan_state" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid     = "ReadPipelineState"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.state.arn}/envs/*",
      "${aws_s3_bucket.state.arn}/shared/*",
    ]
  }

  statement {
    sid     = "ManageLockFiles"
    actions = ["s3:PutObject", "s3:DeleteObject"]
    resources = [
      "${aws_s3_bucket.state.arn}/envs/*.tflock",
      "${aws_s3_bucket.state.arn}/shared/*.tflock",
    ]
  }

  statement {
    sid       = "UseStateKey"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.state.arn]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "terraform-state-read-and-lock"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_state.json
}

# -----------------------------------------------------------------------------
# Apply role: only jobs in the approved "dev" GitHub environment
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "apply_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # A job targeting a GitHub environment gets this subject only after the
    # environment's protection rules pass (required reviewer, main only).
    # That makes the approval gate something AWS enforces, not just the
    # workflow file.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["${local.github_subject_prefix}:environment:dev"]
    }
  }
}

resource "aws_iam_role" "apply" {
  name                 = "zen-infra-apply"
  description          = "GitHub Actions: terraform apply for zen-infra after approval in the dev environment"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

# Apply permissions: decided in the next step (ADR-002).
