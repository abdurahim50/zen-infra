terraform {
  backend "s3" {
    bucket       = "zen-pharma-tfstate-069279771141-us-east-1"
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
