# -----------------------------------------------------------------------------
# Image push role for the application repositories (ADR-003)
#
# GitHub Actions in zen-pharma-backend and zen-pharma-frontend assume this
# role through OIDC to push images to the shared registry. Only workflows on
# main can assume it: pull requests and feature branches build and scan but
# never publish. Permissions cover our zen-pharma/* repositories only.
#
# Named outside zen-pharma-* so the pipeline's apply role cannot change it,
# and listed in the apply role's explicit denies as a second layer.
# -----------------------------------------------------------------------------

locals {
  app_subjects = [
    "repo:abdurahim50@${var.github_owner_id}/zen-pharma-backend@${var.github_backend_repository_id}:ref:refs/heads/main",
    "repo:abdurahim50@${var.github_owner_id}/zen-pharma-frontend@${var.github_frontend_repository_id}:ref:refs/heads/main",
  ]
  # Must match the repository namespace in shared/ecr.tf (zen-pharma/<service>).
  app_repositories_arn = "arn:aws:ecr:${local.region}:${local.account_id}:repository/zen-pharma/*"
}

data "aws_iam_policy_document" "image_push_trust" {
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

    # Exact subjects: main of the two app repositories, nothing else.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = local.app_subjects
    }
  }
}

resource "aws_iam_role" "image_push" {
  name                 = "zen-ci-image-push"
  description          = "GitHub Actions: push images from main of the zen-pharma app repositories to ECR"
  assume_role_policy   = data.aws_iam_policy_document.image_push_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "image_push" {
  # GetAuthorizationToken does not support resource-level permissions.
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Push, plus the reads needed to verify layers, sign with Cosign and read
  # scan results. Limited to our namespace in this account and region.
  statement {
    sid = "PushToOurRepositories"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings",
    ]
    resources = [local.app_repositories_arn]
  }
}

resource "aws_iam_role_policy" "image_push" {
  name   = "push-to-zen-pharma-repositories"
  role   = aws_iam_role.image_push.id
  policy = data.aws_iam_policy_document.image_push.json
}
