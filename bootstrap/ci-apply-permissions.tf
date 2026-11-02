# -----------------------------------------------------------------------------
# Permissions for zen-infra-apply
#
# Allows the services our stacks use, in us-east-1 only. IAM is limited to
# zen-pharma-* roles that carry the workload boundary. Explicit denies
# protect the CI identity, the boundary and Terraform state, so the pipeline
# cannot raise its own access or damage what it depends on.
# Design: docs/adr/0002-github-oidc.md
# -----------------------------------------------------------------------------

locals {
  account_id          = data.aws_caller_identity.current.account_id
  region              = data.aws_region.current.region
  workload_role_arns  = "arn:aws:iam::${local.account_id}:role/zen-pharma-*"
  workload_policy_arn = "arn:aws:iam::${local.account_id}:policy/zen-pharma-*"
}

data "aws_iam_policy_document" "apply" {
  # ---------- Allow: infrastructure services, this region only ----------

  statement {
    sid    = "ManageInfrastructure"
    effect = "Allow"
    actions = [
      "ec2:*",
      "logs:*",
      "ecr:*",
      "eks:*",
      "rds:*",
      "secretsmanager:*",
      "elasticloadbalancing:*",
      "autoscaling:*",
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  statement {
    sid    = "ManageKmsKeys"
    effect = "Allow"
    actions = [
      "kms:CreateKey",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:UpdateAlias",
      "kms:Describe*",
      "kms:Get*",
      "kms:List*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:EnableKeyRotation",
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
      "kms:CreateGrant",
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey*",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  # ---------- Allow: Terraform state for pipeline stacks ----------

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid     = "ReadWritePipelineState"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "${aws_s3_bucket.state.arn}/envs/*",
      "${aws_s3_bucket.state.arn}/shared/*",
    ]
  }

  # ---------- Allow: IAM, limited to zen-pharma-* with the boundary ----------

  statement {
    sid       = "ReadIam"
    effect    = "Allow"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  statement {
    sid    = "CreateBoundedWorkloadRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:PutRolePermissionsBoundary",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
    ]
    resources = [local.workload_role_arns]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.workload_boundary.arn]
    }
  }

  statement {
    sid    = "ChangeWorkloadRoles"
    effect = "Allow"
    actions = [
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:UpdateAssumeRolePolicy",
    ]
    resources = [local.workload_role_arns]
  }

  statement {
    sid    = "ManageWorkloadPolicies"
    effect = "Allow"
    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]
    resources = [local.workload_policy_arn]
  }

  statement {
    sid       = "PassWorkloadRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [local.workload_role_arns]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values = [
        "vpc-flow-logs.amazonaws.com",
        "eks.amazonaws.com",
        "ec2.amazonaws.com",
        "rds.amazonaws.com",
        "monitoring.rds.amazonaws.com",
      ]
    }
  }

  statement {
    sid       = "ServiceLinkedRoles"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "eks.amazonaws.com",
        "eks-nodegroup.amazonaws.com",
        "rds.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
        "autoscaling.amazonaws.com",
      ]
    }
  }

  # EKS needs its own OIDC provider for IRSA (Sprint 3).
  statement {
    sid    = "EksOidcProviders"
    effect = "Allow"
    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
    ]
    resources = ["arn:aws:iam::${local.account_id}:oidc-provider/oidc.eks.${local.region}.amazonaws.com/*"]
  }

  # ---------- Deny: these win over every allow above ----------

  statement {
    sid     = "ProtectCiIdentityAndBoundary"
    effect  = "Deny"
    actions = ["iam:*"]
    resources = [
      aws_iam_role.plan.arn,
      aws_iam_role.apply.arn,
      aws_iam_openid_connect_provider.github.arn,
      aws_iam_policy.workload_boundary.arn,
    ]
  }

  statement {
    sid       = "NoBoundaryRemoval"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }

  statement {
    sid    = "NoLongLivedCredentials"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
      "iam:AttachUserPolicy",
      "iam:PutUserPolicy",
      "iam:AddUserToGroup",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ProtectStateBucket"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketVersioning",
      "s3:PutLifecycleConfiguration",
      "s3:PutEncryptionConfiguration",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketAcl",
    ]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid     = "ProtectStateHistoryAndBootstrap"
    effect  = "Deny"
    actions = ["s3:DeleteObjectVersion", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "${aws_s3_bucket.state.arn}/bootstrap/*",
    ]
  }

  statement {
    sid       = "NoStateVersionDeletion"
    effect    = "Deny"
    actions   = ["s3:DeleteObjectVersion"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }

  statement {
    sid    = "ProtectStateKey"
    effect = "Deny"
    actions = [
      "kms:ScheduleKeyDeletion",
      "kms:DisableKey",
      "kms:DisableKeyRotation",
      "kms:PutKeyPolicy",
    ]
    resources = [aws_kms_key.state.arn]
  }

  statement {
    sid       = "NoAccountChanges"
    effect    = "Deny"
    actions   = ["organizations:*", "account:*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "apply" {
  name   = "zen-infra-apply"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}
