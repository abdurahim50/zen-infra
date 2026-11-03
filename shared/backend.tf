# Shared Remote state for ecr stack. Bucket and KMS key come from backend.hcl
# (git-ignored): terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {
    key          = "shared/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
