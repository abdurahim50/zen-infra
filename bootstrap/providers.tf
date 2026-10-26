provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "zen-pharma"
      Environment = "shared"
      Owner       = "platform-team"
      CostCenter  = "CC-0000"
      ManagedBy   = "terraform"
      Stack       = "bootstrap"
    }
  }
}
