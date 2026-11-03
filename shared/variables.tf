# Inputs for the shared stack. Real values for owner and cost_center
# live in git-ignored terraform.tfvars (see terraform.tfvars.example).

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name, used in resource names and tags"
  type        = string
  default     = "zen-pharma"
}

variable "owner" {
  description = "Team or person accountable for these resources"
  type        = string
}

variable "cost_center" {
  description = "Cost center for billing reports"
  type        = string
}
