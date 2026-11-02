# -----------------------------------------------------------------------------
# Permissions boundary for every role the pipeline creates
#
# The apply role may create IAM roles (flow logs, EKS, IRSA), so it could
# otherwise create a role more powerful than itself. Every such role must
# carry this boundary: whatever policies are attached, the role can never
# exceed it. Design: docs/adr/0002-github-oidc.md
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "workload_boundary" {
  statement {
    sid    = "WorkloadServices"
    effect = "Allow"
    actions = [
      "ec2:*",
      "logs:*",
      "cloudwatch:*",
      "ecr:*",
      "eks:*",
      "rds:*",
      "secretsmanager:*",
      "kms:*",
      "s3:*",
      "sts:*",
      "ssm:*",
      "elasticloadbalancing:*",
      "autoscaling:*",
      "tag:*",
    ]
    resources = ["*"]
  }

  # The AWS Load Balancer Controller creates this one service-linked role.
  statement {
    sid       = "LoadBalancerServiceLinkedRole"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }

  # Workloads never need Terraform state or its key.
  statement {
    sid     = "NoTerraformState"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]
  }

  statement {
    sid       = "NoStateKey"
    effect    = "Deny"
    actions   = ["kms:*"]
    resources = [aws_kms_key.state.arn]
  }
}

resource "aws_iam_policy" "workload_boundary" {
  name        = "zen-pharma-workload-boundary"
  description = "Maximum permissions for any role created by the zen-infra pipeline"
  policy      = data.aws_iam_policy_document.workload_boundary.json
}
