# -----------------------------------------------------------------------------
# Dev environment. Network layout per ADR-000; NAT per ADR-001 (one shared
# NAT gateway); EKS per ADR-004; RDS per ADR-005; Pod Identity per ADR-004.
# Everything here is created and destroyed with each working session.
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

locals {
  # The pipeline may only create IAM roles that carry this boundary (ADR-002).
  permissions_boundary_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/zen-pharma-workload-boundary"
}

module "vpc" {
  source = "../../modules/vpc"

  name     = "${var.project}-${var.environment}"
  vpc_cidr = "10.10.0.0/16"
  azs      = ["us-east-1a", "us-east-1b"]

  public_subnet_cidrs   = ["10.10.0.0/24", "10.10.1.0/24"]
  private_subnet_cidrs  = ["10.10.16.0/20", "10.10.32.0/20"]
  database_subnet_cidrs = ["10.10.48.0/24", "10.10.49.0/24"]

  single_nat_gateway = true

  permissions_boundary_arn = local.permissions_boundary_arn
}

# The SSO admin role is looked up, not written down: its ARN contains the
# account ID and a generated suffix, neither of which belongs in this repo.
data "aws_iam_roles" "sso_admin" {
  name_regex  = "^AWSReservedSSO_AdministratorAccess_"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

module "eks" {
  source = "../../modules/eks"

  name               = "${var.project}-${var.environment}"
  kubernetes_version = "1.37"
  private_subnet_ids = module.vpc.private_subnet_ids

  public_access_cidrs = var.eks_public_access_cidrs
  # one() fails the plan if the lookup finds no role or more than one.
  admin_role_arn = one(data.aws_iam_roles.sso_admin.arns)

  # Default versions for Kubernetes 1.37, looked up on 2026-11-04 with
  # aws eks describe-addon-versions. Upgrade them deliberately, by PR.
  addon_versions = {
    "vpc-cni"                = "v1.22.4-eksbuild.10"
    "kube-proxy"             = "v1.37.0-eksbuild.32"
    "coredns"                = "v1.14.7-eksbuild.22"
    "eks-pod-identity-agent" = "v1.4.1-eksbuild.3"
  }

  permissions_boundary_arn = local.permissions_boundary_arn
}

module "rds" {
  source = "../../modules/rds"

  name                = "${var.project}-${var.environment}"
  engine_version      = "18.6"
  vpc_id              = module.vpc.vpc_id
  database_subnet_ids = module.vpc.database_subnet_ids

  # Only pods and nodes in the EKS cluster can reach PostgreSQL.
  allowed_security_group_id = module.eks.cluster_security_group_id

  # Dev only: the stack is destroyed after each session, so no deletion
  # protection and no final snapshot. Backups stay on (1 day) to prove they work.
  deletion_protection   = false
  skip_final_snapshot   = true
  backup_retention_days = 1
}

# Pod Identity for the inventory service: pods using the inventory/inventory
# service account get a role that can only log in to PostgreSQL as
# svc_inventory (IAM database authentication, ADR-005).
module "pod_identity_inventory" {
  source = "../../modules/pod-identity"

  name            = "${var.project}-${var.environment}"
  service         = "inventory"
  cluster_name    = module.eks.cluster_name
  cluster_arn     = module.eks.cluster_arn
  namespace       = "inventory"
  service_account = "inventory"
  db_resource_id  = module.rds.resource_id
  db_user         = "svc_inventory"

  permissions_boundary_arn = local.permissions_boundary_arn
}
