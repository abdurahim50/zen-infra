# -----------------------------------------------------------------------------
# Managed EKS add-ons with pinned versions (ADR-004 decision 8)
#
# bootstrap_self_managed_addons = false (main.tf), so nothing is installed
# by default: these resources are the only source of the cluster add-ons.
#
# Order matters:
# - vpc-cni, kube-proxy and eks-pod-identity-agent are DaemonSets; they are
#   created before the nodes so a node is Ready as soon as it joins.
# - coredns is a Deployment; it needs nodes to run on, so it comes after.
# -----------------------------------------------------------------------------

locals {
  addons_before_nodes = toset(["vpc-cni", "kube-proxy", "eks-pod-identity-agent"])
}

resource "aws_eks_addon" "before_nodes" {
  for_each = local.addons_before_nodes

  cluster_name  = aws_eks_cluster.this.name
  addon_name    = each.key
  addon_version = var.addon_versions[each.key]

  # Terraform owns the configuration; no manual edits survive an apply.
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "coredns" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "coredns"
  addon_version = var.addon_versions["coredns"]

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.default]
}
