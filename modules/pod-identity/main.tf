# -----------------------------------------------------------------------------
# EKS Pod Identity for one service
#
# - The role trusts the EKS Pod Identity service, and only for sessions whose
#   tags show this cluster, this namespace and this service account. Pod
#   Identity adds those session tags itself, so a pod elsewhere cannot use it.
# - Its only permission is IAM database login as one svc_* user on one
#   database instance. The workload boundary caps it at svc_* users even if a
#   wider policy is attached later.
# - The association tells EKS which service account gets this role.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "EksPodIdentityThisServiceAccountOnly"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks-cluster-arn"
      values   = [var.cluster_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-namespace"
      values   = [var.namespace]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-service-account"
      values   = [var.service_account]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = "${var.name}-${var.service}-pod"
  description          = "Pod Identity role for ${var.service} (${var.namespace}/${var.service_account})"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = var.permissions_boundary_arn
}

data "aws_iam_policy_document" "db_login" {
  statement {
    sid       = "DbLoginOwnUserOnly"
    effect    = "Allow"
    actions   = ["rds-db:connect"]
    resources = ["arn:aws:rds-db:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:dbuser:${var.db_resource_id}/${var.db_user}"]
  }
}

resource "aws_iam_role_policy" "db_login" {
  name   = "db-login"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.db_login.json
}

resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.this.arn
}
