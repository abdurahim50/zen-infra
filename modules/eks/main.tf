# -----------------------------------------------------------------------------
# EKS module: control plane (this file). Nodes and add-ons follow in
# nodes.tf and addons.tf. Design: docs/adr/0004-eks-design.md
#
# - Access entries only; the identity that creates the cluster (the pipeline)
#   does not become a Kubernetes admin. One admin: the SSO admin role.
# - Kubernetes secrets encrypted with a customer managed KMS key.
# - Private endpoint for nodes; public endpoint limited to given /32s.
# - audit and authenticator logs, retention set before the cluster exists.
# -----------------------------------------------------------------------------

# ---------- Secrets encryption key ----------

resource "aws_kms_key" "eks" {
  description             = "${var.name} EKS secrets envelope encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# ---------- Control-plane logs ----------

# EKS writes to this exact name. Creating it first means we set the
# retention; otherwise EKS creates it with "never expire".
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = var.log_retention_days
}

# ---------- Cluster IAM role ----------

data "aws_iam_policy_document" "cluster_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name                 = "${var.name}-eks-cluster"
  assume_role_policy   = data.aws_iam_policy_document.cluster_trust.json
  permissions_boundary = var.permissions_boundary_arn
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------- Cluster ----------

resource "aws_eks_cluster" "this" {
  name     = var.name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  # Add-ons are installed as managed EKS add-ons with pinned versions
  # (addons.tf), not the unmanaged defaults.
  bootstrap_self_managed_addons = false

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  # Nodes use the private endpoint. The public endpoint exists only for the
  # engineer's kubectl and accepts only public_access_cidrs (ADR-004).
  #trivy:ignore:AVD-AWS-0040 Public endpoint is limited to one /32 by public_access_cidrs; see ADR-004 decision 3.
  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.public_access_cidrs
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  enabled_cluster_log_types = ["audit", "authenticator"]

  # At the end of standard support EKS upgrades the control plane instead of
  # charging for extended support. Nodes and add-ons are ours to upgrade.
  upgrade_policy {
    support_type = "STANDARD"
  }

  depends_on = [
    aws_cloudwatch_log_group.cluster,
    aws_iam_role_policy_attachment.cluster,
  ]
}

# ---------- Cluster admin: the SSO admin role only ----------

resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.admin_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.admin.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
