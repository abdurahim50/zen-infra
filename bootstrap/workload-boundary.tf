# -----------------------------------------------------------------------------
# Permissions boundary for every role the pipeline creates
#
# The apply role may create IAM roles (flow logs, EKS, Pod Identity), so it
# could otherwise create a role more powerful than itself. Every such role must
# carry this boundary: whatever policies are attached, the role can never
# exceed it. Design: docs/adr/0002-github-oidc.md, docs/adr/0004-eks-design.md,
# docs/adr/0005-rds-design.md
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

  # EKS Pod Identity: the node role calls this to fetch credentials for pods.
  # The action is eks-auth, but its resource is the EKS cluster ARN; limited to
  # this project's clusters.
  statement {
    sid       = "PodIdentityOwnClusters"
    effect    = "Allow"
    actions   = ["eks-auth:AssumeRoleForPodIdentity"]
    resources = ["arn:aws:eks:${local.region}:${local.account_id}:cluster/zen-pharma-*"]
  }

  # IAM database authentication: roles carrying this boundary may log in only
  # as database users named svc_*, whatever policy they are given, so they
  # cannot IAM-authenticate as the master user (as long as no other statement
  # here allows it; rds_iam is also never granted to the master user). Each
  # role's own policy narrows this to its one user (modules/pod-identity).
  # The resource uses the DB instance resource ID, not its name.
  statement {
    sid       = "DbLoginServiceUsersOnly"
    effect    = "Allow"
    actions   = ["rds-db:connect"]
    resources = ["arn:aws:rds-db:${local.region}:${local.account_id}:dbuser:*/svc_*"]
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
