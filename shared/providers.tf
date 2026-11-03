# AWS provider for the shared stack. Default tags mark every resource as
# shared across environments (Environment and Stack = "shared").
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = "shared"
      Stack       = "shared"
      Owner       = var.owner
      CostCenter  = var.cost_center
      ManagedBy   = "terraform"
    }
  }
}
