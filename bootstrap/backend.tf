# Remote state for the bootstrap stack. The bucket name is not stored here,
# so the account ID stays out of Git. Supply it at init time:
#   terraform init -backend-config=backend.hcl
# (copy backend.hcl.example to backend.hcl and fill in the bucket name)
terraform {
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
