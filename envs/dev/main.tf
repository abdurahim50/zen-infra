# -----------------------------------------------------------------------------
# Dev environment. Network layout per ADR-000; NAT per ADR-001 (one shared
# NAT gateway, created and destroyed with each working session).
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

module "vpc" {
  source = "../../modules/vpc"

  name     = "${var.project}-${var.environment}"
  vpc_cidr = "10.10.0.0/16"
  azs      = ["us-east-1a", "us-east-1b"]

  public_subnet_cidrs   = ["10.10.0.0/24", "10.10.1.0/24"]
  private_subnet_cidrs  = ["10.10.16.0/20", "10.10.32.0/20"]
  database_subnet_cidrs = ["10.10.48.0/24", "10.10.49.0/24"]

  # ... keep your existing lines below (single_nat_gateway etc.) unchanged ...

  # The pipeline may only create IAM roles that carry this boundary
  # (ADR-002), so the flow logs role must have it.
  permissions_boundary_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/zen-pharma-workload-boundary"
}
